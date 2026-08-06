import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import type { EnvEntry } from "../registry.js";

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
}

function exec(command: string, args: string[]): Promise<ExecResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => resolve({ stdout, stderr, code: code ?? 1 }));
  });
}

export interface FilesPullResult {
  remoteUploadsDir: string;
  localUploadsDir: string;
  deleted: boolean;
  rsyncOutput: string;
}

// Mirrors trellis/backup/files-pull.yml: rsync a Trellis site's shared uploads
// directory (a fixed path outside the deploy-versioned `current/`, so it isn't
// derived from remotePath) into development's Bedrock uploads dir on the host.
export async function runFilesPull(site: string, devEntry: EnvEntry, fromEntry: EnvEntry, del: boolean): Promise<FilesPullResult> {
  if (!devEntry.localPath) {
    throw new Error(
      `Site "${site}"'s development entry needs localPath set — files_pull rsyncs straight to the host ` +
        "filesystem (a Trellis dev VM mounts the project directory into the host, so no VM shell is needed)."
    );
  }
  if (!fromEntry.sshHost) {
    throw new Error(`Site "${site}"'s source entry needs sshHost to pull uploads from.`);
  }

  const remoteUploadsDir = `/srv/www/${site}/shared/uploads/`;

  // devEntry.localPath is the WordPress core dir (Bedrock's web/wp, by the same
  // convention runLocal/runVm elsewhere assume); site root is two levels up,
  // and uploads live at the Bedrock-standard web/app/uploads sibling.
  const siteRoot = path.dirname(path.dirname(devEntry.localPath));
  const localUploadsDir = path.join(siteRoot, "web", "app", "uploads") + "/";
  await mkdir(localUploadsDir, { recursive: true });

  const rsyncArgs = ["--archive", "--compress"];
  if (del) rsyncArgs.push("--delete");
  rsyncArgs.push(`${fromEntry.sshHost}:${remoteUploadsDir}`, localUploadsDir);

  const result = await exec("rsync", rsyncArgs);
  if (result.code !== 0) {
    throw new Error(`rsync exited ${result.code}${result.stderr ? `: ${result.stderr}` : ""}`);
  }

  return {
    remoteUploadsDir,
    localUploadsDir,
    deleted: del,
    rsyncOutput: (result.stdout + result.stderr).trim(),
  };
}
