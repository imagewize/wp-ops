# Publishing wp-ops Trellis tools as Trellis extensions

**Status:** Path A **shipped** (see [Path A](#path-a-a-trellis-ops-plugin-shim));
Path B still an evaluation. The trellis-sync issues are closed and the repo is
archived.
**Date:** 2026-08-21.

What this repo already has that the Trellis ecosystem wants, which of the two
extension mechanisms fits it, and what it would cost. The mechanics below were
verified against `trellis-cli` at `/Users/jasperfrumau/code/trellis-cli`
(`v1.19.0-36-gc01ecc8`) and confirmed by running a plugin.

Companion to [`wp-cli-package-evaluation.md`](wp-cli-package-evaluation.md),
which covers the PHP side. Of the two, this is the cheaper path with the
better evidence.

## Table of Contents

- [Two mechanisms, often confused](#two-mechanisms-often-confused)
- [How trellis-cli plugins actually work](#how-trellis-cli-plugins-actually-work)
  - [The naming rule](#the-naming-rule)
  - [The core-namespace guard](#the-core-namespace-guard)
- [What the ecosystem already has](#what-the-ecosystem-already-has)
- [What we have that overlaps](#what-we-have-that-overlaps)
- [Path A: a `trellis-ops` plugin shim](#path-a-a-trellis-ops-plugin-shim)
- [Path B: an Ansible role on Galaxy](#path-b-an-ansible-role-on-galaxy)
- [The trellis-sync repo](#the-trellis-sync-repo)
  - [The open issues are a distribution channel](#the-open-issues-are-a-distribution-channel)
- [Repo layout](#repo-layout)
- [Recommendation](#recommendation)
- [Appendix: reproducing the verification](#appendix-reproducing-the-verification)

---

## Two mechanisms, often confused

"Trellis extension" means two unrelated things, and the
[user-contributed extensions page](https://roots.io/trellis/docs/user-contributed-extensions/)
only lists the first:

| | **Ansible Galaxy role** | **trellis-cli plugin** |
| --- | --- | --- |
| What it extends | The server build / deploy | The `trellis` command surface |
| Install | Add to `galaxy.yml`, run `ansible-galaxy install -r galaxy.yml`, add role to `server.yml` | Put an executable named `trellis-*` on `PATH` |
| Written in | Ansible YAML | Anything executable |
| Runs | During `trellis provision` / `deploy` | When the user types the subcommand |
| Discoverable | Listed on the roots.io page | Not listed anywhere |
| Examples | `bedrock-site-protect`, `trellis-backup-role` | (none published that I can find) |

Every extension on the roots.io page is the left column. `bedrock-site-protect`
is a Galaxy role installed via `galaxy.yml` + `server.yml`;
`trellis-purge-wp-rocket-cache-during-deploy` is the same pattern hooked into
deploys. None of them are CLI plugins.

The right column is the interesting one, because it is real, undocumented, and
**nobody is using it**.

---

## How trellis-cli plugins actually work

Registration happens at startup, gated on one config flag:

```go
// trellis-cli main.go:232-235
if trellis.CliConfig.LoadPlugins {
    pluginPaths := filepath.SplitList(os.Getenv("PATH"))
    plugin.Register(c, pluginPaths, []string{"trellis"})
}
```

`load_plugins` defaults to `true`, so this is on for every user by default.

The finder walks every `PATH` directory for files that are (a) prefixed
`trellis-` and (b) executable (`plugin/finder.go:29-71`). Matches are wired up
as a `PassthroughCommand`, which `syscall.Exec`s the binary with the remaining
argv and the inherited environment:

```go
// trellis-cli cmd/passthrough.go
syscall.Exec(c.Bin, append([]string{c.Bin}, args...), os.Environ())
```

That is a git/kubectl-style plugin model. **The plugin can be anything
executable** — a Bash script, or the existing `wp-ops` Go binary.

Verified by running it:

```console
$ printf '#!/usr/bin/env bash\necho "plugin works: $*"\n' > /somewhere/on/path/trellis-demoplugin
$ chmod +x /somewhere/on/path/trellis-demoplugin
$ trellis --help
...
Available plugin commands:
    demoplugin

$ trellis demoplugin hello world
plugin works: hello world
```

Plugins are appended to help under their own **"Available plugin commands:"**
heading (`plugin/register.go:36`), so they are visibly third-party rather than
masquerading as core.

### The naming rule

The filename is split on `-`, the first segment is dropped, and the rest is
joined **with spaces** (`plugin/finder.go:62-67`):

| Binary name | Subcommand |
| --- | --- |
| `trellis-ops` | `trellis ops` |
| `trellis-backup` | `trellis backup` |
| `trellis-wp-ops` | `trellis wp ops` ← two words, almost certainly not what you want |

So the shim must be a single segment after the prefix. **Shipped as
`trellis-ops` → `trellis ops`**; `trellis-wp-ops` would have become the
three-word `trellis wp ops`. An earlier draft of this document proposed
`trellis-wpops`, which works but reads like a typo.

### The core-namespace guard

This is the trap a naive plan walks into:

```go
// trellis-cli plugin/finder.go:98-103
func isUnderCoreRootCommands(filepath string, coreRootCommands []string) bool {
	rootCommand := strings.Split(filepath, "-")[1]
	return slices.Contains(coreRootCommands, rootCommand)
}
```

A plugin whose **first segment matches any core root command is silently
skipped** — no error, no warning, it simply never appears. `db` is a core
command, so:

```console
$ ls trellis-db-pull trellis-backup    # both executable, both on PATH
$ trellis --help | tail -3
Available plugin commands:
    backup                              # trellis-db-pull is absent

$ trellis db pull
Usage: trellis db <subcommand> [<args>]
Subcommands:
    open    Open database with GUI applications
```

`trellis-db-pull` was ignored entirely. Blocked namespaces are every core root
command: `alias check db deploy dotenv exec galaxy info init key logs new open
provision rollback server shell-init ssh valet vault vm xdebug-tunnel`, plus
`droplet` and `venv`.

Free and relevant: `backup`, `monitor`, `ops`, `security`, `seo`, `scan`.

Note that `trellis db` currently only has `open` — the obvious
`trellis db pull` / `db push` namespace is reserved by core but unimplemented.
Anything we ship has to live elsewhere until Roots fills it in.

---

## What the ecosystem already has

The published extensions closest to this repo's Trellis tooling:

| Extension | Stars | Last pushed | Overlaps our |
| --- | ---: | --- | --- |
| [valentinocossar/trellis-database-uploads-migration](https://github.com/valentinocossar/trellis-database-uploads-migration) | 96 | Dec 2022 | `backup/` — **near-identical** |
| [louim/bedrock-site-protect](https://github.com/louim/bedrock-site-protect) | 80 | Apr 2020 | — |
| [Xilonz/trellis-backup-role](https://github.com/Xilonz/trellis-backup-role) | 65 | Apr 2022 | `backup/`, partially |
| [hamedb89/trellis-db-push-and-pull](https://github.com/hamedb89/trellis-db-push-and-pull) | 31 | **May 2017** | `backup/database-*` |
| [ItinerisLtd/trellis-purge-wp-rocket-cache-during-deploy](https://github.com/ItinerisLtd/trellis-purge-wp-rocket-cache-during-deploy) | 10 | Jan 2020 | — |

Two things follow from this table.

**There is demonstrated demand for exactly what `trellis/backup/` does.** Three
separate projects, ~190 stars between them, all solving database and uploads
push/pull. `trellis-db-push-and-pull` collected 31 stars and is still linked
from the official roots.io page despite not being touched since 2017.

**The bar is low and nobody is maintaining it.** The most popular one is
four years stale, and its install procedure is:

> 1. Download latest release
> 2. Copy `CHANGELOG-...md` into Trellis root
> 3. Copy all `*.yml` files into Trellis root
> 4. Copy all `bin/*.sh` files into Trellis bin folder
> 5. Add `database_backup/*` to the Bedrock `.gitignore`
> 6. Set alias for host files

Six manual copy steps with no version tracking beyond a changelog file you
paste in yourself. It also carries "Tested up to Ansible 2.6.1" and a note that
it doesn't work on 2.4.1.0.

---

## What we have that overlaps

The `trellis` catalog category holds 13 commands:

| Ours | Ecosystem equivalent | Our advantage |
| --- | --- | --- |
| `backup/database-{backup,pull,push}.yml` | all three projects above | see below |
| `backup/files-{backup,pull,push}.yml` | `uploads.yml` in valentinocossar | separate backup/pull/push rather than one mode flag |
| `monitoring/quick-status.yml` (10 tasks) | none found | log-driven health check |
| `monitoring/traffic-report.yml` (7 tasks) | none found | Nginx access-log analysis |
| `monitoring/security-scan.yml` (9 tasks) | none found | attack-pattern scan of Nginx logs |
| `monitoring/setup-monitoring.yml` (15 tasks) | none found | installs the cron jobs for the above |
| `security/check-{ips,deny-ips}.sh` | none found | AbuseIPDB reputation lookups |
| `updater/trellis-updater.sh` | none found | safe Trellis update |

Our backup playbooks are meaningfully better than the three existing projects,
in ways worth stating concretely:

```yaml
# trellis/backup/database-pull.yml
- name: Abort if environment variable is equal to development     # :43
- name: Abort if {{ site }} local folder doesn't exist            # :55
- name: Export development database before importing dump (backup) # :85
  shell: wp db export - | gzip > database_backup/{{ backup_file }}
- command: wp search-replace '//{{ url_from }}' '//{{ url_to }}'   # :108
    --allow-root --all-tables --precise
```

Guards before destructive work, an automatic local backup before import, and
`--all-tables --precise` search-replace. Plus `variable-check.yml`, which fails
with a usage string instead of a Jinja undefined-variable trace.

**The monitoring group is the genuinely novel part.** Four playbooks, ~430
lines, and I found no published Trellis extension doing Nginx log analysis or
traffic reporting at all. If anything here earns attention, it's that — not a
fourth database push/pull tool.

---

## Path A: a `trellis-ops` plugin shim

**Shipped.** The cheapest distribution win available to this repo, and it cost
one config block plus a display-name fix.

`wp-ops` is already a single Go binary that runs all 13 Trellis commands.
Because `PassthroughCommand` execs an arbitrary binary with the remaining argv,
making it a `trellis` subcommand requires **no new code** — just a second name
on `PATH`. wp-ops ships as a Homebrew *cask*, generated by goreleaser, so the
symlink is declared in `.goreleaser.yml` rather than edited into the tap:

```yaml
homebrew_casks:
  - name: wp-ops
    binaries: [wp-ops]
    custom_block: |
      binary "wp-ops", target: "trellis-ops"
```

goreleaser's `homebrew_casks` has no field for a second `binary` stanza with a
target, hence `custom_block`. It renders at the top of the cask body rather
than beside the generated `binary "wp-ops"`; cask stanza order is cosmetic and
an unofficial tap isn't `brew audit`ed.

Verified working with the real binary, not a stub:

```console
$ trellis --help
...
Available plugin commands:
    ops

$ trellis ops                         # scoped to @platform trellis
wp-ops — WordPress Operations Tools

  Monitoring             (11)  Log monitoring, uptime checks, and traffic analysis
  Backup                 ( 9)  Database and file backups — Ansible and shell
  Content                ( 2)  Block pattern screenshots, page creation, and pattern validation
  Security               ( 2)  Malware scanning, fail2ban, IP blocking, and admin recovery
  Misc                   ( 2)  Trellis updater, WooCommerce variations, and one-off utilities
  Diagnostics            ( 1)  WordPress transient and post-count diagnostics

Run 'trellis ops <category>' to see a category's commands (e.g. 'trellis ops backup')
Showing @platform trellis commands only — run 'wp-ops' for the full catalog

$ trellis ops backup                  # category navigation works
Backup Commands:
  db-backup                        Back up a remote site's database over SSH...
  database-pull                    Pull a site's database from a remote environment...
Usage: trellis ops backup <command> [args...]
```

Argv handling needs no changes — Cobra parses `os.Args[1:]`, and
`syscall.Exec` hands it exactly the post-`ops` arguments.

**Plugins don't need a Trellis project.** Registration is a `$PATH` walk at
startup (`main.go:232-235`), before trellis-cli resolves a project at all, so
`trellis ops` runs from anywhere while core `trellis info` refuses:

```console
$ cd /tmp && trellis info
No Trellis project detected in the current directory or any of its parent directories.

$ cd /tmp && trellis ops doctor
wp-ops doctor 5.5.0
```

The Ansible commands still need a project, but they always did — wp-ops finds it
through its own `detect.TrellisDir` (`go/internal/detect/detect.go:30`), which
walks up from the cwd exactly like trellis-cli's. Nothing is passed between the
two.

**The rough edge, now fixed.** `go/cmd/root.go:20` set `Use: "wp-ops"`, so the
help footer instructed users in terms of a command they did not type. Every
usage line, footer, and did-you-mean suggestion now renders against
`filepath.Base(os.Args[0])` (`go/cmd/invoked.go`), which fixes both invocation
paths at once; output under bare `wp-ops` is byte-for-byte unchanged.

The same argv[0] check scopes the *listing* to `@platform trellis` — 27 commands
across 6 categories rather than all 74. Someone at a `trellis` prompt isn't
looking for the image converters. Execution is deliberately not scoped: name any
command and it runs.

Caveats, all documented in the config comments:

- Name it `trellis-ops`. `trellis-wp-ops` becomes the three-word `trellis wp ops`.
- Gated on `load_plugins`, which defaults true but users can disable.
- Requires trellis-cli new enough to have `plugin/`. Confirmed present in v1.19.0.
- `ops` is generic. If Roots ever ships a core `ops` command, the plugin is
  silently skipped by `isUnderCoreRootCommands` — no error, no warning. Lower
  risk than claiming `backup` or `monitor`, but it is the trade for the better
  name.

A narrower alternative was `trellis-backup` → `trellis backup`, exposing only
the backup group. It claims a generic namespace Roots is more likely to want,
and it fragments the entry point. One plugin, one door.

---

## Path B: an Ansible role on Galaxy

For reaching Trellis users who don't want a Go binary at all.

`trellis/backup/*.yml` are standalone playbooks, not a role, so this is a real
port: tasks into `tasks/`, defaults into `defaults/`, `meta/main.yml` for
Galaxy metadata. The monitoring playbooks port more naturally, since
`setup-monitoring.yml` already installs cron jobs — which is exactly what a
provisioning role does.

The pitch writes itself against the incumbents: versioned via `galaxy.yml`
instead of six copy steps, maintained this decade, and with the pre-flight
guards the 2017 project never had.

Two things to check before committing:

- **Ansible version floor.** Ours are written against current Ansible; the
  incumbents cap out around 2.6. Declare the floor in `meta/main.yml`.
- **Trellis coupling.** The playbooks read `wordpress_sites`, `web_user`, and
  `project_local_path`. That's the same coupling every extension on the roots
  page has, so it's acceptable — but it must be documented, not assumed.

Galaxy roles are the channel that's actually indexed on roots.io. Path A gets
better UX; Path B gets discovery.

---

## The trellis-sync repo

**Status: issues closed, repo archived.** Packagist not yet marked abandoned.

[`jasperf/trellis-sync`](https://github.com/jasperf/trellis-sync) predates all
of this: created 2017, 28 stars, 5 watchers, 5 forks. Its description now
reads "superseded by wp-ops" with the homepage pointed at
[imagewize/wp-ops](https://github.com/imagewize/wp-ops). What it is actually
worth, measured rather than assumed:

| Asset | Value |
| --- | --- |
| 28 stars, 5 watchers | Real. Comparable to `hamedb89/trellis-db-push-and-pull` (31) |
| Inbound links since 2017 | Roots Discourse and blog lineage — the scripts descend from Raquelle's and Ben Word's originals, which is why links accumulated |
| Topics already set | `bedrock`, `database-sync`, `devops`, `roots`, `trellis`, `wordpress`, `wp-cli` |
| Packagist `trellis-sync/trellis-sync` | **Dead**, and still live. 102 downloads lifetime, 0/month, 0/day. Not yet flagged abandoned — that's a Packagist maintainer-account action, still open |
| 5 forks | All **0 commits ahead**. Nothing to salvage |
| 7 issues (2017–2019) | **Closed**, each with the specific fix/gap below. See below |
| The scripts | Superseded |

**This changes the repo plan for a backup role.** The section below originally
proposed creating `imagewize/trellis-wp-backup` from nothing. trellis-sync is
already that repo by name, topics, and audience — "Trellis DB + uploads sync"
is precisely the `trellis/backup/` group. Reviving it starts at 28 stars
against `valentinocossar`'s 96, rather than at zero.

It lowers the *setup* cost, not the *differentiation* problem. The sequencing
in [Recommendation](#recommendation) stands: monitoring is still the
uncontested niche, and reviving trellis-sync means committing to maintain it —
which is what killed it the first time.

**So: archived, and noted as the preferred home if the backup role ships.**
Un-archiving a repo with history beats registering a new name.

Do not transfer it to `imagewize` while it is a tombstone. GitHub transfers
preserve stars, forks, and issues and redirect the old URL, so the move is
safe — it just buys nothing, and costs a Packagist homepage update and a
redirect hop. Transfer becomes worthwhile only if the repo goes live again.

### The open issues, closed

All seven closed on 2026-08-21, each with wp-ops's actual equivalent command
and an honest caveat where the gap is real — not a blanket "fixed!" on
threads up to nine years old. Four of the seven were feature requests
wp-ops answers; three stay honestly open gaps, now tracked in a maintained
place instead of a dead one:

| Issue | Resolution |
| --- | --- |
| #4 "Use config from wp-cli.yml" (2 👍) | Closed **solved**. `wp-ops db-pull`/`files-pull` read sites from `wordpress_sites.yml` — no hardcoded `DEVDIR`/`PRODDIR`/`STAGDIR` |
| #13 `mysqldump: No such file` | Closed **solved**. wp-ops runs `wp db export` on the remote over SSH; nothing dumps locally |
| #9 "How do I add this to composer.json" | Closed **obsolete**. Answered in-thread at the time; noted the Packagist package is being marked abandoned in favor of `brew install imagewize/tap/wp-ops` |
| #2 "Backup?" — tar/gzip, timestamped, incremental | Closed **partial, said so**. `wp-ops files-backup`/`database-backup` give timestamped tar/gzip; incremental and cron scheduling are still gaps — pointed to `Xilonz/trellis-backup-role` for those |
| #6 "source and destination cannot both be remote" | Closed **not solved, said so**. Every wp-ops path is remote↔development; no production→staging. Two-hop pull-then-push documented as the workaround |
| #12 "Add as WP CLI package" | Closed, answered by [`wp-cli-package-evaluation.md`](wp-cli-package-evaluation.md) — mostly no for the scripts, yes for one command (now shipped as [`wp imagewize pattern-validate`](wp-cli-package-evaluation.md)) |
| #14 SSH error + uploads not deleted | Closed **half-stale, said so**. The SSH error was never reproduced; the delete behavior is now explicit and opt-in on pull (`--delete yes`), still additive-only on push |

Every close also flagged the two things still in flight: a Trellis Galaxy role
for the sync/backup playbooks (this doc, [Path B](#path-b-an-ansible-role-on-galaxy)),
and the `trellis ops` plugin surface ([Path A](#path-a-a-trellis-ops-plugin-shim)).

**Left to do:** mark the Packagist package abandoned. That's a Packagist
maintainer-account action (not a repo change), still outstanding — nobody is
using the package, but it puts a warning in front of anyone arriving from a
2017 post.

---

## Repo layout

Both paths want to live outside this repo, for different reasons.

**Path A needs no repo at all** — it's a symlink in the existing Homebrew
formula. Nothing moves.

**Path B needs its own repo.** Galaxy roles are one-role-per-repo by
convention, and every extension on the roots.io page follows it. If both the
backup and monitoring groups ship, that's two repos:

```
jasperf/trellis-sync              # database + uploads — un-archive, don't re-register
imagewize/trellis-wp-monitoring   # nginx log analysis + cron install
```

The backup slot is [trellis-sync](#the-trellis-sync-repo), which already holds
the name, the topics, and 28 stars. Only the monitoring repo is new.

Keep the playbooks in wp-ops as the source of truth and generate/sync the role
repos, rather than moving them. The Go catalog indexes `trellis/backup/*.yml`
by path (`go/internal/catalog/catalog.json`); moving those files out breaks all
13 Trellis commands and the MCP bridge along with them. A one-way export is
cheap; a split source of truth is not.

The same reasoning applies to the WP-CLI package in the companion doc — which
is the third potential repo, and the argument for doing these one at a time
rather than announcing a suite.

---

## Recommendation

**1. ~~Ship the `trellis-wpops` symlink now.~~ Done, as `trellis ops`.** One
`custom_block` in `.goreleaser.yml`, no new repo, no maintenance surface. This
was the highest ratio of reach to effort anywhere in either evaluation document.

**2. Then package the monitoring playbooks as a Galaxy role.** Not the backup
ones. Backup is a crowded field where we'd be the fourth entrant offering a
better version of a solved problem; Nginx log analysis and traffic reporting
appear to have no published Trellis extension at all. If the goal is attention,
ship the thing nobody else has.

**3. Backup as a Galaxy role is a maybe, later.** The quality gap over the
incumbents is real and the demand is proven at ~190 stars, but it only pays off
if it's maintained — and the graveyard above is what unmaintained looks like.
Do it after the monitoring role establishes whether the channel produces
anything.

**4. Don't chase `trellis db pull`.** It's blocked by the core-namespace guard
today, silently. If Roots ever implements it, our playbooks are a better
starting point than anything published — that's an upstream PR conversation,
not an extension.

Sequenced this way, step 1 costs an hour and step 2 is a weekend. Neither
requires deciding anything about the WP-CLI package first.

---

## Appendix: reproducing the verification

```bash
# The plugin mechanism, end to end
S=$(mktemp -d)
printf '#!/usr/bin/env bash\necho "plugin works: $*"\n' > "$S/trellis-demoplugin"
cp "$S/trellis-demoplugin" "$S/trellis-backup"      # free namespace
cp "$S/trellis-demoplugin" "$S/trellis-db-pull"     # blocked by core 'db'
chmod +x "$S"/trellis-*

PATH="$S:$PATH" trellis --help | tail -6     # 'backup' + 'demoplugin' listed; 'db pull' absent
PATH="$S:$PATH" trellis backup foo           # => plugin works: foo
PATH="$S:$PATH" trellis db pull              # => core 'db' help; plugin never ran

# Core root commands that block a plugin's first segment
trellis --help | awk '/^    [a-z]/ {print $1}'

# Our Trellis command inventory
python3 -c "
import json
d = json.load(open('go/internal/catalog/catalog.json'))
[print(x['key'], '->', x['script_path']) for x in d if x['category'] == 'trellis']"
```

Source references, all in `trellis-cli` at v1.19.0:

- `main.go:232-235` — registration, gated on `load_plugins`
- `plugin/finder.go:29-71` — PATH walk, prefix and executable-bit checks
- `plugin/finder.go:62-67` — the `-`-split-to-spaces naming rule
- `plugin/finder.go:98-103` — `isUnderCoreRootCommands`, the silent guard
- `plugin/register.go:20-37` — `PassthroughCommand` wiring and help separation
- `cmd/passthrough.go` — `syscall.Exec` with inherited env

## References

- [Trellis user-contributed extensions](https://roots.io/trellis/docs/user-contributed-extensions/) — the Galaxy-role directory
- [Trellis CLI docs](https://roots.io/trellis/docs/cli/) — `load_plugins` config
- [roots/trellis-cli](https://github.com/roots/trellis-cli)
- [`wp-cli-package-evaluation.md`](wp-cli-package-evaluation.md) — the PHP-side companion
- [`trellis-cli-comparison.md`](trellis-cli-comparison.md) — entry point and command surface comparison
- [`third-party-extensions.md`](third-party-extensions.md) — the inverse question: others extending wp-ops
