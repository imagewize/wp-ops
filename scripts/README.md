# Automation Scripts

Production-ready Bash, PHP, and Python scripts for WordPress operations, GitHub integration, server monitoring, and backup automation.

## Overview

This directory contains utility scripts organized into functional areas:

- **GitHub Integration** - AI-powered pull request creation and repository traffic analytics
- **WordPress Management** - File synchronization of themes and packages into a site
- **Local Sandboxes** - Bootstrap a local Valet WordPress site from a directory of UpdraftPlus backup zips
- **Image Utilities** - Render design SVGs to JPG or PNG
- **Pattern Screenshots** - Playwright/sharp toolkit for screenshotting WordPress block patterns and converting them to WebP
- **Git Utilities** - Quick access to recent commit history
- **Operations** - Server resource/traffic/security monitoring and backup infrastructure
- **Webhook Integration** - Updown.io downtime alert handling

## Directory Structure

```
scripts/
├── backup/                      # Backup automation scripts (see backup/README.md)
│   ├── wp-db-backup.sh         # Back up ANY WordPress site's database (Valet, Herd, cPanel, Bedrock)
│   ├── db-backup.sh            # Trellis: back up a remote database over SSH straight to your machine
│   ├── db-pull.sh              # Trellis: pull a remote database into development via SSH
│   └── site-backup.sh          # Trellis: complete site backup (DB + files + config)
├── git/                         # Git/GitHub utilities
│   ├── create-pr.sh            # AI-powered GitHub PR creation
│   ├── gh-traffic.sh           # GitHub repo traffic: views, clones, and referrers
│   └── git-log-oneline.sh      # Show recent git commits as one-liners
├── images/                      # SVG to JPG/PNG rendering
│   ├── svg-to-jpg.sh           # Render design SVGs to JPG via librsvg (native size or forced)
│   └── svg-to-png.sh           # Render design SVGs to PNG via librsvg (lossless, best for text)
├── local-sandbox/                # Bootstrap local dev sites from off-host backups
│   └── updraft-to-valet.sh     # Extract UpdraftPlus zips into a Valet-linked WP site
├── misc/                        # Miscellaneous utilities
│   ├── convert-screenshot-for-claude.sh  # Convert PNG screenshots to JPEG for Claude Code compatibility
│   ├── find-and-replace-files.sh     # Batch find and replace files across directory trees
│   └── README-FIND-AND-REPLACE.md    # Docs for find-and-replace-files.sh
├── monitoring/                  # Server monitoring and alerting
│   ├── 404-checker.sh          # Internal broken-link checker (homepage scan or recursive spider)
│   ├── ai-bot-monitor.sh       # AI crawler traffic analysis (GPTBot, ClaudeBot, etc.)
│   ├── error-monitor.sh        # Nginx/PHP-FPM/WordPress/MySQL/systemd error log review
│   ├── monitor.sh              # Orchestrator: runs all monitors and generates summary
│   ├── redirect-check.sh       # Mass URL redirect checker using curl
│   ├── security-monitor.sh     # Nginx security threat detection
│   ├── server-monitor.sh       # Live CPU/memory/disk/PHP-FPM/MySQL/nginx resource snapshot over SSH
│   ├── ssl-check.sh            # TLS certificate expiry/issuer/subject check via openssl; --warn-days alerts (GitHub Actions workflow via .github/workflows/ssl-expiry.yml)
│   ├── store-audit.sh          # Audit a store's public URL with Min (AI-shopping readiness, price/stock truth check); --fail-under / --fail-on exit 2 as a deploy gate (curl + jq)
│   ├── traffic-monitor.sh      # Nginx traffic analysis and reporting
│   ├── traffic-by-country.sh   # Filter Nginx logs by visitor country (geoip2fast) and show real visits
│   ├── updown-webhook-handler.sh     # Webhook event handler
│   └── updown-webhook-receiver.php   # Webhook HTTP receiver
├── patterns/                    # WordPress block pattern screenshot toolkit
│   ├── screenshot-patterns.sh  # End-to-end: create temp WP page, screenshot, delete, convert to WebP
│   ├── screenshot-url.js       # Generic Playwright URL/element screenshot primitive
│   ├── png-to-webp.js          # Sharp-based PNG to WebP converter
│   ├── trim-screenshots.sh     # Trim whitespace from a directory of pattern screenshots (ImageMagick)
│   ├── center-screenshots.sh   # Center screenshots on a fixed canvas (ImageMagick)
│   └── README.md               # Setup and usage docs
├── sync/                        # File synchronization
│   ├── rsync-package-to-site.sh  # Push a plugin/theme working copy into a Bedrock site
│   └── rsync-theme.sh            # Theme file synchronization utility
```

## Quick Start

### Prerequisites

- Bash shell (included on all Linux/macOS systems)
- Git (for GitHub integration scripts)
- WP-CLI (for WordPress backup scripts)
- Claude CLI, Codex, or Mistral Vibe (optional, for AI features)
- PHP (for webhook receiver)

### Common Operations

```bash
# Render design SVGs to JPG (native size, or forced to a platform spec)
./scripts/images/svg-to-jpg.sh designs/linkedin
./scripts/images/svg-to-jpg.sh -w 1920 -h 1080 designs/mastodon

# Render design SVGs to PNG (lossless — prefer for banners with text or logos)
./scripts/images/svg-to-png.sh designs/linkedin

# Create GitHub PR with AI description
./scripts/git/create-pr.sh main "Add feature name"

# Show GitHub repository traffic statistics (views only, by default)
./scripts/git/gh-traffic.sh imagewize/nynaeve

# Views, clones, and referrers for several repos at once
./scripts/git/gh-traffic.sh --all imagewize/nynaeve imagewize/wp-ops

# Just the cross-repo rollup table (views + clones), no per-repo detail
./scripts/git/gh-traffic.sh --all --summary imagewize/nynaeve imagewize/wp-ops

# Show recent git commits as one-liners
./scripts/git/git-log-oneline.sh
./scripts/git/git-log-oneline.sh 25

# Backup WordPress database
./scripts/backup/db-backup.sh example.com production

# Check homepage links for broken URLs (~30s)
./scripts/monitoring/404-checker.sh https://example.com

# Full spider check (recursive, depth 3, ~5-10 min)
./scripts/monitoring/404-checker.sh --mode spider https://example.com

# Check a list of URLs for redirects
./scripts/monitoring/redirect-check.sh https://example.com/old-path/ https://example.com/another/

# Monitor Nginx traffic
./scripts/monitoring/traffic-monitor.sh /var/log/nginx/access.log 6

# Scan for security threats
./scripts/monitoring/security-monitor.sh /srv/www/example.com/logs/access.log 24

# Show real page visits from a given country (pulls the log over SSH)
./scripts/monitoring/traffic-by-country.sh --host web@example.com NL
./scripts/monitoring/traffic-by-country.sh -q --hours 24 --pattern "/contact/" US

# Analyze AI crawler traffic
./scripts/monitoring/ai-bot-monitor.sh /srv/www/example.com/logs/access.log 24

# Live CPU/memory/disk/PHP-FPM/MySQL/nginx resource snapshot
./scripts/monitoring/server-monitor.sh web@example.com

# Review error logs (nginx, PHP-FPM, WordPress, MySQL, systemd)
ssh root@example.com 'bash -s' < scripts/monitoring/error-monitor.sh example.com 24

# Run all monitors and save timestamped reports
ssh web@example.com 'bash -s' < scripts/monitoring/monitor.sh

# Screenshot WordPress block patterns and convert to WebP
cd scripts/patterns && npm install && npx playwright install chromium
PATTERN_NAMESPACE=mytheme SITE_URL=http://example.test WP_CLI_CMD="wp --path=web/wp" \
  ./screenshot-patterns.sh hero-dark testimonials-and-logos
```

