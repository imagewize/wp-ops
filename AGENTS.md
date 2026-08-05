# Repository Guidelines

## Project Structure & Module Organization
- **trellis/** - Trellis-specific: `backup/`, `monitoring/`, `provision/`, `updater/`
- **wp-cli/** - WordPress CLI tools: `content-creation/`, `diagnostics/`, `migration/`
- **scripts/** - Utilities: `backup/`, `monitoring/`, `git/create-pr.sh`, `release/release-theme.sh`, `sync/rsync-theme.sh`
- **docs/** - Design docs at the top level; guides in subdirectories: `nginx/` (server configs), `troubleshooting/` (server/WP), `bedrock/` (Composer workflows)
- **Root docs**: `README.md`, `CLAUDE.md`, `CREATE-PR.md`, `AGENTS.md`, `CHANGELOG.md`, `LICENSE.md`
- Keep new tools self-contained: add to appropriate category with a concise `README.md` and example configs.

## Build, Test, and Development Commands
- Run updater: `bash trellis/updater/trellis-updater.sh` (clone latest Trellis, diff, rsync updates); use a throwaway project dir before touching production.
- Run PR helper: `bash scripts/git/create-pr.sh` (generates PR text via configured AI backends).
- Most guides describe ad-hoc commands (e.g., `ansible-playbook`, `wp`, `rsync`); mirror the documented invocations inside each tool's `README.md` when adding or updating steps.

## Coding Style & Naming Conventions
- Scripts: Bash with `#!/bin/bash`; prefer `set -euo pipefail`, double-quoting, and long-form flags. Indent with two spaces for readability.
- Variables: UPPER_SNAKE for constants/paths, lower_snake for locals; keep function names verb-based (`run_backup`, `sync_theme`).
- Documentation: Markdown headings, lists, and fenced examples with accurate paths. Keep sections short and actionable.

## Testing Guidelines
- No automated test suite; validate changes by running the exact commands you document with safe flags first (`--check`, `--diff`, `--dry-run` where available).
- For shell changes, sanity-check with `bash -n script.sh`; use `shellcheck` locally if available before submitting.
- Describe manual verification steps in the relevant `README.md` (inputs, expected outputs, cleanup).

## Git Workflow
- Create feature branches from `main` with descriptive names:
  - `git checkout -b add/feature-name` or `git checkout -b fix/issue-name`
  - Use lowercase, hyphens, and prefix with `add/`, `fix/`, `feature/`, etc.
- Make atomic commits per logical change:
  - Concise, imperative summaries (e.g., `Add monitoring tail script`, `Update backup docs`)
  - One logical change per commit, not one big commit
  - Group related changes by tool or feature
- Update `CHANGELOG.md` for material changes:
  - Use Keep a Changelog format
  - Add new versioned section at top with date (e.g., `## [2.6.0] - 2026-05-05`)
  - Bump SemVer: `X.Y.0` for features (new functionality), `X.Y.Z` for fixes (bug fixes)
  - Include `[Unreleased]` section below versioned section for ongoing changes
- Push branch to origin: `git push origin add/feature-name`
- Create Pull Request using the helper script:
  - `bash scripts/git/create-pr.sh --ai=vibe` (interactive — prompts for branch, title, and AI choice)
  - `bash scripts/git/create-pr.sh --no-interactive main "PR title" --ai=claude` (fully non-interactive)
  - Passing positional args without `--no-interactive` still triggers prompts
  - Script auto-generates AI-powered description and creates PR via GitHub CLI
- PRs: include a short description of scope, commands run/outputs (or screenshots for doc-only visual changes), and linked issues if applicable. Note any risk areas (data migration, remote writes).

### Important Rules
- **AI co-authorship in commits is allowed** — `Co-Authored-By` lines for Claude or Mistral Vibe are permitted
- Always update CHANGELOG.md alongside code changes
- Validate scripts with `bash -n script.sh` before committing

## Context for Tasks
Before starting, identify:
1. Which category the task belongs to (trellis, wp-cli, scripts, wordpress-utilities, mcp-server, or docs for guide-only changes)
2. Relevant existing files and conventions in that category
3. Whether changes need companion updates to documentation

## Security & Configuration Tips
- Never commit secrets (vault files, SMTP creds, `.env`, private keys). Use redacted examples and `.example` templates.
- Be cautious with destructive commands (`rm`, `rsync --delete`, database exports); default to dry runs and document required backups/restores.
