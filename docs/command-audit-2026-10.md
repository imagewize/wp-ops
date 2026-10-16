# Command Audit: Keep, Cut, Merge

> **Status:** Draft for review, 2026-10-16. Nothing in this document is implemented. It proposes what to do; each action ships as its own PR after sign-off.
> **Scope:** The 81 CLI commands and 21 MCP tools in 5.30.1.
> **Related:** [wp-ops-recommendations.md](wp-ops-recommendations.md) (gaps), [mcp-server-recommendations.md](mcp-server-recommendations.md) (MCP roadmap), [category-organization.md](category-organization.md) (grouping)

## Why

Usage is concentrated in a small core. Every registered MCP tool also costs context tokens in each Claude session, whether or not it is called. Before adding more, find out what earns its place.

## Evidence and its limits

Measured from the `seo-strategy` repo, which is the heaviest consumer:

- 123 Claude Code session transcripts, **Sep 15 to Oct 16, 2026 only** (older transcripts are gone). Counted real `tool_use` blocks, not text mentions.
- Mentions across the repo's logs and docs, which reach back to Nov 2025.
- zsh and Warp shell history.

**Blind spots.** Other repos (nynaeve, elayne, plugins, client sites) are not measured. No MCP calls to wp-ops turned up in other projects' transcripts, but Release, Images, Sync and Git `create-pr` are the groups most likely to be used there. Treat "zero uses" as "zero uses in `seo-strategy`", and confirm elsewhere before removing anything.

## Usage snapshot

| Tool | Calls (last month) | Notes |
|---|---|---|
| MCP `wp_cli` | 446 across 40 sessions | The workhorse |
| CLI `import-page-draft` | 196 across 30 sessions | |
| CLI `svg-to-jpg` | 115 across 23 sessions | `svg-to-png` is documented in the repo but barely called |
| MCP `publish_post` / CLI `publish-post` | 51 / 42 | Two interfaces, one job |
| MCP `db_backup` | 34 across 22 sessions | |
| MCP `ssh_command` / `scp_file` | 32 / 11 | |
| MCP `verify_post` / CLI `verify-post` | 22 / 7 | |
| CLI `gh-traffic` | ~140 shell history entries, 5 transcript calls | Run by hand in the terminal |
| CLI `traffic-report` / `traffic-monitor` | 17 / 8 | `traffic-monitor` over SSH is the documented quick check |
| CLI `rsync-package-to-site` | 8 | |
| MCP `monitor`, `url_audit`, `ip_reputation_check`, `db_pull`, `server_status` | 1 to 3 each | |
| MCP `schema_audit`, `redirect_audit`, `security_scan`, `broken_link_audit`, `store_audit`, `remote_ttfb_audit`, `files_pull`, `admin_user_create` | 0 | `schema_audit`, `redirect_audit` and `security_scan` appear in older repo notes, so they run periodically |

## Keep

Core, in regular use, no change:

- MCP: `wp_cli`, `publish_post`, `verify_post`, `db_backup`, `ssh_command`, `scp_file`, `command_search`, `command_run`.
- CLI: `import-page-draft`, `publish-post`, `verify-post`, `svg-to-jpg`, `svg-to-png`, `gh-traffic`, `traffic-monitor`, `ai-bot-monitor`, `db-backup`, `db-pull`, `files-pull`, `ssl-check`, `rsync-package-to-site`, `orphan-links-audit`, `schema-audit`, `redirect-audit`, `blog-audit`.
- MCP `monitor`, `url_audit`, `db_pull`, `server_status`, `ip_reputation_check`: low volume, but each does something no other tool does.

`command_search` and `command_run` are the catalog bridge from [mcp-server-recommendations.md](mcp-server-recommendations.md). They are what makes it safe to drop a dedicated MCP tool: the underlying CLI command stays reachable through the bridge. Do not cut them.

## Cut

Candidates for removal. Each needs the cross-repo check noted in the last column.

