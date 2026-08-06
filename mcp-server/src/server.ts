import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z, type ZodTypeAny } from "zod";
import { loadRegistry, resolveSiteEnv } from "./registry.js";
import { runDbBackup } from "./tools/dbBackup.js";
import { runSecurityScan } from "./tools/securityScan.js";
import { isReadOnlyWpCommand, runWpCli, truncateWpCliOutput } from "./tools/wpCli.js";
import { runRedirectAudit } from "./tools/redirectAudit.js";
import { runSchemaAudit } from "./tools/schemaAudit.js";
import { runUrlAudit, DEFAULT_URL_AUDIT_PATTERNS } from "./tools/urlAudit.js";
import { runMonitor } from "./tools/monitor.js";
import { runServerStatus } from "./tools/serverStatus.js";
import { runBrokenLinkAudit } from "./tools/brokenLinkAudit.js";
import { runRemoteTtfbAudit } from "./tools/remoteTtfbAudit.js";
import { checkIpReputation, checkDenyList, type IpCheckResult } from "./tools/ipReputation.js";
import { runAdminUserCreate } from "./tools/adminUserCreate.js";
import { runDbPull } from "./tools/dbPull.js";
import { runFilesPull } from "./tools/filesPull.js";
import {
  formatRunResult,
  formatSearchResults,
  isIntrospectionOnly,
  isReadOnlyCommand,
  loadCatalog,
  resolveCommand,
  runCatalogCommand,
  searchCatalog,
} from "./tools/catalog.js";

// Building z.enum(...) schemas from the registry means a wrong site/env key gets caught
// by the client/model before the call is ever made, instead of costing a full round trip
// (loadRegistry() is cheap, so doing this once at server start is fine). Falls back to
// plain z.string() if the registry can't be loaded yet (e.g. sites.json not created) or
// is empty — the real, more informative error still surfaces from resolveSiteEnv() at
// call time either way. Trade-off: registry edits need a server restart to pick up new
// keys, same as for stdio transport in general.
function buildSiteEnvSchemas(): { site: ZodTypeAny; env: ZodTypeAny } {
  try {
    const registry = loadRegistry();
    const siteKeys = Object.keys(registry);
    if (siteKeys.length === 0) {
      return { site: z.string(), env: z.string() };
    }
    const envKeys = Array.from(new Set(siteKeys.flatMap((site) => Object.keys(registry[site]))));
    return {
      site: z.enum(siteKeys as [string, ...string[]]),
      env: envKeys.length > 0 ? z.enum(envKeys as [string, ...string[]]) : z.string(),
    };
  } catch {
    return { site: z.string(), env: z.string() };
  }
}

