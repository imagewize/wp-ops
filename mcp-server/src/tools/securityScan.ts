import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { EnvEntry } from "../registry.js";
import { hasTrellisVm } from "../registry.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCANNER_DIR = path.resolve(__dirname, "../../../wp-cli/security");

const SCANNERS = {
  targeted: "scanner-targeted.php",
  general: "scanner-general.php",
} as const;

export type ScanMode = "targeted" | "general" | "both";

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

function runLocal(scannerFile: string, scanPath: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("php", [scannerFile, scanPath]);
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
function runRemote(sshHost: string, scannerSource: string, remotePath: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("ssh", [sshHost, "php", "-", remotePath]);
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

// Streams the scanner source over the Trellis dev VM's stdin to `php -`, same
// no-disk-write rationale as the SSH path. Runs `trellis` from the project dir.
function runVm(
  trellisDir: string,
  scannerSource: string,
  workdir: string,
  scanPath: string
): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("trellis", ["vm", "shell", "--workdir", workdir, "--", "php", "-", scanPath], {
      cwd: trellisDir,
    });
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

export async function runSecurityScan(entry: EnvEntry, mode: ScanMode): Promise<string> {
  const modesToRun: Array<keyof typeof SCANNERS> = mode === "both" ? ["targeted", "general"] : [mode];
  const sections: string[] = [];

  for (const m of modesToRun) {
    const scannerFile = path.join(SCANNER_DIR, SCANNERS[m]);

    let result: ExecResult;
    // Scanners read files (no DB), so prefer host localPath when present — it's the
    // fastest path and needs no VM/SSH round trip. Fall back to SSH, then the dev VM.
    if (entry.localPath) {
      result = await runLocal(scannerFile, entry.localPath);
    } else if (entry.sshHost && entry.remotePath) {
      const scannerSource = readFileSync(scannerFile, "utf-8");
      result = await runRemote(entry.sshHost, scannerSource, entry.remotePath);
    } else if (hasTrellisVm(entry)) {
      const scannerSource = readFileSync(scannerFile, "utf-8");
      result = await runVm(entry.trellisDir, scannerSource, entry.vmWorkdir, entry.vmPath ?? "web/wp");
    } else {
      throw new Error("Site/env entry has none of: localPath, sshHost+remotePath, or trellisDir+vmWorkdir.");
    }

    sections.push(
      `--- ${m.toUpperCase()} SCANNER (exit ${result.code}) ---\n${result.stdout}` +
        (result.stderr ? `\nSTDERR:\n${result.stderr}` : "")
    );
  }

  return sections.join("\n\n");
}
