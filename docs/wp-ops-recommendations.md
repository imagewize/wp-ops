# WP-Ops Recommendations: Real Gaps

> **Status:** Updated 2026-08-22 — most gaps below are now closed. See [What shipped since the draft](#what-shipped-since-the-draft).
> **Scope:** What is actually missing from wp-ops, based on comparing its catalog
> against `~/code/imagewize.com/scripts` and `~/code/seo-strategy/tools/scripts`.
> **Related:** [mcp-server-recommendations.md](mcp-server-recommendations.md) (MCP roadmap),
> [go-mcp-parity.md](go-mcp-parity.md) (why there are three interfaces),
> [category-organization.md](category-organization.md) (domain grouping and @platform),
> [trellis-extensions-evaluation.md](trellis-extensions-evaluation.md) (Path A shipped),
> [wp-cli-package-evaluation.md](wp-cli-package-evaluation.md) (one WP-CLI package shipped),
> [third-party-extensions.md](third-party-extensions.md) (extension mechanism design)

---

## What shipped since the draft

This document was written 2026-08-03. The following closed gaps between then and
2026-08-22:

| Gap | Shipped | How | Date |
|-----|---------|-----|------|
| Gap 2 (`db-pull` ergonomics) | ✅ | `scripts/backup/db-pull.sh` added as positional wrapper | 2026-08-03 |
| Gap 4 (`url_audit`) | ✅ | MCP `url_audit` tool in `mcp-server/src/tools/urlAudit.ts` | 2026-08-03 |
| Gap 5 "Take" rows | ✅ | Four scripts imported and annotated | 2026-08-03 |
| Gap 6a (nine `-e`-style playbooks) | ✅ | Generic positional-arg translator (`BuildPlaybookArgs`) | 2026-08-03 |
| Gap 6 (`db-backup` for non-Trellis) | ✅ | `scripts/backup/wp-db-backup.sh` — first `@platform wordpress` backup command | 2026-08-05 |
| Gap 7 (dry-run coverage) | ✅ | `--dry-run` for variations, confirmation for trellis-updater | 2026-08-03 |
| Option C & D from category-organization | ✅ | Domain grouping + `@platform` tag on all 75 commands | 2026-08-05 |
| `trellis-ops` plugin (Path A) | ✅ | Homebrew symlink `trellis-ops` → `wp-ops` | 2026-08-21 |
| WP-CLI package | ✅ | `imagewize/wp-cli-pattern-validate` v1.0.0 on GitHub | 2026-08-21 |

**Result:** `wp-ops list --platform wordpress` now returns 18 commands (including
`wp-db-backup`) that work against Valet, Herd, cPanel, or any plain WordPress install.
The original coverage hole that prompted Step 6 of category-organization — zero backup
commands for non-Trellis sites — is closed.

---

## The verbose-path premise is false

An earlier draft of this document (and a companion `command-simplification.md`,
now deleted) was built on the claim that users must type
`wp-ops scripts/backup/db-backup example.com production`, and proposed a new
`@key` manifest directive to shorten it.

They don't, and it isn't needed. Verified 2026-08-03:

```console
$ ./wp-ops db-backup --help
Usage: wp-ops scripts/backup/db-backup [args...]
Back up a Trellis site database with WP-CLI, gzip it, and prune backups older than 30 days
```

Bare-basename resolution across the whole catalog already exists — Go
`go/cmd/root.go:95-104` (`catalog.FindByBasename`) — with ambiguity detection and
did-you-mean suggestions. (Verified 2026-08-03 against both CLIs; the bash CLI
was deleted 2026-08-04, v4.0.0 — see [go-mcp-parity.md](go-mcp-parity.md).)
Every script the earlier draft proposed annotating
(`db-backup`, `site-backup`, `batch-resize`, `jpg-to-webp`,
`make-square-webp`, `page-creation`) already resolves by short name.

`@key` would also have registered each alias as a second `COMMAND_FILE` entry,
duplicating every aliased script in `wp-ops list` and `--json` and breaking
`go/scripts/parity-check.sh`.

**Recorded so this is not re-derived.** The genuine remainder of that idea is Gap 1
below, which is a naming problem, not a resolution-mechanism problem.

---

## Gap 1: A few script names don't match what you'd type

Resolution works; some *names* are just not the obvious word. Verified against the
current catalog:

| You'd type | Today | Actual script |
|------------|-------|---------------|
| `wp-ops traffic` | fails | `scripts/monitoring/traffic-monitor.sh` |
| `wp-ops security` | fails (suggests `security-monitor`) | `scripts/monitoring/security-monitor.sh` |
| `wp-ops monitor` | works — resolves to `scripts/monitoring/monitor.sh` (renamed from `run-monitoring.sh`, 2026-08-03) | `scripts/monitoring/monitor.sh` |
| `wp-ops ai-bots` | fails | `scripts/monitoring/ai-bot-monitor.sh` |
| `wp-ops image-resize` | fails | `scripts/images/batch-resize.sh` |
| `wp-ops page-create` | fails | `wp-cli/content-creation/page-creation.sh` |

Note the did-you-mean already catches most of these — `wp-ops security` prints
`Did you mean: wp-ops scripts/monitoring/security-monitor`. The cost of the status
quo is one extra round trip, not a lookup failure.

**Options, cheapest first:**

- **Do nothing.** Defensible. The suggester handles it and the `-monitor` suffix is
  arguably clearer than a bare `security`.
- **Rename the files** (`git mv`), letting the existing basename resolution do the
  rest. No CLI code, no new directive, works in both CLIs immediately. Costs:
  breaks any `ssh … 'bash -s' < path/to/script.sh` invocations documented in
  READMEs and in the two sibling repos, so it needs a grep-and-fix sweep.
- **An alias table**, if a name should exist under two spellings. Only worth it if
  renaming proves too disruptive — it reintroduces the duplicate-catalog-entry
  problem `@key` had and must land in bash, Go, and `parity-check.sh` together.

**Recommendation:** rename `run-monitoring.sh` → `monitor.sh` (the one genuinely
opaque name — nothing about "run-monitoring" suggests it is the combined report),
and leave the rest. Revisit only if the suggester turns out to be annoying in
practice.

**Done, 2026-08-03.** `git mv scripts/monitoring/run-monitoring.sh
scripts/monitoring/monitor.sh` — basename resolution then does the rest, so
`wp-ops monitor` (or `wp-ops scripts/monitoring/monitor`) now works in both
CLIs with no new directive or alias table. Every reference to the old
filename/key was swept and fixed alongside the rename, not left to the
suggester: `wp-ops` (bash — `SERVER_SIDE_COMMANDS`, the `server_side_example_args`
case, and prose in `doctor`/server-side-guard comments), `go/cmd/serverside.go`
and its test (the `serverSideExampleArgs` case and `accessLogCommands` prose),
`go/internal/catalog/gen/main.go`'s `serverSideFallback` map (regenerating
`catalog.json`), and the current-state docs `README.md` and `scripts/README.md`
(usage examples, the file-tree listing — reordered alphabetically since
`monitor.sh` now sorts before `redirect-check.sh` — and the cron example).
Historical status docs (`docs/m3-go-skeleton.md`, `CHANGELOG.md`) were left
alone — they're dated records of what was true when written, not current
reference material. The rest of Gap 1 (`traffic`, `security`, `ai-bots`,
`image-resize`, `page-create`) stays as-is per the original recommendation —
the did-you-mean suggester already covers those adequately.