export function createServer(): McpServer {
  const server = new McpServer({
    name: "wp-ops",
    version: "0.1.0",
  });

  const { site: siteSchema, env: envSchema } = buildSiteEnvSchemas();

  server.tool(
    "security_scan",
    "Run the wp-ops WordPress security scanners (targeted and/or general malware detection) " +
      "against a configured site/environment. Targeted (~2s) checks common WP-specific threats; " +
      "general (~3s) is a deeper malware sweep. Use 'both' after a suspected compromise.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "development", "staging", "production"'),
      mode: z
        .enum(["targeted", "general", "both"])
        .default("targeted")
        .describe("Which scanner(s) to run"),
    },
    async ({ site, env, mode }) => {
      try {
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        const output = await runSecurityScan(entry, mode);
        return { content: [{ type: "text" as const, text: output }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "db_backup",
    "Export and gzip the WordPress database for a configured site/environment. Local sites are exported " +
      "directly via `wp db export`; remote sites stream the export over SSH stdout, so nothing is ever " +
      "written to disk on the remote host. Saves to a local backups directory " +
      "(default ~/wp-ops-backups/<site>/<env>/, override with WP_OPS_BACKUP_DIR).",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "development", "staging", "production"'),
    },
    async ({ site, env }) => {
      try {
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        const result = await runDbBackup(entry, site, env);
        const sizeKb = (result.sizeBytes / 1024).toFixed(1);
        return {
          content: [{ type: "text" as const, text: `Database backup saved to ${result.filePath} (${sizeKb} KB)` }],
        };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "wp_cli",
    "Run a WP-CLI command against a configured site/environment. Pass args as separate tokens " +
      "(e.g. [\"post\", \"list\", \"--format=json\"]), omitting the leading \"wp\" and any --path. " +
      "Mutating commands need confirm: true, only after explicit user approval.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "development", "staging", "production"'),
      args: z
        .array(z.string())
        .min(1)
        .describe('WP-CLI command as separate argv tokens, e.g. ["post", "list", "--format=json"]. No "wp" prefix, no --path.'),
      confirm: z
        .boolean()
        .default(false)
        .describe("Required (true) for any command outside the read-only allowlist. Only set after explicit user approval."),
    },
    async ({ site, env, args, confirm }) => {
      try {
        if (args.some((a) => a === "--path" || a.startsWith("--path="))) {
          throw new Error("Don't pass --path — it's set automatically from the site registry entry.");
        }
        if (!isReadOnlyWpCommand(args) && !confirm) {
          throw new Error(
            `"wp ${args.join(" ")}" isn't on the read-only allowlist and may change data. ` +
              "Re-run with confirm: true after the user has explicitly approved this command."
          );
        }
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        const output = await runWpCli(entry, args);
        return { content: [{ type: "text" as const, text: truncateWpCliOutput(output) }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "redirect_audit",
    "Audit one or more URLs for redirect-chain issues: HTTPS status/redirect count, HTTP→HTTPS and " +
      "www→non-www canonicalization, and security headers. Pass `urls` or `site`+`env`.",
    {
      urls: z
        .array(z.string().url())
        .min(1)
        .optional()
        .describe('URL(s) to audit, e.g. ["https://example.com", "https://example.com/about/"]'),
      site: siteSchema.optional().describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.optional().describe('Environment key for that site, e.g. "development", "staging", "production"'),
      checkWww: z
        .boolean()
        .default(true)
        .describe('Whether to test www canonicalization (http://www.domain.com → https://domain.com)'),
      checkSecurityHeaders: z
        .boolean()
        .default(true)
        .describe('Whether to check for security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options)'),
      summary: z
        .boolean()
        .default(false)
        .describe("If true, only list pages with at least one failing test — pages that fully pass are omitted."),
    },
    async ({ urls, site, env, checkWww, checkSecurityHeaders, summary }) => {
      try {
        // Resolve URLs from site/env if provided
        let targetUrls = urls;
        if (site && env) {
          const registry = loadRegistry();
          const entry = resolveSiteEnv(registry, site, env);
          if (entry.url) {
            targetUrls = [entry.url];
          } else {
            throw new Error(`Site entry for "${site}"/"${env}" has no URL field. Use the "urls" parameter instead.`);
          }
        }
        
        if (!targetUrls || targetUrls.length === 0) {
          throw new Error("Either provide 'urls' or 'site' + 'env' parameters.");
        }
        
        const result = await runRedirectAudit(targetUrls, checkWww, checkSecurityHeaders);
        const lines: string[] = [
          `Redirect Audit: ${result.overallStatus === "PASS" ? "✅ PASS" : "❌ FAIL"}`,
          `Total Tests: ${result.totalTests} | Passed: ${result.passedTests} | Failed: ${result.failedTests}`,
          "",
          "Results:",
        ];
        // Mirrors the 3 categories runRedirectAudit itself counts toward passedTests/failedTests
        // (security headers are reported but not scored) — a page only "fully passes" if all 3 do.
        let omitted = 0;
        for (const page of result.pages) {
          const pagePassed =
            page.status === 200 && page.redirects === 0 && page.httpRedirect && (!checkWww || page.wwwRedirect);
          if (summary && pagePassed) {
            omitted++;
            continue;
          }
          lines.push(`  ${page.url}:`);
          lines.push(`    HTTPS: ${page.status} (redirects: ${page.redirects})`);
          lines.push(`    HTTP→HTTPS: ${page.httpRedirect ? "✅" : "❌"} ${page.httpRedirectTarget || "N/A"}`);
          if (page.wwwRedirectTarget) {
            lines.push(`    WWW→non-WWW: ${page.wwwRedirect ? "✅" : "❌"} → ${page.wwwRedirectTarget}`);
          }
          lines.push(
            `    Security Headers: HSTS:${page.securityHeaders.hsts ? "✅" : "❌"} CSP:${
              page.securityHeaders.csp ? "✅" : "❌"
            } X-Frame:${
              page.securityHeaders.xFrameOptions ? "✅" : "❌"
            } X-Content-Type:${
              page.securityHeaders.xContentTypeOptions ? "✅" : "❌"
            }`
          );
        }
        if (summary && omitted > 0) {
          lines.push(`  (${omitted} page(s) fully passed and are omitted from this summary)`);
        }
        lines.push("");
        lines.push(
          `Overall Status: ${result.overallStatus === "PASS" ? "✅ ALL TESTS PASSED" : "❌ SOME TESTS FAILED"}`
        );
        if (result.overallStatus === "FAIL") {
          lines.push("Review the output above for redirect chain issues.");
        }
        return { content: [{ type: "text" as const, text: lines.join("\n") }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "schema_audit",
    "Audit JSON-LD schema markup (Organization, LocalBusiness, Product, Article, etc.) across key pages " +
      "of a site. Pass `siteUrl` or `site`+`env`.",
    {
      siteUrl: z.string().optional().describe('Site URL to audit, e.g. "https://example.com"'),
      site: siteSchema.optional().describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.optional().describe('Environment key for that site, e.g. "development", "staging", "production"'),
      pages: z
        .array(z.string())
        .optional()
        .describe(
          'Specific pages to check as "name|url" pairs, e.g. ["Homepage|/", "Contact|/contact/"]. ' +
            'Defaults to common pages (homepage, services, about, contact, portfolio, shop, blog, etc.)'
        ),
      summary: z
        .boolean()
        .default(false)
        .describe("If true, only list pages missing schema or not found — pages that already have schema are omitted."),
    },
    async ({ siteUrl, site, env, pages, summary }) => {
      try {
        // Resolve siteUrl from site/env if provided
        let targetUrl = siteUrl;
        if (site && env) {
          const registry = loadRegistry();
          const entry = resolveSiteEnv(registry, site, env);
          if (entry.url) {
            targetUrl = entry.url;
          } else {
            throw new Error(`Site entry for "${site}"/"${env}" has no URL field. Use the "siteUrl" parameter instead.`);
          }
        }
        
        if (!targetUrl) {
          throw new Error("Either provide 'siteUrl' or 'site' + 'env' parameters.");
        }
        
        const result = await runSchemaAudit(targetUrl, pages);
        const lines: string[] = [
          `Schema Audit: ${result.pagesWithSchema}/${result.totalPages} pages have schema markup`,
          "",
          "Schema Types Found:",
        ];
        for (const [type, count] of Object.entries(result.schemaTypesFound)) {
          if (count > 0) {
            lines.push(`  ${type}: ${count} page(s)`);
          }
        }
        lines.push("");
        lines.push("Page Details:");
        let omitted = 0;
        for (const page of result.pages) {
          const status = page.exists ? (page.hasSchema ? "✅ Has Schema" : "❌ No Schema") : "⚠️  Not Found";
          if (summary && page.exists && page.hasSchema) {
            omitted++;
            continue;
          }
          lines.push(`  ${page.pageName} (${page.url}): ${status}`);
          if (page.hasSchema) {
            const foundTypes = page.schemaTypes.filter((t) => t.found).map((t) => t.type);
            if (foundTypes.length > 0) {
              lines.push(`    Types: ${foundTypes.join(", ")}`);
            }
          }
        }
        if (summary && omitted > 0) {
          lines.push(`  (${omitted} page(s) already have schema and are omitted from this summary)`);
        }
        lines.push("");
        if (result.pagesWithoutSchema > 0) {
          lines.push(
            `Recommendation: Add schema markup to ${result.pagesWithoutSchema} pages without it.`
          );
        } else if (result.totalPages > 0) {
          lines.push("✅ All pages have schema markup!");
        }
        return { content: [{ type: "text" as const, text: lines.join("\n") }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "url_audit",
    'Audit wp_posts.post_content for hardcoded dev URLs (e.g. ".test"/".localhost") from local content ' +
      "creation. Pass `replace: {from, to}` to preview a search-replace; confirm: true (after explicit " +
      "user approval) to apply it.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "development", "staging", "production"'),
      patterns: z
        .array(z.string())
        .min(1)
        .default(DEFAULT_URL_AUDIT_PATTERNS)
        .describe('Substrings to search for in wp_posts.post_content, e.g. [".test", ".localhost"]'),
      replace: z
        .object({
          from: z.string().min(1).describe('URL to replace, e.g. "http://example.test"'),
          to: z.string().min(1).describe('Replacement URL, e.g. "https://example.com"'),
        })
        .optional()
        .describe(
          "If set, runs `wp search-replace <from> <to> --all-tables --precise` as a dry-run preview " +
            "(and for real if confirm: true)."
        ),
      confirm: z
        .boolean()
        .default(false)
        .describe(
          "Required (true) to actually apply `replace`, not just preview it. Only set after explicit user approval."
        ),
    },
    async ({ site, env, patterns, replace, confirm }) => {
      try {
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        const result = await runUrlAudit(entry, patterns, replace, confirm);

        const lines: string[] = [`URL Audit for ${site}/${env}:`, ""];
        for (const f of result.findings) {
          lines.push(`  "${f.pattern}": ${f.count} hit(s) in wp_posts.post_content`);
        }
        lines.push("");
        lines.push(
          result.totalHits === 0 ? "✅ No dev URLs found." : `⚠️  ${result.totalHits} total hit(s) found.`
        );

        if (result.replacement) {
          lines.push("");
          lines.push(`Search-replace preview (${result.replacement.from} → ${result.replacement.to}), dry-run:`);
          lines.push(result.replacement.dryRunReport);
          if (result.replacement.applied) {
            lines.push("");
            lines.push("Applied for real:");
            lines.push(result.replacement.applyReport ?? "");
          } else {
            lines.push("");
            lines.push("Not applied — re-run with confirm: true after explicit user approval to apply it.");
          }
        }

        return { content: [{ type: "text" as const, text: lines.join("\n") }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "monitor",
    "Run combined traffic, security, AI-crawler, and error-log monitoring against a site's Nginx logs " +
      "and return the generated markdown summary. Requires a site/env with an SSH entry — logs only " +
      "exist on a deployed server, not local dev or a Trellis VM. Self-contained: bundles the monitoring " +
      "scripts into a throwaway remote temp dir for this run, so it works whether or not the site has " +
      "`setup-monitoring.yml` already provisioned.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "staging", "production"'),
      hours: z.number().int().positive().default(24).describe("How many hours of logs to analyze"),
      domain: z
        .string()
        .optional()
        .describe(
          'Domain used to locate logs at /srv/www/<domain>/logs/access.log. Defaults to the "site" key, ' +
            "which is the domain for every currently registered site."
        ),
    },
    async ({ site, env, hours, domain }) => {
      try {
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        const output = await runMonitor(entry, domain ?? site, hours);
        return { content: [{ type: "text" as const, text: output }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "server_status",
    "Live CPU, memory, disk, top processes, PHP-FPM, MySQL/MariaDB, Nginx, and recent OOM-killer snapshot " +
      "of a server over SSH. Requires a site/env with an sshHost entry — this reads live process state, " +
      "not local dev or a Trellis VM.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "staging", "production"'),
      phpFpmPattern: z
        .string()
        .optional()
        .describe('Pattern to match PHP-FPM pool processes, e.g. "php-fpm: pool wordpress". Defaults to matching any pool.'),
    },
    async ({ site, env, phpFpmPattern }) => {
      try {
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        const output = await runServerStatus(entry, phpFpmPattern);
        return { content: [{ type: "text" as const, text: output }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "broken_link_audit",
    "Check a site's internal links for broken (4xx/5xx) responses. `global` mode (default) checks all " +
      "links found on the homepage (~30s); `spider` recursively crawls to a set depth (~5-10 min). Pass " +
      "`siteUrl` or `site`+`env`.",
    {
      siteUrl: z.string().url().optional().describe('Site URL to check, e.g. "https://example.com"'),
      site: siteSchema.optional().describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.optional().describe('Environment key for that site, e.g. "staging", "production"'),
      mode: z
        .enum(["global", "spider"])
        .default("global")
        .describe("global checks homepage links only (fast); spider recursively crawls the whole site (slow)"),
      timeoutSeconds: z.number().int().positive().optional().describe("curl max-time per request, in seconds"),
      spiderLevel: z.number().int().positive().optional().describe("Spider crawl depth, only used in spider mode"),
    },
    async ({ siteUrl, site, env, mode, timeoutSeconds, spiderLevel }) => {
      try {
        let targetUrl = siteUrl;
        if (site && env) {
          const registry = loadRegistry();
          const entry = resolveSiteEnv(registry, site, env);
          if (entry.url) {
            targetUrl = entry.url;
          } else {
            throw new Error(`Site entry for "${site}"/"${env}" has no URL field. Use the "siteUrl" parameter instead.`);
          }
        }
        if (!targetUrl) {
          throw new Error("Either provide 'siteUrl' or 'site' + 'env' parameters.");
        }

        const result = await runBrokenLinkAudit(targetUrl, mode, timeoutSeconds, spiderLevel);
        const text = result.hasBrokenLinks
          ? `❌ Broken link(s) found:\n\n${result.output}`
          : `✅ No broken links found.\n\n${result.output}`;
        return { content: [{ type: "text" as const, text }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "remote_ttfb_audit",
    "Measure TTFB (time to first byte) from the server itself — via SSH, so DNS/network distance from " +
      "your machine doesn't skew it — across multiple user agents (default, Googlebot, AhrefsBot, " +
      "Screaming Frog). Useful after a WAF or caching change to check bots aren't treated differently " +
      "from regular visitors. Requires a site/env with an sshHost entry.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "staging", "production"'),
      urls: z.array(z.string().url()).min(1).describe('URL(s) to test, e.g. ["https://example.com/", "https://example.com/blog/"]'),
    },
    async ({ site, env, urls }) => {
      try {
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        if (!entry.sshHost) {
          throw new Error(`Site entry for "${site}"/"${env}" has no sshHost — remote_ttfb_audit runs curl on the server itself over SSH.`);
        }
        const output = await runRemoteTtfbAudit(entry.sshHost, urls);
        return { content: [{ type: "text" as const, text: output }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  function formatIpResult(r: IpCheckResult): string {
    if (r.error) return `  ${r.ip}: ERROR — ${r.error}`;
    const note = r.score === 0 ? " ⚠ CONSIDER REMOVING (score 0)" : r.score !== undefined && r.score <= 10 ? " ⚠ score dropped low" : "";
    return `  ${r.ip}: score=${r.score} reports=${r.reports} lastSeen=${r.lastSeen ?? "never"} country=${r.country ?? "?"} isp=${r.isp ?? "?"}${r.tor ? " TOR" : ""}${note}`;
  }

  server.tool(
    "ip_reputation_check",
    "Check IP addresses against AbuseIPDB threat intelligence (score, report count, ISP, Tor). Pass " +
      "`ips` directly, or `trellisDir` to audit every individual IP already blocked in that Trellis " +
      "project's deny-ips.conf.j2 (useful for spotting stale blocks safe to remove). Requires an " +
      "AbuseIPDB API key (WP_OPS_ABUSEIPDB_KEY env var, or trellis/security/.env).",
    {
      ips: z.array(z.string()).min(1).optional().describe('IP addresses to check, e.g. ["1.2.3.4", "5.6.7.8"]'),
      trellisDir: z
        .string()
        .optional()
        .describe("Path to a Trellis project, to audit its nginx-includes/all/deny-ips.conf.j2 instead of arbitrary IPs"),
    },
    async ({ ips, trellisDir }) => {
      try {
        if (!ips && !trellisDir) {
          throw new Error("Provide either 'ips' or 'trellisDir'.");
        }
        if (ips && trellisDir) {
          throw new Error("Provide only one of 'ips' or 'trellisDir', not both.");
        }

        if (trellisDir) {
          const result = await checkDenyList(trellisDir);
          const lines = [
            `${result.ips.length} IP(s) checked, ${result.subnetsSkipped} subnet(s) skipped`,
            "",
            ...result.ips.map(formatIpResult),
          ];
          return { content: [{ type: "text" as const, text: lines.join("\n") }] };
        }

        const results = await checkIpReputation(ips!);
        return { content: [{ type: "text" as const, text: results.map(formatIpResult).join("\n") }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "admin_user_create",
    "Create a temporary WordPress administrator via WP-CLI — for lockout recovery (lost admin password, " +
      "a broken login plugin, an ownership handover with no working account). The password is generated " +
      "and returned once, never stored. Requires confirm: true, only after explicit user approval.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      env: envSchema.describe('Environment key for that site, e.g. "staging", "production"'),
      username: z.string().min(1).describe("Username for the new administrator"),
      email: z.string().email().describe("Email address for the new administrator"),
      role: z.string().default("administrator").describe("Role to assign"),
      password: z
        .string()
        .optional()
        .describe("Password to set. Defaults to a generated random password, returned once in the response."),
      confirm: z
        .boolean()
        .default(false)
        .describe("Required (true) — creates a privileged account. Only set after explicit user approval."),
    },
    async ({ site, env, username, email, role, password, confirm }) => {
      try {
        if (!confirm) {
          throw new Error(
            "Creating a WordPress admin account needs confirm: true. Re-run with confirm: true only " +
              "after the user has explicitly approved this."
          );
        }
        const registry = loadRegistry();
        const entry = resolveSiteEnv(registry, site, env);
        const result = await runAdminUserCreate(entry, username, email, role, password);

        const lines = [`User created: ${result.username} <${result.email}> (role: ${result.role})`];
        if (result.generatedPassword) {
          lines.push("", `Password: ${result.generatedPassword}`, "", "Shown once — copy it now.");
        }
        lines.push(
          "",
          "Delete this user when no longer needed, via the wp_cli tool: " +
            `{ site: "${site}", env: "${env}", args: ["user", "delete", "${username}", "--yes", "--reassign=1"], confirm: true }`
        );
        return { content: [{ type: "text" as const, text: lines.join("\n") }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "db_pull",
    "Pull a site's database from a remote environment into local development, with URL search-replace. " +
      "Backs up the current development database first. Requires the site's \"development\" entry to have " +
      "trellisDir+vmWorkdir (drives the dev site through `trellis vm shell`) and the source env to have " +
      "sshHost+remotePath. Requires confirm: true — overwrites the local development database.",
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      fromEnv: envSchema.describe('Environment to pull from, e.g. "production", "staging" — not "development"'),
      multisite: z
        .boolean()
        .default(false)
        .describe("Also fix wp_blogs domains and scope search-replace with --url, for multisite networks"),
      confirm: z
        .boolean()
        .default(false)
        .describe("Required (true) — overwrites the local development database. Only set after explicit user approval."),
    },
    async ({ site, fromEnv, multisite, confirm }) => {
      try {
        if (!confirm) {
          throw new Error(
            "db_pull overwrites the local development database and needs confirm: true. Re-run with " +
              "confirm: true only after the user has explicitly approved this."
          );
        }
        const registry = loadRegistry();
        const devEntry = resolveSiteEnv(registry, site, "development");
        const fromEntry = resolveSiteEnv(registry, site, fromEnv);
        const result = await runDbPull(site, devEntry, fromEntry, fromEnv, multisite);

        const lines = [
          `Pulled ${site}/${fromEnv} database into development.`,
          `  ${fromEnv} URL: ${result.prodUrl}`,
          `  development URL: ${result.devUrl}`,
          `  Development backed up to: ${result.devBackupPath}`,
        ];
        if (result.multisiteFixedUp) lines.push("  Multisite domain fixup applied.");
        lines.push("", "search-replace output:", result.searchReplaceOutput);

        return { content: [{ type: "text" as const, text: lines.join("\n") }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "files_pull",
    "Sync a site's uploads directory from a remote environment into local development via rsync. " +
      "Additive by default (local-only files are kept); `delete: true` mirrors the remote exactly, " +
      "deleting local uploads the remote no longer has — that needs confirm: true. Requires the site's " +
      '"development" entry to have localPath, and the source env to have sshHost.',
    {
      site: siteSchema.describe('Site key from the wp-ops site registry (config/sites.json)'),
      fromEnv: envSchema.describe('Environment to pull from, e.g. "production", "staging" — not "development"'),
      delete: z
        .boolean()
        .default(false)
        .describe("Mirror the remote exactly, deleting local-only uploads. Destructive locally — needs confirm: true."),
      confirm: z
        .boolean()
        .default(false)
        .describe("Required (true) only when delete: true. Only set after explicit user approval."),
    },
    async ({ site, fromEnv, delete: del, confirm }) => {
      try {
        if (fromEnv === "development") {
          throw new Error('"development" is not a valid source environment — you can\'t pull development into itself.');
        }
        if (del && !confirm) {
          throw new Error(
            "delete: true removes local-only uploads and needs confirm: true. Re-run with confirm: true " +
              "only after the user has explicitly approved this."
          );
        }
        const registry = loadRegistry();
        const devEntry = resolveSiteEnv(registry, site, "development");
        const fromEntry = resolveSiteEnv(registry, site, fromEnv);
        const result = await runFilesPull(site, devEntry, fromEntry, del);

        const lines = [
          `Synced ${site}/${fromEnv} uploads into development.`,
          `  Remote: ${result.remoteUploadsDir}`,
          `  Local:  ${result.localUploadsDir}`,
          `  Mode:   ${result.deleted ? "mirrored — local-only files deleted" : "additive — local-only files kept"}`,
          "",
          result.rsyncOutput,
        ];
        return { content: [{ type: "text" as const, text: lines.join("\n") }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  // The catalog bridge. Every other tool above is a hand-written wrapper around
  // one wp-ops capability, which means an MCP client sees only the handful
  // someone got round to porting — and correctly answers "I can't do that" for
  // the ~74 commands in the repo that have no wrapper, even when the exact
  // script exists. These two expose the whole catalog instead of growing that
  // list one tool at a time.
  server.tool(
    "command_search",
    "Search the full wp-ops command catalog (~74 commands: backups, monitoring, SEO and security " +
      "audits, image processing, releases, GitHub repo traffic, and more) by name or description. " +
      "Use this BEFORE concluding that wp-ops cannot do something — most capabilities live here as " +
      "scripts rather than as dedicated MCP tools. A single match returns full usage: arguments, " +
      "flags, and examples. Run what you find with command_run.",
    {
      query: z
        .string()
        .describe('Term matched against command names and descriptions, e.g. "traffic", "backup", "webp". Use "" to list everything.'),
      platform: z
        .enum(["trellis", "wordpress", "any"])
        .optional()
        .describe('Only commands for this stack: "trellis" needs a Trellis project, "wordpress" any WP install, "any" needs neither.'),
      category: z
        .string()
        .optional()
        .describe('Only commands in this category, e.g. "monitoring", "backup", "seo", "security", "images", "git".'),
    },
    async ({ query, platform, category }) => {
      try {
        const entries = loadCatalog();
        const matches = searchCatalog(entries, query, { platform, category });
        return { content: [{ type: "text" as const, text: formatSearchResults(matches, query) }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "command_run",
    "Run a wp-ops catalog command found via command_search, passing args as separate tokens. " +
      'Pass ["--help"] to read a command\'s full usage, or ["--where"] to get its file path — both are ' +
      "free of side effects and never need confirmation. Read-only commands (audits, scans, log " +
      "analysis) run directly; anything that writes, deploys, syncs, or deletes needs confirm: true, " +
      "which you may only set after the user has explicitly approved that specific command.",
    {
      command: z
        .string()
        .describe('Command key from command_search, e.g. "scripts/git/gh-traffic". A unique basename like "gh-traffic" also resolves.'),
      args: z
        .array(z.string())
        .default([])
        .describe('Arguments as separate argv tokens, e.g. ["--all", "imagewize/nynaeve"]. Omit the "wp-ops" prefix and the command name.'),
      confirm: z
        .boolean()
        .default(false)
        .describe("Required (true) for any command that isn't read-only. Only set after explicit user approval of this exact command."),
      timeoutSeconds: z
        .number()
        .int()
        .positive()
        .max(1800)
        .default(120)
        .describe("Kill the command after this many seconds. Raise it for scanners and full-site backups."),
    },
    async ({ command, args, confirm, timeoutSeconds }) => {
      try {
        const entries = loadCatalog();
        const entry = resolveCommand(entries, command);

        if (!isIntrospectionOnly(args) && !isReadOnlyCommand(entry.key) && !confirm) {
          throw new Error(
            `"${entry.key}" is not on the read-only allowlist and may change data, files, or remote state. ` +
              `Show the user what it does (run it with ["--help"], which needs no confirmation), get their ` +
              `explicit approval, then re-run with confirm: true.`
          );
        }

        const timeoutMs = timeoutSeconds * 1000;
        const result = await runCatalogCommand(entry.key, args, timeoutMs);
        const text = formatRunResult(entry.key, result, timeoutMs);
        // A nonzero exit is the command's own verdict (a scanner finding
        // something, an audit failing), not an MCP-level failure — surface the
        // output rather than flagging the call itself as broken.
        return { content: [{ type: "text" as const, text }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  return server;
}
