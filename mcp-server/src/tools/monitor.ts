import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { EnvEntry } from "../registry.js";

function shellQuote(arg: string): string {
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MONITOR_DIR = path.resolve(__dirname, "../../../scripts/monitoring");

// monitor.sh dispatches to these four as sibling files via
// `${SCRIPT_DIR}/traffic-monitor.sh` etc. — SCRIPT_DIR is derived from
// `${BASH_SOURCE[0]}`, which is empty when the script is read from stdin, so
// on a bare `ssh host 'bash -s' < monitor.sh` it resolves to the remote
// shell's cwd instead. That only works if these four already happen to live
// there (e.g. a prior `setup-monitoring.yml` run). Bundling all five and
// writing them into a throwaway remote temp dir removes that assumption —
// the tool works against any registered SSH site, provisioned or not.
const MONITOR_SCRIPTS = [
  "monitor.sh",
  "traffic-monitor.sh",
  "security-monitor.sh",
  "ai-bot-monitor.sh",
  "error-monitor.sh",
] as const;

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

function runRemote(sshHost: string, script: string): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn("ssh", [sshHost, "bash", "-s"]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
    child.stdin.write(script);
    child.stdin.end();
  });
}

// Builds one self-contained bash script: unpack all five monitoring scripts
// (base64, to sidestep quoting the heredoc body) into a `mktemp -d` remote
// temp dir, run monitor.sh there, print its own progress output, then print
// whichever summary markdown file it produced and clean up the temp dir.
// monitor.sh's OUTPUT_DIR is `~/monitoring` when `/srv/www/<domain>` exists on
// the host (a real Trellis deploy) or `./monitoring-reports` (under the temp
// dir) otherwise — checking both paths after the run covers either case
// without duplicating that detection logic here.
function buildRemoteScript(hours: number, domain: string): string {
  const lines = ["set -e", "TMPDIR=$(mktemp -d)", 'trap \'rm -rf "$TMPDIR"\' EXIT', 'cd "$TMPDIR"'];

  for (const name of MONITOR_SCRIPTS) {
    const source = readFileSync(path.join(MONITOR_DIR, name), "utf-8");
    const b64 = Buffer.from(source, "utf-8").toString("base64");
    lines.push(`base64 -d > ${shellQuote(name)} <<'WP_OPS_B64'`, b64, "WP_OPS_B64");
  }

  lines.push(
    "chmod +x ./*.sh",
    `bash ./monitor.sh ${shellQuote(String(hours))} ${shellQuote(domain)}`,
    "echo '--- MONITORING SUMMARY ---'",
    'SUMMARY=$(ls -t "$HOME/monitoring"/monitoring-summary*.md "$PWD/monitoring-reports"/monitoring-summary*.md 2>/dev/null | head -1)',
    'if [ -n "$SUMMARY" ]; then cat "$SUMMARY"; else echo "(no summary report file found)"; fi'
  );

  return lines.join("\n");
}

export async function runMonitor(entry: EnvEntry, domain: string, hours: number): Promise<string> {
  if (!entry.sshHost) {
    throw new Error(
      "monitor requires a site/env entry with sshHost — traffic and security logs only exist on a " +
        "deployed server, not local dev or a Trellis VM."
    );
  }

  const script = buildRemoteScript(hours, domain);
  const result = await runRemote(entry.sshHost, script);

  if (result.code !== 0) {
    throw new Error(`monitor exited ${result.code}${result.stderr ? `: ${result.stderr}` : ""}`);
  }

  return result.stdout.trim() + (result.stderr.trim() ? `\n\nSTDERR:\n${result.stderr.trim()}` : "");
}
