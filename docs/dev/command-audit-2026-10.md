# Command Audit: Keep, Cut, Merge

> **Status:** In progress, 2026-10-16. Steps 1 to 5 of the [order of work](#proposed-order-of-work) are done: the audit, the `deprecated` manifest field, 15 commands deprecated in 5.33.0 and removed in 5.34.0 (`release-theme` was removed outright). The three MCP tools were trimmed in 5.35.0. Only the held-back items and open questions remain. The Keep, Cut and Merge tables below are the original draft; the [Status](#status) section records what changed after a closer look. Each remaining action ships as its own PR.
> **Scope:** The 81 CLI commands and 21 MCP tools in 5.30.1.
> **Related:** [wp-ops-recommendations.md](wp-ops-recommendations.md) (gaps), [mcp-server-recommendations.md](mcp-server-recommendations.md) (MCP roadmap), [category-organization.md](category-organization.md) (grouping)

## Why

Usage is concentrated in a small core. Every registered MCP tool also costs context tokens in each Claude session, whether or not it is called. Before adding more, find out what earns its place.

## Evidence and its limits

Measured from the `seo-strategy` repo, which is the heaviest consumer:

- 123 Claude Code session transcripts, **Sep 15 to Oct 16, 2026 only** (older transcripts are gone). Counted real `tool_use` blocks, not text mentions.
- Mentions across the repo's logs and docs, which reach back to Nov 2025.
- zsh and Warp shell history.

Then checked the rest of `~/code` (Oct 16, 2026) two ways: the same transcript scan across every project's Claude history, and a grep for `wp-ops <command>` in `.md`, `.sh`, `.yml`, `.json` and `.py` files outside this repo.

**Cross-repo findings.**

- `rsync-package-to-site` is core: about 170 transcript calls across 10 repos (marin 36, ecotuin 23, min 19, alantin 15, imagewize.com 13, warder-cookie-consent 12, aviendha 11, aludra 8, koffie 5).
- `import-page-draft` is used in `ecotuin` (14 calls) as well as `seo-strategy`.
- `create-pr` (11 mentions), `db-pull` (28) and `files-pull` (9) are used from the `imagewize.com` repo, and its docs also reference `database-backup` (12), `database-pull` (5) and `files-backup` (4).
- `store-audit` has a dependent repo, `store-audit-action`, and is also used from `min`.
- `command_search` is used in `duurzaam-doede` and `ecotuin`.
- wp-ops MCP calls appear only in `seo-strategy`, `imagewize.com`, `ecotuin` and `min`.
- **No Cut candidate below has live use outside this repo.** Their only appearances are was→now mapping tables from the script migration (`imagewize.com/scripts/README.md`, `seo-strategy/tools/scripts/README.md`), which document the old script names, not current use. `setup-monitoring` is the exception: `seo-strategy/RUN.md` tells the reader to run it, so it stays.
- **Release workflows (warder, elayne, nynaeve).** None calls the Release group. Elayne and Warder ship through a GitHub Actions `create-release.yml` that zips the repo and attaches it to a release. Nynaeve's `CLAUDE.md` says `release-theme.sh` "no longer applies" (it resolves the theme inside `imagewize.com`, where Nynaeve is now a git-ignored Composer snapshot, so it would generate an empty changelog), and bumps the four version places by hand. Nynaeve's `AGENTS.md` still tells agents to run it, which contradicts that. Warder publishes to WordPress.org without wp-ops: its own `bin/prepare-svn.sh` stages the `trunk/`, `tags/` and `assets/` layout, then Claude does the SVN steps by hand from the instructions in Warder's `CLAUDE.md` ("Publishing to WordPress.org"). Its `deploy-wporg.yml` workflow was removed, and nothing in the repo references `deploy-plugin-wporg`.

**Remaining blind spots.** Commands run by hand from a terminal in another repo leave no trace unless they reached shell history. Warp and zsh history were checked, but only for the last few weeks to months. A zero here means "no trace found", so the deprecation window in the order of work below is still the safety net.

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
| CLI `rsync-package-to-site` | 8 here, ~170 across 10 repos | Most-used command outside `seo-strategy` |
| MCP `monitor`, `url_audit`, `ip_reputation_check`, `db_pull`, `server_status` | 1 to 3 each | |
| MCP `schema_audit`, `redirect_audit`, `security_scan`, `broken_link_audit`, `store_audit`, `remote_ttfb_audit`, `files_pull`, `admin_user_create` | 0 | `schema_audit`, `redirect_audit` and `security_scan` appear in older repo notes, so they run periodically |

## Keep

Core, in regular use, no change:

- MCP: `wp_cli`, `publish_post`, `verify_post`, `db_backup`, `ssh_command`, `scp_file`, `command_search`, `command_run`.
- CLI: `import-page-draft`, `publish-post`, `verify-post`, `svg-to-jpg`, `svg-to-png`, `gh-traffic`, `traffic-monitor`, `ai-bot-monitor`, `db-backup`, `db-pull`, `files-pull`, `ssl-check`, `rsync-package-to-site`, `create-pr`, `store-audit`, `orphan-links-audit`, `schema-audit`, `redirect-audit`, `blog-audit`.
- MCP `store_audit`: moved here from Cut. The CLI gate has a dependent repo (`store-audit-action`) and the tool shipped only days before this audit.
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
| `release-theme` | **Decided: remove.** Broken for its main user (Nynaeve's `CLAUDE.md` says it no longer applies), and every theme now documents its own release steps, which Claude or Vibe follow directly | Remove the stale `release-theme.sh` instruction from `nynaeve/AGENTS.md` in the same change |
| `release-plugin`, `upload-release-asset`, `sync-extracted`, `deploy-plugin-wporg` | No live use found; Warder and Elayne release through GitHub Actions, and Warder's WordPress.org publishing is `bin/prepare-svn.sh` plus manual SVN | Check for use in other plugin repos (alantin, ecotuin, koffie) |
| `check-ips`, `check-deny-ips` | Only a mapping-table mention; the MCP `ip_reputation_check` covers the same lookup | Trellis deny-list review habit |
| `cf7-smoke-test`, `updown-webhook-handler`, `diagnostic-transients` | No references | Server-side hooks may call them by path, not by name |
| MCP `broken_link_audit`, `remote_ttfb_audit` | 0 calls | Reachable through `command_run` if needed |

Cutting an MCP tool does not remove the CLI command behind it. Of the MCP tools, `files_pull` also has 0 calls, but it is the only way for an agent to pull uploads, so keep it for now.

## Merge

Overlapping tools that do the same job. Pick one canonical name, keep the others as aliases for a deprecation window, then remove.

| Family | Members | Proposed canonical |
|---|---|---|
| Database backup | `db-backup` (SSH, straight to your machine), `database-backup` (Ansible), `wp-db-backup`, `site-backup` | `db-backup`. Keep `site-backup` only for full Trellis-site backups (database, uploads, config). `imagewize.com` docs still reference `database-backup`, so alias it for a release or two and update those docs |
| Database pull | `db-pull`, `database-pull` | `db-pull`. Same alias note: `imagewize.com` docs reference `database-pull` |
| Database push | `database-push` | Keep; no overlap, but name it `db-push` for symmetry |
| Files | `files-backup`, `files-pull`, `files-push` | Keep as is |
| Security scanning | `security-scan`, `security_scan` (MCP), `malware-scan`, `scanner-general`, `scanner-targeted`, `scanner-wrapper` | `malware-scan` as the one entry point; scanners become internal. Fix wp-ops#222 first |
| Traffic | `traffic-report` (Ansible, slow), `traffic-monitor`, `traffic-by-country`, `quick-status`, `server-monitor` | `traffic-monitor` for traffic; `server-monitor` for host health; drop `traffic-report` and `quick-status` |
| MCP and CLI pairs | `publish_post` and `publish-post`, `verify_post` and `verify-post` | Keep both interfaces; they share code, so there is no maintenance cost |

## Status

**Deprecated (5.33.0), removed (5.34.0), 15 commands:** `noindex-expired-posts`, `openverse_search`, `openverse_download`, `batch-resize`, `jpg-to-webp`, `make-square-webp`, `create-product-variations`, `list-posts-count`, `post-count`, `release-plugin`, `upload-release-asset`, `sync-extracted`, `deploy-plugin-wporg`, `cf7-smoke-test`, `diagnostic-transients`. Each has no internal caller and no live use found. They warned on every run in 5.33.0 and were removed in 5.34.0.

**Deprecated (5.38.0), 3 commands:** `svg-to-png`, `convert-screenshot-for-claude` and `updraft-to-valet`, for sitting outside the Trellis, Bedrock and Sage focus. `find-and-replace-files` is now called only by `updraft-to-valet`, so it goes when that does.

**Held back after a closer look.** The tables above were drafted before these were checked, and the findings change them:

| Item | Why it stays for now |
|---|---|
| `database-backup`, `database-pull` | Not duplicates of `db-backup` and `db-pull`. They are the Ansible route, and `db-backup.sh` and `site-backup.sh` both point to them for automated, repeatable runs. The SSH scripts are the one-shot route. Two ways, on purpose. |
| `wp-db-backup` | Backs up any local WordPress site (Valet, Herd, cPanel, Bedrock). A different job from `db-backup`, which pulls from a remote Trellis box. |
| `check-ips`, `check-deny-ips` | `check-deny-ips` calls `check-ips`, and the MCP `ip_reputation_check` mirrors them. It is not a replacement for someone working in a terminal. |
| `updown-webhook-handler` | Invoked by path from the server-side `updown-webhook-receiver.php`, so a deprecation notice would only land in a server log. |
| `find-and-replace-files` | Called by `updraft-to-valet`, which is now deprecated; it goes with it. |
| `svg-to-jpg` | 115 calls across 23 sessions. It is the featured-image workflow, so it stays even though `svg-to-png` is deprecated. |
| Screenshot toolkit (`screenshot-url`, `screenshot-patterns`, `center-screenshots`, `trim-screenshots`, `png-to-webp`) | Elayne pattern screenshots may depend on it. |
| `traffic-report` | 17 calls in the last month in `seo-strategy`, so it is used. The advice to prefer `traffic-monitor` stands. |
| `quick-status` | Not a replacement for `server-monitor` (HTTP status codes and errors, not CPU and memory). |
| Security family (`security-scan`, `malware-scan`, `scanner-*`) | `security-scan` reads Nginx logs and `malware-scan` runs malware scanners. They are different jobs, and wp-ops#222 is still open. |
| MCP `admin_user_create`, `broken_link_audit`, `remote_ttfb_audit` | Removed in 5.35.0, in a separate release because clients load the tool list at process start. The CLI commands stay, reachable through `command_run`. |

## Proposed order of work

1. **Docs only (this PR).** Agree on the list.
2. **Add a `deprecated` field** to the script manifest header, shown in `wp-ops list` and `--help`, so removal has a visible warning period. There is no such mechanism today.
3. **Mark the Merge losers and the Cut candidates as deprecated** in one release.
4. **Remove** after one or two releases, once the cross-repo checks are done.
5. **Trim the MCP tools** (`admin_user_create`, `broken_link_audit`, `remote_ttfb_audit`) in a separate release, since MCP clients load the tool list at process start.

## Open questions

- Is anyone else running wp-ops? The Homebrew tap is public, so removals are breaking changes for them. If so, steps 2 and 3 matter more.
- ~~Should `gh-traffic` stay in wp-ops?~~ No. It moved to [imagewize/gh-traffic](https://github.com/imagewize/gh-traffic) as a `gh` extension (`gh traffic`). Deprecated here in 5.36.0 and removed in 5.39.0.
