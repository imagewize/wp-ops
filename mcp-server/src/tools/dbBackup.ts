import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { gzip as gzipCallback } from "node:zlib";
import type { EnvEntry } from "../registry.js";
import { hasTrellisVm, resolveWpBin, resolvePhpBin } from "../registry.js";
import { stripVmBannerFromBuffer } from "./wpCli.js";

function shellQuote(arg: string): string {
  return `'${arg.replace(/'/g, `'\\''`)}'`;
}

const gzip = promisify(gzipCallback);

export interface BackupResult {
  filePath: string;
  sizeBytes: number;
}

function backupRoot(): string {
  return process.env.WP_OPS_BACKUP_DIR
    ? path.resolve(process.env.WP_OPS_BACKUP_DIR)
    : path.join(os.homedir(), "wp-ops-backups");
}

function timestamp(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}_${pad(d.getMonth() + 1)}_${pad(d.getDate())}_${pad(d.getHours())}_${pad(
    d.getMinutes()
  )}_${pad(d.getSeconds())}`;
}

// Exports as a Buffer (not text) since a SQL dump isn't guaranteed valid UTF-8.
function exportSql(command: string, args: string[], cwd?: string): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, cwd ? { cwd } : {});
    const chunks: Buffer[] = [];
    let stderr = "";
    child.stdout.on("data", (d) => chunks.push(d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) {
        reject(new Error(`wp db export exited ${code}${stderr ? `: ${stderr}` : ""}`));
        return;
      }
      resolve(Buffer.concat(chunks));
    });
  });
}

export async function runDbBackup(entry: EnvEntry, site: string, env: string): Promise<BackupResult> {
  const wpBin = resolveWpBin(entry);
  const phpBin = resolvePhpBin(entry);
  const wpCommand = phpBin ? [phpBin, wpBin] : [wpBin];
  
  let sql: Buffer;
  // VM-first: a Trellis dev box keeps the DB in the VM, so `wp db export` must run there.
  if (hasTrellisVm(entry)) {
    const wpPath = entry.vmPath ?? "web/wp";
    // Export streams over the VM shell's stdout; nothing is written to disk in the VM.
    // `trellis vm shell` prints a "Running command => …" banner ahead of the real
    // output — strip it here too, or it lands inside the .sql dump before gzip (see
    // the comment on stripVmBanner in wpCli.ts for the bug this already caused once).
    sql = stripVmBannerFromBuffer(
      await exportSql(
        "trellis",
        ["vm", "shell", "--workdir", entry.vmWorkdir, "--", ...wpCommand, "db", "export", "-", `--path=${wpPath}`],
        entry.trellisDir
      )
    );
  } else if (entry.sshHost && entry.remotePath) {
    // Streams the export over SSH stdout so nothing is ever written to disk on the
    // remote host (same rationale as securityScan's remote path).
    const remoteCommand = [...wpCommand, "db", "export", "-", `--path=${entry.remotePath}`].map(shellQuote).join(" ");
    sql = await exportSql("ssh", [entry.sshHost, remoteCommand]);
  } else if (entry.localPath) {
    sql = await exportSql(wpCommand[0], [...wpCommand.slice(1), "db", "export", "-", `--path=${entry.localPath}`]);
  } else {
    throw new Error("Site/env entry has none of: trellisDir+vmWorkdir, sshHost+remotePath, localPath, or url.");
  }

  const compressed = await gzip(sql);

  const destDir = path.join(backupRoot(), site, env);
  await mkdir(destDir, { recursive: true });

  const fileName = `${site.replace(/\./g, "_")}_${env}_${timestamp()}.sql.gz`;
  const filePath = path.join(destDir, fileName);
  await writeFile(filePath, compressed);

  return { filePath, sizeBytes: compressed.length };
}
