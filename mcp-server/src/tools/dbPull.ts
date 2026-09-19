import { spawn } from "node:child_process";
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
// string: read both URLs, back up dev first, stream the remote export straight
// into `trellis vm shell -- wp db import -` (buffer-only, no intermediate file
// either side), search-replace, optional multisite domain fixup, flush cache.
//
// Two URL pairs get read and replaced, not one. `siteurl` and `home` diverge on
// Bedrock (siteurl carries the `/wp` core subdirectory, home doesn't), and content
// — nav menus, post guids, the `home` option itself — is written against `home`,
// never `siteurl`. A search-replace keyed only on `siteurl` silently skips every
// one of those: it matches nothing, exits 0, and the pulled site looks fine until
// someone clicks a menu link and lands back on production. Both pairs are searched
// unless they're identical (non-Bedrock installs, where siteurl === home already
// covers it).
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

  const prodUrl = assertSiteUrl((await runWpCliRaw(fromEntry, ["option", "get", "siteurl"])).stdout.trim(), fromEnv);
  const devUrl = assertSiteUrl((await runWpCliRaw(devEntry, ["option", "get", "siteurl"])).stdout.trim(), "development");
  const prodHome = assertSiteUrl((await runWpCliRaw(fromEntry, ["option", "get", "home"])).stdout.trim(), fromEnv);
  const devHome = assertSiteUrl((await runWpCliRaw(devEntry, ["option", "get", "home"])).stdout.trim(), "development");

  // Back up dev's current DB before overwriting it — same safety step db-pull.sh
  // takes, reusing the db_backup tool's own implementation rather than
  // duplicating export logic.
  const backup = await runDbBackup(devEntry, site, "development");

  const exportCmd = [...fromWpCommand, "db", "export", "-", `--path=${fromEntry.remotePath}`].map(shellQuote).join(" ");
  const dump = await exec("ssh", [fromEntry.sshHost, exportCmd], undefined, Buffer.alloc(0));
  if (dump.code !== 0) {
    throw new Error(`Remote db export from "${fromEnv}" failed (exit ${dump.code}): ${dump.stderr}`);
  }

  const importResult = await exec(
    "trellis",
    ["vm", "shell", "--workdir", devEntry.vmWorkdir, "--", ...devWpCommand, "db", "import", "-", `--path=${devPath}`],
    devEntry.trellisDir,
    dump.stdout
  );
  if (importResult.code !== 0) {
    throw new Error(`Import into development failed (exit ${importResult.code}): ${importResult.stderr}`);
  }

  const searchReplaceArgs = ["search-replace", prodUrl, devUrl, "--all-tables", "--precise"];
  if (multisite) searchReplaceArgs.push(`--url=${prodUrl}`);
  const searchReplace = await runWpCliRaw(devEntry, searchReplaceArgs);
  if (searchReplace.code !== 0) {
    throw new Error(`search-replace failed (exit ${searchReplace.code}): ${searchReplace.stderr}`);
  }

  // siteurl and home only differ on Bedrock (siteurl has /wp); running this pass
  // unconditionally on a non-Bedrock install would just be a harmless no-op, but
  // skipping it when they're equal saves a redundant full-table scan.
  let homeSearchReplaceOutput = "";
  if (prodHome !== prodUrl || devHome !== devUrl) {
    const homeSearchReplaceArgs = ["search-replace", prodHome, devHome, "--all-tables", "--precise"];
    if (multisite) homeSearchReplaceArgs.push(`--url=${prodUrl}`);
    const homeSearchReplace = await runWpCliRaw(devEntry, homeSearchReplaceArgs);
    if (homeSearchReplace.code !== 0) {
      throw new Error(`search-replace (home URL) failed (exit ${homeSearchReplace.code}): ${homeSearchReplace.stderr}`);
    }
    homeSearchReplaceOutput = (homeSearchReplace.stdout + homeSearchReplace.stderr).trim();
  }

  // Content written before a site moved to HTTPS still carries http:// links to
  // the production host. Neither pass above matches those, so replace the http://
  // form of prod's home too.
  let httpHomeSearchReplaceOutput = "";
  const prodHomeHttp = prodHome.replace(/^https:\/\//, "http://");
  if (prodHomeHttp !== prodHome) {
    const httpHomeSearchReplaceArgs = ["search-replace", prodHomeHttp, devHome, "--all-tables", "--precise"];
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
    searchReplaceOutput: (searchReplace.stdout + searchReplace.stderr).trim(),
    homeSearchReplaceOutput,
    httpHomeSearchReplaceOutput,
  };
}
