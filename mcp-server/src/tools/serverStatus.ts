import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { EnvEntry } from "../registry.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = path.resolve(__dirname, "../../../scripts/monitoring/server-monitor.sh");

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

// Unlike monitor.ts's scripts, server-monitor.sh is meant to run on the *calling*
// machine — it takes the target as an argv SSH target and issues its own `ssh
// "$SERVER" ...` call per metric. So this just runs the script locally with the
// registry-resolved sshHost as its argument, no SSH-stdin streaming needed.
function runLocal(sshHost: string, phpFpmPattern?: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const args = [SCRIPT_PATH, sshHost];
    if (phpFpmPattern) args.push(phpFpmPattern);
    const child = spawn("bash", args);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

export async function runServerStatus(entry: EnvEntry, phpFpmPattern?: string): Promise<string> {
  if (!entry.sshHost) {
    throw new Error(
      "server_status requires a site/env entry with sshHost — it measures live resource usage on a " +
        "deployed server, not local dev or a Trellis VM."
    );
  }

  const result = await runLocal(entry.sshHost, phpFpmPattern);
  if (result.code !== 0) {
    throw new Error(`server-monitor.sh exited ${result.code}${result.stderr ? `: ${result.stderr}` : ""}`);
  }
  return result.stdout.trim();
}
