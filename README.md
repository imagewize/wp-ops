<div align="center">
  <img src="assets/logo.svg" alt="WordPress Operations Logo" width="128" height="128">
  <h1>WP OPS</h1>
</div>

<div align="center">
wp-ops is a CLI for WordPress operations — deployments, database and files backup, security scanning, monitoring, and content workflows — backed by manifest-driven scripts, Ansible playbooks, and guides, optimized for <a href="https://roots.io/trellis/">Trellis</a>/<a href="https://roots.io/bedrock/">Bedrock</a> workflows.
</div>

## Contents

- [wp-ops CLI](#wp-ops-cli)
- [Trellis](#trellis)
- [Bedrock](#bedrock)
- [WP-CLI](#wp-cli)
- [Nginx](#nginx)
- [Scripts](#scripts)
- [MCP Server](#mcp-server)
- [WordPress Utilities](#wordpress-utilities)
- [Troubleshooting](#troubleshooting)

## wp-ops CLI

The single entry point for everything in this repo — a Cobra binary that auto-discovers commands across every category, groups them by subdirectory, and renders real `--help`, guided prompts, and shell completions from each command's manifest.

```bash
# Recommended: Homebrew
brew install imagewize/tap/wp-ops
wp-ops init                  # install shell completions (one-time)

# Without Homebrew, build from source:
git clone https://github.com/imagewize/wp-ops.git && cd wp-ops
go build -o wp-ops ./go && mv wp-ops /usr/local/bin/   # or anywhere on your PATH
wp-ops init

wp-ops                       # interactive picker
wp-ops --help                # list all categories
wp-ops trellis --help        # list commands in one category
wp-ops <category> <command> [args...]

wp-ops search webp           # find a command by name or description
wp-ops docs oom              # search the guides, not just the commands
wp-ops doctor                # check dependencies and environment
wp-ops <command> --where     # print the path to a command's script
```

`wp-ops` with no arguments opens an interactive picker: categories first, then a fuzzy-filterable command list with a live preview pane (usage, args, examples) — no `fzf` dependency.

Run `wp-ops doctor` first — it reports which of the external tools these scripts rely on (WP-CLI, Ansible, ImageMagick, `gh`, `cwebp`, Node, …) are actually installed, so you find out before a command fails partway through.

`wp-ops init` installs `wp-ops <TAB>` completion for zsh, bash, or fish, auto-detected from `$SHELL`. Worth running right after install — the Homebrew cask this ships as doesn't wire up completions on its own the way a Homebrew formula would.

Two categories resolve their project directory from an environment variable — but you
don't need to export it by hand if you're standing inside the project: wp-ops detects
it by walking up from your current directory and asks before using what it finds.
Setting the variable explicitly is only required when you're running from elsewhere
(e.g. from this repo's own directory) or non-interactively (CI, cron), where there's
no prompt to confirm a detected guess:

```bash
# Ansible playbooks (wp-ops trellis <playbook>) need a Trellis project's ansible.cfg/inventory/group_vars
export TRELLIS_DIR=/path/to/your/trellis
wp-ops trellis database-backup -e site=example.com -e env=production

# WP-CLI scripts (wp-ops wp-cli|bedrock <script>) need a real WordPress/Bedrock install
export WP_SITE_DIR=/path/to/your/bedrock-site
wp-ops wp-cli scanner-wrapper
wp-ops bedrock wp-cli-pattern-validate web/app/themes/your-theme/patterns/ --fix
```

Detection deliberately only matches a project you're actually standing inside, so an
unrelated Trellis checkout sitting next to your current repo won't be picked up.

`nginx/` and `troubleshooting/` contain guides and Nginx config templates rather than runnable scripts; `wp-ops nginx` lists those documents instead of commands.

A good deal of what this repo knows is written down rather than scripted, so `wp-ops docs` searches the prose the way `wp-ops search` searches the catalog:

```bash
wp-ops docs                  # list every guide
wp-ops docs "search-replace" # show matching lines, grouped by document
wp-ops docs oom -w           # whole words only (so "oom" skips "server room")
wp-ops docs oom -l           # paths only, for piping: wp-ops docs oom -l | xargs $EDITOR
```

When `wp-ops search` finds no command for a term, it checks the documentation and points you there.

Everything else runs on your own machine, including the commands that touch a server — Ansible playbooks, `server-monitor`, and `post-count --ssh` all reach out over SSH from here. The exception is the log monitors, which read `/srv/www/<site>/logs/` and `/var/log/` directly and execute on the host. Those are tagged `(server)` in listings and search, and running one locally prints the SSH invocation rather than failing on a missing log path:

```bash
ssh web@example.com 'bash -s' < scripts/monitoring/monitor.sh
ssh root@example.com 'bash -s' < scripts/monitoring/error-monitor.sh example.com 48
```

Nothing needs to be installed on the server for that — the script is streamed to its stdin. The access-log monitors want `gawk` there for accurate time filtering (Ubuntu ships mawk, so `apt install gawk`); without it they fall back to a line-count estimate. `error-monitor` needs neither gawk nor a log path — it takes the domain, and connecting as `root` additionally gets you the systemd sections (critical errors, PHP segfaults, OOM kills) that the `web` user can't read. `wp-ops --json` reports the local/server split as a `runs_on` field.

`wordpress-utilities/` is different: those are copy-paste-into-a-theme snippets, not runnable scripts, so `wp-ops wordpress-utilities <snippet>` prints or clipboard-copies them instead:

```bash
wp-ops wordpress-utilities footer --copy     # copy to clipboard
wp-ops wordpress-utilities footer > footer.php   # redirect into your theme
```

## Trellis

| Tool | Description | Docs |
|------|-------------|------|
| **Updater** | Safely update Trellis while preserving custom configurations | [→](trellis/updater/README.md) |
| **Backup Tools** | Ansible playbooks for database and files backup/push/pull | [→](trellis/backup/README.md) |
| **Provisioning** | Common provisioning commands and workflows | [→](trellis/provision/README.md) |
| **New Machine Setup** | Set up macOS for Trellis development | [→](trellis/provision/NEW-MACHINE.md) |
| **Project Setup** | Clone and configure an existing Trellis/Bedrock project | [→](trellis/provision/PROJECT-SETUP.md) |
| **Monitoring** | Nginx log monitoring for traffic analysis and security threat detection | [→](trellis/monitoring/README.md) |
| **Security** | fail2ban IP blocking, manual deny rules, and AbuseIPDB reputation lookup | [→](trellis/security/README.md) |

## Bedrock

| Tool | Description | Docs |
|------|-------------|------|
| **Local Package Development** | Test an in-development plugin/theme branch in a Bedrock site via a Composer `path` repository, before tagging a release | [→](bedrock/local-package-development/README.md) |
| **WP-CLI Config** | Standard `wp-cli.yml` for Bedrock path setup plus a `wp pattern validate` command for canonicalizing block pattern files | [→](bedrock/wp-cli-config/README.md) |

## WP-CLI

| Tool | Description | Docs |
|------|-------------|------|
| **Content Creation** | Automated page creation and content management workflows | [→](wp-cli/content-creation/README.md) |
| **Migration Tools** | Migrate WordPress sites to Trellis/Bedrock (single and multi-site) | [→](wp-cli/migration/README.md) |
| **URL Update Methods** | WordPress URL update methods for migrations | [→](wp-cli/migration/URL-UPDATE-METHODS.md) |
| **Diagnostics** | Diagnostic tools for transients, caching, and performance | [→](wp-cli/diagnostics/README.md) |
| **Security Scanners** | Dual-scanner suite for malware detection and security auditing | [→](wp-cli/security/README.md) |
| **SEO** | SEO analysis and audit tools for page structure, redirects, schema markup, blog content, and orphan pages | [→](wp-cli/seo/README.md) |

## Nginx

| Tool | Description | Docs |
|------|-------------|------|
| **Image Optimization** | WebP/AVIF configuration with automatic format serving | [→](nginx/image-optimization/README.md) |
| **Browser Caching** | Optimal static asset caching configuration | [→](nginx/browser-caching/README.md) |
| **Redirects** | Redirect configuration for SEO and URL management | [→](nginx/redirects/README.md) |

## Scripts

27 standalone Bash/PHP/Python utilities — full docs, flags, and examples in [scripts/README.md](scripts/README.md).

| Category | Includes | Docs |
|------|-------------|------|
| **Releases & GitHub** | PR creation, plugin/theme release automation, WordPress.org SVN deploy, release asset upload, GitHub traffic stats | [→](scripts/README.md#github-integration) |
| **Monitoring & Security** | Traffic/security/AI-bot monitoring, 404 & redirect checking, CF7 smoke test, updown.io webhooks | [→](scripts/README.md#monitoring-scripts) |
| **Backups** | Trellis-aware database and full-site backups | [→](scripts/README.md#backup-scripts) |
| **Images, WooCommerce & Files** | Batch resize, WebP conversion, square-canvas padding, Openverse image search/download, WooCommerce product variations, theme/package sync, find & replace | [→](scripts/README.md#image-utilities) |
| **Content Reporting** | Published-post counts by year/month | [→](scripts/README.md#content-reporting) |

## MCP Server

Exposes wp-ops operations as [MCP](https://modelcontextprotocol.io) tools, so Claude (and other MCP-compatible clients) can call them directly instead of running the underlying scripts by hand. Scaffold stage — five tools so far (`security_scan`, `db_backup`, `wp_cli`, `redirect_audit`, `schema_audit`), more planned. See [mcp-server/README.md](mcp-server/README.md) for tool details, setup, transports (stdio/Streamable HTTP), and Docker usage.

## WordPress Utilities

| Tool | Description | Docs |
|------|-------------|------|
| **Snippets** | Self-contained PHP snippets ready to drop into themes or plugins | [→](wordpress-utilities/snippets/README.md) |
| **Age Verification** | Cookie-based age verification with modal interface and ACF integration | [→](wordpress-utilities/age-verification/README.md) |
| **Analytics** | Google Analytics, Matomo implementation and detection | [→](wordpress-utilities/analytics/README.md) |
| **Speed Optimization** | Performance testing and TTFB analysis with curl/wget | [→](wordpress-utilities/speed-optimization/README.md) |

## Troubleshooting

| Tool | Description | Docs |
|------|-------------|------|
| **Server Diagnostics** | Diagnose PHP-FPM, MariaDB, and server issues | [→](troubleshooting/README.md) |

## Requirements

- **Core**: Git, Bash, rsync
- **Tool-specific**: See individual docs for Ansible, WP-CLI, ImageMagick, etc.

## License

MIT License. See [LICENSE.md](LICENSE.md) for details.

---

Copyright © Imagewize
