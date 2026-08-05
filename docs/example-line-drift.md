# Example lines still name internal keys: inventory and fix

> **Status (2026-08-05): implemented in 5.1.2.** Option 3 shipped as the
> three commits §6 recommends — the test, the 47-line sweep, and the four Go
> sites — plus the `docs/trellis-cli-comparison.md` fix. §7's open question
> (`search` vs `list` naming) is deliberately still open. Prose below is
> preserved as written, so it describes the pre-fix state; measured against
> `main` at 3a53555 (5.1.1).
> **Problem:** `wp-ops scanner-targeted --help` prints a correct usage line
> and then an `Examples:` block that reads
> `wp-ops wp-cli/security/scanner-targeted`. 5.1.0 and 5.1.1 fixed the usage
> line for every command and every executor, but they fixed it by changing the
> code that *generates* it. Example lines are not generated — they are prose
> copied verbatim out of each script's `@example` annotation — so they were
> never touched. **42 of the 71 commands that carry examples** still print at
> least one path-style invocation, 47 lines in total.
> **Conclusion:** Sweep the 47 lines once, fix the four remaining Go call
> sites that still format `e.Key` into user-facing text, and add a test in the
> `catalog` package that fails when an example's command token is not the
> entry's `ShortName`. The test is what makes the sweep stick; without it this
> recurs at the next rename, exactly as it did at 5.1.1's.
> **Related:** [trellis-cli-comparison.md](trellis-cli-comparison.md) §5
> (where the usage-line problem was first written up),
> [category-organization.md](category-organization.md),
> [wp-ops-recommendations.md](wp-ops-recommendations.md)

---

## 1. What you are seeing

The clearest form of it is the picker's post-selection detail block, where the
two lines sit six rows apart and disagree:

```
Usage: wp-ops find-and-replace-files <filename> [source-file] [options]

Find (and optionally replace) multiple copies of a file across projects

Requires: find · Platform: any

Examples:
  wp-ops scripts/misc/find-and-replace-files -l -s create-pr.sh
```

The usage line is 5.1.0's generated one. The example under it is the 2024-era
annotation. Both render paths are affected — `exec.DetailBody` (the picker,
above) and `exec.writeManifestHelpBody` (`--help`) each carry their own copy
of the same three-line `for _, ex := range e.Examples` loop
(`help.go:108-113` and `help.go:159-164`), printing the string unchanged. So
anywhere examples appear, they appear in the long form.

More real output from the current binary:

```
$ wp-ops scanner-targeted --help
Usage: wp-ops scanner-targeted [args...]
...
Examples:
  wp-ops wp-cli/security/scanner-targeted        ← names an internal key

$ wp-ops check-ips --help
Examples:
  wp-ops trellis/security/check-ips 1.2.3.4 5.6.7.8

$ wp-ops convert-screenshot-for-claude --help
Examples:
  wp-ops scripts/misc/convert-screenshot-for-claude .playwright/screenshots/test.png
```

The path forms still *work* — `Lookup` resolves a full key, and always has —
so nothing is broken for someone who pastes one. They are wrong in that they
teach the long form as the name of the command, three lines under a usage line
that just taught the short one.

One is genuinely broken rather than merely long:

```
$ wp-ops wp-cli-pattern-validate --help
Examples:
  wp-ops bedrock/wp-cli-config/wp-cli-pattern-validate web/app/themes/theme-name/patterns/ --fix

$ wp-ops bedrock/wp-cli-config/wp-cli-pattern-validate --fix
Unknown command or category: bedrock/wp-cli-config/wp-cli-pattern-validate
```

5.0.0 moved that tree under `docs/` and dropped the `bedrock` category. The
command survived the move and resolves as `wp-ops wp-cli-pattern-validate`;
its example still names the path it had two majors ago. This is the same class
of bug 5.1.1 fixed in `README.md` — the `bedrock` category documented after
its removal — and it was missed because nobody thought to grep the *scripts*
for the retired category name.

## 2. Why 5.1.0 and 5.1.1 did not catch this

Two different mechanisms produce the two blocks, and only one was migrated.

| | Usage line | Examples block |
| --- | --- | --- |
| Source | Computed at render time | Verbatim string from the source file |
| Code | `exec.UsageLine(e)` → `e.CommandName()` → `ShortName` | `manifest.go:210` appends `@example` value; `help.go:110`/`161` prints it unchanged |
| Effect of 5.1.0's short-name work | Every command, every executor, all at once | None |
| Effect of a rename | Follows automatically | Silently goes stale |

