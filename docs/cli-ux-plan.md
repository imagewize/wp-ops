# CLI UX Plan: Command Manifest + Go Rewrite

> **Status (2026-07-31):** M1 shipped in 3.10.0 and is merged to `main`
> (`feature/cli-manifest-phase-a`, PR #134) — manifest spec, bash parser,
> `wp-ops manifest lint`, and the first two command groups
> (`scripts/backup/*`, `scripts/monitoring/*`, 10 commands) annotated.
> Rollout group 2 (`trellis/backup/*.yml`, `trellis/monitoring/*.yml`, 10
> commands), merged to `main` in PR #135, is also annotated — 20/66 total.
> Rollout group 3 (`wp-cli/**`, `bedrock/**`, 12 commands), group 4
> (`wordpress-utilities/**`, 5 commands), and group 5 (remaining `scripts/**`,
> 25 commands, plus the 2 `trellis/security`/`trellis/updater` stragglers it
> surfaced) are now all annotated too, on `feature/cli-manifest-m2-group3` —
> 64/66 total — see "Progress" under Phase A below for details. The only
> holdouts are `mcp-server/*` (2), always out of Phase A's scope — see Phase D.
> Guided per-argument prompting in `fzf_menu()`/`interactive_command_menu()`,
> M2's last item besides CI lint wiring, shipped in 3.13.0 — see "Phase A
> implementation" below.

A plan to take the `wp-ops` CLI from "auto-discovered shell scripts" to a
declarative, self-documenting tool with the ergonomics of
[trellis-cli](https://github.com/roots/trellis-cli).

Two phases, deliberately sequenced:

- **Phase A — Manifest.** Every command declares its description, arguments,
  and where it runs. Shipped in the existing bash CLI, so the UX improves
  before any rewrite starts.
- **Phase C — Go binary.** Replace the 1,816-line bash dispatcher with a Cobra
  CLI that reads the same manifest. Real flag parsing, generated help, shell
  completions, a single installable binary.

Phase A is a prerequisite, not an alternative. Go does not know what
`db-backup.sh` expects either.

## The problem

`wp-ops` has **no metadata**. Every element of the UI is scraped from source
files at runtime:

| UI element | How it's produced | Location |
|---|---|---|
| Command description | `grep -m1 '^#\s'` over the first 20 lines | `wp-ops:288` |
| Description cleanup | First sentence, truncated to 72 chars | `wp-ops:189` |
| fzf preview | `head -40` of the raw file | `wp-ops:1497` |
| "Runs on server" warning | Hardcoded list of 5 of 66 commands | `wp-ops:88-102` |
| `--help` | Probe `script --help`; fall back to a stub | `wp-ops:1068-1077` |
| Shell completion | Hand-written bash function | `wp-ops:1615` |

There is nothing to render a good UI *from*, so the interactive picker can only
offer a single blank `Arguments:` box.

### Worked example: the failure this plan fixes

A user wants to back up a production database.

1. `wp-ops` → fzf picker → selects `scripts/backup/db-backup`.
2. Prompt: `Arguments (leave blank for none, --help for usage):`. No indication
   that it wants `<site-name> <backup-type>`.
3. They type `--help`. `db-backup.sh` has no `--help` handling, so the probe at
   `wp-ops:1068` fails and they get the generic stub: *"Run 'db-backup.sh
   --help' for script-specific options."* Circular.
4. They guess `example.com production`. It fails with `Site directory not
   found: /srv/www/example.com`.

The script hardcodes `/srv/www/$SITE_NAME` and `/srv/backups/`
(`scripts/backup/db-backup.sh:14-17`) — it **only runs on the server**. But it
isn't in `SERVER_SIDE_COMMANDS`, so the guard at `wp-ops:1012-1036` never
fires and nothing says so.

There is no way to reach that conclusion from the UI.

**Status:** this specific failure was patched directly in 3.9.1 (`--help` text
added to both backup scripts, both registered in `SERVER_SIDE_COMMANDS`) and
then superseded in 3.10.0 by the manifest doing the same job generically — see
"Immediate fixes" below and "Progress" under Phase A.

### Related: the CLI and MCP server have forked

`mcp-server/config/sites.example.json` already models exactly what the CLI
lacks — per-site, per-environment connection details:

```json
"client.nl": { "production": {
  "sshHost": "client@client.nl",
  "remotePath": "/home/client/public_html",
  "wpBin": "~/wp-cli.phar",
  "phpBin": "/opt/plesk/php/8.2/bin/php"
}}
```

`mcp-server/src/tools/dbBackup.ts:60-79` resolves site+env to Trellis VM / SSH /
local and streams the dump over stdout. **The MCP server can back up production
over SSH. The CLI cannot.** Every release widens the gap.

## Current inventory

66 commands, four execution modes:

| Category | Count | Executor | Location |
|---|---|---|---|
| `scripts` | 35 | direct exec (`.sh`, `.js`, `.py`) | `wp-ops:1085` |
| `trellis` | 12 | Ansible playbook (`.yml`) | `execute_playbook`, `wp-ops:710` |
| `wp-cli` | 11 | WP-CLI / PHP (`.php`) | `execute_php_command`, `wp-ops:790` |
| `wordpress-utilities` | 5 | snippet → clipboard | `execute_snippet`, `wp-ops:865` |
| `mcp-server` | 2 | direct exec | — |
| `bedrock` | 1 | WP-CLI / PHP | — |

`nginx` and `troubleshooting` are docs-only. File types: 39 `.sh`, 13 `.yml`,
10 `.php`, 4 `.js`, 2 `.py`, 1 `.css`.

All four executors must survive the rewrite.

---

# Phase A — Command manifest

## Directive format

A block of `@` directives in the script's header comment. Comment syntax varies
by file type (`#`, `//`, `*`), so the parser strips the leading comment marker
before matching.

```bash
#!/usr/bin/env bash
# Trellis Database Backup Script
#
# @desc     Back up a Trellis site database with WP-CLI
# @category backup
# @runs     server
# @requires wp
# @arg      site  required  {example.com}  Site name as in wordpress_sites.yml
# @arg      env   required  {production|staging|development}  Target environment
# @flag     --retention-days  optional  {30}  Days of backups to keep
# @example  wp-ops backup db example.com production
# @doc      trellis/backup/README.md
```

### Directives

| Directive | Purpose |
|---|---|
| `@desc` | One-line description. Replaces the scrape at `wp-ops:288`. |
| `@category` | Logical group. Decouples grouping from directory layout. |
| `@runs` | `local` \| `server` \| `either`. Replaces `SERVER_SIDE_COMMANDS`. |
| `@requires` | Binaries needed. Feeds `wp-ops doctor` (`wp-ops:1394`). |
| `@arg` | `NAME  required\|optional  {choices-or-default}  Description` |
| `@flag` | Same shape, for named flags. |
| `@example` | Copy-pasteable invocation. Multiple allowed. |
| `@doc` | Repo-relative guide path. Feeds `wp-ops docs`. |

`@arg` parses as: whitespace-separated name and requiredness, an optional
`{...}` field holding either a default or `|`-separated choices, then the rest
of the line as free-text description. Robust to `awk` field splitting and
readable in the source file.

## What the manifest unlocks

1. **Per-argument prompts.** The picker asks for `site` and `env` separately,
   showing the description and offering choices, instead of one blank box.
2. **Real `--help` for every command**, generated from the declaration. No more
   probing a script that may not support it, no more stub.
3. **Generic `@runs server` guard.** `SERVER_SIDE_COMMANDS` becomes derived
   rather than hardcoded, so `db-backup` is covered automatically — along with
   any script added later.
4. **Curated fzf preview** — usage, args, examples — instead of `head -40`.
5. **Dependency-aware `doctor`** — `@requires` tells you which commands are
   currently unusable and why.
6. **Richer `--json`.** It already emits a `runs_on` field; the manifest turns
   that into a full contract the MCP server can consume.

## Phase A rollout

Annotate in dependency order, most-confusing-first:

1. `scripts/backup/*` (2), `scripts/monitoring/*` (8) — the commands in the
   worked example above. **Done, merged in 3.10.0.**
2. `trellis/**/*.yml` (10 commands — `variable-check.yml` is an imported
   playbook, not a discoverable command, so the real count is 10, not 12);
   every one needs `site` and `env`, today that's only discoverable by
   reading `variable-check.yml`. **Done, on `feature/cli-manifest-m2`,
   shipping in 3.11.0.** Also required a fix to `execute_playbook()`, whose
   `--help` branch called its own hardcoded usage text unconditionally
   instead of checking `has_manifest` first — the same short-circuit the
   generic script dispatcher already had. Without it, annotating a `.yml`
   command had no visible effect on `--help`.
3. `wp-cli/**` (11) and `bedrock/**` (1). **Done, on
   `feature/cli-manifest-m2-group3`.** Also required a fix to
   `execute_php_command()`, whose `--help` branch had the same
   `has_manifest`-blind short-circuit as `execute_playbook()` (fixed in group
   2) — it always rendered the hardcoded description/usage text instead of
   `print_manifest_help()`, so annotating the 12 `.php` commands had no
   visible effect on `--help` until fixed.
4. `wordpress-utilities/**` (5) — snippets, mostly `@desc` + `@doc`. **Done, on
   `feature/cli-manifest-m2-group3`.** Also required a fix to
   `execute_snippet()`, whose `--help` branch had the same
   `has_manifest`-blind short-circuit as `execute_playbook()`/
   `execute_php_command()` — corrected the same way.
5. The remaining `scripts/**` (25 commands: `git`, `images`, `misc`, the two
   `monitoring` stragglers added after group 1 shipped, `patterns`, `release`,
   `sync`, `woocommerce`), plus 2 `trellis/security`/`trellis/updater`
   stragglers this group surfaced (see below). **Done, on
   `feature/cli-manifest-m2-group3`.** Three scripts
   (`deploy-plugin-wporg.sh`, `rsync-package-to-site.sh`, `rsync-theme.sh`)
   print their own `--help` via a fixed `sed -n 'N,Mp'` line range over their
   own source, so their manifest blocks had to be inserted *after* that range
   rather than in the natural spot right before `set -e` — otherwise the
   inserted lines would shift everything after them and get printed as part
   of the script's own `--help` output.

**Discovered during group 5:** `discover_commands()` matches `*.sh` under
every category, not just `trellis/**/*.yml` — so `trellis/security/check-ips.sh`
and `trellis/updater/trellis-updater.sh` were real, undiscovered commands that
group 2's "10, not 12" count missed entirely. Both are now annotated too
(`@category security` / `@category updater`, `@runs local`). Only
`mcp-server/*` (2, never in scope for Phase A — see Phase D) remains
unannotated, which is why the total sits at 64/66 rather than 66/66.

## Phase A implementation

- `parse_manifest()` — extract directives from a file into a tab-delimited
  record. **Done** — `manifest_directive_lines()` + `load_manifest()`,
  storing `command_key|directive|value` rows in a temp file per run
  (`get_all_commands`'s sibling: `manifest_get`/`manifest_get_all`/
  `has_manifest`).
- Extend `discover_commands()` (`wp-ops:214`) to prefer manifest data, falling
  back to the current scrape for un-annotated scripts. **Annotation can be
  incremental** — nothing breaks mid-rollout. **Done** — a manifest `@desc`
  is written straight into `COMMAND_FILE`, so `search`, category listings,
  and `--json` all pick it up for free.
- Replace `is_server_side_command()` (`wp-ops:104`) with a `@runs` lookup.
  **Mechanism done**, coverage now at 64/66: it checks the manifest first and
  falls back to the hardcoded `SERVER_SIDE_COMMANDS` list, needed only for
  `mcp-server/*`'s 2 remaining un-annotated commands. Groups 2–4 and the
  `trellis` stragglers were all `@runs local` (or not run at all, for the
  snippets), so the hardcoded list was unchanged by them; group 5 is the first
  to add manifest-only server-side coverage —
  `scripts/monitoring/updown-webhook-handler.sh` is `@runs server` but was
  never in `SERVER_SIDE_COMMANDS`, so before this it had no wrong-machine
  guard at all.
- Rewrite the `--help` path (`wp-ops:1068`) to render from the manifest.
  **Done** — `print_manifest_help()` short-circuits the script-probe entirely
  when a manifest exists, so commands with no `--help` handling of their own
  (6 of the 8 annotated monitoring scripts) get real usage output for the
  first time. `execute_php_command()` and `execute_snippet()` had the same
  has_manifest-blind short-circuit `execute_playbook()` had before the group 2
  fix; corrected in groups 3 and 4 respectively, so the 12 `wp-cli`/`bedrock`
  `.php` commands' and the 5 `wordpress-utilities` snippets' `--help` are also
  manifest-driven now.
- Add guided prompting to `fzf_menu()` (`wp-ops:1477`) and
  `interactive_command_menu()` (`wp-ops:1563`). **Done, shipped in 3.13.0.**
  Both now call a shared `prompt_manifest_args()`, which prompts once per
  `@arg`/`@flag` — showing its description, its `|`-separated choices or
  default inline, and reprompting on a blank required field — instead of one
  free-text box. Commands with no manifest data at all keep the original
  prompt. Ends with an "Additional arguments" catch-all, since a manifest
  line is only prompted once and can't express a repeatable flag. Required a
  fix along the way: the natural `while read line; do ...; done <<< "$args"`
  loop rebinds stdin to the heredoc for its body, so the nested `read -p`
  inside the per-line prompt was consuming the next manifest line instead of
  the user's answer — fixed by collecting lines into an array first and
  walking that with a plain `for`.
- Add `wp-ops manifest lint` — fails on missing or malformed directives. Wire
  into CI so new scripts can't regress. **Parser and command done**
  (`wp-ops manifest lint`, checks `@desc` presence, `@runs` enum, `@arg`/
  `@flag` requiredness, and `@doc` file existence). **CI wiring not done.**
- `--json`'s existing `runs_on` field is now manifest-derived where a
  manifest exists; `requires` and `doc` fields were added alongside it
  (empty string when unset, so the schema stays stable across annotated and
  un-annotated commands).

Ships as **3.10.0** (parser + first two groups) and **3.11.0** (full coverage
plus guided prompts). No breaking changes.

---

# Phase C — Go binary

## Framework

**Cobra**, not `hashicorp/cli`.

trellis-cli uses [`hashicorp/cli`](https://github.com/hashicorp/cli) (the
maintained fork of mitchellh/cli), which is why its help output looks the way it
does. Cobra gives us better flag handling and — decisively — free completions
for bash, zsh, fish, and PowerShell, replacing the hand-written
`print_completion` at `wp-ops:1615`.

## Architecture

```
main.go                       Cobra root, registers commands from the catalog
internal/manifest/            Directive parser + validator (shared with lint)
internal/catalog/             Embedded catalog.json + lookup/search
internal/exec/
  shell.go                    .sh / .js / .py  → direct exec
  ansible.go                  .yml             → port of execute_playbook (wp-ops:710)
  wpcli.go                    .php             → port of execute_php_command (wp-ops:790)
  snippet.go                  snippets         → port of execute_snippet (wp-ops:865)
internal/detect/              Port of detect_trellis_dir (wp-ops:593)
                              and detect_wp_site_dir (wp-ops:627)
internal/registry/            sites.json — schema shared with the MCP server
internal/ui/                  Bubble Tea picker (replaces the fzf dependency)
```

**Build-time catalog.** A `go:generate` step parses all 66 manifests into
`catalog.json`, embedded via `go:embed`. No runtime filesystem scan; a malformed
manifest fails the build rather than degrading the UI.

## Carried over from the bash CLI

The scripts themselves are **not** rewritten. The binary shells out exactly as
today. Logic worth porting rather than reinventing:

- Symlink-resolving `REPO_ROOT` detection (`wp-ops:26-33`)
- Trellis and WP site directory detection + confirmation (`wp-ops:593-681`)
- GNU `date` detection and its guidance path (`wp-ops:149`, `wp-ops:972`)
- Ambiguous-basename resolution (`wp-ops:1105`) and did-you-mean
  (`wp-ops:1136`)
- `docs` search (`wp-ops:1235-1346`) and `doctor` (`wp-ops:1394`)

## Distribution

`goreleaser` → Homebrew tap (`imagewize/tap`) + `go install`. Replaces the
PATH-append in `install.sh`.

**Open decision — where do the scripts live?**

- **(a) Embed them.** `go:embed` the script tree; extract to a cache dir on
  first run. `brew install wp-ops` becomes fully self-contained. `--where`
  points at the extracted copy.
- **(b) Locate the checkout.** Binary resolves a repo root from `WP_OPS_ROOT` or
  config, as today.

**Recommendation: (a), with `WP_OPS_ROOT` as a development override.** Most
users want the tool, not the repo. Contributors set the env var and iterate on
scripts without rebuilding. Note that several assets (nginx configs, WP
snippets) exist to be *copied into projects* — extraction handles this fine.

## Compatibility

- `wp-ops <category>/<command>` keys keep working — they are how the docs, the
  MCP server, and muscle memory refer to commands.
- Short forms are added on top: `wp-ops backup db example.com production`.
- `--json`, `--where`, `search`, `docs`, `doctor` keep their current contracts.

---

# Phase D — Site registry convergence

Once Go owns the CLI, adopt the MCP server's registry
(`mcp-server/src/registry.ts`, `config/sites.example.json`) as the shared
source of truth at `~/.config/wp-ops/sites.json`.

This is what answers *"how do I run the production backup?"* end to end:

```
wp-ops backup db example.com production --on production
```

The CLI resolves `sshHost` from the registry and streams the command to the
server — the dispatch `dbBackup.ts:60-79` already implements. The bash CLI
cannot do this; it's the single largest capability gain in the plan.

# Phase E — trellis-cli plugin symlink

trellis-cli's plugin system is a kubectl-style PATH passthrough: `main.go:232-234`
scans `$PATH` for executables named `trellis-*` and registers them, executing
via `syscall.Exec` (`cmd/passthrough.go`).

Symlinking the binary as `trellis-wpops` makes `trellis wpops backup db ...`
work for Trellis users. **One install step, not an architecture.**

It contributes nothing to the UX problem — `Synopsis()` is hardcoded to
*"Third party plugin: Forward command to …"* (`cmd/passthrough.go:43`) and
`plugin/help_func.go` prints a bare name list. It also cannot express the
non-Trellis half of the catalog (`scripts/images`, `scripts/patterns`,
`scripts/release`, `scripts/git`, `bedrock`, `wordpress-utilities`). It is
purely additive distribution.

---

# Milestones

| # | Scope | Version | Status |
|---|---|---|---|
| M1 | Manifest spec, bash parser, `manifest lint`, backup + monitoring annotated | 3.10.0 | **Done**, merged (PR #134) |
| M2 | All 66 annotated; guided prompts; `@runs` replaces the hardcoded list | 3.11.0 | **In progress** — groups 1–5 plus the 2 `trellis` stragglers annotated (64/66 total); guided prompts shipped in 3.13.0; only `mcp-server/*` (2, out of scope) and CI lint wiring remain |
| M3 | Go skeleton, catalog generator, shell + ansible executors; parity on `list`/`search`/`doctor`/`--json` | 4.0.0-beta | Not started |
| M4 | Remaining executors, Bubble Tea picker, completions, goreleaser + tap | 4.0.0 | Not started |
| M5 | Shared site registry, `--on <env>` SSH dispatch | 4.1.0 | Not started |
| M6 | `trellis-wpops` symlink | 4.1.0 | Not started |

## Immediate fixes (do now, independent of the plan)

Both shipped in 3.9.1, ahead of and independent of this plan:

1. ~~Add a real `--help` / usage block to `scripts/backup/db-backup.sh` and
   `scripts/backup/site-backup.sh`.~~ **Done** (3.9.1).
2. ~~Add both to `SERVER_SIDE_COMMANDS` (`wp-ops:88-102`) so the existing
   server-side guidance fires.~~ **Done** (3.9.1), then superseded in 3.10.0
   by the `@runs server` manifest directive on both scripts.

# Risks

- **Dual maintenance during M3–M4.** Mitigated by having the Go binary read the
  *same* manifest the bash CLI reads. The bash implementation is deleted only at
  4.0.0.
- **Manifest drift.** Mitigated by `manifest lint` in CI and by the build-time
  catalog failing the build on malformed input.
- **Go build in the release path.** New for this repo; goreleaser plus a tap is
  well-trodden, and the scripts remain runnable directly if the binary is
  unavailable.

# Non-goals

- Rewriting the 66 scripts in Go. They stay shell/PHP/Python/YAML.
- Replacing the MCP server. It keeps its own entry point; the two converge on a
  shared registry and manifest, not a shared process.
- Upstreaming commands into trellis-cli. Roots' scope is Trellis project
  management, not a general WordPress ops catalog.
