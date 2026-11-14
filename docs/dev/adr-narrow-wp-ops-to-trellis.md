# ADR: Narrow wp-ops to a Trellis front door, and stop shipping generic remote access as a headline

**Status:** Accepted, 2026-11-15, in progress. Work lands on the `adr/narrow-to-trellis`
branch in batches, one PR and one version per batch, not one PR per fix. See
[Progress](#progress) for what has shipped.
**Related:** [command-audit-2026-10.md](command-audit-2026-10.md) (what was cut),
[trellis-extensions-evaluation.md](trellis-extensions-evaluation.md) (the `trellis ops` plugin, shipped),
[wp-cli-package-evaluation.md](wp-cli-package-evaluation.md) (why the scanners and audits stay standalone),
[mcp-server-recommendations.md](mcp-server-recommendations.md),
[db-pull vs database-pull](#open-questions)

## Context

wp-ops is a 938-commit repo that ships a Go CLI, an MCP server, Ansible playbooks,
roughly 40 shell scripts and some PHP. The question raised on 2026-11-15: most people
do not want another tool that runs shell scripts for backup, traffic checks and post
creation. The Trellis-focused repositioning (README now opens with "The day-to-day ops
layer for Trellis sites") is the only change that has produced visible interest, one
extra GitHub star. Should the repo be split into a WP-CLI package plus shell scripts
and a trellis-cli extension?

### Evidence: what is actually used

Counted from real `tool_use` blocks in the 296 Claude Code session transcripts kept on
this machine (117 of them touched wp-ops). Transcripts reach back only to about
October 2026, so this is a recent snapshot, not history. Same method and caveats as the
[October audit](command-audit-2026-10.md#evidence-and-its-limits).

| MCP tool | Calls | Share of ~1,000 |
| --- | --- | --- |
| `wp_cli` | 570 to 655 | about 65% |
| `publish_post` + `verify_post` | about 140 | about 15% |
| `db_backup` | 55 | |
| `ssh_command` | 50 | |
| `scp_file` | 41 | |
| `url_audit`, `files_pull`, `store_audit`, `security_scan`, `db_pull` | 10 to 14 each | |
| `monitor`, `server_status`, `schema_audit` | 12 combined | |

- By project, `seo-strategy` is about 80% of MCP calls. `imagewize.com` is next,
  with `elayne` and `elayne-legal` at about 80 calls combined. `elayne` uses wp-ops only
  for `wp_cli` and the `rsync-package-to-site` script.
- `rsync-package-to-site` is the most used script (about 274 mentions in the three
  projects above alone, and about 170 calls across ten repos in the October audit).
  `db-pull`, `svg-to-jpg`, `import-page-draft` and `publish-post` follow.
- Traffic and security reads, the thing the README sells in section 2, total about
  22 MCP calls. They are not what the heaviest user reaches for.
- I found no wp-ops calls in `aviendha` or `nynaeve`, and 3 in `winespring`.

In practice wp-ops is used as: (1) a remote shell for WP-CLI, (2) post publish and
verify, (3) a backup before risky edits, (4) rsync of themes and packages to sites.

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
   backup commands the front-page story. `db-pull` and `database-pull` stay as
   documented in [db-pull-vs-database-pull](#open-questions); add a shell `db-push` so
   the playbooks can be deprecated rather than the shell scripts.
2. **Treat the MCP server as an adapter, not a product.** Keep it, with its safety
   layer (the read-only `ssh_command` allowlist). Say plainly in its README that
   `wp_cli`, `ssh_command` and `scp_file` are generic and have alternatives, and that
   the Trellis-aware tools (`db_pull`, `files_pull`, `publish_post`, `verify_post`,
   `db_backup`) are the reason to use it. Do not add more generic tools.
3. **Keep audits and scanners standalone.** No WP-CLI rewrite. Per the package
   evaluation they stay curl and PHP scripts.
4. **Move non-WordPress personal scripts out of the repo.** `svg-to-jpg`,
   `find-and-replace-files`, `git-log-oneline` and `create-pr` have no WordPress or
   Trellis audience. `svg-to-png`, `convert-screenshot-for-claude` and
   `updraft-to-valet` were already deprecated on this basis. Candidates for a personal
   scripts repo; each needs the October audit's deprecation window first.
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
- **Not decided here:** whether to publish a second WP-CLI package. The evaluation's
  next candidate, a thin WP-CLI front end over the scanners that wraps and does not
  replace them, stays optional and gated on step 6.

## Open questions

1. **Where does `rsync-package-to-site` belong?** It deploys a theme or plugin to a
   demo or main site, which is the most common use here, but it is not
   Trellis-specific. Options: keep under a `wordpress` platform tag, or document it as
   a Trellis theme-deploy step. Needs a decision before step 4 shrinks the surface.
2. **Is one star enough signal?** It is one data point. Step 6 exists to avoid acting
   on it alone.
3. **Does a generic MCP tool earn its context cost?** `wp_cli` is 65% of my usage but
   alternatives exist. If another server covers it with equal safety, retiring it from
   wp-ops would cut tokens per session. Needs a safety comparison, not a guess.
4. **Counting method.** Transcripts show only recent months and only calls made through
   Claude Code. Hand-run terminal use and Mistral Vibe sessions are not counted.

## Next steps

| Step | Size | Ships as |
| --- | --- | --- |
| README and MCP README reposition (steps 1 and 2) | small | docs-only, direct to `main` |
| Shell `db-push`, then deprecate playbook pull | medium | PR, patch or minor bump |
| Deprecate non-WordPress personal scripts (step 4) | small | PR, one per script group |
| Re-count usage and decide on step 6 | small | update this ADR |

## Progress

| Step | State |
| --- | --- |
| 1. Lead with `trellis ops` (done) | README reworded (b24c731). Trellis project detection no longer prompts from the project root (5.45.3). Shell `db-push` written on this branch and tested by a round trip on `demo.imagewize.com` production (multisite): pull, restore the local-only `koffie` subsite, push. The first push hit a foreign key and was restored from its own backup; fixed with foreign-key checks off and automatic restore. The `database-pull`/`database-push` playbooks are deprecated and README section 1 shows `db-pull`/`db-push`. The README GIF shows `trellis ops db-pull` (tape in `assets/screenshots/db-pull.tape`). Step 1 is done; removing the deprecated playbooks waits a release or two |
| 2. MCP as an adapter | MCP README groups the tools and labels `wp_cli`, `ssh_command` and `scp_file` as generic remote access (on this branch) |
| 3. Audits and scanners stay standalone | No change needed |
| 4. Move personal scripts out | Not started |
| 5. `rsync-package-to-site` stays | Open question below |
| 6. Re-count usage | Due about 2026-12-15 |

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
