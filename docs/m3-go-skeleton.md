# M3: Go CLI Skeleton — Implementation Tracker

> **Status (2026-08-01):** Implemented on `feature/cli-manifest-m3-go-skeleton`,
> not yet merged. All nine task groups below are done: `go build ./...` from
> `go/` produces a working `wp-ops` binary; the embedded catalog matches
> bash's 66-command set field-for-field (`go/scripts/parity-check.sh` passes
> 8/8 checks, including a strict `--json list` diff); a `scripts/**/*.sh`
> command (`scripts/git/git-log-oneline`) and a `trellis/**/*.yml` command
> (`trellis/backup/database-backup`, exercised against a scratch Trellis
> project with a real `ansible.cfg`) both ran end to end through the Go
> binary; CI (`.github/workflows/go-build.yml`) is wired. See the per-task
> notes below for scoping calls made along the way (`internal/exec/wpcli.go`
> and `snippet.go` remain M4 as planned; the per-entry Cobra commands use
> `DisableFlagParsing` rather than typed flags — see task 7's note). Parent
> plan: `docs/cli-ux-plan.md` (Phase C, milestone M3, target **4.0.0-beta**).

## Goal

> Go skeleton, catalog generator, shell + ansible executors; parity on
> `list`/`search`/`doctor`/`--json`.

The bash CLI keeps working untouched throughout M3 — this is a second,
independent binary that reads the *same* manifests. Nothing in `wp-ops`
(the bash script) changes. See "Risks — Dual maintenance during M3–M4" in
the parent plan.

## Open decisions (resolve before/while implementing)

These aren't blocking the scope below, but they're calls a future session
needs to either confirm or revisit — flagging them explicitly so they don't
get silently decided by whoever picks this up next.

1. **Where the Go module lives.** Recommendation: a top-level `go/`
   directory (sibling to `mcp-server/`, following that same
   one-directory-per-non-bash-tool precedent already in this repo). Can't be
   `wp-ops/` — that name is taken by the existing bash script file at repo
   root. Module path: `github.com/imagewize/wp-ops/go`.
2. **`mcp-server/*` (2 commands) and catalog parity.** Phase A explicitly
   excludes `mcp-server/*` from manifest annotation. But bash
   `discover_commands()` still lists them via a fallback first-comment-line
   scrape, so `wp-ops list` includes them today. For the Go catalog
   generator to match `list`/`--json` output exactly, it needs either (a)
   the same fallback scrape for un-annotated files, or (b) finally
   annotating those 2 commands, ending the "out of scope" carve-out.
   **Recommendation: (a)** — replicate the fallback, keep the carve-out
   intact, don't let M3 quietly expand Phase A's scope.
3. **`docs` search command.** The parent plan's "Carried over" list
   (Phase C, general) includes `docs` search, but the M3 milestone row only
   commits to `list`/`search`/`doctor`/`--json`. **Recommendation:** defer
   `docs` to M4, matching the milestone table's literal scope. Revisit if a
   future session finds it's cheap to include alongside `search` (both walk
   the same catalog).