`ShortName` is computed in `catalog.Load` from basename uniqueness across the
whole catalog (`catalog.go:134-143`), so the usage line cannot be wrong by
construction — which is precisely why 5.1.0's fix was one small change and
`TestLoad_ShortNameUniqueBasenames` can pin it. The example block has no such
invariant. It is a comment in a shell script, and a comment is only as correct
as the last person to read it.

That asymmetry also explains 5.1.1's webp rename. Renaming
`scripts/images/convert-to-webp` → `jpg-to-webp` fixed both files' usage lines
for free. Their `@example` lines had to be edited by hand — and were, because
that rename was the whole subject of the PR. Nothing generalizes that to the
41 other commands nobody was looking at.

## 3. The measured inventory

Counted from `go/internal/catalog/catalog.json` (the generated catalog, so
this is exactly what the binary prints), plus `grep` over the Go sources.

### A. `@example` annotations — 42 entries, 47 lines

The bulk of it. These are the lines the user sees.

| Top-level directory | Entries with a stale example |
| --- | ---: |
| `scripts/` | 27 |
| `wp-cli/` | 13 |
| `trellis/` | 2 |
| **Total** | **42** of 71 entries that carry examples |

Notably clean: **all 10 `trellis/backup/` and `trellis/monitoring/`
playbooks**, every `scripts/images/svg-*` command, and the `wp-cli/seo/`
commands added most recently (`noindex-expired-posts`, `orphan-links-audit`).
The clean set is the recently-authored set — this is drift, not a convention
nobody ever followed. The `.yml` playbooks are clean because their examples
were rewritten wholesale when the Ansible executor moved from `-e site=…` to
positional arguments.

