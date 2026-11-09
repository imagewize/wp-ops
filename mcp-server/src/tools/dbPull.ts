import { spawn } from "node:child_process";
import { gunzipSync } from "node:zlib";
import type { EnvEntry } from "../registry.js";
import { hasTrellisVm, resolveWpBin, resolvePhpBin } from "../registry.js";
import { runWpCliRaw } from "./wpCli.js";
import { runDbBackup } from "./dbBackup.js";

function shellQuote(arg: string): string {
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

interface BufferExecResult {
  stdout: Buffer;
  stderr: string;
  code: number;
}

// Buffer-based like dbBackup.ts's exportSql — a SQL dump isn't guaranteed valid
// UTF-8, and here it also needs to go *in* as stdin, not just come out.
function exec(command: string, args: string[], cwd: string | undefined, input: Buffer): Promise<BufferExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, cwd ? { cwd } : {});
    const chunks: Buffer[] = [];
    let stderr = "";
    child.stdout.on("data", (d) => chunks.push(d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout: Buffer.concat(chunks), stderr, code: code ?? 1 }));
    child.stdin.write(input);
    child.stdin.end();
  });
}

// Both URLs from one `wp eval`: one SSH round trip (or one `trellis vm shell`)
// and one WordPress boot per side instead of two.
const READ_URLS_PHP = "echo get_option('siteurl'), PHP_EOL, get_option('home'), PHP_EOL;";

async function readUrls(entry: EnvEntry, env: string): Promise<{ siteurl: string; home: string }> {
  const result = await runWpCliRaw(entry, ["eval", READ_URLS_PHP]);
  if (result.code !== 0) {
    throw new Error(`Reading siteurl/home on "${env}" failed (exit ${result.code}): ${result.stderr}`);
  }
  const [siteurl = "", home = ""] = result.stdout.trim().split(/\r?\n/).map((l) => l.trim());
  return { siteurl: assertSiteUrl(siteurl, env), home: assertSiteUrl(home, env) };
}

// siteurl needs no search-replace pass of its own when it is home plus the same
// suffix on both ends (Bedrock's /wp, or none): the home pass already rewrites
// it. Every --all-tables --precise pass walks the whole database, so this is
// one fewer full scan on a typical Bedrock site.
export function siteurlCoveredByHome(prodUrl: string, prodHome: string, devUrl: string, devHome: string): boolean {
  return (
    prodUrl.startsWith(prodHome) &&
    devUrl.startsWith(devHome) &&
    prodUrl.slice(prodHome.length) === devUrl.slice(devHome.length)
  );
}

