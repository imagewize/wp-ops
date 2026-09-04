<div align="center">
  <img src="assets/logo.svg" alt="WordPress Operations Logo" width="128" height="128">
  <h1>WP OPS</h1>
</div>
<div align="center">

[![Homebrew Downloads](https://img.shields.io/github/downloads/imagewize/wp-ops/total.svg?label=brew%20downloads)](https://github.com/imagewize/wp-ops/releases)
[![Latest Release](https://img.shields.io/github/v/release/imagewize/wp-ops.svg?label=version)](https://github.com/imagewize/wp-ops/releases)
[![License](https://img.shields.io/github/license/imagewize/wp-ops.svg)](LICENSE.md)

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

The single entry point for everything in this repo — a single binary that auto-discovers commands across every category, groups them by domain, and renders real `--help`, guided prompts, and shell completions from each command's manifest.

```bash
# Recommended: Homebrew
brew install imagewize/tap/wp-ops
wp-ops init                  # install shell completions (one-time)

# Without Homebrew, build from source (needs Go 1.26+):
git clone https://github.com/imagewize/wp-ops.git && cd wp-ops
go build -o wp-ops ./go
sudo mv wp-ops /usr/local/bin/   # or ~/.local/bin, or anywhere on your PATH
wp-ops init

wp-ops                       # interactive picker
wp-ops --help                # list all categories
wp-ops backup --help         # list commands in one category
wp-ops <category> <command> [args...]

wp-ops search webp           # find a command by name or description
wp-ops list --platform wordpress   # only what runs on any WordPress site
wp-ops docs oom              # search the guides, not just the commands
wp-ops doctor                # check dependencies and environment
wp-ops <command> --where     # print the path to a command's script
```

Categories group by **domain**, not by directory: `wp-ops backup` lists all ten
backup commands whether they're Ansible playbooks under `trellis/` or shell scripts
under `scripts/`. The directory names still work as aliases (`wp-ops trellis
database-backup`), they're just no longer how the catalog presents itself.

Every command also carries a **platform** — `trellis` (needs a Trellis project),
`wordpress` (any WP install: Valet, Herd, cPanel, Bedrock, Trellis), or `any` (no
WordPress involved). `wp-ops search` badges each result with it, and
`wp-ops list --platform <value>` filters to what will actually run against the site
in front of you.

The scripts, playbooks, and guides are embedded in the binary, so once it's on your PATH nothing else needs to stay around — you can delete the clone after building.

`wp-ops` with no arguments opens an interactive picker: categories first, then a fuzzy-filterable command list, then the chosen command's full help (usage, requirements, examples, args) printed above its argument prompts — no `fzf` dependency. It renders inline rather than taking over the screen, so earlier output stays visible above it and the last frame stays in your scrollback after it exits.

Run `wp-ops doctor` first — it reports which of the external tools these scripts rely on (WP-CLI, Ansible, ImageMagick, `gh`, `cwebp`, Node, …) are actually installed, so you find out before a command fails partway through.

`wp-ops init` installs `wp-ops <TAB>` completion for zsh, bash, or fish, auto-detected from `$SHELL`. Worth running right after install — the Homebrew cask this ships as doesn't wire up completions on its own the way a Homebrew formula would.

### As a trellis-cli plugin

The Homebrew cask installs the same binary under a second name, `trellis-ops`,
which [trellis-cli](https://github.com/roots/trellis-cli) picks up as a plugin —
it scans `$PATH` for `trellis-*` executables and turns each into a subcommand. So
everything below is also reachable from inside the tool you already have open:

```bash
trellis ops                              # Trellis-relevant categories
trellis ops backup database-pull         # same as: wp-ops backup database-pull
trellis ops search backup
```

`trellis ops` scopes its **listing** to the commands tagged `@platform trellis`;
run plain `wp-ops` for the full catalog. Running a command is never scoped — name
any command and it works. See the [Trellis command reference](#command-reference)
for what that surface contains.

Unlike core `trellis` subcommands, a plugin doesn't need you to be inside a Trellis
project — trellis-cli registers plugins from `$PATH` before it resolves a project at
all, so `trellis ops doctor` runs from anywhere while `trellis info` refuses. The
Ansible commands do still need a project, but they always did: wp-ops locates it
itself by walking up from your current directory, exactly as under bare `wp-ops`.

Requires trellis-cli new enough to have plugin support (v1.19.0 or later) and the
default `load_plugins: true`. If you built from source instead of installing the
cask, make the alias yourself:

```bash
ln -s "$(command -v wp-ops)" /usr/local/bin/trellis-ops
```

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
trellis ops trellis database-backup -e site=example.com -e env=production   # identical

# WP-CLI scripts (wp-ops wp-cli <script>) need a real WordPress/Bedrock install
export WP_SITE_DIR=/path/to/your/bedrock-site
wp-ops wp-cli scanner-wrapper
wp-ops wp-cli-pattern-validate web/app/themes/your-theme/patterns/ --fix
```

Detection deliberately only matches a project you're actually standing inside, so an
unrelated Trellis checkout sitting next to your current repo won't be picked up.

`docs/nginx/`, `docs/troubleshooting/`, and `docs/bedrock/` hold guides and config templates rather than runnable scripts, so they carry no commands and no CLI category — reach them through `wp-ops docs` instead.

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

Every catalog entry is something that runs. Copy-paste-into-a-theme reference
material — PHP snippets, the age-verification component — lives under
`docs/wordpress-utilities/` instead, reachable through `wp-ops docs`. To pull
one into a project, `wp-ops docs -l <term>` gives you the path:

```bash
cat "$(wp-ops docs -l age-verification | head -1)"
```

## Trellis

If you have trellis-cli, every command below is also reachable as
`trellis ops <...>` — same binary, same behaviour, no project required.
See [As a trellis-cli plugin](#as-a-trellis-cli-plugin).

```bash
trellis ops                                    # the 27 Trellis-relevant commands
trellis ops backup database-pull example.com production
trellis ops monitoring quick-status example.com production
```

`trellis ops` scopes its *listing* to commands tagged `@platform trellis`;
running a command is never scoped, so anything in the catalog still works if
you name it. Plain `wp-ops` shows all 74.

### Command reference

Grouped as `trellis ops` presents them. `(runs on server)` marks the log
readers that execute on the host — running one locally prints the SSH
invocation instead of failing. This table is generated from the catalog;
`wp-ops list --all` is the always-current version.

**`trellis ops monitoring`** (11)

| Command | What it does |
|---------|--------------|
| `ai-bot-monitor` | Analyze AI crawler traffic (GPTBot, ClaudeBot, etc.) from an Nginx access log *(runs on server)* |
| `error-monitor` | Surface errors from Nginx, PHP-FPM, WordPress, MySQL, and systemd for a domain *(runs on server)* |
| `monitor` | Run traffic, security, AI-bot, and error monitoring together and save timestamped reports *(runs on server)* |
| `security-monitor` | Detect malicious activity (wp-login/xmlrpc abuse, high-volume IPs) in an Nginx access log *(runs on server)* |
| `traffic-by-country` | Filter a server's Nginx access log by visitor country and show real page visits |
| `traffic-monitor` | Analyze legitimate traffic from an Nginx access log *(runs on server)* |
| `updown-webhook-handler` | Analyze Nginx logs on the server when updown.io reports downtime via webhook *(runs on server)* |
| `quick-status` | Quick health check for a site: recent status codes, errors, and service status |
| `security-scan` | Scan a site's Nginx logs for attack patterns and suspicious activity |
| `setup-monitoring` | Install cron jobs for daily traffic reports and periodic security scans |
| `traffic-report` | Generate a traffic analysis report from a site's Nginx access log |

**`trellis ops backup`** (9)

| Command | What it does |
|---------|--------------|
| `db-backup` | Back up a remote site's database over SSH straight to your machine |
| `db-pull` | Pull a remote site's database into development via SSH, with URL search-replace |
| `site-backup` | Full backup of a Trellis site: database, uploads, config, and plugins/themes *(runs on server)* |
| `database-backup` | Back up a site's database from any environment (development/staging/production) |
| `database-pull` | Pull a site's database from a remote environment into development, with URL search-replace |
| `database-push` | Push development's database to a remote environment, with URL search-replace |
| `files-backup` | Back up a site's uploads directory from any environment (development/staging/production) |
| `files-pull` | Pull a site's uploads directory from a remote environment into development via rsync |
| `files-push` | Push development's uploads directory to a remote environment via rsync |

**`trellis ops content`** (2)

| Command | What it does |
|---------|--------------|
| `import-page-draft` | Update an existing WordPress page from an HTML draft, locally and/or in production |
| `page-creation` | Deploy an HTML page to production via SCP and WP-CLI over SSH |

**`trellis ops misc`** (2)

| Command | What it does |
|---------|--------------|
| `create-product-variations` | Bulk-create WooCommerce product variations via WP-CLI over Trellis vm shell |
| `trellis-updater` | Safely update a Trellis installation to the latest upstream while preserving vault/config customizations |

**`trellis ops security`** (2)

| Command | What it does |
|---------|--------------|
| `check-deny-ips` | Check every individual IP in a Trellis deny-ips.conf.j2 against AbuseIPDB |
| `check-ips` | Check IP addresses against AbuseIPDB threat intelligence |

**`trellis ops diagnostics`** (1)

| Command | What it does |
|---------|--------------|
| `list-posts-count` | Count published posts on example.com via SSH and save the list to /tmp/all_posts.csv |

### Guides

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
| **Local Package Development** | Test an in-development plugin/theme branch in a Bedrock site via a Composer `path` repository, before tagging a release | [→](docs/bedrock/local-package-development/README.md) |
| **WP-CLI Config** | Standard `wp-cli.yml` for Bedrock path setup plus a `wp imagewize pattern-validate` command for canonicalizing block pattern files | [→](docs/bedrock/wp-cli-config/README.md) |

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
| **Image Optimization** | WebP/AVIF configuration with automatic format serving | [→](docs/nginx/image-optimization/README.md) |
| **Browser Caching** | Optimal static asset caching configuration | [→](docs/nginx/browser-caching/README.md) |
| **Redirects** | Redirect configuration for SEO and URL management | [→](docs/nginx/redirects/README.md) |

## Scripts

42 standalone Bash/PHP/Python/Node utilities — full docs, flags, and examples in [scripts/README.md](scripts/README.md).

| Category | Includes | Docs |
|------|-------------|------|
| **Releases & GitHub** | PR creation, plugin/theme release automation, WordPress.org SVN deploy, release asset upload, GitHub traffic stats | [→](scripts/README.md#github-integration) |
| **Monitoring & Security** | Traffic/security/AI-bot monitoring, 404 & redirect checking, CF7 smoke test, updown.io webhooks | [→](scripts/README.md#monitoring-scripts) |
| **Backups** | Trellis-aware database and full-site backups | [→](scripts/README.md#backup-scripts) |
| **Images, WooCommerce & Files** | Batch resize, WebP conversion, square-canvas padding, Openverse image search/download, WooCommerce product variations, theme/package sync, find & replace | [→](scripts/README.md#image-utilities) |
| **Content Reporting** | Published-post counts by year/month | [→](scripts/README.md#content-reporting) |

## MCP Server

Exposes wp-ops operations as [MCP](https://modelcontextprotocol.io) tools, so Claude (and other MCP-compatible clients) can call them directly instead of running the underlying scripts by hand. Scaffold stage — twenty tools so far, spanning security/SEO audits, backups, dev-site sync, content publishing/verification, SSH/SCP passthrough, and a catalog bridge (`command_search`/`command_run`) that exposes the full 74-command CLI catalog without a dedicated tool per command. See [mcp-server/README.md](mcp-server/README.md) for the full tool list, setup, transports (stdio/Streamable HTTP), and Docker usage.

## WordPress Utilities

| Tool | Description | Docs |
|------|-------------|------|
| **Snippets** | Self-contained PHP snippets ready to drop into themes or plugins | [→](docs/wordpress-utilities/snippets/README.md) |
| **Age Verification** | Cookie-based age verification with modal interface and ACF integration | [→](docs/wordpress-utilities/age-verification/README.md) |
| **Analytics** | Google Analytics, Matomo implementation and detection | [→](docs/wordpress-utilities/analytics/README.md) |
| **Speed Optimization** | Performance testing and TTFB analysis with curl/wget | [→](docs/wordpress-utilities/speed-optimization/README.md) |

## Troubleshooting

| Tool | Description | Docs |
|------|-------------|------|
| **Server Diagnostics** | Diagnose PHP-FPM, MariaDB, and server issues | [→](docs/troubleshooting/README.md) |

## Requirements

- **Core**: Git, Bash, rsync
- **Building from source**: Go 1.26+ (not needed if you install via Homebrew — the binary ships prebuilt)
- **Tool-specific**: See individual docs for Ansible, WP-CLI, ImageMagick, etc.

## License

MIT License. See [LICENSE.md](LICENSE.md) for details.

---

Copyright © Imagewize
