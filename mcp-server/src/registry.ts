import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG_PATH = path.resolve(__dirname, "../config/sites.json");

export interface EnvEntry {
  localPath?: string;
  sshHost?: string;
  remotePath?: string;
}

export type SiteRegistry = Record<string, Record<string, EnvEntry>>;

export function loadRegistry(): SiteRegistry {
  const configPath = process.env.WP_OPS_SITES_CONFIG
    ? path.resolve(process.env.WP_OPS_SITES_CONFIG)
    : DEFAULT_CONFIG_PATH;

  if (!existsSync(configPath)) {
    throw new Error(
      `Site registry not found at ${configPath}. Copy config/sites.example.json to ` +
        `config/sites.json and fill in your sites, or set WP_OPS_SITES_CONFIG.`
    );
  }

  return JSON.parse(readFileSync(configPath, "utf-8"));
}

export function resolveSiteEnv(registry: SiteRegistry, site: string, env: string): EnvEntry {
  const siteEntry = registry[site];
  if (!siteEntry) {
    const known = Object.keys(registry).join(", ") || "(none configured)";
    throw new Error(`Unknown site "${site}". Known sites: ${known}`);
  }

  const envEntry = siteEntry[env];
  if (!envEntry) {
    const known = Object.keys(siteEntry).join(", ") || "(none configured)";
    throw new Error(`Unknown env "${env}" for site "${site}". Known envs: ${known}`);
  }

  return envEntry;
}
