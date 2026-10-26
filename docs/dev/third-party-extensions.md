# Third-Party Extensions for wp-ops

**Status:** design proposal, nothing implemented.

How someone outside this repository could add a command that `wp-ops`
discovers, lists, and runs — without forking, and without wp-ops growing a
plugin ecosystem it has no demand for.

This document is deliberately narrow. It names one architectural decision,
the code that decision breaks, and the smallest change that makes extensions
work. Everything that isn't required to get one third-party script running is
in [Out of scope](#out-of-scope) with a reason.

## Table of Contents

- [Is this needed?](#is-this-needed)
- [What the current architecture constrains](#what-the-current-architecture-constrains)
- [The decision: build-time catalog vs. runtime discovery](#the-decision-build-time-catalog-vs-runtime-discovery)
- [Design](#design)
  - [1. Entries need a root](#1-entries-need-a-root)
  - [2. Discovery](#2-discovery)
  - [3. Namespacing makes collisions structurally impossible](#3-namespacing-makes-collisions-structurally-impossible)
  - [4. Category placement](#4-category-placement)
  - [5. Degradation and caching](#5-degradation-and-caching)
- [Consumers that must change](#consumers-that-must-change)
- [The author contract](#the-author-contract)
- [Security: what wp-ops can and cannot enforce](#security-what-wp-ops-can-and-cannot-enforce)
- [Validation, not a test framework](#validation-not-a-test-framework)
- [Implementation phases](#implementation-phases)
- [Out of scope](#out-of-scope)
- [Open questions](#open-questions)

---

## Is this needed?

Answer this before building anything.

Today, someone who wants their own command has two options: open a PR against
this repo, or run a fork with `WP_OPS_ROOT` pointed at it
(`go/cmd/env.go:46`). The fork path already works, costs nothing to maintain,
and survives upgrades badly — which is the actual complaint an extension
system would fix.

So the question is not "would extensions be nice" but **who is blocked, and on
what.** Three plausible answers, with very different price tags:

| Need | Fix | Cost |
| --- | --- | --- |
| A few people at Imagewize want private client-specific scripts | One env var + a directory convention | ~1 day |
| External contributors want to publish shareable command packs | This document | ~1 week |
| A public plugin ecosystem with discovery and versioning | A registry, a package format, and ongoing curation | Months, forever |

**Everything below assumes the middle row.** If the real need is the first
row, implement [Phase 1](#implementation-phases) only and stop — it is
self-contained and already solves it.

The cost that is easy to miss: every field of `catalog.Entry` becomes a public
contract the moment a third party writes a manifest against it. `Entry` is
currently free to change (`go/internal/catalog/catalog.go:26-83`). After
extensions ship, it is not.

---

## What the current architecture constrains

The previous draft of this document described the manifest format correctly
and then designed against a codebase that doesn't exist. These are the facts
that actually decide the design.

**The catalog is generated at build time and embedded.** `gen` walks the
repo, parses every manifest, and writes `catalog.json`
(`go/internal/catalog/gen/main.go:89-200`); `catalog.go:19-20` embeds it.
`catalog.go:1-4` states the invariant outright:

> No filesystem scan happens at runtime: a malformed manifest fails the
> build, not the CLI's behavior.

**A malformed manifest is fatal.** `gen` collects lint errors and exits
non-zero on any hard error (`gen/main.go:180-193`). That is correct for a
repo you control and unacceptable for a directory a stranger writes into.

**The binary ships its own scripts.** `repoRoot()` tries `WP_OPS_ROOT`, then
a live checkout found by walking up from the binary and the cwd, and finally
extracts the embedded asset tree into
`~/Library/Caches/wp-ops/assets-<version>/` (`go/cmd/env.go:45-111`). A
Homebrew install has **no checkout on disk at all**. Any design phrased as
"drop your script into the repo" only serves the least common install shape.

**`ScriptPath` is repo-relative and joined against that single root.** Every
execution path does it: `--where` (`go/cmd/dispatch.go:222`), shell
(`:256`), Ansible (`:293`), WP-CLI (`:309`). So does `@doc` resolution in
`wp-ops docs` (`go/cmd/docs.go:71`) and in `manifest.Lint`
(`go/internal/manifest/manifest.go:272`).

**Human-facing listings are gated on a hardcoded slice.** `DisplayCategories()`
filters against `DisplayOrder` (`catalog.go:340-353`), and every grouped
surface iterates it — `go/cmd/list.go:77,99` and `go/internal/ui/model.go:60`.
A command whose `@category` isn't in that slice is dispatchable by key but
appears in no listing and no picker, and its header renders as `" commands"`
because `CategoryDisplayNames` misses.

**Short names are computed, not stored.** `Load` assigns `ShortName` from
basename uniqueness across the whole catalog and falls back to the full key
on collision (`catalog.go:134-144`); `printAmbiguous` handles the rest
(`dispatch.go:359`). Collision handling already exists.

**The MCP server reads `catalog.json` off disk.** `mcp-server/src/tools/catalog.ts`
resolves it from `REPO_ROOT` and parses it directly, deliberately, so that
command search works without a built Go binary. Runtime-discovered extensions
are invisible to it unless the same merge lands in TypeScript.

**`wp-ops list --json` is a stable contract.** Called that in
`go/cmd/list.go:134`. Its `category` field is directory-based. Whatever
extensions report there is a promise.

---

## The decision: build-time catalog vs. runtime discovery

This is the whole design. Everything else follows.

Extensions cannot be in the embedded catalog — they aren't in the repo when
`gen` runs. So either the CLI scans the filesystem at startup, or extensions
are registered explicitly through a config file listing their metadata.

**Take runtime discovery.** Explicit registration means an author writes
their manifest twice — once in the script header, once in the user's config —
and the two drift. It also duplicates executor selection, which today is
inferred from the file extension (`dispatch.go:227-235`); a config `type:
ansible` field is a second source of truth for something already knowable.

The cost is that `catalog.go:1-4`'s invariant no longer holds unconditionally.
Restate it as a two-tier rule:

> The **embedded** catalog is validated at build time and cannot be malformed
> at runtime. **Extension** entries are scanned at startup, and a malformed
> one is skipped with a warning — never fatal.

That asymmetry is the design, not a compromise. Core commands keep their
build-time guarantee; extensions can never take the CLI down.

---

## Design

### 1. Entries need a root

Nothing works before this. Add one field:

```go
// Root is the absolute directory ScriptPath is resolved against. Empty
// for embedded/core entries, which resolve against repoRoot() as they
// always have. Never serialized into the embedded catalog.json — it is a
// property of where an entry was discovered, not of the file.
Root string `json:"-"`
```

Then introduce a single accessor and route **every** join through it:

```go
func (e Entry) AbsPath(repoRoot string) string {
    if e.Root != "" {
        return filepath.Join(e.Root, e.ScriptPath)
    }
    return filepath.Join(repoRoot, e.ScriptPath)
}
```

Call sites to convert: `dispatch.go:222` (`--where`), `:256` (shell), `:293`
(Ansible), `:309` (WP-CLI), `docs.go:71` (`@doc`), and `manifest.Lint`'s doc
check (`manifest.go:272`). That list is the complete blast radius.

Note that Ansible playbooks additionally get `WithWPOpsRoot(playbookArgs,
root)` (`dispatch.go:294`) — an extension playbook still needs the *core*
root for that variable, so it stays `repoRoot()`, not the extension root.
Two different roots, deliberately.

### 2. Discovery

One directory, one env var:

```
$WP_OPS_EXTENSIONS_DIR   default: ~/.wp-ops-extensions
```

Layout — each immediate subdirectory is one extension, named by its vendor:

```
~/.wp-ops-extensions/
└── acme/                        # vendor namespace
    ├── scripts/
    │   └── client-backup.sh
    └── trellis/
        └── client-deploy.yml
```

Discovery reuses `gen`'s walk verbatim: same per-category extensions
(`gen/main.go:47-59`), same excluded dirs, same `manifest.Parse`. That means
**factoring the walk out of `package main`** into something both `gen` and
the runtime scanner import — otherwise the two discovery rules drift, and a
script that works in-repo behaves differently as an extension. Proposed
home: `go/internal/catalog/discover`.

Merge order: embedded entries first, extension entries appended, then `Load`'s
`ShortName` computation runs over the combined set so basename uniqueness
accounts for both.

A single directory, not a list of paths. A `$PATH`-style list invites
precedence questions that namespacing (below) makes moot, and nobody has
asked for more than one.

### 3. Namespacing makes collisions structurally impossible

Extension keys are minted as `ext/<vendor>/<path-under-vendor-dir>`:

```
~/.wp-ops-extensions/acme/scripts/client-backup.sh
  → key: ext/acme/scripts/client-backup
```

Because every extension key starts with `ext/`, it can never equal a core
key. Duplicate *full keys* are therefore impossible without any priority
system, override config, or conflict resolver.

Duplicate *basenames* remain possible — `ext/acme/scripts/db-backup` vs.
`scripts/backup/db-backup` — and are **already handled**: both lose their
`ShortName` and fall back to full keys (`catalog.go:134-144`), and
`printAmbiguous` prints both with instructions (`dispatch.go:359`). Nothing
new is needed. Two extensions from different vendors can't collide on a full
key either, since the vendor segment is in it.

This deletes the previous draft's four duplicate-prevention strategies. In
particular it deletes `command_overrides.disable`: letting a machine-local
config silently repoint `wp-ops db-backup` at someone else's script is worse
than the ambiguity error, because the error is visible and the redirect
isn't.

Register `"ext"` in `catalog.Categories` so `wp-ops ext <name>` works as a
category scope via the existing hidden-alias path (`dispatch.go:77-82`).
`gen` will `os.Stat` a repo-level `ext/` directory, not find one, and
`continue` (`gen/main.go:102-105`) — harmless, but worth a comment there so
it doesn't read as an oversight.

For `wp-ops list --json`, extension entries report `"category": "ext"`. That
keeps the existing contract's meaning intact (`category` is still the
top-level directory) and gives external tooling a trivial filter.

### 4. Category placement

An extension declaring `@category backup` should group with the other backup
commands. An extension declaring `@category deployment` — a value not in
`DisplayOrder` — must not vanish from every listing.

Rule: if `@category` is present in `DisplayOrder`, use it. Otherwise fall
back to `misc`, which is already the catch-all and already carries a blurb
(`catalog.go:392`). Do **not** append unknown categories to `DisplayOrder` at
runtime: it's a curated ordering with hand-written blurbs and display names,
and a stranger's `@category` should not be able to insert a top-level group
into `wp-ops --help`.

### 5. Degradation and caching

**Degradation.** A malformed extension manifest gets one line on stderr and
is skipped. The rules from `gen/main.go:180-193` carry over as *warnings*
rather than fatals — with the same carve-out for missing `@desc`, which falls
back to the header scrape (`gen/main.go:163-167`). An unreadable extensions
directory is not an error; it means no extensions.

**Caching is not optional.** Scanning happens on every invocation, including
shell completion (`dispatch.go:115`, `:143`) — which runs on every `<TAB>`
and is the most latency-sensitive path in the CLI. Cache the scan result in
`~/.cache/wp-ops/extensions-<hash>.json`, keyed on the extensions dir's
recursive max mtime; on a hit, skip the walk and the manifest parsing
entirely. The `~/.cache/wp-ops/` parent already exists for asset extraction
(`env.go:81`).

Budget: a cache hit should add **under 5ms** to startup. Measure it before
merging; if that isn't achievable, the discovery approach is wrong and
explicit registration deserves a second look.

---

## Consumers that must change

Checklist. Each of these reads the catalog and would otherwise be silently
wrong.

| Consumer | Change |
| --- | --- |
| `dispatch.go` execution paths (4 sites) | Route through `Entry.AbsPath` |
| `docs.go` `@doc` resolution | Resolve against the entry's root |
| `manifest.Lint` doc check | Take the extension root, not `repoRoot` |
| `list.go` grouped views | Nothing — `DisplayCategory` fallback covers it |
| `list.go` `printJSON` | Emit `"category": "ext"`; contract note |
| `ui/model.go` picker | Nothing, same reason |
| `doctor.go` | Report extension count and any skipped/malformed entries |
| `mcp-server/src/tools/catalog.ts` | **Decide explicitly** — see below |
| Shell completion | Nothing functional; the cache is what keeps it usable |

The MCP bridge is a real fork in the road, not an afterthought. It reads
`catalog.json` from `REPO_ROOT` on disk by design, so extensions are invisible
to it for free. Two honest options:

1. **CLI-only extensions.** Document it in one line in `mcp-server/README.md`.
   Zero work, and defensible: MCP tools are an agent-facing surface where
   arbitrary third-party commands are a larger trust question anyway.
2. **Mirror the scan in TypeScript.** Real work, and a second implementation
   of discovery rules that must track the Go one.

Recommend (1) for the first release. Revisit only if someone asks.

---

## The author contract

Unchanged from the existing manifest format — that's the point. An extension
script is an ordinary wp-ops script that happens to live elsewhere.

```bash
#!/usr/bin/env bash
#
# @desc     Nightly backup to the client's own S3 bucket
# @category backup
# @platform wordpress
# @runs     local
# @requires wp aws
# @arg      site  required  {example.com}  Site to back up
# @example  wp-ops ext/acme/scripts/client-backup example.com
```

Required for an extension: `@desc`, `@category`, `@platform`, `@runs`.
`@desc` is technically optional (the header scrape covers it,
`gen/main.go:163-167`) but a scraped description reads badly in the picker.

Recognized values are enforced by the existing linter and unchanged:
`@platform` ∈ {`trellis`, `wordpress`, `any`} (`manifest.go:251-257`),
`@runs` ∈ {`local`, `server`, `either`} (`manifest.go:238-244`).

Two notes for authors:

- **`@doc` resolves against your extension root**, not wp-ops'.
- **`@example` should use the full `ext/...` key.** Your basename may or may
  not survive as a short name depending on what else the user has installed,
  so an example written against the short form can be wrong on someone
  else's machine. (The repo pins this for core commands in a test — see
  commit db25031.)

Unrecognized directives like `@version` and `@author` are silently ignored by
the parser (`manifest.go:96-99`) and are fine to include as documentation.

---

## Security: what wp-ops can and cannot enforce

Be blunt here, because the previous draft was not.

**wp-ops cannot sandbox an extension.** It `exec`s the script as the invoking
user (`internal/exec/shell.go`). There is no filesystem allowlist, no network
policy, no blocked-commands list, and no way to add one without a container
or an OS sandbox that wp-ops does not have. A `permissions:` block in a
manifest would be decoration that reads as a guarantee — strictly worse than
saying nothing.

**wp-ops cannot enforce `--dry-run` either.** Every dispatch path sets
`DisableFlagParsing` and passes argv through untouched (`dispatch.go:36,52`),
because the underlying scripts own their flag grammars. Whether an extension
honors `--dry-run` is between its author and its user.

So the security model is one sentence:

> Installing an extension is equivalent to running a shell script you
> downloaded. Trust is binary and it is yours to grant.

What wp-ops can usefully do:

- `wp-ops ext where <key>` — print the file's absolute path so it can be read
  before it's run. `--where` already does this (`dispatch.go:216-224`); it
  just needs to work for extensions, which falls out of `Entry.AbsPath`.
- `wp-ops ext list` — show every extension, its vendor, and its path, so
  "what is installed" is answerable without `find`.
- Warn once, on first discovery of a new vendor directory, that its scripts
  run with the user's privileges.
- Preserve the existing server-side guard (`serverSideGuard`,
  `dispatch.go:246`) for extensions declaring `@runs server`.

No signature verification, no curated trusted-source list. Both require
infrastructure and a trust authority this project doesn't have.

---

## Validation, not a test framework

Extension authors need to know their manifest is correct before a user hits
it. They do not need wp-ops to ship an assertion library.

```bash
wp-ops ext validate [path]
```

What it does, all of it reusing existing code:

1. Walk the extension the way discovery does (shared `discover` package).
2. `manifest.Parse` + `manifest.Lint` each file, with `@doc` resolved against
   the extension root (`manifest.go:231-278`).
3. Syntax-check by extension: `bash -n` for `.sh`, `ansible-playbook
   --syntax-check` for `.yml`, `php -l` for `.php`, `node --check` for `.js`.
4. Report basename collisions against the installed catalog — informational,
   since they resolve to full keys rather than failing.
5. Exit non-zero on any hard error, so it drops into an author's CI unchanged.

That's roughly 100 lines and catches the failures that actually reach users.

The previous draft proposed `wp-ops test-helpers`, a fixture convention, an
assertion library, and `wp-ops test generate-ci`. Dropped: this repo does not
test its own ~60 shell scripts, and shipping a test harness for third parties
before testing your own commands is the wrong order. If script testing is
wanted, it should land for core commands first and extensions should inherit
whatever that turns out to be.

---

## Implementation phases

**Phase 1 — make external paths executable.** `Entry.Root` + `AbsPath`, all
six call sites converted, and `$WP_OPS_EXTENSIONS_DIR` scanned with `ext/`
keys. No caching yet, no new subcommands. This is independently useful: it
alone solves the "private client scripts" case.

**Phase 2 — make it usable.** The mtime cache, the `DisplayOrder` → `misc`
fallback, degradation warnings, `doctor` reporting, and the `discover`
package factored out of `gen`.

**Phase 3 — make it publishable.** `wp-ops ext list | where | validate`, plus
a short authoring guide. Distribution is `git clone` into the extensions
directory — no installer.

Stop there. Reassess only with evidence of extensions in the wild.

---

## Out of scope

Each of these was in the previous draft. Each is dropped for a stated reason,
not forgotten.

| Dropped | Why |
| --- | --- |
| Package manager (`ext install/update/search`) | `git clone` into one directory covers it. `search` needs a registry that doesn't exist. |
| Extension registry | Requires hosting, curation, and a trust authority. No demand. |
| Priority system, override config, aliases | Namespacing makes full-key collisions impossible; basename collisions are already handled (`catalog.go:134-144`). Three mechanisms for a solved problem. |
| `permissions:` sandboxing | Unenforceable against an `exec`d shell script. Documenting controls that don't exist is worse than documenting none. |
| Signature verification, trusted sources | Needs a trust authority. |
| Test-helper library, `test generate-ci` | Core scripts aren't tested either. `ext validate` covers the real failure mode. |
| Config-file registration of metadata (previous Option B) | Second source of truth; duplicates extension-based executor selection (`dispatch.go:227-235`). |
| Git submodules (previous Option C) | Bloats this repo with third-party code and requires a PR to add anything — the opposite of the goal. |
| Multiple extension search paths | Precedence questions namespacing already removes. |

---

## Open questions

1. **Does anyone actually want this?** See [Is this needed?](#is-this-needed).
   Not rhetorical — Phase 1 is worth doing regardless, Phases 2–3 are not.
2. **MCP: option (1) or (2)?** Recommend CLI-only for the first release, but
   it should be a decision on the record rather than an omission.
3. **Does the cache hold the 5ms completion budget?** If not, the whole
   runtime-discovery premise needs revisiting.
4. **Should `ext/` appear in `wp-ops --help` at all?** Core categories are
   visible; the directory aliases are hidden. An `ext` group with a vendor's
   commands in it is arguably neither.
