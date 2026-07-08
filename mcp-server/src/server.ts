import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { loadRegistry, resolveSiteEnv } from "./registry.js";
import { runDbBackup } from "./tools/dbBackup.js";
import { runSecurityScan } from "./tools/securityScan.js";

export function createServer(): McpServer {
  const server = new McpServer({
    name: "wp-ops",
    version: "0.1.0",
  });

  server.tool(
    "security_scan",
    "Run the wp-ops WordPress security scanners (targeted and/or general malware detection) " +
      "against a configured site/environment. Targeted (~2s) checks common WP-specific threats; " +
      "general (~3s) is a deeper malware sweep. Use 'both' after a suspected compromise.",
    {
      site: z.string().describe('Site key from the wp-ops site registry (config/sites.json), e.g. "example.com"'),
      env: z.string().describe('Environment key for that site, e.g. "development", "staging", "production"'),
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
      site: z.string().describe('Site key from the wp-ops site registry (config/sites.json), e.g. "example.com"'),
      env: z.string().describe('Environment key for that site, e.g. "development", "staging", "production"'),
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

  return server;
}