---

## Pattern Screenshots

### patterns/ toolkit

Playwright/sharp toolkit for screenshotting WordPress block patterns (or any URL) and
converting them to WebP — for pattern-library preview images, documentation
screenshots, or visual diffs during theme development. Full docs in
[`patterns/README.md`](patterns/README.md); summary here.

#### Setup

```bash
cd scripts/patterns
npm install
npx playwright install chromium
brew install imagemagick   # only needed for trim-screenshots.sh / center-screenshots.sh
```

#### Scripts

- **`screenshot-patterns.sh`** — end-to-end pipeline: creates a temporary WordPress
  page containing the pattern, screenshots it, deletes the page, converts every
  capture to WebP. Configured entirely via environment variables (`WP_CLI_CMD`,
  `SITE_URL`, `PATTERN_NAMESPACE`, `OUTPUT_DIR`) so it works against a local site, a
  Trellis VM, or a remote server over SSH.
- **`screenshot-url.js`** — the generic Playwright capture primitive underneath it;
  screenshots any URL (element selector or full page), independent of WordPress.
- **`png-to-webp.js`** — standalone sharp-based PNG → WebP converter, single file
  or `--all` batch mode.
- **`trim-screenshots.sh`** / **`center-screenshots.sh`** — ImageMagick post-processing
  for a directory of `pattern-*.webp` files (trim whitespace, or trim + center on a
  fixed canvas). Both back up originals and are safe to re-run.

#### Usage

```bash
PATTERN_NAMESPACE=mytheme \
SITE_URL=http://example.test \
WP_CLI_CMD="wp --path=web/wp" \
./scripts/patterns/screenshot-patterns.sh hero-dark testimonials-and-logos

# Then, optionally, center on a fixed canvas
./scripts/patterns/center-screenshots.sh ./scripts/patterns/screenshots 900 600
```

`WP_CLI_CMD` is whatever actually invokes WP-CLI for the target site:

```bash
WP_CLI_CMD="wp --path=web/wp"                                                  # local Bedrock site
WP_CLI_CMD="trellis vm shell --workdir /srv/www/example.com/current -- wp"     # Trellis VM
WP_CLI_CMD="ssh web@example.com -- wp --path=/srv/www/example.com/current/web/wp"  # remote over SSH
```

#### Not included

