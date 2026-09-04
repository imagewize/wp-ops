import { spawn } from "node:child_process";
import path from "node:path";
import type { EnvEntry } from "../registry.js";
import { shellQuote } from "./wpCli.js";

export interface SshCommandResult {
  stdout: string;
  stderr: string;
  code: number;
}

// Conservative allowlist of commands that only read state from the remote host.
// Anything else (or any command with shell metacharacters intended as operators)
// needs confirm: true. Each token is shell-quoted before being sent to ssh, so
// even a command like "cat file > other" is treated as literal arguments to cat.
const READ_ONLY_COMMANDS = new Set([
  "cat",
  "date",
  "df",
  "dmesg",
  "du",
  "file",
  "free",
  "grep",
  "head",
  "hostname",
  "id",
  "iostat",
  "journalctl",
  "last",
  "ls",
  "lsb_release",
  "lsblk",
  "mpstat",
  "netstat",
  "ps",
  "pwd",
  "readlink",
  "ss",
  "stat",
  "tail",
  "uname",
  "uptime",
  "vmstat",
  "whoami",
]);

// Split a simple shell-like command string into tokens, respecting single and
// double quotes and backslash escapes. This is intentionally minimal: it lets
// callers pass arguments with spaces ("ls -la /some dir") without invoking a
// local shell or letting ssh re-interpret metacharacters.
function tokenizeCommand(command: string): string[] {
  const tokens: string[] = [];
  let current = "";
  let quote: "'" | '"' | null = null;
  let escaped = false;

  for (const char of command) {
    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }
    if (char === "\\") {
      escaped = true;
      continue;
    }
    if (quote) {
      if (char === quote) {
        quote = null;
      } else {
        current += char;
      }
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (/\s/.test(char)) {
      if (current !== "") {
        tokens.push(current);
        current = "";
      }
      continue;
    }
    current += char;
  }

  if (escaped) {
    current += "\\";
  }
  if (current !== "") {
    tokens.push(current);
  }

  return tokens;
}

export function isReadOnlySshCommand(command: string): boolean {
  const tokens = tokenizeCommand(command);
  const first = tokens[0];
  if (!first) return false;
  const base = path.basename(first);
  return READ_ONLY_COMMANDS.has(base);
}

export function runSshCommand(entry: EnvEntry, command: string): Promise<SshCommandResult> {
  const sshHost = entry.sshHost;
  if (!sshHost) {
    throw new Error("ssh_command requires a site/env entry with sshHost set.");
  }

  const tokens = tokenizeCommand(command);
  if (tokens.length === 0) {
    throw new Error("No command tokens found.");
  }

  const remoteCommand = tokens.map(shellQuote).join(" ");

  return new Promise((resolve, reject) => {
    const child = spawn("ssh", [sshHost, remoteCommand]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

export interface ScpResult {
  stdout: string;
  stderr: string;
  code: number;
  remoteFullPath: string;
}

export function runScpFile(
  entry: EnvEntry,
  direction: "up" | "down",
  localPath: string,
  remotePath: string
): Promise<ScpResult> {
  const sshHost = entry.sshHost;
  const entryRemotePath = entry.remotePath;
  if (!sshHost) {
    throw new Error("scp_file requires a site/env entry with sshHost set.");
  }
  if (!entryRemotePath) {
    throw new Error("scp_file requires a site/env entry with remotePath set.");
  }

  const remoteFullPath = remotePath.startsWith("/")
    ? remotePath
    : `${entryRemotePath}/${remotePath}`;
  const remoteSpec = `${sshHost}:${remoteFullPath}`;

  const source = direction === "down" ? remoteSpec : localPath;
  const dest = direction === "down" ? localPath : remoteSpec;

  return new Promise((resolve, reject) => {
    const child = spawn("scp", [source, dest]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) =>
      resolve({ stdout, stderr, code: code ?? 1, remoteFullPath })
    );
  });
}
