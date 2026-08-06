import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = path.resolve(__dirname, "../../../scripts/monitoring/404-checker.sh");

export type LinkAuditMode = "global" | "spider";

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

function run(args: string[]): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("bash", [SCRIPT_PATH, ...args]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

export interface LinkAuditResult {
  hasBrokenLinks: boolean;
  output: string;
}

// 404-checker.sh's own exit codes: 0 = clean, 1 = broken link(s) found, 2 = usage
// error. Only 2 is a genuine tool failure — 1 is a normal (if unwelcome) result.
export async function runBrokenLinkAudit(
  siteUrl: string,
  mode: LinkAuditMode,
  timeoutSeconds?: number,
  spiderLevel?: number
): Promise<LinkAuditResult> {
  const args = ["--mode", mode];
  if (timeoutSeconds !== undefined) args.push("--timeout", String(timeoutSeconds));
  if (mode === "spider" && spiderLevel !== undefined) args.push("--level", String(spiderLevel));
  args.push(siteUrl);

  const result = await run(args);
  if (result.code === 2) {
    throw new Error(`404-checker.sh usage error: ${result.stderr || result.stdout}`);
  }

  return {
    hasBrokenLinks: result.code === 1,
    output: (result.stdout + (result.stderr ? `\n${result.stderr}` : "")).trim(),
  };
}
