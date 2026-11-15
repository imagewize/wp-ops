// Shared helpers for running plain WP-CLI against a registered site/environment. The
// wp_cli MCP tool that used them was retired (see docs/dev/adr-narrow-wp-ops-to-trellis.md);
// publish_post, verify_post, db_pull and url_audit still run their commands through here.
import { spawn } from "node:child_process";
import type { EnvEntry } from "../registry.js";
import { hasTrellisVm, resolveWpBin, resolvePhpBin } from "../registry.js";

export interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

function runLocal(args: string[], localPath: string, wpBin: string, phpBin?: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const command = phpBin ? [phpBin, wpBin] : [wpBin];
    const child = spawn(command[0], [...command.slice(1), ...args, `--path=${localPath}`]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

// ssh concatenates all trailing argv into one string and hands it to the remote login
// shell, so a caller-supplied token containing shell metacharacters would otherwise
// execute on the remote host. Shell-quote each token ourselves and pass ssh a single
// pre-quoted command string instead of separate argv entries.
export function shellQuote(arg: string): string {
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

function runRemote(sshHost: string, args: string[], remotePath: string, wpBin: string, phpBin?: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const wpCommand = phpBin ? [phpBin, wpBin] : [wpBin];
    const remoteCommand = [...wpCommand, ...args, `--path=${remotePath}`].map(shellQuote).join(" ");
    const child = spawn("ssh", [sshHost, remoteCommand]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

// `trellis vm shell` prints a "Running command => …" banner to stdout before the wrapped
// command's own output. Callers that parse stdout programmatically would otherwise treat
// it as part of the value: dbPull read `option get siteurl` this way, so the banner ended
// up in the search-replace replacement and in `hostOf(devUrl)`, which wrote it into
// wp_blogs.domain and 61 content rows on the demo site.
//
// Only the first line is dropped, and only when it is the banner — WordPress content can
// legitimately begin with "Running command =>" (post revisions on that same demo did,
// from an earlier round of this bug).
// Exported so other tools that spawn `trellis vm shell` directly (rather than going
// through runWpCli/runWpCliRaw) can strip the same banner — dbBackup.ts and
// securityScan.ts both do.
export function stripVmBanner(stdout: string): string {
  return stdout.replace(/^Running command => [^\n]*\n?/, "");
}

const VM_BANNER_PREFIX = "Running command => ";

// Buffer-safe counterpart of stripVmBanner, for callers streaming binary output (e.g.
// dbBackup.ts's `wp db export -`, which isn't guaranteed valid UTF-8 and can't be routed
// through the string version without risking corruption of the SQL dump itself). Only
// the leading bytes are ever decoded, and only to check for the fixed ASCII prefix.
export function stripVmBannerFromBuffer(buf: Buffer): Buffer {
  if (buf.toString("latin1", 0, VM_BANNER_PREFIX.length) !== VM_BANNER_PREFIX) return buf;
  const newlineIndex = buf.indexOf(0x0a);
  if (newlineIndex === -1) return buf;
  return buf.subarray(newlineIndex + 1);
}

// Runs wp inside the Trellis dev VM via `trellis vm shell --workdir <dir> -- wp ...`.
// `trellis` must run from the Trellis project dir (it locates the project from cwd), so
// we set cwd rather than relying on the caller's working directory. Tokens are passed as
// separate argv after `--` (matching `trellis vm shell -- wp post list --path=web/wp`).
function runVm(trellisDir: string, workdir: string, wpPath: string, args: string[], wpBin: string, phpBin?: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const wpCommand = phpBin ? [phpBin, wpBin] : [wpBin];
    const child = spawn(
      "trellis",
      ["vm", "shell", "--workdir", workdir, "--", ...wpCommand, ...args, `--path=${wpPath}`],
      { cwd: trellisDir }
    );
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout: stripVmBanner(stdout), stderr, code: code ?? 1 }));
  });
}

// Raw exit code/stdout/stderr, for callers (e.g. urlAudit's count queries) that need to
// parse stdout programmatically rather than read runWpCli's human-formatted string.
export async function runWpCliRaw(entry: EnvEntry, args: string[]): Promise<ExecResult> {
  const wpBin = resolveWpBin(entry);
  const phpBin = resolvePhpBin(entry);
  // Order matters: a Trellis dev VM keeps the DB in the VM, so prefer the VM over
  // localPath when both are set — plain `wp` against the host can't reach the database.
  if (hasTrellisVm(entry)) {
    return runVm(entry.trellisDir, entry.vmWorkdir, entry.vmPath ?? "web/wp", args, wpBin, phpBin);
  } else if (entry.sshHost && entry.remotePath) {
    return runRemote(entry.sshHost, args, entry.remotePath, wpBin, phpBin);
  } else if (entry.localPath) {
    return runLocal(args, entry.localPath, wpBin, phpBin);
  } else {
    throw new Error("Site/env entry has none of: trellisDir+vmWorkdir, sshHost+remotePath, localPath, or url.");
  }
}

export async function runWpCli(entry: EnvEntry, args: string[]): Promise<string> {
  const result = await runWpCliRaw(entry, args);

  // Nonzero exit isn't necessarily failure (e.g. `plugin is-active` returns 1 for
  // "inactive"), so report it rather than throwing and let the caller interpret it.
  const parts = [`(exit ${result.code})`, result.stdout.trim()];
  if (result.stderr.trim()) parts.push(`STDERR:\n${result.stderr.trim()}`);
  return parts.filter(Boolean).join("\n");
}
