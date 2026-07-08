import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG_PATH = path.resolve(__dirname, "../config/sites.json");

export interface EnvEntry {
  localPath?: string;
  sshHost?: string;
  remotePath?: string;
  // Trellis VM (local development): run commands inside the dev VM via
  // `trellis vm shell`, since a Trellis dev box keeps the database in the VM,
  // not on the host — so plain `wp` against localPath can't reach the DB.
  trellisDir?: string; // dir to run `trellis` from (the Trellis project root, holds trellis.cli.yml)
  vmWorkdir?: string; // --workdir inside the VM, e.g. /srv/www/example.com/current
  vmPath?: string; // wp --path relative to vmWorkdir; defaults to "web/wp"
}

export function hasTrellisVm(entry: EnvEntry): entry is EnvEntry & { trellisDir: string; vmWorkdir: string } {
  return Boolean(entry.trellisDir && entry.vmWorkdir);
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
