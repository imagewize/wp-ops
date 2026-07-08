import { spawn } from "node:child_process";
import type { EnvEntry } from "../registry.js";
import { hasTrellisVm } from "../registry.js";

interface ExecResult {
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
]);

export function isReadOnlyWpCommand(args: string[]): boolean {
  const verb = args[1];
  return verb !== undefined && SAFE_READ_VERBS.has(verb);
}

function runLocal(args: string[], localPath: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("wp", [...args, `--path=${localPath}`]);
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

function runRemote(sshHost: string, args: string[], remotePath: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const remoteCommand = ["wp", ...args, `--path=${remotePath}`].map(shellQuote).join(" ");
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
function runVm(trellisDir: string, workdir: string, wpPath: string, args: string[]): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      "trellis",
      ["vm", "shell", "--workdir", workdir, "--", "wp", ...args, `--path=${wpPath}`],
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

export async function runWpCli(entry: EnvEntry, args: string[]): Promise<string> {
  let result: ExecResult;
  // Order matters: a Trellis dev VM keeps the DB in the VM, so prefer the VM over
  // localPath when both are set — plain `wp` against the host can't reach the database.
  if (hasTrellisVm(entry)) {
    result = await runVm(entry.trellisDir, entry.vmWorkdir, entry.vmPath ?? "web/wp", args);
  } else if (entry.sshHost && entry.remotePath) {
    result = await runRemote(entry.sshHost, args, entry.remotePath);
  } else if (entry.localPath) {
    result = await runLocal(args, entry.localPath);
  } else {
    throw new Error("Site/env entry has none of: trellisDir+vmWorkdir, sshHost+remotePath, or localPath.");
  }

  // Nonzero exit isn't necessarily failure (e.g. `plugin is-active` returns 1 for
  // "inactive"), so report it rather than throwing and let the caller interpret it.
  const parts = [`(exit ${result.code})`, result.stdout.trim()];
  if (result.stderr.trim()) parts.push(`STDERR:\n${result.stderr.trim()}`);
  return parts.filter(Boolean).join("\n");
}
