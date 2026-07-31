# M3: Go CLI Skeleton — Implementation Tracker

> **Status (2026-08-01):** Scoped, not started. This doc breaks M3 down into
> ordered, checkable tasks so it can be picked up across multiple sessions
> without re-deriving the plan each time. Parent plan: `docs/cli-ux-plan.md`
> (Phase C, milestone M3, target **4.0.0-beta**).

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
- [ ] Create `go/` with `go.mod` (module `github.com/imagewize/wp-ops/go`)
- [ ] Add `github.com/spf13/cobra` dependency
- [ ] `go/main.go` — bare Cobra root that builds and prints help
- [ ] `.gitignore` entries for Go build artifacts (`go/wp-ops`, etc.)

### 2. `internal/manifest` — directive parser + validator
Port of the bash `parse_manifest()` / `manifest_directive_lines()` logic
(`wp-ops:220`-area in the bash script — see parent plan's Phase A
implementation section for the original).
- [ ] `Command` struct: `Key, Desc, Category, Runs, Requires []string, Args
  []Arg, Flags []Flag, Examples []string, Doc string`
- [ ] `Arg`/`Flag` struct: `Name, Required bool, Choices []string, Default
  string, Description string`
- [ ] Parser for the `@arg`/`@flag` line shape: `NAME required|optional
  {choices-or-default} description` — same grammar as the bash version,
  see parent plan's "Directive format" section
- [ ] Comment-marker stripping for `#`, `//`, `*` (file-type-dependent, same
  as bash)
- [ ] Validator equivalent to `lint_manifest_command()` (`wp-ops:1900`) —
  not exposed as a CLI command in M3 (bash `manifest lint` stays
  authoritative until the bash CLI is retired at 4.0.0), but the same
  checks should live here so a later `go vet`-style lint command in M4+
  doesn't duplicate parsing logic
- [ ] Unit tests against a handful of real manifest blocks pulled from the
  existing annotated scripts (fixtures, not live file reads)

### 3. `internal/catalog` — build-time generator + embedded lookup
- [ ] Generator (`go/internal/catalog/gen/main.go`, invoked via
  `go:generate`) walks the repo the same way `discover_commands()`
  (`wp-ops:214`) does: same category directories, same file-type filter
  (`.sh`, `.yml`, `.php`, `.js`, `.py`)
- [ ] For annotated files: build a `Command` via `internal/manifest`
- [ ] For un-annotated files (`mcp-server/*`): fallback first-comment-line
  scrape, matching decision #2 above
- [ ] Emit `catalog.json`, embedded via `go:embed`
- [ ] Lookup/search API: by exact key (`category/command`), by
  short-form disambiguation, and substring search over key+description
  (backs `search`)
- [ ] Build fails (not degrades) on a malformed manifest — per parent
  plan's "Build-time catalog" note

### 4. `internal/detect`
Port of:
- [ ] `detect_trellis_dir` (`wp-ops:593`)
- [ ] `detect_wp_site_dir` (`wp-ops:627`)
- [ ] Same confirmation-prompt behavior when detection is ambiguous

### 5. `internal/exec/shell.go`
- [ ] Direct exec for `.sh` / `.js` / `.py` commands: resolve interpreter,
  build argv, inherit stdio, propagate exit code
- [ ] Same argument passthrough model as bash: `wp-ops <key> <args...>` →
  `script <args...>`, no re-parsing of the script's own flags

### 6. `internal/exec/ansible.go`
Port of `execute_playbook()` (`wp-ops:710`).
- [ ] Build `ansible-playbook <path> -e site=<site> -e env=<env>` plus any
  `@flag`-declared `-e key=value` extras
- [ ] `--help` renders from the manifest (no probe, no short-circuit bug —
  this is the bug class fixed in bash across 3.11.0–3.12.0; the Go version
  should never have it since it's manifest-first by construction)

### 7. Cobra command wiring (`main.go`)
- [ ] Dynamic registration: one `cobra.Command` per catalog entry, built
  from its `Args`/`Flags` — real typed flags, not a single blank arguments
  box. Execution still shells out to the existing script; Cobra only owns
  parsing/help/completion scaffolding (per parent plan's Framework
  rationale)
- [ ] `wp-ops <category>/<command> [args...]` (full key form)
- [ ] `wp-ops <category> <command> [args...]` (short form, e.g. `wp-ops
  backup db example.com production`)
- [ ] `wp-ops` (no args) / `list` — categorized listing from the catalog
- [ ] `wp-ops search <term>`
- [ ] `wp-ops doctor` — checks each command's `@requires` binaries are on
  `PATH`, port of `wp-ops:1394`
- [ ] `wp-ops --json list` — **exact field parity** with the bash
  `--json` output (`runs_on`, `requires`, `doc`, etc. — see parent plan
  "Compatibility")
- [ ] `wp-ops --where <command>` — resolves and prints the script path
- [ ] Ambiguous-basename resolution (`wp-ops:1105`) and did-you-mean
  (`wp-ops:1136`)

### 8. Parity verification
- [ ] A comparison script (bash) that runs both binaries' `--json list`,
  `search <term>` (a fixed set of terms), and `doctor` output side by side
  and diffs them — not a permanent test suite, just an M3 acceptance check
- [ ] Manual pass: run a handful of real commands (one per executor type
  implemented — a `scripts/*` `.sh`, a `trellis/**/*.yml`) through the Go
  binary end to end

### 9. CI
- [ ] `.github/workflows/go-build.yml` — `go build ./...`, `go vet ./...`,
  `go test ./...` on push/PR to `main`, scoped to the `go/` directory.
  Separate workflow from `manifest-lint.yml` (different toolchain, should
  fail independently)

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

- `go build ./...` produces a working binary from `go/`
- `catalog.json` is generated at build time from all 66 discoverable
  commands (64 annotated + 2 fallback-scraped), matching bash's
  `get_all_commands` set exactly
- `list`, `search`, `doctor`, and `--json list` produce output equivalent
  to the bash CLI's (per the parity verification script)
- At least one `scripts/**` `.sh` command and one `trellis/**/*.yml`
  command run successfully end to end through the Go binary
- CI is green on `go build`/`vet`/`test`
