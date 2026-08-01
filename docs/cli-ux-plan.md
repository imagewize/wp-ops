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
> Guided per-argument prompting in `fzf_menu()`/`interactive_command_menu()`
> shipped in 3.13.0, and CI lint wiring (`.github/workflows/manifest-lint.yml`,
> running `wp-ops manifest lint` on push/PR to `main`) landed right after —
> M2 is now fully done bar the 2 out-of-scope `mcp-server/*` commands. See
> "Phase A implementation" below. M3 (Go CLI skeleton) is also done, merged
> to `main` in PR #140 — see `docs/m3-go-skeleton.md`. M4 is in progress —
> tasks 3 (Bubble Tea picker) and 4 (shell completions) are merged (PRs
> #144, #145); tasks 1–2 (remaining executors) were also done earlier. Task
> 5 (`docs` search) and 6 (goreleaser + tap) remain — see
> `docs/m4-go-cli-completion.md`. Phase F (below) was raised against M4's
> shipped picker/list surfaces; its options 1–3 merged in PR #146 (3.20.0).
> Option 4 (splitting `scripts`) is now also done, on
> `feature/cli-picker-search-scripts-categories`, not yet merged — turned out
> far cheaper than estimated since every `scripts/**` file already carried a
> fine-grained `@category` tag, just never wired into the top-level grouping.
> The same branch also fixes a small regression option 3 introduced: typing
> on the picker's new outermost category screen did nothing until Enter was
> pressed on "All categories" first. See Phase F's "Done (4)" below.

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
  into CI so new scripts can't regress. **Done** — `wp-ops manifest lint`
  checks `@desc` presence, `@runs` enum, `@arg`/`@flag` requiredness, and
  `@doc` file existence; wired into
  `.github/workflows/manifest-lint.yml`, which runs it on every push and PR
  to `main`.
- `--json`'s existing `runs_on` field is now manifest-derived where a
  manifest exists; `requires` and `doc` fields were added alongside it
  (empty string when unset, so the schema stays stable across annotated and
  un-annotated commands).

Ships as **3.10.0** (parser + first two groups) and **3.11.0** (full coverage
plus guided prompts). No breaking changes.

---

# Phase C — Go binary

> **M3 scope:** see `docs/m3-go-skeleton.md` for the ordered task
> breakdown, open decisions (Go module location, `mcp-server/*` catalog
> parity, `docs` command deferral), and acceptance criteria. This section
> stays the high-level architecture reference; the tracker doc is where
> multi-session implementation progress gets checked off.

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

# Phase F — Command discovery: default views and picker density

**Status (2026-08-01):** Options 1, 2, and 3 done, merged to `main` in
PR #146 (3.20.0). Option 4 done, on
`feature/cli-picker-search-scripts-categories`, not yet merged — see "Done
(4)" below. That branch also fixes a type-to-search regression option 3
introduced; see the same section.
Raised against the M4 Go CLI (`docs/m4-go-cli-completion.md`), after M4
tasks 3 (Bubble Tea picker) and 4 (shell completions) shipped — the
manifest work in Phase A gave every command good metadata, but the three
surfaces that render the *list* of commands still show too much at once, or
too little structure, to act as a landing page.

## The problem

Three views, three different symptoms:

1. **`wp-ops list` / piped bare `wp-ops`** (`go/cmd/list.go:34`,
   `printCategorizedList`) — flattens all ~66 commands under category
   headers, one full-sentence description per line. Correctly organized,
   just long: it's a wall of text that requires scrolling, not a landing
   page.
2. **The Bubble Tea picker on bare `wp-ops`** (`go/internal/ui/model.go`) —
   the opposite problem. `New()` (`model.go:80-89`) loads `c.Entries` as one
   flat, alphabetically-sorted list with no category grouping at all,
   filterable by typing. Compact, but directionless: nothing distinguishes
   a backup command from an image-conversion command except reading each
   line.
3. **`trellis` with no arguments** — short (~22 lines) because it's a
   **two-level** structure: top-level verbs, some of which (`db`, `server`,
   `key`, `vm`) fan out to subcommands only shown after typing
   `trellis db`.

## Key finding: the two-level structure already exists

`wp-ops <category>` (e.g. `wp-ops trellis`) is already a real command —
`registerCatalogCommands` (`go/cmd/dispatch.go:47-61`) registers one Cobra
command per active category, whose bare-args `RunE` calls `runCategory` →
`printCategoryCommands` (`list.go:49`), printing just that category's
commands. Nothing needs to be built to get trellis-style drill-down; it's
wired but not the *default* landing view — `wp-ops list` and bare `wp-ops`
both still call `printCategorizedList`, which shows everything at once
instead of pointing at the category commands that already exist.

## Options

| # | Change | Effort | Effect |
|---|---|---|---|
| 1 | Rewrite `printCategorizedList` to print **category names + counts + one blurb only** (~8 lines), pointing at `wp-ops <category>` for the existing full per-category view | Small — one function, no new plumbing | Matches `trellis`'s brevity directly |
| 2 | Picker: insert **dim, non-selectable category header rows** into the browse list — group `filterEntries`'s output by category before rendering (`model.go`'s `viewBrowse`, `filterEntries`) | Small–medium — a grouping pass plus header rows in `viewBrowse` | Same item count, but scannable instead of a flat name wall |
| 3 | Picker: add a **category-select stage before the command list** (browse categories → then that category's commands), mirroring `trellis`'s two-level nav | Medium — a new `stage` in the picker's state machine (`model.go:17-24`) | Biggest ergonomic win, closest match to `trellis`, but adds a keystroke to drill into a category |
| 4 | Split the oversized `scripts` category (35 commands, no subgrouping — the largest of the 6 active categories) into subcategories matching its existing directories (`backup`, `monitoring`, `git`, `images`, `release`, `sync`, `woocommerce`, `misc`, `patterns`) | Larger — touches `@category` manifest values across ~25 files plus catalog grouping logic | Fixes the one category still too big even after #1 |

**Done (1):** `printCategorizedList` (`list.go`) now prints an 8-line
category summary (name, count, one blurb from a new `catalog.CategoryBlurbs`
map); the original full per-command listing moved to `printAllCommands`,
exposed as `wp-ops list --all`. Bare `wp-ops` (piped) and `wp-ops --help`
both pick up the shorter view for free since they already called
`printCategorizedList` (`root.go:71,83`).

**Done (2):** `filterEntries` (`model.go`) now sorts by category rank
(`catalog.Categories`' curated order, matching option 1's summary order)
then key, instead of plain alphabetical-by-key — categories were already
contiguous as a side effect of key-prefix sorting, but not in curated
order. `viewBrowse` tracks the previous row's category while iterating the
visible window and renders a `categoryHeaderStyle`-styled header line
whenever it changes, including at the top of the window after a scroll (so
a mid-scroll view still tells you what category you're looking at). Headers
aren't part of `m.filtered`, so cursor movement and selection indices are
unaffected — only rendering changed.

**Done (3):** added `stageCategory` as the picker's new outermost stage
(`model.go`'s `stage` enum), shown first on launch: "All categories" (cursor
default, scoped to nothing — the full catalog, same reach as before this
option) followed by each active category with its count and
`catalog.CategoryBlurbs` text, reusing the same list `cmd`'s compact `list`
view (option 1) shows. Selecting a category sets `browseCategory` and
re-filters into `stageBrowse` scoped to just that category (`applyFilter` /
new `filterByCategory`); the browse header grows a breadcrumb
(`wp-ops > Trellis > `) and, once scoped, the option-2 per-row category
headers stop repeating themselves since the breadcrumb already says which
category. Esc now means "go up one level" everywhere (stageBrowse → back to
stageCategory; stageFields/stageFreeText → back to stageBrowse, unchanged
from before); Ctrl+C is the only "quit entirely" key past stageCategory.
`catalog.CategoryBlurbs` moved from `cmd/list.go` into `internal/catalog`
so both `cmd` and `internal/ui` read the same map without either package
importing the other.

**Done (4):** far cheaper than the effort estimate above predicted — every
`scripts/**` file already carries a fine-grained `@category` directive
(`backup`, `git`, `images`, `misc`, `monitoring`, `patterns`, `release`,
`sync`, `woocommerce`), a byproduct of Phase A's rollout groups 1 and 5. That
data just wasn't wired into the top-level grouping catalog.json's `category`
field is derived from directory name only, and `Catalog.Categories()` /
`CommandsIn()` / `registerCatalogCommands` all keyed off it. Rather than
promote every subcategory (several are too small to justify their own
top-level entry — `backup`(2), `git`(3), `misc`(3), `sync`(2),
`woocommerce`(1)), only the four with 4+ commands were split out:
`monitoring`(10), `images`(5), `patterns`(5), `release`(4); the rest stay
folded into `scripts`(11).

Implementation added a new `catalog.Entry.DisplayCategory` field
(`internal/catalog/catalog.go`), computed in `gen/main.go`'s
`displayCategoryFor()`, kept **deliberately separate** from the existing
`Category` field: `printJSON` (`cmd/list.go`) must keep emitting `category`
as the top-level directory, byte-for-byte identical to bash's, since
`go/scripts/parity-check.sh` diffs `--json` field-for-field and other
tooling may depend on that contract (see "the CLI and MCP server have
forked" above). A parallel `Catalog.DisplayCategories()` /
`CommandsInDisplay()` / `byDisplayCategory` was added alongside the existing
`Categories()`/`CommandsIn()`/`byCategory`; `printCategorizedList`,
`printAllCommands`, `printCategoryCommands`, `registerCatalogCommands` (so
`wp-ops monitoring`/`images`/`patterns`/`release` work as real category
commands), `runCategory`'s basename-scoping filter, and the picker's
`buildCategoryOptions`/`filterByCategory`/`categoryRank`/`viewBrowse` header
all switched to the Display variants; `printJSON` alone was left untouched.
`catalog.CategoryDisplayNames`/`CategoryBlurbs` gained entries for the four
new categories, and a new `catalog.DisplayOrder` var (parallel to the
existing directory-walk `Categories` var) gives them curated placement
right after `scripts`. Verified: `go test ./...` green, `parity-check.sh`
still 8/8 (confirming `--json` didn't drift), and a manual pass through both
the non-interactive `wp-ops list`/`wp-ops monitoring` output and the
Bubble Tea picker's category-select screen.

**Also fixed alongside (4):** option 3 made `stageCategory` the picker's new
default screen, but it only handled arrow keys — typing there did nothing,
so a user had to arrow-down-and-Enter onto "All categories" before typing
could filter anything, silently dropping the "just start typing to search"
behavior the picker had before option 3 shipped. `updateCategory`
(`model.go`) now treats a rune/space keypress as "jump straight into
`stageBrowse` unscoped, seeded with the typed text as the initial filter" —
arrow+Enter still drills into a category, but typing anywhere on that screen
now searches the whole catalog immediately, same as before option 3.

**Recommendation:** 1–4 all done. Remaining Phase F work, if any, would be
new findings from further use of the split categories and picker.

## Picker visual density vs. upstream Bubble Tea examples

Bubble Tea's own README demo (a `./demo` todo-list picker: `[ ] Plant
carrots`, `[x] See friends`, four items, generous blank lines between
sections, no borders, a single faint hint line) reads as calmer than
`wp-ops`'s picker, which wraps both the list and the preview in
`lipgloss.RoundedBorder()` panes (`model.go:43`) side by side inside an
alt-screen, with rows packed tightly.

Worth naming explicitly: **this is not an apples-to-apples comparison.**
The README demo is a 4-item toy built to be legible in a screenshot; the
`wp-ops` picker is rendering up to 66 filterable rows *and* a live
multi-section preview pane (usage/args/examples — `wpexec.PreviewBody`),
which is closer to real dense Bubble Tea tools (`gh dash`, `glow`) than to
the README's todo list. A literal style match isn't the goal.

What *is* borrowable regardless of density:

- More vertical whitespace around the header/footer (the demo never
  crowds text against the pane edge).
- Lighter chrome on the list pane specifically — a single outer border
  around the whole app, rather than two nested bordered boxes
  (`borderedPane` applied twice in `viewBrowse`), reads as less boxed-in.
- The footer hint style (`j/k, up/down: select • enter: choose • q, esc:
  quit`) is already close to what `wp-ops` does (`viewBrowse`'s footer
  string) — no change needed there.

This is a secondary polish item, best done alongside option #2 above (both
touch `viewBrowse`), not a prerequisite for it.

---

# Milestones

| # | Scope | Version | Status |
|---|---|---|---|
| M1 | Manifest spec, bash parser, `manifest lint`, backup + monitoring annotated | 3.10.0 | **Done**, merged (PR #134) |
| M2 | All 66 annotated; guided prompts; `@runs` replaces the hardcoded list | 3.11.0 | **Done** — groups 1–5 plus the 2 `trellis` stragglers annotated (64/66 total); guided prompts shipped in 3.13.0; CI lint wiring landed after. Only `mcp-server/*` (2, out of scope) remains unannotated |
| M3 | Go skeleton, catalog generator, shell + ansible executors; parity on `list`/`search`/`doctor`/`--json` | 4.0.0-beta | **Done**, merged to `main` (PR #140) — see `docs/m3-go-skeleton.md` for the full breakdown; all acceptance criteria met, parity script passing 8/8 |
| M4 | Remaining executors, Bubble Tea picker, completions, goreleaser + tap | 4.0.0 | **In progress** — tasks 1–4 done (PHP/snippet executors, picker PR #144, completions PR #145); tasks 5 (`docs` search) and 6 (goreleaser + tap) remain. See `docs/m4-go-cli-completion.md` |
| M5 | Shared site registry, `--on <env>` SSH dispatch | 4.1.0 | Not started |
| M6 | `trellis-wpops` symlink | 4.1.0 | Not started |
| F | Command discovery: category-first default views, picker grouping | 3.20.0 | **In progress** — options 1–3 done, merged (PR #146); option 4 not started. See Phase F below |

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