function hostOf(url: string): string {
  return url.replace(/^https?:\/\//, "").replace(/\/.*$/, "");
}

export interface DbPullResult {
  devBackupPath: string;
  prodUrl: string;
  devUrl: string;
  prodHome: string;
  devHome: string;
  multisiteFixedUp: boolean;
  searchReplaceOutput: string;
  homeSearchReplaceOutput: string;
  httpHomeSearchReplaceOutput: string;
}

// Ports scripts/backup/db-pull.sh's PULL_COMMAND to composable calls against the
// already-resolved registry entries, instead of building one big remote bash -c
// string: read both URLs, back up dev first, fetch the remote export gzipped,
// verify and unzip it in memory, feed it to `trellis vm shell -- wp db import -`
// (buffer-only, no intermediate file either side), search-replace, optional
// multisite domain fixup, flush cache.
//
// Two URL pairs get read and replaced, not one. `siteurl` and `home` diverge on
// Bedrock (siteurl carries the `/wp` core subdirectory, home doesn't), and content
// — nav menus, post guids, the `home` option itself — is written against `home`,
// never `siteurl`. A search-replace keyed only on `siteurl` silently skips every
// one of those: it matches nothing, exits 0, and the pulled site looks fine until
// someone clicks a menu link and lands back on production. home is always
// replaced; siteurl gets its own pass only when the home pass can't cover it
// (see siteurlCoveredByHome).
//
// Both pairs are also interpolated into UPDATEs on wp_blogs.domain and
// wp_site.domain for multisite. If a wrapper ever prefixes that stdout again, a
// malformed value would be written across the whole database before anyone
// noticed — which is exactly what happened once. Fail before touching data
// instead.
function assertSiteUrl(url: string, env: string): string {
  if (!/^https?:\/\/[^\s/]+(?:\/[^\s]*)?$/.test(url)) {
    throw new Error(
      `Refusing to continue: "siteurl" for "${env}" is not a bare URL. Got: ${JSON.stringify(url)}`
    );
  }
  return url;
}

export async function runDbPull(
  site: string,
  devEntry: EnvEntry,
  fromEntry: EnvEntry,
  fromEnv: string,
  multisite: boolean
): Promise<DbPullResult> {
  if (fromEnv === "development") {
    throw new Error('"development" is not a valid source environment — you can\'t pull development into itself.');
  }
  if (!hasTrellisVm(devEntry)) {
    throw new Error(
      `Site "${site}"'s development entry needs trellisDir+vmWorkdir — db_pull drives the local dev site ` +
        "through `trellis vm shell`."
    );
  }
  if (!fromEntry.sshHost || !fromEntry.remotePath) {
    throw new Error(`Site "${site}"'s "${fromEnv}" entry needs sshHost+remotePath to pull a database from.`);
  }

  const devWpBin = resolveWpBin(devEntry);
  const devPhpBin = resolvePhpBin(devEntry);
  const devPath = devEntry.vmPath ?? "web/wp";
  const devWpCommand = devPhpBin ? [devPhpBin, devWpBin] : [devWpBin];

  const fromWpBin = resolveWpBin(fromEntry);
  const fromPhpBin = resolvePhpBin(fromEntry);
  const fromWpCommand = fromPhpBin ? [fromPhpBin, fromWpBin] : [fromWpBin];

  const { siteurl: prodUrl, home: prodHome } = await readUrls(fromEntry, fromEnv);
  const { siteurl: devUrl, home: devHome } = await readUrls(devEntry, "development");

  // Back up dev's current DB before overwriting it — same safety step db-pull.sh
  // takes, reusing the db_backup tool's own implementation rather than
  // duplicating export logic.
  const backup = await runDbBackup(devEntry, site, "development");

  // Gzip on the remote so only the compressed dump crosses the network (plain
  // SQL is several times larger); pipefail keeps a failed export from passing
  // as a valid gzip stream.
  const exportCmd =
    "set -o pipefail; " +
    [...fromWpCommand, "db", "export", "-", `--path=${fromEntry.remotePath}`].map(shellQuote).join(" ") +
    " | gzip";
  const compressed = await exec("ssh", [fromEntry.sshHost, exportCmd], undefined, Buffer.alloc(0));
  if (compressed.code !== 0) {
    throw new Error(`Remote db export from "${fromEnv}" failed (exit ${compressed.code}): ${compressed.stderr}`);
  }
  let sql: Buffer;
  try {
    sql = gunzipSync(compressed.stdout);
  } catch (err) {
    throw new Error(`Downloaded dump from "${fromEnv}" is not valid gzip — development untouched: ${String(err)}`);
  }
  if (!sql.subarray(-512).toString("latin1").includes("-- Dump completed")) {
    throw new Error(`Downloaded dump from "${fromEnv}" is incomplete (no "Dump completed" footer) — development untouched.`);
  }

  const importResult = await exec(
    "trellis",
    ["vm", "shell", "--workdir", devEntry.vmWorkdir, "--", ...devWpCommand, "db", "import", "-", `--path=${devPath}`],
    devEntry.trellisDir,
    sql
  );
  if (importResult.code !== 0) {
    throw new Error(`Import into development failed (exit ${importResult.code}): ${importResult.stderr}`);
  }

  let searchReplaceOutput = "";
  if (!siteurlCoveredByHome(prodUrl, prodHome, devUrl, devHome)) {
    const searchReplaceArgs = ["search-replace", prodUrl, devUrl, "--all-tables", "--precise", "--report-changed-only"];
    if (multisite) searchReplaceArgs.push(`--url=${prodUrl}`);
    const searchReplace = await runWpCliRaw(devEntry, searchReplaceArgs);
    if (searchReplace.code !== 0) {
      throw new Error(`search-replace failed (exit ${searchReplace.code}): ${searchReplace.stderr}`);
    }
    searchReplaceOutput = (searchReplace.stdout + searchReplace.stderr).trim();
  }

  const homeSearchReplaceArgs = ["search-replace", prodHome, devHome, "--all-tables", "--precise", "--report-changed-only"];
  if (multisite) homeSearchReplaceArgs.push(`--url=${prodUrl}`);
  const homeSearchReplace = await runWpCliRaw(devEntry, homeSearchReplaceArgs);
  if (homeSearchReplace.code !== 0) {
    throw new Error(`search-replace (home URL) failed (exit ${homeSearchReplace.code}): ${homeSearchReplace.stderr}`);
  }
  const homeSearchReplaceOutput = (homeSearchReplace.stdout + homeSearchReplace.stderr).trim();

  // Content written before a site moved to HTTPS still carries http:// links to
  // the production host. Neither pass above matches those, so replace the http://
  // form of prod's home too.
  let httpHomeSearchReplaceOutput = "";
  const prodHomeHttp = prodHome.replace(/^https:\/\//, "http://");
  if (prodHomeHttp !== prodHome) {
    const httpHomeSearchReplaceArgs = [
      "search-replace",
      prodHomeHttp,
      devHome,
      "--all-tables",
      "--precise",
      "--report-changed-only",
    ];
    if (multisite) httpHomeSearchReplaceArgs.push(`--url=${prodUrl}`);
    const httpHomeSearchReplace = await runWpCliRaw(devEntry, httpHomeSearchReplaceArgs);
    if (httpHomeSearchReplace.code !== 0) {
      throw new Error(
        `search-replace (http:// home URL) failed (exit ${httpHomeSearchReplace.code}): ${httpHomeSearchReplace.stderr}`
      );
    }
    httpHomeSearchReplaceOutput = (httpHomeSearchReplace.stdout + httpHomeSearchReplace.stderr).trim();
  }

  let multisiteFixedUp = false;
  if (multisite) {
    // wp_blogs.domain and wp_site.domain hold a bare hostname, so the scheme-prefixed
    // search-replace above never touches them. Both need fixing: wp_blogs for the
    // subsites, wp_site for the network itself — a wp_site.domain left pointing at
    // production disagrees with DOMAIN_CURRENT_SITE and breaks network-admin URLs.
    const query =
      `UPDATE wp_blogs SET domain = REPLACE(domain, '${hostOf(prodUrl)}', '${hostOf(devUrl)}');` +
      `UPDATE wp_site SET domain = REPLACE(domain, '${hostOf(prodUrl)}', '${hostOf(devUrl)}');`;
    const fixup = await runWpCliRaw(devEntry, ["db", "query", query]);
    if (fixup.code !== 0) {
      throw new Error(`Multisite domain fixup failed (exit ${fixup.code}): ${fixup.stderr}`);
    }
    multisiteFixedUp = true;
  }

  await runWpCliRaw(devEntry, ["cache", "flush"]);

  return {
    devBackupPath: backup.filePath,
    prodUrl,
    devUrl,
    prodHome,
    devHome,
    multisiteFixedUp,
    searchReplaceOutput,
    homeSearchReplaceOutput,
    httpHomeSearchReplaceOutput,
  };
}
