import { spawn } from "node:child_process";
import type { EnvEntry } from "../registry.js";
import { hasTrellisVm, resolveWpBin, resolvePhpBin } from "../registry.js";

export interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

// Verbs that only read state. Anything else needs explicit confirm: true — this is a
// deliberately conservative allowlist (unknown verbs fall on the "needs confirm" side).
const SAFE_READ_VERBS = new Set([
  "list",
  "get",
  "exists",
  "status",
  "info",
  "version",
  "search",
  "check-update",
  "doctor",
  "export",
  "size",
  "tables",
  "verify-checksums",
  "pluck",
]);

// Commands where the read/write verb is the third token rather than the second, because
// the second token names a sub-resource rather than a verb (e.g. "wp cron event list").
// Kept as an explicit per-command allowlist rather than blindly checking args[2] for every
// command, since args[2] is often an arbitrary caller-supplied value (an option name, a
// post ID, ...) that could coincidentally collide with a SAFE_READ_VERBS entry.
const NESTED_RESOURCE_VERBS: Record<string, Set<string>> = {
  cron: new Set(["event", "schedule"]),
};

export function isReadOnlyWpCommand(args: string[]): boolean {
  const [command, verbOrResource, thirdToken] = args;
  if (verbOrResource !== undefined && SAFE_READ_VERBS.has(verbOrResource)) {
    return true;
  }
  const nestedResources = command !== undefined ? NESTED_RESOURCE_VERBS[command] : undefined;
  if (nestedResources && verbOrResource !== undefined && nestedResources.has(verbOrResource)) {
    return thirdToken !== undefined && SAFE_READ_VERBS.has(thirdToken);
  }
  return false;
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
function shellQuote(arg: string): string {
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
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
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