Site-specific QA checks (e.g. verifying a custom carousel block's JS state) are too
coupled to a particular block/theme to generalize usefully — write those as one-off
Playwright scripts in the project itself, using `screenshot-url.js` as a starting
point.

---

## Misc Utilities

### convert-screenshot-for-claude.sh

Converts a PNG screenshot to JPEG, working around a Claude Code VSCode extension bug that mislabels PNG screenshots as `image/jpeg`, causing API errors when the screenshot is shared with Claude. Handy after a Playwright screenshot run.

#### Requirements

```bash
brew install imagemagick   # macOS
sudo apt-get install imagemagick  # Ubuntu/Debian
```

#### Usage

```bash
./scripts/misc/convert-screenshot-for-claude.sh .playwright/screenshots/test.png

# Custom JPEG quality (default: 90)
./scripts/misc/convert-screenshot-for-claude.sh .playwright/screenshots/test.png --quality=95
```

#### Output

```
JPEG file created: .playwright/screenshots/test-for-claude.jpg
```

---

## Local Sandboxes

### updraft-to-valet.sh

Bootstraps a local [Laravel Valet](https://laravel.com/docs/valet)-linked WordPress site from a directory of UpdraftPlus backup zips (`db`/`plugins`/`themes`/`uploads[+N]`) — no SSH or hosting access needed. For the recurring "handed a set of backup zips before you have server access" pattern: a client onboarding, or evaluating a prospective site.

Local-only, plain WordPress (`@platform wordpress`) — not Trellis- or Bedrock-specific, and it doesn't use any of the Trellis-project helpers other backup scripts rely on.

#### What it does

1. Matches the UpdraftPlus files in the directory by their shared hash (`backup_<date>_<site>_<hash>-<type>.zip/gz`) so a directory holding more than one backup run isn't mixed together
2. Extracts `plugins`/`themes`/`uploads[+N]`/`others` into `wp-content/` — detecting per-zip whether entries already carry a `wp-content/` prefix, since that has varied across UpdraftPlus versions
3. Downloads a matching WordPress core with `--skip-content`, so it never overwrites the restored `wp-content/`
4. `valet link` (+ optional `--secure`)
5. Creates the local database and `wp-config.php`
6. Auto-detects the old site URL from the dump's `siteurl` row (grepped straight off the compressed dump — never hardcoded) and imports the database
7. `wp search-replace`s the old URL for `https://<site-slug>.test`, then flushes rewrites
8. Optional `--reset-password <user>` for local wp-admin testing

#### Requirements

- WP-CLI, [Valet](https://laravel.com/docs/valet), `unzip`, `gzip`
- The WordPress core version to install — the DB dump only tells you `siteurl`/`ABSPATH`, not the core version, so `--wp-version` is required and explicit rather than auto-detected

#### Usage

```bash
# Minimal: WP version is the only required flag
./scripts/local-sandbox/updraft-to-valet.sh ~/Downloads/client-backup client --wp-version 6.7.1

# Secure the Valet link and set a known local wp-admin password
./scripts/local-sandbox/updraft-to-valet.sh ~/Downloads/client-backup client \
  --wp-version 6.6.2 --secure --reset-password admin

# Override auto-detection or local DB credentials
./scripts/local-sandbox/updraft-to-valet.sh ~/Downloads/client-backup client --wp-version 6.7.1 \
  --old-url https://old-host.example.com --db-user root --db-pass secret
```

Via wp-ops: `wp-ops updraft-to-valet ~/Downloads/client-backup client --wp-version 6.7.1`.

#### Not handled

Any local PHP-FPM/MySQL environment repair (e.g. two Homebrew PHP versions' default pools colliding on the same port) is a one-time machine setup issue, not part of this repeatable workflow — fix that separately.

---

## Git Utilities

### git-log-oneline.sh

Shows recent git commits as compact one-liners with short hash and commit message. Quick way to review recent work or changes before creating a PR.

#### Features

- **Compact Output**: Displays short commit hash + message on a single line
- **Configurable Count**: Show 1, 10, 25, or any number of recent commits
- **Input Validation**: Validates that the count is a positive integer
- **Error Handling**: Clear error messages for invalid input

#### Usage

```bash
# Show last 10 commits (default)
./scripts/git/git-log-oneline.sh

# Show last 20 commits
./scripts/git/git-log-oneline.sh 20

# Show last 5 commits
./scripts/git/git-log-oneline.sh 5

# Show last 100 commits, but only display first 25
./scripts/git/git-log-oneline.sh 100 | head -n 25
```

#### Example Output

```
476fc26 Release 2.5.11 - WebP conversion script and Vibe CLI config
4633427 Add Mistral Vibe CLI project configuration
1da9044 Add webp-featured-image.md entry to snippets README
9737050 Document convert-to-webp.sh in scripts README
2762531 Add convert-to-webp.sh script
```

#### Use Cases

- Quickly check what you've been working on
- Review recent commits before creating a PR
- Verify the last deployment included the right changes
- Check if a specific fix has been committed

---

## GitHub Integration

### create-pr.sh (635 lines)

Intelligent GitHub pull request creation with AI-powered descriptions using Claude CLI, Codex, or Mistral Vibe. Full docs — features, usage, flags, token-cost comparison, troubleshooting — live in [CREATE-PR.md](../CREATE-PR.md) at the repo root; this file doesn't duplicate them.

---

## Theme Management

### rsync-theme.sh

Simple rsync wrapper for theme synchronization between Trellis and standalone repositories.

#### Features

- **Archive Mode**: Preserves timestamps, permissions, ownership
- **Selective Deletion**: Removes destination files not in source
- **Dry Run**: `--dry-run` previews the transfer — including deletions — without
  writing anything
- **Exclude Filters**:
  - `node_modules/`, `vendor/` (dependencies)
  - `.git/`, `.github/` (version control)
  - `create-pr.sh`, `.distignore` (repo-specific files)

#### Configuration

Edit the defaults at the top of the script, or override them per invocation:

```bash
SOURCE="$HOME/code/example.com/demo/web/app/themes/elayne/"
DEST="$HOME/code/elayne/"
```

#### Usage

```bash
# Preview first — --delete means anything at the destination that is not in the
# source is removed
./scripts/sync/rsync-theme.sh --dry-run

# Run synchronization
./scripts/sync/rsync-theme.sh

# One-off paths
SOURCE=~/code/example.com/site/web/app/themes/my-theme/ \
  DEST=~/code/my-theme/ ./scripts/sync/rsync-theme.sh -n

# Output shows:
# - Files sent/received
# - Total size transferred
# - Speedup achieved
```

Unknown options are rejected rather than ignored — the script previously passed
over any argument it did not recognize, so a mistyped `--dry-run` ran the sync
for real.

#### Use Cases

- Sync theme from Bedrock to standalone repo
- Prepare theme for WordPress.org submission
- Backup theme to separate repository
- Development workflow: edit in Trellis, sync to standalone for distribution

---

### rsync-package-to-site.sh

The **reverse direction** of `rsync-theme.sh`: pushes a plugin or theme working
copy *into* a Bedrock site, so unreleased changes can be tested on a real site
without cutting a release. Use it when the package repo is the source of truth
and the site is disposable.

Keep this script here rather than committing a copy into each package repo — the
paths are personal configuration, and WordPress Theme Check's `File_Check`
rejects a theme that ships a `.sh` file at all.

#### Features

- **Dist-faithful**: reads the package's own `.distignore` when present, so a file
  excluded from the release zip never reaches the site — what you test is what ships
- **Dry Run**: `--dry-run` previews the transfer — including deletions — without
  writing anything
- **`--delete-excluded`**: a file that used to ship and is now excluded is removed
  at the destination too, rather than lingering and being tested after it is gone
- **Version echo**: prints the version that landed (theme `style.css` header, or the
  plugin's main-file header), making a no-op sync obvious
- **Fallback excludes** for packages without a `.distignore` (`node_modules/`,
  `vendor/`, `.git/`, `.github/`, `docs/`, `tests/`, `bin/`, `*.sh`, editor cruft)

#### Configuration

`SITE_ROOT` is the Bedrock content directory — the one holding `plugins/` and
`themes/` (`web/app` in a stock Bedrock install). Set it per invocation or in your
shell profile:

```bash
export SITE_ROOT="$HOME/code/example.com/demo/web/app"
```

#### Usage

```bash
# Preview first — the sync runs with --delete --delete-excluded
./scripts/sync/rsync-package-to-site.sh --dry-run plugin my-plugin

# From inside the package repo
./scripts/sync/rsync-package-to-site.sh plugin my-plugin

# Or point at it explicitly
./scripts/sync/rsync-package-to-site.sh theme my-theme ~/code/my-theme

# One-off destination
SITE_ROOT=~/code/example.com/staging/web/app \
  ./scripts/sync/rsync-package-to-site.sh theme my-theme
```

#### Use Cases

- Test a plugin/theme branch on a real site before tagging a release
- Verify a release zip's contents in situ, since the sync honours `.distignore`
- Refresh a demo site after every local change, without touching its `composer.json`

#### Alternative

A Composer `path` repository (see
[bedrock/local-package-development](../docs/bedrock/local-package-development/README.md))
is the better fit when you want Composer itself to resolve the package and you are
happy editing the site's `composer.json`. This script suits a *pinned* dependency
you would rather leave alone. Either way, `composer update vendor/package` on the
site restores the released code.

---

## Backup Scripts

### db-backup.sh

Backs up a remote site's database over SSH, straight to your machine. Runs on your machine — no `trellis vm shell` or VM dependency, unlike `db-pull.sh`; it just SSHes directly to the site's own web directory.

#### Features

- **No remote temp file**: streams `wp db export - --path=web/wp` over SSH directly into `gzip`, writing straight to a local file
- **Never touches `/srv/backups`**: a stock Trellis box provisions and `chown`s `/srv/www`, never `/srv/backups` itself, so the old version of this script (which wrote there) failed with a permission error on every site's first run. SSHing into the already-`web`-writable web directory instead sidesteps that entirely.
- **Local retention**: prunes this site's own backups in the destination directory older than 30 days

#### Usage

```bash
# Backup production
./db-backup.sh example.com production

# Backup staging, from a host that differs from the site key
./db-backup.sh example.com staging --host staging.example.com

# Custom local destination directory
./db-backup.sh example.com production --dest ~/backups/example.com
```

Backing up `development` is already local — just run `wp db export --path=web/wp` directly; no SSH hop needed.

Via wp-ops: `wp-ops db-backup example.com production`.

For automated/repeatable backups instead, use `trellis/backup/database-backup.yml` (`wp-ops trellis database-backup -e site=example.com -e env=production`). See [trellis/backup/README.md](../trellis/backup/README.md) for the tradeoffs.

#### Output Files

```
database_backup/
└── example_com_production_2026_08_03_14_30_00.sql.gz
```

---

### db-pull.sh

Pulls a remote site's database into local development over SSH, with URL search-replace. Runs on your machine — uses `trellis vm shell` to reach the local dev VM, and SSHes from inside it straight to the remote host, so the dump streams through with no intermediate file on either end.

#### Features

- **No remote temp file**: streams `wp db export` over SSH directly into `wp db import`
- **Dynamic URL detection**: reads both the remote and local `siteurl` at run time via WP-CLI — no hardcoded per-site URL table
- **Safety backup**: exports the current development database before overwriting it
- **Multisite support** (`--multisite`): scopes `search-replace` with `--url` and fixes `wp_blogs` domains
- **Confirmation prompt**: skip with `--yes`/`-y`

#### Usage

```bash
export TRELLIS_DIR=/path/to/trellis

# Pull production into development
./db-pull.sh example.com production

# Pull from a host that differs from the site key, skip the prompt
./db-pull.sh example.com staging --host staging.example.com --yes

# Multisite network
./db-pull.sh network.example.com production --multisite
```

Via wp-ops: `wp-ops db-pull example.com production`.

For automated/repeatable pulls instead, use `trellis/backup/database-pull.yml` (`wp-ops trellis database-pull -e site=example.com -e env=production`) — it has no `trellis vm shell` dependency and is the better fit for CI/scheduled jobs. See [trellis/backup/README.md](../trellis/backup/README.md) for the tradeoffs.

---

### site-backup.sh (193 lines)

Complete site backup including database, uploads, configuration files, and WordPress content.

#### Features

- **Four Backup Categories**:

  1. **Database** (`db_*.sql.tar.gz`)
     - WP-CLI export with optimal settings
     - Compressed with tar + gzip

  2. **Uploads** (`uploads_*.tar.gz`)
     - WordPress uploads directory
     - Excludes cache and tmp directories
     - Preserves file structure and permissions

  3. **Configuration** (`config_*.tar.gz`)
     - `.env` files (database credentials, salts)
     - `.htaccess` rules
     - `config/application.php` (Bedrock config)

  4. **Content** (`content_*.tar.gz`)
     - Plugins directory
     - Themes directory
     - MU-plugins directory
     - Excludes: cache, node_modules, .git

- **Backup Manifest**:
  - Text file with complete backup metadata
  - File sizes and counts
  - WordPress version and environment
  - Backup statistics

- **Retention Policy**: 30-day automatic cleanup

- **Size Calculation**: Human-readable output with `numfmt`

#### Usage

```bash
# Backup complete site
./site-backup.sh example.com

# Cron automation
0 2 * * * /srv/scripts/site-backup.sh example.com > /var/log/backup.log 2>&1
```

#### Output Files

```
/srv/backups/example.com/
├── database/
│   └── db_20251231_120000.sql.tar.gz
├── files/
│   └── uploads_20251231_120000.tar.gz
└── config/
    ├── config_20251231_120000.tar.gz
    ├── content_20251231_120000.tar.gz
    └── manifest_20251231_120000.txt
```

#### Manifest Example

```
=== Site Backup Manifest ===
Site: example.com
Date: 2025-12-31 12:00:00
WordPress Version: 6.4.2

Database Backup:
- File: db_20251231_120000.sql.tar.gz
- Size: 45.2 MB
- Tables: 23

Uploads Backup:
- File: uploads_20251231_120000.tar.gz
- Size: 1.2 GB
- Files: 3,421

Configuration Backup:
- File: config_20251231_120000.tar.gz
- Size: 42 KB

Content Backup:
- File: content_20251231_120000.tar.gz
- Size: 125 MB
```

---

## Monitoring Scripts

### traffic-monitor.sh (533 lines)

Real-time Nginx traffic analysis with intelligent bot filtering and comprehensive reporting.

#### Features

- **Bot Filtering**:
  - Excludes search engine crawlers (Googlebot, Bingbot, DuckDuckBot, etc.)
  - Filters social media bots (Facebook, Twitter, LinkedIn)
  - Removes monitoring services (UptimeRobot, Pingdom)

- **Static File Exclusion**:
  - Ignores CSS, JS, images, fonts
  - Excludes WebP, AVIF, WOFF2, etc.
  - Focuses on actual page requests

- **Comprehensive Reports**:
  - Non-bot vs bot traffic split
  - Unique visitors by IP address
  - HTTP status code breakdown (color-coded)
  - Top 10 requested pages
  - Top 10 IP addresses
  - Hourly traffic with ASCII bar chart
  - Top external referrers
  - Top user agents
  - HTTP methods distribution (GET, POST, etc.)
  - Bandwidth summary (MB/GB calculation)

- **Configurable Time Windows**:
  - Exact epoch-based filtering via `gawk` (falls back to line estimate if unavailable)
  - Cutoff timestamp shown in analysis header

- **Output File Support**:
  - Optional third argument saves report to disk via `tee`

#### Usage

```bash
# Default (analyze full log)
./traffic-monitor.sh

# Specific log file and time window
./traffic-monitor.sh /srv/www/demo.example.com/logs/access.log 6

# Last 24 hours, save to file
./traffic-monitor.sh /var/log/nginx/access.log 24 /tmp/traffic-report.txt

# Production usage
./traffic-monitor.sh /srv/www/example.com/logs/access.log 12
```

#### Example Output

```
=== Traffic Summary (Last 6 Hours) ===
Total Requests: 15,234
├─ Non-Bot Traffic: 12,456 (81.8%)
└─ Bot Traffic: 2,778 (18.2%)

Unique Visitors: 1,234 IPs

Status Codes:
✓ 200 OK: 14,521 (95.3%)
⚠ 301 Redirect: 432 (2.8%)
⚠ 404 Not Found: 189 (1.2%)
✗ 500 Error: 12 (0.08%)

Top 10 Pages:
  2,341 /
  1,234 /about/
    892 /services/
    671 /contact/
    ...

Hourly Traffic:
12:00 ████████████████████ 2,341
13:00 ███████████████ 1,892
14:00 ██████████████████ 2,104
...

Bandwidth: 1.2 GB total
```

---

### security-monitor.sh (552 lines)

Advanced Nginx security threat detection with detailed attack pattern analysis and IP blocking recommendations.

#### Features

- **12 Threat Detection Categories**:

  1. **Brute Force Attacks**
     - wp-login.php excessive attempts
     - Alert threshold: 10+ attempts per IP

  2. **XML-RPC Abuse**
     - Pingback/trackback spam
     - DDoS via XML-RPC

  3. **High-Request IPs**
     - DoS attack detection
     - Scraper identification
     - Configurable threshold

  4. **404 Scanners**
     - Directory enumeration attempts
     - Automated vulnerability scanning

  5. **SQL Injection**
     - Pattern detection in URLs
     - POST data analysis

  6. **Directory Traversal**
     - Path traversal attempts (../, etc.)
     - File inclusion attacks

  7. **Shell Injection**
     - Command injection attempts
     - Shell metacharacter detection

  8. **Sensitive File Access**
     - `.env`, `.git`, `wp-config.php`
     - Backup files, config files

  9. **Suspicious User Agents**
     - sqlmap, nikto, nmap, masscan
     - Known attack tools

  10. **Empty User Agents**
      - Automated scripts
      - Malicious bots

  11. **Non-Standard POST Requests**
      - Unexpected POST to static files
      - Form spam detection

  12. **Server Errors (5xx)**
      - Application crashes
      - Resource exhaustion

- **IP Block Recommendations**:
  - Generates nginx `deny` rules
  - Shows how to add to Trellis config
  - Prioritizes most active attackers

- **Configurable Thresholds**:
  - Alert when single IP exceeds X requests
  - Customizable per deployment

- **Color-Coded Output**:
  - RED: Critical threats
  - YELLOW: Warnings
  - CYAN: Informational

#### Usage

```bash
# Default analysis
./security-monitor.sh

# Specific log, time window, and alert threshold
./security-monitor.sh /srv/www/example.com/logs/access.log 1 50

# Last 24 hours, alert at 100 requests, save to file
./security-monitor.sh /var/log/nginx/access.log 24 100 /tmp/security-report.txt

# Syntax
./security-monitor.sh [LOG_FILE] [HOURS] [ALERT_THRESHOLD] [OUTPUT_FILE]
```

#### Example Output

```
=== Security Threat Analysis ===

⚠ BRUTE FORCE ATTACKS (wp-login.php):
192.168.1.100: 45 attempts
203.0.113.50: 23 attempts

⚠ HIGH-REQUEST IPs (Exceeding 50 requests):
198.51.100.25: 152 requests (potential DoS)
192.0.2.75: 89 requests (possible scraper)

⚠ SQL INJECTION ATTEMPTS:
POST /search.php?id=1' OR '1'='1 - 192.168.1.200
GET /product.php?id=-1 UNION SELECT - 203.0.113.100

⚠ SENSITIVE FILE ACCESS:
/.env - 192.168.1.50 (3 attempts)
/.git/config - 198.51.100.10 (5 attempts)

=== RECOMMENDED IP BLOCKS ===
# Add to Trellis nginx-includes:

location / {
    deny 192.168.1.100;  # 45 login attempts
    deny 198.51.100.25;  # 152 requests (DoS)
    deny 192.168.1.50;   # .env access attempts
}
```

#### Integration with Trellis

Create `nginx-includes/ip-blocks.conf.j2`:

```nginx
# Generated by security-monitor.sh
# Date: 2025-12-31

location / {
    deny 192.168.1.100;
    deny 198.51.100.25;
    deny 192.168.1.50;
    # ... more IPs
}
```

Deploy with:
```bash
trellis provision --tags nginx-includes production
```

---

### ai-bot-monitor.sh (390 lines)

Analyzes AI crawler traffic from Nginx logs, with per-bot breakdowns, bandwidth usage, scraped pages, and robots.txt compliance.

#### Features

- **Detects 20+ AI Crawlers**:
  - OpenAI: GPTBot, ChatGPT-User, OAI-SearchBot
  - Anthropic: ClaudeBot, anthropic-ai
  - Google: Google-Extended
  - Meta: meta-externalagent
  - Others: PerplexityBot, CCBot, Bytespider, Amazonbot, Diffbot, YouBot, cohere-ai, Applebot-Extended, AI2Bot, and more

- **Comprehensive Reports**:
  - AI vs non-AI traffic split with percentage
  - Requests and bandwidth per crawler
  - Top 30 pages scraped by all AI bots combined
  - Top 10 pages per major crawler
  - Hourly AI traffic distribution with ASCII bar chart
  - HTTP status codes returned to AI bots
  - Total bandwidth consumed (MB/GB) and share of total
  - Top IP addresses used by AI crawlers
  - Robots.txt compliance check

- **Operator IP Cross-Check** (optional):
  - Flag AI UA requests from known operator IP ranges
  - Distinguishes tool sessions from autonomous crawlers
  - Configure `OPERATOR_IP_PATTERN` in script header

- **Accurate Time Filtering**:
  - gawk-based epoch timestamp filtering; falls back to tail estimate if unavailable

#### Usage

```bash
# Default: example.com log, last 24 hours
./ai-bot-monitor.sh

# Specific log file and time window
./ai-bot-monitor.sh /srv/www/demo.example.com/logs/access.log 6

# Last 7 days, save to file
./ai-bot-monitor.sh /srv/www/example.com/logs/access.log 168 /tmp/ai-bots.txt

# Syntax
./ai-bot-monitor.sh [LOG_FILE] [HOURS] [OUTPUT_FILE]
```

---

### server-monitor.sh

Live resource-usage snapshot over SSH — complements the log-based monitors above
(traffic/security/AI-bot) with a point-in-time view of what the server itself is
doing right now.

#### Features

- System uptime and load average
- Memory usage (absolute and percentage)
- Disk usage (absolute and percentage)
- Top 15 memory-consuming processes
- PHP-FPM pool statistics (worker count, total and average RSS memory)
- MySQL/MariaDB and Nginx memory/CPU usage
- Process summary (total, running, sleeping)
- Recent OOM killer events (last 7 days, via `journalctl`)
- Swap usage warning

#### Usage

```bash
./server-monitor.sh <ssh-target> [php-fpm-pool-pattern]

# Examples
./server-monitor.sh web@example.com
./server-monitor.sh root@example.com "php-fpm: pool wordpress"
```

The optional second argument narrows the PHP-FPM `ps aux` grep to a specific pool
name — useful on a multi-site server where several pools are running and you only
want one site's numbers. Defaults to matching any `php-fpm: pool` process.

#### Example Output

```
━━━ Memory Usage (Percentage) ━━━
Memory: 5.1G/7.5G (68.42% used)

━━━ PHP-FPM Pool Statistics ━━━
PHP-FPM workers: 13
Total RSS memory: 1950.23 MB
Average per worker: 150.02 MB

━━━ Recent OOM Killer Events (Last 7 Days) ━━━
✓ No OOM killer events in last 7 days
```

#### Requirements

- SSH access to the target server
- `journalctl` on the remote host (systemd-based Linux; standard on Trellis/Ubuntu servers)

---

### error-monitor.sh

Error-log review across every layer of the stack. The traffic/security/AI-bot
monitors read the *access* log and answer "who is visiting?"; this one reads the
*error* logs and answers "is anything broken?".

Runs **on the server** — it reads `/var/log/` and `/srv/www/<domain>/logs/`
directly and needs GNU `date` — so stream it over SSH like `monitor.sh`.

#### Features

- Nginx error log, global and per-site, with a severity breakdown
  (`[emerg]`/`[alert]`/`[crit]`/`[error]`/`[warn]`/`[notice]`) so a single
  `[emerg]` isn't buried among hundreds of routine notices
- PHP-FPM error log, discovered by globbing `/var/log/php*-fpm.log` rather than
  asking `php -v` — the CLI version can differ from the version FPM runs, and a
  server mid-upgrade has more than one log
- WordPress/Acorn exceptions (`.../cache/acorn/logs/laravel.log`), with stack
  trace continuation lines kept attached to their entry
- MySQL/MariaDB error log
- systemd journal: priority-`err` messages, PHP segfaults, OOM kills
- Every source is **filtered to the requested time window**, each by its own
  timestamp format — counts and excerpts come from one read of the file, so they
  can never disagree
- Summary with a per-source breakdown, and a callout when segfaults or OOM kills
  occurred (those drop requests mid-flight and never appear in the access log)

#### Usage

```bash
ssh <target> 'bash -s' < ./error-monitor.sh [domain] [hours] [output_file]

# Examples
ssh web@example.com 'bash -s' < scripts/monitoring/error-monitor.sh
ssh web@example.com 'bash -s' < scripts/monitoring/error-monitor.sh example.com 48
ssh root@example.com 'bash -s' < scripts/monitoring/error-monitor.sh example.com 24

# On the server itself
./error-monitor.sh example.com 24
```

Connect as **root** to include the systemd sections. The `web` user usually
can't read the journal, in which case those checks are reported as *skipped*
rather than silently empty — an empty result and no permission look identical
otherwise, and the difference matters when you're chasing an outage.

#### Example Output

```
━━━ Nginx Error Log (example.com) ━━━
14 entries in the last 24h (/srv/www/example.com/logs/error.log)

━━━ Nginx Severity Breakdown ━━━
  11 [error]
   2 [warn]
   1 [crit]

━━━ Out of Memory Events ━━━
✓ No OOM killer events

━━━ Summary ━━━
23 log entries in the last 24 hours

Breakdown:
  - Nginx (example.com):   14
  - PHP-FPM:               2
  - WordPress/Acorn:       7
```

#### Requirements

- Runs on the server (GNU `date`; no `gawk` needed — the time filtering is plain
  `awk` string comparison, since these log formats all sort chronologically as text)
- `journalctl` access for the systemd sections (root, or a user in `adm`/`systemd-journal`)

---

### 404-checker.sh

Internal broken-link checker for WordPress sites. Scans for pages and links that return 4xx or 5xx responses. Two modes: a fast homepage scan (~30 s) that catches global footer/nav issues, and a recursive wget spider (~5–10 min) that traverses the whole site.

#### Features

- **Global mode** (default): fetches the homepage and checks every internal link found — catches header/footer/nav links that appear on every page
- **Spider mode**: recursive `wget --spider` crawl to configurable depth — covers the full site including blog posts and service pages
- **Color-coded output**: green OK, yellow warnings, red broken links
- **Exit code 1** when broken links are found — suitable for CI/deploy hooks
- **Optional output file**: append broken links to a file for audit trails
- **Configurable timeout and spider depth**

#### Usage

```bash
# Fast homepage scan — covers all global (header/footer/nav) links
./scripts/monitoring/404-checker.sh https://example.com

# Full recursive spider, depth 3
./scripts/monitoring/404-checker.sh --mode spider https://example.com

# Save broken links to a file
./scripts/monitoring/404-checker.sh --output /tmp/broken-links.txt https://example.com

# Spider with custom depth and timeout
./scripts/monitoring/404-checker.sh --mode spider --level 4 --timeout 15 https://example.com
```

#### Example Output

```
[10:05:12] Fetching homepage: https://example.com
[10:05:13] Found 42 internal links — checking each...
404  https://example.com/old-page/
410  https://example.com/?page_id=3330
[WARN] 2 broken link(s) found.
```

#### Integration ideas

- **After every page deletion**: `./404-checker.sh https://example.com` to catch stale footer/nav links before Ahrefs does
- **Post-deploy hook**: add to a Makefile target or Trellis deploy callback
- **CI pipeline**: exit code 1 on broken links blocks a deploy

#### Requirements

- `curl` (standard on macOS/Linux)
- `wget` — only required for `--mode spider` (`brew install wget` on macOS)

---

### redirect-check.sh

Mass URL redirect checker using curl. Useful for verifying redirect rules, `.htaccess` changes, or migration redirect mappings.

#### Features

- Checks HTTP status code and redirect target for each URL
- Accepts URLs as command-line arguments or uses built-in defaults
- Shows `URL => HTTP_CODE -> REDIRECT_URL` for each entry
- Uses `--max-redirs 0` to stop after the first redirect and reveal the target

#### Use Cases

- Verifying bulk redirects after a site migration
- Checking `.htaccess` or Nginx redirect rules
- Auditing canonical URL implementations
- Debugging 301/302 redirect chains

#### Usage

```bash
# Run with default URLs (edit the defaults array in the script)
bash redirect-check.sh

# Pass URLs as arguments
bash redirect-check.sh \
  https://example.com/old-path/ \
  https://example.com/new-path/

# Pipe a list of URLs from a file
cat urls.txt | xargs bash redirect-check.sh
```

#### Example Output

```
https://example.com/contact-us/ => 301 -> https://example.com/contact/
https://example.com/cart/ => 200 ->
https://example.com/old-page/ => 404 ->
```

---

### monitor.sh (285 lines)

Orchestrator that runs all four monitoring scripts in sequence and generates a consolidated markdown summary report.

#### Features

- **Runs All Monitors**:
  - `traffic-monitor.sh` — traffic analysis
  - `security-monitor.sh` — security threat detection
  - `ai-bot-monitor.sh` — AI crawler analysis
  - `error-monitor.sh` — error logs across nginx, PHP-FPM, WordPress, MySQL, systemd

- **Timestamped Output Files** (for the default site):
  - `traffic-monitor-YYYY-MM-DD-HHmmss.txt`
  - `security-monitor-YYYY-MM-DD-HHmmss.txt`
  - `ai-bot-monitor-YYYY-MM-DD-HHmmss.txt`
  - `error-monitor-YYYY-MM-DD-HHmmss.txt`
  - `monitoring-summary-YYYY-MM-DD.md` — consolidated markdown report

  When a non-default `domain` argument is passed, each filename gets a
  `-<domain>` suffix (e.g. `traffic-monitor-othersite.com-YYYY-MM-DD-HHmmss.txt`)
  so reports for multiple sites on the same server don't collide.

- **Auto-Detects Context**:
  - Production server (`/srv/www/<domain>` present): saves to `~/monitoring/`
  - Local or other context: saves to `./monitoring-reports/`

- **Summary Report Includes**:
  - Site name, total requests, real user traffic, unique visitors, bandwidth
  - Security alert and warning counts with top alerts listed
  - AI crawler share of traffic and bandwidth
  - Error-log entry totals, plus PHP segfault and OOM-kill counts called out
    separately (those take down requests without leaving an access-log trace)
  - Top 10 most requested pages (real users)
  - Recommendations and next steps

  Run it as `root` to get the systemd portion of the error report; as `web` those
  sections are marked skipped.

#### Usage

```bash
# Remote execution (recommended — streams script over SSH)
ssh web@example.com 'bash -s' < scripts/monitoring/monitor.sh

# Remote with custom hours window
ssh web@example.com 'bash -s' < scripts/monitoring/monitor.sh 48

# Remote, for a different site on the same server
ssh web@example.com 'bash -s' < scripts/monitoring/monitor.sh 24 othersite.com

# Local execution on production server
./monitor.sh 24
./monitor.sh 24 othersite.com
```

---

### updown-webhook-handler.sh (181 lines)

Event handler for updown.io webhook alerts with automated diagnostics and reporting.

#### Features

- **Three Event Types**:

  1. **Down/Downtime**
     - Analyzes logs for root cause
     - Generates comprehensive diagnostic report
     - Investigates recent errors and traffic

  2. **Up/Uptime**
     - Documents recovery time
     - Logs recovery event

  3. **SSL Expiry**
     - Sends email warning
     - Provides renewal instructions

- **Downtime Analysis Report**:
  - Recent 5xx errors from access log
  - Nginx error log tail (last 50 lines)
  - Traffic analysis (calls traffic-monitor.sh)
  - Security alerts (calls security-monitor.sh)
  - System resources (disk, memory usage)
  - Active connection count

- **Report Storage**: `/home/web/monitoring/updown-alerts/`

- **Email Alerts** (optional):
  - Set `ALERT_EMAIL` environment variable
  - Uses `mail` command (sendmail)

#### Usage

```bash
# Handle downtime event
./updown-webhook-handler.sh example.com down

# Handle recovery event
./updown-webhook-handler.sh example.com up

# Handle SSL expiry with email
ALERT_EMAIL=admin@example.com ./updown-webhook-handler.sh example.com ssl

# Called automatically by webhook receiver
```

#### Example Downtime Report

```
=== Updown.io Alert: example.com DOWN ===
Time: 2025-12-31 12:34:56

=== Recent 5xx Errors ===
[31/Dec/2025:12:34:45] 502 /api/users - 2.341s
[31/Dec/2025:12:34:47] 502 /api/posts - 2.156s
[31/Dec/2025:12:34:50] 503 / - 30.001s

=== Nginx Error Log (Last 50 lines) ===
2025/12/31 12:34:45 [error] upstream timed out (110: Connection timed out)
2025/12/31 12:34:47 [error] no live upstreams while connecting to upstream
...

=== Traffic Analysis (Last 1 Hour) ===
[Output from traffic-monitor.sh]

=== Security Scan (Last 1 Hour) ===
[Output from security-monitor.sh]

=== System Resources ===
Disk Usage: 78% /dev/sda1
Memory: 3.2GB / 4.0GB (80%)
Active Connections: 42

=== Action Items ===
1. Review PHP-FPM worker configuration
2. Check database connection pool
3. Investigate recent deployment
```

---

### updown-webhook-receiver.php (161 lines)

PHP webhook receiver for updown.io with HMAC signature verification and secure event processing.

#### Features

- **Security**:
  - HMAC-SHA256 signature verification
  - Configurable webhook secret
  - Validates POST requests only
  - JSON payload validation

- **Event Mapping**:
  - `check.down` → `down`
  - `check.up` → `up`
  - `check.ssl_expiry` → `ssl`

- **Background Processing**:
  - Executes handler script asynchronously
  - Returns HTTP 200 immediately
  - Prevents webhook timeout

- **Logging**:
  - Records all webhook activity
  - Timestamp and event type
  - Payload preview
  - Error messages

- **Error Handling**:
  - Invalid signature → HTTP 403
  - Invalid JSON → HTTP 400
  - Missing parameters → HTTP 400
  - Success → HTTP 200 with JSON response

#### Installation

1. **Configure constants**:
   ```php
   define('WEBHOOK_SECRET', 'your-webhook-secret-here');
   define('HANDLER_SCRIPT', '/home/web/monitoring/updown-webhook-handler.sh');
   define('ALERT_EMAIL', 'admin@example.com');
   define('LOG_FILE', '/home/web/monitoring/webhook.log');
   ```

2. **Upload to web-accessible location**:
   ```bash
   # Not in document root recommended
   /home/web/monitoring/webhook.php

   # Or in public_html if necessary
   /srv/www/example.com/current/web/webhook.php
   ```

3. **Set permissions**:
   ```bash
   chown web:www-data webhook.php
   chmod 750 webhook.php
   ```

4. **Configure in updown.io**:
   - Webhook URL: `https://example.com/webhook.php`
   - Webhook secret: `your-webhook-secret-here`
   - Events: check.down, check.up, check.ssl_expiry

#### Testing

```bash
# Test webhook locally
curl -X POST https://example.com/webhook.php \
  -H "Content-Type: application/json" \
  -H "X-Updown-Signature: signature-here" \
  -d '{"event":"check.down","check":{"url":"https://example.com"}}'

# Check logs
tail -f /home/web/monitoring/webhook.log
```

#### Security Considerations

1. **Secret Protection**:
   - Use strong random secret (32+ characters)
   - Store outside web root if possible
   - Never commit secrets to version control

2. **HTTPS Only**:
   - Configure updown.io to use HTTPS webhook URL
   - Reject HTTP requests

3. **IP Whitelisting** (optional):
   - Restrict to updown.io IP ranges
   - Add nginx `allow` directives

4. **File Permissions**:
   - `chmod 750` for script files
   - `chown web:www-data` for proper ownership

---

## Automation with Cron

### Backup Automation

`db-backup.sh` runs on your machine, not the server (it SSHes out), so it
doesn't belong in a server crontab. For scheduled/automated database
backups, use the Ansible playbook instead:

```bash
# Daily database backup at 2 AM, from wherever the playbook is scheduled
0 2 * * * cd /path/to/trellis && ansible-playbook /path/to/wp-ops/trellis/backup/database-backup.yml -e site=example.com -e env=production > /var/log/db-backup.log 2>&1
```

`site-backup.sh` is still server-side and belongs in the server's own crontab:

```bash
# Weekly full site backup on Sundays at 3 AM
0 3 * * 0 /srv/scripts/backup/site-backup.sh example.com > /var/log/site-backup.log 2>&1

# Backup retention cleanup (30 days)
0 4 * * * find /srv/backups -name "*.gz" -mtime +30 -delete
```

### Monitoring Automation

```bash
# Run all monitors daily at 9 AM (traffic + security + AI bots + summary)
0 9 * * * /srv/scripts/monitoring/monitor.sh 24 >> /var/log/monitoring.log 2>&1

# Hourly security scan (standalone)
0 * * * * /srv/scripts/monitoring/security-monitor.sh /srv/www/example.com/logs/access.log 1 50 > /var/log/security-scan.log 2>&1

# Daily traffic report at 9 AM (standalone)
0 9 * * * /srv/scripts/monitoring/traffic-monitor.sh /srv/www/example.com/logs/access.log 24 > /var/log/traffic-report.log 2>&1

# Weekly AI crawler report on Mondays at 8 AM
0 8 * * 1 /srv/scripts/monitoring/ai-bot-monitor.sh /srv/www/example.com/logs/access.log 168 > /var/log/ai-bot-report.log 2>&1
```

---

## Best Practices

### General

1. **Test in development first** - Always test scripts in staging before production
2. **Use version control** - Commit all scripts to git
3. **Document customizations** - Add comments for site-specific changes
4. **Monitor logs** - Check script output regularly
5. **Set proper permissions** - Use `chmod 750` for executable scripts

### Backups

1. **Multiple locations** - Store backups on different servers/services
2. **Test restoration** - Verify backups can be restored monthly
3. **Monitor disk space** - Ensure sufficient space before backups
4. **Encrypt sensitive backups** - Use GPG for database backups
5. **Automate with cron** - Schedule regular backups

### Monitoring

1. **Set appropriate thresholds** - Adjust alert levels for your traffic
2. **Review reports regularly** - Don't just collect, analyze
3. **Act on alerts** - Block malicious IPs promptly
4. **Combine tools** - Use both traffic and security monitoring
5. **Document incidents** - Keep records of attacks and responses

### GitHub Integration

1. **Review AI descriptions** - Always verify before creating PR
2. **Use --no-ai for simple PRs** - Save tokens on trivial changes
3. **Keep git history clean** - Squash commits when appropriate
4. **Link issues in PRs** - Reference related issues
5. **Update branch before PR** - Rebase on latest main

---

## Troubleshooting

### Script Permission Errors

```bash
# Make script executable
chmod +x script-name.sh

# Check ownership
ls -l script-name.sh

# Fix ownership if needed
chown web:www-data script-name.sh
```

### Backup Script Issues

**Disk space errors:**
```bash
# Check available space
df -h /srv/backups

# Clean old backups manually
find /srv/backups -name "*.gz" -mtime +30 -delete
```

**WP-CLI not found:**
```bash
# Verify WP-CLI installation
which wp

# Install if missing (Trellis includes by default)
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp
```

### Monitoring Script Issues

**Log file not found:**
```bash
# Verify log location (Trellis default)
ls -la /srv/www/example.com/logs/

# Check Nginx log configuration
grep -r "access_log" /etc/nginx/sites-enabled/
```

**Empty reports:**
```bash
# Check log file has data
tail /srv/www/example.com/logs/access.log

# Verify time window (may be too narrow)
./traffic-monitor.sh /path/to/log 24  # Try larger window
```

### Webhook Issues

**Signature verification failed:**
- Verify webhook secret matches in updown.io and PHP script
- Check HMAC calculation in PHP
- Review webhook payload in logs

**Handler script not executing:**
```bash
# Check script permissions
ls -l /home/web/monitoring/updown-webhook-handler.sh

# Verify path in PHP receiver
grep HANDLER_SCRIPT webhook.php

# Test handler manually
./updown-webhook-handler.sh example.com down
```

---

## Further Reading

- [WP-CLI Documentation](https://wp-cli.org/)
- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)
- [GitHub CLI Documentation](https://cli.github.com/)
- [Nginx Log Format](https://nginx.org/en/docs/http/ngx_http_log_module.html)
- [Updown.io Webhooks](https://updown.io/webhooks)
- [HMAC Authentication](https://en.wikipedia.org/wiki/HMAC)

---

## Contributing

When adding new scripts:

1. Include header comments with description, usage, and author
2. Use color-coded output for readability (`\033[0;32m` for green, etc.)
3. Add error handling and validation
4. Provide usage examples in comments
5. Test with various inputs and edge cases
6. Document in this README
7. Follow existing code style
8. Include logging where appropriate