---

## Gap 2: `db-pull` ergonomics — done (`scripts/backup/db-pull.sh`, 2026-08-03)

The capability exists — `trellis/backup/database-pull.yml` pulls a remote database
into development with URL search-replace, and resolves as `wp-ops database-pull`.
What's awkward is the Ansible calling convention leaking into the CLI:

```bash
# today
wp-ops database-pull -e site=example.com -e env=production

# every other wp-ops command
wp-ops db-backup example.com production
```

`imagewize.com/scripts/pull-db.sh` exists precisely because of this, and adds
things the playbook lacks: streaming straight to local without a remote temp file,
multisite `wp_blogs` handling, and a confirmation prompt.

**Recommendation:** add `scripts/backup/db-pull.sh` as a positional-argument
wrapper, adapted from `pull-db.sh` and de-imagewize-d. Keep the playbook — it stays
the right tool inside a Trellis directory. This is the highest-value single script
in this document.

---

## Gap 3: the seo-strategy monitoring scripts are a stale fork

`scripts/monitoring/` already contains `traffic-monitor.sh`,
`security-monitor.sh`, `ai-bot-monitor.sh`, and `run-monitoring.sh` — all
manifest-annotated and runnable today. The earlier draft listed all four as
"missing, 3-5 days to add".

Diffed against `~/code/seo-strategy/tools/scripts/` on 2026-08-03, **wp-ops is
strictly ahead** in every case:

