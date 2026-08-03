# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.27.0] - 2026-08-03

### Added

- **scripts/monitoring** - `ttfb-test.sh`: runs `curl` against a URL 5 times, averages TTFB/DNS/connect/SSL timings, rates the result against Google's Core Web Vitals TTFB benchmarks, and writes a detailed report with optimization recommendations to `audits/`. Adapted from `seo-strategy/tools/scripts/ttfb-test.sh`, generalized off the hardcoded `imagewize.com` default URL — the URL is now a required argument.
- **scripts/monitoring** - `remote-ttfb-ua.sh`: runs `curl` on the server itself over SSH (so local network distance doesn't skew the measurement), once per URL for each of the default, Googlebot, AhrefsBot, and Screaming Frog user agents. Adapted from `seo-strategy/tools/scripts/remote-ttfb-ua.sh`, generalized off the hardcoded `web@imagewize.com` SSH host and default URL list — both are now required arguments. Placed under `scripts/monitoring/` rather than `wordpress-utilities/speed-optimization/` (as `docs/wp-ops-recommendations.md` Gap 5 originally suggested) because the CLI treats every file under `wordpress-utilities/` as a copy-paste-into-a-theme reference snippet and never executes it; the speed-optimization README stays the docs home via `@doc`.
- **wp-cli/content-creation** - `import-page-draft.sh`: updates an *existing* WordPress page's content from an HTML draft, locally and/or in production, stripping Blade `{{-- ... --}}` doc-comments before import. Complements `page-creation.sh`, which only creates new pages. Adapted from `seo-strategy/tools/scripts/import-page-draft.sh`, generalized off the hardcoded `imagewize.com` paths — site name is now a positional argument, and the local Trellis/Bedrock checkout dirs come from `TRELLIS_DIR`/`SITE_DIR` env vars, matching `db-pull.sh`'s convention.
- **trellis/security** - `check-deny-ips.sh`: bulk-checks every individual IP already in a Trellis project's `deny-ips.conf.j2` against AbuseIPDB, so blocks that are no longer warranted (score dropped to 0, no recent reports) are easy to spot; CIDR subnet entries are skipped and reported as a count instead, since AbuseIPDB checks single IPs, not ranges. Adapted from `imagewize.com/scripts/check-deny-ips.sh`, generalized off the hardcoded conf path (now `TRELLIS_DIR`-relative) and dropped the original's hand-picked, site-specific hardcoded subnet IP list in favor of actually skipping subnets, matching what the script's own comment already claimed it did. Reuses `check-ips.sh`'s existing `trellis/security/.env` instead of introducing a second env file.

All four address the "Take" rows of Gap 5 in `docs/wp-ops-recommendations.md`, and are manifest-annotated and resolve by basename in both the bash and Go CLIs (`go/scripts/parity-check.sh` passes 8/8; `catalog.json` regenerated).

## [3.26.0] - 2026-08-03

### Added

- **scripts/backup** - `db-pull.sh`: positional-argument wrapper (`wp-ops db-pull example.com production`) that pulls a remote site's database into local development over SSH, adapted from `imagewize.com/scripts/pull-db.sh` and generalized — no hardcoded site table. Runs via `trellis vm shell` and reads both the remote and local `siteurl` at run time through WP-CLI instead of guessing URL suffixes, so it isn't tied to any one site's naming convention. Backs up the current development database before overwriting it, prompts for confirmation (`--yes`/`-y` to skip), and supports multisite via `--multisite` (scopes `search-replace` with `--url` and fixes `wp_blogs` domains). Complements the existing `trellis/backup/database-pull.yml` playbook, which stays the better fit for automated/scheduled pulls; `trellis/backup/README.md` now points at the script instead of its old hand-copied inline-bash template. Addresses Gap 2 of `docs/wp-ops-recommendations.md`.

## [3.25.1] - 2026-08-03

### Fixed

- **wp-ops** - `discover_commands()`'s `find` (the bash CLI's command-discovery walk) had the identical bug just fixed in the Go catalog generator: no exclusion for `node_modules`/`dist`/`.git`, so a machine with `mcp-server/node_modules` or `mcp-server/dist` present (both gitignored; a fresh checkout never has them, so this was latent) would scan every dependency and build-output file as a discoverable command. A doc-search `find` elsewhere in the same script already excluded `*/node_modules/*`/`*/vendor/*`/`*/.git/*` — `discover_commands()`'s own `find` just never got the same treatment. Added the matching `! -path` exclusions. `go/scripts/parity-check.sh` now passes 8/8 (previously would have failed the `--json list` field-for-field comparison, since the Go side — fixed in 3.25.0 — reported 67 while bash reported 1298+).

## [3.25.0] - 2026-08-03

### Added

- **mcp-server** - `mcp-server/run.sh`: new stdio-safe launcher for `mcpServers` client registration. Rebuilds `dist/` only when `src/*.ts` is newer (or `dist/index.js` is missing), sends build output to stderr, then `exec`s `node dist/index.js` so stdout carries nothing but the MCP JSON-RPC stream. Replaces registering a bare `node dist/index.js` directly, which never rebuilds, and avoids `npm start`, which risks mixing npm's own log lines into stdout ahead of the server's first message and corrupting stdio framing.
- **mcp-server** - `mcp-server/package.json`: added a `prestart` script (`tsc`) so `npm start` always rebuilds first. `start.sh` now relies on this instead of an explicit `npm run build` step.

### Fixed

- **mcp-server** - The MCP server's user-scoped registration in `~/.claude.json` pointed at `node dist/index.js` directly, so `src/*.ts` edits were silently ignored by already-registered clients until someone remembered to run `npm run build` by hand. Confirmed `dist/index.js` had in fact gone stale relative to `src/server.ts` and `src/tools/wpCli.ts` — the running server was missing the 3.24.0 enum-schema and read-only-allowlist work despite the changelog marking it done. Rebuilt, and repointed the registration at `mcp-server/run.sh`.
- **docs** - `docs/mcp-server-recommendations.md`: corrected several stale observations found while investigating the above — the server *was* already registered true user-scoped (not project-scoped as the doc claimed), and `config/sites.json` already covers `aseonomics.com`/`imagewize.com`/`demo.imagewize.com` (not just example.com). Documented the stale-build failure mode and its fix.
- **go** - `go/internal/catalog/gen/main.go`: the catalog generator's `filepath.WalkDir` never excluded any directory by name, so adding `mcp-server/run.sh` and regenerating on a machine with `mcp-server/node_modules`/`mcp-server/dist` present (both gitignored, both matched by the `mcp-server` category's `.js` extension filter) inflated `catalog.json` from 66 entries to 1298 — every dependency and build-output `.js` file got scanned as if it were a discoverable command. A fresh CI checkout never has those directories, so this was latent rather than previously triggered. New `excludedDirs` map (`node_modules`, `dist`, `.git`) makes the walk `filepath.SkipDir` into them regardless of local dev state; regenerated `catalog.json` is back to a correct 67 entries (66 + `mcp-server/run`).
- **go** - `go/internal/catalog/catalog_test.go`: `TestLoad`'s hardcoded entry-count assertion bumped 66 → 67 for the new `mcp-server/run` command.

### Changed

- **docs** - `CLAUDE.md`, `AGENTS.md`: AI co-authorship (`Co-Authored-By` trailers for Claude or Mistral) is now permitted in commit messages in this repo — previously explicitly disallowed.

## [3.24.0] - 2026-08-03

### Added

- **mcp-server** - `mcp-server/src/server.ts`: `site`/`env` tool parameters are now `z.enum(...)` built from the site registry at server start (`buildSiteEnvSchemas()`) instead of free-form `z.string()`, so an invalid site/env key is rejected before the call is made rather than costing a full round trip. Falls back to plain `z.string()` if the registry can't be loaded yet or is empty, so a fresh install without `config/sites.json` still starts.
- **mcp-server** - `mcp-server/src/tools/wpCli.ts`: expanded the read-only allowlist. `SAFE_READ_VERBS` gained `size`/`tables`/`verify-checksums`/`pluck` (covers `wp db size`, `wp db tables`, `wp core verify-checksums`, `wp option pluck`); a new `NESTED_RESOURCE_VERBS` allowlist covers commands where the verb is the third token because the second names a sub-resource (`wp cron event list`), without blindly trusting `args[2]` for every command — `wp option update list <value>` still correctly requires `confirm: true`.

### Changed

- **mcp-server** - `mcp-server/README.md`: recommend user-scoped MCP server registration in `~/.claude.json`; add Permissions section with pre-approval config for read-only tools (`redirect_audit`, `schema_audit`, `security_scan`, `wp_cli`); add Usage Tips covering multi-site registry and CLAUDE.md integration guidance.
- **docs** - `docs/mcp-server-recommendations.md`: mark items 1-8 as done. Items 5-6 (`wpBin`/`phpBin` override, `url` field + `site`/`env` on audits) turned out to already be implemented (predating this pass); items 7-8 are the new schema-enum and allowlist work above.

## [3.23.2] - 2026-08-01

### Changed

- **docs** - `docs/cli-ux-plan.md` and `docs/m4-go-cli-completion.md` now reflect M4's actual shipped state instead of the "not yet merged"/"not yet verified" wording written before PR #150 and #151 landed: `brew install imagewize/tap/wp-ops` is confirmed working end to end at v3.23.1, including the tap-repo-name fix, the Gatekeeper quarantine-strip hook, and the org PAT permission gotcha (fine-grained tokens default to read-only; the cask push needs `Contents: Read and write` explicitly) hit while setting up the release credentials. Root `README.md`'s "wp-ops CLI" intro drops the "not tagged yet" hedge and leads with `brew install` as the recommended path.

## [3.23.1] - 2026-08-01

### Fixed

- **go** - The Homebrew tap's real repo name is `imagewize/homebrew-tap`, not `imagewize/tap` — Homebrew's tap-naming convention maps the short `imagewize/tap` form used in `brew tap`/`brew install` commands to a repo literally prefixed `homebrew-`. `.goreleaser.yml`'s `repository.name` pointed at the wrong one, so the first real release's cask push landed nowhere; caught by an actual `brew install imagewize/tap/wp-ops` run. Also: the installed binary isn't code-signed or notarized (no Apple Developer ID), so macOS quarantines it on download and Gatekeeper killed it outright on first run (`exit 137`) instead of showing the usual "open anyway" prompt — a `homebrew_casks` `hooks.post.install` now strips `com.apple.quarantine` from the staged binary, the standard goreleaser fix for distributing an unsigned CLI tool via a cask. `brew install imagewize/tap/wp-ops` followed by `wp-ops --version`/`wp-ops search` verified working end to end after both fixes.

## [3.23.0] - 2026-08-01

### Added

- **go** - M4 task 6 (per `docs/m4-go-cli-completion.md`): `goreleaser` + a Homebrew tap (`imagewize/tap`), closing out M4. Resolves the "Script distribution: embed vs. locate" open decision in favor of embedding — a `brew`-installed binary has no repo checkout to locate scripts against. `go.mod`/`go.sum` move from `go/` to the repo root (module renamed `github.com/imagewize/wp-ops/go` → `github.com/imagewize/wp-ops`; every existing `.../wp-ops/go/...` import path is unchanged since the directory layout didn't move) so a new root-level `assets` package (`assets.go`) can `//go:embed` the command-carrying directories (`scripts`, `trellis`, `wp-cli`, `bedrock`, `wordpress-utilities`, `nginx`, `troubleshooting`, `mcp-server`, `docs`, plus `README.md`/`CLAUDE.md`/`CHANGELOG.md`/`LICENSE.md`) — `go:embed` patterns can't ascend directories or cross a module boundary, and `go/go.mod` previously put those directories out of reach. `repoRoot()` (`go/cmd/env.go`) gains a third fallback tier below `WP_OPS_ROOT` and live-checkout detection: `extractedAssetsRoot()` extracts the embedded tree to a version-stamped `~/.cache/wp-ops` (`os.UserCacheDir()`) directory on first run of a given binary version, giving `.sh`/`.py`/`.js` files the executable bit `internal/exec/shell.go` needs since it execs them directly, and reusing the extraction on subsequent runs; a temp-dir-then-rename keeps concurrent invocations from racing on a partial extract. Verified end to end by copying a built binary outside the checkout with `HOME` pointed at an empty directory and confirming both `--version` and a real script invocation (`scripts/git/git-log-oneline`) work purely off the embedded tree. New `.goreleaser.yml` builds darwin/linux amd64/arm64 archives and publishes a `homebrew_casks` entry (not `brews`, hard-deprecated as of goreleaser v2.16) to `imagewize/tap`'s `Casks/` directory; new `.github/workflows/release.yml` runs it on `v*` tag pushes, using a `HOMEBREW_TAP_GITHUB_TOKEN` secret (a repo admin still needs to create that PAT and set the secret — the default `GITHUB_TOKEN` can't push cross-repo). `imagewize/tap` created with a README pointing back here. `go-build.yml` updated for the moved `go.mod`/`go.sum` and gains a step building/vetting the root `assets` package directly, since `go/`'s own `./...` patterns don't reach it. `go test ./...` and `go/scripts/parity-check.sh` (still 8/8) both green after the move.

## [3.22.0] - 2026-08-01

### Added

- **go** - M4 task 5 (per `docs/m4-go-cli-completion.md`): the Go CLI gets `wp-ops docs [term]`, a port of bash's full-text search over the repo's ~65 markdown guides (`wp-ops:1610-1736`). With no term, lists every `*.md` file under the repo root (excluding `.git`/`node_modules`/`vendor`); with a term, prints each matching file with its match count and up to 3 matching lines (collapsed whitespace, truncated to 96 chars), plus a "… N more" summary beyond that. `-w`/`--word` restricts matching to whole words (so `oom` doesn't hit inside "server room"); `-l`/`--files`/`--paths` prints matching paths only, for piping to an editor. This is unrelated to the per-command `@doc` manifest directive (`catalog.Entry.Doc`, already surfaced by `--help`/`--json`) — a pure filesystem search independent of any command's manifest, new file `go/cmd/docs.go`. `wp-ops search`'s "no command matches" path (`go/cmd/search.go`) regains the "the documentation mentions it though" cross-reference into this search, matching bash's behavior — the gap was called out explicitly in a comment left when `search` was ported ahead of `docs` landing. Unit-tested (`go/cmd/docs_test.go`): file discovery/exclusion, case-insensitivity vs. whole-word matching, whitespace collapsing/truncation, and match-count-is-lines-not-occurrences (`grep -c` semantics). `go/scripts/parity-check.sh` still 8/8 — `docs` isn't part of that contract (bash's output there is hand-formatted prose, not a stable interface), and neither `--json` nor `search`/`doctor` changed shape.

## [3.21.0] - 2026-08-01

### Added

- **go** - Phase F option 4 (per `docs/cli-ux-plan.md`): split the oversized 35-command `scripts` category into real top-level categories. Turned out far cheaper than the original effort estimate — every `scripts/**` file already carries a fine-grained `@category` directive from Phase A's rollout, it just wasn't wired into the top-level grouping. Added a new `catalog.Entry.DisplayCategory` field, computed in `gen/main.go`, kept deliberately separate from the existing directory-based `Category` field so `printJSON`'s `--json` output stays byte-for-byte identical to bash's (`go/scripts/parity-check.sh` still 8/8) — only the human-facing surfaces (`list`, the picker, `wp-ops <category>`) read the new grouping. Subcategories with 4+ commands get their own top-level entry — `monitoring`(10), `images`(5), `patterns`(5), `release`(4) — while the smaller ones (`backup`, `git`, `misc`, `sync`, `woocommerce`, 2-3 commands each) stay folded into `scripts`(11), per a new `catalog.DisplayOrder` var and matching `CategoryDisplayNames`/`CategoryBlurbs` entries. `Catalog.DisplayCategories()`/`CommandsInDisplay()` join the existing `Categories()`/`CommandsIn()` rather than replacing them. `displayCategoryFor()` is table-tested (`gen/main_test.go`), and `TestCommandsInDisplayPreservesCategoryForJSON` (`catalog_test.go`) encodes the `--json` parity guarantee as an assertion rather than just a comment.

### Fixed

- **go** - The Bubble Tea picker's outermost category-select screen (Phase F option 3, 3.20.0) only handled arrow keys, so typing did nothing until Enter was pressed on "All categories" first — silently dropping the "just start typing to search" behavior the picker had before that stage existed. `updateCategory` (`internal/ui/model.go`) now treats a rune/space keypress as jumping straight into the browse list, unscoped, seeded with the typed text as the initial filter; arrow+Enter still drills into a category as before. New `internal/ui/model_test.go` — the package previously had no tests for `model.go` at all, only `fields.go`'s pure helpers — covers both key branches plus regression guards for arrow-key navigation and Enter-to-drill-into-a-category.

## [3.20.0] - 2026-08-01

### Added

