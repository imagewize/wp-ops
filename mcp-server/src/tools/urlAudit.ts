import type { EnvEntry } from "../registry.js";
import { runWpCli, runWpCliRaw } from "./wpCli.js";

export const DEFAULT_URL_AUDIT_PATTERNS = [".test", ".localhost"];

export interface UrlAuditFinding {
  pattern: string;
  count: number;
}

export interface UrlReplacement {
  from: string;
  to: string;
  dryRunReport: string;
  applied: boolean;
  applyReport?: string;
}

export interface UrlAuditResult {
  findings: UrlAuditFinding[];
  totalHits: number;
  replacement?: UrlReplacement;
}

function escapeSqlLikeString(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/'/g, "''");
}

function parseCount(stdout: string): number {
  const n = parseInt(stdout.trim(), 10);
  return Number.isNaN(n) ? 0 : n;
}

/**
 * Audit wp_posts.post_content for hardcoded dev URLs (the CRITICAL check CLAUDE.md
 * documents: patterns like ".test" get baked in by get_template_directory_uri() during
 * local content creation and survive a database migration unless search-replaced).
 * With `replace` set, always previews a `wp search-replace --dry-run` first; only applies
 * it for real when `confirm` is also true.
 */
export async function runUrlAudit(
  entry: EnvEntry,
  patterns: string[] = DEFAULT_URL_AUDIT_PATTERNS,
  replace?: { from: string; to: string },
  confirm = false
): Promise<UrlAuditResult> {
  const findings: UrlAuditFinding[] = [];
  for (const pattern of patterns) {
    const sql = `SELECT COUNT(*) FROM wp_posts WHERE post_content LIKE '%${escapeSqlLikeString(pattern)}%';`;
    const result = await runWpCliRaw(entry, ["db", "query", sql, "--skip-column-names"]);
    if (result.code !== 0) {
      throw new Error(
        `wp db query failed for pattern "${pattern}": ${result.stderr.trim() || result.stdout.trim()}`
      );
    }
    findings.push({ pattern, count: parseCount(result.stdout) });
  }

  const totalHits = findings.reduce((sum, f) => sum + f.count, 0);

  let replacement: UrlReplacement | undefined;
  if (replace) {
    const dryRunReport = await runWpCli(entry, [
      "search-replace",
      replace.from,
      replace.to,
      "--all-tables",
      "--precise",
      "--dry-run",
    ]);
    replacement = { from: replace.from, to: replace.to, dryRunReport, applied: false };

    if (confirm) {
      replacement.applyReport = await runWpCli(entry, [
        "search-replace",
        replace.from,
        replace.to,
        "--all-tables",
        "--precise",
      ]);
      replacement.applied = true;
    }
  }

  return { findings, totalHits, replacement };
}
