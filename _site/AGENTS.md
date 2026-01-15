# Repository Guidelines

## Project Structure & Module Organization
- **trellis/** - Trellis-specific: `backup/`, `monitoring/`, `provision/`, `updater/`
- **wp-cli/** - WordPress CLI tools: `content-creation/`, `diagnostics/`, `migration/`
- **nginx/** - Server configs: `browser-caching/`, `image-optimization/`, `redirects/`
- **scripts/** - Utilities: `backup/`, `monitoring/`, `create-pr.sh`, `release-theme.sh`, `rsync-theme.sh`
- **troubleshooting/** - Cross-cutting server/WP troubleshooting guides
- **Root docs**: `README.md`, `CLAUDE.md`, `CREATE-PR.md`, `AGENTS.md`, `CHANGELOG.md`, `LICENSE.md`
- Keep new tools self-contained: add to appropriate category with a concise `README.md` and example configs.

## Build, Test, and Development Commands
- Run updater: `bash trellis/updater/trellis-updater.sh` (clone latest Trellis, diff, rsync updates); use a throwaway project dir before touching production.
- Run PR helper: `bash scripts/create-pr.sh` (generates PR text via configured AI backends).
- Most guides describe ad-hoc commands (e.g., `ansible-playbook`, `wp`, `rsync`); mirror the documented invocations inside each tool's `README.md` when adding or updating steps.

## Coding Style & Naming Conventions
- Scripts: Bash with `#!/bin/bash`; prefer `set -euo pipefail`, double-quoting, and long-form flags. Indent with two spaces for readability.
- Variables: UPPER_SNAKE for constants/paths, lower_snake for locals; keep function names verb-based (`run_backup`, `sync_theme`).
- Documentation: Markdown headings, lists, and fenced examples with accurate paths. Keep sections short and actionable.

## Testing Guidelines
- No automated test suite; validate changes by running the exact commands you document with safe flags first (`--check`, `--diff`, `--dry-run` where available).
- For shell changes, sanity-check with `bash -n script.sh`; use `shellcheck` locally if available before submitting.
- Describe manual verification steps in the relevant `README.md` (inputs, expected outputs, cleanup).

## Commit & Pull Request Guidelines
- Commits should be concise, imperative summaries (e.g., `Add monitoring tail script`, `Update backup docs`). Group related changes by tool.
- PRs: include a short description of scope, commands run/outputs (or screenshots for doc-only visual changes), and linked issues if applicable. Note any risk areas (data migration, remote writes).
- Update changelog entries when behavior changes materially; keep doc updates alongside the tool they describe.
- Changelog updates: edit `CHANGELOG.md` using Keep a Changelog sections, bump the SemVer version (e.g., `1.13.0` for new features, `1.13.1` for fixes), and stamp the date `YYYY-MM-DD`.

## Security & Configuration Tips
- Never commit secrets (vault files, SMTP creds, `.env`, private keys). Use redacted examples and `.example` templates.
- Be cautious with destructive commands (`rm`, `rsync --delete`, database exports); default to dry runs and document required backups/restores.