- **go** - Phase F options 1-3 (category-first command discovery, per `docs/cli-ux-plan.md`): the three surfaces that render the *list* of commands were either too long or too flat to act as a landing page, so all three now lead with categories. `wp-ops list` and bare (piped) `wp-ops` print an 8-line category summary — display name, command count, and a one-line blurb from the new `catalog.CategoryBlurbs` map — pointing at `wp-ops <category>` for detail; the original full per-command listing is unchanged but moves behind `wp-ops list --all` (`printAllCommands`), still the one-shot way to see or grep the whole catalog. `wp-ops --help` picks up the shorter view for free, since it already called `printCategorizedList`. Nothing new was needed for the drill-down itself: `wp-ops <category>` was already a real Cobra command from M3's `registerCatalogCommands`, just never the default landing view.
- **go** - The Bubble Tea picker (`internal/ui/model.go`) gains the same two-level structure. `filterEntries` now sorts by curated category rank (the same order the compact `list` view uses) then key, rather than plain alphabetical-by-key, and `viewBrowse` renders a dim category header whenever the category changes while walking the visible window — including at the top of the window after a scroll, so a mid-scroll view still says which category you're in. Headers aren't members of `m.filtered`, so cursor movement and selection indices are untouched; only rendering changed. On top of that, launch now opens on a new outermost `stageCategory` (mirroring `trellis-cli`'s top-level verb list) listing "All categories" as the cursor default — same full-catalog reach as before, one keystroke away — followed by each active category with its count and blurb. Picking a category scopes the browse list via `filterByCategory` and adds a breadcrumb (`wp-ops > Trellis > `), at which point the per-row headers stop repeating since the breadcrumb already names the category. Esc now consistently means "up one level" (browse → category select, fields/free-text → browse) instead of quitting; Ctrl+C is the only quit-entirely key past the category stage. `CategoryBlurbs` lives in `internal/catalog` rather than `cmd` so `cmd` and `internal/ui` share one copy of the text without either package importing the other.
- **docs** - `docs/cli-ux-plan.md` gains a Phase F section covering the information-density problem across the three list surfaces, the finding that per-category drill-down already existed via `wp-ops <category>`, and the four options considered — with 1-3 marked done and option 4 (splitting the oversized 35-command `scripts` category into subcategories matching its directories) deferred as a separable change, since it would touch `@category` values across ~25 files. Also notes the picker's visual density versus upstream Bubble Tea examples as secondary polish, and refreshes the stale M4 milestone row, which still read "Not started" after tasks 1-4 had merged.

## [3.19.0] - 2026-08-01

### Added

- **go** - M4 task 4 (shell completions, per `docs/m4-go-cli-completion.md`): the Go CLI now generates real bash/zsh/fish/PowerShell completion scripts via Cobra's built-in `completion` command — free once the command tree is fully populated, since `rootCmd` doesn't opt out of it. Added `categoryBasenameCompletions()` (`go/cmd/dispatch.go`) as each category command's `ValidArgsFunction`, porting bash's `print_completion()` (`wp-ops:2098`) two-token grammar: `wp-ops <category> <TAB>` offers every basename in that category (deduplicated), and anything past the basename returns no completions — the rest of argv belongs to the underlying script, not to wp-ops. The dynamically-registered per-entry (full-key, hidden) leaf commands from M3 task 7 complete without error despite `DisableFlagParsing: true`: positional args fall back to file completion (a reasonable default, since most scripts take paths) and `--<TAB>` correctly suppresses bogus flag suggestions instead of leaking them.
- **go** - `wp-ops doctor` now reports whether `wp-ops completion bash`/`zsh` will actually work: zsh always does (its `compinit` ships with the shell, no extra package), but bash needs bash ≥4 — macOS ships bash 3.2, frozen since 2007 over the GPLv3 relicense, which can't run Cobra's generated script even with `bash-completion` installed — and the separate `bash-completion` package itself. Both are checked and reported with install guidance (`brew install bash`, `brew install bash-completion`) rather than failing silently on a clean Mac.
- **docs** - Root `README.md`'s "wp-ops CLI" section gets a pointer note: a Go rewrite is in progress (`go/`), not yet distributed, so the documented bash CLI usage stays authoritative for now — links to `docs/cli-ux-plan.md` for the plan and milestone status.

## [3.18.0] - 2026-08-01

### Added

- **go** - M4 task 3 (`internal/ui`, per `docs/m4-go-cli-completion.md`): the Go CLI now has an interactive picker, replacing bash's two-path `fzf_menu()`/`interactive_command_menu()` (`wp-ops:1962`, `wp-ops:2047`) with a single Bubble Tea implementation and no `fzf` dependency (open decision #3). Launches on a bare `wp-ops` invocation from an interactive terminal (`detect.IsTerminal` on both stdin and stdout, port of `main()`'s `[[ -t 0 && -t 1 ]]` check); a piped/redirected invocation still prints the plain `list`-equivalent output. A flat, instantly-filterable command list (typing narrows the set on every keystroke, no `/`-to-filter mode switch) pairs with a live preview pane rendering `internal/exec/help.go`'s manifest body verbatim via its new `PreviewBody()` export, so the picker and every executor's own `--help` can never drift apart. Selecting a command walks its declared `@arg`/`@flag` lines one at a time — port of `prompt_manifest_args()`/`prompt_one_manifest_param()` (`wp-ops:484`, `wp-ops:420`) as pure, unit-tested logic in `internal/ui/fields.go` (`buildFields`/`resolveField`): choices/defaults shown inline, a blank required field reprompts, an off-list choice is accepted with a note, and every run ends with an "Additional arguments" catch-all for anything a single manifest line can't express (repeatable flags, etc. — same limitation bash's version has). A command with no declared `@arg`/`@flag` at all falls back to a single free-text prompt, same as bash. `go/cmd/interactive.go` owns the "Pick another command?" outer loop, running the selected command only after the Bubble Tea program has released the terminal — same reasoning as `fzf_menu` exiting before `execute_command` runs (`wp-ops:1993-1997`). Manually verified end to end for one command per executor type: a `.sh` command with a non-default guided value, a `.yml`/Ansible command through its required-field reprompt, a `.php`/WP-CLI command reaching its executor and failing clearly on unset `WP_SITE_DIR`, and a `wordpress-utilities` snippet completing successfully through the no-manifest-args fallback. New direct dependencies: `github.com/charmbracelet/bubbletea`, `bubbles`, `lipgloss`.

## [3.17.0] - 2026-08-01

### Added

- **go** - M4 task 2 (`internal/exec/snippet.go`, per `docs/m4-go-cli-completion.md`): the Go CLI can now run `wordpress-utilities/**` reference snippets, closing the second of M4's two remaining executor gaps. Port of `execute_snippet()` (`wp-ops:1232`) — default (no args) prints the snippet to stdout, TTY-aware like bash (filename header plus trailing reference-snippet notice on a terminal, raw content only when piped/redirected so `wp-ops ... > footer.php` still works, minus bash's ANSI dimming to match the rest of the Go CLI's plain-text convention); `--path` prints only the resolved file path; `--copy` clipboard-copies via the same `pbcopy` → `xclip`/`xsel` → `clip.exe` fallback chain as `find_clipboard_cmd()` (`wp-ops:1220`), failing with the same "no clipboard tool found, try --path instead" message if none are on `PATH`. `--help` renders from the manifest plus the fixed "reference snippet, not run directly" explanation and three-line usage block bash prints. `go/cmd/dispatch.go`'s `wordpress-utilities/*` branch now dispatches for real instead of printing the M4 stub message.

### Fixed

- **go** - `go/cmd/dispatch.go`'s executor dispatch checked `ext == ".php"` before the `wordpress-utilities/` category prefix, a regression introduced when M4 task 1 split what had been a single combined condition. Since 3 of the 5 non-doc files under `wordpress-utilities/` are `.php`, they were silently executed via WP-CLI (`wp eval-file`) instead of being printed/copied as reference snippets — never shipped to a release, caught while wiring up task 2's executor. The category-prefix check now runs first.

## [3.16.0] - 2026-08-01

### Added

- **go** - M4 task 1 (`internal/exec/wpcli.go`, per `docs/m4-go-cli-completion.md`): the Go CLI can now run `wp-cli/**` and `bedrock/**` `.php` commands, closing one of the two remaining executor gaps from M3. Port of `execute_php_command()` (`wp-ops:1146`) — detects a registered `WP_CLI_Command` subclass via `get_registered_wp_command()`'s Go equivalent and invokes `wp --require=<script> <command> [args...]`, falling back to `wp eval-file <script> [args...]` otherwise. `resolveWPSiteDir()` (`go/cmd/wpsite.go`) ports `require_wp_site_dir()`, mirroring `resolveTrellisDir()`'s detect-then-confirm flow via `internal/detect.WPSiteDir()`. `--help` renders from the manifest with no probe, same manifest-first-by-construction property `ansible.go` already has. `go/cmd/dispatch.go`'s `.php` branch now dispatches for real instead of printing the M4 stub message; `wordpress-utilities/*` snippets still hit that stub pending task 2.

## [3.15.1] - 2026-08-01

### Added

- **docs** - Scoped out M4 (remaining Go executors, Bubble Tea picker, completions, goreleaser + tap, per `docs/cli-ux-plan.md` Phase C) into a new tracker doc, `docs/m4-go-cli-completion.md`, following M3's format: an ordered task breakdown (`internal/exec/wpcli.go`, `internal/exec/snippet.go`, the interactive picker, shell completions, `docs` search, goreleaser/tap distribution), four flagged open decisions (embed vs. locate scripts, `docs` command inclusion, picker scope vs. bash's two picker paths, typed flags vs. the `DisableFlagParsing` M3 chose), and explicit M4 done criteria. `cli-ux-plan.md`'s M4 milestone row and M3's tracker doc now point at it. Also corrected `cli-ux-plan.md` and `docs/m3-go-skeleton.md`, both of which still described M3 as "implemented, not yet merged" on a feature branch after PR #140 had already merged to `main`. No code changes.

## [3.15.0] - 2026-08-01

### Added