Full list in [Appendix A](#appendix-a-the-47-lines).

### B. Go call sites still formatting `e.Key` into user-facing text — 4

These are not covered by a sweep of the scripts; they need code changes.

| Site | Emits | Note |
| --- | --- | --- |
| `go/cmd/serverside.go:171` | `wp-ops %s /path/to/access.log` ← `e.Key` | Reached on macOS for the access-log commands |
| `go/cmd/serverside.go:155-156` | `wp-ops trellis/backup/database-pull -e site=example.com -e env=production` | **Wrong twice**: path form, and `-e site=` is no longer the argument syntax — the playbook takes positionals (`wp-ops database-pull example.com production`) |
| `go/internal/exec/ansible.go:231` | `Usage: wp-ops %s %s` ← `e.Key` | Missing-argument error path |
| `go/internal/exec/ansible.go:287` | `Usage: wp-ops %s -e site=<site> …` ← `e.Key` | Unannotated fallback. Dead today (0 of 74 entries are unannotated) but it is the branch a newly-added, not-yet-annotated playbook lands in |

`go/cmd/dispatch.go:362,365` and `go/cmd/search.go:68` also print `e.Key`, but
correctly: the first is the ambiguity message, whose entire job is to show the
disambiguating full names, and the second is a search listing where the path
is the useful discriminator. Leave both. (`go/cmd/list.go:127` already prints
`filepath.Base(e.Key)`, which is the inconsistency that makes `search` output
look odd next to `list` output — worth a follow-up, out of scope here.)

### C. Shell scripts printing invocation hints — 4 lines

| Site | Line |
| --- | --- |
| `scripts/backup/db-backup.sh:56` | `echo "  wp-ops trellis/backup/database-backup -e site=… -e env=…"` |
| `scripts/backup/site-backup.sh:45-46` | same shape, `database-pull` / `files-pull` |
| `trellis/security/check-deny-ips.sh:67` | `echo "$IPS" \| xargs wp-ops trellis/security/check-ips` |

The first two carry the same doubled staleness as `serverside.go:155` — path
form *and* retired `-e` syntax. The third is not a hint but a **real runtime
invocation**: it works, but it is the one place where a future rename of
`check-ips` breaks an actual code path rather than a comment.

### D. Markdown — 2 live, 4 historical

Live and worth fixing:

- `trellis/security/README.md:183, 234`
- `docs/trellis-cli-comparison.md:150` — asserts `wp-ops db-backup --help`
  prints `Usage: wp-ops scripts/backup/db-backup`, which stopped being true in
  5.1.0. That document's own status header says rough edge #1 is fixed, so
  this line contradicts the header four sections above it.

Leave alone: `docs/wp-ops-recommendations.md` (lines 15-22, 56, 78, 220-228)
and `docs/go-mcp-parity.md:43` quote the path form *as the problem being
analyzed*. Rewriting them would destroy the record. `CHANGELOG.md` likewise.

## 4. Root cause, stated once

**The catalog validates its own structure but not its prose.** `catalog.Load`
guarantees `ShortName` resolves. `TestLoad_ShortNameUniqueBasenames` pins that
guarantee. CI even guards the catalog against drift
(`.github/workflows/go-build.yml:58` regenerates and `git diff --exit-code`s
it). But every one of those checks is about the *key*. The `Examples` field
travels from a shell comment, through `manifest.go:210`, into `catalog.json`,
out through `help.go:110`, and onto the user's screen without a single
assertion that the thing it tells them to type exists.

A secondary finding, which argues for putting the check in Go rather than in a
shell one-liner: my first two `grep -rnE` passes over the scripts silently
missed `scripts/git/create-pr.sh`, which has two stale lines. Only counting
from `catalog.json` produced the number that matches reality. A grep-based
audit of this is not trustworthy; a test over the loaded catalog is.

## 5. Options

### Option 1 — sweep the 47 lines, done

Edit the annotations, regenerate, ship.

Fixes today's output, costs an hour, guards nothing. The next command rename
reintroduces it in exactly the way 5.1.1's rename would have, had its two
`@example` lines not happened to be the subject of that PR. **Insufficient
alone.**

### Option 2 — normalize in the generator

Have `catalog/gen` rewrite the command token of each `@example` to the entry's
short name as it builds `catalog.json`.

Attractive: examples become unwrongable, and a rename propagates to them for
free the same way it already propagates to usage lines. Two problems, and the
second is decisive:

1. `ShortName` deliberately is not stored in `catalog.json` — it is a property
   of the catalog as a whole, computed in `Load`, "so persisting it would let
   it go stale the moment a colliding command is added" (`catalog.go:78-81`).
   Normalizing at generation time would bake exactly the value that comment
   refuses to bake.
2. It fixes the screen and leaves the source file lying. These headers are
   read directly at least as often as through `--help` — `head -40
   some-script.sh` is how you read a script you are about to modify. Silent
   rewriting means the file and the output disagree forever, and the file is
   what the next author copies when adding a command.

**Rejected**, but it is the right instinct: the fix should make wrongness
impossible rather than merely absent.

### Option 3 — validate in the catalog package, sweep once (recommended)

Add to `go/internal/catalog/catalog_test.go`, alongside the test that already
pins `ShortName`:

```go
// TestExamplesNameTheCommand pins the other half of what a user reads.
// UsageLine is generated from ShortName so it cannot be wrong; an @example
// is prose, and prose goes stale at every rename. An example whose command
// token is not this entry's ShortName either names an internal key the
// usage line three lines above just contradicted, or — as
// wp-cli-pattern-validate's did between 5.0.0 and 5.1.1 — names a category
// that no longer exists at all.
func TestExamplesNameTheCommand(t *testing.T) { ... }
```

It extracts the token after `wp-ops`, skipping any leading `VAR=value`
environment prefixes (`scripts/patterns/screenshot-patterns`'s example is
`PATTERN_NAMESPACE=mytheme SITE_URL=http://example.test wp-ops
screenshot-patterns hero-dark`), and asserts it equals `e.ShortName`.

Why this shape:

- **It runs already.** CI runs `go test ./...` and regenerates the catalog on
  any change under `scripts/`, `trellis/`, `wp-cli/`, `mcp-server/`, or
  `docs/` (`go-build.yml:14-30`). No new infrastructure, no new workflow step,
  no pre-commit hook to install.
- **It fires at the right moment.** Renaming a script changes its key, which
  changes `ShortName`, which fails the test in the same PR as the rename —
  which is the only moment the fix is cheap.
- **It is also the audit.** Run it today and it names all 42 entries. It is
  the checklist for the sweep and the guard afterward, and there is no window
  where the guard exists but the sweep has not landed, because the test is red
  until it does.
- **It works post-`Load`,** so it reads the real `ShortName` without
  persisting it — respecting the constraint that rules out Option 2.

Deliberately *not* enforced by the test: that an example references only its
own command. `check-deny-ips` legitimately mentions `check-ips`, and a rule
against cross-references would either ban that or need a whitelist. The
first-token rule covers the actual bug and stays a five-line assertion.

## 6. Recommendation

Option 3, as three commits.

1. **`Add a test pinning @example lines to the command's short name`** — the
   test alone, red. Small, and it states the invariant in one place.
2. **`Name commands by what you type in every @example`** — the 47-line sweep
   plus `go generate ./...`, turning it green. Mechanical; one commit is
   correct here despite the atomic-commit rule, because it is one change
   applied 47 times.
3. **`Stop printing internal keys in ansible and server-side guidance`** — the
   four Go sites from §B (`e.Key` → `e.CommandName()`), the two backup hints
   corrected to positional Ansible syntax, `check-deny-ips.sh:67`, and the two
   `trellis/security/README.md` lines.

Then fix `docs/trellis-cli-comparison.md:150` as part of 3 or as a fourth
one-line commit, and leave the historical documents alone.

Expected end state: `wp-ops <anything> --help` names a command that resolves,
in the usage line and in every example, enforced by a test rather than by
whoever remembers.

## 7. Open question worth settling in the same pass

`search` prints full keys (`search.go:68`) and `list` prints bare basenames
(`list.go:127`), so the same command appears under two different names
depending on how you found it. Neither is wrong on its own terms — search
results benefit from the disambiguating path, browse results from brevity —
but `CommandName()` now exists as the answer to "what do I call this," and two
of the three listings do not use it. Worth deciding, but it is a UX call
rather than a correctness one, and this document does not need to make it.

---

## Appendix A: the 47 lines

42 entries. Where a file appears twice it has two example lines.

```
scripts/git/create-pr.sh:27,28
scripts/git/gh-traffic.sh:18
scripts/git/git-log-oneline.sh:32
scripts/images/batch-resize.sh:42
scripts/images/make-square-webp.sh:15
scripts/images/openverse_download.py:16
scripts/images/openverse_search.py:17
scripts/misc/convert-screenshot-for-claude.sh:28
scripts/misc/find-and-replace-files.sh:36
scripts/misc/post-count.sh:53
scripts/monitoring/404-checker.sh:25,26
scripts/monitoring/cf7-smoke-test.js:26
scripts/monitoring/redirect-check.sh:12
scripts/monitoring/remote-ttfb-ua.sh:24
scripts/monitoring/server-monitor.sh:20
scripts/monitoring/ttfb-test.sh:22
scripts/patterns/center-screenshots.sh:21
scripts/patterns/screenshot-patterns.sh:38     ← has an env-var prefix
scripts/patterns/screenshot-url.js:38
scripts/patterns/trim-screenshots.sh:19
scripts/release/deploy-plugin-wporg.sh:66
scripts/release/release-plugin.sh:31
scripts/release/release-theme.sh:33
scripts/release/upload-release-asset.sh:23
scripts/sync/rsync-package-to-site.sh:49
scripts/sync/rsync-theme.sh:37
scripts/woocommerce/create-product-variations.sh:28,29
trellis/security/check-deny-ips.sh:24,25
trellis/security/check-ips.sh:19
wp-cli/content-creation/import-page-draft.sh:36,37
wp-cli/content-creation/page-creation.sh:24
wp-cli/content-creation/wp-cli-pattern-validate.php:50   ← names retired `bedrock/`
wp-cli/diagnostics/diagnostic-transients.php:13
wp-cli/diagnostics/list-posts-count.sh:9
wp-cli/security/scanner-general.php:41
wp-cli/security/scanner-targeted.php:35
wp-cli/security/scanner-wrapper.php:21
wp-cli/seo/blog-audit.sh:25
wp-cli/seo/orphan-pages-audit.sh:25
wp-cli/seo/page-audit.sh:25
wp-cli/seo/redirect-audit.sh:27
wp-cli/seo/schema-audit.sh:24
```

`go/internal/manifest/testdata/{db-backup.sh,database-backup.yml,redirect-audit.sh}`
also carry path-style examples. Those are parser fixtures, not commands — the
manifest parser must keep accepting the form. Leave them, and keep them out of
any sweep regex.

## Appendix B: reproducing the count

Do not grep the scripts — it under-reports (§4). Count from the generated
catalog:

```bash
cd go && go generate ./...
python3 - <<'PY'
import json, re
entries = json.load(open('internal/catalog/catalog.json'))
token = re.compile(r'^(?:[A-Za-z_][A-Za-z0-9_]*=\S+\s+)*wp-ops\s+(\S+)')
lines = 0
for e in entries:
    bad = [x for x in (e.get('examples') or [])
           if (m := token.match(x)) and '/' in m.group(1)]
    if bad:
        lines += len(bad)
        print(e['key'])
print('stale entries:', sum(1 for _ in ()), 'lines:', lines)
PY
```

At 3a53555 this prints 42 keys and `lines: 47`. After the sweep it should
print nothing — and once the test from §5 exists, this script is redundant.