4. **Go version / module pinning.** No constraint from the rest of the repo
   (it's not currently a Go consumer of anything). Recommendation: current
   stable Go at time of implementation, no need to pin low.

## Task breakdown

Ordered by dependency — each task assumes the ones above it exist.

### 1. Module scaffold
- [x] Create `go/` with `go.mod` (module `github.com/imagewize/wp-ops/go`)
- [x] Add `github.com/spf13/cobra` dependency
- [x] `go/main.go` — bare Cobra root that builds and prints help
- [x] `.gitignore` entries for Go build artifacts (`go/wp-ops`, etc.) —
  `internal/catalog/catalog.json` is deliberately **not** ignored; see task
  3's note

### 2. `internal/manifest` — directive parser + validator
Port of the bash `parse_manifest()` / `manifest_directive_lines()` logic
(`wp-ops:220`-area in the bash script — see parent plan's Phase A
implementation section for the original). **Done.**
- [x] `Command` struct: `Key, Desc, Category, Runs, Requires []string, Args
  []Arg, Flags []Flag, Examples []string, Doc string` (plus an `Annotated
  bool`, the Go equivalent of bash's `has_manifest()`)
- [x] `Arg`/`Flag` struct: `Name, Required bool, Choices []string, Default
  string, Description string` — implemented as one shared `Param` type
  (`type Arg = Param`, `type Flag = Param`), mirroring how bash parses both
  with the same `manifest_parse_param_line()`
- [x] Parser for the `@arg`/`@flag` line shape: `NAME required|optional
  {choices-or-default} description` — same grammar as the bash version,
  see parent plan's "Directive format" section
- [x] Comment-marker stripping for `#`, `//`, `*` (file-type-dependent, same
  as bash)
- [x] Validator equivalent to `lint_manifest_command()` (`wp-ops:1900`) —
  `manifest.Lint()`. Not exposed as a CLI command in M3 (bash `manifest
  lint` stays authoritative until the bash CLI is retired at 4.0.0); reused
  by the catalog generator (task 3) to fail the build on a malformed
  manifest
- [x] Unit tests against a handful of real manifest blocks pulled from the
  existing annotated scripts (fixtures, not live file reads) —
  `go/internal/manifest/testdata/*` + `manifest_test.go`, covering choice
  args, boolean flags, unknown-directive tolerance, and every lint failure
  mode

### 3. `internal/catalog` — build-time generator + embedded lookup
**Done.** `go generate ./...` (from `go/`) produces a catalog matching
bash's discovery exactly — verified by `go/scripts/parity-check.sh`'s
`--json list` diff (66/66, zero field mismatches).
- [x] Generator (`go/internal/catalog/gen/main.go`, invoked via
  `go:generate`) walks the repo the same way `discover_commands()`
  (`wp-ops:214`) does: same category directories, same file-type filter
  (`.sh`, `.yml`, `.php`, `.js`, `.py`)
- [x] For annotated files: build a `Command` via `internal/manifest`
- [x] For un-annotated files (`mcp-server/*`): fallback first-comment-line
  scrape, matching decision #2 above (`fallbackDescription()` in `gen/main.go`,
  including bash's `clean_description()` trim/truncate rules)
- [x] Emit `catalog.json`, embedded via `go:embed` — **committed to the
  repo, not gitignored**: `go:embed` needs the file to exist for the
  package to type-check at all, which is a chicken-and-egg problem for a
  fresh clone otherwise (`go generate` itself fails to even compile the
  generator, since `gen/main.go` imports the `catalog` package). Committing
  it also lets CI catch drift with `git diff --exit-code` after
  regenerating (task 9)
- [x] Lookup/search API: by exact key (`category/command`), by
  short-form disambiguation (`FindByBasename`), and substring search over
  key+description (`Search`, backs `search`)
- [x] Build fails (not degrades) on a malformed manifest — per parent
  plan's "Build-time catalog" note. A bare "missing @desc" is deliberately
  *not* treated as fatal (that's the normal, expected shape of an
  un-annotated fallback-scrape command); only real malformations
  (bad `@runs`, malformed `@arg`/`@flag`, a dangling `@doc`) fail the
  generator

### 4. `internal/detect`
Port of: **Done**, with unit tests covering the sibling-checkout false
positive bash's comment calls out, the `$HOME` walk boundary, and both
confirm/refuse prompt paths.
- [x] `detect_trellis_dir` (`wp-ops:593`) — `TrellisDir()`
- [x] `detect_wp_site_dir` (`wp-ops:627`) — `WPSiteDir()`
- [x] Same confirmation-prompt behavior when detection is ambiguous —
  `Confirm()`, used by `cmd.resolveTrellisDir()` (task 7)

### 5. `internal/exec/shell.go`
**Done.**
- [x] Direct exec for `.sh` / `.js` / `.py` commands: resolve interpreter,
  build argv, inherit stdio, propagate exit code — relies on the shebang
  line (`os/exec.Command(scriptPath, args...)`), chmod'ing `+x` first if
  needed, exactly like bash's own generic dispatch branch
- [x] Same argument passthrough model as bash: `wp-ops <key> <args...>` →
  `script <args...>`, no re-parsing of the script's own flags

### 6. `internal/exec/ansible.go`
Port of `execute_playbook()` (`wp-ops:710`). **Done.**
- [x] Build `ansible-playbook <path> <args...>`, run from `$TRELLIS_DIR` —
  argument building (`-e site=...`, `-e env=...`, or any other
  `-e key=value` extras) is the caller's job (`cmd` package, task 7), same
  split of responsibility bash has between `execute_playbook()` and its
  callers
- [x] `--help` renders from the manifest (no probe, no short-circuit bug —
  this is the bug class fixed in bash across 3.11.0–3.12.0; the Go version
  never has it, being manifest-first by construction) — `FormatHelp()`,
  sharing its body renderer with the generic (non-ansible) help path in
  `internal/exec/help.go`

### 7. Cobra command wiring (`go/cmd/`, invoked from `main.go`)
**Done** — actual command tree lives under `go/cmd/` (`root.go`,
`dispatch.go`, `list.go`, `search.go`, `doctor.go`, `version.go`,
`trellis.go`, `env.go`), with `main.go` just calling `cmd.Execute()`.
- [x] Dynamic registration: one `cobra.Command` per catalog entry — **with
  a scoping deviation from the original wording here**: entries use
  `DisableFlagParsing: true` rather than real typed `cmd.Flags()`, so
  arguments pass through to the underlying script byte-for-byte unparsed
  (matching `internal/exec/shell.go`'s explicit non-goal of re-parsing a
  script's own flags, and safely handling flags a script accepts that
  aren't declared via `@flag`, e.g. `redirect-audit`'s repeatable `--url`).
  Cobra still owns the *tree* (routing, `Hidden` full-key commands,
  category commands) and each entry gets real generated `--help` text from
  its manifest via `internal/exec`'s help renderers — genuinely "not a
  single blank arguments box" even without typed flags. Revisit true typed
  flags if M4's interactive picker wants them for guided prompting.
- [x] `wp-ops <category>/<command> [args...]` (full key form) — one hidden
  root-level command per catalog entry
- [x] `wp-ops <category> <command> [args...]` (short form) — bash's actual
  grammar is exactly two tokens (category, then a bare basename resolved
  via `find_commands_by_basename`), *not* the nicer verb-based
  `wp-ops backup db example.com production` this section originally showed
  as an example — that phrasing was Phase D's (`--on <env>` SSH dispatch)
  aspirational syntax leaking in here; the real, ported grammar is
  `wp-ops <category> <basename> [args...]`, e.g. `wp-ops scripts
  db-backup example.com production`
- [x] `wp-ops` (no args) / `list` — categorized listing from the catalog
- [x] `wp-ops search <term>`
- [x] `wp-ops doctor` — checks each command's `@requires` binaries are on
  `PATH`, port of `wp-ops:1394`
- [x] `wp-ops --json list` (and bare `wp-ops --json`, matching bash) —
  **exact field parity** with the bash `--json` output (`runs_on`,
  `requires`, `doc`, etc.), verified by `go/scripts/parity-check.sh`
- [x] `wp-ops <command> --where` — resolves and prints the script path.
  Ported bash's *actual* behavior (`execute_command()` checks `--where` as
  the first arg *after* the resolved command, `wp-ops:1400`), not the
  `wp-ops --where <command>` global-flag phrasing this bullet originally
  used — bash has no top-level `--where` case in `main()`'s switch
- [x] Ambiguous-basename resolution (`wp-ops:1105`) and did-you-mean
  (`wp-ops:1136`) — `printAmbiguous()` / `suggestSimilar()` in
  `dispatch.go`, scored identically to bash's substring/prefix heuristic

### 8. Parity verification
**Done** — `go/scripts/parity-check.sh`, 8/8 checks passing.
- [x] A comparison script (bash) that runs both binaries' `--json list`,
  `search <term>` (a fixed set of terms), and `doctor` output side by side
  and diffs them — not a permanent test suite, just an M3 acceptance check.
  `--json list` gets a strict field-for-field diff (via a small embedded
  Python helper, comparing parsed JSON rather than raw text); `search` and
  `doctor` get a looser count-based comparison, since bash's output there
  is hand-formatted prose rather than a stable contract
- [x] Manual pass: run a handful of real commands (one per executor type
  implemented — a `scripts/*` `.sh`, a `trellis/**/*.yml`) through the Go
  binary end to end. `scripts/git/git-log-oneline` ran and printed real
  commits; `trellis/backup/database-backup` was exercised against a
  scratch directory with a bare `ansible.cfg` (`TRELLIS_DIR` override,
  since no real Trellis project was available in this environment) and
  `ansible-playbook` genuinely ran, hit `variable-check.yml`'s guards as
  expected, and returned a real play recap — confirms the dispatch
  mechanics (cwd, args, `-e` passthrough) are correct end to end even
  though the scratch project had no real inventory to complete against

### 9. CI
**Done.**
- [x] `.github/workflows/go-build.yml` — `go build ./...`, `go vet ./...`,
  `go test ./...` on push/PR to `main`, scoped to the `go/` directory (path
  filter on `go/**`). Separate workflow from `manifest-lint.yml` (different
  toolchain, fails independently). Also runs `go generate ./...` first,
  then `git diff --exit-code -- internal/catalog/catalog.json` to catch a
  forgotten regeneration after a manifest edit — see task 3's note on why
  `catalog.json` is committed rather than gitignored

## Explicitly out of scope for M3

Don't let these creep in — they're M4+ per the parent plan's milestone
table:

- `internal/exec/wpcli.go`, `internal/exec/snippet.go` (remaining
  executors — M4)
- `internal/ui` Bubble Tea picker, replacing fzf (M4)
- Shell completions (M4)
- `goreleaser` / Homebrew tap distribution (M4)
- `internal/registry` / site registry / `--on <env>` SSH dispatch
  (Phase D)
- `trellis-wpops` symlink (Phase E)
- `docs` search — deferred per open decision #3 above

## Acceptance criteria for M3 done

All met, on `feature/cli-manifest-m3-go-skeleton` (not yet merged):

- [x] `go build ./...` produces a working binary from `go/`
- [x] `catalog.json` is generated at build time from all 66 discoverable
  commands (64 annotated + 2 fallback-scraped), matching bash's
  `get_all_commands` set exactly
- [x] `list`, `search`, `doctor`, and `--json list` produce output
  equivalent to the bash CLI's (per the parity verification script —
  `go/scripts/parity-check.sh`, 8/8 checks passing, including a strict
  field-for-field `--json` diff)
- [x] At least one `scripts/**` `.sh` command and one `trellis/**/*.yml`
  command run successfully end to end through the Go binary (see task 8's
  manual-pass note)
- [x] CI is green on `go build`/`vet`/`test` (`.github/workflows/go-build.yml`,
  not yet exercised by an actual PR since this branch isn't pushed/opened yet)

**Remaining before merge:** push the branch and open a PR so CI actually
runs (only run locally so far); decide whether `go/internal/catalog/gen`
needs its own unit tests (currently only exercised transitively via
`catalog_test.go` + the parity script, not directly); consider whether the
simplified `serverSideGuardOK()`/`printServerSideGuidance()` in
`go/cmd/dispatch.go` (see its doc comment) is worth fleshing out to match
bash's fuller version before M4, or left as a documented gap.
