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
| `pull-db.sh` | imagewize.com | **Take** — see Gap 2 |
| `import-page-draft.sh` | seo-strategy | **Take** — updates an existing page from an HTML draft; complements `page-creation.sh`, which only creates |
| `ttfb-test.sh`, `remote-ttfb-ua.sh` | seo-strategy | **Take** — `wordpress-utilities/speed-optimization/` documents TTFB measurement but ships no runnable script |
| `check-deny-ips.sh` | imagewize.com | **Take** — verifies `deny-ips.conf.j2` entries against AbuseIPDB; natural fit beside `trellis/security/`. Needs an API key, so gate on the key being set |
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

## Suggested order

1. **Gap 3** — delete the stale seo-strategy monitoring fork. Costs nothing, stops
   the divergence that produced the false "missing tools" list.
2. **Gap 2** — `scripts/backup/db-pull.sh`. Highest daily value. **Done.**
3. **Gap 5 "Take" rows** — four scripts, mechanical work.
4. **Gap 4** — `url_audit` MCP tool, per the MCP roadmap.
5. **Gap 1** — rename `run-monitoring.sh`, or consciously decide not to.

Deliberately not queued: `@key` or any new manifest directive (premise false, and
per [go-mcp-parity.md](go-mcp-parity.md) any new directive must land in both
parsers at once); `db-replace` (a wrapper around `db-backup` + `db-pull` that is
only worth writing once `db-pull` exists and proves it needs one).

---

## See Also

- [mcp-server-recommendations.md](mcp-server-recommendations.md) — MCP roadmap, `url_audit`, tool design principles
- [go-mcp-parity.md](go-mcp-parity.md) — ADR on the three interfaces
- [cli-ux-plan.md](cli-ux-plan.md) — CLI architecture and command resolution grammar
