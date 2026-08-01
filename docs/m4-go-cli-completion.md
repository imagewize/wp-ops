# M4: Go CLI Completion — Implementation Tracker

> **Status (2026-08-01):** In progress. Task 1 (`internal/exec/wpcli.go`)
> and task 2 (`internal/exec/snippet.go`) are done. Scoped out of M3
> (`docs/m3-go-skeleton.md`, "Explicitly out of scope for M3") now that M3
> is merged to `main` (PR #140). Parent plan: `docs/cli-ux-plan.md`
> (Phase C, milestone M4, target **4.0.0**).

## Goal

> Remaining executors, Bubble Tea picker, completions, goreleaser + tap.

M3 shipped the Go skeleton with two of four executors (`shell.go` for
`.sh`/`.js`/`.py`, `ansible.go` for `.yml`) and non-interactive parity on
`list`/`search`/`doctor`/`--json`. The bash CLI (`wp-ops`) is still the
only way to run a `wp-cli/**` `.php` command or a `wordpress-utilities/**`
snippet, and the only way to get an interactive picker or shell
completions — the Go binary currently tells the user to fall back to bash
for those (`go/cmd/dispatch.go:132-140`). M4 closes that gap and makes the
Go binary the complete, installable replacement.

The bash CLI keeps working untouched throughout M4, same as M3 — it is
deleted only at 4.0.0 once the Go binary has full parity. See "Risks —
Dual maintenance during M3–M4" in the parent plan.

## Open decisions (resolve before/while implementing)

1. **Script distribution: embed vs. locate.** Parent plan's Phase C section
   already frames this and recommends **(a) embed** (`go:embed` the script
   tree, extract to a cache dir on first run, `WP_OPS_ROOT` as a dev
   override) over **(b) locate the checkout** (resolve a repo root as
   today). This decision gates the goreleaser/tap task below — a
   `brew install wp-ops` user has no checkout to locate. Confirm (a) before
   starting that task; `internal/detect` (M3) already ports the checkout
   -location path for the `WP_OPS_ROOT` dev-override case either way.
2. **`docs` search command.** Deferred from M3 (open decision #3 there)
   with a note that it's likely cheap to add alongside `search` since both
   walk the same catalog. Confirm it's still in scope for M4 — the
   milestone table's M4 row doesn't explicitly list it, but the parent
   plan's general "Carried over from the bash CLI" list does
   (`docs` search at `wp-ops:1235-1346`). **Recommendation:** include it;
   low incremental cost once `internal/catalog`'s search API exists.
3. **Bubble Tea picker scope.** Bash's interactive surface is actually two
   things: `fzf_menu()` (delegates to the `fzf` binary when present) and
   `interactive_command_menu()` (a plain-bash fallback picker when `fzf`
   isn't installed), both feeding into the shared
   `prompt_manifest_args()` guided per-argument prompting from M2. Decide
   whether the Bubble Tea picker replaces both paths with one
   implementation (recommended — that's the whole point of dropping the
   `fzf` dependency) or only replaces the `fzf` path and keeps a bare
   fallback. **Recommendation:** one Bubble Tea implementation, no `fzf`
   dependency at all post-M4.
4. **Typed flags vs. `DisableFlagParsing`.** M3's task 7 note flags this
   explicitly: per-entry Cobra commands currently use
   `DisableFlagParsing: true` and pass args through raw. If the Bubble Tea
   picker wants to render per-`@flag` prompts the way `prompt_manifest_args`
   does in bash, decide whether it reads `catalog.Entry.Flags` directly
   (no Cobra flag involvement, recommended — keeps the raw passthrough
   M3 chose) or whether picker-driven runs need real typed flags after all.

## Task breakdown

Ordered by dependency — each task assumes the ones above it exist. Unlike
M3, these four are largely independent of each other (no shared
foundation task like `internal/manifest`/`internal/catalog`); order here is
by how directly each blocks "the Go binary can replace bash," not by a
hard technical dependency.

### 1. `internal/exec/wpcli.go`
Port of `execute_php_command()` (`wp-ops:1146`). **Done.**
- [x] Detect `extends WP_CLI_Command` in the script source; if present,
  resolve the registered command name (port of
  `get_registered_wp_command()`, `wp-ops:1140`) and invoke via
  `wp --require=<script> <registered-command> [args...]`; otherwise
  `wp eval-file <script> [args...]` — `RegisteredWPCommand()` /
  `RunWPCLI()` in `wpcli.go`
- [x] Run from `$WP_SITE_DIR` (port of `require_wp_site_dir()`,
  `wp-ops:1109`) — fail clearly if unset/undetected, same as bash.
  `resolveWPSiteDir()` in `go/cmd/wpsite.go` mirrors `resolveTrellisDir()`
  (M3), reusing `internal/detect.WPSiteDir()` and `detect.Confirm()`
- [x] Fail clearly if `wp` isn't on `PATH` before attempting anything —
  `WPAvailable()`, checked in `executeWPCLI()` before site-dir resolution
- [x] `--help` renders from the manifest (`internal/exec/help.go`'s shared
  renderer, extended with the "Runs via WP-CLI against..." / "Runs as:
  wp ..." lines bash prints), no probe — same manifest-first-by-construction
  property ansible.go already has, so there's no short-circuit bug class to
  worry about here. `FormatWPCLIHelp()`
- [x] Wire into `go/cmd/dispatch.go`: `ext == ".php"` now dispatches to
  `executeWPCLI()` instead of the M4 stub message (the stub remains for
  `wordpress-utilities/*` pending task 2)
- [x] Unit tests mirroring `internal/exec/ansible_test.go`'s shape:
  `wpcli_test.go` covers `RegisteredWPCommand` (WP_CLI_Command subclass,
  plain script, missing file) and `FormatWPCLIHelp` (eval-file form,
  --require form, site-dir-not-set). Manual pass: both `--help` forms
  rendered correctly end to end (`wp-cli/security/scanner-targeted`,
  `bedrock/wp-cli-config/wp-cli-pattern-validate`), and the
  `WP_SITE_DIR`-not-a-directory failure path was exercised

### 2. `internal/exec/snippet.go`
Port of `execute_snippet()` (`wp-ops:1232`) — covers `wordpress-utilities/**`. **Done.**
- [x] Default (no args): print to stdout. Match bash's TTY-aware
  formatting (filename header + trailing reference-snippet notice
  on a terminal; raw file content only when piped/redirected, so
  `wp-ops ... > footer.php` still works) — `PrintSnippet()` in
  `snippet.go`. Go port drops bash's ANSI dimming, matching the rest of
  the Go CLI's plain-text convention (`printCompletionBanner` etc.)
- [x] `--path`: print only the resolved file path
- [x] `--copy`: copy to clipboard. Port `find_clipboard_cmd()`
  (`wp-ops:1220`) — `pbcopy` (macOS) → `xclip`/`xsel` (Linux) →
  `clip.exe` (WSL/Windows) — fail with the same "no clipboard tool found,
  try --path instead" message if none are on `PATH` — `clipboardCmd()` /
  `CopySnippet()`
- [x] `--help` renders from the manifest, plus the fixed "this is a
  reference snippet, not run directly" explanation and the three-line
  usage block bash prints (`wp-ops <key>`, `--copy`, `--path`) —
  `FormatSnippetHelp()`
- [x] Wire into `go/cmd/dispatch.go`: replaced the
  `strings.HasPrefix(e.Key, "wordpress-utilities/")` early return with
  `executeSnippet()`. Also fixed an ordering bug found while wiring this
  up: the `ext == ".php"` check ran before the `wordpress-utilities/`
  prefix check, so `wordpress-utilities/**.php` snippets (3 of the 5
  non-doc files in that tree) were silently executed via WP-CLI instead
  of printed/copied. The category-prefix check now runs first.
- [x] Unit tests: `--path`/`--copy`/default branches, clipboard-tool
  fallback chain (mock `exec.LookPath`), TTY vs. piped output shape —
  `snippet_test.go`. Manual pass: `--help`/`--path`/default/`--copy` all
  exercised end to end against a real annotated `.php` snippet
  (`wordpress-utilities/snippets/post-expiry-noindex`), a non-`.php`
  snippet pair (`.css`/`.js` in `wordpress-utilities/age-verification/`),
  and a plain-file `.php` snippet (`age-verification/footer`) to confirm
  the ordering fix

### 3. `internal/ui` — Bubble Tea interactive picker
Replaces the `fzf`-dependent `fzf_menu()` (`wp-ops:1477`) and its
no-`fzf` fallback `interactive_command_menu()` (`wp-ops:1563`), per open
decision #3.
- [ ] Category → command list navigation, filterable by typing (the `fzf`
  UX bash currently shells out for)
- [ ] Curated preview pane per M1/Phase A: manifest-rendered usage/args
  /examples (`internal/exec/help.go`'s body renderer already produces
  this text — reuse it verbatim, don't re-derive)
- [ ] Guided per-`@arg`/`@flag` prompting on selection, port of
  `prompt_manifest_args()` (`wp-ops:1477`-area helper added in M2/3.13.0):
  one prompt per declared arg/flag showing description + choices/default
  inline, reprompt on blank required field, "Additional arguments"
  catch-all at the end for anything not expressible as a single manifest
  line (repeatable flags, etc. — same limitation bash's version has)
- [ ] No-manifest commands keep a plain free-text prompt, same fallback
  bash uses
- [ ] Launches when `wp-ops` runs with no args on an interactive terminal
  (`main()`'s `[[ -t 0 && -t 1 ]]` check, `wp-ops:2148`) — non-interactive
  (piped/redirected) keeps printing `list`-equivalent output
- [ ] Manual pass: run the picker end to end for one command per executor
  type (`.sh`, `.yml`, `.php` post-task-1, snippet post-task-2), same
  spirit as M3's task 8 manual pass

### 4. Shell completions
Replaces the hand-written `print_completion()` (`wp-ops:2098`, bash-only).
- [ ] Wire Cobra's built-in `completion` command (bash/zsh/fish/PowerShell)
  — largely free once the command tree is fully populated (it already is,
  post-M3), but verify the dynamically-registered per-entry commands
  (`DisableFlagParsing: true`, M3 task 7) complete correctly; Cobra's
  default completion may need `ValidArgsFunction` hints since flag
  parsing is disabled
- [ ] Category → basename two-token completion (`wp-ops <category>
  <TAB>` → basenames in that category), matching bash's actual grammar
  ported in M3 task 7, not the flatter completion bash's
  `print_completion()` implements today
- [ ] Manual pass: source the generated completion script in bash and zsh,
  confirm category and basename completion both work

### 5. `docs` search command
Deferred from M3 per open decision #2 above; port of `docs` search
(`wp-ops:1235-1346`) if decision #2 confirms it's in scope.
- [ ] Walk `@doc` references from the catalog (already populated by M3's
  `internal/catalog`) plus a full-text search fallback over doc files,
  matching bash's behavior
- [ ] `wp-ops docs <term>` prints matching doc paths/excerpts

### 6. `goreleaser` + Homebrew tap distribution
Gated on open decision #1 (embed vs. locate).
- [ ] If embed: `go:embed` the script tree (everything under the category
  directories in `catalog.Categories`), extract to a cache dir
  (`~/.cache/wp-ops` or platform equivalent) on first run;
  `internal/detect`'s `WP_OPS_ROOT` env var overrides for development,
  pointing at a live checkout instead of the extracted copy
- [ ] `.goreleaser.yml`: build matrix (darwin/linux, amd64/arm64 at
  minimum), archive naming, checksums
- [ ] Homebrew tap: `imagewize/tap` formula, `brew install
  imagewize/tap/wp-ops`
- [ ] Update `install.sh` or superseded by `brew install` instructions —
  decide whether `install.sh`'s PATH-append approach stays as a
  no-Homebrew fallback or is retired
- [ ] CI: goreleaser run on tag push, separate from `go-build.yml`

## Explicitly out of scope for M4

Don't let these creep in — they're later phases per the parent plan's
milestone table:

- `internal/registry` / shared site registry / `--on <env>` SSH dispatch
  (Phase D, M5)
- `trellis-wpops` symlink (Phase E, M6)
- Deleting the bash CLI — stays authoritative and untouched until 4.0.0
  ships with full Go parity

## Acceptance criteria for M4 done

- [ ] `wp-cli/**` `.php` commands and `wordpress-utilities/**` snippets run
  end to end through the Go binary (one of each, minimum)
- [ ] Interactive picker launches on a bare `wp-ops` invocation with no
  `fzf` binary required, with guided per-argument prompting matching M2's
  bash UX
- [ ] Generated completions work in at least bash and zsh
- [ ] `brew install imagewize/tap/wp-ops` (or the chosen distribution path
  per open decision #1) produces a working, self-contained binary
- [ ] `docs` search, if in scope per open decision #2, matches bash output
- [ ] CI green on all of the above (`go-build.yml` plus any new
  goreleaser workflow)
