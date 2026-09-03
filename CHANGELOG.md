# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.17.0] - 2026-09-03

### Changed

- **`publish-post --update` now rewrites `post_title` and `post_excerpt`** from the
  draft header, instead of writing only `post_content`. The SEO meta title and
  description were already rewritten from that same header on every run, so a title
  fixed in the draft stayed stale on the post while the SEO title it is supposed to
  match was updated — on one post a "WooComerce" typo survived an update that changed
  everything else. If you relied on the post title being preserved across an update,
  it no longer is; the draft header is now authoritative for both fields.
- `post_name` and `post_status` are still deliberately left alone on update: rewriting
  a slug would silently break the live URL, and an update must not flip a draft live.
  When the draft's slug differs from the stored one, `publish-post` now warns and
  leaves it untouched rather than changing it.

## [5.16.1] - 2026-09-03

### Fixed

- **`publish-post` / `publish_post` no longer strip backslashes from post content.**
  The body was passed to `wp_update_post()` / `wp_insert_post()` unslashed, but both
  call `wp_unslash()` internally and expect slashed input, so every literal backslash
  was eaten on the way into the database. Prose was unaffected; posts containing code
  were silently corrupted — `\"`, `\'`, `\\`, `\n`, `\b` and backreferences like `\2`
  are load-bearing in regexes and `printf`/`sprintf` calls, and vanished. Fixed by
  applying `wp_slash()` to the body immediately before the write, on both the update
  and the create path, in the MCP tool and the CLI script. The slash is applied after
  the transit-length guard so that guard still measures the real payload.
  `post_title` and `post_excerpt` are slashed on the create path for the same reason.
  ([#210](https://github.com/imagewize/wp-ops/issues/210))

## [5.16.0] - 2026-09-01

### Added

- **`publish-post` — create or update a WordPress post from an HTML draft, and
  verify the write actually survived.** `import-page-draft` only updates an
  existing *page* by ID and touches no metadata, so publishing a blog post meant
  a long manual sequence: strip the `<!-- SUGGESTED ... -->` header, scp the
  body, `wp eval` an insert, set `_thumbnail_id`, set `_genesis_title` /
  `_genesis_description`, assign terms, flush cache, then hand-check that
  nothing was silently dropped. This does all of it, and refuses to proceed on a
  duplicate slug, a body under 500 bytes, or a JSON-LD block count that changed
  in transit.

  The post-write verification is the reason the command exists. Every way
  content silently disappears on this stack is invisible to a `post_content`
  diff — kses stripping `<script type="application/ld+json">`, a self-closing
  custom block one-liner saving as a genuinely empty block, a stale render off
  cache. None of them raise an error. `publish-post` re-reads the saved post and
  compares stored bytes and `<script>`/JSON-LD counts against the source, so a
  loss is reported at write time rather than discovered later in a search
  result.

  It also declines to invent taxonomy: a tag or category that does not already
  exist is reported as a warning and skipped, never created.

- **`verify-post` — check a published post's stored content against what
  actually renders.** Split out as its own command so it can run against any
  post, not just one this toolkit wrote. Reports stored bytes, JSON-LD and
  `<script>` counts, self-closing custom blocks, SEO meta length, and featured
  image; then fetches the live URL and confirms the schema still renders, every
  internal link resolves, and no CTA wrapper rendered empty.

- **MCP tools `publish_post` and `verify_post`,** implemented against
  `runWpCliRaw` rather than shelling out to the scripts, so both work across an
  SSH host, a local path and a Trellis VM through the same site/env resolution
  as every other tool. `publish_post` ships the body as base64 inside `wp eval`
  instead of scp'ing it, which keeps one code path across all three transports.
  It requires `confirm: true` for a real write, and `dryRun: true` preflights a
  draft (header parsing, block and length checks) without confirmation.

### Changed

- **`publish-post` and `publish_post` now behave identically.** They were split
  on two points: the shell script uploaded an image file while the MCP tool only
  accepted an already-uploaded attachment ID, and the shell script demanded
  `TRELLIS_DIR`/`SITE_DIR` for a local run while the MCP tool resolved the VM
  from the registry. Both now take an image *file*, upload it, set alt text, and
  write the resulting verified URL into the Article JSON-LD `image` field;
  `publish-post` auto-detects `TRELLIS_DIR` (with the same confirm prompt as
  `scripts/backup/db-pull.sh`) and defaults `SITE_DIR` to the Bedrock checkout
  beside it.

  The two Article-schema injections are separate implementations — python3 in
  the script, TypeScript in the MCP tool — so both parse the block as real JSON
  rather than patching it textually, and their output is verified byte-identical
  on the same input. The MCP tool ships the image as base64 through `wp eval`
  for the same reason it ships the post body that way: one code path across SSH,
  a local path and a Trellis VM. Confirmed lossless by SHA-256 round-trip
  against a live upload.

  Because the attachment URL differs per environment, the post body is now built
  per target rather than once and shared — the byte counts the verification
  compares against are taken after injection.

### Fixed

- **`publish-post` now actually performs the Article JSON-LD image rewrite its
  header documented.** The behaviour was described in the command's comment
  block but never implemented.

### Notes

- Both new commands deliberately **omit `--user`** when invoking WP-CLI, and say
  so in their headers. WP-CLI tears down kses filters at `init` priority 11 only
  when `--user` is absent; passing it for any account lacking `unfiltered_html`
  re-adds the filters and strips JSON-LD from the post. This is the opposite of
  the intuitive reading, which is why it is commented at both call sites.

## [5.15.1] - 2026-08-30

### Fixed

- **The database playbooks now run their development-side steps where the
  development database actually lives.** `database-pull.yml`,
  `database-push.yml` and `database-backup.yml` ran `wp db export` /
  `wp db import` / `wp search-replace` on the host against `local_path`, which
  only works when WordPress and MariaDB are reachable from the host. With a
  trellis-cli VM development site (`trellis vm start`, Lima) both live inside
  the VM, so the host's `wp` read the site's `.env` credentials, aimed them at
  whatever MySQL the host happens to run, and failed with `Access denied for
  user '<site>'@'localhost'` — while the *export* steps failed silently, since
  `wp db export - | gzip > file` returns gzip's exit status, leaving a
  ~170-byte husk where the pre-import backup of the development database should
  have been. The playbooks now detect a VM development site from
  `<trellis>/.trellis/lima/inventory` and run each development-side command
  through `trellis vm shell --workdir /srv/www/<site>/current -- bash -c
  '<command>'`. The VM mounts `local_path` at that same path, so dumps and
  backups stay in the shared directory and the paths around the commands are
  relative to it, identical on both sides. Host-local development is unchanged.
  `-e dev_target=host|vm` overrides the detection; a VM site with no trellis-cli
  on `PATH` aborts in `pre_tasks` with an explanation instead of at the first
  command. `database-backup.yml -e env=development` additionally needs an
  Ansible-reachable development host, which a stock `hosts/development`
  inventory does not describe for a trellis-cli VM — `trellis/backup/README.md`
  records that limitation.
- **The pull/push URL search-replace rewrote a hostname to itself.**
  `database-pull.yml` took `url_from`, and `database-push.yml` took `url_to`,
  from `wordpress_sites[site]` — but both plays load
  `group_vars/development/wordpress_sites.yml` through `vars_files`, which
  outranks the remote environment's `group_vars` for the whole play. Both ends
  therefore resolved to the *development* hostname, and the search-replace
  became `example.test` → `example.test`: a no-op that still reports `changed`,
  leaving every production URL in the freshly pulled development database (1527
  posts on the run that caught it) and every `.test` URL in production on a
  push. Each end is now read from its own environment's file by name.
- **`ansible_date_time` replaced with `ansible_facts.date_time`** in the
  database, files-backup and monitoring playbooks. ansible-core deprecates the
  injected top-level fact variables — `INJECT_FACTS_AS_VARS` defaults to `True`
  today but the injection is removed in 2.24, and the deprecation warning fired
  on every run of these playbooks in the meantime.

## [5.15.0] - 2026-08-30

### Changed

- **Superseded asset-cache extractions are now pruned after an upgrade.** A
  binary installed via Homebrew extracts its embedded scripts to a
  version-stamped cache directory (`~/Library/Caches/wp-ops/assets-<version>`)
  on first run, and nothing ever removed the previous one — a machine that had
  been upgrading since the Go CLI shipped had 29 of them, back to 3.23.2.
  Extracting a new version now sweeps the parent afterwards, keeping the
  current extraction, the two most recent superseded ones, and anything less
  than 24 hours old; leftover `.extract-*` temp directories from a run killed
  mid-extraction are swept on the same age rule. The keep-recent and age rules
  are what make this safe against an older binary that is still running: a
  long database or files pull keeps reading its own scripts for as long as it
  lasts. The sweep runs only when an extraction actually happened, so a run
  that finds its version already extracted does no directory scanning at all.

## [5.14.1] - 2026-08-30

### Fixed

- **Local `wp` tasks in the database playbooks ran from the wrong directory,
  breaking `database-pull`, `database-push`, and a development
  `database-backup`.** Every local task `chdir`'d into
  `{{ project_local_path }}/web/wp` but referenced its files relative to
  `{{ project_local_path }}` — the directory one level up, where the
  `database_backup/` folder is created and where the dump is fetched to. So
  `database-pull` aborted at "Export development database before importing
  dump (backup)" with `database_backup/<site>_development_<stamp>.sql.gz: No
  such file or directory`, and would have failed again on the import
  (`gzip: <site>_db_dump.sql.gz: No such file or directory`) had it got that
  far; `database-push` failed the same way copying its dump up. Every local
  path is now built from a new `local_site_dir` — the site's `local_path`
  resolved against the playbook directory — so no local file reference depends
  on a task's working directory or on where `ansible-playbook` was invoked
  from, and the local `wp` calls pass `--path=web/wp` so WordPress is still
  found under Bedrock's layout.

## [5.14.0] - 2026-08-29

### Added

- **`traffic-monitor.sh` excludes known non-visitor IPs from analysis.** Our
  own dev/testing traffic through a ProtonVPN (ID) exit-node range
  (`146.70.14.0/24`) was being counted as real user traffic throughout the
  report — totals, top pages, top IPs, SEO breakdowns — inflating
  human-traffic numbers by up to ~8% in some weekly windows. The new
  `EXCLUDE_IP_PATTERN` is applied once against the time-filtered log before
  any section runs, so every downstream count is already clean.

## [5.13.0] - 2026-08-29

### Added

- **`gh-traffic.sh --summary`** shows only the cross-repo rollup table added
  in 5.12.0 and skips per-repo detail entirely — for scanning traffic across
  many repos without the daily-breakdown noise. Works with any number of
  repos, including one. If `--referrers` came along (directly or via
  `--all`), it's dropped rather than fetched: the summary has no column for
  it, and `--summary` means per-repo detail — where referrers would
  otherwise show — isn't printed at all. Passing `--referrers` with no
  views or clones section active errors out instead, since the summary
  would then have nothing to put in it.

## [5.12.0] - 2026-08-29

### Added

- **`gh-traffic.sh` prints a cross-repo summary table when more than one
  `owner/repo` is given.** Each repo's detail already rendered as a tidy
  table on its own, but a multi-repo `--all` run stacked up to 18 of them
  (views, clones, referrers × N repos) with nothing tying them together, so
  comparing repos meant scrolling through a wall of text. The new summary
  is one row per repo — 14-day views/clones totals and uniques, from the
  same API fields the per-repo `Total`/`Unique (14d)` rows already used —
  sorted by unique views descending (unique clones, if only `--clones` was
  requested). It's skipped for a single repo, where it would just repeat
  the detail table, and for a referrers-only run, which has no numeric
  column to sort by. Each repo's traffic is now fetched once and reused for
  both the summary and the detail section, rather than hitting the API
  twice.

### Changed

- **`gh-traffic.sh` table output now draws real borders** (`+---+---+`)
  instead of `column -t`'s whitespace-aligned columns, with numbers and the
  `-` placeholder right-aligned against left-aligned text. Rendered with a
  small `awk` routine rather than `column`, which is no longer a
  dependency of the script.

## [5.11.5] - 2026-08-29

### Fixed

- **Ansible playbook reports (`quick-status`, `security-scan`,
  `traffic-report`) printed as one unreadable escaped blob.** Ansible's
  default JSON callback format escapes every embedded newline in a `debug`
  `msg` as literal `\n` text and quotes every string, so a multi-line
  report reads as a wall of backslash-n's and quote marks regardless of
  whether the underlying script emits ANSI colors — a problem `quick-status`
  had independently of the escape-sequence noise fixed in 5.11.3/5.11.4,
  since it never calls a colored script.

  `RunPlaybook` now sets `ANSIBLE_CALLBACK_RESULT_FORMAT=yaml` on the
  `ansible-playbook` subprocess (unless the caller already set it), so
  Ansible renders multi-line strings with a YAML block-literal scalar —
  real line breaks, no escaping or quoting — instead of JSON. General fix
  at the process level rather than another per-playbook patch. Confirmed
  against `imagewize.com` production for all three commands.

## [5.11.4] - 2026-08-29

### Fixed

- **5.11.3 did not actually fix the `security-scan` escape-sequence noise.**
  That release changed the "Display security report" task's `debug` msg
  from `security_report.stdout_lines` to `security_report.stdout` on the
  theory that Ansible's default callback only JSON-encodes list results.
  Verified against the installed ansible-core (2.21.2) that this is wrong:
  the callback always runs a debug `msg` through its result-format
  serializer, string or list alike, and control bytes get mangled either
  way — the JSON format escapes the ESC byte to literal `\u001b` text,
  and the YAML format silently drops it from the block-literal style it
  uses for multi-line strings. No Ansible result format carries a raw
  ANSI byte through this path intact.

  Fixed at the source instead: `security-monitor.sh` and `traffic-monitor.sh`
  (used by `traffic-report`, which has the same `debug: msg: stdout_lines`
  setup) now skip emitting color codes when their stdout isn't a tty (the
  case whenever Ansible's `shell` module captures it), the same pattern
  `grep`/`ls --color=auto` use. Interactive runs (ssh'ing in and running a
  script directly) keep their colors; Ansible-captured reports are now
  clean, readable text with no escape-code noise. Confirmed against
  `imagewize.com` production for both commands. The other monitoring
  scripts with the same unconditional color codes (`404-checker.sh`,
  `ai-bot-monitor.sh`, `error-monitor.sh`, `monitor.sh`, `server-monitor.sh`,
  `ttfb-test.sh`) aren't invoked from any playbook, so they're unaffected.

## [5.11.3] - 2026-08-29

### Fixed

- **`security-scan`'s report showed literal `\u001b[...]` escape sequences
  instead of colored output.** The "Display security report" task passed
  `security_report.stdout_lines` (a list) to `debug`'s `msg`, which makes
  Ansible's default callback serialize the result with `json.dumps` before
  printing it. JSON escapes the ESC control byte in `security-monitor.sh`'s
  ANSI color codes as the literal text `\u001b`, so terminals printed that
  text instead of rendering color. Changed `msg` to `security_report.stdout`
  (a plain string), which the callback prints directly and preserves the
  raw escape bytes.

## [5.11.2] - 2026-08-29

### Fixed

- **`quick-status`'s "Get PHP-FPM status" task silently returned nothing.**
  `systemctl status php*-fpm` matched no unit — systemd unit-name globbing
  requires the full suffix, so `php*-fpm` never matches `php8.4-fpm.service`
  even though the unit is loaded and running — and the task exited `rc=0`
  with empty output instead of erroring, so it went unnoticed by the
  `become` fix in 5.11.1. Changed the glob to `'php*-fpm.service'`,
  confirmed against `imagewize.com` production, and quoted it so the
  remote shell can't expand it against files in the deploy user's home
  directory before systemctl sees it.

## [5.11.1] - 2026-08-29

### Fixed

- **`quick-status` failed with `Missing sudo password` instead of reporting
  status.** The "Get Nginx status" and "Get PHP-FPM status" tasks in
  `trellis/monitoring/quick-status.yml` carried `become: yes`, but
  `systemctl status` is a read-only query that doesn't need root, and the
  command has no sudo password source when run non-interactively. Dropped
  `become` from both tasks, matching the `become: no` already used by the
  other read-only monitoring playbooks (`traffic-report.yml`,
  `security-scan.yml`).

- **The `5.11.0` release never reached Homebrew.** It was tagged `5.11.0`
  instead of `v5.11.0`, and the release workflow only builds on a `v*` tag
  push, so GoReleaser never ran and the tap was never updated. This release
  is tagged correctly to get both it and the fix above out.

## [5.11.0] - 2026-08-29

### Added

- **`wp-ops sync-extracted` — the two extracted repos are now checked against
  their wp-ops sources instead of hoped about.** `imagewize.trellis_wp_monitoring`
  on Ansible Galaxy and `imagewize/wp-cli-pattern-validate` on Packagist were
  both populated by hand, and nothing has propagated an edit or verified one
  since. `5569454` added `@mutates false` to `scripts/monitoring/security-monitor.sh`
  and `scripts/monitoring/traffic-monitor.sh` two days ago; the published role
  never saw it. That particular difference is correct — a wp-ops manifest
  directive has no business in a Galaxy role — but nothing distinguished it
  from a dropped bug fix, which is the actual hazard
  [trellis-extensions-evaluation.md](docs/trellis-extensions-evaluation.md)
  warned about when it chose a one-way export over moving the files out.

  The split the command enforces is the one already true of all three published
  files, verified before it was encoded: the leading comment block differs on
  purpose (wp-ops carries `@desc`/`@category`/`@flag`, the downstreams carry
  their own install instructions), and every line after it is byte-identical.
  So `--write` rebuilds each downstream file as its own header plus this repo's
  body, preserving the target's file mode; the default reports drift with a
  diff and exits non-zero, which makes it usable as a pre-release check. It
  stages files in the downstream working trees and stops there — a Galaxy role
  and a WP-CLI package are versioned artifacts with their own release cadence,
  and this command has no opinion about either.

  Adding a future role or package means adding a row to `MAPPINGS`. Only
  downstreams genuinely extracted *from* wp-ops qualify: one that owns its own
  source, like the Playwright-based `wp-pattern-sentinel`, has no upstream here
  to drift from and is deliberately not listed.

## [5.10.0] - 2026-08-27

### Added

- **`@mutates` manifest directive — the MCP write gate now reads the script's
  own header instead of a hardcoded list.** Which commands `command_run` runs
  directly and which need an explicit `confirm: true` was a `Set` of 31 command
  keys in `mcp-server/src/tools/catalog.ts`, a long way from the scripts it
  described. Renaming a script silently dropped it off that list and flipped it
  to "needs confirm"; the only signal was a stderr warning from
  `warnOnAllowlistDrift` that nothing surfaces to the user.

  `@mutates true|false` parses alongside `@runs` and `@platform`, with `Lint`
  rejecting any other value so a typo fails the build rather than quietly
  picking a default nobody chose. `catalog.Entry` carries the resolved bool:
  only an explicit `@mutates false` reads as read-only, so the unannotated
  majority and any future script that forgets the directive both land on the
  cautious side. It is emitted without `omitempty`, since `false` is the
  interesting case and omitting it would make "read-only" and "field absent"
  indistinguishable to anything reading `catalog.json`.

  The gate's behavior is unchanged — the catalog resolves to exactly the same
  31 read-only commands the allowlist held, verified key for key. What changes
  is that marking a new read-only command is now a one-line manifest edit plus
  `go generate ./internal/catalog/`, instead of an edit in two places that could
  disagree. The TypeScript compares against `false` rather than truthiness, so
  an older `catalog.json` without the field costs an extra confirmation instead
  of skipping one.

### Fixed

- **The binary embedded `mcp-server/node_modules`, `dist/`, and the operator's
  real `config/sites.json`.** `assets.go` embedded `mcp-server` as a whole
  directory. The package comment's reasoning for choosing plain `go:embed` over
  `all:` only covers dot- and underscore-prefixed entries, so the three paths
  gitignored underneath it were picked up whenever they existed on disk — which
  is always, for anyone who has run the server locally.

  `node_modules/` (~61MB) dominated the result: a local build produced a 55MB
  binary, 48MB of it embedded JavaScript, while goreleaser's clean-checkout
  release build of the same commit produced ~8MB. The same commit built to very
  different binaries depending on who built it. `config/sites.json` — SSH hosts,
  remote and local paths, public URLs, no credentials — was readable straight
  out of the embedded filesystem; low-sensitivity, but the wrong thing to ship
  inside a binary and the file most likely to gain something sensitive later.

  `.gitignore` was never the gap: all three paths are correctly ignored and none
  has ever been committed. `go:embed` reads the working tree rather than the
  index, so it sees straight through `.gitignore`, as any build step that walks
  the filesystem does.

  `mcp-server/` is now enumerated file by file, with `sites.example.json`
  embedded in place of `sites.json`. Nothing is lost by dropping the two build
  artifacts: `run.sh` already runs `npm install` when `node_modules/` is absent
  and rebuilds when `dist/` is stale, which is exactly the state a freshly
  extracted install starts in. Local builds now match the release build at
  8.1MB.

  `assets_test.go` guards both directions, because reverting to the one-line
  directory form compiles and passes every other test in the repo — the
  regression is otherwise silent. CI's root-package step gained `go test .` to
  run it, scoped with `.` rather than `./...` since `go.mod` sits at the repo
  root and `./...` would re-run every `go/` test the previous step just ran.

## [5.9.1] - 2026-08-25

### Fixed

- **`db_pull` wrote a command banner into the database instead of the dev URL.**
  `trellis vm shell` prints a `Running command => …` banner to stdout ahead of
  the wrapped command's own output, and `runVm` captured it as part of the
  result. Human-readable callers just showed a noisy extra line, but `dbPull`
  parses that stdout: it read `wp option get siteurl` for the development
  environment, so `devUrl` became the banner *plus* the URL. That value was then
  used as the `search-replace` replacement and interpolated into
  `hostOf(devUrl)` for the multisite `UPDATE wp_blogs SET domain = …`.

  On a real multisite pull this left every row of `wp_blogs.domain` set to the
  banner text truncated at `http:`, plus 61 content cells carrying the banner as
  a prefix — WordPress could then resolve no domain at all and the whole local
  network 500'd. `prodUrl` was unaffected because the source environment is
  reached over SSH, which prints no banner; only the search *replacement* was
  corrupt, which is why the operation still reported success.

  Two changes, since either alone would have prevented the damage:

  - `runVm` now strips the banner from stdout. Only the first line, and only
    when it is the banner — WordPress content can legitimately begin with
    `Running command =>`, and on the demo site post revisions did, from an
    earlier round of this same bug through `wp post get`.
  - `dbPull` now validates both URLs with `assertSiteUrl()` before any write.
    A value that is not a bare `http(s)://host[/path]` throws, so a future
    wrapper change fails loudly rather than propagating across every table.

## [5.9.0] - 2026-08-22

### Added

- **`scripts/local-sandbox/updraft-to-valet.sh` — bootstrap a local Valet site
  from UpdraftPlus backup zips.** Closes #184. Covers the recurring
  "handed a set of backup zips before you have SSH or hosting access"
  onboarding pattern: matches the `plugins`/`themes`/`uploads[+N]`/`others`/`db`
  files in a directory by their shared UpdraftPlus hash, extracts them into
  `wp-content/` (detecting per-zip whether entries carry a `wp-content/`
  prefix, since that has varied across UpdraftPlus versions), downloads a
  matching WP core with `--skip-content`, links it with Valet, creates the
  local database, and imports the dump. The pre-import URL is read straight
  off the compressed dump's `siteurl` row rather than hardcoded, then
  `search-replace`d for `https://<site-slug>.test`. New `@platform wordpress`
  command (not Trellis- or Bedrock-specific) and new `scripts/local-sandbox/`
  category, documented in `scripts/README.md`; `wp-ops doctor` now also checks
  for `valet` on PATH.

## [5.8.0] - 2026-08-21

### Changed

- **`wp pattern validate` is now `wp imagewize pattern-validate`.** The
  command claimed an unprefixed global WP-CLI namespace (`pattern`), which is
  generic enough that publishing it as a standalone WP-CLI package would risk
  colliding with someone else's command. Renamed ahead of publishing rather
  than after, since a post-release rename is a breaking change. Updated
  everywhere the old name was documented: `README.md`, `CLAUDE.md`,
  `docs/bedrock/README.md`, `docs/bedrock/wp-cli-config/README.md`, and
  `docs/category-organization.md`.

## [5.7.1] - 2026-08-21

### Fixed

- **`create-pr.sh` could name an AI assistant in a generated PR description.**
  The generation prompt already forbade mentioning the tooling, but that reads
  as "do not credit yourself" rather than "do not describe a change that
  happens to concern it". So when a diff touched the contributor guide's own
  commit-message convention, the model described it faithfully — and named the
  assistant in prose, in a public description. The prompt now says explicitly
  that the rule survives such a change and that the neutral phrasing
  ("the contributor guide", "commit-message conventions") is what belongs
  there. Referring to a changed file by its real path stays fine.

- **The PR-description convention only ruled out footers.** It said "no AI
  attribution footers or tool references", which the prose above technically
  slipped past. It now rules out any mention anywhere in the description,
  matching the commit-message rule.

## [5.7.0] - 2026-08-21

### Fixed

- **`setup-monitoring.yml`: the security alert e-mail had a broken subject.**
  It built the subject with an unquoted `$(date +%Y-%m-%d %H:%M)`. `date`
  takes `%H:%M` as a second operand and errors out, so `mail` received a
  truncated subject *and* `%H:%M` as an extra recipient. The format string is
  now one quoted argument.

- **`setup-monitoring.yml`: the weekly summary cron job never ran.** It was an
  inline cron command containing `$(date +%Y-%m-%d)`, and cron treats an
  unescaped `%` as end-of-command, piping the remainder to the job's stdin —
  so the entry was truncated mid-word and wrote nothing. It now calls a
  wrapper script, as the daily traffic and security reports already did, which
  keeps `%` out of the crontab entirely and adds the 90-day report cleanup the
  other two had.

  Both were found while porting these playbooks into the standalone
  [`imagewize/trellis-wp-monitoring`](https://github.com/imagewize/trellis-wp-monitoring)
  Ansible role, and both failed silently — no error, just a missing report or
  a mangled e-mail.

### Added

- **A Trellis command reference in the README.** The Trellis section listed
  documentation links but never the commands themselves. It now opens with the
  `trellis ops` equivalence and carries a generated table of all 27
  `@platform trellis` commands, grouped the way `trellis ops` presents them and
  marking the ones that execute on the server. The existing documentation table
  moved under a "Guides" heading rather than being replaced.

## [5.6.0] - 2026-08-21

### Added

- **`trellis ops` — wp-ops as a trellis-cli plugin.** trellis-cli scans `$PATH`
  for executables named `trellis-*`, drops the first `-`-separated segment, and
  registers what's left as a subcommand, exec'ing the binary with the remaining
  argv (roots/trellis-cli `plugin/finder.go`, `cmd/passthrough.go`). That's a
  git/kubectl-style plugin model with no API to implement, so the whole
  integration is a second symlink to the same binary: the Homebrew cask now
  installs `trellis-ops` alongside `wp-ops`, and every wp-ops command is
  reachable as `trellis ops <...>` from inside the tool Trellis users already
  have open.

  The name has to be exactly `trellis-ops`. The finder joins the remaining
  segments with *spaces*, so `trellis-wp-ops` would register the three-word
  `trellis wp ops`; and a first segment matching a core root command is
  silently skipped with no error (`isUnderCoreRootCommands`), which rules out
  `db`, `backup`-adjacent core names, and anything else on `trellis --help`.
  `ops` is free.

  Plugins are registered from `$PATH` before trellis-cli resolves a project, so
  unlike core subcommands `trellis ops` runs anywhere — the playbook commands
  locate the Trellis directory through wp-ops's own `detect.TrellisDir`, exactly
  as they do under bare `wp-ops`.

### Changed

- **Help text and suggestions now name the command you actually typed.** Every
  "Run `wp-ops ...`" line, usage string, and did-you-mean suggestion is rendered
  against `filepath.Base(os.Args[0])`, so a `trellis ops` user is pointed at
  `trellis ops backup` rather than a command they may not know exists. Output
  under bare `wp-ops` is byte-for-byte unchanged.

- **`trellis ops` scopes its listing to `@platform trellis`.** The bare listing,
  `list`, and per-category views show the 27 Trellis-tagged commands across 6
  categories instead of all 74 — someone at a `trellis` prompt isn't looking for
  the image converters or release scripts. An explicit `--platform` overrides
  it, a category with nothing Trellis-tagged still lists in full rather than
  claiming to be empty, and *execution* is never scoped: any command runs if you
  name it. `--json` stays the full catalog, since it's a contract for external
  tooling.

## [5.5.0] - 2026-08-07

### Added

- **`command_search` and `command_run` MCP tools — the catalog bridge.** Every
  other MCP tool wraps one wp-ops capability by hand, which caps what a client
  can see at whatever has been ported so far. The repo has ~74 commands, so a
  client seeing only the 14 wrappers correctly answers "I can't do that" for the
  rest — even when the exact script exists. (Observed in practice: a wp-ops-only
  session asked for GitHub repo traffic gave a well-reasoned out-of-scope answer
  while `scripts/git/gh-traffic.sh` sat two directories away.) These two tools
  expose the whole catalog instead of growing the wrapper list one at a time.

  `command_search` reads `go/internal/catalog/catalog.json` — the file the Go CLI
  embeds — directly, so it works whether or not the binary has been built, and
  gets the full manifest (args, flags, examples, platform) where `list --json`
  deliberately exposes a frozen subset. Its matching mirrors `catalog.Search` so
  `wp-ops search X` and `command_search(X)` can't disagree. A single match
  returns full usage inline.

  `command_run` dispatches through the `wp-ops` binary rather than exec'ing
  scripts, reusing the Ansible and WP-CLI executors, the server-side guard, and
  `--help` formatting instead of reimplementing them. Read-only commands run
  directly; anything that writes, deploys, syncs, or deletes needs
  `confirm: true`. `--help` and `--where` are always free, since `executeEntry`
  handles both before any executor runs. The read-only allowlist is hardcoded in
  `src/tools/catalog.ts` because the manifest has no `@mutates` directive yet; a
  startup check warns on stderr if a listed key leaves the catalog.

- **`gh-traffic.sh` now reports clones and referrers**, not just views. New
  `--clones`, `--referrers`, and `--all` flags; views remain the default when no
  section flag is given, so existing invocations are unchanged. The script also
  accepts multiple `owner/repo` arguments in one pass, and each day-series
  section prints a `Total` row alongside a separate `Unique (14d)` row — GitHub's
  top-level `uniques` is deduplicated across the whole window, so summing the
  daily uniques column would overcount, and folding the two into one "Total"
  would be wrong.

  Clone counts are dominated by CI runners, mirrors, and package resolvers rather
  than people, which is worth knowing before reading them as interest; `--help`
  now says so.

### Fixed

- **`gh-traffic.sh --days N` had no effect.** The flag was parsed and validated
  (rejecting `> 14`) but never applied to the output, so every invocation showed
  the full 14-day window. It now limits the day-series sections to the last N
  days with activity. Referrer data has no day series and is always the full
  window, which `--help` now states.
- **`gh-traffic.sh` reported success when a repo could not be read.** The traffic
  endpoints are maintainer-only, so a 403 is a routine outcome; the script now
  explains that specifically, keeps going so one unreadable repo doesn't hide the
  others, and exits 1 if any section failed. In `--json` mode a failed section
  becomes an explicit `null` — `gh api` writes the API's error body to stdout on
  a 4xx, which previously would have corrupted the document.

### Changed

- **`gh-traffic.sh --json` now emits a JSON array of per-repo objects**
  (`{repo, views?, clones?, referrers?}`) rather than the raw views payload,
  since it can now carry three sections for any number of repos. Nothing in the
  repo consumed the old shape.
- **`gh-traffic.sh` now requires `jq`**, previously optional and used only for
  `--json`. Filtering the three payloads locally needs it.

## [5.4.0] - 2026-08-06

### Added

- **Three more read-only MCP tools**, following on from `monitor`:
  `server_status` (`scripts/monitoring/server-monitor.sh` — live CPU/memory/
  disk/PHP-FPM/MySQL/Nginx/OOM snapshot over SSH), `broken_link_audit`
  (`scripts/monitoring/404-checker.sh` — internal-link 4xx/5xx check, global
  or recursive-spider mode), and `remote_ttfb_audit`
  (`scripts/monitoring/remote-ttfb-ua.sh` — TTFB measured from the server
  itself across multiple crawler user agents). Part of a broader pass
  (tracked across this and the next few entries) filling in MCP tool gaps
  found by auditing `scripts/`, `trellis/`, and `wp-cli/` against the 7 tools
  that existed going into it.
- **`ip_reputation_check` MCP tool** — wraps `trellis/security/check-ips.sh`
  (arbitrary IP lookups against AbuseIPDB) and `check-deny-ips.sh` (audits
  every individual IP in a Trellis project's `deny-ips.conf.j2` for
  staleness, e.g. a score that's dropped to 0). Uses Node's native `fetch`
  directly against the AbuseIPDB API rather than shelling out to `curl`/`jq`.
  Reads the same `trellis/security/.env` `ABUSEIPDB_KEY` the CLI scripts use,
  or `WP_OPS_ABUSEIPDB_KEY` as an override.
- **`admin_user_create` MCP tool** — wraps `wp-cli/security/admin-user-create.sh`
  (lockout recovery: create a temporary WordPress admin with a generated
  password, shown once and never stored) by reusing `wp_cli`'s existing
  `runWpCliRaw` dispatch instead of reimplementing local/SSH/VM execution —
  the script's three steps (check username, check email, create) are just
  three WP-CLI calls against an already-resolved site/env entry. Requires
  `confirm: true`.
- **`db_pull` MCP tool** — ports `scripts/backup/db-pull.sh`'s workflow (pull
  a remote database into local development, with URL search-replace and a
  pre-pull backup of the dev database) to composable calls against the
  registry's already-resolved site/env entries, instead of assembling one
  large remote `bash -c` string: read both URLs via `wp_cli`'s own
  `runWpCliRaw`, back up dev via the existing `db_backup` tool's
  implementation, stream the remote export straight into
  `trellis vm shell -- wp db import -` (buffer-only, no intermediate file
  either side, same binary-safety rationale as `db_backup`'s own export),
  search-replace, optional `--multisite` domain fixup, cache flush. Requires
  `confirm: true` — overwrites the local development database.
  **`db_push` is deliberately not implemented** — pulling into production
  carries too much blast radius for a first pass; noted in
  `mcp-server/README.md`.
- **`files_pull` MCP tool** — wraps `trellis/backup/files-pull.yml`'s rsync
  of a Trellis site's `shared/uploads/` into development's Bedrock
  `web/app/uploads/` on the host (no VM shell needed — a Trellis dev VM
  mounts the project directory into the host filesystem). Additive by
  default; `delete: true` mirrors the remote exactly and requires
  `confirm: true`, mirroring the playbook's own opt-in `--delete` footgun
  flag. **`files_push` is deliberately not implemented**, for the same
  production-risk reason as `db_push`.

## [5.3.0] - 2026-08-06

### Added

- **`monitor` MCP tool** — wraps `scripts/monitoring/monitor.sh` (combined
  traffic, security, AI-crawler, and error-log analysis) as a 7th MCP tool.
  Found missing after observing an agent asked to "use wp-ops mcp monitor"
  fall back to nine ad-hoc bash/ssh steps (find the binary, read `--help`,
  guess at the remote invocation, `Read` the 350-line script to work out its
  argv) because no MCP tool existed for it — only a CLI-catalog script did.
  Requires a site/env entry with `sshHost` (traffic/security logs only exist
  on a deployed server, not local dev or a Trellis VM). Bundles all five
  monitoring scripts (base64-encoded, same SSH-stdin approach as
  `security_scan`) into a throwaway remote temp dir for the run, rather than
  assuming `setup-monitoring.yml` already copied `traffic-monitor.sh` /
  `security-monitor.sh` there — `ai-bot-monitor.sh` and `error-monitor.sh`
  aren't provisioned by that playbook at all, so relying on pre-deployed
  copies would have silently skipped two of the four reports on most sites.

## [5.2.0] - 2026-08-06

### Added

- **`wp-ops mcp-register`** — a native Go command (not a catalog script; same
  bucket as `doctor`/`init`, since it's meta-tooling about wp-ops's own setup
  rather than a WordPress/Trellis operation) that checks `~/.claude.json`,
  `~/.vibe/config.toml`, and `~/.codex/config.toml` for an existing wp-ops MCP
  entry and prints the exact block to add for whichever ones are missing it,
  with the real resolved path to `mcp-server/run.sh` already filled in (via
  the same `repoRoot()` dev-checkout-or-extracted-assets resolution every
  other command uses). Read-only — never writes to a config file it doesn't
  own. Claude's config is parsed as real JSON (`encoding/json`); Mistral's and
  Codex's as real TOML (new `github.com/BurntSushi/toml` dependency), so
  "already registered" detection doesn't rely on string-matching a file it
  didn't validate. Documented in `mcp-server/README.md`'s new "Quick check"
  section, ahead of the three manual "Register with ..." sections.

## [5.1.4] - 2026-08-06

### Fixed

- **`mcp-server/README.md` overstated Streamable HTTP as the transport
  non-Claude clients need.** stdio is a core MCP transport, not a
  Claude-specific one — Mistral Vibe CLI and OpenAI Codex CLI both support it
  the same way Claude Code does (spawn `run.sh` locally, no token/port
  needed), confirmed against each vendor's own docs (2026-08-06). Added
  "Register with Mistral Vibe" and "Register with OpenAI Codex CLI" sections
  mirroring the existing Claude Code one, reframed the Streamable HTTP
  section as for genuinely remote/shared-server cases only, and noted that
  OpenAI's server-side Responses API (unlike its Codex CLI) is remote-MCP-only
  and can't spawn a local process at all.

## [5.1.3] - 2026-08-05

### Fixed

- **The picker's detail view never said a `.php`/`.yml` command needed a
  project on disk.** `--help` for wp-cli and Trellis commands already appends
  a trailer stating the command runs against `$WP_SITE_DIR`/`$TRELLIS_DIR`
  (`FormatWPCLIHelp`/`FormatHelp`), but `exec.DetailBody` — the block the
  interactive picker shows once a command is chosen, before prompting for
  arguments — has no such trailer. A command annotated `@runs local`, like
  `scanner-targeted`, gave no hint it needed anything beyond what's on
  `$PATH` until you actually ran it and hit "`WP_SITE_DIR` is not set."
  `DetailBody`'s meta line now adds `Runs via WP-CLI against the site at
  $WP_SITE_DIR` for `.php` commands and `Runs via ansible-playbook against
  the Trellis project at $TRELLIS_DIR` for `.yml` playbooks, keyed off the
  same file extension `executeEntry` (`cmd/dispatch.go`) already dispatches
  the executor on, so it can't drift. Deliberately not phrased as "runs
  locally": a `.yml` playbook resolves `$TRELLIS_DIR` on this machine but
  often SSHes out from there to do its actual work against a remote host
  (`database-pull`, `files-backup`, ...), so that claim would be wrong for
  exactly the playbooks this note exists to flag. Plain `.sh`/`.js` scripts,
  most of which are self-contained, are unaffected.

- **`scanner-targeted.php`'s six helper functions had undocumented parameter
  and return types** (intelephense `P1132`). Added `@param`/`@return`
  docblocks to `color_text`, `output`, `build_file_list`, `scan_file`,
  `format_bytes`, and `display_results`, matching this file's existing
  doc-comment style rather than introducing native type hints the rest of
  the script doesn't use.

## [5.1.2] - 2026-08-05

### Fixed

- **Every `Examples:` block named the internal key rather than the command
  you type.** 5.1.0 fixed the usage line for every command and every executor,
  but it fixed it by changing the code that *generates* it. Example lines are
  not generated — they are prose copied verbatim out of each script's
  `@example` annotation — so they were never touched, and `--help` printed a
  correct `Usage: wp-ops scanner-targeted` three rows above
  `wp-ops wp-cli/security/scanner-targeted`. 42 of the 71 commands that carry
  examples were affected, 47 lines in total; both render paths showed it, since
  `exec.DetailBody` (the picker) and `exec.writeManifestHelpBody` (`--help`)
  each print the string unchanged.

  The path forms still resolved, so nothing was broken for anyone who pasted
  one — they were wrong in that they taught the long form as the command's
  name. One was genuinely broken: `wp-cli-pattern-validate`'s example still
  named `bedrock/wp-cli-config/`, a category 5.0.0 retired, so the line it
  told you to type answered `Unknown command or category`. That is the same
  class of bug 5.1.1 fixed in `README.md`, missed then because nobody thought
  to grep the *scripts* for the retired category name.

- **`TestExamplesNameTheCommand` now pins this.** The catalog validated its
  own structure but not its prose: `ShortName` is guaranteed to resolve and
  CI already guards the generated catalog against drift, but every one of
  those checks was about the *key*. The `Examples` field travelled from a
  shell comment onto the user's screen without a single assertion that the
  thing it told them to type exists. The new test extracts the token after
  `wp-ops` — skipping `VAR=value` environment prefixes — and requires it to
  equal the entry's `ShortName`, so a rename now fails in the same pull
  request that makes it, which is the only moment the fix is cheap. Left
  unenforced deliberately: that an example mentions only its own command,
  since `check-deny-ips` legitimately pipes into `check-ips`.

- **Server-side and Ansible guidance printed internal keys**, which no sweep
  of the scripts could reach: the macOS access-log hint, the
  missing-argument error, and the unannotated-playbook fallback all formatted
  `e.Key` directly and now read through `CommandName()`. The ambiguity
  message and `search` listing keep printing full keys, where the path is
  the point.

- **The backup hints were stale twice over.** `serverside.go`,
  `scripts/backup/db-backup.sh` and `scripts/backup/site-backup.sh` all
  suggested `wp-ops trellis/backup/database-pull -e site=… -e env=…` — the
  path form *and* the `-e` syntax the playbooks stopped accepting when they
  moved to positional arguments. They now print
  `wp-ops database-pull example.com production`.

- **`trellis/security/check-deny-ips.sh` invoked `check-ips` by full key.**
  Not a hint but a real code path, and the one place a future rename would
  have broken execution rather than a comment.

- **`docs/trellis-cli-comparison.md` §5** asserted in the present tense that
  `wp-ops db-backup --help` prints a full key, contradicting its own status
  header four sections above; and two `trellis/security/README.md`
  invocations used the path form. Documents that quote the path form *as the
  problem being analysed* were left alone.

## [5.1.1] - 2026-08-05

### Changed

- **The two `convert-to-webp` commands were renamed to `jpg-to-webp` and
  `png-to-webp`**, in `scripts/images/` and `scripts/patterns/` respectively.
  They were the catalog's only basename collision, which meant they were the
  only two commands `wp-ops <name>` could not resolve and the only two whose
  usage line still printed a full key with directory separators
  (`Usage: wp-ops scripts/patterns/convert-to-webp [input-file] [options]`) —
  5.1.0's short-name work correctly declines to abbreviate an ambiguous name.
  Renaming removes the ambiguity at its source rather than teaching the CLI to
  paper over it, and the new names say which format each one consumes, which
  the shared name never did: one center-crops a JPG to the Facebook OG ratio
  via `cwebp`, the other batch-converts `pattern-*.png` screenshots via
  `sharp`. Every basename in the catalog is now unique, so every usage line
  names a command that resolves if pasted back.

  Callers and docs were updated with them (`screenshot-patterns.sh`, both
  `README.md` files, `docs/nginx/image-optimization/RESIZE-AND-CONVERSION.md`).
  Any script invoking the old filenames needs the same rename.

### Fixed

- **`README.md` documented a `bedrock` category that no longer exists.** 5.0.0
  moved that tree under `docs/` and dropped `bedrock` from `catalog.Categories`,
  so the documented `wp-ops bedrock wp-cli-pattern-validate …` answered
  `Unknown command or category: bedrock`. The command itself was never removed —
  it lives under `wp-cli/content-creation/` and resolves as
  `wp-ops wp-cli-pattern-validate`.

- **`README.md` still described the picker's live preview pane**, which 5.1.0
  deleted. Details print as a post-selection block above the argument prompts
  now, and the picker renders inline rather than taking over the screen.

- **Three stale counts in `README.md`**: nine backup commands (ten since
  `wp-db-backup`), 39 scripts (42), and five MCP tools (six — `url_audit` was
  missing from the list, though `mcp-server/README.md` already documented it).
  The intro also still said commands group "by subdirectory", which the
  paragraph twenty-five lines below it contradicted with the domain grouping
  5.0.0 introduced.

## [5.1.0] - 2026-08-05

The interactive picker stops behaving like a separate application. It renders
inline, keeps your scrollback, and shows one thing per screen instead of three
at once — the differences benchmarked against `trellis-cli` in the new
`docs/trellis-cli-comparison.md`.

### Changed

- **The picker renders inline instead of taking over the screen.** `RunPicker`
  no longer passes `tea.WithAltScreen()`. The alternate screen buffer keeps no
  scrollback of its own and discards everything drawn in it on exit, which is
  what made a bare `wp-ops` read as a separate prompt rather than as a command
  that printed something. Output from earlier commands now stays visible above
  the picker, and the last frame stays in the buffer after it exits.

  The picker caps itself at 20 rows (`maxInlineRows`) as a consequence: sized
  to the full window it would have shoved the scrollback off-screen on launch
  and left a window-height frame behind on exit, reintroducing the problem from
  the other direction. Same bargain `fzf --height 40%` makes.

- **The browse list is a single full-width column.** It was a bordered list
  pane beside a bordered live-preview pane, and that layout could not survive
  its own width arithmetic: rows were built as a 28-column name plus
  `[platform]` plus `(server)` — about 43 columns — and rendered into a pane of
  `width * 2/5`, so on any terminal narrower than ~118 columns every tagged row
  wrapped and its tags landed in the left margin of the next line. The preview
  pane lost the same fight horizontally, clipping flag help mid-word
  (`Append broken-link resu`). Both were the two panes competing for one
  terminal's width, so neither pane splits it now.

  `[platform]` no longer appears per row — it was the quietest signal on screen
  and the one most responsible for the overflow. `(server)` stays, right-aligned
  into its own column, and yields to the description rather than overflowing
  when the terminal is too narrow for both.

- **Command details moved from a live preview to a post-selection block.**
  Choosing a command now prints its full help at full terminal width — usage,
  description, requirements, examples, arguments, options — directly above the
  argument prompts, which is the moment the information is actually needed.
  Long option descriptions soft-wrap with a hanging indent instead of being
  clipped, so nothing is lost off the right edge.

- **Usage lines name the command you typed, with its real arguments.**
  `wp-ops db-backup --help` answered `Usage: wp-ops scripts/backup/db-backup
  [args...]` — an internal key carrying directory separators no user types, and
  a placeholder where the manifest already knew the positional names three
  lines further down. It now answers
  `Usage: wp-ops db-backup [site-name] [environment] [options]`, derived from
  the same `@arg`/`@flag` data, so it cannot drift from what the command
  documents.

  This lands on `--help` for every executor type and on the picker's detail
  block, because it lands on the shared `writeManifestHelpBody`:

  ```
  Usage: wp-ops database-backup <site> <env>          (Ansible playbook)
  Usage: wp-ops scanner-targeted [path]               (WP-CLI PHP)
  Usage: wp-ops dev [args...]                         (un-annotated Node)
  ```

  The name comes from a new `Entry.ShortName`, computed once by `catalog.Load`
  rather than stored in `catalog.json`: it is a property of the catalog as a
  whole, not of the discovered file, so persisting it would let it go stale the
  moment a colliding command is added. A basename shared by two commands has no
  unambiguous short form — dispatch reports those as ambiguous rather than
  picking one — so those keep the full key and the usage line stays something
  that resolves if pasted back. `convert-to-webp` is currently the catalog's
  only collision.

- **Detail sections are ordered for a bounded viewport.** Requirements and
  examples precede the parameter tables, the reverse of `--help`'s ordering and
  the same shape `trellis alias --help` uses. The block runs past its ~14 rows
  for a real command, so what sits above the fold matters: "needs `ssh`", "runs
  on the server", and a worked invocation decide whether and how to run the
  thing, while the exhaustive per-parameter tables can afford to scroll
  (`pgup`/`pgdn`, hinted in the footer only when there is something to scroll).

- **The category screen opens with a usage line**,
  `Usage: wp-ops [--help] [--version] <command> [<args>]`, as `trellis` does
  above its command table. Without it the screen read as though arrow keys were
  the only interface to 74 commands, when every row is also reachable as
  `wp-ops <command>`.

- **Key hints abbreviate rather than wrap** on terminals too narrow for the
  full footer, and the detail viewport shrinks to its content — a command
  declaring no arguments used to push the prompt nine blank lines down.

### Fixed

- **`truncate` counts runes, not bytes.** Descriptions now fill the width the
  preview pane used to occupy and so get truncated far more often than the old
  28-column name field ever was; several contain an em dash that a byte-indexed
  cut would have split into a partial rune.

### Added

- **docs/trellis-cli-comparison.md** - what `trellis-cli` does at its entry
  point and command surface, what wp-ops does, and which differences are worth
  closing. Verified against both codebases rather than inferred: framework,
  command counts, help ownership, flag handling, completions, and the two
  interactive-prompt models. Also reviews `docs/cli-comparison.md`, whose
  central recommendation (add a `--help` that prints an inline list) describes
  behavior `root.go` has shipped for some time.

## [5.0.0] - 2026-08-05

Implements Option C of `docs/category-organization.md`: the catalog now groups
by **domain** and filters by **platform**, both as manifest metadata. No files
moved and no command keys changed — the directory layout is now an
implementation detail rather than the thing `wp-ops list` shows you.

### Changed

- **BREAKING** - **`wp-ops patterns` is now `wp-ops content`.** The category
  absorbed `wp-cli/content-creation/` and the pattern validator, so
  screenshotting a pattern, creating the page it goes on, and validating the
  file all live in one group. This is the only removed *category* form; see
  Deprecated for the directory categories, which survive, and Option D below
  for the one command key that moved.

- **Categories group by `@category` (domain), not by directory.**
  `displayCategoryFor()` previously honoured the manifest tag only for
  `scripts/**` subcategories with 4+ commands, so `Monitoring` meant
  *`scripts/monitoring` only* and the four `trellis/monitoring` playbooks sat
  under `Trellis`. Now every command's `@category` wins.

  The concrete payoff: **`wp-ops backup` lists all ten backup commands** —
  four shell scripts under `scripts/backup/` and six Ansible playbooks under
  `trellis/backup/` — which the two-directory split made impossible. Same for
  `security` (3 under `wp-cli/`, 2 under `trellis/`) and `monitoring` (13 + 4).
  41% of the catalog previously lived in a domain no single directory
  contained.

  `wp-ops list` goes from 10 directory-ish groups to 12 domain groups:
  Monitoring (17), Backup (10), Content (8), Images (7), SEO (7), Security (6),
  Misc (5), Release (4), Git (3), MCP Server (3), Diagnostics (2), Sync (2).

- **Singletons merged into neighbours** rather than left as one-command groups
  or swept into a catch-all. Dropping the promotion threshold would otherwise
  have produced `WooCommerce (1)`, `Updater (1)`, and `WP-CLI Config (1)` as
  top-level entries. The merges: `patterns` + `content-creation` +
  `wp-cli-config` → `content`; `age-verification` → `snippets`; `woocommerce`
  + `updater` → `misc`. The rejected alternative — a 4+ threshold with the
  rest in `Misc` — would have bucketed 20 commands across ten unrelated
  domains, which is less navigable than the split it replaced. (The
  `snippets` group that merge produced is gone again — see step 7 below.)

- **13 `@category` values normalized.** The tags the analysis flagged as
  directory echoes rather than domains (`wp-cli-config`, `age-verification`,
  `updater`) are the same ones the merges absorbed.

- **`wp-ops search` badges every result with its platform**, e.g.
  `scripts/backup/db-backup  [trellis]  Back up a remote site's database…`.
  Suppressed under `--platform`, where every row would carry the same value.

- **The interactive picker** shows the platform tag per row, faint so it stays
  subordinate to `(server)`. Domain grouping puts an Ansible playbook directly
  above a plain-WP shell script under one header, which is exactly where the
  row needs to say which stack it wants.

### Added

- **`@platform` manifest directive**, on every command. Three values, because
  two aren't enough — `scripts/images/batch-resize.sh` needs no WordPress at
  all, while `wp-cli/security/scanner-targeted.php` needs *a* WordPress but no
  Trellis, and calling both "agnostic" answers the wrong question:

  | Value | Means | Count |
  | --- | --- | ---: |
  | `trellis` | Needs a Trellis project, vault, `/srv/www`, or the `trellis` CLI | 27 |
  | `wordpress` | Any WP install — Valet, Herd, cPanel, Bedrock, Trellis | 17 |
  | `any` | No WordPress involved | 30 |

  Deliberately its own field rather than derived from `@requires`, which names
  binaries and breaks in both directions: `scripts/backup/db-backup.sh`
  declares only `@requires ssh` yet hard-codes `/srv/www` and `web@host`, while
  `@requires wp` says nothing about whether the target must be Trellis. Also
  distinct from `@runs local|server`, which says where a command *executes*,
  not what stack it needs.

- **`--platform` filter on `wp-ops list` and `wp-ops search`.**
  `wp-ops list --platform wordpress` answers "what can I run against this
  site" for a non-Trellis host. An unknown value is rejected up front rather
  than silently filtering to nothing, which would read as "no such commands
  exist" instead of "no such platform".

  This made a real coverage hole **visible before closing it**:
  `--platform wordpress` returned **zero backup commands**, because all nine
  assumed Trellis. Previously `wp-ops backup` listed all nine happily and you
  found out by running one. Step 6 below writes the command that fills it.

- **`catalog.Platforms`** as the single source of truth for legal values,
  shared by the flag usage strings and the validator so `list` and `search`
  can't drift.

- **`manifest.Lint()` validates `@platform`**, alongside its existing `@runs`
  check, so a typo fails the build (`go generate ./...` in `go-build.yml`)
  rather than silently dropping that command out of every `--platform` filter.

### Deprecated

- **Directory categories are now hidden aliases.** `wp-ops trellis
  database-backup`, `wp-ops wp-cli scanner-wrapper`, `wp-ops scripts
  db-backup`, `wp-ops bedrock wp-cli-pattern-validate`, and `wp-ops
  wordpress-utilities <snippet>` all still resolve — they're registered from
  the directory grouping rather than the display grouping, and hidden from
  `--help` so the CLI presents one set of categories instead of two competing
  ones. Prefer the domain form (`wp-ops backup database-backup`).

### Fixed

- **README** - `wp-ops nginx` was documented as listing `nginx/`'s guides. It
  never did: categories with zero commands are skipped at registration, so the
  command has always errored. Those guides are reachable through
  `wp-ops docs`, and Option D below removes the dead category outright.

- **`wp-ops list`'s footer** pointed at `wp-ops trellis` as the example
  category, which the domain regrouping would have turned into a broken
  suggestion printed by the tool itself.

- **The catalog generator's `-out` flag** documented itself as "relative to
  the catalog package directory" but resolved against the working directory.
  Under `go generate` the two coincide, so this only bit a manual run:
  `go run ./internal/catalog/gen` from `go/` wrote a stray, untracked
  `go/catalog.json` and left the real embedded catalog stale — which reads as
  the generator having done nothing. It now resolves from its own source path,
  the same working-directory-independent trick `findRepoRoot()` already used.

### Option D — doc-only trees moved under `docs/`

- **BREAKING** - **`bedrock/wp-cli-config/wp-cli-pattern-validate` is now
  `wp-cli/content-creation/wp-cli-pattern-validate`.** The basename form
  (`wp-ops wp-cli-pattern-validate`) is unchanged, so only the full-key
  invocation moves. Its `@category` was already `content`, which is what made
  `wp-cli/content-creation/` the obvious home — it now sits beside
  `page-creation` and `import-page-draft`.

- **`nginx/` → `docs/nginx/`, `troubleshooting/` → `docs/troubleshooting/`,
  `bedrock/` → `docs/bedrock/`.** All three were pure documentation sitting at
  top level next to command directories, and all three appeared in the curated
  `Categories` order where they were skipped on every pass for having zero
  commands. `bedrock/` became documentation the moment its one command left.
  `wp-ops docs` is unaffected — it walks every `.md` in the repo rather than a
  category list — and `wp-ops nginx` / `wp-ops bedrock` were already
  unreachable, so nothing that previously worked stops working.

  Note `nginx/` was never purely `.md`: it carries four `.conf.j2` templates
  copied into a Trellis `nginx-includes/` directory, and `bedrock/` a
  reference `wp-cli.yml`. These moved with the guides that describe them
  rather than being split off — `browser-caching/README.md` and
  `assets-expiry.conf.j2` are one unit.

- **`.github/workflows/go-build.yml`** - the removed directories are replaced
  in both path-filter blocks by `docs/**`, which also closes a pre-existing
  gap: `docs/` has always been embedded into the binary by `assets.go` but
  never triggered a build when it changed.

- **Inbound links** - 16 markdown links across `README.md`, `AGENTS.md`,
  `scripts/README.md`, `wordpress-utilities/README.md`, `trellis/security/`,
  `wp-cli/migration/`, `wp-cli/security/`, and the moved files' own relative
  paths. `CLAUDE.md`'s repository structure gains a `docs/` section
  describing the split: design docs as loose `.md` at the top level,
  operational guides in subdirectories.

### Step 6 — `wp-db-backup.sh`, the first non-Trellis backup command

- **Added: `scripts/backup/wp-db-backup.sh`** (`@platform wordpress`) - backs
  up any WordPress database to a local `.sql.gz`, closing the coverage hole
  `@platform` exposed. All nine existing backup commands assume Trellis, so
  `wp-ops list --platform wordpress` previously returned **zero** of them; a
  Valet, Herd, cPanel, or plain `public_html` site had no backup path in this
  toolkit at all.

  Everything the Trellis scripts assume is discovered instead. Layout
  detection probes for `wp-load.php` at the given path, then `web/wp`
  (Bedrock), then `wordpress/` — `site-backup.sh` hard-codes Bedrock's
  `web/app/` and breaks on anything else. The site URL comes from
  `wp option get siteurl` rather than `wordpress_sites.yml`, and names the
  backup. `--host` requires an explicit `--site-path` instead of guessing
  `/srv/www/<site>/current`. `--wp-bin`/`--php-bin` reach shared hosts whose
  PHP lives somewhere like `/opt/plesk/php/8.2/bin/php`, matching the
  four-shape host model in `mcp-server/src/registry.ts` rather than inventing
  a second convention. The dump is streamed, so nothing is written on the
  server and no writable backup directory has to exist there.

  Named `wp-db-backup` so `wp-ops db-backup` stays unambiguous — a shared
  basename would turn the short form into a did-you-mean list.

- **Added: `scripts/backup/README.md`** - documents the trellis/wordpress
  split across the four shell scripts, the restore command, and the stdout
  hazard below.

  **Written against a real site, which is why it works.** The first version
  produced a corrupt backup: WP-CLI on the test host printed a PHP
  deprecation notice to **stdout**, so `wp db export - | gzip` made that
  notice the first line of the dump. The result is a valid gzip, of the right
  size, still ending in `Dump completed` — it passes every check the existing
  scripts make and fails only on import. Three fixes came out of it:

  - WP-CLI is invoked **from the site directory**, not merely pointed at it.
    It finds `wp-cli.yml` by walking up from the working directory, not from
    `--path`, so running elsewhere silently drops the site's own config — here,
    a `require` that suppressed those very deprecations.
  - The dump is validated at **both ends**. A trailing `Dump completed` marker
    proves nothing, because pollution arrives at the front; a dump whose first
    line isn't SQL is deleted rather than kept.
  - `--php-bin` now adds `-d display_errors=stderr`. WP-CLI's shebang wrapper
    gives no way to pass `-d`, so invoking PHP directly is the only way to get
    diagnostics off stdout on a noisy host — and the rejection message says so.

### Step 7 — `wordpress-utilities/` entries are no longer commands

The last open question from `docs/category-organization.md`: whether that
tree's five "commands" were commands at all. They weren't — one was a
stylesheet, one an HTML template, and the CLI already routed the whole
directory to a separate print-or-copy executor rather than running anything.
Two of them described operations that WP-CLI can just do, so those became
real commands and the rest became documentation.

- **BREAKING** - **the five `wordpress-utilities/*` entries are gone from the
  catalog**, along with `wp-ops wordpress-utilities <snippet>`. The files
  themselves are unchanged at `docs/wordpress-utilities/`, reachable with
  `wp-ops docs`. Catalog count goes 76 → 73.

- **Added: `wp-cli/security/admin-user-create`** (`@platform wordpress`) -
  replaces the `admin-user-creation.php` snippet, which asked you to paste
  credentials into `functions.php` and remember to delete the block
  afterwards. Nothing is written to a file now: the password is generated with
  `openssl`, printed once, and the matching `wp user delete` line is printed
  with it. Refuses to run if the username or email already exists. Works
  locally or over `--host`/`--site-path`, and appends `--path` only when you
  pass it, so a plain Valet/Herd/`public_html` install isn't forced into
  Bedrock's `web/wp` layout.

- **Added: `wp-cli/seo/noindex-expired-posts`** (`@platform wordpress`) -
  writes Yoast's `_yoast_wpseo_meta-robots-noindex` on published posts whose
  `_post_expiry_date` has passed, in one `wp post list` query rather than a
  per-post read. The `post-expiry-noindex.php` snippet evaluated the same
  condition through Yoast's `wpseo_robots` filter on every front-end request;
  stamping the meta instead makes the result visible in wp-admin, independent
  of the filter being installed, and runnable from cron. `--dry-run` prints
  the affected posts as a table, `--revert` clears the flag from posts whose
  date moved back into the future.

  The snippet is **not** redundant and stays in `docs/`: it also renders the
  "Noindex After Date" meta box that sets `_post_expiry_date` in the first
  place. Keep it for the editor UI; use the command to apply the outcome.

- **Removed: `internal/exec/snippet.go`** and its tests (~130 lines) — the
  print/`--copy`/`--path` executor, plus the `wordpress-utilities/` prefix
  branch in `executeEntry` that was checked ahead of the `.php` branch. It had
  no remaining callers. This drops `--copy` (clipboard) as a feature;
  `wp-ops <command> --where` already covered `--path`, and the clipboard case
  is `cat "$(wp-ops docs -l <term> | head -1)" | pbcopy`.

- **`wordpress-utilities` is dropped from `Categories`**, `assets.go`'s embed
  list, and the CI path filters — the same treatment Option D gave the other
  three, and for the same reason: with no commands left it would have been a
  fourth entry the catalog walked past every time. The `Snippets` display
  group disappears with it (it was exactly those five entries), and `SEO` and
  `Security` each gain one from the new commands.

## [4.2.1] - 2026-08-04

### Fixed

- **trellis/updater/trellis-updater.sh** - the script hardcoded
  `PROJECT="site.com"` and instructed you to edit the file before running. That
  is impossible through the CLI: `wp-ops` executes scripts from a
  version-stamped cache directory (`~/Library/Caches/wp-ops/assets-<version>/`)
  that is replaced on every upgrade, so any edit is silently discarded. The
  command was effectively unusable as installed.

  It now resolves `trellis/` from `$TRELLIS_DIR` — the same variable the
  playbook commands use — falling back to `detect_trellis_dir()` /
  `confirm_trellis_dir()`, the pair already used by `scripts/backup/db-pull.sh`
  and mirroring `go/internal/detect`. `PROJECT` and `PROJECT_DIR` are derived
  from the resolved directory rather than assumed to live under `~/code`.

  This matters beyond convenience: the naive "walk up until you see a trellis/"
  approach picks up an unrelated sibling checkout — from `~/code/seo-strategy`
  it would find `~/code/trellis` and rsync into the wrong project. The shared
  helper guards against that (a parent holding `trellis/` is trusted only when
  you started there, or came up through its own Bedrock site), stops at `$HOME`,
  and refuses to guess non-interactively since the operation overwrites
  `trellis/`.

## [4.2.0] - 2026-08-04

### Added

- **scripts/release/release-theme.sh** - Mistral Vibe joins claude and codex as
  an AI backend (`--ai=vibe`, `VIBE_COMMAND`, `VIBE_CLI_ARGS`). This existed only
  in the imagewize.com fork of the script and was never upstreamed, so it would
  have been lost when that fork was deleted. `create-pr.sh` already supported
  vibe; `release-theme.sh` did not.

  Vibe takes the prompt as an argument rather than on stdin and writes its own
  errors to stdout, so its branch does not capture stderr separately the way the
  claude and codex branches do. Default args are `-p` unless `VIBE_CLI_ARGS` is
  set.

### Known inconsistency

`scripts/release/release-plugin.sh` is release-theme's sibling and still offers
only claude and codex. Nothing depended on vibe there, so it was left alone
rather than changed speculatively — worth aligning if vibe becomes a regular
part of the release flow.

## [4.1.0] - 2026-08-04

### Added

Four commands adopted from `seo-strategy/tools/scripts/`, generalized off
imagewize-specific hardcodes. That repo had accumulated ~32 scripts, 16 of them
forks of scripts already here; these four were the ones with no wp-ops
equivalent, so they move up before the forks get deleted.

- **scripts/images/svg-to-jpg.sh** - renders design SVGs to JPG next to their
  source via librsvg (accurate font/gradient rendering) plus ImageMagick to
  encode. Takes a directory or individual `.svg` files. `-w`/`-h` force output
  dimensions for a platform spec (e.g. Mastodon's 1920x1080), `-s` scales by a
  multiplier for high-DPI, `-q` sets quality. Since the source is vector,
  upscaling is lossless.
- **scripts/images/svg-to-png.sh** - the same, to PNG. Prefer it for any banner
  or card carrying text or a logo — JPG compression blurs fine text edges, which
  shows up on wordmarks and URL strips. Gained `-w`/`-h`/`-s` in the move; the
  original was native-size only.
- **scripts/monitoring/traffic-by-country.sh** - pulls an Nginx access log over
  SSH, resolves every unique client IP through `geoip2fast`, and reports only
  the requests from one country, with bots, static assets, attack probes, Tor
  exits, and redirect/404 responses filtered out. Answers "did anyone from NL
  actually read the page after that outreach batch went out?" `--quick`/`--hours`
  bound how much log gets pulled; `--pattern` narrows to a URL regex.
- **wp-cli/seo/orphan-links-audit.sh** - finds published posts/pages that no
  other content links to, as a single SQL query. This is the inbound-link
  sibling of the existing `orphan-pages-audit.sh`, which only checks navigation
  menus — a page can sit in the nav with zero in-content links, or be linked
  from a dozen posts while absent from every menu, so the two are worth running
  together. Runs locally or against production over `--host`. Link detection is
  a slug substring match, so the output is a shortlist to review rather than a
  verdict; the script and README both say so.

### Changed

- **wp-cli/seo/README.md** - the orphan-pages "Important Note" pointed at
  Screaming Frog/Ahrefs/Sitebulb for "filter for pages with 0 internal links".
  That is now `orphan-links-audit.sh`, so the note points there first and keeps
  the external crawlers as the step beyond both scripts.

### Fixed

- **go/internal/catalog/catalog_test.go** - count expectations updated for the
  four new commands (72→76 entries, scripts 38→41, monitoring display 12→13),
  following the existing running-tally comment convention.

## [4.0.0] - 2026-08-04

### Removed

- **BREAKING** - the bash CLI (`wp-ops`, ~2,400 lines at the repo root) and
  its installer (`install.sh`) are deleted. The Go CLI (`go/`, installable
  via `brew install imagewize/tap/wp-ops` or built from source) reached
  full parity with the bash implementation at M4 (v3.23.1) and is now the
  only CLI — this was the planned 4.0.0 removal flagged in
  `docs/cli-ux-plan.md`'s Risks section. `docs/go-mcp-parity.md`'s
  "keep three interfaces" decision is superseded; two remain (Go CLI, MCP
  server).
- **.github/workflows/manifest-lint.yml** - ran `./wp-ops manifest lint`,
  which no longer exists. Redundant with `go-build.yml`'s "Generate
  catalog" step, which already fails the build on a malformed manifest via
  `manifest.Lint()`.
- **go/scripts/parity-check.sh** - diffed bash vs. Go CLI output; nothing
  left to diff against.
- **`wp-ops doctor`'s `fzf` check** - listed `fzf` as an optional helper
  ("fuzzy command picker in the bash CLI"). The Bubble Tea picker has its
  own fuzzy filtering built in, so doctor was advertising a tool nothing in
  the repo uses.

### Changed

- **README** - reframed around the Go CLI as the only CLI: dropped the
  "Go rewrite" framing and bash-specific fzf/`install.sh` instructions,
  added a "build from source" fallback (`go build -o wp-ops ./go`) for
  users without Homebrew. That fallback needs `sudo` to write to
  `/usr/local/bin` (root-owned on stock macOS), and Go 1.26+ is now listed
  under Requirements — previously the no-Homebrew path was `install.sh`,
  which needed no toolchain. Also notes that the clone can be deleted after
  building, since the scripts are embedded in the binary.
- **docs** - `docs/go-mcp-parity.md` and `docs/cli-ux-plan.md` both gained
  status notes marking the bash CLI's removal against their earlier
  "deleted only at 4.0.0" / "verified against bash" language.
- **go/main.go** - package doc comment no longer describes the binary as
  "a rewrite of the bash wp-ops CLI wrapper".

### Fixed

- **README's scripts count** - said "27 standalone Bash/PHP/Python
  utilities"; `scripts/` holds 39 (33 Bash, 3 Node, 2 Python, 1 PHP),
  38 of which the CLI exposes as commands — `updown-webhook-receiver.php`
  is deployed to a webserver rather than run from the CLI, but is
  documented in `scripts/README.md` alongside the rest. The count had
  drifted since 3.35.0 and the language list never mentioned Node.

## [3.35.1] - 2026-08-03

### Fixed

- **scripts/backup** - `db-pull.sh` required `TRELLIS_DIR` to already be exported and hard-failed otherwise, unlike the Go `wp-ops trellis <playbook>` path (e.g. `files-pull`, which only exists as an Ansible playbook) which auto-detects a Trellis project from the current directory and confirms before using it. Ported the same walk-up detection and interactive confirmation (`detect_trellis_dir`/`confirm_trellis_dir`, mirroring `go/internal/detect`'s `TrellisDir`/`Confirm`) into `db-pull.sh` itself, so it now only demands an explicit `export TRELLIS_DIR=...` when no project can be found nearby or the session is non-interactive.

## [3.35.0] - 2026-08-03

### Added

- **mcp-server** - `wp_cli` tool output is now capped at 15,000 characters (`truncateWpCliOutput()` in `tools/wpCli.ts`), addressing item 9 of `docs/mcp-server-recommendations.md`: a big `wp post list` on a large site could otherwise dump tens of KB straight into an agent's context. The truncation notice hints at `--format=count` / `--fields=` / `--posts_per_page=` to narrow the command instead. Applied only at the `wp_cli` tool's call site in `server.ts` — `urlAudit.ts`'s own `runWpCli` calls (search-replace previews) are already small, curated reports and stay untruncated.
- **mcp-server** - `redirect_audit` and `schema_audit` both gained a `summary: boolean` parameter (item 9): when true, pages that fully pass — the same categories each tool already scores into its pass/fail counts — or already have schema are omitted from the per-page detail and replaced with a single "N page(s) omitted" line, cutting typical output on multi-page audits by more than half.

### Changed

- **mcp-server** - `wp_cli`, `redirect_audit`, `schema_audit`, and `url_audit` tool descriptions trimmed from 3–4 sentences to 1–2 (item 10 of `docs/mcp-server-recommendations.md`), since user-scope registration loads all five tool descriptions into every session in every project. The confirm-gating detail `wp_cli`'s description used to spell out is still fully covered by the runtime error already thrown when a mutating command is called without `confirm: true`, so no information was lost.
- **README** - reworded the `TRELLIS_DIR`/`WP_SITE_DIR` section to lead with the existing auto-detection behavior (wp-ops walks up from the current directory and asks before using what it finds) rather than presenting the explicit `export` as a hard prerequisite; the variables are only required when running from outside the project or non-interactively.
- **docs** - `docs/mcp-server-recommendations.md`: marked items 9 and 10 done.

## [3.33.0] - 2026-08-03

### Changed

- **scripts/monitoring** - `run-monitoring.sh` renamed to `monitor.sh` (Gap 1 of `docs/wp-ops-recommendations.md`) — the one genuinely opaque script name in the catalog; nothing about "run-monitoring" suggested it was the combined traffic/security/AI-bot/error report. `wp-ops monitor` (and `wp-ops scripts/monitoring/monitor`) now resolves via the existing basename resolution, no new directive or alias needed. Every reference to the old key/filename was swept alongside the rename: `wp-ops` (bash — `SERVER_SIDE_COMMANDS`, `server_side_example_args`, doctor/guard prose), `go/cmd/serverside.go` and its tests, `go/internal/catalog/gen/main.go`'s `serverSideFallback` map (`catalog.json` regenerated), and the current-state docs `README.md`/`scripts/README.md`. `go/scripts/parity-check.sh` still 8/8.

## [3.32.0] - 2026-08-03

### Added

- **scripts/woocommerce**, **trellis/updater** - the two mutating commands `docs/wp-ops-recommendations.md`'s Gap 7 audit flagged with no dry-run and no confirmation prompt now have both. `create-product-variations.sh` takes `-d`/`--dry-run` (matching `batch-resize.sh`'s convention): it builds each `wp wc product_variation create` invocation either way, but only prints it instead of running it over `trellis vm shell` when the flag is set, so the full attribute cross-product can be previewed with no VM round trip. `trellis-updater.sh` now prompts `This will overwrite files in $TRELLIS_DIR. Continue? (y/N)` before it starts backing up and rewriting the Trellis directory; `-y`/`--yes` (matching `db-pull.sh`'s convention) skips it for non-interactive use. Both scripts' manifest headers gained a `@flag` line so the new flags surface in `--help` and the interactive picker in both CLIs; `go/internal/catalog/catalog.json` regenerated, `go/scripts/parity-check.sh` still 8/8.

## [3.31.0] - 2026-08-03

### Added

- **trellis/backup** - `files-pull` takes an optional `--delete yes` flag (`wp-ops files-pull example.com production --delete yes`, or `-e delete=yes` when running the playbook directly), which passes rsync's `--delete` through the `synchronize` task and makes the development uploads directory an exact mirror of the remote. The default stays `no`, i.e. a purely additive pull: local-only files survive, which is what you want most of the time — a long-lived development copy accumulates dev-only uploads and keeps media that has since been deleted from the remote library (on imagewize.com, 142 such files out of 16,670 after a fully-synced pull, mostly rotated `wc-logs/`, deleted screenshots and their generated sizes, and `.DS_Store`). Mirroring is destructive on the development side only and runs without a confirmation prompt, so the playbook emits an explicit warning task when the flag is on, and the completion message now states which mode ran (`mirrored — local-only files deleted` vs `additive — local-only files kept`). `trellis/backup/README.md` documents an `rsync --dry-run --itemize-changes` invocation for previewing the deletions first.

  Deliberately not added to `files-push`: the same flag there would delete files on the remote server, a different risk class than pruning a local checkout.

## [3.30.3] - 2026-08-03

### Fixed

- **trellis/backup** - `files-pull` and `files-push` failed on every Trellis project with `Task failed: ... Error while resolving value for 'path': hostvars['development_host']`. Both playbooks read the development site's location as `{{ hostvars.development_host.wordpress_sites[site].local_path }}` and delegated their local-side tasks with `delegate_to: development_host`, but no such inventory host exists — Trellis's `hosts/development` lists the development machine by address (e.g. `192.168.56.5`), and nothing in Trellis or wp-ops ever defines a `development_host` alias. They now read `local_path` out of development's own `group_vars` via `lookup('file', 'group_vars/development/wordpress_sites.yml') | from_yaml`, which is what the sibling `database-pull.yml`/`database-push.yml` already do (the play's own `wordpress_sites` belongs to the *remote* environment, so it can't supply a development path), and delegate their local tasks to `localhost` with `become: no` per the repo's local-delegation convention. The relative `local_path` this yields (e.g. `../site`) resolves against the playbook's directory, which is the Trellis project root — see 3.30.2's staging fix.

Surfaced by the 3.30.2 end-to-end check: with `group_vars` finally resolving, `wp-ops files-pull imagewize.com production` got as far as the sync tasks and failed there instead, which is what exposed this second, older bug behind it. Verified fixed by a real pull against imagewize.com production — 140 files synced into `../site/web/app/uploads/`, with the staged `.wp-ops-run-*` playbooks cleaned up afterward.

## [3.30.2] - 2026-08-03

### Fixed

- **go** - `wp-ops <trellis-playbook-command> site env` (e.g. `files-pull`, `database-pull`, `quick-status`) failed with `Error processing keyword 'remote_user': 'web_user' is undefined` (or any other var normally set in the project's `group_vars/`) on every real Trellis project, because Ansible resolves `group_vars`/`host_vars` relative to the *directory containing the playbook file actually being executed* — not the current working directory and not the inventory's directory. `RunPlaybook` (`go/internal/exec/ansible.go`) ran these playbooks straight from wherever they physically live (the wp-ops Homebrew cask's own asset cache, e.g. `~/Library/Caches/wp-ops/assets-<version>/trellis/backup/files-pull.yml`), so the project's `group_vars/` — where `web_user`, PHP version, etc. are defined — was never loaded, even though `cmd.Dir` was correctly set to `$TRELLIS_DIR` and inventory/`-e site=`/`-e env=` resolution all looked fine (which is what made this easy to miss: only vars sourced from `group_vars/` were affected). Added `stagePlaybookInProjectDir`, which copies the entry playbook — and, recursively, any same-directory file it references via `import_playbook:` (only `variable-check.yml` today, across every `trellis/backup/*.yml` and `trellis/monitoring/*.yml` command) — into `$TRELLIS_DIR` itself under randomized `.wp-ops-run-*` names before running, rewriting the `import_playbook:` references to match, and removing every staged file afterward (`defer cleanup()`); a `sweepStalePlaybookStaging` pass at the start of each run also clears any leftovers from a prior run that was killed before it could clean up after itself. `RunPlaybook` now runs the staged copy instead of the original path.

- **trellis/monitoring**, **go** - `setup-monitoring`, `traffic-report` and `security-scan` copied their helper scripts with a playbook-relative `src: "../../scripts/monitoring/*.sh"`, which resolved only because Ansible anchors a relative `src:` to the executed playbook's directory and those playbooks sat exactly two levels under the wp-ops root. Staging them into `$TRELLIS_DIR` (above) moves that anchor onto the Trellis project, where `../../scripts/monitoring/` is two directories *above* the project and does not exist — so the three commands would have failed at their copy tasks. The four `src:` references now go through a `monitor_scripts_dir` var, `{{ wp_ops_root | default(playbook_dir + '/../..', true) }}/scripts/monitoring`, and the Go CLI passes `-e wp_ops_root=<abs repo root>` via the new `WithWPOpsRoot` (`go/internal/exec/ansible.go`, prepended so an explicit caller-supplied `-e` still wins). The `default` keeps the bash `wp-ops` CLI — which runs playbooks in place, not staged — working unchanged.

- **go** - `sweepStalePlaybookStaging` deleted *every* `.wp-ops-run-*` file it found, including those of a concurrently running `wp-ops` command against the same Trellis project (two terminals, or one backup running alongside another), defeating the randomized run IDs meant to keep such runs independent. It now skips anything modified within the last hour (`stalePlaybookStagingAge`), which is far longer than the window between staging a playbook and `ansible-playbook` parsing it — `import_playbook:` is a static import, resolved at parse time — so a long-running pull is unaffected by a later run's sweep.

- **go** - a relative `TRELLIS_DIR` (e.g. `export TRELLIS_DIR=./trellis`, which `resolveTrellisDir` accepts since it only stats `<dir>/ansible.cfg`) broke playbook runs once staging landed: the staged path is `trellisDir`-joined while `cmd.Dir` is `trellisDir` itself, so `ansible-playbook` was handed `trellis/.wp-ops-run-*.yml` to resolve from inside `trellis/`. `RunPlaybook` now resolves `TRELLIS_DIR` to an absolute path once, up front, and uses it for both.

Found while diagnosing why `wp-ops files-pull imagewize.com production` failed on a real Trellis project (imagewize.com) despite `TRELLIS_DIR` being set correctly — confirmed by reproducing the same failure with a trivial `debug: msg="{{ web_user }}"` playbook run from outside the project (`UNDEFINED`) versus the identical file copied directly into the project directory (`web`), and again one directory level deep inside the project (still `UNDEFINED` — Ansible does not walk up looking for `group_vars/`, confirming the fix has to place the copy at the project root, not merely somewhere inside it).

## [3.30.1] - 2026-08-03

### Fixed

- **go** - `wp-ops <TAB>` (root-level completion) offered categories and other registered subcommands but no basenames (e.g. `db-backup`, `db-pull`) — the per-entry full-key commands (`scripts/backup/db-backup`) are registered `Hidden` so `wp-ops --help` isn't drowned in ~66 entries, and Cobra's default subcommand-name completion skips hidden commands. `wp-ops <category> <TAB>` (e.g. `wp-ops scripts <TAB>`) already worked via `categoryBasenameCompletions`; root itself had no `ValidArgsFunction` to fall back on. Added `rootBasenameCompletions` (`go/cmd/dispatch.go`) and wired it into `rootCmd.ValidArgsFunction` (`go/cmd/root.go`) — Cobra calls `ValidArgsFunction` in addition to its subcommand-name matching, not instead of it, so this supplements the existing category/subcommand completions rather than replacing them. Matches the bare-basename invocation `rootRunE` already supports via `FindByBasename`.

Found after running `wp-ops init` and finding `wp-ops db<TAB>` produced no completions.

## [3.30.0] - 2026-08-03

### Added

- **go** - `wp-ops init`: installs the Cobra-generated shell completion script for zsh, bash, or fish (auto-detected from `$SHELL`, or `--shell` to override), so `wp-ops <TAB>` works without the user hand-running `wp-ops completion <shell>` and figuring out where to put the output themselves. Prefers Homebrew-managed completion directories (`$(brew --prefix)/share/zsh/site-functions`, `.../share/bash-completion/completions`) when `brew` is on `PATH` — matching how this CLI is actually distributed (`homebrew_casks` in `.goreleaser.yml`, which unlike a Homebrew formula does *not* wire up completions automatically) — and falls back to a per-user directory (`~/.zsh/completions`, `~/.local/share/bash-completion/completions`, `~/.config/fish/completions`) otherwise, printing the `fpath`/`source` line the user still needs to add in that case. Named to match trellis-cli's `trellis init`; `doctor` remains the `trellis check` equivalent, which already existed.

Addresses a gap raised in conversation: `doctor.go`'s `checkShellCompletion()` could tell you completions weren't installed but nothing installed them, and the Homebrew cask distribution path means no user gets them for free.

## [3.29.0] - 2026-08-03

### Added

- **wp-ops**, **go** - a generic positional-argument translator for `trellis/**/*.yml` (Ansible playbook) commands: `build_playbook_args()` in `wp-ops` (bash), `BuildPlaybookArgs()` in `go/internal/exec/ansible.go` (Go). Every `.yml` command's manifest already declares its `@arg`/`@flag` names, so the executor now consumes required `@arg` entries positionally, in manifest order, into `-e name=value`, then reads anything after that as `--name value` / `--name=value` against the declared `@flag` names into more `-e name=value` pairs — `wp-ops database-backup example.com production` and `wp-ops security-scan example.com production --hours 48 --threshold 50` both now work, matching `db-backup`/`db-pull`'s ergonomics without a bespoke script per playbook. The legacy explicit `-e key=value [...]` form keeps working unchanged: if the first raw arg already starts with `-`, nothing is translated. Covers all ten `trellis/backup/*.yml` and `trellis/monitoring/*.yml` commands from one change per CLI.

### Changed

- **trellis/backup**, **trellis/monitoring** - `@example` lines updated to the new positional form across `database-backup.yml`, `database-push.yml`, `database-pull.yml`, `files-backup.yml`, `files-pull.yml`, `files-push.yml`, `quick-status.yml`, `security-scan.yml`, `traffic-report.yml`, `setup-monitoring.yml`; the four with optional `@flag`s gained a second example demonstrating `--flag value` usage. `catalog.json` regenerated; `go/scripts/parity-check.sh` passes 8/8.
- **docs** - `docs/wp-ops-recommendations.md`: marked Gap 6a done, with a note on why this was one generic translator rather than nine bespoke scripts (per `go-mcp-parity.md`'s "the scripts are the single source of truth" decision), and why a `@key`/`@alias` short-name directive was considered again and rejected for the same reason the original `@key` proposal was — bare-basename resolution already gives every one of these commands its short name today.

Addresses Gap 6a of `docs/wp-ops-recommendations.md`.

## [3.28.0] - 2026-08-03

### Added

- **mcp-server** - `url_audit` tool (`mcp-server/src/tools/urlAudit.ts`, registered in `mcp-server/src/server.ts`): audits `wp_posts.post_content` for hardcoded dev URLs (default patterns `.test`/`.localhost`) that `get_template_directory_uri()` bakes in during local content creation and that survive a database migration unless search-replaced — the CRITICAL check documented in the parent repo's `CLAUDE.md`, previously only reconstructed by hand from `wp-cli/migration/URL-UPDATE-METHODS.md` and `wp-cli/content-creation/PAGE-CREATION.md` each time. Reports a `wp db query` hit count per pattern; an optional `replace: {from, to}` always previews `wp search-replace --all-tables --precise --dry-run` first and only applies it for real when `confirm: true` is also set, matching `wp_cli`'s existing confirm-gating convention.

### Changed

- **mcp-server** - `tools/wpCli.ts`: factored `runWpCliRaw` (returns the raw exit code/stdout/stderr) out of `runWpCli` (which formats that into a human-readable string), so `urlAudit.ts` can parse the count query's stdout directly instead of scraping it out of the formatted string. `runWpCli` is now a thin wrapper over `runWpCliRaw`; behavior unchanged for existing callers.
- **docs** - `docs/mcp-server-recommendations.md`: marked item 11 (the `url_audit` tool) done. `docs/wp-ops-recommendations.md`: marked Gap 4 done.

Addresses Gap 4 of `docs/wp-ops-recommendations.md` and item 11 of `docs/mcp-server-recommendations.md`.

## [3.27.1] - 2026-08-03

### Fixed

- **scripts/backup** - `db-backup.sh` wrote its export to `/srv/backups/<site>/database` on the remote server, but a stock Trellis box provisions and `chown`s `/srv/www`, never `/srv/backups` itself — the `web` user the script runs as couldn't `mkdir` there, so the script failed on every Trellis server's first run, not just the one it was caught on (`imagewize.com`). Rebuilt as a local wrapper: it SSHes into the site's own web directory (already `web`-writable) and streams `wp db export - | gzip` straight into a local `database_backup/` directory, the same pattern `db-pull.sh` and the MCP `db_backup` tool (`mcp-server/src/tools/dbBackup.ts`) already use — no remote temp file is ever written, so there's nothing to clean up server-side either.

### Changed

- **scripts/backup** - `db-backup.sh` is now `@runs local` (was `server`) and no longer needs the `ssh web@example.com 'bash -s' < db-backup.sh` invocation — `wp-ops db-backup example.com production` runs it directly, matching `db-pull.sh`'s calling convention. New `--host`/`--dest` flags; the `backup-type` argument's `development` choice was dropped (development is already local — running `wp db export` directly needs no SSH hop) in favor of `environment` (`production`/`staging`). `trellis/backup/database-backup.yml` is unchanged and still the right tool for automated/Ansible-native backups.
- **wp-ops**, **go** - Removed `scripts/backup/db-backup` from the now-stale hardcoded server-side command lists (`BACKUP_COMMANDS`/`SERVER_SIDE_COMMANDS` in `wp-ops`, `backupCommands` in `go/cmd/serverside.go`, `serverSideFallback` in `go/internal/catalog/gen/main.go`) now that its manifest declares `@runs local` directly — `wp-ops`'s `is_server_side_command()` already prefers the manifest over these lists, but leaving stale entries there was misleading. `catalog.json` regenerated; `go/scripts/parity-check.sh` passes 8/8.
- **docs** - `docs/wp-ops-recommendations.md`: marked Gap 6's `db-backup` item done. `trellis/backup/README.md`: added a "Direct Shell Script Method" subsection under Database Backup pointing at the new script, mirroring the existing one under Database Pull.

Addresses Gap 6 of `docs/wp-ops-recommendations.md`.

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
