import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { EnvEntry } from "../registry.js";
import { hasTrellisVm, resolvePhpBin } from "../registry.js";
import { stripVmBanner } from "./wpCli.js";

function shellQuote(arg: string): string {
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCANNER_DIR = path.resolve(__dirname, "../../../wp-cli/security");

const SCANNERS = {
  targeted: "scanner-targeted.php",
  general: "scanner-general.php",
} as const;

// Both scanners `require_once dirname(__FILE__) . '/checksum-verify.php'` to
// pull in the checksum-verification module. That resolves fine when php runs
// the file directly off disk (runLocal), but runRemote/runVm stream the
// scanner source over `php /dev/stdin`, where __FILE__ resolves to a
// /proc/<pid>/fd/<pipe> path with no real sibling directory - the require
// fails with "Failed opening required '.../checksum-verify.php'" on every
// remote/VM scan. Inline the module's body in place of that require_once
// line so the streamed script is fully self-contained.
const CHECKSUM_REQUIRE_RE = /^\s*require_once\s+dirname\(__FILE__\)\s*\.\s*'\/checksum-verify\.php';\s*$/m;

function readStandaloneScannerSource(scannerFile: string): string {
  const source = readFileSync(scannerFile, "utf-8");
  if (!CHECKSUM_REQUIRE_RE.test(source)) {
    return source;
  }
  const modulePath = path.join(SCANNER_DIR, "checksum-verify.php");
  const moduleBody = readFileSync(modulePath, "utf-8").replace(/^<\?php\s*/, "");
  return source.replace(CHECKSUM_REQUIRE_RE, moduleBody);
}

export type ScanMode = "targeted" | "general" | "both";

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

function runLocal(scannerFile: string, scanPath: string, phpBin: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(phpBin, [scannerFile, scanPath]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

// Streams the scanner source over SSH stdin so nothing is ever written to disk
// on the remote host (avoids the scp-to-/tmp-then-remember-to-delete step).
function runRemote(sshHost: string, scannerSource: string, remotePath: string, phpBin: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("ssh", [sshHost, `${shellQuote(phpBin)} /dev/stdin ${shellQuote(remotePath)}`]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
    child.stdin.write(scannerSource);
    child.stdin.end();
  });
}

// Streams the scanner source over the Trellis dev VM's stdin to `php /dev/stdin`, same
// no-disk-write rationale as the SSH path. Runs `trellis` from the project dir.
function runVm(
  trellisDir: string,
  scannerSource: string,
  workdir: string,
  scanPath: string,
  phpBin: string
): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("trellis", ["vm", "shell", "--workdir", workdir, "--", phpBin, "/dev/stdin", scanPath], {
      cwd: trellisDir,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout: stripVmBanner(stdout), stderr, code: code ?? 1 }));
    child.stdin.write(scannerSource);
    child.stdin.end();
  });
}

export async function runSecurityScan(entry: EnvEntry, mode: ScanMode): Promise<string> {
  const phpBin = resolvePhpBin(entry) || "php";
  const modesToRun: Array<keyof typeof SCANNERS> = mode === "both" ? ["targeted", "general"] : [mode];
  const sections: string[] = [];

  for (const m of modesToRun) {
    const scannerFile = path.join(SCANNER_DIR, SCANNERS[m]);

    let result: ExecResult;
    // Scanners read files (no DB), so prefer host localPath when present — it's the
    // fastest path and needs no VM/SSH round trip. Fall back to SSH, then the dev VM.
    if (entry.localPath) {
      result = await runLocal(scannerFile, entry.localPath, phpBin);
    } else if (entry.sshHost && entry.remotePath) {
      const scannerSource = readStandaloneScannerSource(scannerFile);
      result = await runRemote(entry.sshHost, scannerSource, entry.remotePath, phpBin);
    } else if (hasTrellisVm(entry)) {
      const scannerSource = readStandaloneScannerSource(scannerFile);
      result = await runVm(entry.trellisDir, scannerSource, entry.vmWorkdir, entry.vmPath ?? "web/wp", phpBin);
    } else {
      throw new Error("Site/env entry has none of: localPath, sshHost+remotePath, trellisDir+vmWorkdir, or url.");
    }

    sections.push(
      `--- ${m.toUpperCase()} SCANNER (exit ${result.code}) ---\n${result.stdout}` +
        (result.stderr ? `\nSTDERR:\n${result.stderr}` : "")
    );
  }

  return sections.join("\n\n");
}
