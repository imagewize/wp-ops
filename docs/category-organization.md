# Category Organization: directories, display categories, and what `wp-ops` shows

> **Status:** **Fully implemented** 2026-08-05 — Options C and D, plus the
> `wp-db-backup.sh` gap (step 6) and the `wordpress-utilities/` question
> (step 7). See [What shipped](#what-shipped) at the foot of this document
> for the decisions the analysis left open, how they were settled, and what
> it got wrong.
> **Problem:** The repo's top-level directories try to encode three different
> axes at once — *mechanism* (bash/Ansible/PHP), *platform* (Trellis-only vs
> host-agnostic), and *domain* (backup/monitoring/security) — and a directory
> can only encode one. The result reads as arbitrary from `wp-ops list`.
> **Conclusion:** The fix is *not* a directory reorganization — it's metadata.
> Group by domain and filter by platform, both in the manifest: the catalog
> already separates `Category` (directory) from `DisplayCategory` (what humans
> see), so extending that gives domain grouping with zero file moves, and
> platform belongs in a per-command tag rather than a path. One change, two
> halves — see Option C.
> **Related:** [cli-ux-plan.md](cli-ux-plan.md) (where `DisplayCategory`
> came from), [wp-ops-recommendations.md](wp-ops-recommendations.md)
>
> This document supersedes `backup-organization.md`, which analyzed the
> `scripts/backup/` vs `trellis/backup/` split in isolation and concluded
> "leave it, fix the descriptions." That conclusion is retired: the split is
> one instance of a repo-wide pattern, and a per-command `@platform` tag makes
> the directory-level description fix redundant. Its still-live findings — the
> design constraints for a host-agnostic backup set, and the basename-collision
> caveat — are absorbed below.

---

## The current state, measured

76 commands across 6 command-bearing top-level directories (plus three
doc-only trees):

| Directory | Commands | File types | Trellis-coupled | Docs (`.md`) |
| --- | ---: | --- | ---: | ---: |
| `scripts/` | 41 | 36 `.sh`, 3 `.js`, 2 `.py` | 16 | 4 |
| `trellis/` | 13 | 10 `.yml`, 3 `.sh` | 13 | 13 |
| `wp-cli/` | 13 | 9 `.sh`, 4 `.php` | 4 | 13 |
| `wordpress-utilities/` | 5 | 3 `.php`, 1 `.js`, 1 `.css` | 0 | 10 |
| `mcp-server/` | 3 | 3 `.sh` | 0 | — |
| `bedrock/` | 1 | 1 `.php` | 0 | 3 |
| `nginx/` | **0** | — | — | 5 |
| `troubleshooting/` | **0** | — | — | 6 |
| `docs/` | **0** | — | — | 7 |

("Trellis-coupled" = the file references `/srv/www`, `/srv/backups`, `web@`,
`TRELLIS_DIR`, `wordpress_sites`, or the `trellis` CLI. 33 of 76 commands,
43%.)

### The three axes, and where each one leaks

**Axis 1 — mechanism.** `trellis/` is *mostly* Ansible but holds 3 shell
scripts ([`trellis/security/check-ips.sh`](../trellis/security/check-ips.sh),
`check-deny-ips.sh`, [`trellis/updater/trellis-updater.sh`](../trellis/updater/trellis-updater.sh)).
`scripts/` is *mostly* bash but holds 3 Node and 2 Python commands. `wp-cli/`
is a 9/4 split of shell and PHP. No directory is mechanism-pure.

**Axis 2 — platform.** `scripts/` is 39% Trellis-coupled; `wp-cli/` is 31%.
Neither name says so. All three scripts in `scripts/backup/` hard-code Trellis
conventions — `web@host` and `/srv/www/<site>/current` in
[`db-backup.sh`](../scripts/backup/db-backup.sh), `TRELLIS_DIR` +
`trellis vm shell` in [`db-pull.sh`](../scripts/backup/db-pull.sh),
`/srv/backups` and the Bedrock `web/app/` layout in
[`site-backup.sh`](../scripts/backup/site-backup.sh) — while the directory
name says only "standalone shell scripts." That is the defect that started
this analysis.

**Axis 3 — domain.** This is what people actually search by, and it's the axis
most badly served — three domains are each split across two top-level
directories:

| Domain (`@category`) | Total | Split across |
| --- | ---: | --- |
| `monitoring` | 17 | `scripts/monitoring/` (13) + `trellis/monitoring/` (4) |
| `backup` | 9 | `scripts/backup/` (3) + `trellis/backup/` (6) |
| `security` | 5 | `wp-cli/security/` (3) + `trellis/security/` (2) |

31 of 76 commands (41%) live in a domain that no single directory contains.
That is the real cost of the current layout — not the naming.

### The CLI already half-solves this

`gen/main.go`'s `promotedScriptCategories`
([`gen/main.go:74-79`](../go/internal/catalog/gen/main.go#L74-L79)) promotes
`scripts/**` subcategories with 4+ commands — `monitoring`, `images`,
`patterns`, `release` — to their own top-level display group, so `wp-ops list`
already shows ten groups rather than six. The machinery for "display grouping
≠ directory" exists and ships. It is simply applied to one directory only, and
`Monitoring` in that list means *`scripts/monitoring` only* — the four
`trellis/monitoring` playbooks stay filed under `Trellis`. The half-measure is
arguably more confusing than no measure.

---

## Option A — rename by mechanism (`trellis/`→`ansible/`, `scripts/`→`shell/`)

**Verdict: rejected.** It is false on its own terms and fixes nothing.

- `ansible/` would contain 3 shell scripts; `shell/` would contain 5 Node and
  Python commands. The names would be wrong on day one for 8 commands.
- It doesn't touch the domain split. `ansible/backup/` + `shell/backup/` is
  the identical problem with new spelling — you'd still hunt in two places for
  a backup command.
- `wp-cli/` and `wordpress-utilities/` have no mechanism identity at all
  (mixed `.sh`/`.php`/`.js`/`.css`), so the scheme can't be applied
  consistently even in principle.
- Cost: every catalog key changes, plus 69 references across `go/` and
  `mcp-server/`, plus **23 manifest `@doc` paths** pointing into `trellis/`
  and 7 into `scripts/`.

The instinct behind it is right — the names *are* misleading — but mechanism
is the least useful of the three axes to encode, because it's the one you
never search by.

## Option B — reorganize by domain (`backup/`, `monitoring/`, `security/`…)

**Verdict: correct axis, wrong lever.** This is what users actually want, but
paying for it in directory moves is the expensive way to buy it.

- Every one of the 76 catalog keys changes. Every `@doc` path. Every doc
  cross-link. `README.md`, `CLAUDE.md`, `serverSideFallback`, and literal keys
  in five test files.
- It destroys information that currently matters at the point of use: inside
  `backup/`, you could no longer tell at a glance that `database-backup.yml`
  needs a Trellis project + vault while `db-backup.sh` needs only SSH. You'd
  reintroduce that distinction as a filename prefix or a nested directory —
  i.e. re-encode mechanism, one level down.
- The doc trees (`trellis/backup/README.md`, 612 lines) don't decompose by
  domain as cleanly as the commands do.

Take the outcome, skip the moves — see Option C.

## Option C — group by domain, filter by platform ✅

**Verdict: recommended. The highest-value change, and it moves no files.**

Two halves of one idea, so treat them as one change rather than two options:
domain answers *what kind of thing is this* and becomes the grouping;
platform answers *will it run against my site* and becomes a filter. Either
half alone is incomplete — grouping all 9 backup commands together (C1) is
only useful if you can also tell which of them work on the site in front of
you (C2), and the platform tag is hard to read if the commands it labels are
still scattered across `scripts/` and `trellis/`. Both are pure metadata: no
file moves, no key changes.

### C1 — derive display categories from `@category` everywhere

`Entry.Category` (directory) and `Entry.DisplayCategory` (human-facing
grouping) are already distinct fields, deliberately so —
[`catalog.go:62-73`](../go/internal/catalog/catalog.go#L62-L73) notes the
split exists precisely to keep `--json`'s directory-based `category` a stable
contract while the human surfaces group differently. Today
`displayCategoryFor()` applies the manifest category only for promoted
`scripts/**` subcategories. Drop that restriction and `DisplayCategory`
becomes `@category` for all commands.

`wp-ops list` would then show, by domain:

```
Monitoring (17)   Log monitoring, uptime checks, traffic analysis
Backup (9)        Database and file backups — Ansible and shell
Images (7)        Resizing, WebP/AVIF conversion, Openverse downloads
SEO (6)           Redirect audits, sitemap and schema checks
Patterns (5)      Block pattern screenshots and conversion
Security (5)      Malware scanning, fail2ban, IP blocking
Release (4)       Plugin/theme release automation
Git (3) · Misc (3) · Sync (2) · …
```

`wp-ops backup --help` would list all 9 backup commands — playbooks and shell
scripts side by side — which is the grouping the two-directory split currently
prevents. (It also makes the `promotedScriptCategories` threshold moot for
`scripts/backup/`, which sits at 3 commands and would otherwise need a manual
promotion entry the moment a fourth is added.)

**What it costs:** `displayCategoryFor()` in
[`gen/main.go:82-89`](../go/internal/catalog/gen/main.go#L82-L89), the three
tables in [`catalog.go:224-272`](../go/internal/catalog/catalog.go#L224-L272)
(`DisplayOrder`, `CategoryDisplayNames`, `CategoryBlurbs`), a catalog
regeneration, and the display-category assertions in the catalog tests.
**What it doesn't cost:** no file moves, no key changes, no `@doc` churn, no
`--json` contract change.

**Two things to decide when doing it:**

1. **Singletons.** `woocommerce` (1), `updater` (1), `wp-cli-config` (1),
   `snippets` (2), `sync` (2), `content-creation` (2), `diagnostics` (2) would
   each become a one- or two-command group. Either keep the 4+ promotion
   threshold and fold the rest into a `Misc`/`Other` group, or merge them into
   neighbours (`diagnostics` → `Troubleshooting`, `content-creation` +
   `patterns` → `Content`).
2. **`@category` values need one normalization pass.** Some are domains
   (`backup`, `seo`), some are directory echoes (`wp-cli-config`,
   `age-verification`, `updater`). Domain-based grouping is only as good as
   the tags, so this is the actual work — roughly 76 one-line manifest edits
   at most, and most are already right. Do it in the same sweep as C2's
   `@platform` annotations; both touch every command file.

### C2 — add a `@platform` tag

Cheap, and it's the axis that actually bit you. Add one manifest directive and
the question no directory name can answer becomes answerable:

```bash
wp-ops list --platform wordpress    # what works on my Valet / cPanel site
wp-ops search backup                # shows a [trellis] badge per result
```

#### Three values, not two

An earlier draft proposed `trellis | agnostic | any`. Two buckets aren't
enough: `scripts/images/batch-resize.sh` needs no WordPress at all, while
`wp-cli/security/scanner-targeted.php` needs *a* WordPress but no Trellis.
Calling both "agnostic" answers the wrong question for someone pointing the
CLI at a specific site.

| Value | Means | Examples |
| --- | --- | --- |
| `trellis` | Needs a Trellis project, vault, `/srv/www`, or the `trellis` CLI | all of `trellis/`, `scripts/backup/*`, most of `scripts/monitoring/` |
| `wordpress` | Any WP install — Valet, Herd, cPanel, Bedrock, Trellis | `wp-cli/security/scanner-*`, `wp-cli/seo/*`, `wp-cli/diagnostics/*` |
| `any` | No WordPress involved | `scripts/images/*`, `scripts/git/*`, `scripts/sync/*`, `scripts/release/*` |

`wp-ops list --platform wordpress` then reads as "what can I run against this
site," which is the actual user question.

**Note this is *not* derivable from the existing `@requires`.** That directive
names binaries (`ssh` 7, `wp` 7, `trellis` 4, `ansible-playbook` 11, `magick`
6, …), and the mapping breaks in both directions:
`scripts/backup/db-backup.sh` declares only `@requires ssh` yet is thoroughly
Trellis-shaped, while `@requires wp` says nothing about whether the target must
be Trellis. `@platform` has to be its own field. It's also distinct from
`@runs local|server`, which says where a command *executes*, not what stack it
needs.

This retires the naming problem outright. `scripts/backup/db-backup.sh` stays
where it is and is honestly labelled `[trellis]`; a future `wp-db-backup.sh`
sits beside it labelled `[wordpress]`. It also gives the MCP layer's
already-host-agnostic model
([`mcp-server/src/registry.ts:12-44`](../mcp-server/src/registry.ts#L12-L44) —
four env shapes: `trellisDir`+`vmWorkdir`, `sshHost`+`remotePath`, `localPath`,
or `url`, plus `wpBin`/`phpBin` overrides for cPanel/Plesk) a CLI-side
counterpart.

Cost: manifest spec + parser, one field in `Entry`, one filter flag on `list`
and `search`, one badge in the picker, and 76 one-line annotations (the
regex used for the table above gets ~90% of them right as a first pass).

#### What the tag exposes but doesn't fix

Tagging makes a real coverage hole visible rather than closing it. Concrete
case: a plain (non-Bedrock) WordPress install served by Laravel Valet, e.g.
`~/code/robdisbergen` — `wp-config.php` and `wp-cli.yml` at the project root.
None of the nine backup commands run against it:

| Command | Why it fails on a Valet site |
| --- | --- |
| `scripts/backup/db-backup.sh` | SSHes to a remote host; assumes `/srv/www/<site>/current` |
| `scripts/backup/db-pull.sh` | `@requires trellis`; refuses to run outside a Trellis project |
| `scripts/backup/site-backup.sh` | `@runs server`; reads `/srv/www`, writes `/srv/backups` |
| `trellis/backup/*.yml` (6) | Need `group_vars/*/wordpress_sites.yml` and a vault |

Today `wp-ops backup --help` will happily list all nine and you discover the
mismatch by running one. With `@platform`, `--platform wordpress` returns zero
backup commands — the hole is stated instead of stumbled into. Closing it needs
one small script, tagged `wordpress`:

| Candidate | Purpose |
| --- | --- |
| `wp-db-backup.sh` | `wp db export \| gzip` against a `--path`; works for Valet/Herd, plain `public_html`, or any SSH host |
| `wp-site-backup.sh` | DB + `wp-content` (or Bedrock `web/app`) + config |
| `wp-db-pull.sh` | Remote → local with `search-replace`, plain `wp` locally — no `trellis vm shell` |

Design constraints, each of which the current three scripts violate:

- No `/srv/www`, `/srv/backups`, or `web@` assumptions — take a path and an
  optional SSH target.
- Detect layout rather than assume it; `site-backup.sh` hard-codes Bedrock's
  `web/app/`, and the Valet case above is classic `wp-content/`.
- Allow a custom `wp`/`php` binary the way the MCP registry does, for
  cPanel/Plesk hosts where PHP is at `/opt/plesk/php/8.2/bin/php`.
- Read the site URL via `wp option get siteurl`, not from Trellis config.

**Naming caveat:** basename collisions break the short form. If a generic
script were also called `db-backup.sh`, `wp-ops db-backup` becomes ambiguous
and errors with a did-you-mean list instead of running. Keep the agnostic set
on distinct names (`wp-db-backup`, `wp-site-backup`, …).

#### Corollary: the CLI stays `wp-ops`, not `trellis-ops`

Worth recording, since domain-based grouping invites the question. Of the 76
commands, **33 are Trellis-coupled and 43 are not** — whole categories carry no
Trellis dependency at all: every `scripts/images/` command, all of
`wp-cli/seo/`, all four release scripts, all three security scanners,
`scripts/git/`, `scripts/sync/`. Trellis is the largest single platform but a
minority of the catalog, and it's the *host-agnostic* half that serves every
site. `trellis-ops` would misname 57% of the repo and write off the half that
covers cases like the Valet site above.

## Option D — move the doc-only trees under `docs/`

**Verdict: worth doing, low stakes.** `nginx/` (0 commands, 5 docs) and
`troubleshooting/` (0 commands, 6 docs) are pure documentation sitting at top
level next to command directories, and both appear in `Categories`/
`DisplayOrder` ([`catalog.go:205-237`](../go/internal/catalog/catalog.go#L205-L237))
where they're always skipped for having zero commands — dead entries in the
curated order.

`wp-ops docs` walks every `.md` in the repo
([`docs.go:191-206`](../go/cmd/docs.go#L191-L206)), so moving them costs
nothing there. Only inbound `.md` cross-links (23 files reference `nginx/` or
`troubleshooting/`) and the dead `Categories` entries need touching.

`bedrock/` is a genuine edge case: 1 command, 3 docs. Its one command
(`wp imagewize pattern-validate`) is arguably a `wp-cli/` command, after which the whole
tree is documentation too. **Your instinct that `bedrock` belongs under docs
is right** — it's the one directory where the reorganization is unambiguous.

`wordpress-utilities/` (5 commands, 10 docs) is mostly copy-paste-into-your-
project material rather than runnable commands; the `.css` and `.php` "commands"
are components, not executables. Worth a separate look at whether they should
be commands at all.

---

## Recommendation

Do **C** (both halves), then **D**. Skip A and B.

The framing that resolves this: **directories should encode the least
volatile axis and the CLI should encode the most useful ones.** Mechanism is
stable (a playbook stays a playbook) so it can stay in the paths, imperfectly,
where it costs nothing. Domain is what people search by, so it belongs in
`DisplayCategory` where it's free to change. Platform is a property of each
command, not a location, so it belongs in a tag. C1 and C2 are the same move
applied to the two axes a path can't hold, which is why they ship together.

Once C lands, "should this file live in `scripts/` or `trellis/`?" stops
being a question anyone has to get right — the path becomes an implementation
detail, and `wp-ops list`, `wp-ops search`, and the picker all group and
filter on the axes that matter.

## Suggested sequencing

C is one change, but it's three commits — the metadata pass is a prerequisite
for the code that reads it, and splitting keeps each diff reviewable.

1. **Land this document** (no code change).
2. **Metadata pass (C, commit 1)** — audit all 76 `@category` values against a
   settled domain vocabulary, and annotate all 76 with `@platform` in the same
   sweep. Both are one-line manifest edits per file, both touch every command
   file, and doing them together means reading each file once. Pure manifest
   edits, no behaviour change until step 3.
3. **Grouping (C, commit 2)** — `displayCategoryFor()` drops the
   `scripts`-only condition; update
   `DisplayOrder`/`CategoryDisplayNames`/`CategoryBlurbs`; decide the singleton
   policy; regenerate the catalog; fix the display-category assertions.
4. **Filtering (C, commit 3)** — `@platform` parser, `Entry.Platform`,
   `--platform` filter on `list`/`search`, badge in the picker. This retires
   the directory-description fix the old `backup-organization.md` proposed:
   once every command carries its own platform tag, correcting `CLAUDE.md`'s
   description of `scripts/backup/` is redundant.
5. **Option D** — move `nginx/`, `troubleshooting/`, and `bedrock/`'s docs
   under `docs/`; relocate `bedrock/`'s one command to `wp-cli/`; drop the
   dead `Categories` entries. Lowest risk, do it whenever.
6. **Write `wp-db-backup.sh`** — the first `@platform wordpress` backup
   command, driven by a real host (the Valet site above), not speculatively.
   Port the host-detection logic from `mcp-server/src/registry.ts` rather than
   reinventing it.
7. **Revisit `wordpress-utilities/`** separately — the question there is
   whether its entries are commands at all, which is a different problem from
   this one.

---

## What shipped

All of steps 2-7 landed on 2026-08-05.

**The two open decisions, settled.**

*Singletons* (§C1, decision 1) — merged into neighbours rather than folded into
a catch-all `Misc`. The 4+ threshold was rejected because it would have swept
20 commands across ten unrelated domains into one bucket, which is less
navigable than the split it replaces. The merges: `patterns` +
`content-creation` + `wp-cli-config` → **`content`**; `age-verification` →
**`snippets`**; `woocommerce` + `updater` → **`misc`**. Thirteen `@category`
values changed; 76 gained `@platform`. Result is 13 groups, none below 2
commands.

*`@category` normalization* (§C1, decision 2) — the directory-echo tags the
analysis flagged (`wp-cli-config`, `age-verification`, `updater`) are exactly
the ones the merges absorbed, so normalization and de-singleton-ing turned out
to be the same edit rather than two.

**One thing the analysis missed.** Dropping the directory names from
`DisplayOrder` also deletes the per-category Cobra commands built from it —
`wp-ops trellis <playbook>`, `wp-ops wp-cli <script>`, `wp-ops bedrock
<script>`, all documented in `README.md`. They now survive as **hidden
back-compat aliases** registered from `Categories` (directory grouping) rather
than `DisplayOrder` (domain grouping), so `--help` presents one grouping while
the old forms keep resolving. `wp-ops patterns` is the single casualty: it was
a real display category in 4.2.1 and is now `wp-ops content`.

**The Valet coverage hole was visible first, then closed.** Tagging alone made
`wp-ops list --platform wordpress` return zero backup commands — §C2's worked
example holding for real rather than by accident of missing tags. Step 6 then
wrote the command that fills it; see below.

### Option D

`nginx/` → `docs/nginx/`, `troubleshooting/` → `docs/troubleshooting/`,
`bedrock/` → `docs/bedrock/`, and `bedrock/`'s one command to
`wp-cli/content-creation/` (joining `page-creation` and `import-page-draft`
under the same `content` domain). All three names are gone from `Categories`,
so the curated order no longer carries entries that are skipped on every pass.

Two wrinkles the analysis didn't cover, both minor:

- **`nginx/` is not purely documentation.** It carries four `.conf.j2`
  templates that get copied into a Trellis `nginx-includes/` directory — the
  "0 commands, 5 docs" count only measured `.md`. They moved with their
  guides rather than being split off: `browser-caching/README.md` and
  `assets-expiry.conf.j2` are one unit, and separating them to keep `docs/`
  pure `.md` would cost more than the impurity does. Same for
  `bedrock/wp-cli-config/wp-cli.yml`.
- **`assets.go` and the CI path filters** both enumerate these directories.
  The `go-build.yml` filters gained `docs/**` in place of the three removed
  entries, which also closes a pre-existing gap: `docs/` has always been
  embedded in the binary but never triggered a build.

`wp-ops docs` was unaffected, as predicted — it walks every `.md` in the repo
rather than a category list.

### Step 6 — `wp-db-backup.sh`

Written against the Valet site this document names, per its own instruction
not to write it speculatively. That paid for itself immediately: **the first
working version produced a corrupt backup**, and no amount of desk-checking
would have found it.

WP-CLI on that host emits a PHP deprecation notice **on stdout**. Piped
through `wp db export - | gzip`, the notice becomes the first line of the
dump. The file is a valid gzip, it is the right size, and it still ends with
`Dump completed` — every check the Trellis-shaped `db-backup.sh` would have
applied passes, and the backup fails only when you try to import it, which is
the worst possible moment to find out.

Three things came out of that, all of which the design constraints missed:

1. **WP-CLI must be run from the site directory**, not merely pointed at it
   with `--path`. It discovers `wp-cli.yml` by walking up from the working
   directory, so running from elsewhere silently drops the site's own config —
   on this site, a `require` that suppresses exactly those deprecations.
2. **A trailing `Dump completed` marker proves nothing.** The dump is checked
   at both ends now, and the *first* line is the one that matters: anything
   written to stdout lands ahead of the SQL. A dump that doesn't start with
   `--` or `/*` is deleted rather than kept.
3. **`--php-bin` is not only for cPanel.** WP-CLI's shebang wrapper offers no
   way to pass `-d`, so invoking PHP directly is the only way to force
   `display_errors=stderr` on a noisy host. The script adds that flag whenever
   `--php-bin` is set, and the rejection message tells you to use it.

The four design constraints held up otherwise. Layout detection probes for
`wp-load.php` at the given path, then `web/wp`, then `wordpress/`, so Bedrock
and classic installs both work without being told which they are; the site URL
comes from `wp option get siteurl`; there is no `/srv/www`, `/srv/backups`, or
`web@` anywhere, and `--host` refuses to run without an explicit
`--site-path` rather than guessing a Trellis layout.

Naming followed the caveat: `wp-db-backup` keeps `wp-ops db-backup`
unambiguous. `wp-site-backup.sh` and `wp-db-pull.sh` remain unwritten and
should stay on distinct basenames too.

### Step 7 — `wordpress-utilities/`

Answered: **they were not commands.** One of the five was a stylesheet, one an
HTML template, and `executeEntry` already tested for the `wordpress-utilities/`
prefix *before* its `.php` branch so they'd be printed rather than run — the
repo maintained a whole separate executor for the only five entries that
didn't execute.

The split was decided by what each file actually is, not by file type:

- **Reference material → `docs/wordpress-utilities/`.** The age-verification
  component (JS + PHP template + CSS) is something you paste into a theme;
  there is no command hiding in it.
- **Operations → real WP-CLI commands.** The two remaining PHP snippets
  described things WP-CLI can do directly, so they became
  `wp-cli/security/admin-user-create` and `wp-cli/seo/noindex-expired-posts`,
  both `@platform wordpress`.

`post-expiry-noindex.php` is the interesting case: it doesn't fully reduce to
a command. Its `wpseo_robots` filter and its "Noindex After Date" meta box are
genuinely runtime concerns, and the meta box is what writes the date the
command reads. The snippet stays in `docs/` for the editor UI; the command
applies the outcome in bulk and can run from cron. Complementary, not
redundant.

With all five gone the directory had no commands left, so it followed
`nginx/`, `troubleshooting/`, and `bedrock/` under `docs/` and out of
`Categories` — otherwise Option D would have cleaned up three dead entries
and immediately created a fourth. `internal/exec/snippet.go` and its tests
went with it (~130 lines, no remaining callers), which costs the `--copy`
clipboard helper; `--where` already covered `--path`.
