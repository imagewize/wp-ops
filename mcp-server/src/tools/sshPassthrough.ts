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
  "awk",
  "cat",
  "date",
  "df",
  "dmesg",
  "du",
  "file",
  "find",
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
  "wc",
  "whoami",
]);

// find mutates remote state through primaries like -delete and -exec, so it is
// only read-only when none of those appear in its arguments.
const FIND_MUTATING_PRIMARIES = new Set([
  "-delete",
  "-exec",
  "-execdir",
  "-ok",
  "-okdir",
  "-fprint",
  "-fprint0",
  "-fprintf",
  "-fls",
]);

// awk can execute arbitrary remote commands via system()/| and write files via
// redirection inside its program text, so it is only allowed without any of
// those escape hatches.
const AWK_ESCAPE_PATTERNS = [/system\s*\(/, /\|/, /getline/, /\bclose\s*\(/, />>/, /(^|[^<>])>/];

function isReadOnlySegment(base: string, tokens: string[]): boolean {
  if (!READ_ONLY_COMMANDS.has(base)) return false;
  if (touchesCredentialPath(tokens)) return false;
  if (base === "find") {
    return !tokens
      .slice(1)
      .some((token) => FIND_MUTATING_PRIMARIES.has(token));
  }
  if (base === "awk") {
    return tokens.slice(1).every((token) => {
      // -F (field separator) and -v (variable) are the only options that stay
      // read-only. gawk's -i inplace, -o/--pretty-print, --profile, -f progfile
      // and -l/-E/--include can write files or load code, so any other option
      // needs confirm: true. A bare "-" (stdin) is a plain operand.
      if (/^-[Fv]/.test(token)) return true;
      if (token.startsWith("-") && token !== "-") return false;
      return !AWK_ESCAPE_PATTERNS.some((pattern) => pattern.test(token));
    });
  }
  return true;
}

// Split a simple shell-like command string into tokens, respecting single and
// double quotes and backslash escapes. This is intentionally minimal: it lets
// callers pass arguments with spaces ("ls -la /some dir") without invoking a
// local shell or letting ssh re-interpret metacharacters.
// An unquoted "|" becomes a pipe operator token, so callers can validate and
// rebuild pipelines. A quoted or escaped "|" ("echo 'a|b'") is a plain argument
// like any other, as is an operator glued to other text ("a|b") — only a
// standalone unquoted "|" counts.
export type Token = { value: string; isPipe: boolean };

export function tokenizeCommand(command: string): Token[] {
  const tokens: Token[] = [];
  let current = "";
  let currentQuoted = false;
  let quote: "'" | '"' | null = null;
  let escaped = false;

  const flush = () => {
    // A quoted empty string ("" or '') is a real, empty argument; only drop
    // the buffer when nothing was typed at all.
    if (current === "" && !currentQuoted) return;
    tokens.push({
      value: current,
      isPipe: current === "|" && !currentQuoted,
    });
    current = "";
    currentQuoted = false;
  };

  for (const char of command) {
    if (escaped) {
      current += char;
      currentQuoted = true;
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
      currentQuoted = true;
      quote = char;
      continue;
    }
    if (/\s/.test(char)) {
      flush();
      continue;
    }
    current += char;
  }

  if (escaped) {
    current += "\\";
    currentQuoted = true;
  }
  flush();

  return tokens;
}

// Split a token stream into pipeline segments at unquoted pipe operators.
// Returns null when a pipe is leading, trailing, or doubled — those are shell
// syntax errors or constructs this minimal parser should not approve.
function splitPipeline(tokens: Token[]): Token[][] | null {
  const segments: Token[][] = [[]];
  for (const token of tokens) {
    if (token.isPipe) {
      if (segments[segments.length - 1].length === 0) return null;
      segments.push([]);
      continue;
    }
    segments[segments.length - 1].push(token);
  }
  if (segments[segments.length - 1].length === 0) return null;
  return segments;
}

// Path fragments that indicate a credential-bearing file. Even a command in
// READ_ONLY_COMMANDS (cat, grep, head, tail, ...) needs confirm: true when any
// argument targets one of these — "cat" being harmless in general doesn't mean
// "cat wp-config.php" or "cat ~/.ssh/id_rsa" should be auto-approved, since that
// prints database credentials or an SSH private key straight into the response.
const CREDENTIAL_PATH_PATTERNS: RegExp[] = [
  /wp-config\.php$/i,
  /(^|\/)\.env(\.|$)/,
  /(^|\/)\.ssh(\/|$)/,
  /(^|\/)id_rsa/,
  /(^|\/)id_ed25519/,
  /(^|\/)id_ecdsa/,
  /\.pem$/i,
  /(^|\/)authorized_keys$/,
  /(^|\/)\.netrc$/,
  /(^|\/)\.pgpass$/,
  /(^|\/)\.git-credentials$/,
];

function touchesCredentialPath(tokens: string[]): boolean {
  return tokens
    .slice(1)
    .some((token) => CREDENTIAL_PATH_PATTERNS.some((pattern) => pattern.test(token)));
}

// Read-only when the command is a simple command or a pipeline whose every
// segment is read-only on its own. A pipe is only sent to the remote shell as
// an operator if all segments pass, so "find ... | wc -l" can be auto-approved
// while "find ... -delete" or "awk '...system(...)'" cannot.
export function isReadOnlySshCommand(command: string): boolean {
  const tokens = tokenizeCommand(command);
  if (tokens.length === 0) return false;
  const segments = splitPipeline(tokens);
  if (!segments) return false;
  return segments.every((segment) => {
    const base = path.basename(segment[0].value);
    return isReadOnlySegment(base, segment.map((t) => t.value));
  });
}

// Rebuild the remote command line: every token shell-quoted, except validated
// pipe operators, which are passed through unquoted so the remote shell runs
// them as a pipeline.
export function buildRemoteCommand(tokens: Token[]): string {
  return tokens.map((t) => (t.isPipe ? "|" : shellQuote(t.value))).join(" ");
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

  const remoteCommand = buildRemoteCommand(tokens);

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
