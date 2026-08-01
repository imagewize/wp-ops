# M4: Go CLI Completion — Implementation Tracker

> **Status (2026-08-01):** **M4 is complete and shipped**, all 6 tasks
> done. Task 6 (goreleaser + Homebrew tap) merged in PR #150, resolving
> open decision #1 in favor of **(a) embed**: `go.mod`/`go.sum` moved from
> `go/` to the repo root (module renamed `github.com/imagewize/wp-ops/go` →
> `github.com/imagewize/wp-ops`; no import paths changed, since the
> directory layout under `go/` didn't move) so a new root-level `assets`
> package (`assets.go`) could `//go:embed` the command-carrying directories
> — `go:embed` can't ascend directories or cross the module boundary
> `go/go.mod` used to impose. `repoRoot()` (`go/cmd/env.go`) gained a third
> fallback tier, `extractedAssetsRoot()`, below `WP_OPS_ROOT` and live-
> checkout detection: it extracts the embedded tree to a version-stamped
> `~/.cache/wp-ops` directory on first run and reuses it after. `.goreleaser.yml`
> publishes a `homebrew_casks` entry (`brews` is hard-deprecated as of
> goreleaser v2.16) to a tap repo; `.github/workflows/release.yml` runs it
> on `v*` tag pushes.
>
> The first real tagged release (`v3.23.0`) surfaced two bugs PR #150's
> local testing (a `goreleaser --snapshot` dry run, no actual publish)
> couldn't have caught, fixed in follow-up PR #151: (1) the tap repo has to
> be named `imagewize/homebrew-tap` on GitHub — Homebrew's naming
> convention maps the short `imagewize/tap` form used in `brew
> tap`/`brew install` to a repo literally prefixed `homebrew-`; it was
> created as plain `imagewize/tap` and renamed to match; (2) the binary
> isn't code-signed or notarized (no Apple Developer ID), so macOS
> quarantines it on download and Gatekeeper killed it outright on first
> run (`exit 137`) instead of prompting to allow it — a `homebrew_casks`
> `hooks.post.install` now strips `com.apple.quarantine` from the staged
> binary, the standard goreleaser fix for an unsigned CLI cask. Both tags
> (`v3.23.0`, then `v3.23.1`) were deleted and recreated while iterating on
> these fixes — safe pre-launch since there were no real consumers yet.
>
> **`brew install imagewize/tap/wp-ops` is now confirmed working end to
> end at v3.23.1** — verified `wp-ops --version`, `wp-ops search`, and a
> real script invocation (`scripts/git/git-log-oneline --help`), all
> against the actual installed binary run in isolation (empty `HOME`, no
> repo checkout anywhere nearby), confirming the embedded-asset extraction
> path works for a genuine brew-installed user, not just in a local test
> harness. Parent plan: `docs/cli-ux-plan.md` (Phase C, milestone M4,
> target **4.0.0**).

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
   dependency at all post-M4. **Resolved (task 3):** one implementation
   (`internal/ui`), no `fzf` dependency added — `go.mod` only gained
   `bubbletea`/`bubbles`/`lipgloss`.
4. **Typed flags vs. `DisableFlagParsing`.** M3's task 7 note flags this
   explicitly: per-entry Cobra commands currently use
   `DisableFlagParsing: true` and pass args through raw. If the Bubble Tea
   picker wants to render per-`@flag` prompts the way `prompt_manifest_args`
   does in bash, decide whether it reads `catalog.Entry.Flags` directly
   (no Cobra flag involvement, recommended — keeps the raw passthrough
   M3 chose) or whether picker-driven runs need real typed flags after all.
   **Resolved (task 3):** reads `catalog.Entry.Args`/`.Flags` directly
   (`internal/ui/fields.go`); Cobra flag parsing is untouched.

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
decision #3. **Done.**
- [x] Category → command list navigation, filterable by typing (the `fzf`
  UX bash currently shells out for) — a flat list sorted/filtered via
  `catalog.Search` (keys are already category-prefixed, so filtering
  naturally groups by category); every rune keypress re-filters instantly,
  no `/`-to-filter mode switch. `Model.updateBrowse` in `internal/ui/model.go`
- [x] Curated preview pane per M1/Phase A: manifest-rendered usage/args
  /examples (`internal/exec/help.go`'s body renderer already produces
  this text — reuse it verbatim, don't re-derive) — `internal/exec/help.go`
  gained `PreviewBody()`, extracted from the existing `writeManifestHelpBody`
  used by all three executors' own `--help`, so the picker's preview and
  `--help` output can never drift
- [x] Guided per-`@arg`/`@flag` prompting on selection, port of
  `prompt_manifest_args()` (`wp-ops:1477`-area helper added in M2/3.13.0):
  one prompt per declared arg/flag showing description + choices/default
  inline, reprompt on blank required field, "Additional arguments"
  catch-all at the end for anything not expressible as a single manifest
  line (repeatable flags, etc. — same limitation bash's version has) —
  pure logic ported into `internal/ui/fields.go` (`buildFields`/
  `resolveField`, unit-tested) and driven by `Model.updatePrompt`
- [x] No-manifest commands keep a plain free-text prompt, same fallback
  bash uses — `buildFields` returns nil for any entry with no declared
  `@arg`/`@flag` (annotated or not), which `beginPrompting` routes straight
  to the free-text stage
- [x] Launches when `wp-ops` runs with no args on an interactive terminal
  (`main()`'s `[[ -t 0 && -t 1 ]]` check, `wp-ops:2148`) — non-interactive
  (piped/redirected) keeps printing `list`-equivalent output —
  `rootRunE` in `go/cmd/root.go`, gated on `detect.IsTerminal(os.Stdin) &&
  detect.IsTerminal(os.Stdout)`; `go/cmd/interactive.go`'s `runInteractive`
  owns the "pick another command?" outer loop (port of `interactive_menu`'s
  loop, wp-ops:2001-2013), running the selected command only after the
  Bubble Tea program has released the terminal, same as `fzf_menu` exiting
  before `execute_command` runs (wp-ops:1993-1997)
- [x] Manual pass: run the picker end to end for one command per executor
  type (`.sh`, `.yml`, `.php` post-task-1, snippet post-task-2), same
  spirit as M3's task 8 manual pass — driven via `expect` against the real
  binary (no fzf/bubbletea test harness needed a TTY substitute): a `.sh`
  command (`scripts/git/git-log-oneline`) end to end including a
  non-default guided value (`n`=5, verified exactly 5 commits printed) and
  the "Pick another command?" loop; a `.yml`/Ansible command
  (`trellis/backup/database-backup`) through its two required args,
  including the blank-required-field reprompt; a `.php`/WP-CLI command
  (`wp-cli/security/scanner-targeted`) reaching `executeWPCLI` and failing
  clearly on unset `WP_SITE_DIR`, same as direct invocation; a
  `wordpress-utilities` snippet with no declared args
  (`post-expiry-noindex`) through the free-text fallback to a full
  successful completion. Also verified: Esc-to-quit from the browse list,
  Ctrl+C-to-quit from a field prompt, and an empty filter query's "No
  matches" state

### 4. Shell completions
Replaces the hand-written `print_completion()` (`wp-ops:2098`, bash-only). **Done.**
- [x] Wire Cobra's built-in `completion` command (bash/zsh/fish/PowerShell)
  — free once the command tree is fully populated (it already was, post-M3):
  Cobra registers it automatically since `rootCmd` doesn't set
  `CompletionOptions.DisableDefaultCmd`. Verified the dynamically-registered
  per-entry (full-key, hidden) leaf commands complete without error despite
  `DisableFlagParsing: true` — positional args fall back to
  `ShellCompDirectiveDefault` (file completion, a reasonable default for
  scripts that mostly take paths), and `--<TAB>` correctly returns
  `ShellCompDirectiveNoFileComp` rather than leaking bogus flag suggestions.
  No `ValidArgsFunction` needed for these; the open decision's concern
  didn't end up applying in practice.
- [x] Category → basename two-token completion (`wp-ops <category>
  <TAB>` → basenames in that category), matching bash's actual grammar
  ported in M3 task 7, not the flatter completion bash's
  `print_completion()` implements today — `categoryBasenameCompletions()`
  in `dispatch.go`, wired as each category command's `ValidArgsFunction`:
  returns every basename in the category (deduplicated) when completing the
  first arg, `ShellCompDirectiveNoFileComp` with no candidates for anything
  past that — matching bash's `cword >= 3` → `COMPREPLY=()`, since
  everything after the basename belongs to the underlying script's own
  argv, not to wp-ops. Unit-tested (`dispatch_test.go`).
- [x] Manual pass: source the generated completion script in bash and zsh,
  confirm category and basename completion both work — zsh verified with a
  real `compinit` + sourced completion script driven via `expect` (TAB
  against `wp-ops scripts <TAB>` and `wp-ops scripts db<TAB>`, confirming
  both the full category list and prefix-filtered single-match
  autocomplete); bash needed two things installed first that a stock macOS
  shell lacks — Homebrew `bash` (macOS ships bash 3.2, frozen since 2007
  over the GPLv3 relicense, which Cobra's generated script can't run even
  with `bash-completion` installed) and the `bash-completion` package
  itself — then verified the same way. `wp-ops doctor` now reports both
  (see below) so this isn't a silent trap for the next person testing on a
  clean Mac.

### 5. `docs` search command
Deferred from M3 per open decision #2 above; port of `docs` search
(`wp-ops:1610-1736`, dispatch at `wp-ops:2196-2211`). **Done.**
- [x] Full-text search over every `*.md` file in the repo (excluding
  `.git`/`node_modules`/`vendor`), independent of any command's manifest —
  the `@doc` per-command directive (`catalog.Entry.Doc`) is a separate,
  already-shipped feature (surfaced in executors' `--help` and `--json`
  since M2/M3); `docs` search never reads it. New `go/cmd/docs.go`:
  `findDocs` (file discovery), `compileDocTerm` (case-insensitive, or
  whole-word via `-w`/`--word`), `searchDocFile`/`searchDocs` (per-file and
  aggregate matching, `grep -c` semantics — match count is lines, not
  occurrences)
- [x] `wp-ops docs [term]` prints matching doc paths/excerpts: no term lists
  every doc file; a term prints each matching file with its match count and
  up to 3 matching lines (collapsed whitespace, truncated to 96 chars) plus
  a "… N more" summary; `-l`/`--files`/`--paths` prints matching paths only
- [x] `wp-ops search`'s "no command matches" path regains the "the
  documentation mentions it though" cross-reference into `docs` search
  (`hasDocMatches` in `docs.go`), closing the gap `search.go`'s doc comment
  flagged when `search` was ported ahead of `docs` landing
- [x] Unit tests (`go/cmd/docs_test.go`): file discovery/exclusion,
  case-insensitive vs. whole-word matching, whitespace collapsing/
  truncation, match-count-is-lines-not-occurrences. Manual pass: term
  search, `-w`, `-l`, no-term listing, and no-match all verified against the
  real repo tree; `go/scripts/parity-check.sh` still 8/8 (`docs` isn't part
  of that contract — bash's own output there is hand-formatted prose, not a
  stable interface, same reasoning `search`/`doctor` already use)

### 6. `goreleaser` + Homebrew tap distribution
Gated on open decision #1 (embed vs. locate). **Done**, merged in PR #150,
with two follow-up distribution bugs fixed in PR #151 (see the status
banner above) — `brew install imagewize/tap/wp-ops` confirmed working end
to end at v3.23.1.
- [x] Embed resolved: `go.mod`/`go.sum` moved from `go/` to the repo root
  (module renamed to bare `github.com/imagewize/wp-ops`, directory layout
  and all existing import paths unchanged) so a new root-level `assets`
  package (`assets.go`) can `//go:embed` `catalog.Categories`' directories
  plus `docs/` and the root guide files — `go:embed` can't reach outside
  the module a source file lives in, and `go/go.mod` previously made `go/`
  its own module boundary, putting the script tree out of reach. `WP_OPS_ROOT`
  keeps working exactly as before (checked first, ahead of both live-checkout
  detection and the new embedded fallback) — `repoRoot()` in `go/cmd/env.go`
  now has three tiers instead of two. New `extractedAssetsRoot()` extracts
  to `os.UserCacheDir()/wp-ops/assets-<version>` (version read straight off
  the embedded `CHANGELOG.md`, since `repoRoot()` isn't resolved yet at that
  point) via a temp-dir-then-rename so concurrent invocations can't race on
  a partial extract; `.sh`/`.py`/`.js` files get the executable bit back on
  extraction (`internal/exec/shell.go` execs them directly), `.php`/`.yml`
  don't need it. Unit-tested (`go/cmd/env_test.go`); manually verified by
  copying a built binary outside the checkout and running it with `HOME`
  pointed at an empty directory — both `--version` and a real script
  (`scripts/git/git-log-oneline`) worked purely off the embedded tree, with
  the cache dir populated as expected.
- [x] `.goreleaser.yml`: darwin/linux × amd64/arm64 build matrix, `tar.gz`
  archives (bundling `LICENSE.md`/`README.md`/`CHANGELOG.md`), checksums.
  Verified with `goreleaser check` and a `goreleaser release --snapshot
  --clean --skip=publish` dry run — all 4 binaries built and ran correctly.
- [x] Homebrew tap: created as `imagewize/tap`, then renamed to
  `imagewize/homebrew-tap` (PR #151) — Homebrew's tap-naming convention
  maps the short `imagewize/tap` form used in `brew tap`/`brew install` to
  a repo literally prefixed `homebrew-`; the plain `tap` name silently
  fails with "Repository not found" at install time, only caught by
  actually running `brew install`. Publishes via goreleaser's
  `homebrew_casks` section, **not** `brews` — hard-deprecated as of
  goreleaser v2.16 (https://goreleaser.com/deprecations/#brews) in favor of
  casks for precompiled-binary distribution regardless of GUI-vs-CLI.
  Cross-repo push needs a token wider than the default `GITHUB_TOKEN`;
  `repository.token` templates in `HOMEBREW_TAP_GITHUB_TOKEN` from the
  environment — creating that PAT also surfaced that `imagewize`'s org
  policy requires fine-grained PATs to be granted **Contents: Read and
  write** explicitly (the default/first attempt was Read-only, which 403s
  on the cask file push; org-level "require administrator approval" was
  already off, so that wasn't the blocker it first looked like).
  Also added a `hooks.post.install` stripping `com.apple.quarantine` from
  the staged binary (PR #151) — it isn't code-signed or notarized, so
  macOS quarantines it on download and Gatekeeper killed it outright
  (`exit 137`) on first run without the strip.
- [x] `install.sh` decision: kept as the no-Homebrew fallback —
  `README.md`'s "wp-ops CLI" section shows `brew install
  imagewize/tap/wp-ops` first, `install.sh` second.
- [x] CI: new `.github/workflows/release.yml`, triggered on `v*` tag
  pushes, separate from `go-build.yml` (push/PR to `main`, never
  publishes). Exercised for real across `v3.23.0` (tap-push failed twice,
  see above) and `v3.23.1` (fully green, cask published, `brew install`
  verified).

## Explicitly out of scope for M4

Don't let these creep in — they're later phases per the parent plan's
milestone table:

- `internal/registry` / shared site registry / `--on <env>` SSH dispatch
  (Phase D, M5)
- `trellis-wpops` symlink (Phase E, M6)
- Deleting the bash CLI — stays authoritative and untouched until 4.0.0
  ships with full Go parity

## Acceptance criteria for M4 done

- [x] `wp-cli/**` `.php` commands and `wordpress-utilities/**` snippets run
  end to end through the Go binary (one of each, minimum) — task 1/2's
  manual passes above
- [x] Interactive picker launches on a bare `wp-ops` invocation with no
  `fzf` binary required, with guided per-argument prompting matching M2's
  bash UX — task 3's manual pass above
- [x] Generated completions work in at least bash and zsh
- [x] A binary built via the chosen distribution path (embed, per open
  decision #1) is working and self-contained — verified two ways: a
  binary copied outside the checkout with an empty `HOME` (task 6's local
  test), and a real `brew install imagewize/tap/wp-ops` at v3.23.1
  (`--version`/`search`/a real script invocation, all in isolation)
- [x] `docs` search, if in scope per open decision #2, matches bash output
- [x] CI green on all of the above — `go-build.yml` (module move verified
  with `go build`/`go vet`/`go test`/`parity-check.sh`) and `release.yml`
  (green at v3.23.1, after two failed attempts at v3.23.0 that surfaced
  and fixed the tap-name and quarantine bugs — see task 6)
