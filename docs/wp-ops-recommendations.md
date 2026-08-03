# WP-Ops Recommendations: Real Gaps

> **Status:** Draft — 2026-08-03
> **Scope:** What is actually missing from wp-ops, based on comparing its catalog
> against `~/code/imagewize.com/scripts` and `~/code/seo-strategy/tools/scripts`.
> **Related:** [mcp-server-recommendations.md](mcp-server-recommendations.md) (MCP roadmap),
> [go-mcp-parity.md](go-mcp-parity.md) (why there are three interfaces)

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

Bare-basename resolution across the whole catalog already exists in both CLIs —
bash `wp-ops:2262-2281`, Go `go/cmd/root.go:95-104` — with ambiguity detection and
did-you-mean suggestions. Every script the earlier draft proposed annotating
(`db-backup`, `site-backup`, `batch-resize`, `convert-to-webp`,
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
| `wp-ops monitor` | fails | `scripts/monitoring/run-monitoring.sh` |
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
| `convert-images.sh` | imagewize.com | **Skip** — theme-specific; `scripts/images/convert-to-webp.sh` covers it |
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

### 6a. Ansible playbooks still needing `-e site=... -e env=...`

Every one of these takes exactly the `site`/`env` pair `db-pull` used to
require, resolved from `docs/wp-ops-recommendations.md`'s own catalog
(`./wp-ops --json`, filtered to `.yml` scripts):

| Command | Extra args | Today |
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
now-stale command lists (`BACKUP_COMMANDS`/`SERVER_SIDE_COMMANDS` in
`wp-ops`, `backupCommands` in `go/cmd/serverside.go`,
`serverSideFallback` in `go/internal/catalog/gen/main.go`) were cleaned up
and `catalog.json` regenerated. `go/scripts/parity-check.sh` passes 8/8.

The remaining 6a playbooks and 6b scripts are lower-value repeats of the same
fix — worth doing, but `db-pull.sh` and (once built) `db-backup.sh` between
them cover the two highest-frequency operations already.

---

## Suggested order

1. **Gap 3** — delete the stale seo-strategy monitoring fork. Costs nothing, stops
   the divergence that produced the false "missing tools" list.
2. **Gap 2** — `scripts/backup/db-pull.sh`. Highest daily value. **Done.**
3. **Gap 5 "Take" rows** — four scripts, mechanical work. **Done (2026-08-03).**
4. **Gap 6, `db-backup`** — positional wrapper + fixes the `/srv/backups`
   permission dead end. Same shape and value as Gap 2. **Done.**
5. **Gap 4** — `url_audit` MCP tool, per the MCP roadmap.
6. **Gap 1** — rename `run-monitoring.sh`, or consciously decide not to.
7. **Gap 6, remaining items** — the other eight `-e`-style playbooks and four
   unwrapped server scripts. Same mechanical pattern as `db-backup`; lower
   priority since they're used less often.

Deliberately not queued: `@key` or any new manifest directive (premise false, and
per [go-mcp-parity.md](go-mcp-parity.md) any new directive must land in both
parsers at once); `db-replace` (a wrapper around `db-backup` + `db-pull` that is
only worth writing once `db-pull` exists and proves it needs one).

---

## See Also

- [mcp-server-recommendations.md](mcp-server-recommendations.md) — MCP roadmap, `url_audit`, tool design principles
- [go-mcp-parity.md](go-mcp-parity.md) — ADR on the three interfaces
- [cli-ux-plan.md](cli-ux-plan.md) — CLI architecture and command resolution grammar