- **go** - M3 (Go CLI skeleton, per `docs/cli-ux-plan.md` Phase C / `docs/m3-go-skeleton.md`): a new `go/` module (`github.com/imagewize/wp-ops/go`, Cobra-based) that reads the same manifest-annotated scripts as the bash CLI and builds a working `wp-ops` binary alongside it. The bash `wp-ops` script is untouched — this is a second, independent implementation, not a replacement yet. `internal/manifest` ports the directive parser and linter (`parse_manifest`/`manifest_parse_param_line`/`lint_manifest_command`), unit-tested against fixture blocks pulled from real annotated scripts.
- **go** - `internal/catalog`: a build-time generator (`go generate`, `internal/catalog/gen`) walks the repo the same way bash's `discover_commands()` does — same category directories, same file-type filters, manifest-first with a header-scrape fallback for the two still-unannotated `mcp-server/*` commands — and emits `catalog.json`, embedded into the binary via `go:embed`. Matches bash's 66-command set field-for-field; a malformed manifest fails the build rather than degrading the catalog. `catalog.json` is committed rather than gitignored, since `go:embed` needs it to exist for the package to even compile on a fresh clone. The generator's own discovery rules are unit-tested directly (per-category file-type filters, the `@runs`/`SERVER_SIDE_COMMANDS` precedence, `clean_description`'s trim/first-sentence/72-rune-cap behavior, and the header-scrape fallback's per-extension scan windows), not just transitively via the parity script.
- **go** - `internal/detect` and `internal/exec`: ports of `detect_trellis_dir`/`detect_wp_site_dir`/`confirm_detected_dir` (unit-tested, including the sibling-checkout false-positive bash's own comments call out), and executors for direct-exec (`.sh`/`.js`/`.py`) and `ansible-playbook` (`.yml`) commands, with manifest-driven `--help` rendering that's never subject to the has-manifest-blind short-circuit bug bash fixed piecemeal across 3.11.0-3.12.0 (it's manifest-first by construction here).
- **go** - Cobra command wiring (`go/cmd`): full-key (`wp-ops <category>/<command>`) and category-short (`wp-ops <category> <command>`) dispatch, `list`, `search`, `doctor`, `--json`, `--where`, ambiguous-basename resolution and did-you-mean, all reading the embedded catalog. Per-entry commands use `DisableFlagParsing` so a script's own flags (including ones not declared via `@flag`) pass through unparsed rather than risk Cobra rejecting them — commands still get real generated `--help` text from their manifest, not a blank arguments box. The server-side guard is a full port (`go/cmd/serverside.go`) of `execute_command()`'s `/srv/www` check plus `print_server_side_guidance`/`print_gnu_date_required`, including the nuance that an explicit readable log-file argument unlocks a local run — but only for the three commands that actually take a log path, and only where GNU `date -d` exists; verified byte-identical to bash for all 8 server-side commands. `wp-cli/*.php` and `wordpress-utilities/*` commands are cataloged but not yet runnable through this binary (their executors are M4); they print a clear message pointing at the bash CLI instead of failing silently.
- **go** - `go/scripts/parity-check.sh`: an acceptance script diffing both CLIs' `--json list` (strict, field-for-field), `search <term>` (a fixed term set), and `doctor` output — 8/8 checks passing. `.github/workflows/go-build.yml` runs `go build`/`vet`/`test` plus a catalog-drift check (`go generate` then `git diff --exit-code`) on push/PR to `main`, independent of `manifest-lint.yml`. Its path filter covers `go/**` *and* every command-category directory the catalog is generated from, so a manifest-only change still trips the drift check rather than merging a stale `catalog.json` that fails some later, unrelated `go/` PR.

## [3.14.1] - 2026-08-01

### Added

- **docs** - Scoped out M3 (Go CLI skeleton, per `docs/cli-ux-plan.md` Phase C) into a new tracker doc, `docs/m3-go-skeleton.md`: an ordered, checkable task breakdown (module scaffold, manifest parser port, catalog generator, `detect`/`exec` ports, Cobra command wiring, parity verification, CI), three flagged open decisions (Go module location, `mcp-server/*` catalog parity, `docs` command deferral to M4), and explicit M3 done criteria — written so the multi-session implementation work can be picked up cold. `cli-ux-plan.md`'s M3 milestone row and Phase C intro now point at it. No code changes.

## [3.14.0] - 2026-08-01

### Added

- **wp-ops CLI** - Wired `wp-ops manifest lint` into CI (per `docs/cli-ux-plan.md`, M2): `.github/workflows/manifest-lint.yml` runs it on every push and pull request to `main`, failing the check if any annotated command's `@desc`, `@runs`, `@arg`/`@flag`, or `@doc` directives are missing or malformed. This was M2's last open item — new scripts can no longer merge with a broken or incomplete manifest.

## [3.13.0] - 2026-07-31

### Added

- **wp-ops CLI** - Guided argument prompting (per `docs/cli-ux-plan.md`, M2): the fzf picker and the fallback `select`-based interactive menu now prompt once per `@arg`/`@flag` declared on a command, instead of a single blank `Arguments (leave blank for none):` box. Each prompt shows the directive's description, offers its `|`-separated choices or default inline, and — for a required field — reprompts rather than silently passing nothing. Boolean flags (`@flag` with an empty `{}`) get a `y/N` prompt instead of a value box. Commands with no manifest, or a manifest with no `@arg`/`@flag` at all (the `wordpress-utilities` snippets), keep the original free-text prompt unchanged. Every guided run ends with an "Additional arguments" catch-all, since a manifest line is only prompted once and can't express a repeatable flag (e.g. `redirect-audit`'s `--url`, shown passed twice in its own `@example`).

### Fixed

- **wp-ops CLI** - The guided prompt's per-line loop originally iterated with `while read line; do prompt_one_manifest_param ...; done <<< "$args"`, which rebinds stdin to the heredoc for the loop's entire body — so the nested `read -p` inside `prompt_one_manifest_param` silently consumed the *next manifest line* instead of the user's typed answer, and the real answer ended up satisfying a later, unrelated prompt. Fixed by collecting lines into a plain array first and walking that with a `for` loop, which never touches stdin.

## [3.12.0] - 2026-07-31

### Added

- **wp-cli**, **bedrock** - Manifest rollout group 3 (per `docs/cli-ux-plan.md`): all 12 `wp-cli/**` and `bedrock/**` commands annotated — content-creation's `page-creation`, diagnostics' `diagnostic-transients` and `list-posts-count`, the three security scanners (`scanner-general`, `scanner-targeted`, `scanner-wrapper`), the five SEO audits (`blog-audit`, `orphan-pages-audit`, `page-audit`, `redirect-audit`, `schema-audit`), and bedrock's `wp pattern validate` WP-CLI command.
- **wordpress-utilities** - Manifest rollout group 4: the age-verification modal's JS/PHP/CSS trio and the two `functions.php` snippets (`admin-user-creation`, `post-expiry-noindex`) now declare `@desc`/`@category`/`@doc`. These are copy-paste reference snippets, not runnable commands, so there's no `@runs`/`@arg`/`@flag` to declare.
- **scripts** - Manifest rollout group 5: the remaining 25 `scripts/**` commands across `git`, `images`, `misc`, `monitoring` (the two stragglers added after group 1 shipped), `patterns`, `release`, `sync`, and `woocommerce`.
- **trellis/security**, **trellis/updater** - `check-ips` and `trellis-updater` — two commands `discover_commands()` already matched but that were never inventoried into any of the 5 rollout groups — are now annotated too. 64 of 66 commands now have a manifest; only `mcp-server/*` (2, out of Phase A's scope) remain.

### Fixed

- **wp-ops CLI** - `execute_php_command()` and `execute_snippet()` had the same `has_manifest`-blind `--help` short-circuit `execute_playbook()` had before the 3.11.0 fix: both always rendered a hardcoded description/usage stub instead of `print_manifest_help()`, so annotating a `.php` command or a `wordpress-utilities` snippet had no visible effect on `--help` until corrected here.

## [3.11.0] - 2026-07-31

### Added

- **trellis/backup**, **trellis/monitoring** - The second manifest rollout group (per `docs/cli-ux-plan.md`) is annotated: all 10 Ansible playbook commands (`database-backup`, `database-pull`, `database-push`, `files-backup`, `files-pull`, `files-push`, `quick-status`, `security-scan`, `setup-monitoring`, `traffic-report`). Each now declares `site`/`env` as required `@arg`s plus their optional `-e key=value` extras (`hours`, `threshold`, `email`, `log_path`), so `--help` shows exactly what a playbook expects instead of leaving it to `variable-check.yml`'s runtime failure to explain.
- **wp-ops CLI** - `execute_playbook()` now renders `--help` from the manifest when one exists, the same short-circuit the generic script dispatcher already had. Previously every `trellis/**/*.yml` command's `--help` was a fixed three-line stub regardless of manifest data, so annotating a playbook had no visible effect until this wired up.

## [3.10.0] - 2026-07-31

### Added

- **wp-ops CLI** - Command manifest: scripts can now declare `@desc`, `@category`, `@runs`, `@requires`, `@arg`, `@flag`, `@example`, and `@doc` directives in their header comment, parsed by a new `parse_manifest`/`load_manifest` pair in `wp-ops` (see `docs/cli-ux-plan.md`). Every element of the CLI's UI used to be scraped from source at runtime — a description grepped from the first `#` comment, `--help` output probed from the script itself with a generic stub on failure, and a hand-maintained `SERVER_SIDE_COMMANDS` list covering 5 of 66 commands. A manifest replaces the scrape/probe for the commands that have one: `get_description()` prefers `@desc`, `--help` renders directly from the declaration instead of risking a probe that runs the script with `--help` as a stray positional argument, and `is_server_side_command()` checks `@runs` before falling back to the hardcoded list. Annotation is incremental — unannotated scripts keep working exactly as before.
- **wp-ops CLI** - `wp-ops manifest lint`: validates every annotated command's directives (missing `@desc`, an `@runs` value other than `local`/`server`/`either`, a malformed `@arg`/`@flag` line, or an `@doc` path that doesn't exist) and exits non-zero on the first problem found, so a manifest can't silently drift from the script it describes.
- **scripts/backup**, **scripts/monitoring** - The first two command groups are annotated: `db-backup`, `site-backup`, and all 8 monitoring scripts (`traffic-monitor`, `security-monitor`, `ai-bot-monitor`, `error-monitor`, `run-monitoring`, `404-checker`, `redirect-check`, `server-monitor`). `--help` on any of them now lists arguments, flags, requirements, and examples straight from the manifest — including the ones that never implemented `--help` themselves.

## [3.9.1] - 2026-07-31

### Fixed

- **scripts/backup** - `db-backup.sh` and `site-backup.sh` had no `--help` handling, so `wp-ops scripts/backup/db-backup --help` fell through to the generic stub whose only advice was to run `db-backup.sh --help` — the thing that had just failed. Both now document their positional arguments, their defaults, and the fact that they write to `/srv/backups/` on the server.
- **wp-ops CLI** - Both backup scripts are now registered as server-side commands. They hardcode `/srv/www/<site>` and `/srv/backups/`, so running one from a workstation failed with `Site directory not found: /srv/www/example.com` — indistinguishable from a broken command. Invoking one locally now prints the `ssh host 'bash -s' < script` form with correct example arguments, and points at `trellis/backup/database-pull` / `files-pull` for the common case of wanting the archive on *this* machine rather than left on the server. `runs_on` in `--json` reports them accordingly.

## [3.9.0] - 2026-07-31

### Added

- **scripts/monitoring** - New `error-monitor.sh`: error-log review across the whole stack — Nginx (global and per-site, with a severity breakdown), PHP-FPM, WordPress/Acorn exceptions, MySQL/MariaDB, and the systemd journal (priority-`err` messages, PHP segfaults, OOM kills). Completes the monitoring set: the existing three read the *access* log and answer "who is visiting?", this one reads the *error* logs and answers "is anything broken?". Migrated from a client project, where it hardcoded one server and one domain; it now takes `[domain] [hours] [output_file]` like its siblings and is wired into `run-monitoring.sh`, whose summary gains an error section that calls out segfaults and OOM kills separately — those drop requests mid-flight and leave no access-log trace. Where the journal isn't readable (the `web` user usually can't), those sections report as *skipped* rather than empty, since "no errors" and "no permission" otherwise look identical while you're chasing an outage.
- **wp-ops CLI** - `wp-ops docs [term]`: full-text search across the repository's ~60 guides, grouped by document with line numbers. `wp-ops search` only ever looked at command names and descriptions, which left two entire categories (`nginx/`, `troubleshooting/`) and every README unreachable from the CLI — a large part of what this toolkit knows is written down rather than scripted. `-w` matches whole words only (so `oom` stops matching "server room"), `-l` prints paths only for piping to an editor, and a bare `wp-ops docs` lists every guide. When `wp-ops search` finds no command for a term, it now checks the documentation and points there.

### Fixed

- **scripts/monitoring/error-monitor** - Time filtering that only claimed to be time filtering. The original counted `tail -100 | wc -l`, which reports ~100 for any non-empty log regardless of the window, and its Nginx count combined `find`'s output with a line count into a value that made `[ "$x" -gt 0 ]` fail outright. Every source is now filtered to the requested window by its own timestamp format (Nginx `2026/07/31 11:07:01`, PHP-FPM `[31-Jul-2026 …]`, Acorn `[2026-07-31 …]`, MySQL ISO), all of which sort chronologically as text — so plain `awk` string comparison suffices and no `gawk` is required on the server. Counts and excerpts now come from a single read of each file, so the number can't disagree with the lines printed beneath it. Also: PHP-FPM logs are found by globbing `/var/log/php*-fpm.log` instead of asking `php -v` (the CLI version can differ from the version FPM runs), Acorn stack-trace continuation lines stay attached to their entry, and the summary no longer exits early on `set -e` when a breakdown line's count is zero.
- **wp-ops CLI** - The server-side guidance printed for `run-monitoring` was written for the access-log monitors: it described reading `access.log`, suggested a log path as the first argument (`run-monitoring`'s is an hour count), and offered to run it locally against a log file it doesn't accept. Guidance, example arguments, and the local-log-file escape hatch are now scoped to the commands that genuinely take an access log path.

## [3.8.0] - 2026-07-31

### Added

- **wp-ops CLI** - `wp-ops doctor`: preflight check for the external tools the scripts shell out to (WP-CLI, Ansible, ImageMagick, `cwebp`, Node, `gh`, `svn`, `jq`, `gawk`, `fzf`) plus `TRELLIS_DIR`/`WP_SITE_DIR`, so a missing dependency surfaces up front instead of partway through an operation.
- **wp-ops CLI** - `wp-ops search <term>`: search commands by name or description, for when you know what you want to do but not where it lives among 65 commands.
- **wp-ops CLI** - `wp-ops <command> --where`: print the resolved path to any command's script. Previously only `wordpress-utilities` snippets could report their path (`--path`).
- **wp-ops CLI** - Fuzzy command picker. Running `wp-ops` with no arguments now fuzzy-searches the whole catalog with the script's header comment as a live preview when [fzf](https://github.com/junegunn/fzf) is installed, falling back to the existing numbered category → command menu when it isn't.
- **wp-ops CLI** - Server-side commands are marked as such. The Nginx log monitors (`traffic-monitor`, `security-monitor`, `ai-bot-monitor`, `run-monitoring`) execute on the host rather than on your machine, so they're tagged `(server)` in listings, search, and the fuzzy picker, exposed as a `runs_on` field in `--json`, and invoking one locally now prints the `ssh host 'bash -s' < script` invocation instead of failing on a missing `/srv/www` log path. `--help`, `--where`, and passing an existing log file explicitly all still work as before — and since those scripts date-filter with GNU-only `date -d "N hours ago"`, pointing one at a local log on a machine without GNU date now explains that up front (with the `coreutils`/`gnubin` fix) instead of dying several screens in on `date: illegal option -- d`.
- **wp-ops CLI** - `TRELLIS_DIR` and `WP_SITE_DIR` are detected by walking up from the current directory when unset. Detection only matches a project you're genuinely inside (the Trellis directory itself, or a Bedrock site next to it) so an unrelated Trellis checkout sitting beside your current repo isn't picked up, and the result is always confirmed interactively before use — non-interactive runs still require the variable to be set explicitly, since these commands back up, overwrite, and push databases.

### Fixed

- **wp-ops CLI / scripts/monitoring** - `wp-ops doctor` checked for `gawk` locally, but the Nginx log monitors (`traffic-monitor.sh`, `security-monitor.sh`, `ai-bot-monitor.sh`) read `/srv/www/<site>/logs/` directly and use GNU `date -d`, and `run-monitoring.sh` is invoked as `ssh host 'bash -s' < run-monitoring.sh` — they execute on the server, so a missing local `gawk` meant nothing. `gawk` moved to a "Server-side" note, and `ssh`/`rsync` (genuinely needed locally, by the remote monitors, theme sync, and pattern screenshots) added to the local checks. The scripts' own comment claiming gawk is "available by default on Ubuntu" was wrong — Ubuntu ships mawk as its default awk — and now points at `apt install gawk`.
- **wp-ops CLI** - A command that exited non-zero was reported as "Unknown command or category" and its exit code replaced with a generic failure. Command resolution and command execution are now separate, so a failing command's own output and exit code reach the caller intact.
- **wp-ops CLI** - `wp-ops nginx` and `wp-ops troubleshooting` dead-ended on "No commands found in category". Both hold guides and Nginx config templates rather than runnable scripts, so they're now marked `(docs only)` in the category list and list their documents when selected.
- **wp-ops CLI** - An unknown command printed its "Did you mean" suggestion and then buried it under a full reprint of the usage text and category list. Unknown input now produces a single error with the suggestion and a pointer to `wp-ops search`.
- **wp-ops CLI** - A bare command name matching more than one command (`convert-to-webp` exists in both `scripts/images/` and `scripts/patterns/`) silently ran whichever sorted first. Ambiguous names now list every match and ask for the full name.
- **wp-ops CLI** - `--version` reported a hardcoded `v1.0.0`. It now reads the current version from `CHANGELOG.md`.
- **wp-ops CLI** - Categories were listed alphabetically, discarding the curated priority order in the script. Command listings also overflowed their column with the full `category/subgroup/name` key already shown in the subgroup heading above, and descriptions kept redundant `script.sh - ` prefixes or cut off mid-clause. Listings now show the bare command name under its subgroup, with descriptions trimmed to their first sentence.

## [3.7.0] - 2026-07-31

### Added

- **scripts/patterns** - New Playwright/sharp toolkit for screenshotting WordPress block patterns and converting them to WebP: `screenshot-patterns.sh` orchestrates the full pipeline (create a temp WP page via a fully configurable `WP_CLI_CMD`, screenshot it, delete the page, batch-convert to WebP); `screenshot-url.js` is the underlying generic Playwright capture primitive (any URL, element selector or full page); `convert-to-webp.js` is a standalone sharp-based converter; `trim-screenshots.sh`/`center-screenshots.sh` post-process a directory of screenshots with ImageMagick (whitespace trim, or trim + center on a fixed canvas), backing up originals and safe to re-run. `WP_CLI_CMD` supports a local site, a Trellis VM, or a remote server over SSH, so no client-specific paths are baked in. Rebuilt from scratch rather than ported, since the source project's Playwright scripts were hardcoded to one theme's paths and one site's Trellis VM location.
- **scripts/monitoring** - New `server-monitor.sh`: live CPU/memory/disk/PHP-FPM/MySQL/nginx resource snapshot over SSH, plus recent OOM killer events and swap usage. Complements the existing log-based monitors (`traffic-monitor.sh`, `security-monitor.sh`, `ai-bot-monitor.sh`) with a point-in-time view of what the server itself is doing. SSH target and PHP-FPM pool name are arguments, not hardcoded.

Second pass of the client-project audit flagged in 3.6.0. `check-carousel.sh` and the ~50 one-off debug scripts in the source project's `.playwright/scripts/` were deliberately left out — too coupled to one theme's custom carousel block and that project's dev history to generalize usefully.

## [3.6.0] - 2026-07-31

### Added

- **wp-ops** - `scripts/*.py` files are now discovered and runnable through the CLI, alongside the existing `.sh`/`.js`/`.yml`/`.php` support. Descriptions are scraped from a single-line module docstring (`"""text"""`) rather than a shell `#` comment, matching how the JS/PHP/CSS branch already reads its own doc style.
- **trellis/security** - New `check-ips.sh`: looks up one or more IPs against AbuseIPDB threat intelligence, so a manual Nginx deny rule is backed by an actual reputation score instead of a guess. Documented as a companion step in the "When to Add Manual IP Blocks" workflow, with its own setup/usage section and a `trellis/security/.env` (gitignored) for the API key.
- **scripts/images** - New `make-square-webp.sh` (pads an image onto a square canvas and exports it as WebP, with an optional left-margin offset for off-center artwork) and `openverse_search.py`/`openverse_download.py` (search and download CC-licensed images from Openverse, with optional WebP conversion in the same pass). The Openverse pair is stdlib-only Python — no `pip install` required.
- **scripts/misc** - New `convert-screenshot-for-claude.sh`: converts a PNG screenshot to JPEG, working around a Claude Code VSCode extension bug that mislabels PNG screenshots as `image/jpeg` and causes API errors when they're shared with Claude.

These five scripts were migrated out of a client project's local `scripts/` directory, where they'd accumulated with no project-specific paths or config — pure duplication risk with no benefit to living outside wp-ops. First pass of a broader audit to pull generic, reusable tooling into wp-ops and keep client repos thin; a few thin site-specific wrappers (database backup/pull, Trellis updater) and a larger Playwright-based pattern-screenshot pipeline are candidates for a follow-up pass.

## [3.5.0] - 2026-07-31

### Added

- **wp-ops** - Trellis Ansible playbooks (`trellis/backup/*.yml`, `trellis/monitoring/*.yml`) are now discovered and runnable through the CLI, closing the biggest gap in wp-ops's coverage (previously only `trellis-updater.sh` was visible under the `trellis` category). Since these playbooks read a real Trellis project's `ansible.cfg`, inventory, and `group_vars/`, wp-ops now requires `TRELLIS_DIR` to be set and runs `ansible-playbook` with that directory as the working directory; commands without it (or pointing at a directory without `ansible.cfg`) get a clear setup error instead of a cryptic Ansible failure. `variable-check.yml` (a shared import, not a standalone playbook) is excluded from discovery. Arguments pass straight through to `ansible-playbook`, so documented usage like `-e site=example.com -e env=production` works unchanged via `wp-ops trellis <playbook>`.
- **wp-ops** - PHP scripts under `wp-cli/security/`, `wp-cli/diagnostics/`, and `bedrock/wp-cli-config/` are now discovered and runnable through the CLI, closing the `bedrock` category's coverage gap (it previously discovered zero commands, since it has no `.sh`/`.js` files at all). Descriptions are scraped from the PHPDoc header (like the existing JS handling), and `transient-debug-browser.php` is excluded from discovery since it's a browser-uploaded debug tool, not a WP-CLI script. Two invocation shapes are auto-detected per file: a plain script (the three security scanners, `diagnostic-transients.php`) runs via `wp eval-file <path> [args]`; a file that registers a `WP_CLI_Command` class (`wp-cli-pattern-validate.php`) runs via `wp --require=<path> <registered-command> [args]`, with the command name (e.g. `pattern validate`) parsed from its own `WP_CLI::add_command()` call. Both need `WP_SITE_DIR` set to the target WordPress/Bedrock install, mirroring `TRELLIS_DIR` for the Ansible runner above.
- **wp-ops** - `wordpress-utilities/` files (PHP includes, CSS, browser JS under `age-verification/` and `snippets/`) are now discovered too, in a new "snippet" mode: since these are copy-paste-into-a-theme reference code with no meaningful "run" behavior, wp-ops prints them (or `--copy`s them to the clipboard via `pbcopy`/`xclip`/`xsel`/`clip.exe`, or `--path`s the file location) instead of executing them. Output is undecorated when piped/redirected (`wp-ops wordpress-utilities footer > footer.php` writes a clean copy), and PHP/CSS files are newly discovered in this category (previously only `.js` was, and only by accident of the global `*.js` matcher). This also fixes `age-verification.js` — a jQuery snippet meant to be enqueued in a theme — being misclassified as an executable command; `wp-ops wordpress-utilities age-verification` would previously `chmod +x` it and try to run it as a shell script.

### Fixed

- **wp-ops** - The description-scraper's whitespace trim piped through `xargs`, which throws `unterminated quote` on any header comment containing an apostrophe (e.g. "a site's database") — silently breaking `wp-ops trellis --help` for the newly-added playbook descriptions. Replaced with a `sed`-based trim that handles arbitrary text safely.
- **trellis/backup/*.yml** - All six backup playbooks (`database-backup`, `database-pull`, `database-push`, `files-backup`, `files-pull`, `files-push`) `import_playbook: variable-check.yml`, but that file only ever existed in `trellis/monitoring/` — so every backup playbook has failed with "could not find variable-check.yml" since it was introduced, regardless of wp-ops. Added `trellis/backup/variable-check.yml` (identical validation logic) so `backup/` is self-contained, matching the "copy this directory into your Trellis project" workflow documented in its README.
- **trellis/monitoring/traffic-report.yml**, **security-scan.yml**, **setup-monitoring.yml** - Fixed `copy: src: "../scripts/traffic-monitor.sh"` / `"../scripts/security-monitor.sh"` references left stale by the `scripts/` subdirectory reorganization in 3.4.0; both scripts now live at `scripts/monitoring/`, two directories up from `trellis/monitoring/`, not one.
- **trellis/backup/*.yml**, **trellis/monitoring/*.yml** - Added missing header description comments (e.g. "Back up a site's database from any environment...") so wp-ops surfaces a real description instead of falling back to the bare filename.

## [3.4.0] - 2026-07-31

### Added

- **wp-ops** - New unified CLI wrapper at the repo root. Auto-discovers executable scripts across every category, groups listings by subdirectory (e.g. `scripts/release/`, `wp-cli/seo/`), and adds an interactive category → command picker with colorized output and `✓`/`✗` completion markers when run from a terminal. Falls back to the original static listing when piped or run non-interactively, so scripted/CI usage is unaffected. Includes bash completion (`--completion`) and machine-readable output (`--json`).
- **install.sh** - Adds the wp-ops repo to `PATH` via `~/.zshrc`/`~/.bashrc`, so the `wp-ops` command works from any directory.
- **mcp-server/dev.sh**, **mcp-server/start.sh** - Give the MCP server discoverable run commands, so the pre-existing "MCP Server" wp-ops category actually lists and runs something instead of finding zero commands.

### Changed

- **scripts/** - Reorganized loose top-level scripts into themed subdirectories, matching the existing `backup/`, `monitoring/`, `woocommerce/` pattern:
  - `scripts/release/` - `deploy-plugin-wporg.sh`, `release-plugin.sh`, `release-theme.sh`, `upload-release-asset.sh`
  - `scripts/git/` - `create-pr.sh`, `gh-traffic.sh`, `git-log-oneline.sh`
  - `scripts/sync/` - `rsync-theme.sh`, `rsync-package-to-site.sh`
  - `scripts/images/` - `batch-resize.sh`, `convert-to-webp.sh`
  - `scripts/misc/` - `post-count.sh`, `find-and-replace-files.sh`, `README-FIND-AND-REPLACE.md`
  - Updated every path reference across `README.md`, `CLAUDE.md`, `AGENTS.md`, `scripts/README.md`, and `nginx/image-optimization/RESIZE-AND-CONVERSION.md`, plus self-referencing usage examples inside the moved scripts.

### Fixed

- **wp-ops** - `--completion` generated syntactically broken bash (`\({cword}` instead of `${cword}`) and split each category's command list across an unquoted line, so tab-completion would have thrown syntax errors and never populated. `set -e` also killed the entire interactive session whenever a picked command failed, instead of returning to the menu; and a script without its own `--help`/`-h` support could leak "file not found"-style output to stdout before the generic fallback usage was shown.
- **trellis/updater/trellis-updater.sh**, **wp-cli/seo/redirect-audit.sh**, **scripts/images/convert-to-webp.sh**, **wordpress-utilities/age-verification/age-verification.js** - Fixed missing or misleading header comments that wp-ops surfaces as each command's help description. `trellis-updater.sh` had no real header at all, so wp-ops picked up an unrelated inline comment (`Set your project slug here...`); `redirect-audit.sh` led with a redundant filename-only title line; `convert-to-webp.sh` only had a `Usage:` line; `age-verification.js` had no header comment at all. Also taught wp-ops's description scraper to read JSDoc/`//` comments in `.js` files instead of only shell `#` comments, which is what surfaced the two JS gaps.

## [3.3.3] - 2026-07-25

### Fixed

- **scripts/release-theme.sh**, **scripts/release-plugin.sh** - Fixed changelog extraction leaving a trailing `",` (or `"`) artifact appended to every generated entry. The awk parser assumed both JSON keys sat on a single line; when the AI pretty-prints its response (one key per line), each value's closing quote lands at the end of its own line and the greedy `","readme_txt".*` / `"}$` patterns never matched. Both scripts now parse the response with `jq` (already required by `create-pr.sh`) and fall back to a hardened awk extractor that strips a closing quote optionally followed by `,` or `}` at end of line.

## [3.3.2] - 2026-07-23

### Added

- **scripts/create-pr.sh** - Added `--dry-run` flag that generates the PR description and prints it without pushing to GitHub or touching the remote repository.

### Changed

- **scripts/create-pr.sh** - Added safety checks before PR creation:
  - Warns when there are uncommitted changes (local modifications or staged but uncommitted changes) that won't be included in the PR
  - Interactive prompt to continue or cancel when uncommitted changes are detected
  - Enhanced branch push logic: now checks if branch exists remotely AND if there are new commits to push, then pushes accordingly
- **scripts/create-pr.sh** - Updated AI prompt requirements to explicitly prohibit mentioning AI assistants or adding generated-by/co-authored-by footers in PR descriptions.

## [3.3.1] - 2026-07-23

### Added

- **scripts/rsync-theme.sh**, **scripts/rsync-package-to-site.sh** - Added `-n` / `--dry-run` to both sync scripts. Both run rsync with `--delete` (plus `--delete-excluded` in `rsync-package-to-site.sh`), so a mistaken invocation can remove files at the destination; `--dry-run` prints the full transfer, deletions included, and writes nothing.

### Fixed

- **scripts/rsync-theme.sh** - Unknown arguments are now rejected instead of silently ignored. The script previously hardcoded its rsync invocation and dropped anything passed to it, so `./rsync-theme.sh --dry-run` looked like a preview but performed a real sync — which is what prompted adding the flag.

### Changed

- **scripts/rsync-theme.sh** - Source and destination are now `SOURCE` / `DEST` variables overridable per invocation (`SOURCE=… DEST=… ./rsync-theme.sh -n`) rather than requiring an edit to the script. Added `-h` / `--help`, and switched to `#!/usr/bin/env bash` with `set -euo pipefail` to match `rsync-package-to-site.sh`. Corrected the README's stale `DESTINATION` variable name and its `(28 lines)` heading.

## [3.3.0] - 2026-07-23

### Added

- **scripts/rsync-package-to-site.sh** - Pushes a plugin or theme working copy *into* a Bedrock site, so unreleased changes can be tested on a real site without cutting a release. The reverse direction of `rsync-theme.sh`, which pulls a theme out of a Trellis site back into its standalone repo.
  - Reads the package's own `.distignore` when present, so what reaches the site is what ships. `--delete-excluded` means a file that used to ship and is now excluded is removed at the destination too, rather than lingering and being tested after it is gone. Falls back to a sensible exclude list (`node_modules/`, `vendor/`, `.git/`, `.github/`, `docs/`, `tests/`, `bin/`, `*.sh`, editor cruft) for packages without one.
  - Takes `<plugin|theme> <slug> [source-dir]` and reads the destination from `SITE_ROOT` (the Bedrock content directory holding `plugins/` and `themes/`), defaulting to the `example.com` layout used throughout this repo. Echoes the version that landed, so a no-op sync is obvious.
  - Consolidates per-repo copies that had accumulated in the Aludra plugin and Aviendha theme as `bin/sync-demo.sh`. Those are being removed in favour of this one: their paths were personal configuration rather than package code, and WordPress Theme Check's `File_Check` rejects a theme that ships a `.sh` file at all — which is how the duplication surfaced.
  - Complements rather than replaces the Composer `path` repository approach in `bedrock/local-package-development/`: that one suits a package you want Composer to resolve, this one a *pinned* dependency whose site `composer.json` you would rather leave alone.

## [3.2.2] - 2026-07-23

### Changed

- **trellis/updater/** - Added `roles/nginx/templates/nginx.conf.j2` to Trellis updater exclusions to protect custom Nginx rate limiting configuration from being overwritten during updates. Updated both rsync `--exclude` and `EXCLUDED_FILES` array, and documented in README.

## [3.2.1] - 2026-07-10

### Changed

- **scripts/create-pr.sh** - Reworked version detection so PR descriptions report the correct version reliably (previously AI backends, notably Mistral Vibe, frequently got the version wrong):
  - `detect_version` is now **diff-based** - it inspects added lines in the branch diff rather than the current file contents, so it only reports a version that was genuinely introduced and always returns the new value. Editing `package.json`/`composer.json` for unrelated reasons no longer produces a false "bump" signal. A shared `added_version_line` helper replaces four near-duplicate extraction blocks.
  - The detected version is now **injected into the PR body deterministically** (prepended as `**Version:** \`x.y.z\``) after the AI step, guaranteeing the correct version appears regardless of which AI backend generated the prose. The version is still passed to the prompt as narrative context.
  - Generalized the WordPress plugin/theme header check from a hardcoded `min.php` filename to any changed `.php` file or a theme's `style.css`, matching an added `Version: x.y.z` header line - filename-agnostic and usable in any repo.
  - Detection order is CHANGELOG → package.json → plugin/theme header → composer.json, all diff-based.

## [3.2.0] - 2026-07-09

### Added

- **scripts/gh-traffic.sh** - New script to fetch and display GitHub repository traffic statistics (views and unique visitors) in a formatted table. Features include: configurable output (table with headers, quiet mode without headers, raw JSON), repository format validation, and dependency checking for `gh` CLI and `column` command. Uses GitHub's traffic API which retains 14 days of data. Documented in [`scripts/README.md`](scripts/README.md).

### Changed

- **scripts/README.md** - Updated to include `gh-traffic.sh`: incremented script count from 22 to 23, added to directory structure, added GitHub Integration description update, and added usage example in Common Operations section.

## [3.1.1] - 2026-07-08

### Documentation

- **README.md** - Added missing **SEO** entry to WP-CLI section, linking to [`wp-cli/seo/README.md`](wp-cli/seo/README.md) which documents the page structure, redirect, schema markup, blog content, and orphan pages audit tools

## [3.1.0] - 2026-07-08

### Added

- **mcp-server/** - Enhanced site registry schema with support for custom `wpBin` and `phpBin` paths (enables cPanel/Plesk shared hosting sites with non-standard WP-CLI/PHP locations) and optional `url` field per environment (enables static sites and simplifies audit tool usage). Updated `redirect_audit` and `schema_audit` tools to accept either raw URLs or `site`+`env` parameters to look up URLs from the registry.

## [3.0.0] - 2026-07-08

### Added

- **mcp-server/** - New [MCP](https://modelcontextprotocol.io) server exposing wp-ops operations as tools Claude (and other MCP-compatible clients) can call directly instead of running the underlying scripts by hand. Tools implemented:
  - **`security_scan`** - runs `wp-cli/security/scanner-targeted.php` / `scanner-general.php` against a registered site/environment. Remote environments stream the scanner source over SSH stdin (`php - <path>`) rather than writing it to disk on the remote host.
  - **`db_backup`** - runs `wp db export` against a registered site/environment, gzips the result, and saves it locally to `~/wp-ops-backups/<site>/<env>/` (override with `WP_OPS_BACKUP_DIR`). Remote environments stream the export over SSH stdout, so nothing is written to disk on the remote host, matching `security_scan`'s pattern. `Dockerfile` now also installs WP-CLI so the tool works inside the container.
  - **`wp_cli`** - runs an arbitrary WP-CLI command (passed as an argv array, not a shell string) against a registered site/environment. Read-only verbs (list/get/exists/status/info/version/search/check-update/doctor/export) run immediately; everything else requires `confirm: true`. Remote args are individually shell-quoted before being sent over SSH, since SSH otherwise concatenates trailing args into one string for the remote shell to re-parse — a real command-injection vector for a passthrough tool taking arbitrary arguments.
  - **`redirect_audit`** - runs a comprehensive redirect chain audit for one or more URLs. Tests HTTPS pages for 200 status with 0 redirects (optimal for SEO), verifies HTTP→HTTPS 301 redirects, checks www→non-www canonicalization, and validates security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options). Uses `curl` for HTTP requests.
  - **`schema_audit`** - audits JSON-LD schema markup across key pages of a site. Checks for Organization, LocalBusiness, Service, Product, WebSite, BreadcrumbList, Article, FAQPage, HowTo, and Person schema types. Uses `curl` to fetch pages and extract schema.
  - Site/environment lookup via a gitignored `config/sites.json` (mapping site → env → local path or SSH host/remote path), resolved against `config/sites.example.json` and validated against a Zod schema.
  - Two transports, both verified end-to-end: **stdio** (default, for Claude Code/Desktop) and **Streamable HTTP** for remote/non-Claude clients, gated behind a required `WP_OPS_MCP_TOKEN` bearer token since HTTP mode can reach staging/production over SSH. Trellis VM transport is also supported.
  - `Dockerfile` for running the server in a container with a fixed Node/PHP/openssh toolchain, built from the repo root so the image can include `wp-cli/security/`.
  - Documented in [`mcp-server/README.md`](mcp-server/README.md).

- **wp-cli/seo/** - New SEO audit tools directory with comprehensive SEO analysis scripts ported from seo-strategy:
  - **`page-audit.sh`** - Analyzes WordPress page structure including hierarchy, navigation menus, key business pages, duplicate titles, and basic orphaned page detection
  - **`redirect-audit.sh`** - Comprehensive redirect chain testing (HTTPS pages, HTTP→HTTPS, www canonicalization) with security header validation
  - **`schema-audit.sh`** - Validates JSON-LD schema markup presence and types across key pages
  - **`blog-audit.sh`** - Analyzes blog content: categorization, featured images, content length, thin content detection
  - **`orphan-pages-audit.sh`** - Identifies pages not linked from navigation menus (basic detection)
  - All scripts are generic (not hardcoded to specific domains), support WP-CLI path configuration, and generate detailed reports
  - Documented in [`wp-cli/seo/README.md`](wp-cli/seo/README.md)

- Updated **wp-cli/README.md** with new SEO section documenting all tools and best practices

- **docs/mcp-server-recommendations.md** - Usage recommendations and roadmap for the new MCP server: setup gaps (project- vs user-scoped registration, single-site registry), config-only quick wins, server changes needed for non-Bedrock/non-WordPress sites (`wpBin`/`phpBin` override, per-site `url` field), token/time-saving improvements (enum-typed site keys, wider read-only allowlist, output capping), and a proposed `url_audit` tool for the dev-URL-hardcoding problem.

### Changed

- Replaced remaining hardcoded `imagewize.com` references with the `example.com` placeholder domain across docs and scripts, continuing the [2.3.1] sanitization pass: `bedrock/local-package-development/README.md`, `scripts/README.md`, `scripts/monitoring/404-checker.sh`, `scripts/monitoring/cf7-smoke-test.js`, `scripts/post-count.sh`, `trellis/security/FAIL2BAN.md`, `trellis/security/MANUAL-IP-BLOCKING.md`, `trellis/security/README.md`, `trellis/updater/README.md`, `troubleshooting/MULTI-SITE-ADDITION.md`, `wordpress-utilities/snippets/wp-template-db-override-wpcli.md`. Real-world production statistics and case studies in the security docs keep their factual content, with only the domain genericized.

This is a major version bump: it's the first release to ship an executable service (not just scripts/docs) as part of the repo, and more tools (backups, PR creation, releases, image optimization) are planned to follow the same pattern.

## [2.18.0] - 2026-07-08

### Added

- **scripts/post-count.sh** - New script to count published WordPress blog posts by year or month via `wp db query`:
  - Defaults to `post_type=post` / `post_status=publish` only — pages, CPTs, and drafts excluded unless overridden with `--type` / `--status`
  - Three modes: all-years breakdown (default), single-year total (`--year YYYY`), or monthly breakdown (`--months YYYY`)
  - Runs locally (Trellis VM / server) or remotely via `--ssh HOST`, with `--site DIR` to target other web roots on a shared server
  - Documented in [`scripts/README.md`](scripts/README.md#post-countsh)

### Changed

- **README.md** - Reorganized the Scripts section into four categorized tables (Releases & GitHub, Monitoring & Security, Content & Backups, Images/WooCommerce & Files) covering previously-undocumented scripts, and moved Troubleshooting out of the Trellis table into its own top-level section
- **scripts/README.md** - Updated script count (21 → 22) and added a Content Reporting functional area for `post-count.sh`

## [2.17.0] - 2026-07-04

### Added

- **SSH Connection Multiplexing** - Documented `ControlMaster`/`ControlPersist` setup in [trellis/provision/PROJECT-SETUP.md](trellis/provision/PROJECT-SETUP.md) under "Speed Up SSH with Connection Multiplexing": reuses an authenticated SSH socket across repeat connections to production (log checks, WP-CLI, fail2ban lookups) instead of renegotiating each time. Keyed per remote user via `%r`, so `web@` and `admin_user@` get independent sockets.

## [2.16.0] - 2026-07-04

### Added

- **wp-cli/diagnostics/list-posts-count.sh** - New shell script snippet that lists all published posts via WP-CLI in CSV format and counts the results. Useful for content audits and diagnostics.

## [2.15.0] - 2026-06-26

### Changed

- **scripts/monitoring/ai-bot-monitor.sh** - Expanded AI crawler detection to cover three previously untracked bots:
  - `MistralAI-User` (Mistral's live Le Chat fetcher) and `MistralAI-Index` (Mistral's indexing crawler)
  - `DeepSeekBot` (DeepSeek's web crawler)
  - Added all three to both the `AI_BOTS` display array and the aggregate `AI_PATTERN` matcher, so they now appear in per-bot request/bandwidth counts, scraped-page lists, and robots.txt compliance checks. Verified against two months of production logs: DeepSeekBot was actively crawling (and probing for `.env`/build manifests) but went uncounted, while neither Mistral bot has appeared at all.

## [2.14.0] - 2026-06-23

### Added

- **scripts/monitoring/cf7-smoke-test.js** - Playwright-based smoke test that verifies Contact Form 7 submissions still work after deploying Nginx rate limit changes:
  - Navigates to the contact page, fills form fields, and submits
  - Captures all CF7 REST API requests and verifies 200 responses (schema, feedback, refill)
  - Confirms the success message appears on the page
  - Exits with code 0 on pass, 1 on failure — suitable for CI or post-deploy hooks
  - Configurable via CLI flags: `--name`, `--email`, `--subject`, `--message`
  - Usage: `node cf7-smoke-test.js https://yoursite.com/contact/`

### Changed

- **Mistral Vibe CLI configuration** - Switched from custom system prompt to built-in `cli` prompt with `AGENTS.md` for repo-specific instructions:
  - Changed `system_prompt_id` from `"wp-ops"` to `"cli"` in [.vibe/config.toml](.vibe/config.toml) so Vibe uses its default agent prompt
  - Merged useful content from `.vibe/prompts/wp-ops.md` into [AGENTS.md](AGENTS.md): git workflow (branch naming, CHANGELOG versioning, `create-pr.sh` usage), Mistral Vibe co-author prohibition, and "Context for Tasks" checklist
  - Deleted `.vibe/prompts/wp-ops.md` and the `prompts/` directory — repo-specific rules now live in `AGENTS.md` where Vibe reads them natively

## [2.13.0] - 2026-06-20

### Added

- **Trellis Updater Upstream Change Detection** - Extended [trellis/updater/trellis-updater.sh](trellis/updater/trellis-updater.sh) with post-sync diff analysis for excluded files:
  - Compares each excluded file against the fresh upstream Trellis clone after rsync
  - Saves per-file diffs to `~/trellis-diff/excluded-file-diffs/` for review
  - Reports count of excluded files with upstream changes
  - Detects new upstream files not yet present locally
  - Suggests reviewing diffs with Claude Code to cherry-pick upstream fixes without losing customizations
  - Updated summary steps to include excluded file diff review

## [2.12.0] - 2026-06-14

### Added

- **Multisite Search-Replace Practical Example** - Added a real-world HTTPS theme-asset migration example to [`trellis/backup/README.md`](trellis/backup/README.md) and [`wp-cli/migration/README.md`](wp-cli/migration/README.md):
  - `wp search-replace` invocation with `--all-tables --precise --url=... --path=web/wp --dry-run --report-changed-only`
  - Sample dry-run output showing replacements across the main site and multiple subsites (81 total replacements across 7 sites)
  - Highlights that `--url=` does not scope the search to a single subsite — `--dry-run` is essential before running for real

## [2.11.1] - 2026-06-14

### Added

- **scripts/monitoring/run-monitoring.sh** - Added an optional `domain` argument (after `hours`) so the script can target a different site's logs on multi-site servers (e.g. `./run-monitoring.sh 24 othersite.com`). When a non-default domain is passed, report filenames get a `-<domain>` suffix to avoid collisions between sites, and the summary report now includes the site name. Documented in [`scripts/README.md`](scripts/README.md).

## [2.11.0] - 2026-06-04

### Added

- **scripts/deploy-plugin-wporg.sh** - New script to publish a plugin from its Git working tree to the WordPress.org plugin directory via SVN: syncs `trunk/`, creates `tags/<version>/`, and uploads the marketing `assets/` (banners, icon, screenshots) from `.wordpress-org/`. Respects `.distignore` (same filter as the release zip), auto-detects the main plugin file and version, guards against overwriting a published tag, and is safe by default (stages and prints the `svn ci` command; only commits with `--commit`). Documented in [`scripts/README.md`](scripts/README.md).

## [2.10.1] - 2026-05-30

### Documentation

- **bedrock/README.md** - Added top-level README for the `bedrock/` directory with a brief intro and summary links to each subdirectory: `local-package-development/` (Composer path repository workflow) and `wp-cli-config/` (standard `wp-cli.yml` and `wp pattern validate` command)

## [2.10.0] - 2026-05-30

### Added

- **Bedrock Local Package Development Guide** - New [`bedrock/local-package-development/README.md`](bedrock/local-package-development/README.md) for testing an in-development plugin or theme branch inside a Bedrock site via a Composer `path` repository, before tagging a release:
  - Covers the `symlink: false` requirement (symlinks break plugin/theme activation because `realpath` resolves outside `web/app`)
  - Branch-based constraint setup (`dev-<branch>` form) with inline alias support for cross-package semver constraints
  - Re-sync workflow for keeping the copied mirror up to date during development (`composer update vendor/package`)
  - VCS repository alternative for pushed branches (no local checkout needed)
  - Revert and cleanup steps for after the release is tagged

### Added

- **Bedrock WP-CLI Config** - New [`bedrock/wp-cli-config/`](bedrock/wp-cli-config/) with a standard `wp-cli.yml` and a `wp pattern validate` WP-CLI command for Bedrock projects:
  - `wp-cli.yml` sets `path: web/wp` and `server.docroot: web` for Bedrock's directory layout, and auto-requires the validator on every `wp` call
  - `wp-cli-pattern-validate.php` round-trips block pattern files through WordPress's own `parse_blocks()` / `serialize_blocks()` to produce canonical markup — supports `--fix`, `--diff`, `--log`, and `--log-dir` flags
  - WooCommerce-bundled patterns automatically skipped; `--compliance` / `--compliance-only` hooks for project-specific static analysis
  - Exit codes: `0` (all pass / fixed), `1` (issues found in dry-run)
  - Log output written to `docs/pattern-logs/<date>/` with per-file diffs and a `summary.md`

### Documentation

- **README.md** - Added Bedrock section linking to the new local package development guide; added WP-CLI Config row to the Bedrock table
- **CLAUDE.md** - Added `bedrock/local-package-development/` and `bedrock/wp-cli-config/` to the repository structure
- **.vibe/prompts/wp-ops.md** - Added `wp-cli-config/` to the bedrock entry in Project Structure

## [2.9.0] - 2026-05-26

### Added

- **Upload Release Asset Script** - New [`scripts/upload-release-asset.sh`](scripts/upload-release-asset.sh) for manually attaching a zipped plugin or theme to a GitHub Release when the Actions release event fails to fire (e.g. after a repository rename):
  - Verifies the target release exists before doing any work
  - Runs `npm ci && npx webpack` automatically if `package.json` is present
  - Zips the project respecting `.distignore` exclusions (falls back to excluding only `.git` if no `.distignore`)
  - Detects and prompts before overwriting an existing asset on the release
  - Uploads via `gh release upload` and prints the attached asset size and release URL
  - Cleans up the local zip on completion

### Documentation

- **scripts/README.md** - Documented `upload-release-asset.sh` and corrected script count:
  - Updated script count from 18 → 20 (also fixed a pre-existing off-by-one where `find-and-replace-files.sh` was listed in the directory tree but not counted)
  - Added `upload-release-asset.sh` to the directory structure tree with inline description
  - Updated GitHub Integration overview bullet to mention manual release asset uploads
  - Added full `upload-release-asset.sh` documentation section (features, usage, example output, requirements) after `create-pr.sh`

## [2.8.1] - 2026-05-24

### Changed

- **Traffic Monitor Admin Path Filtering** - Updated [`scripts/monitoring/traffic-monitor.sh`](scripts/monitoring/traffic-monitor.sh) to exclude WordPress admin and API paths from page view analysis:
  - Added `ADMIN_PATTERN` variable filtering `/wp/wp-login.php`, `/wp/wp-admin/`, `/wp-json/`, `/xmlrpc.php`, and `/wp-cron.php`
  - Prevents admin/API traffic from skewing content page view statistics

## [2.8.0] - 2026-05-22

### Added

- **404 Checker Script** - New [`scripts/monitoring/404-checker.sh`](scripts/monitoring/404-checker.sh) for scanning internal links for broken responses:
  - **Global mode** (default) — fetches homepage, extracts and checks all internal links (~30s)
  - **Spider mode** — recursive `wget` spider to configurable depth (default: 3, ~5-10 min)
  - Filters out assets (CSS, JS, images, fonts), feeds, sitemaps, and WordPress admin/API paths to avoid noise
  - Color-coded output (green OK, yellow warnings, red errors, cyan progress)
  - `--output FILE` flag to append broken-link results to a file alongside stdout
  - `--timeout N` flag to control per-request curl max-time (default: 10s)
  - `--level N` flag to control spider recursion depth
  - Exit codes: `0` (no broken links), `1` (broken links found), `2` (usage error / missing dependency)
  - Cross-platform: uses `bash` parameter expansion instead of GNU-specific `sed` flags for macOS/BSD compatibility

## [2.7.3] - 2026-05-12

### Added

- **WP Template DB Override WP-CLI Snippet** - New [`wordpress-utilities/snippets/wp-template-db-override-wpcli.md`](wordpress-utilities/snippets/wp-template-db-override-wpcli.md) for managing block theme template overrides:
  - Detect DB-stored templates (`wp_template` post type) that override theme files
  - Option A: Delete DB override to restore file-system template control
  - Option B: Surgically update specific block markup in the DB copy via `wp eval` + `str_replace`
  - Trellis VM variants for all commands
  - Prevention guidance with `WP_DEVELOPMENT_MODE=theme`

## [2.7.2] - 2026-05-12

### Documentation

- **CLAUDE.md create-pr.sh usage** - Corrected GitHub PR Creation examples to show `--no-interactive` flag:
  - Passing positional args alone does not suppress the AI prompt; `--no-interactive` is required for scripted use
  - Added explicit examples for non-interactive AI, no-AI, and update-mode invocations

- **.vibe/prompts/wp-ops.md create-pr.sh usage** - Updated Git Workflow step 5 to reflect the same fix:
  - Clarified interactive vs. fully non-interactive invocation
  - Added note that positional args without `--no-interactive` still trigger prompts

## [2.7.1] - 2026-05-12

### Documentation

- **CLAUDE.md Structure Update** - Synced repository structure section to match current repo:
  - Added `trellis/security/` (fail2ban and manual IP blocking guides)
  - Added `wordpress-utilities/snippets/` (PHP snippets and WP-CLI references)
  - Added `scripts/woocommerce/`, `batch-resize.sh`, `convert-to-webp.sh`, `find-and-replace-files.sh`, `git-log-oneline.sh`, and `release-plugin.sh` to scripts listing

- **.vibe/prompts/wp-ops.md Structure Update** - Synced project structure to match current repo:
  - Added `trellis/security/` and `wp-cli/security/` subdirectories
  - Added `wordpress-utilities/` section (`age-verification/`, `analytics/`, `snippets/`, `speed-optimization/`)
  - Added `scripts/woocommerce/`, `batch-resize.sh`, `find-and-replace-files.sh`, and `release-plugin.sh` to scripts listing

## [2.7.0] - 2026-05-12

### Added

- **Batch Resize Script** - New [`scripts/batch-resize.sh`](scripts/batch-resize.sh) for processing one or more images:
  - Batch resize with center-crop (maintains aspect ratio, then crops to exact dimensions)
  - Perfect for creating WordPress featured images from screenshots
  - Custom output naming with automatic numbering (`-o`/`--output` prefix)
  - Configurable dimensions (`-w`/`--width`, `-H`/`--height`), format (`-f`/`--format`: jpg, png, webp), and quality (`-q`/`--quality`)
  - **Dry-run mode** (`-d`/`--dry-run`) to preview changes safely
  - **Delete originals** (`--delete`) option for cleanup after conversion
  - WebP output via `cwebp` pipe (consistent with `convert-to-webp.sh`; validated upfront before processing)

- **WooCommerce Variation Creation Script** - New [`scripts/woocommerce/create-product-variations.sh`](scripts/woocommerce/create-product-variations.sh) for bulk-creating product variations via WP-CLI:
  - Creates all combinations of attribute values for a variable product
  - Configurable via environment variables (product ID, price, attributes, etc.)
  - Trellis VM compatible with `--workdir` and `--url` support
  - Success/failure tracking with detailed output
  - See companion snippet [`wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md`](wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md) for attribute setup

### Documentation

- **scripts/README.md** - Updated directory structure and script count (16 → 18)
  - Added `batch-resize.sh` to root-level scripts list
  - Added WooCommerce subdirectory with `create-product-variations.sh` to directory structure
  - Added comprehensive documentation section for batch-resize.sh with usage examples

- **wordpress-utilities/snippets/README.md** - Added WooCommerce product attributes WP-CLI snippet:
  - New entry for [`woocommerce-product-attributes-wpcli.md`](wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md)
  - Comprehensive guide for creating and managing WooCommerce attributes and terms via WP-CLI

## [2.6.0] - 2026-05-05

### Added

- **Admin User Creation Snippets** - New snippets in [`wordpress-utilities/snippets/`](wordpress-utilities/snippets/):
  - [`admin-user-creation.php`](wordpress-utilities/snippets/admin-user-creation.php) - Temporary admin user creation for functions.php with placeholder values and safety checks
  - [`admin-user-creation-wpcli.md`](wordpress-utilities/snippets/admin-user-creation-wpcli.md) - Comprehensive WP-CLI guide with secure password generation, emergency recovery, batch creation, and cleanup commands

## [2.5.15] - 2026-05-01

### Added

- **Find and Replace Files Script** - New [`scripts/find-and-replace-files.sh`](scripts/find-and-replace-files.sh) utility for batch operations across projects:
  - Finds all instances of a file by name recursively through directory trees
  - Replaces multiple copies with an updated version in one operation
  - **Dry-run mode** (`-n`/`--dry-run`) to preview changes before applying
  - **List-only mode** (`-l`/`--list`) to just locate files
  - **Size display** (`-s`/`--size`) to show file sizes and line counts
  - Configurable search directory (`-d`/`--directory`) and max depth (`-m`/`--maxdepth`)
  - Preserves file permissions (executable flags)
  - Safe handling of filenames with spaces (null-terminated output)

### Documentation

- **README for Find and Replace Script** - New [scripts/README-FIND-AND-REPLACE.md](scripts/README-FIND-AND-REPLACE.md) with:
  - Comprehensive usage examples and options reference
  - Use cases for batch script updates and file synchronization
  - Best practices for dry-run workflow
- **scripts/README.md** - Updated directory structure and script count (15 → 16)
  - Added `find-and-replace-files.sh` to root-level scripts list

## [2.5.14] - 2026-05-01

### Added

- **One-Step Resize and Convert to WebP Documentation** - Enhanced [nginx/image-optimization/RESIZE-AND-CONVERSION.md](nginx/image-optimization/RESIZE-AND-CONVERSION.md) with a new dedicated section:
  - One-step pipe-based workflow combining ImageMagick resize with `cwebp` conversion
  - Reference to existing [`scripts/convert-to-webp.sh`](scripts/convert-to-webp.sh) as the recommended reusable tool
  - Usage examples for different dimensions and quality settings
  - Links to full script documentation in scripts/README.md

### Changed

- **Create PR Script Help Documentation** - Updated [`scripts/create-pr.sh`](scripts/create-pr.sh) with `--help`/`--h` flag support:
  - Added help function with clean usage, options, arguments, and examples display
  - Updated header comments to reflect new options
- **CREATE-PR.md Documentation** - Enhanced [CREATE-PR.md](CREATE-PR.md) with comprehensive updates:
  - Added `--help` flag documentation and examples
  - Added Vibe CLI support throughout (AI backend, installation, environment variables)
  - Updated AI backend options to include vibe alongside claude and codex
  - Added note about help message availability
- **.vibe/prompts/wp-ops.md Workflow** - Updated [.vibe/prompts/wp-ops.md](.vibe/prompts/wp-ops.md) with detailed standard workflow:
  - Step-by-step branch creation, atomic commits, CHANGELOG updates, push, and PR creation
  - Added create-pr.sh usage examples
  - Enhanced Git Workflow section with clear process

## [2.5.13] - 2025-05-06

### Added

- **Git Log Oneline Script** - New [scripts/git-log-oneline.sh](scripts/git-log-oneline.sh) utility for showing recent git commits as compact one-liners:
  - Displays short commit hash and message on a single line per commit
  - Accepts optional argument for number of commits to show (default: 10)
  - Includes input validation and error handling
  - Useful for quickly reviewing recent work before creating PRs or checking recent changes

## [2.5.12] - 2026-04-30

### Changed

- **convert-to-webp.sh IM7 Compatibility** - Updated [scripts/convert-to-webp.sh](scripts/convert-to-webp.sh) to use `magick` (ImageMagick 7+) with automatic fallback to `convert` (ImageMagick 6) for backwards compatibility, fixing deprecation warning in newer ImageMagick versions

## [2.5.11] - 2026-04-30

### Added

- **WebP Featured Image Conversion Script** - New [scripts/convert-to-webp.sh](scripts/convert-to-webp.sh) for converting JPG images to WebP format optimized for WordPress featured images and Facebook Open Graph sharing:
  - Defaults to 800×419 px (1.91:1 ratio — Facebook OG minimum-compliant, above 600×315 floor)
  - Uses ImageMagick center-crop (`-resize WxH^` + `-gravity center -extent`) to avoid distortion on non-1.91:1 sources
  - Pipes cropped output directly to `cwebp -q 82` for efficient single-step conversion
  - Accepts optional arguments: output filename, quality (default 82), width (default 800), height (default 419)

- **WebP Featured Image Snippet** - New [wordpress-utilities/snippets/webp-featured-image.md](wordpress-utilities/snippets/webp-featured-image.md) with command reference for WebP conversion:
  - Single image and batch conversion examples using ImageMagick + cwebp pipeline
  - Quality settings guidance and Nginx integration notes
  - Batch convert with existing WebP check (skip already-converted files)
  - Complete workflow example for uploads directories

- **Mistral Vibe CLI Project Configuration** - New [.vibe/](:.vibe/) directory with project-specific Vibe CLI setup:
  - `config.toml` — model settings (mistral-medium-3.5), tool permissions, session logging config
  - `prompts/wp-ops.md` — project system prompt covering repo structure, coding style, safety rules, and git workflow

### Changed

- **scripts/README.md** - Added Image Utilities as a fifth functional area:
  - Updated script count from 13 to 14
  - Added `convert-to-webp.sh` to directory structure
  - Added quick start example for image conversion
  - Added dedicated Image Utilities section with usage, requirements, and cross-reference to the snippet

- **wordpress-utilities/snippets/README.md** - Added entry for `webp-featured-image.md` with feature summary and setup steps

## [2.5.10] - 2026-04-23

### Changed

- **redirect-check.sh Moved to Monitoring** - Relocated [scripts/monitoring/redirect-check.sh](scripts/monitoring/redirect-check.sh) from `wordpress-utilities/snippets/` to `scripts/monitoring/` where it better fits alongside other diagnostic shell scripts:
  - Replaced hardcoded `imagewize.com` example URLs with `example.com` placeholders
  - Updated [wordpress-utilities/snippets/README.md](wordpress-utilities/snippets/README.md) to remove the entry
  - Updated [scripts/README.md](scripts/README.md) with the script in the directory tree, Quick Start section, and a full Monitoring Scripts entry

## [2.5.9] - 2026-04-22

### Added

- **Google Organic Referrals Quick Reference** - New [scripts/monitoring/GOOGLE-ORGANIC-REFERRALS.md](scripts/monitoring/GOOGLE-ORGANIC-REFERRALS.md) with Nginx access log commands for extracting organic traffic data:
  - Full organic landing page breakdown with hit counts sorted by most visited
  - Bot and crawler noise filtering (Googlebot, AhrefsBot, SemrushBot, etc.)
  - Distinct organic landing page count over a 24h window
  - Per-slug organic traffic check
  - Category-scoped hit lookup excluding bots

- **Post Expiry Noindex WP-CLI Checks** - New [wordpress-utilities/snippets/post-expiry-noindex-wpcli-checks.md](wordpress-utilities/snippets/post-expiry-noindex-wpcli-checks.md) with diagnostic commands for verifying the post expiry noindex feature:
  - Check `_post_expiry_date` meta is saved correctly
  - Verify post category membership against configured expiry categories
  - Timezone-aware expiry logic test via `wp eval` that bypasses `is_singular()` (always false in WP-CLI context)
  - Notes on Yoast SEO admin UI limitations and staging noindex behaviour

### Changed

- **RESIZE-AND-CONVERSION.md WordPress Featured Image Workflow** - Added new [WordPress Featured Image from macOS Screenshot](nginx/image-optimization/RESIZE-AND-CONVERSION.md) section:
  - Uses built-in `sips` to scale Retina screenshots (2× resolution) to 1200px wide before converting
  - `cwebp` conversion at quality 85 — ~95% size reduction vs unscaled PNG
  - One-liner workflow with input/output path variables
  - Naming convention guidance (`{post-slug}-{descriptor}.webp`)
  - Comparison of `sips` vs ImageMagick for single-file proportional resizes

## [2.5.8] - 2026-04-06

### Changed

- **README restructured** - Reorganized [README.md](README.md) for clarity and conciseness:
  - Grouped tools into sections (Trellis, WP-CLI, Nginx, Scripts, WordPress Utilities) with a TOC
  - Shortened descriptions and removed redundant label text in the Docs column
  - Removed empty Quick Start section
  - Moved Troubleshooting under Trellis
  - Added missing Snippets entry to the tools table

## [2.5.7] - 2026-04-06

### Added

- **WordPress Snippets Directory** - New [wordpress-utilities/snippets/](wordpress-utilities/snippets/) directory for small, self-contained PHP snippets:
  - `post-expiry-noindex.php` — Auto-noindex posts past their expiry date via Yoast SEO's `wpseo_robots` filter, evaluated in the site's configured WordPress timezone (not UTC); adds a "Noindex After Date" meta box to the post sidebar; scoped to configurable category IDs; outputs `noindex, follow`
  - `README.md` — Snippet index with usage notes, dependencies (Yoast SEO, WP 5.3+), and setup instructions
- Updated [wordpress-utilities/README.md](wordpress-utilities/README.md) to document the new Snippets section

## [2.5.6] - 2026-03-28

### Added

- **AI Bot Monitor** - New [scripts/monitoring/ai-bot-monitor.sh](scripts/monitoring/ai-bot-monitor.sh) script for analyzing AI crawler traffic from Nginx logs:
  - Detects 20+ AI crawlers (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, CCBot, Bytespider, etc.)
  - Reports requests and bandwidth per crawler, top scraped pages (overall + per bot), traffic by hour, HTTP status codes, robots.txt compliance, and IP breakdown
  - Optional operator IP cross-check to distinguish tool sessions from autonomous crawlers
  - Accepts optional `output_file` argument to save report to disk
  - Uses gawk-based timestamp filtering for accurate time windows

- **Run Monitoring Orchestrator** - New [scripts/monitoring/run-monitoring.sh](scripts/monitoring/run-monitoring.sh) script that runs all three monitors in sequence:
  - Runs `traffic-monitor.sh`, `security-monitor.sh`, and `ai-bot-monitor.sh` with timestamped output files
  - Generates a consolidated `monitoring-summary-YYYY-MM-DD.md` markdown report with key metrics
  - Auto-detects production vs. local context for output directory selection
  - Designed for remote execution: `ssh web@example.com 'bash -s' < run-monitoring.sh`

### Changed

- **traffic-monitor.sh Accurate Time Filtering** - Updated [scripts/monitoring/traffic-monitor.sh](scripts/monitoring/traffic-monitor.sh) to use gawk-based timestamp parsing instead of tail-line estimation:
  - Replaced `tail -n estimated_lines` with exact epoch-based filtering via `gawk`; falls back to tail estimate if gawk is unavailable
  - Added optional `output_file` third argument — pipes output to both stdout and file via `tee`
  - Increased top pages from 10 to 50 results
  - Improved "Analyzing..." label to show exact cutoff timestamp

- **security-monitor.sh Accurate Time Filtering** - Updated [scripts/monitoring/security-monitor.sh](scripts/monitoring/security-monitor.sh) with the same gawk-based timestamp filtering:
  - Replaced tail estimation with exact epoch-based filtering; gawk fallback preserved
  - Added optional `output_file` fourth argument for saving reports to disk
  - Added cutoff timestamp label to analysis header

## [2.5.5] - 2026-03-25

### Added

- **Trellis Updater php-fpm-pool Template Preservation** - Extended [trellis/updater/trellis-updater.sh](trellis/updater/trellis-updater.sh) to preserve custom PHP-FPM pool template:
  - Added `--exclude="roles/wordpress-setup/templates/php-fpm-pool-wordpress.conf.j2"` to rsync exclusion list
  - Added comment noting this preserves custom `request_terminate_timeout` settings

### Changed

- **create-pr.sh Update Mode Prompts** - Fixed [scripts/create-pr.sh](scripts/create-pr.sh) interactive mode to skip base branch and PR title prompts when running with `--update` flag
- **create-pr.sh Vibe stdin Fix** - Fixed Vibe CLI invocation to use `< /dev/null` to prevent stdin blocking in non-interactive contexts

### Documentation

- **CLAUDE.md Git Conventions** - Updated Git Commit and PR Conventions section:
  - Added atomic commits policy (one logical change per commit)
  - Replaced co-authorship attribution note with a no-Claude-mentions policy

## [2.5.4] - 2026-02-18

### Added

- **Trellis Updater security.yml Preservation** - Extended `trellis/updater/trellis-updater.sh` and `trellis/updater/manual-update.md` to preserve `group_vars/all/security.yml` during Trellis updates:
  - Added `--exclude="group_vars/all/security.yml"` to rsync exclusion list in both the automated script and manual update guide
  - Added post-update verification check in `trellis-updater.sh` that warns when the `wordpress_wp_login` fail2ban jail is missing or disabled
  - Documented `security.yml` in the manual update notes with a warning about fail2ban jail configuration (bantime, maxretry, IP whitelist)

## [2.5.3] - 2026-02-10

### Added

- ** Multi Site site addition issues and solutions** 
  - Added Multi site site addition trouble shooting section including commands to deal with issues when ID, slug and or name don't match post addition new site

## [2.5.2] - 2026-02-10

### Added

- **Mistral Vibe AI Support for PR Creation** - Enhanced [scripts/create-pr.sh](scripts/create-pr.sh) with Mistral Vibe CLI integration:
  - Added `--ai=vibe` flag for explicit Mistral Vibe selection alongside Claude and Codex
  - Automatic detection of Vibe CLI with multi-tool selection prompt
  - Environment variable support for custom Vibe command (`VIBE_COMMAND`) and arguments (`VIBE_CLI_ARGS`)
  - Vibe-specific command execution with `-p` flag and `--output text` parameter
  - Interactive AI tool selection now includes Vibe when multiple CLIs are available
  - Updated [scripts/README.md](scripts/README.md) with Vibe installation instructions and usage examples

### Changed

- **PR Creation Script AI Backend** - Updated [scripts/create-pr.sh](scripts/create-pr.sh) option parsing and execution logic:
  - Extended AI tool validation to accept "claude", "codex", or "vibe"
  - Enhanced non-interactive mode to support Vibe as fallback option
  - Updated error messages to include Vibe in supported AI tools list
  - Modified AI tool detection to check for all three CLI tools (Claude, Codex, Vibe)

## [2.5.1] - 2026-02-10

### Changed

- **Trellis Updater File Preservation** - Extended [trellis/updater/trellis-updater.sh](trellis/updater/trellis-updater.sh) to preserve additional custom files:
  - **Custom Ansible playbooks** - Database and files management playbooks (`database-backup.yml`, `database-pull.yml`, `database-push.yml`, `files-backup.yml`, `files-pull.yml`, `files-push.yml`, `uploads.yml`)
  - **Custom Nginx configurations** - Project-specific Nginx includes (`nginx-includes/` directory)
  - **Custom documentation** - Project docs and changelogs (`docs/`, `CHANGELOG.md`, `CHANGELOG-TRELLIS-DATABASE-UPLOADS-MIGRATION.md`)
  - Updated [trellis/updater/README.md](trellis/updater/README.md) to document newly preserved file categories

### Improved

- Trellis updater script now preserves a more comprehensive set of custom configurations during version updates
- Better documentation of which files and directories are excluded from rsync during Trellis updates

## [2.5.0] - 2026-01-30

### Added

- **SEO-Focused Traffic Analysis Enhancements** - Major upgrade to [scripts/monitoring/traffic-monitor.sh](scripts/monitoring/traffic-monitor.sh) with comprehensive SEO analytics:
  - **404 Error Analysis** - Identifies broken links and missing content from real users (excluding bots) with actionable redirect recommendations
  - **Search Engine Crawler Activity** - Tracks Googlebot, Bingbot, DuckDuckBot, Baiduspider, Yandex, and Slurp activity with most-crawled pages analysis
  - **Mobile vs Desktop Traffic** - Device type breakdown with mobile-first indexing recommendations based on traffic percentages
  - **Organic Search Traffic Sources** - Identifies which search engines are sending traffic with robust filtering to exclude spoofed referrers
  - **Top Landing Pages (External Traffic)** - Shows which content pages attract external visitors, excluding admin pages and malware scans
  - **Social Media Traffic** - Tracks referrals from Facebook, Twitter, LinkedIn, Instagram, Pinterest, Reddit, YouTube, and t.co
  - **Redirect Analysis (301/302)** - Lists all redirects with color-coded SEO impact indicators (301 = permanent, 302 = temporary)
  - **URL Depth Analysis** - Analyzes site structure with recommendations to keep content within 3 clicks for better crawling
  - New configuration variable `SEO_BOTS` for targeting legitimate search engine crawlers

### Improved

- **Advanced Referrer Filtering** - Enhanced fake referrer detection to block sophisticated attack patterns:
  - Filters spoofed search engine referrers (e.g., `imagewize.com//yahoo.php` masquerading as Yahoo traffic)
  - Blocks attack patterns: `.php` files, `/config/`, `//`, `/./`, `.env`, `.git`, `.yml`, `.dockerenv`
  - Excludes WordPress admin/malware scans: `wp-login`, `wp-admin`, `xmlrpc.php`, `/db.php`, `seotheme`, `timthumb`
  - Removes Magento config scans (`/app/etc/`), random PHP shells (8-character filenames), and AWS config scans (`.ebextensions`)
  - Prevents same-domain referrers from appearing in external referrer lists
  - Social media filters now require actual platform domains (facebook.com, twitter.com, etc.)

- **Separation of Concerns** - Clear division between traffic analysis (traffic-monitor.sh) and security monitoring (security-monitor.sh):
  - Traffic monitor focuses on SEO insights, content performance, and user behavior
  - Security monitor handles threat detection, brute force attempts, and malicious activity
  - No duplication of security-focused analysis between scripts

### Changed

- **Enhanced External Referrers Section** - Now uses site domain extraction from log file path for accurate same-domain filtering
- **Improved Landing Pages Analysis** - Multi-layer filtering pipeline to show only legitimate content pages
- **Better Organic Search Detection** - Domain-specific matching (google.com, bing.com) instead of keyword matching to prevent spoofing
- Updated report structure with dedicated "SEO & Content Analysis" section following standard traffic metrics

## [2.4.2] - 2026-01-21

### Fixed

- **Plugin Release Script Version Update** - Replaced fragile `sed` pattern matching with robust `awk`-based version updates in [scripts/release-plugin.sh](scripts/release-plugin.sh):
  - Replaced two `sed` commands with single `awk` script for plugin file version updates
  - More reliable pattern matching for plugin header "Version:" field
  - More reliable pattern matching for `define( 'ELAYNE_BLOCKS_VERSION', ... )` constant
  - Eliminates dependency on POSIX character classes in sed (which vary by platform)
  - Single temp file operation instead of multiple in-place edits
  - More portable solution that works consistently across macOS, Linux, and BSD systems

## [2.4.1] - 2026-01-21

### Fixed

- **Plugin Release Script sed Pattern** - Fixed version update regex in [scripts/release-plugin.sh](scripts/release-plugin.sh) to correctly handle whitespace in plugin header:
  - Replaced `\s*` with `[[:space:]]*` for POSIX-compliant whitespace matching in sed
  - Ensures proper version number updates in plugin file headers
  - Resolves issues where version updates might fail due to whitespace variations

## [2.4.0] - 2026-01-20

### Added

- **WordPress Plugin Release Automation** - New AI-powered plugin release script with comprehensive changelog generation:
  - **[scripts/release-plugin.sh](scripts/release-plugin.sh)** - Automated version bumping and changelog generation for WordPress plugins (422 lines)
  - Multi-AI backend support (Claude CLI or Codex) with automatic detection and interactive selection
  - Semantic versioning validation (X.Y.Z format)
  - Updates three files automatically: main plugin file (version header and constant), readme.txt (stable tag and changelog), CHANGELOG.md (detailed version history)
  - AI-powered changelog generation in two formats:
    - **CHANGELOG.md**: Detailed Keep a Changelog format with sections (Changed, Added, Fixed, Technical)
    - **readme.txt**: Concise WordPress.org style with single-line entries
  - Git diff analysis between current branch and main branch
  - Interactive confirmation prompts with change preview
  - Optional `--commit` flag for automatic commits with standardized messages
  - `--ai=claude|codex` flag for explicit AI tool selection
  - Environment variable support for custom CLI commands and arguments (`CLAUDE_COMMAND`, `CODEX_COMMAND`, `CLAUDE_CLI_ARGS`, `CODEX_CLI_ARGS`)
  - Safety features: git diff preview, backup files (.bak), color-coded output, no-changes detection
  - Token usage: 500-1,500 tokens per release (~$0.01-0.05 cost)

### Changed

- Enhanced [scripts/README.md](scripts/README.md) with WordPress Plugin Release documentation:
  - Updated directory structure to include release-plugin.sh
  - Changed "Theme Management" to "WordPress Management" to reflect broader scope
  - Added comprehensive release-plugin.sh section (after create-pr.sh, before release-theme.sh)
  - Documented features, usage examples, workflow, changelog formats, AI tool selection, and requirements
  - Updated script count from 9 to 10 utility scripts
  - Reorganized functional areas to include "WordPress Management" category

- Updated main [README.md](README.md) tools table:
  - Added Plugin Release Script entry between PR Creation and Theme Release
  - Consistent tool ordering: PR Creation → Plugin Release → Theme Release → Theme Sync

### Improved

- Complete parity between plugin and theme release automation workflows
- Unified AI-powered changelog generation for both WordPress plugins and themes
- Consistent documentation structure across all release automation scripts
- Better developer experience with interactive AI tool selection when multiple CLIs available

## [2.3.6] - 2026-01-15

### Fixed

- **PR Update Handling** - Improved [scripts/create-pr.sh](scripts/create-pr.sh) to detect `gh pr view` failures before checking PR number, preventing false "no PR found" states when the GitHub CLI call fails

## [2.3.5] - 2026-01-10

### Added

- **Theme Release Script Multi-AI Support** - Enhanced [scripts/release-theme.sh](scripts/release-theme.sh) with flexible AI backend selection:
  - Added `--ai=claude|codex` flag for explicit AI tool selection
  - Interactive AI tool selection when both Claude and Codex CLIs are available
  - Environment variable support for custom CLI command names (`CLAUDE_COMMAND`, `CODEX_COMMAND`)
  - Support for custom AI CLI arguments via `CLAUDE_CLI_ARGS` and `CODEX_CLI_ARGS` environment variables
  - Improved error handling with detailed AI CLI failure messages

### Changed

- **Enhanced Theme Release Documentation** - Updated [scripts/README.md](scripts/README.md) with multi-AI backend documentation:
  - Updated release-theme.sh description to mention both Claude CLI and Codex support
  - Added `--ai` flag examples in Usage section
  - Enhanced Requirements section with both Claude and Codex installation instructions
  - Clarified AI-Generated Changelogs feature supports multiple AI backends

### Improved

- Refactored release-theme.sh option parsing to use `case` statement for better maintainability
- Enhanced AI CLI detection to check for both Claude and Codex availability
- More flexible AI tool configuration with environment variable overrides
- Better user experience with automatic AI tool selection based on availability

## [2.3.4] - 2026-01-09

### Changed

- **Standardized admin username placeholder across documentation** - Replaced hardcoded usernames with `admin_user` placeholder for better clarity and universality:
  - **[trellis/README.md](trellis/README.md)** - Updated fail2ban examples to use `admin_user` placeholder with note explaining to replace with configured username
  - **[trellis/provision/PROJECT-SETUP.md](trellis/provision/PROJECT-SETUP.md)** - Replaced `warden` references with `admin_user` throughout SSH and provisioning examples
  - **[trellis/security/MANUAL-IP-BLOCKING.md](trellis/security/MANUAL-IP-BLOCKING.md)** - Standardized all SSH commands to use `admin_user` placeholder with explanation
  - **[troubleshooting/MAIL.md](troubleshooting/MAIL.md)** - Added comprehensive SSH user access guide explaining `web`, `admin_user`, and `root` user roles with usage recommendations

### Added

- **Mail Troubleshooting Enhancement** - Expanded [troubleshooting/MAIL.md](troubleshooting/MAIL.md) with comprehensive WordPress email bounce diagnosis and solutions:
  - New "SSH User Access" section explaining when to use `web`, `admin_user`, and `root` users
  - New "Issue 2: WordPress Email Bounces - Non-Existent Admin Email" section covering:
    - Multisite network admin email configuration issues
    - WP-CLI commands for diagnosing and updating admin emails across sites
    - Comprehensive testing procedures for server-level and WordPress email functionality
    - Prevention best practices for initial setup and regular audits
    - Common pitfalls to avoid (non-existent subdomains, `.test` domains in production)
  - Detailed examples for single sites and multisite networks
  - Bulk operations for updating multiple subsites
  - Email monitoring and documentation recommendations

### Improved

- Better documentation clarity by using consistent placeholder usernames (`admin_user`) instead of specific usernames (`warden`, `admin`, `deploy`)
- Enhanced troubleshooting workflow with clear user role separation and appropriate permissions
- All SSH command examples now include contextual notes about which user to use and why

## [2.3.3] - 2026-01-07

### Added

- **Trellis Backup Documentation Enhancement** - Added alternative direct shell script method for database pull operations:
  - **[trellis/backup/README.md](trellis/backup/README.md)** - New section documenting shell script approach for interactive development
  - Standard site example with SSH pipe streaming from production to development
  - Multisite example with `--url` parameter for proper search-replace context
  - Comprehensive comparison of when to use shell scripts vs Ansible playbooks
  - Advantages: Single command execution, full visibility, SSH pipe streaming (no intermediate files), includes cache flushing
  - Use cases: Manual work, quick syncs, troubleshooting vs automation/CI-CD
  - Complete Table of Contents for improved navigation

### Changed

- Enhanced [trellis/backup/README.md](trellis/backup/README.md) with comprehensive Table of Contents
- Improved navigation with hierarchical TOC including all sections (Overview, Configuration, Automation, Troubleshooting)
- Added new "Alternative: Direct Shell Script Method" subsection under Database Pull with proper TOC linking

## [2.3.2] - 2026-01-03

### Fixed

- **Theme Release Script JSON Parsing** - Enhanced changelog extraction in [scripts/release-theme.sh](scripts/release-theme.sh) to properly handle escaped quotes and backslashes in Claude AI responses:
  - Replaced fragile `grep`/`sed` approach with robust `awk`-based JSON value extraction
  - Fixed issue where changelog entries containing escaped quotes (`\"`) would be truncated or malformed
  - Improved handling of escaped newlines (`\n`) in multi-line changelog content
  - More reliable parsing of Claude CLI JSON output for both `changelog_md` and `readme_txt` fields

## [2.3.1] - 2026-01-01

### Changed

- **Standardized placeholder domain across documentation** - Replaced `imagewize.com` with `example.com` for consistency in all generic examples and documentation:
  - Updated 13 files across scripts, documentation, and configuration examples
  - Affected files: PAGE-CREATION.md, MULTI-SITE-MIGRATION.md, CRON.md, PROJECT-SETUP.md, nginx/README.md, nginx/redirects/README.md, scripts/README.md, monitoring scripts, and more
  - Preserved historical references to `imagewize.com` in CHANGELOG.md to maintain accurate project history
  - Preserved real-world production data and case studies in security documentation (FAIL2BAN.md, security/README.md, MANUAL-IP-BLOCKING.md) which contain actual attack statistics and production examples
  - Enhanced documentation clarity by using industry-standard `example.com` placeholder domain (RFC 2606)

## [2.3.0] - 2026-01-01

### Added

- **Trellis fail2ban WordPress Protection Documentation**:
  - **[trellis/security/README.md](trellis/security/README.md)** - Security overview covering fail2ban automatic IP blocking and manual Nginx deny rules
  - **[trellis/security/FAIL2BAN.md](trellis/security/FAIL2BAN.md)** - Comprehensive fail2ban setup guide with WordPress wp-login.php protection, XML-RPC abuse prevention, configuration examples, monitoring commands, and troubleshooting
  - **[trellis/security/MANUAL-IP-BLOCKING.md](trellis/security/MANUAL-IP-BLOCKING.md)** - Advanced manual IP blocking via Nginx deny directives for extreme high-volume attacks, with implementation examples and best practices
  - Automatic IP blocking after brute force attempts (default: 6 failed attempts = 10 minute ban)
  - Zero-maintenance WordPress security via fail2ban (pre-installed in Trellis, disabled by default)
  - Real-world attack statistics showing 40+ unique attacker IPs with 20-200 failed login attempts each (Nov-Dec 2025)
  - Production impact demonstration: 1,420 wp-login attempts from single IP blocked automatically after enabling fail2ban
  - IP whitelist configuration to prevent self-lockout
  - Integration with [wp-cli/security](wp-cli/security/) malware scanners for comprehensive security workflow

### Changed

- Enhanced main [trellis/README.md](trellis/README.md) with new Security section (#3) including:
  - fail2ban WordPress protection features (automatic blocking, temporary bans, zero maintenance)
  - Manual IP blocking for extreme cases (high-volume attacks, persistent attackers)
  - Security monitoring tools (banned IPs, attack patterns, fail2ban logs)
  - Quick start guide for enabling WordPress protection
  - Real-world impact statistics (before/after fail2ban)
  - Cross-references to security documentation and malware scanners
- Renumbered existing sections: Provisioning & Setup (#3 → #4), Trellis Updater (#4 → #5)

### Improved

- Complete fail2ban WordPress jail configuration examples with recommended, stricter, and lenient settings
- Monitoring and management commands for checking status, viewing banned IPs, and manual IP management
- Self-lockout prevention with IP whitelist and emergency recovery procedures
- Detailed troubleshooting for common issues (jail not enabled, filter patterns, log paths)
- Clear comparison table showing when to use fail2ban vs manual IP blocks
- Integration workflow combining prevention (fail2ban), detection (malware scanners), and analysis (access logs)

## [2.2.2] - 2025-12-31

### Changed

- **Enhanced Trellis Provisioning Documentation**:
  - **[trellis/provision/README.md](trellis/provision/README.md)** - Added comprehensive Table of Contents with organized sections:
    - Setup Guides section linking to NEW-MACHINE.md and PROJECT-SETUP.md
    - Configuration Guides section linking to CRON.md
    - Command Reference section for general provisioning commands
  - Added "Quick Command Reference" introduction section explaining the purpose of provisioning commands and when to use them
  - Improved navigation with clear separation between initial setup guides and day-to-day command reference
  - Better workflow organization following natural user progression (machine setup → project setup → configuration → commands)

## [2.2.1] - 2025-12-31

### Added

- **Repository Logo** - Custom SVG logo with dark mode support:
  - **[assets/logo.svg](assets/logo.svg)** - Adaptive logo with theme-aware colors (gray-600 light mode, gray-400 dark mode)
  - Logo design inspired by Opsgenie icon from Blade Icons
  - Updated main [README.md](README.md) with centered logo header and credits section

- **WordPress Utilities Overview Documentation**:
  - **[wordpress-utilities/README.md](wordpress-utilities/README.md)** - Comprehensive guide to reusable WordPress components and tools
  - Detailed documentation for Age Verification, Analytics, and Speed Optimization utilities
  - Integration examples for theme functions, deployment scripts, and site audits
  - Best practices for security, performance, and maintenance
  - Coding standards and file organization guidelines
  - Contributing guidelines for adding new utilities

### Changed

- Enhanced main [README.md](README.md) header with visual logo and "WP OP" branding
- Added Credits section to main README acknowledging logo design inspiration

## [2.2.0] - 2025-12-31

### Added

- **WordPress Security Scanner Suite** - Comprehensive dual-scanner malware detection and security auditing system:
  - **[wp-cli/security/scanner-targeted.php](wp-cli/security/scanner-targeted.php)** - Site-specific threat detection for common WordPress vulnerabilities (Facebook redirects, file disclosure, SQL injection, PHP malware, code obfuscation) - Fast performance: ~1.7 seconds for 6,600 files
  - **[wp-cli/security/scanner-general.php](wp-cli/security/scanner-general.php)** - Broad-spectrum malware detection (known malware filenames, pharmaceutical spam, SEO spam, webshells, backdoor functions, encoding layers) - Comprehensive scan: ~2.5 seconds for 7,400 files
  - **[wp-cli/security/scanner-wrapper.php](wp-cli/security/scanner-wrapper.php)** - Wrapper script that runs both scanners sequentially for complete coverage
  - **[wp-cli/security/README.md](wp-cli/security/README.md)** - Complete documentation with installation, usage, troubleshooting, and hosting-specific guides (WP-CLI, direct PHP, cPanel/Plesk, browser access)
  - **[wp-cli/security/SECURITY-GUIDE.md](wp-cli/security/SECURITY-GUIDE.md)** - Detailed usage guide with scanning strategies, integration workflows, and security best practices
  - **[wp-cli/security/SCANNER-SUMMARY.md](wp-cli/security/SCANNER-SUMMARY.md)** - Quick reference guide for busy developers with common false positives and real threat examples
  - Multi-execution support: WP-CLI (`wp eval-file`), direct PHP, remote via SSH/Trellis, cron automation
  - Severity-based reporting (CRITICAL, HIGH, MEDIUM) with colored CLI output
  - Comprehensive hosting support: VPS/dedicated servers, shared hosting (SSH/FTP), cPanel/Plesk, Trellis/Bedrock
  - Security-conscious design with IP whitelisting for browser access (not recommended)

### Changed

- Updated main [README.md](README.md) to include Security Scanners tool in tools table
- Updated [CLAUDE.md](CLAUDE.md) repository structure documentation to include `wp-cli/security/` directory
- Enhanced [CLAUDE.md](CLAUDE.md) Common Commands section with Security Scanning examples and execution methods

### Improved

- Dual-scanner strategy provides both fast weekly monitoring (targeted) and comprehensive monthly audits (general)
- Extensive troubleshooting documentation covering WP-CLI installation, hosting restrictions, PHP versions, file permissions, and timeout/memory issues
- Clear separation between recommended (WP-CLI/direct PHP) and last-resort (browser) execution methods
- Integration guidance with wp-ops workflows (pre-deployment checks, post-deployment verification, incident response)

## [2.1.0] - 2025-12-31

### Added

- **WordPress Utilities Module** - New top-level directory for reusable WordPress components and tools:
  - **[wordpress-utilities/age-verification/](wordpress-utilities/age-verification/)** - Cookie-based age verification system with modal interface, ACF integration, and dynamic content filtering (JavaScript, CSS, PHP template)
  - **[wordpress-utilities/analytics/](wordpress-utilities/analytics/)** - Comprehensive analytics implementation guide covering Google Analytics (Site Kit and manual), Matomo (plugin and self-hosted), and detection methods using curl/grep
  - **[wordpress-utilities/speed-optimization/](wordpress-utilities/speed-optimization/)** - Performance testing tools with TTFB analysis using curl and wget, including Google's web.dev performance guidelines

- **WP-CLI Migration Enhancement**:
  - **[wp-cli/migration/URL-UPDATE-METHODS.md](wp-cli/migration/URL-UPDATE-METHODS.md)** - Generic WordPress URL update methods covering WP-CLI (recommended), wp-config.php constants, direct database updates, admin panel, and multisite network handling

### Changed

- **Repository Integration** - Merged [wordpress-tools](https://github.com/imagewize/wordpress-tools) repository into wp-ops for unified WordPress operations management
- Updated main [README.md](README.md) with four new tool entries: Age Verification, Analytics, Speed Optimization, and URL Update Methods
- Updated [CLAUDE.md](CLAUDE.md) repository structure documentation to reflect new `wordpress-utilities/` directory
- Created deprecation notice in wordpress-tools repository directing users to wp-ops

### Improved

- Consolidated WordPress operations tooling into single repository for better discoverability and maintenance
- Clear separation between infrastructure tools (Trellis, Nginx, Ansible) and WordPress application-level utilities
- Enhanced migration documentation with comprehensive URL update methods for all migration scenarios

## [2.0.1] - 2025-12-31

### Added

- Comprehensive README files for all top-level technology directories:
  - **[trellis/README.md](trellis/README.md)** - Complete guide to Trellis-specific tools including backup operations, monitoring, provisioning workflows, and Trellis updater
  - **[nginx/README.md](nginx/README.md)** - Nginx configuration management covering browser caching, image optimization (WebP/AVIF), URL redirects, and Trellis deployment workflows
  - **[wp-cli/README.md](wp-cli/README.md)** - WordPress CLI operations guide including content creation, diagnostics, and migration tools
  - **[scripts/README.md](scripts/README.md)** - Automation scripts documentation for GitHub integration, theme management, monitoring, and backup automation

### Changed

- Enhanced [trellis/README.md](trellis/README.md) with expanded sections:
  - Added detailed backup/restore workflows with example commands
  - Enhanced monitoring section with traffic analysis and security scanning examples
  - Improved provisioning quick reference with common command patterns
  - Updated Trellis updater documentation with troubleshooting guidance
  - Better organization of tools by functional area

### Improved

- Consistent documentation structure across all top-level directories
- Better discoverability of tools and features through comprehensive READMEs
- Cross-references between related tools and workflows
- Unified quick-start sections for common operations
- Enhanced navigation with detailed tables of contents

## [2.0.0] - 2025-12-31

### Changed

**BREAKING: Repository Restructuring and Rename**

- **Renamed repository** from `trellis-tools` to `wp-ops` to better reflect broader WordPress operations scope
- **Reorganized directory structure** into technology-based categories:
  - `trellis/` - Trellis-specific tools (backup, monitoring, provision, updater)
  - `wp-cli/` - WordPress CLI operations (content-creation, diagnostics, migration)
  - `nginx/` - Web server configurations (browser-caching, image-optimization, redirects)
  - `scripts/` - General utilities (create-pr.sh, release-theme.sh, rsync-theme.sh, plus backup and monitoring scripts)
  - `troubleshooting/` - Server and WordPress troubleshooting guides (remains at root)

### Migration Guide for Existing Users

**If you've cloned this repository:**

1. Update your git remote URL:
   ```bash
   cd trellis-tools
   git remote set-url origin https://github.com/imagewize/wp-ops.git
   git pull
   ```

2. Update any references in your scripts or documentation:
   - Old: `backup/trellis/database-backup.yml` → New: `trellis/backup/database-backup.yml`
   - Old: `provision/README.md` → New: `trellis/provision/README.md`
   - Old: `content-creation/` → New: `wp-cli/content-creation/`
   - Old: `image-optimization/` → New: `nginx/image-optimization/`
   - Old: `create-pr.sh` → New: `scripts/create-pr.sh`

3. All documentation and internal links have been updated automatically

**Note:** GitHub automatically redirects the old repository name, so existing clones will continue to work, but updating the remote URL is recommended.

## [1.17.0] - 2025-12-31

### Added
- New `release-theme.sh` script for AI-powered WordPress theme releases with Claude CLI integration
- Automated version bumping across `style.css`, `readme.txt`, and `CHANGELOG.md`
- Claude AI-powered changelog generation in two formats: detailed Keep a Changelog format and concise WordPress.org format
- Support for both demo/ and site/ Bedrock installation structures
- Interactive confirmation prompts and change preview before committing
- Automatic git diff analysis between current branch and main
- Optional `--commit` flag for automatic git commits with standardized messages
- Semantic versioning validation (X.Y.Z format)
- Dual changelog format generation:
  - **CHANGELOG.md**: Detailed with sections (Changed, Added, Fixed, Technical) and sub-sections
  - **readme.txt**: Concise single-line entries with CHANGED/ADDED/FIXED/TECHNICAL prefixes

### Changed
- Updated main README.md to include Theme Release tool in tools table between PR Creation and Theme Sync

## [1.16.3] - 2025-12-31

### Changed
- Enhanced rsync-theme.sh to preserve theme-repository-only files during sync
- Added `create-pr.sh` to exclusion list to protect theme repo's PR automation script from deletion
- Added `.distignore` to exclusion list to preserve WordPress.org deployment configuration in theme repo
- Updated example paths from 'nynaeve' theme to 'elayne' theme for better documentation clarity

### Fixed
- Theme sync now preserves files that exist only in standalone theme repository (not in Trellis project)

## [1.16.2] - 2025-12-31

### Added
- Critical URL sanitization section in PAGE-CREATION.md explaining hardcoded pattern URLs issue
- Pre-deployment URL audit commands for detecting local development URLs in production
- Step-by-step URL search-replace workflow with database backup procedures
- Browser verification steps for mixed content warnings
- CLAUDE.md section explaining how WordPress pattern URLs get hardcoded in database
- Search-replace examples for both single-site and multisite WordPress installations

### Changed
- Enhanced PAGE-CREATION.md with "CRITICAL: URL Sanitization Before Production" section
- Updated CLAUDE.md "URL Management in Database Operations" with pattern URL hardcoding warning
- Added cross-reference between CLAUDE.md and PAGE-CREATION.md for URL sanitization workflows

## [1.16.1] - 2025-12-30

### Changed
- Updated PROJECT-SETUP.md to use HTTP by default for local development instead of HTTPS
- Changed `WP_HOME` example from `https://yourproject.test` to `http://yourproject.test` for simpler local setup
- Updated all URL examples throughout the guide to use HTTP (with notes on HTTPS if SSL is enabled)
- Enhanced database pull section with URL search-replace guidance based on local SSL configuration
- Added dedicated multisite URL update section with WP-CLI `--network` flag examples
- Expanded troubleshooting section with new entries for 500 errors, WP-CLI autoloader issues, and SSH host key verification
- Added critical theme setup instructions after database pull (Composer/NPM install and build steps)
- Enhanced verification checklist to include theme dependency and asset build verification
- Added method 2 for direct rsync file sync when Ansible playbooks fail
- Updated quick reference commands to include theme setup workflow

### Added
- Multisite network URL update documentation with WP-CLI network commands
- Theme setup section explaining why Composer/NPM builds are required after database pulls
- Alternative MySQL-only commands for multisite URL updates (with warnings about limitations)
- SSH known_hosts configuration examples for production server access
- Theme asset build verification steps in checklist
- Explanation of Lima VM bidirectional file sync behavior

## [1.16.0] - 2025-12-30

### Added
- New project setup guide (provision/PROJECT-SETUP.md) for cloning and configuring existing Trellis/Bedrock projects
- Comprehensive project-specific documentation covering repository cloning, dependency installation, and VM provisioning
- Database and files setup options with Ansible playbook and direct VM command methods
- Theme development workflow with Vite dev server and HMR setup
- Production access configuration and deployment instructions
- Common project workflows including daily development, VM management, and WP-CLI operations
- Project-specific troubleshooting section with file sync, port conflicts, and SSL certificate issues
- Verification checklist for confirming successful project setup
- Quick reference commands for project management

### Changed
- **Breaking:** Refactored NEW-MACHINE.md to focus exclusively on macOS setup for Trellis development (machine setup only)
- Removed project-specific content from NEW-MACHINE.md (imagewize.com examples, ACF Pro setup, repository cloning)
- Generalized NEW-MACHINE.md with placeholder names (your-project, your-theme) for universal applicability
- Updated NEW-MACHINE.md to reference PROJECT-SETUP.md for next steps after machine configuration
- Updated main README.md to include both "New Machine Setup" and "Project Setup" guides with clear descriptions
- Reduced NEW-MACHINE.md from 804 lines to 318 lines for improved clarity and focus
- NEW-MACHINE.md now serves as a universal reference for any Trellis project

### Improved
- Clear separation of concerns between machine setup and project setup documentation
- Better navigation with cross-references between NEW-MACHINE.md and PROJECT-SETUP.md
- Enhanced reusability - PROJECT-SETUP.md serves as a template for any Trellis project
- Reduced confusion by eliminating the dual-purpose nature of the original NEW-MACHINE.md

## [1.15.0] - 2025-12-30

### Added
- Comprehensive new machine setup guide (provision/NEW-MACHINE.md) for setting up Trellis development environment
- Step-by-step instructions for installing required tools (Trellis CLI, Composer, PHP, Node.js, pnpm)
- Detailed explanation of host machine vs Trellis VM architecture and tool separation
- Complete workflow for cloning repository, installing dependencies, and configuring Trellis VM
- ACF Pro authentication setup instructions for Composer installation
- Database and files setup options (fresh installation vs production pull)
- Theme development workflow documentation with Vite dev server and HMR
- Production SSH access setup and deployment instructions
- Common development workflows (daily development, creating blocks, VM management)
- Troubleshooting section covering port conflicts, file sync, SSL certificates, and VM issues
- Verification checklist and quick reference commands
- Architecture diagrams explaining host/VM separation and development workflow
- Documentation on Lima VM vs Vagrant differences and file sync behavior

### Changed
- Updated main README.md to include "New Machine Setup" in tools table

## [1.14.0] - 2025-12-26

### Added
- New diagnostics directory with WordPress diagnostic tools for troubleshooting
- CLI transient diagnostic script (`diagnostic-transients.php`) for WP-CLI-based transient testing
- Browser-based transient debugger (`transient-debug-browser.php`) for web-accessible diagnostics
- Comprehensive diagnostic documentation covering transient storage, caching, and performance issues
- Security-conscious diagnostic tools with access controls and secret token protection
- Support for diagnosing external object cache conflicts (Redis, Memcached, LiteSpeed)
- Database performance metrics and wp_options table analysis
- Business hours logic testing for time-based cache lifetimes

### Changed
- Updated main README.md to include Diagnostics tool in tools table

## [1.13.1] - 2025-12-15

### Changed
- Updated `content-creation/PATTERN-REQUIREMENTS.md` to clarify metadata is recommended (not required), add guidance on block comment vs rendered HTML validation, extend checklist, and bump document version to 1.2

## [1.13.0] - 2025-12-15

### Added
- New `PATTERN-REQUIREMENTS.md` with comprehensive WordPress block pattern standards and validation checklist
- `AGENTS.md` contributor guide summarizing project structure, commands, coding conventions, and PR expectations

### Changed
- Reworked `content-creation/README.md` into a concise landing page with clear navigation to page creation workflows, pattern requirements, and automation scripts
- Moved the sample Gutenberg content file to `content-creation/examples/example-page-content.html` and updated references in `PAGE-CREATION.md`

## [1.12.2] - 2025-12-14

### Added
- New section "Adding Patterns to Existing Pages" to PAGE-CREATION.md with comprehensive examples
- Method 1: Update page via Trellis VM with heredoc pattern insertion
- Method 2: Batch add patterns by category for showcase pages
- Method 3: Finding pattern slugs from theme files
- Real-world Elayne theme pattern showcase examples (Heroes page and Patterns page)
- Tips for creating pattern showcase pages with consistent spacing and formatting
- Troubleshooting section for pattern rendering and content update issues
- VM-based content file creation examples using `/tmp` directory
- Multi-AI support in create-pr.sh with `--ai=claude|codex` option for flexible AI backend selection
- Interactive AI tool selection when both Claude and Codex CLIs are available
- Environment variable support for custom CLI command names (`CLAUDE_COMMAND`, `CODEX_COMMAND`)
- Support for custom AI CLI arguments via `CLAUDE_CLI_ARGS` and `CODEX_CLI_ARGS` environment variables

### Changed
- Updated PAGE-CREATION.md Table of Contents to include section 9
- Enhanced PAGE-CREATION.md with VM heredoc examples for multisite pattern updates
- Improved document version to 1.1 with updated timestamp (December 14, 2025)
- Refactored create-pr.sh option parsing to use `case` statement for better maintainability
- Enhanced AI CLI detection to check for both Claude and Codex availability
- Improved error handling in AI description generation with detailed error messages
- Updated CREATE-PR.md with multi-AI backend documentation and usage examples

## [1.12.1] - 2025-12-01

### Fixed
- **Critical:** Fixed timestamp filtering in monitoring scripts that prevented log analysis
- Fixed broken AWK timestamp parsing in `filter_recent_logs()` function (traffic-monitor.sh and security-monitor.sh)
- Fixed invalid octal number error when displaying hours 08 and 09 in traffic reports
- Replaced complex AWK-based timestamp filtering with simple tail-based line estimation (HOURS × 1000 requests)

### Changed
- Simplified log filtering approach using `tail -n` with estimated line count for better performance
- Updated monitoring scripts to process up to 50,000 most recent log lines (configurable based on time period)
- Improved monitoring script execution speed by eliminating per-line date command spawning

## [1.12.0] - 2025-12-01

### Added
- Comprehensive Nginx redirect configuration documentation and examples (redirects/)
- SEO redirect examples for fixing 404 errors and URL structure changes
- Generic redirect templates for common WordPress permalink migrations
- SSL/HTTPS redirect patterns for secure page enforcement
- Site-specific redirect example (imagewize.com/seo-redirects.conf.j2)
- Documentation covering Trellis nginx-includes deployment workflow
- Redirect best practices including exact path matching, regex patterns, and query string preservation
- Testing strategies for manual and automated redirect verification
- Performance considerations and optimization tips for large redirect sets
- Troubleshooting guide for common redirect issues (404s, loops, deployment problems)
- Methods for finding URLs to redirect using Google Search Console, server logs, and SEO tools

### Changed
- Updated main README.md to include Redirects tool in tools table

## [1.11.2] - 2025-11-29

### Fixed
- **Critical:** Fixed monitoring playbooks to use per-site log paths instead of global Nginx logs
- Updated all Ansible playbooks to default to `/srv/www/{{ site }}/logs/access.log` (Trellis standard)
- Updated traffic-report.yml, security-scan.yml, quick-status.yml to use `{{ project_root }}/logs/access.log`
- Updated setup-monitoring.yml wrapper scripts to use per-site logs in cron jobs
- Updated updown-webhook-handler.sh to default to per-site logs with environment variable override
- Updated shell scripts (traffic-monitor.sh, security-monitor.sh) to default to imagewize.com per-site logs

### Changed
- Added log path configuration documentation explaining per-site vs global logs
- Updated README.md with "Log File Locations" section and configuration override examples
- Updated QUICK-REFERENCE.md to show proper log path usage with `$LOG` variable
- All playbooks now support `-e log_file=/path/to/log` override for flexibility
- Modified all one-liner command examples to use configurable `$LOG` variable
- Shell scripts now default to `/srv/www/imagewize.com/logs/access.log` with examples for demo.imagewize.com and global logs

### Added
- Documentation explaining when to use per-site logs (default) vs global logs
- Examples showing how to override default log paths in Ansible playbooks
- Clear prerequisites about Trellis log configuration in both README and QUICK-REFERENCE
- Inline comments in shell scripts showing all available log path options

## [1.11.1] - 2025-11-29

### Changed
- Updated monitoring documentation to recommend root SSH access with key-based authentication
- Changed all monitoring examples from `web@example.com` to `root@example.com`
- Added "Alternative Access Methods" section with three options: sudo, adm group, and passwordless sudo
- Added security considerations emphasizing root password authentication must be disabled
- Updated QUICK-REFERENCE.md with root user examples and prerequisites note
- Clarified that root SSH access with keys is secure and practical for system administration tasks

## [1.11.0] - 2025-11-29

### Added
- Comprehensive monitoring tools for Nginx log analysis (monitoring/)
- Traffic analysis script (traffic-monitor.sh) with bot filtering, page views, unique visitors, and bandwidth tracking
- Security monitoring script (security-monitor.sh) for detecting bad actors, brute force attempts, SQL injection, and scanners
- Ansible playbooks for automated monitoring: quick-status.yml, traffic-report.yml, security-scan.yml, setup-monitoring.yml
- Automated monitoring setup with cron jobs for daily traffic reports and security scans
- updown.io webhook integration (updown-webhook-handler.sh and updown-webhook-receiver.php) for automatic log analysis on downtime
- Quick reference guide (QUICK-REFERENCE.md) with common monitoring commands and one-liners
- Comprehensive monitoring documentation covering traffic analysis, security monitoring, and updown.io integration
- IP blocking recommendations and fail2ban integration guidance
- GoAccess and AWStats tool integration examples
- Real-time monitoring commands and performance tracking

### Changed
- Updated main README.md to include Monitoring tools section

## [1.10.0] - 2025-11-28

### Added
- Comprehensive WordPress cron documentation (provision/CRON.md) covering system cron vs WP-Cron
- WordPress Cron section in migration guide explaining the transition from WP-Cron to system cron
- Multisite cron configuration documentation with real examples
- Cron verification commands and log examples from production systems
- Log filtering commands for monitoring specific sites on multi-site servers
- WordPress Cron section in provision/README.md with reference to detailed guide

### Changed
- Updated migration guide Table of Contents to include WordPress Cron section
- Enhanced provision documentation with cron reference and link to CRON.md

## [1.9.1] - 2025-11-27

### Added
- Theme screenshot example demonstrating proper screenshot formatting and dimensions

## [1.9.0] - 2025-11-26

- This update adds a new ImageMagick command to the RESIZE-AND-CONVERSION.md documentation, specifically for resizing screenshots to fit theme requirements (1200x900 pixels). The command ensures the screenshot is centered and cropped to the exact dimensions, which is useful for maintaining consistency in theme-related visuals.


### Added
- Automated page creation script (page-creation.sh) for deploying WordPress pages to production
- Example WordPress page content file (example-page-content.html) with Gutenberg block markup
- Script features: automated SCP file transfer, conflict detection/resolution, interactive prompts, verification, and cleanup
- Comprehensive automated script documentation section in PAGE-CREATION.md
- Quick Start section in content-creation README with script usage examples
- Files in This Directory section in content-creation README

### Changed
- Updated PAGE-CREATION.md to feature automated script as recommended Option 1 for production deployment
- Enhanced PAGE-CREATION.md with detailed script workflow, customization, security considerations, and requirements
- Reorganized PAGE-CREATION.md Table of Contents to include Automated Script Details and Examples sections
- Removed all references to external `seo-strategy` directory for self-contained documentation
- Updated all code examples to use generic paths and the included example-page-content.html file
- Enhanced content-creation README with script and example file references

## [1.8.0] - 2025-11-25

### Added
- Comprehensive WordPress page creation guide (PAGE-CREATION.md) with step-by-step instructions for Trellis/Bedrock
- Local development workflow using Trellis VM and WP-CLI for page creation
- Production deployment strategies (recreate, export/import, WXR)
- Content preparation guidelines for Gutenberg blocks and patterns
- Common issues and solutions for page creation workflows
- Best practices for development, security, performance, and SEO optimization
- Complete example workflows with full command sequences
- Quick reference guide with essential paths and commands

### Changed
- Enhanced content-creation README with Page Creation Guide reference
- Updated Related Guides section in content-creation README
- Added troubleshooting and additional resources sections to content-creation README

## [1.7.0] - 2025-11-25

### Added
- Out of Memory (OOM) troubleshooting guide with comprehensive WP-Cron memory leak diagnosis
- Mail configuration troubleshooting guide for SMTP issues after Trellis upgrades
- OOM guide includes PHP CLI memory limit analysis, WP-Cron investigation, and Action Scheduler debugging
- Mail guide includes symptoms, diagnosis steps, and prevention best practices
- Mail configuration verification step in trellis-updater.sh that checks for SMTP settings (Brevo/Sendgrid) after update
- `mail.yml` to rsync exclusion list in both trellis-updater.sh and manual-update.md
- Detailed mail.yml restoration instructions in updater script warnings

### Changed
- Updated troubleshooting README to include OOM and MAIL guides in guides table
- Enhanced trellis-updater.sh with mail.yml preservation and verification
- Enhanced manual-update.md with mail.yml exclusion and preservation notes
- Updated updater rsync comments to include SMTP settings preservation category
- Improved file verification warnings with specific restoration commands for mail.yml

## [1.6.0] - 2025-11-23

### Added
- New troubleshooting section with comprehensive server diagnostics guides
- PHP-FPM troubleshooting guide covering pool exhaustion, memory management, worker configuration, and the low-traffic recycling problem
- MariaDB troubleshooting guide covering startup failures, compression plugin issues, and connection problems
- Quick diagnostic commands reference for system health checks

## [1.5.3] - 2025-11-22

### Added
- Critical file verification step in trellis-updater.sh that checks for `.vault_pass`, `ansible.cfg`, and vault.yml files after update
- Vault password troubleshooting section in updater README with step-by-step recovery instructions
- `ansible.cfg` to rsync exclusion list to preserve vault_password_file setting

### Changed
- Updated preservation list in README to note `ansible.cfg` as CRITICAL for vault operations

## [1.5.2] - 2025-11-22

### Added
- Post-upgrade manual review section in updater README with guidance for role templates, new variables, and Galaxy roles
- Organized preservation list by category (Secrets, Git/CI, Site Config, PHP/Server Settings, Deploy Hooks)

### Changed
- Updated trellis-updater.sh to exclude custom PHP/server settings (`main.yml` files) and deploy hooks
- Updated manual-update.md rsync command with additional exclusions for `main.yml` files and `deploy-hooks/`
- Added explanatory comments in updater script for rsync exclude categories

## [1.5.1] - 2025-11-15

### Added
- CLAUDE.md file with comprehensive guidance for Claude Code AI assistant
- Architecture documentation for Ansible playbook structure and patterns
- File naming conventions and compression strategies documentation
- URL management patterns for database operations
- Development workflow guidance for PR creation and backup testing

### Changed
- Updated README with Content Creation Tools section (tool #6)
- Updated README with GitHub PR Creation Script section (tool #7)
- Renumbered Theme Sync Script to #8 and Provisioning Documentation to #9
- Enhanced Requirements section with tool-specific dependencies
- Improved documentation organization and cross-references

## [1.5.0] - 2025-11-15

### Added
- Content creation guide with WordPress block patterns and WP-CLI commands
- Image resizing and conversion guide (RESIZE-AND-CONVERSION.md) with comprehensive ImageMagick examples
- Detailed workflows for creating optimized avatars and thumbnails
- Batch processing examples for image conversion
- Quality settings recommendations for JPEG, WebP, and AVIF formats
- Responsive image workflow examples
- File size comparison data for different image formats

### Changed
- Enhanced image optimization documentation with better structure and cross-references
- Updated README to reference new image resizing guide
- Improved quality settings guidance across all image formats
- Added ImageMagick installation instructions to main image optimization README

## [1.4.0] - 2025-10-23

### Added
- Theme Rsync script for syncing theme files from Trellis to standalone theme repository
- Multi-site migration guide with strategies for migrating multiple WordPress sites to a single Trellis server
- Complete single-site migration guide: Regular WordPress to Trellis/Bedrock
- PR creation shell script for automated pull request workflows
- PHP upgrade additions to provisioning documentation

### Changed
- Updated migration documentation with comprehensive guides and best practices
- Enhanced main README with theme sync and migration guide references

## [1.3.0] - 2025-10-02

### Added
- Provisioning documentation with common Trellis commands and workflows
- Files backup, pull, and push playbooks for managing uploads
- Comprehensive backup documentation with Ansible playbooks and shell scripts
- Backup retention and compression strategies using tar.gz and sql.gz formats

### Changed
- Updated backup playbooks to follow Trellis conventions
- Enhanced database backup script with better export messages
- Improved backup clarification and organization
- Extended browser caching expiry dates for better performance
- Cleaned up assets configuration

### Fixed
- Database export message formatting
- Backup playbooks compatibility issues

### Removed
- Map directive from Nginx configuration

## [1.2.0] - 2025-05-27

### Added
- Site-wide browser caching configuration for static assets
- Assets expiry configuration for images, CSS, JavaScript, and fonts
- Cache headers for optimal performance

### Changed
- Refactored browser caching implementation for better coverage

### Removed
- Deprecated caching directory structure
- Acorn-specific caching references

## [1.1.0] - 2025-04-27

### Added
- WordPress migration tools and commands documentation
- Migration commands for domain changes, multisite handling, and Bedrock path conversions

## [1.0.0] - 2025-04-26

### Added
- Manual Trellis update documentation with step-by-step instructions
- Alternative to automated updater script

### Changed
- Renamed 'updates' directory to 'updater' for clarity

### Fixed
- Nginx configuration typo

## [1.0.0-beta.4] - 2025-04-26

### Added
- Image optimization configuration supporting WebP and AVIF formats
- Nginx configuration for automatic modern image format serving
- Image optimization documentation

### Changed
- Major restructuring of directory organization
- Updated documentation structure for better clarity
- New directory structure for better tool organization

## [1.0.0-beta.3] - 2025-04-24

### Removed
- Deleted files and directories cleanup

## [1.0.0-beta.2] - 2025-04-24

### Changed
- Updated README exclusion list for updater script

## [1.0.0-beta.1] - 2025-04-24

### Added
- Staging vault exclusion in updater script
- .github directory exclusion from updates

### Changed
- Modified copy command to use standard cp without -a flag

## [1.0.0-alpha.2] - 2025-04-24

### Added
- Script limitations documentation
- Note on commit deactivation option

## [1.0.0-alpha.1] - 2025-04-24

### Added
- Initial project setup
- README documentation
- MIT License
- Trellis updater script for safe Trellis updates
- Automated backup and update workflow
- Git integration for tracking changes