| Item | Why | Check before removing |
|---|---|---|
| `noindex-expired-posts` | Sets Yoast's noindex. imagewize.com uses The SEO Framework, so it does nothing here | Is any client site on Yoast and using it? |
| `openverse_search`, `openverse_download` | No use found | Used for theme demo imagery in elayne? |
| `batch-resize`, `jpg-to-webp`, `make-square-webp` | No use found; `svg-to-jpg` covers the featured-image workflow | Used for theme or plugin screenshots? |
| `create-product-variations` | No use found | Client WooCommerce work? |
| `updraft-to-valet` | One-off bootstrap helper | Used for the WorkCycles sandbox in Aug 2026? |
| `convert-screenshot-for-claude` | Workaround for a VS Code extension bug | Still needed after Claude Code updates? |
| `find-and-replace-files` | One-off utility | Any caller? |
| `list-posts-count`, `post-count` | Hardcoded `example.com` path; `wp_cli` does this in one call | None expected |
| `screenshot-url`, `screenshot-patterns`, `center-screenshots`, `trim-screenshots`, `png-to-webp` | Pattern screenshot toolkit, no use here | Elayne pattern screenshots may depend on it |
| MCP `admin_user_create` | 0 real calls; creating admins is a destructive action best left to `wp_cli` with explicit `confirm` | Incident recovery use (see Aseonomics, Sep 2026)? Keep the CLI script either way |
| MCP `store_audit` | 0 calls and shipped 5.29.0, three days before this audit. The CLI `store-audit` gate is the part CI users need | Wait for real adoption before judging |
| MCP `broken_link_audit`, `remote_ttfb_audit` | 0 calls | Reachable through `command_run` if needed |

Cutting an MCP tool does not remove the CLI command behind it. Of the MCP tools, `files_pull` also has 0 calls, but it is the only way for an agent to pull uploads, so keep it for now.

## Merge

Overlapping tools that do the same job. Pick one canonical name, keep the others as aliases for a deprecation window, then remove.

| Family | Members | Proposed canonical |
|---|---|---|
| Database backup | `db-backup` (SSH, straight to your machine), `database-backup` (Ansible), `wp-db-backup`, `site-backup` | `db-backup`. Keep `site-backup` only for full Trellis-site backups (database, uploads, config) |
| Database pull | `db-pull`, `database-pull` | `db-pull` |
| Database push | `database-push` | Keep; no overlap, but name it `db-push` for symmetry |
| Files | `files-backup`, `files-pull`, `files-push` | Keep as is |
| Security scanning | `security-scan`, `security_scan` (MCP), `malware-scan`, `scanner-general`, `scanner-targeted`, `scanner-wrapper` | `malware-scan` as the one entry point; scanners become internal. Fix wp-ops#222 first |
| Traffic | `traffic-report` (Ansible, slow), `traffic-monitor`, `traffic-by-country`, `quick-status`, `server-monitor` | `traffic-monitor` for traffic; `server-monitor` for host health; drop `traffic-report` and `quick-status` |
| MCP and CLI pairs | `publish_post` and `publish-post`, `verify_post` and `verify-post` | Keep both interfaces; they share code, so there is no maintenance cost |

## Proposed order of work

1. **Docs only (this PR).** Agree on the list.
2. **Add a `deprecated` field** to the script manifest header, shown in `wp-ops list` and `--help`, so removal has a visible warning period. There is no such mechanism today.
3. **Mark the Merge losers and the Cut candidates as deprecated** in one release.
4. **Remove** after one or two releases, once the cross-repo checks are done.
5. **Trim the MCP tools** (`admin_user_create`, `broken_link_audit`, `remote_ttfb_audit`) in a separate release, since MCP clients load the tool list at process start.

## Open questions

- Which repos outside `seo-strategy` call wp-ops, and which commands do they use? A one-off `grep -r "wp-ops "` across `~/code` would answer most of this.
- Is anyone else running wp-ops? The Homebrew tap is public, so removals are breaking changes for them. If so, steps 2 and 3 matter more.
- Should `gh-traffic` stay in wp-ops? It is used constantly, but it is a GitHub utility, not a WordPress one.