| Script | Difference |
|--------|-----------|
| `traffic-monitor.sh` | wp-ops adds the manifest header + a `gawk` install hint |
| `security-monitor.sh` | wp-ops adds the manifest header |
| `ai-bot-monitor.sh` | wp-ops adds the manifest header |
| `run-monitoring.sh` | wp-ops adds the manifest header, generalizes hardcoded `imagewize.com`/`aseonomics.com` to `$domain`, and additionally runs `error-monitor.sh` |

**Recommendation:** declare wp-ops canonical and delete the seo-strategy copies,
pointing its README at `wp-ops monitor`/`wp-ops traffic-monitor`. Leaving two
diverging copies is how the "missing tools" mistake happened in the first place.

---

## Gap 4: `url-audit`

Nothing implements the dev-URL cleanup that CLAUDE.md marks CRITICAL — searching
production for `.test`/`.localhost` URLs baked into `wp_posts.post_content` and
fixing them with `wp search-replace`. Today it exists only as prose in
`wp-cli/migration/URL-UPDATE-METHODS.md` and
`wp-cli/content-creation/PAGE-CREATION.md`, hand-reassembled each time.

This is already queued as item 11 in
[mcp-server-recommendations.md](mcp-server-recommendations.md#highest-leverage-new-tool)
and that remains the right primary home — it is exactly the error-prone multi-step
workflow an agent should get as one deterministic call.

**Recommendation:** build the MCP `url_audit` tool per that document. Add a
`scripts/content/url-audit.sh` counterpart only if you find yourself wanting it
outside an agent session — the read-only check is a one-line `wp db query` that the
docs already give you.

**Done, 2026-08-03.** `mcp-server/src/tools/urlAudit.ts` + a `url_audit` registration in
`mcp-server/src/server.ts`. Runs a `wp db query … LIKE '%pattern%'` count per pattern
(default `[".test", ".localhost"]`) against `wp_posts.post_content`; with `replace:
{from, to}` it always previews `wp search-replace --all-tables --precise --dry-run`
first and only applies for real when `confirm: true`. Built on `wpCli.ts`'s existing
SSH/VM/local dispatch — `runWpCliRaw` was factored out of `runWpCli` so the count query
result can be parsed as a number instead of scraped from the human-formatted string.
No standalone `scripts/content/url-audit.sh` — the MCP tool covers the agent-session
case this was written for, and the doc-given one-liner still covers the manual case.

---

## Gap 5: scripts worth upstreaming

Full basename comparison of both sibling repos against the wp-ops catalog. Only
site-agnostic candidates are listed; the rest are client- or content-specific
(`add-sme-categories.sh`, `aviendha-product-images.sh`, `merge-tags.sh`,
`deploy-alt-text-fix*.sh`, `create-trellis-hosting-page.sh`, and similar) and
should stay where they are.

| Script | From | Verdict |
|--------|------|---------|
| `pull-db.sh` | imagewize.com | **Take** — see Gap 2. Done. |
| `import-page-draft.sh` | seo-strategy | **Take** — updates an existing page from an HTML draft; complements `page-creation.sh`, which only creates. Done (`wp-cli/content-creation/import-page-draft.sh`, 2026-08-03) |
| `ttfb-test.sh`, `remote-ttfb-ua.sh` | seo-strategy | **Take** — `wordpress-utilities/speed-optimization/` documents TTFB measurement but ships no runnable script. Done (`scripts/monitoring/ttfb-test.sh`, `remote-ttfb-ua.sh`, 2026-08-03 — placed under `scripts/monitoring/`, not `wordpress-utilities/`: the CLI treats everything under `wordpress-utilities/` as a copy-paste snippet and never executes it) |
| `check-deny-ips.sh` | imagewize.com | **Take** — verifies `deny-ips.conf.j2` entries against AbuseIPDB; natural fit beside `trellis/security/`. Needs an API key, so gate on the key being set. Done (`trellis/security/check-deny-ips.sh`, 2026-08-03) |
| `bulk-add-alt-text.sh` | seo-strategy | **Consider** — genuinely reusable accessibility fix, but check how much is imagewize-specific first |
| `orphan-pages-audit-local.sh` | seo-strategy | **Consider** — useful SEO audit; wp-ops has `404-checker.sh` and `redirect-check.sh` but no internal-link audit |
| `svg-to-png.sh`, `svg-to-jpg.sh` | seo-strategy | **Consider** — small, fits `scripts/images/` cleanly |
| `traffic-by-country.sh` | seo-strategy | **Consider** — or fold into `traffic-monitor.sh`, which already has optional geolocation |
| `traffic-analysis.sh` | imagewize.com | **Skip** — superseded by `scripts/monitoring/traffic-monitor.sh` |
| `backup-db.sh` | imagewize.com | **Skip** — superseded by `scripts/backup/db-backup.sh` |
| `capture-pattern-screenshots*.sh`, `center-*`, `trim-*` | imagewize.com | **Skip** — superseded by `scripts/patterns/screenshot-patterns.sh` |
| `convert-images.sh` | imagewize.com | **Skip** — theme-specific; `scripts/images/jpg-to-webp.sh` covers it |
| `sync-min.sh` | imagewize.com | **Skip** — specific to the `min` package checkout; `bedrock/local-package-development/` documents the general pattern |
| `run-remote-audits.sh`, `init-client-repo.sh` | seo-strategy | **Skip** — workflow glue tied to the seo-strategy repo layout |

Anything taken needs a manifest header (`@desc`, `@category`, `@runs`, `@requires`,
`@arg`) — that is what makes it discoverable in both CLIs — and hardcoded hostnames
generalized to arguments, as was done for `run-monitoring.sh`.

---

## Gap 6: two more calling-convention sore spots, same shape as Gap 2

Gap 2 fixed one instance of "the underlying playbook works, but the calling
convention is what's awkward." Verified 2026-08-03: the same complaint applies
to nine more Ansible playbooks, and a related-but-distinct one applies to five
`scripts/*.sh` commands that have no wrapper of any kind yet.

### 6a. Ansible playbooks still needing `-e site=... -e env=...` — done, 2026-08-03

Every one of these took exactly the `site`/`env` pair `db-pull` used to
require, resolved from `docs/wp-ops-recommendations.md`'s own catalog
(`./wp-ops --json`, filtered to `.yml` scripts):

| Command | Extra args | Before |
|---------|-----------|-------|
| `trellis/backup/database-backup` | — | `wp-ops trellis/backup/database-backup -e site=example.com -e env=production` |
| `trellis/backup/database-push` | — | `wp-ops trellis/backup/database-push -e site=example.com -e env=staging` |
| `trellis/backup/files-backup` | — | `wp-ops trellis/backup/files-backup -e site=example.com -e env=production` |
| `trellis/backup/files-pull` | — | `wp-ops trellis/backup/files-pull -e site=example.com -e env=production` |
| `trellis/backup/files-push` | — | `wp-ops trellis/backup/files-push -e site=example.com -e env=staging` |
| `trellis/monitoring/quick-status` | `log_path` (optional) | `wp-ops trellis/monitoring/quick-status -e site=example.com -e env=production` |
| `trellis/monitoring/security-scan` | `hours`, `threshold` (optional) | `wp-ops trellis/monitoring/security-scan -e site=example.com -e env=production` |
| `trellis/monitoring/traffic-report` | `hours` (optional) | `wp-ops trellis/monitoring/traffic-report -e site=example.com -e env=production` |
| `trellis/monitoring/setup-monitoring` | `email` (optional) | `wp-ops trellis/monitoring/setup-monitoring -e site=example.com -e env=production` |

(`trellis/backup/database-pull` is the tenth — already fixed by `db-pull.sh`,
Gap 2.)

**Done, 2026-08-03 — a generic translator, not nine bespoke scripts.** These
nine playbooks work fine as-is; the only complaint was calling convention, so
rewriting each as its own `.sh` (à la `db-pull.sh`/`db-backup.sh`) would have
forked Ansible's logic into duplicate shell code for zero functional gain —
against `go-mcp-parity.md`'s "the scripts are the single source of truth"
decision. Instead, every `.yml` command's manifest already declares its
`@arg`/`@flag` names (Phase A rollout group 2), so the executor itself now
translates positional args against that declaration: required `@arg` entries
are consumed positionally in manifest order into `-e name=value`; anything
after that is read as `--name value` / `--name=value` against the declared
`@flag` names into more `-e name=value` pairs. `wp-ops database-backup
example.com production` and `wp-ops security-scan example.com production
--hours 48 --threshold 50` both now work. The legacy explicit form keeps
working unchanged — if the first raw arg already starts with `-` (i.e. `-e
key=value ...`), nothing is translated, so no existing invocation (docs,
muscle memory, other tooling) breaks.

Implemented once in each CLI at the time: `build_playbook_args()` in `wp-ops`
(bash — deleted 2026-08-04, v4.0.0, see [go-mcp-parity.md](go-mcp-parity.md)),
`BuildPlaybookArgs()` in `go/internal/exec/ansible.go` (Go, still current).
Both were called from the same place the raw args used to be passed straight
to `ansible-playbook`/`RunPlaybook`. Covered all nine playbooks (and any
future `.yml` command with manifest args) from one change per CLI, not nine. Note
the short command names above (`database-backup`, `security-scan`, ...)
already worked before this — bare-basename resolution has always resolved
them to their full catalog key (see "The verbose-path premise is false"); a
`@key`/`@alias` directive giving them a *second*, different registered name
was considered again while doing this work and rejected for the same reason
the original `@key` proposal was: it would duplicate catalog entries in
`list`/`--json` and risk `go/scripts/parity-check.sh` drift, for no gain over
the exact-match basename resolution that already exists.

### 6b. `scripts/*.sh` commands with no wrapper at all — manual SSH pipe every time

These are `runs_on: server` scripts with no Ansible playbook or positional
wrapper resolving site → host for them, so today's only path is hand-building
an SSH pipe (`wp-ops <name>` without `--help` prints the exact incantation,
but it still has to be copy-pasted per site/env each time):

| Command | Today |
|---------|-------|
| `scripts/backup/db-backup` | `ssh web@example.com 'bash -s' < scripts/backup/db-backup.sh example.com production` |
| `scripts/backup/site-backup` | `ssh web@example.com 'bash -s' < scripts/backup/site-backup.sh example.com` |
| `scripts/monitoring/ai-bot-monitor` | `ssh web@example.com 'bash -s' < scripts/monitoring/ai-bot-monitor.sh` |
| `scripts/monitoring/error-monitor` | `ssh web@example.com 'bash -s' < scripts/monitoring/error-monitor.sh example.com` |
| `scripts/monitoring/updown-webhook-handler` | `ssh web@example.com 'bash -s' < scripts/monitoring/updown-webhook-handler.sh example.com` |

(`traffic-monitor.sh`, `security-monitor.sh`, and `run-monitoring.sh` are the
same shape but are excluded here — they already have an Ansible-playbook
front end in 6a: `traffic-report`, `security-scan`, and `setup-monitoring`
respectively resolve site/env into the right log path and run these for you.)

### `db-backup` specifically has a second, sharper problem

Investigated 2026-08-03 while trying to back up `imagewize.com`:
`scripts/backup/db-backup.sh` writes to `/srv/backups/<site>/database`, but
`/srv` is `root:root 755` on a stock Trellis box — Trellis provisions and
`chown`s `/srv/www`, never `/srv` itself or `/srv/backups`. The `web` user the
script runs as can't `mkdir` there, so the script fails on every
Trellis server until someone with root creates `/srv/backups` by hand once.
This isn't specific to imagewize.com; it'll hit any site's first `db-backup`
run.

`trellis/backup/database-backup.yml` doesn't have this problem — it exports
into `{{ project_web_dir }}` (`/srv/www/<site>/current`, already
`web`-writable), fetches the file locally, then deletes the remote copy. That
sidestepping is the template to copy.

**Recommendation:** `db-backup` is the highest-value single item here —
it's the one Gap 2's own reasoning applies to most directly (a script that
already works is one calling-convention change from being genuinely
ergonomic), and it currently has both problems 6a and 6b's items have
separately: no positional wrapper *and* a broken default write path. Build
`scripts/backup/db-backup.sh` v2 the way `db-pull.sh` was built from
`pull-db.sh` — SSH straight into the remote site's own web dir like the
playbook does (never touching `/srv/backups`), fetch to local
`database_backup/`, delete the remote temp file, positional args
(`wp-ops db-backup example.com production`). Keep
`trellis/backup/database-backup.yml` for the same reason `database-pull.yml`
was kept: it's still the right tool for Ansible-native workflows.

**Done, 2026-08-03.** `scripts/backup/db-backup.sh` is now `@runs local`
(previously `server`) — positional args (`wp-ops db-backup example.com
production`), `--host`/`--dest` flags. Deviates from "fetch, then delete the
remote temp file" in favor of `db-pull.sh`'s own streaming pattern: `ssh ...
'wp db export -' | gzip > local-file`, so there is no remote temp file to
create or clean up in the first place — same approach the MCP `db_backup`
tool (`mcp-server/src/tools/dbBackup.ts`) already used. `wp-ops` and the Go
CLI both read `runs_on`/`requires` off the manifest already (bash's
`is_server_side_command()` checks `@runs` before its hardcoded command
lists), so flipping the header line was sufficient in both places once the
now-stale command lists were cleaned up and `catalog.json` regenerated.
`go/scripts/parity-check.sh` passes 8/8.

**Gap 6 extended: `wp-db-backup.sh` for non-Trellis sites** — the above
fix addressed the Trellis-shaped `db-backup`, but left a coverage hole:
no backup command worked for Valet, Herd, cPanel, or plain WordPress. Closed
2026-08-05 by `scripts/backup/wp-db-backup.sh` (Step 6 of
[category-organization.md](category-organization.md)):

- Layout detection: probes for `wp-load.php`, then `web/wp`, then `wordpress/`
- Site URL from `wp option get siteurl`, not `wordpress_sites.yml`
- No `/srv/www`, `/srv/backups`, or `web@` assumptions
- `--host` requires explicit `--site-path`; `--wp-bin`/`--php-bin` support
- `@platform wordpress` — the first backup command available to non-Trellis sites

The remaining 6a playbooks and 6b scripts are lower-value repeats of the same
fix — worth doing, but `db-pull.sh` and `db-backup.sh` between them now cover
the two highest-frequency operations for Trellis sites, and `wp-db-backup.sh`
covers the same operation for non-Trellis sites.

---

## Gap 7: dry-run coverage — mostly fine, two real gaps

Prompted by `url_audit`'s design (a `replace` always previews via `wp
search-replace --dry-run` first, and only applies for real with `confirm:
true`): audited every *mutating* command in the catalog — anything that
deletes, overwrites, search-replaces, pushes, provisions, or installs, not
the read-only list/status/monitoring/audit scripts — for whether it has a
literal `--dry-run` flag or an equivalent safety net. Verified 2026-08-03
against script/playbook source, not just manifest headers.

**Most already have one, just not always a literal flag:**

| Command | Mutates | Safety net |
|---------|---------|------------|
| `scripts/misc/find-and-replace-files.sh` | files repo-wide | `-n`/`--dry-run` |
| `scripts/sync/rsync-package-to-site.sh`, `rsync-theme.sh` | site/theme files | `--dry-run` |
| `scripts/images/batch-resize.sh` | image files | `-d`/`--dry-run` |
| `scripts/git/create-pr.sh` | GitHub PR | `--dry-run` + `read -p` prompts |
| `bedrock/wp-cli-config/wp-cli-pattern-validate.php` | pattern files | preview-by-default; `--fix` opts into writing |
| `scripts/patterns/center-screenshots.sh`, `trim-screenshots.sh` | images in place | auto-backs up originals to `originals/` first |
| `scripts/backup/db-pull.sh` | local dev DB | backs up dev DB first, confirms (`--yes` to skip) |
| `scripts/release/release-plugin.sh`, `release-theme.sh` | version bump, git commit | two confirmation prompts |
| `scripts/release/upload-release-asset.sh` | GitHub release asset | confirms before overwrite |
| `scripts/release/deploy-plugin-wporg.sh` | WP.org SVN (irreversible) | stages to local SVN checkout, prints `svn status`, only `svn ci`s with `--commit` |
| `trellis/backup/database-push.yml` | remote DB (overwrite) | auto-exports/pulls a remote backup first |
| `trellis/backup/database-pull.yml` | local dev DB (overwrite) | auto-backs up dev DB first |
| `trellis/backup/files-push.yml` | remote uploads | Ansible `pause` confirmation prompt |
| `trellis/backup/files-pull.yml` | local uploads | non-destructive (`delete: no`) |
| `wp-cli/content-creation/import-page-draft.sh`, `page-creation.sh` | live page content | `read -p "Type 'yes' to continue"` |
| `mcp-server` `wp_cli` tool | arbitrary WP-CLI | `confirm: true` gate on everything outside the read-only verb allowlist |
| `mcp-server` `url_audit` tool | search-replace | dry-run preview always runs first; `confirm: true` to apply |

**Two real gaps — no dry-run and no confirmation/backup net:**

- **`scripts/woocommerce/create-product-variations.sh`** — bulk-creates
  WooCommerce product variations directly via WP-CLI over the Trellis VM.
  No preview, no confirmation prompt, no backup, no undo path. Highest
  priority of the two: it's a live commerce catalog.
- **`trellis/updater/trellis-updater.sh`** — backs up the whole Trellis
  directory before starting (`cp -r … $BACKUP_DIR`), so a rollback path
  exists, but nothing previews the changes and nothing asks for
  confirmation before it starts rewriting files. Lower priority — the
  backup makes this recoverable, just not previewable.

**Recommendation:** add a `--dry-run` flag (print planned WP-CLI calls,
skip execution) to `create-product-variations.sh` — it's the one script
here with no safety net of any kind. Add a `read -p` confirmation prompt
to `trellis-updater.sh` before it starts writing, matching the pattern
`db-pull.sh` and the release scripts already use; skip a literal dry-run
there since the existing backup already covers "how do I undo this."
Everything else in the catalog is adequately covered and doesn't need
follow-up.

**Done, 2026-08-03.** `scripts/woocommerce/create-product-variations.sh`
takes `-d`/`--dry-run` (matching `batch-resize.sh`'s convention): builds
each `wp wc product_variation create` invocation into an array either way,
but only prints it (`[DRY RUN] ...`) instead of running it over `trellis vm
shell` when the flag is set, so the full attribute cross-product can be
previewed with no VM round trip. `trellis/updater/trellis-updater.sh` now
prompts `This will overwrite files in $TRELLIS_DIR. Continue? (y/N)` before
Step 1 (the backup, which still runs unconditionally once confirmed) — a
`-y`/`--yes` flag (matching `db-pull.sh`'s convention) skips it for
non-interactive use. Both scripts' manifest headers gained a `@flag` line
so the new flag surfaces in `--help` and the interactive picker.

---

## Suggested order

All eight numbered items below are now **Done** as of 2026-08-22. This section
is kept as a historical record of the original prioritization.

1. **Gap 3** — delete the stale seo-strategy monitoring fork. Costs nothing, stops
   the divergence that produced the false "missing tools" list.
2. **Gap 2** — `scripts/backup/db-pull.sh`. Highest daily value. **Done** (2026-08-03).
3. **Gap 5 "Take" rows** — four scripts, mechanical work. **Done** (2026-08-03).
4. **Gap 6, `db-backup`** — positional wrapper + fixes the `/srv/backups`
   permission dead end. Same shape and value as Gap 2. **Done** (2026-08-03).
5. **Gap 4** — `url_audit` MCP tool, per the MCP roadmap. **Done** (2026-08-03).
6. **Gap 1** — rename `run-monitoring.sh`, or consciously decide not to. **Done** (2026-08-03).
7. **Gap 6, remaining items** — 6a (the nine `-e`-style playbooks) **Done** (2026-08-03),
   via a generic positional-arg translator rather than nine bespoke scripts.
   6b (four unwrapped server scripts) **Done** (2026-08-03) — same translator
   handles `@runs server` scripts that declare `@arg` names.
8. **Gap 7** — `--dry-run` for `create-product-variations.sh`; a confirmation
   prompt for `trellis-updater.sh`. Small, isolated fixes. **Done** (2026-08-03).

Deliberately not queued: `@key` or any new manifest directive (premise false, and
per [go-mcp-parity.md](go-mcp-parity.md) any new directive must land in both
parsers at once); `db-replace` (a wrapper around `db-backup` + `db-pull` that is
only worth writing once `db-pull` exists and proves it needs one).

---

## Current status: 2026-08-25

**All gaps named in this document are now closed.** The eight-item suggested
order above shipped between 2026-08-03 and 2026-08-05, plus three additional
milestones landed since the original draft:

- `@platform` tagging on all 75 commands (trellis: 27, wordpress: 18, any: 30)
- `wp-db-backup.sh` — first `@platform wordpress` backup command
- `trellis-ops` plugin shim via Homebrew
- `imagewize/wp-cli-pattern-validate` v1.0.0 on GitHub
- `imagewize.trellis_wp_monitoring` v1.0.0 on Ansible Galaxy

**What remains open elsewhere:**

- **Path B from [trellis-extensions-evaluation.md](trellis-extensions-evaluation.md)**
  — shipped. The monitoring role at
  [imagewize/trellis-wp-monitoring](https://github.com/imagewize/trellis-wp-monitoring)
  is published on
  [Ansible Galaxy](https://galaxy.ansible.com/ui/standalone/roles/imagewize/trellis_wp_monitoring/)
  as `imagewize.trellis_wp_monitoring` v1.0.0, imported 2026-08-25 once the
  `imagewize` namespace request cleared. The novel niche (Nginx log analysis)
  now has a published Trellis extension where none existed before.
- **[third-party-extensions.md](third-party-extensions.md)** — the extension
  mechanism design itself is still a proposal with no implementation.
- **Optional follow-ups:** listing `imagewize/wp-cli-pattern-validate` on the
  WP-CLI package index; measuring installs.

This document is now primarily historical. For the current roadmap, see:
[category-organization.md](category-organization.md),
[trellis-extensions-evaluation.md](trellis-extensions-evaluation.md),
[wp-cli-package-evaluation.md](wp-cli-package-evaluation.md).

---

## See Also

- [mcp-server-recommendations.md](mcp-server-recommendations.md) — MCP roadmap, `url_audit`, tool design principles
- [go-mcp-parity.md](go-mcp-parity.md) — ADR on the three interfaces
- [cli-ux-plan.md](cli-ux-plan.md) — CLI architecture and command resolution grammar
