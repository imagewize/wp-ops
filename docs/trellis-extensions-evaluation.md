# Publishing wp-ops Trellis tools as Trellis extensions

**Status:** evaluation, nothing implemented.
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
- [Path A: a `trellis-wpops` plugin shim](#path-a-a-trellis-wpops-plugin-shim)
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
$ printf '#!/usr/bin/env bash\necho "plugin works: $*"\n' > /somewhere/on/path/trellis-wpopstest
$ chmod +x /somewhere/on/path/trellis-wpopstest
$ trellis --help
...
Available plugin commands:
    wpopstest

$ trellis wpopstest hello world
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
| `trellis-wpops` | `trellis wpops` |
| `trellis-backup` | `trellis backup` |
| `trellis-wp-ops` | `trellis wp ops` ← two words, almost certainly not what you want |

So the shim must be named `trellis-wpops`, not `trellis-wp-ops`.

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

Free and relevant: `backup`, `monitor`, `wpops`, `security`, `seo`, `scan`.

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

## Path A: a `trellis-wpops` plugin shim

The cheapest distribution win available to this repo.

`wp-ops` is already a single Go binary that runs all 13 Trellis commands.
Because `PassthroughCommand` execs an arbitrary binary with the remaining argv,
making it a `trellis` subcommand requires **no new code** — just a second name
on `PATH`:

```ruby
# in the Homebrew formula
bin.install "wp-ops"
bin.install_symlink bin/"wp-ops" => "trellis-wpops"
```

Verified working with the real binary, not a stub:

```console
$ ln -s /path/to/wp-ops /somewhere/on/path/trellis-wpops

$ trellis --help
...
Available plugin commands:
    wpops

$ trellis wpops                       # full category listing, as bare wp-ops
wp-ops — WordPress Operations Tools
  Monitoring             (17)  Log monitoring, uptime checks, and traffic analysis
  Backup                 (10)  Database and file backups — Ansible and shell
  ...

$ trellis wpops backup                # category navigation works
Backup Commands:
  db-backup                        Back up a remote site's database over SSH...
  database-pull                    Pull a site's database from a remote environment...

$ trellis wpops search backup         # subcommands work
10 matches for 'backup':
  trellis/backup/database-pull  [trellis] Pull a site's database from a remote...
```

Argv handling needs no changes — Cobra parses `os.Args[1:]`, and
`syscall.Exec` hands it exactly the post-`wpops` arguments.

What this buys: every Trellis user who installs wp-ops discovers it from inside
the tool they already use, and it shows up in `trellis --help` on a machine
where they've forgotten it's installed. What it costs: one symlink line.

**The one real rough edge.** `go/cmd/root.go:20` sets `Use: "wp-ops"`, so the
help footer instructs users in terms of a command they did not type:

```
Run 'wp-ops <category>' to see a category's commands (e.g. 'wp-ops backup')
Run 'wp-ops doctor' to check dependencies and environment
```

Under the alias that should read `trellis wpops <category>`. It is cosmetic —
every command still runs — but it is the difference between a shim that feels
deliberate and one that feels like a leak. Deriving the display name from
`filepath.Base(os.Args[0])` fixes it for both invocation paths at once.

Remaining caveats for the formula comment:

- Name it `trellis-wpops`. `trellis-wp-ops` becomes the two-word `trellis wp ops`.
- Gated on `load_plugins`, which defaults true but users can disable.
- Requires trellis-cli new enough to have `plugin/`. Confirmed present in v1.19.0.

A narrower alternative is `trellis-backup` → `trellis backup`, exposing only
the backup group. That reads better as a command name, but it claims a generic
namespace that Roots might want later, and it fragments the entry point. Prefer
one vendor-named plugin.

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

[`jasperf/trellis-sync`](https://github.com/jasperf/trellis-sync) predates all
of this: created 2017, 28 stars, 5 watchers, 5 forks. Its README now redirects
to wp-ops. What it is actually worth, measured rather than assumed:

| Asset | Value |
| --- | --- |
| 28 stars, 5 watchers | Real. Comparable to `hamedb89/trellis-db-push-and-pull` (31) |
| Inbound links since 2017 | Roots Discourse and blog lineage — the scripts descend from Raquelle's and Ben Word's originals, which is why links accumulated |
| Topics already set | `bedrock`, `database-sync`, `devops`, `roots`, `trellis`, `wordpress`, `wp-cli` |
| Packagist `trellis-sync/trellis-sync` | **Dead.** 102 downloads lifetime, 0/month, 0/day |
| 5 forks | All **0 commits ahead**. Nothing to salvage |
| 7 open issues (2017–2019) | The most useful asset. See below |
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

**So: archive it, and note it as the preferred home if the backup role ships.**
Un-archiving a repo with history beats registering a new name.

Do not transfer it to `imagewize` while it is a tombstone. GitHub transfers
preserve stars, forks, and issues and redirect the old URL, so the move is
safe — it just buys nothing, and costs a Packagist homepage update and a
redirect hop. Transfer becomes worthwhile only if the repo goes live again.

### The open issues are a distribution channel

Four of the seven are feature requests wp-ops now answers. Closing them
notifies the authors and every watcher — including `strarsis`, a Roots
contributor who filed three of them. Verified against the catalog, not assumed:

| Issue | Status |
| --- | --- |
| #4 "Use config from wp-cli.yml" (2 👍) | **Solved.** Sites come from `wordpress_sites.yml` |
| #13 `mysqldump: No such file` | **Solved.** `scripts/backup/db-pull.sh:268` runs `wp db export` over SSH on the remote; nothing dumps locally |
| #9 "How do I add this to composer.json" | Obsolete, already answered in-thread |
| #2 "Backup?" — tar/gzip, timestamped, incremental | **Two of three.** `files-backup.yml:27,57` produces timestamped `.tar.gz`. Not incremental, and no backup cron. `Xilonz/trellis-backup-role` does both via duply |
| #6 "source and destination cannot both be remote" | **Not solved.** Every wp-ops path is remote↔development. No production→staging |
| #12 "Add as WP CLI package" | Answered by [`wp-cli-package-evaluation.md`](wp-cli-package-evaluation.md) — mostly no, with reasons |
| #14 SSH error + uploads not deleted | **Stale.** The delete half is unchanged: `files-push.yml:76` hardcodes `delete: no`. `files-pull` has an opt-in `--delete` flag; push is deliberately additive |

Close them with specific commands and honest caveats. A wrong "fixed!" on a
nine-year-old thread is worse than leaving it open.

Order matters: **close the issues first, then archive** — archived repos are
read-only. Mark the Packagist package abandoned at the same time; nobody is
using it, but it puts a warning in front of anyone arriving from a 2017 post.

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

**1. Ship the `trellis-wpops` symlink now.** One line in the Homebrew formula,
no new code, no new repo, no maintenance surface. Verify the `argv[0]` behavior
and the alias name, then ship it. This is the highest ratio of reach to effort
anywhere in either evaluation document.

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
printf '#!/usr/bin/env bash\necho "plugin works: $*"\n' > "$S/trellis-wpopstest"
cp "$S/trellis-wpopstest" "$S/trellis-backup"      # free namespace
cp "$S/trellis-wpopstest" "$S/trellis-db-pull"     # blocked by core 'db'
chmod +x "$S"/trellis-*

PATH="$S:$PATH" trellis --help | tail -6     # 'backup' + 'wpopstest' listed; 'db pull' absent
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
