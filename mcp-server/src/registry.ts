import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONFIG_PATH = path.resolve(__dirname, "../config/sites.json");

// Every entry must resolve to exactly one way of reaching the site: a Trellis dev VM
// (trellisDir+vmWorkdir), a remote host (sshHost+remotePath), a local path, or a URL.
// Mirrors the fallback order in tools/wpCli.ts's runWpCli.
const envEntrySchema = z
  .object({
    localPath: z.string().min(1).optional(),
    sshHost: z.string().min(1).optional(),
    remotePath: z.string().min(1).optional(),
    url: z.string().url().optional(),
    // Trellis VM (local development): run commands inside the dev VM via
    // `trellis vm shell`, since a Trellis dev box keeps the database in the VM,
    // not on the host — so plain `wp` against localPath can't reach the DB.
    trellisDir: z.string().min(1).optional(), // dir to run `trellis` from (the Trellis project root, holds trellis.cli.yml)
    vmWorkdir: z.string().min(1).optional(), // --workdir inside the VM, e.g. /srv/www/example.com/current
    vmPath: z.string().min(1).optional(), // wp --path relative to vmWorkdir; defaults to "web/wp"
    // Custom binary paths for shared hosting (cPanel/Plesk) or non-standard setups
    wpBin: z.string().min(1).optional(), // path to wp-cli binary/phar, e.g. "~/wp-cli.phar" or "/usr/local/bin/wp"
    phpBin: z.string().min(1).optional(), // path to PHP binary, e.g. "/opt/plesk/php/8.2/bin/php"
  })
  .refine(
    (entry) =>
      Boolean(
        (entry.trellisDir && entry.vmWorkdir) ||
        (entry.sshHost && entry.remotePath) ||
        entry.localPath ||
        entry.url
      ),
    {
      message: "must set one of: trellisDir+vmWorkdir, sshHost+remotePath, localPath, or url",
    }
  )
  .refine((entry) => !entry.sshHost === !entry.remotePath, {
    message: "sshHost and remotePath must be set together",
  })
  .refine((entry) => !entry.trellisDir === !entry.vmWorkdir, {
    message: "trellisDir and vmWorkdir must be set together",
  });

const siteRegistrySchema = z.record(z.string(), z.record(z.string(), envEntrySchema));

export type EnvEntry = z.infer<typeof envEntrySchema>;

export function hasTrellisVm(entry: EnvEntry): entry is EnvEntry & { trellisDir: string; vmWorkdir: string } {
  return Boolean(entry.trellisDir && entry.vmWorkdir);
}

export function resolveWpBin(entry: EnvEntry): string {
  return entry.wpBin || "wp";
}

export function resolvePhpBin(entry: EnvEntry): string | undefined {
  return entry.phpBin;
}

export function hasUrl(entry: EnvEntry): entry is EnvEntry & { url: string } {
  return Boolean(entry.url);
}

export type SiteRegistry = z.infer<typeof siteRegistrySchema>;

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

  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(configPath, "utf-8"));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    throw new Error(`Site registry at ${configPath} is not valid JSON: ${message}`);
  }

  const result = siteRegistrySchema.safeParse(raw);
  if (!result.success) {
    const issues = result.error.issues
      .map((issue) => `  - ${issue.path.join(".") || "(root)"}: ${issue.message}`)
      .join("\n");
    throw new Error(`Site registry at ${configPath} is invalid:\n${issues}`);
  }

  return result.data;
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
