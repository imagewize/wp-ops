import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z, type ZodTypeAny } from "zod";
import { loadRegistry, resolveSiteEnv } from "./registry.js";
import { runDbBackup } from "./tools/dbBackup.js";
import { runSecurityScan } from "./tools/securityScan.js";
import { isReadOnlyWpCommand, runWpCli } from "./tools/wpCli.js";
import { runRedirectAudit } from "./tools/redirectAudit.js";
import { runSchemaAudit } from "./tools/schemaAudit.js";
import { runUrlAudit, DEFAULT_URL_AUDIT_PATTERNS } from "./tools/urlAudit.js";

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
    "Run a WP-CLI command against a configured site/environment. Pass the command and its arguments as " +
      "separate tokens in `args` (e.g. [\"post\", \"list\", \"--post_type=page\", \"--format=json\"]), not as " +
      "one shell string, and omit the leading \"wp\" and any --path flag (added automatically from the site " +
      "registry). Read-only commands (list/get/exists/status/info/version/search/check-update/doctor/export) " +
      "run immediately; anything else — updates, deletes, installs, search-replace, eval, etc. — requires " +
      "confirm: true, which should only be set after the user has explicitly approved that specific command.",
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
        return { content: [{ type: "text" as const, text: output }] };
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text" as const, text: `Error: ${message}` }], isError: true };
      }
    }
  );

  server.tool(
    "redirect_audit",
    "Run a comprehensive redirect chain audit for one or more URLs. Tests HTTPS pages for 200 status " +
      "with 0 redirects (optimal), verifies HTTP→HTTPS 301 redirects, checks www→non-www canonicalization, " +
      "and validates security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options). Returns color-coded " +
      "status for each test with detailed recommendations. Pass either `urls` or `site`+`env` (to use the site's registered URL).",
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
    },
    async ({ urls, site, env, checkWww, checkSecurityHeaders }) => {
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
        for (const page of result.pages) {
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
    "Audit schema markup (JSON-LD) across key pages of a site. Checks for Organization, LocalBusiness, " +
      "Service, Product, WebSite, BreadcrumbList, Article, FAQPage, HowTo, and Person schema types. " +
      "Returns count of pages with/without schema and which schema types are present. Pass either `siteUrl` or `site`+`env`.",
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
    },
    async ({ siteUrl, site, env, pages }) => {
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
        for (const page of result.pages) {
          const status = page.exists ? (page.hasSchema ? "✅ Has Schema" : "❌ No Schema") : "⚠️  Not Found";
          lines.push(`  ${page.pageName} (${page.url}): ${status}`);
          if (page.hasSchema) {
            const foundTypes = page.schemaTypes.filter((t) => t.found).map((t) => t.type);
            if (foundTypes.length > 0) {
              lines.push(`    Types: ${foundTypes.join(", ")}`);
            }
          }
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
    'Audit wp_posts.post_content for hardcoded dev URLs (e.g. ".test"/".localhost") baked in by ' +
      "get_template_directory_uri() during local content creation — the CRITICAL post-migration check " +
      "CLAUDE.md documents. Reports a hit count per pattern. Pass `replace: {from, to}` to also preview " +
      "a `wp search-replace --all-tables --precise --dry-run`; add confirm: true, only after explicit " +
      "user approval, to apply it for real.",
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

  return server;
}
