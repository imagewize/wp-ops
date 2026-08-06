import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = path.resolve(__dirname, "../../../scripts/monitoring/remote-ttfb-ua.sh");

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

function run(command: string, args: string[], cwd: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

// remote-ttfb-ua.sh writes its own report to ./audits/remote-ttfb-ua-<timestamp>.txt
// relative to cwd rather than printing it — run it in a throwaway temp dir so the
// report lands somewhere predictable, read it back, then discard the directory.
export async function runRemoteTtfbAudit(sshHost: string, urls: string[]): Promise<string> {
  const tmpDir = await mkdtemp(path.join(os.tmpdir(), "wp-ops-ttfb-"));
  try {
    const result = await run("bash", [SCRIPT_PATH, sshHost, ...urls], tmpDir);
    if (result.code !== 0) {
      throw new Error(`remote-ttfb-ua.sh exited ${result.code}${result.stderr ? `: ${result.stderr}` : ""}`);
    }

    const savedMatch = result.stdout.match(/^Saved: (.+)$/m);
    if (!savedMatch) {
      throw new Error(`remote-ttfb-ua.sh didn't report a saved file. Output:\n${result.stdout}`);
    }

    const report = await readFile(path.join(tmpDir, savedMatch[1]), "utf-8");
    return report.trim();
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }
}
