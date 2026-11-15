# ADR: Narrow wp-ops to a Trellis front door, and stop shipping generic remote access as a headline

**Status:** Accepted, 2026-11-15, in progress. Work lands in batches, one branch, one PR
and one version per batch, not one PR per fix. The first batch shipped as 5.46.0
(PR #290, branch `adr/narrow-to-trellis`); the next batch gets a new branch. See
[Progress](#progress) for what has shipped.
**Related:** [command-audit-2026-10.md](command-audit-2026-10.md) (what was cut),
[trellis-extensions-evaluation.md](trellis-extensions-evaluation.md) (the `trellis ops` plugin, shipped),
[wp-cli-package-evaluation.md](wp-cli-package-evaluation.md) (why the scanners and audits stay standalone),
[mcp-server-recommendations.md](mcp-server-recommendations.md),
[CHANGELOG 5.46.0](../../CHANGELOG.md) (the playbook deprecation)

## Context

wp-ops is a 938-commit repo that ships a Go CLI, an MCP server, Ansible playbooks,
roughly 40 shell scripts and some PHP. The question raised on 2026-11-15: most people
do not want another tool that runs shell scripts for backup, traffic checks and post
creation. The Trellis-focused repositioning (README now opens with "The day-to-day ops
layer for Trellis sites") is the only change that has produced visible interest, one
extra GitHub star. Should the repo be split into a WP-CLI package plus shell scripts
and a trellis-cli extension?

### Evidence: what is actually used

Counted from real `tool_use` blocks in the Claude Code session transcripts kept on
this machine. Transcripts reach back only to about October 2026, so this is a recent
snapshot, not history. Same method and caveats as the
[October audit](command-audit-2026-10.md#evidence-and-its-limits).

**Recount, 2026-11-15.** The first count (`wp_cli` 570 to 655 of about 1,000) counted
lines, and resumed and forked sessions repeat earlier calls in their transcripts. The
recount below counts each `tool_use` ID once, across every `.jsonl` under
`~/.claude/projects`, including subagent transcripts. Use the same method at step 6.

| MCP tool | Calls | Share of 557 |
| --- | --- | --- |
| `wp_cli` | 398 | 71% |
| `publish_post` + `verify_post` | 70 | 13% |
| `ssh_command` | 29 | |
| `db_backup` | 23 | |
| `scp_file` | 16 | |
| `store_audit`, `security_scan`, `url_audit`, `db_pull`, `files_pull`, `monitor` | 3 to 4 each | |
| `command_search`, `schema_audit` | 1 each | |

What the 398 `wp_cli` calls ran: `post list` 61, `post meta` 52 (37 updates, mostly
The SEO Framework titles and descriptions), `eval` 52 (applying Elayne style
variations to global styles), `option` 34, `plugin list/get` 28, `db query` 26,
`post get` 26, `search-replace` 25 (13 dry runs, 12 live), `theme` 21, `cache flush`
15. 358 went to production, 39 to development; about 81 production calls wrote
something. By site: imagewize.com 263, demo.imagewize.com 123, aseonomics.com 12.

**WP-CLI outside wp-ops.** In the same transcripts, 312 to 446 Bash calls ran `wp`
directly (the low figure drops calls whose `wp` sits in a heredoc, a commit message
or a Python edit). 163 went through `trellis vm shell` to development, 113 over `ssh`
to a remote, 36 ran locally (`wp i18n`, Valet). Top commands: `post get` 43,
`db query` 34, `eval` 33, `eval-file` 24, `post list` 23, `option get` 20. So for
production the MCP tool is used about three times as often as raw `ssh … wp`, and for
development raw `trellis vm shell -- wp` is used about four times as often as the
tool. Raw `wp` wins when a call chains several commands, pipes into `grep` or `curl`,
or feeds SQL or PHP from a file, none of which the one-command `wp_cli` tool does.

**By repository** (Claude Code sessions only):

| Repo | Sessions | wp-ops MCP | wp-ops scripts via Bash | Raw `wp` via Bash |
| --- | --- | --- | --- | --- |
| `seo-strategy` | 141 | 436, `wp_cli` 300 | `svg-to-jpg` 114, `import-page-draft` 57, `publish-post` 33, `svg-to-png` 24, `checkout-check` 23, `update-snapshot` 14, `rsync-package-to-site` 14, `traffic-monitor` 13 | 186 to 284 |
| `winespring` | 12 | 1 | `rsync-package-to-site` 50 | 35 to 48 |
| `aludra` | 10 | 1 | `rsync-package-to-site` 37 | 37 to 58 |
| `elayne` | 6 | 35, all `wp_cli` | `rsync-package-to-site` 36 | 6 to 11 |
| `nynaeve` | 1 | none | none | none |
| `aviendha`, `ixian` | 0 | none | none | none |

- `seo-strategy` is the only repo that uses wp-ops as a product. Every theme and
  plugin repo uses it for one thing, `rsync-package-to-site`, and their `CLAUDE.md`
  or `AGENTS.md` documents that. `aviendha` and `ixian` have no Claude Code sessions
  here, so any use there is by hand or through Vibe.
- `svg-to-jpg`, deprecated in 5.46.0, is the most used script in `seo-strategy`, and
  63 files there reference it. It now lives in `seo-strategy/tools/scripts/` (PR #37
  there), and its live references point to that copy, so removing it here breaks
  nothing.
- Traffic and security reads, the thing the README sells in section 2, total about
  10 MCP calls plus a dozen `traffic-monitor` runs. They are not what the heaviest
  user reaches for.

In practice wp-ops is used as: (1) a remote shell for WP-CLI on production, (2) post
publish and verify, (3) a backup before risky edits, (4) rsync of themes and packages
to sites. Development WP-CLI does not go through it at all.

### Evidence: what already exists

| Need | Existing tools |
| --- | --- |
| WP-CLI over SSH as MCP | wp-cli-mcp (SSH, multisite), mcp-wp-cli-terminus (SSH, Pantheon, Docker, cross-environment post copy), wpxmcp, rnaga/wp-mcp |
| Pull production DB to local | wp-cli-move, wp-cli-deploy, WP Migrate (`wp migrate pull`), Wordmove, plain WP-CLI aliases |
| Provision and deploy Trellis | trellis-cli (no pull, push, traffic or content commands) |

Generic remote WP-CLI and SSH access is commodity. Trellis-aware pull and push, and
content verification, are not covered by any of them.

### What is distinctive

- **Trellis awareness:** site name resolves to host, path and `.test` domain from
  `wordpress_sites.yml`. Pull backs up the dev database first, rewrites URLs, keeps
  dumps. Push backs up the remote first. `trellis-updater` does a three-way merge.
- **Content verification:** `verify-post` checks blocks, JSON-LD and links survive the
  write and the live render.
- **Update safety:** `update-snapshot` and `update-compare`, `checkout-check`.

## Options considered

**A. Status quo.** One repo, one binary, full catalog. Rejected: the README already
leads with Trellis, but the catalog and MCP surface still read as a grab bag.

**B. Split into three repos** (Trellis extension, WP-CLI package, shell scripts).
Rejected for now. Reasons, all from existing evidence:

1. The [WP-CLI package evaluation](wp-cli-package-evaluation.md) found that only
   `pattern-validate` uses the WP-CLI API, and it is already published. The scanners
   deliberately run without WP-CLI because the target is compromised shared hosting.
   `schema-audit` and `redirect-audit` need only `curl`. Wrapping them in WP-CLI would
   shrink their audience.
2. `publish-post` runs from a laptop over SSH, uploads an image and verifies the live
   page. A WP-CLI package runs on the server and cannot do the laptop side. It could
   only cover the narrow `wp post create` step.
3. The `trellis ops` plugin already exists. A separate Go extension repo would
   duplicate the binary, the catalog and the release pipeline.
4. Three repos triple release, CI and install overhead for a project with one
   maintainer and roughly one weekly user.

**C. Narrow in place** (chosen below).

## Decision

Keep one repository and one binary. Change what it leads with and what it carries.

1. **Lead with `trellis ops` for pull, push and checks.** Make
   `trellis ops database-pull`, `files-pull`, `database-push`, `files-push` and the
   backup commands the front-page story. Add a shell `db-push` so the
   `database-pull` and `database-push` playbooks can be deprecated rather than the
   shell scripts (done in 5.46.0: `db-pull` and `db-push` are the documented
   commands, the playbooks print a deprecation notice).
2. **Treat the MCP server as an adapter, not a product.** Keep it, with its safety
   layer (the read-only `ssh_command` allowlist). Say plainly in its README that
   `wp_cli`, `ssh_command` and `scp_file` are generic and have alternatives, and that
   the Trellis-aware tools (`db_pull`, `files_pull`, `publish_post`, `verify_post`,
   `db_backup`) are the reason to use it. Do not add more generic tools.
3. **Keep audits and scanners standalone.** No WP-CLI rewrite. Per the package
   evaluation they stay curl and PHP scripts.
4. **Move non-WordPress personal scripts out of the repo, into wpvilla.in posts.**
   A script with no WordPress or Trellis audience becomes a blog post that carries the
   script, the same way the guides moved. `svg-to-png`, `convert-screenshot-for-claude`
   and `updraft-to-valet` were already deprecated on this basis. Each keeps the October
   audit's deprecation window before removal. Tooling the repo itself relies on
   (`create-pr`, and `find-and-replace-files`, which syncs its copies) stays.
5. **Keep `rsync-package-to-site` in the repo for now.** It is the most used script
   and ten repos depend on it, but it is not Trellis-specific. See open questions.
6. **Measure before splitting anything further.** Revisit this ADR after one month
   with the same transcript count, plus GitHub release download counts and Homebrew
   installs, and decide on a second package only if a distinct audience shows up.

## Consequences

- **Positive:** a clearer pitch for the audience that responded; no new repos; no
  breaking renames; the safety work on the MCP layer is kept.
- **Negative:** the catalog is still large and the generic MCP tools still cost
  context tokens in every session. Step 2 only relabels them, it does not remove them.
- **Risk:** removing the personal scripts breaks muscle memory and cross-repo
  references. The October audit's mapping tables and deprecation window apply.
  `svg-to-jpg` was the concrete case; `seo-strategy` now carries its own copy.
- **Not decided here:** whether to publish a second WP-CLI package. The evaluation's
  next candidate, a thin WP-CLI front end over the scanners that wraps and does not
  replace them, stays optional and gated on step 6.

## Open questions

1. **Where does `rsync-package-to-site` belong?** It deploys a theme or plugin to a
   demo or main site, which is the most common use here, but it is not
   Trellis-specific. Options: keep under a `wordpress` platform tag, or document it as
   a Trellis theme-deploy step. Needs a decision before step 4 shrinks the surface.
   *Decided 2026-11-15: keep it, tagged `wordpress`, and do not count it toward the
   Trellis pitch.* It syncs a theme or plugin working copy into a Bedrock site
   (`plugin` or `theme` only, not Composer packages), and it is the only reason the
   theme and plugin repos depend on wp-ops. About 200 runs from nine repos, by
   package: `elayne-legal` 51, `aludra` 44, `winespring` 36, `elayne` 31, `ecotuin` 9,
   `waygate` 5, `aviendha` 2, `warder-cookie-consent` 1. Eleven repos document it in
   `CLAUDE.md` or `AGENTS.md`. `aviendha` and `ixian` document it in `AGENTS.md` with
   a hard-coded `/Users/j/code/...` path that does not exist here, while their
   `CLAUDE.md` uses `wp-ops rsync-package-to-site`.
2. **Is one star enough signal?** It is one data point. Step 6 exists to avoid acting
   on it alone.
3. **Does a generic MCP tool earn its context cost?** `wp_cli` is 71% of MCP calls,
   but alternatives exist, and raw `wp` through `ssh` or `trellis vm shell` runs about
   as often in total (312 to 446 calls). About three quarters of the `wp_cli` calls are
   plain reads or single meta writes that any WP-CLI MCP server or plain `ssh` does.
   What it adds is the site-name lookup and the safety layer on production writes. If
   another server covers that with equal safety, retiring it from wp-ops would cut
   tokens per session. Needs a safety comparison, not a guess.
   *Why it was used, checked 2026-11-15:* the repo docs told agents to. The four repos
   with `wp_cli` calls (`seo-strategy`, `imagewize.com`, `elayne`, `elayne-legal`) all
   said to prefer it over raw `ssh`/`wp`, from 2026-08-03 on; `aludra` and `winespring`
   documented only `trellis vm shell -- wp`, and that is what ran there. Blocking was
   not the reason: raw `wp` over `ssh` was refused 5 times in about 150 calls (3 by
   the auto-mode classifier, 2 by me), through `trellis vm shell` 2 in about 220, and
   `wp_cli` 6 times, about as often. After a refused `ssh` call the agent switched to
   `wp_cli` once. The tool's own allowlist refused it 35 more times, 20 of them reads
   or reads in effect (`db query SELECT`, a leading `--url=` that breaks the
   positional check, `wc product list`), and 17 calls failed input validation
   ([#291](https://github.com/imagewize/wp-ops/issues/291)).
   *Done:* the "prefer `wp_cli`" lines in `seo-strategy`, `imagewize.com` and `elayne`
   now say plain `wp` is fine and the tool is optional; the MCP tools stay the advice
   for audits and scans. Re-count at step 6 to see whether `wp_cli` use drops, and
   decide on retiring it then.
4. **Counting method.** Transcripts show only recent months and only calls made through
   Claude Code. Hand-run terminal use and Mistral Vibe sessions are not counted. Count
   each `tool_use` ID once; the first count did not and was about 50% too high.

## Next steps

| Step | Size | Ships as |
| --- | --- | --- |
| README and MCP README reposition (steps 1 and 2) | small | done, 5.46.0 |
| Shell `db-push`, then deprecate playbook pull | medium | done, 5.46.0 |
| Deprecate non-WordPress personal scripts (step 4) | small | first group done, 5.46.0 |
| Move `svg-to-jpg` into `seo-strategy` and repoint its references | small | done, `seo-strategy` PR #37 |
| Retire the `wp_cli` tool (decided 2026-11-15, see Progress); #291 closes with it | small | 5.47.0, [#291](https://github.com/imagewize/wp-ops/issues/291) |
| Re-count usage and decide on step 6 | small | update this ADR, about 2026-12-15 |
| Remove the deprecated playbooks and scripts | small | PR after the re-count |

## Progress

| Step | State |
| --- | --- |
| 1. Lead with `trellis ops` (done) | README reworded (b24c731). Trellis project detection no longer prompts from the project root (5.45.3). Shell `db-push` added in 5.46.0, tested by a round trip on `demo.imagewize.com` production (multisite): pull, restore the local-only `koffie` subsite, push. The first push hit a foreign key and was restored from its own backup; fixed with foreign-key checks off and automatic restore. The `database-pull`/`database-push` playbooks are deprecated and README section 1 shows `db-pull`/`db-push`. The README GIF shows `trellis ops db-pull` (tape in `assets/screenshots/db-pull.tape`). Step 1 is done; removing the deprecated playbooks waits a release or two |
| 2. MCP as an adapter | MCP README groups the tools and labels `wp_cli`, `ssh_command` and `scp_file` as generic remote access (5.46.0) |
| 3. Audits and scanners stay standalone | No change needed |
| 4. Move personal scripts out | `svg-to-jpg` deprecated, now a [wpvilla.in post](https://wpvilla.in/export-svg-designs-jpg-featured-images-rsvg-convert/) with the script; `git-log-oneline` deprecated (it only wraps `git log --oneline`). `create-pr` and `find-and-replace-files` kept, decided 2026-11-15: the repo uses `create-pr` for its own PRs, as do `min` and `ikwedopsport`, and it is too long for a post. Revisit at the re-count |
| 5. `rsync-package-to-site` stays | Decided 2026-11-15: keeps a `wordpress` tag; it is the theme and plugin sync for nine repos (open question 1) |
| 6a. Retire `wp_cli` | Decided 2026-11-15, after the count post ([wpvilla.in branch `post/claude-code-wp-cli-usage`](https://wpvilla.in)): plain `wp` through `ssh` or `trellis vm shell` does everything the tool did and more (pipes, chains, files), and the tool was used mainly because project docs said to. Write approval is not lost: the rule the tool enforced with `confirm: true` now applies to plain `wp` too. Ask the user before any `wp` command that writes (`post update`, `post meta update`, `option update`, `search-replace` without `--dry-run`, `db query` that is not a SELECT, `db import`, `eval` or `eval-file` that changes data, installs and deletes) or reads credentials (`config get`, `db export`), on every route and every environment. Reads and `--dry-run` previews need no approval. Removed in 5.47.0 (branch `remove/wp-cli-mcp-tool`); the `wp-ops` Go CLI never had a `wp_cli` command, only the MCP tool |
| 6. Re-count usage | Method corrected and a first recount done 2026-11-15 (see Evidence). Full re-count with downloads and installs due about 2026-12-15 |

Monitoring polish done along the way, because the README pitch depends on it: monitor
scripts now refresh on the server (5.45.4), `quick-status` and `traffic-report` print a
plain report (5.45.5), and read-only tasks report `changed=0`.

## Sources

- [wp-cli-mcp](https://glama.ai/mcp/servers/mvtandas/wp-cli-mcp)
- [WP-MCP (rnaga)](https://mcpservers.org/es/servers/rnaga/wp-mcp)
- [wp-cli-move](https://packagist.org/packages/n5s/wp-cli-move)
- [wp-cli-deploy](https://github.com/artificer/wp-cli-deploy)
- [WP Migrate and WP-CLI](https://deliciousbrains.com/?p=178764)
- [roots/trellis-cli](https://github.com/roots/trellis-cli)
