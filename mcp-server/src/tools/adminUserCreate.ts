import { randomBytes } from "node:crypto";
import type { EnvEntry } from "../registry.js";
import { runWpCliRaw } from "./wpCli.js";

export interface AdminUserCreateResult {
  username: string;
  email: string;
  role: string;
  // Only set when generated (not caller-supplied) — shown once, matching
  // admin-user-create.sh's "printed once, not stored anywhere" behavior.
  generatedPassword?: string;
}

// Mirrors wp-cli/security/admin-user-create.sh: check the username/email aren't
// already taken, then create the user with --porcelain. Reuses runWpCliRaw
// directly rather than reimplementing local/SSH/VM dispatch — the same three
// checks the script does (existing username, existing email, then create) are
// just three ordinary WP-CLI calls against the already-resolved site/env entry.
export async function runAdminUserCreate(
  entry: EnvEntry,
  username: string,
  email: string,
  role: string,
  password?: string
): Promise<AdminUserCreateResult> {
  const byUsername = await runWpCliRaw(entry, ["user", "get", username, "--field=ID"]);
  if (byUsername.code === 0) {
    throw new Error(`A user named "${username}" already exists.`);
  }

  const byEmail = await runWpCliRaw(entry, ["user", "get", email, "--field=ID"]);
  if (byEmail.code === 0) {
    throw new Error(`A user with email "${email}" already exists.`);
  }

  const generated = !password;
  // openssl rand -base64 24 (the script's default) encodes 24 raw bytes; match
  // that exactly rather than picking an arbitrary Node equivalent.
  const finalPassword = password ?? randomBytes(24).toString("base64");

  const create = await runWpCliRaw(entry, [
    "user",
    "create",
    username,
    email,
    `--role=${role}`,
    `--user_pass=${finalPassword}`,
    "--display_name=Temporary Admin",
    "--porcelain",
  ]);
  if (create.code !== 0) {
    throw new Error(`WP-CLI could not create the user (exit ${create.code}): ${create.stderr || create.stdout}`);
  }

  return { username, email, role, generatedPassword: generated ? finalPassword : undefined };
}
