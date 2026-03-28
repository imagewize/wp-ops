# Automation Scripts

Production-ready Bash and PHP scripts for WordPress operations, GitHub integration, server monitoring, and backup automation.

## Overview

This directory contains 12 utility scripts organized into four functional areas:

- **GitHub Integration** - AI-powered pull request creation
- **WordPress Management** - Plugin and theme release automation, file synchronization
- **Operations** - Server monitoring and backup infrastructure
- **Webhook Integration** - Updown.io downtime alert handling

## Directory Structure

```
scripts/
├── backup/                      # Backup automation scripts
│   ├── db-backup.sh            # Database-only backup with URL replacement
│   └── site-backup.sh          # Complete site backup (DB + files + config)
├── monitoring/                  # Server monitoring and alerting
│   ├── ai-bot-monitor.sh       # AI crawler traffic analysis (GPTBot, ClaudeBot, etc.)
│   ├── run-monitoring.sh       # Orchestrator: runs all monitors and generates summary
│   ├── security-monitor.sh     # Nginx security threat detection
│   ├── traffic-monitor.sh      # Nginx traffic analysis and reporting
│   ├── updown-webhook-handler.sh     # Webhook event handler
│   └── updown-webhook-receiver.php   # Webhook HTTP receiver
├── create-pr.sh                # AI-powered GitHub PR creation
├── release-plugin.sh           # WordPress plugin version release automation
├── release-theme.sh            # WordPress theme version release automation
└── rsync-theme.sh             # Theme file synchronization utility
```

## Quick Start

### Prerequisites

- Bash shell (included on all Linux/macOS systems)
- Git (for GitHub integration scripts)
- WP-CLI (for WordPress backup/release scripts)
- Claude CLI, Codex, or Mistral Vibe (optional, for AI features)
- PHP (for webhook receiver)

### Common Operations

```bash
# Create GitHub PR with AI description
./scripts/create-pr.sh main "Add feature name"

# Release WordPress theme version
./scripts/release-theme.sh theme-name 1.2.5

# Backup WordPress database
./scripts/backup/db-backup.sh example.com production

# Monitor Nginx traffic
./scripts/monitoring/traffic-monitor.sh /var/log/nginx/access.log 6

# Scan for security threats
./scripts/monitoring/security-monitor.sh /srv/www/example.com/logs/access.log 24

# Analyze AI crawler traffic
./scripts/monitoring/ai-bot-monitor.sh /srv/www/example.com/logs/access.log 24

# Run all monitors and save timestamped reports
ssh web@example.com 'bash -s' < scripts/monitoring/run-monitoring.sh
```

---

## GitHub Integration

### create-pr.sh (635 lines)

Intelligent GitHub pull request creation with AI-powered descriptions using Claude CLI, Codex, or Mistral Vibe.

#### Features

- **AI-Generated Descriptions**:
  - Analyzes git diff and commit history
  - Generates professional PR body with summarized intro
  - Groups file changes by status (Added/Modified/Deleted/Renamed)
  - Auto-detects change categories (dependencies, docs, config, JS, PHP, etc.)
  - Creates clickable GitHub file links

- **Interactive Mode** (default):
  - Prompts for PR title
  - Asks for base branch
  - Requests AI description generation
  - Shows preview before creation

- **Non-Interactive Mode**:
  - Accepts command-line arguments
  - Skips all prompts
  - Ideal for automation

- **Update Mode**:
  - Regenerates description for existing PRs
  - Preserves PR number
  - Updates body only

- **Flags**:
  - `--no-ai` - Skip AI generation (simple PR, saves tokens)
  - `--no-interactive` - Non-interactive mode
  - `--update` - Update existing PR description
  - `--ai=claude|codex|vibe` - Choose AI provider

#### Usage

```bash
# Interactive mode with AI description
./create-pr.sh

# Non-interactive with arguments
./create-pr.sh main "Add feature name"

# Skip AI generation (saves tokens)
./create-pr.sh --no-ai

# Update existing PR
./create-pr.sh --update

# Specific AI provider
./create-pr.sh --ai=codex main "Fix bug"
./create-pr.sh --ai=vibe main "Add feature"
```

#### Example Output

```markdown
## Summary

This PR adds user authentication with JWT tokens, implements login/logout endpoints, and updates the frontend to handle authenticated requests.

## Changes

### Added
- [src/auth/jwt.js](https://github.com/user/repo/blob/hash/src/auth/jwt.js) - JWT token generation and validation
- [src/routes/auth.js](https://github.com/user/repo/blob/hash/src/routes/auth.js) - Authentication endpoints

### Modified
- [src/api/client.js](https://github.com/user/repo/blob/hash/src/api/client.js) - Add auth header injection
- [package.json](https://github.com/user/repo/blob/hash/package.json) - Add jsonwebtoken dependency
```

#### Token Usage

- **With AI**: 500-1,500 tokens (vs 2,000-10,000 manual)
- **Without AI**: 0 tokens
- **Cost**: ~$0.01-0.05 per PR (Claude Sonnet)

#### Requirements

```bash
# Install gh CLI
brew install gh  # macOS
apt install gh   # Ubuntu

# Authenticate
gh auth login

# Install Claude CLI (optional)
npm install -g @anthropics/claude-cli

# Or use Codex (optional)
pip install openai-codex

# Or use Mistral Vibe (optional)
npm install -g @mistralai/vibe-cli
```

---

## WordPress Management

### release-plugin.sh (422 lines)

Automates WordPress plugin version releases with AI-generated changelogs using Claude CLI or Codex.

#### Features

- **AI-Generated Changelogs**:
  - Supports Claude CLI or Codex for changelog generation
  - Analyzes git diff between current branch and main branch
  - Generates two changelog formats:
    - **CHANGELOG.md**: Detailed Keep a Changelog format (Changed, Added, Fixed, Technical)
    - **readme.txt**: Concise WordPress.org style
  - Customizable AI tool selection with `--ai=claude|codex` flag

- **Semantic Versioning**:
  - Validates X.Y.Z format
  - Prevents invalid version numbers
  - Updates version in three locations:
    - Plugin header comment in main PHP file
    - Plugin version constant (e.g., `ELAYNE_BLOCKS_VERSION`)
    - Stable tag in readme.txt

- **Updates Three Files**:
  - Main plugin file (e.g., `elayne-blocks.php`) - Version header and constant
  - `readme.txt` - Stable tag and changelog
  - `CHANGELOG.md` - Detailed version history

- **Safety Features**:
  - Shows git diff before committing
  - Interactive confirmation prompts
  - Optional `--commit` flag for automatic commits
  - Preserves `.bak` backup files
  - Color-coded output with progress indicators
  - Detects no changes between branches

#### Usage

```bash
# Generate changelog with AI (manual commit)
./release-plugin.sh 2.5.3

# Generate changelog and auto-commit
./release-plugin.sh 2.5.3 --commit

# Specify AI tool
./release-plugin.sh 2.5.3 --ai=codex
./release-plugin.sh 2.5.3 --commit --ai=claude

# Interactive AI tool selection (if both installed)
./release-plugin.sh 2.5.3
# Prompts: "Choose AI tool [default: claude]:"
```

#### Example Workflow

1. Create feature branch and make changes
2. Run release script:
   ```bash
   ./release-plugin.sh 2.5.3
   ```
3. Script analyzes `git diff main..HEAD`
4. AI generates professional changelog
5. Updates version in all three files
6. Shows preview of changes
7. Optionally commits changes
8. Push and create PR:
   ```bash
   git push origin feature-branch
   ./create-pr.sh main "Elayne Blocks Version 2.5.3"
   ```

#### Example Changelog Output

**CHANGELOG.md format:**
```markdown
## [2.5.3] - 2026-01-20

### Added
**Mega Menu Icon Features:**
- Added new icon-based pattern for mega menu content
- Supports custom icons with flexible positioning

### Changed
- Updated block editor controls for better UX
- Improved pattern preview in block inserter

### Fixed
- Hero section alignment on tablet devices
- Missing alt text in gallery patterns
```

**readme.txt format:**
```
= 2.5.3 =
* Added: Mega Menu Icon Features pattern with custom icon support
* Changed: Updated block editor controls for better UX
* Fixed: Hero section tablet alignment and gallery alt text
```

#### Configuration

The script automatically detects the plugin's main PHP file and version constant. Default behavior:
- Analyzes changes from `main` branch
- Uses current branch for updates
- Generates changelog via Claude CLI (if available)
- Shows preview before committing

#### AI Tool Selection

**Automatic detection:**
- If only Claude CLI installed → uses Claude
- If only Codex installed → uses Codex
- If both installed → prompts for selection

**Manual selection:**
```bash
./release-plugin.sh 2.5.3 --ai=claude
./release-plugin.sh 2.5.3 --ai=codex
```

**Environment variables:**
```bash
# Custom CLI command names
export CLAUDE_COMMAND="claude-custom"
export CODEX_COMMAND="codex-custom"

# Custom CLI arguments
export CLAUDE_CLI_ARGS="--model opus"
export CODEX_CLI_ARGS="--temperature 0.7"
```

#### Requirements

```bash
# Install Claude CLI (recommended)
npm install -g @anthropic-ai/claude-cli

# Configure API key
export ANTHROPIC_API_KEY="your-key-here"

# Or install Codex CLI (alternative)
npm install -g @openai/codex
export OPENAI_API_KEY="your-key-here"
```

#### Token Usage

- **With AI**: 500-1,500 tokens depending on diff size
- **Without AI**: Manual changelog editing required
- **Cost**: ~$0.01-0.05 per release (Claude Sonnet)

---

## Theme Management

### release-theme.sh (346 lines)

Automates WordPress theme version releases with AI-generated changelogs (Claude CLI or Codex).

#### Features

- **Supports Multiple Installations**:
  - `demo/` directory (Bedrock structure)
  - `site/` directory (Bedrock structure)
  - Auto-detects available installations

- **Semantic Versioning**:
  - Validates X.Y.Z format
  - Prevents invalid version numbers
  - Supports pre-release suffixes (1.2.3-beta)

- **AI-Generated Changelogs**:
  - Supports Claude CLI or Codex for changelog generation
  - Analyzes git diff since last tag
  - Generates two changelog formats:
    - **CHANGELOG.md**: Detailed Keep a Changelog format (Changed, Added, Fixed, Technical)
    - **readme.txt**: Concise WordPress.org style

- **Updates Three Files**:
  - `style.css` - Version header
  - `readme.txt` - Stable tag and changelog
  - `CHANGELOG.md` - Detailed version history

- **Safety Features**:
  - Shows git diff before committing
  - Optional `--commit` flag for automatic commits
  - Preserves `.bak` backup files
  - Color-coded output with progress indicators

#### Usage

```bash
# Release version (manual commit)
./release-theme.sh theme-name 1.2.5

# Release with automatic commit
./release-theme.sh theme-name 1.0.0 --commit

# Specify AI tool
./release-theme.sh theme-name 1.2.5 --ai=codex
./release-theme.sh theme-name 1.0.0 --commit --ai=claude

# Examples
./release-theme.sh elayne 1.2.5
./release-theme.sh nynaeve 2.0.0 --commit
```

#### Configuration

Edit script to set theme paths:

```bash
# Bedrock installation directories
DEMO_DIR="$HOME/code/example.com/demo/web/app/themes"
SITE_DIR="$HOME/code/example.com/site/web/app/themes"
```

#### Example Changelog Output

**CHANGELOG.md format:**
```markdown
## [1.2.5] - 2025-01-15

### Changed
- Updated navigation menu styling for better mobile responsiveness
- Improved block pattern spacing consistency

### Added
- New testimonials block pattern
- Support for WebP and AVIF image formats

### Fixed
- Hero section alignment on tablet devices
- Missing alt text in gallery patterns

### Technical
- Updated Tailwind CSS to 3.4.0
- Optimized build process with reduced bundle size
```

**readme.txt format:**
```
= 1.2.5 =
* Updated navigation menu for mobile
* Added testimonials block pattern
* Fixed hero section tablet alignment
```

#### Requirements

```bash
# Install Claude CLI (recommended)
npm install -g @anthropics/claude-cli

# Configure API key
export ANTHROPIC_API_KEY="your-key-here"

# Or install Codex CLI (alternative)
npm install -g @openai/codex
export OPENAI_API_KEY="your-key-here"
```

---

### rsync-theme.sh (28 lines)

Simple rsync wrapper for theme synchronization between Trellis and standalone repositories.

#### Features

- **Archive Mode**: Preserves timestamps, permissions, ownership
- **Selective Deletion**: Removes destination files not in source
- **Exclude Filters**:
  - `node_modules/`, `vendor/` (dependencies)
  - `.git/`, `.github/` (version control)
  - `create-pr.sh`, `.distignore` (repo-specific files)

#### Configuration

Edit script with your paths:

```bash
SOURCE="$HOME/code/example.com/demo/web/app/themes/elayne/"
DESTINATION="$HOME/code/elayne/"
```

#### Usage

```bash
# Run synchronization
./rsync-theme.sh

# Output shows:
# - Files sent/received
# - Total size transferred
# - Speedup achieved
```

#### Use Cases

- Sync theme from Bedrock to standalone repo
- Prepare theme for WordPress.org submission
- Backup theme to separate repository
- Development workflow: edit in Trellis, sync to standalone for distribution

---

## Backup Scripts

### db-backup.sh (196 lines)

Trellis-aware database backup with optional URL replacement for staging/development environments.

#### Features

- **WP-CLI Based Export**:
  - `--add-drop-table` for clean imports
  - `--single-transaction` for InnoDB consistency
  - `--default-character-set=utf8mb4` for proper encoding
  - Automatic gzip compression

- **Backup Metadata**:
  - Creates `.txt` info file with:
    - WordPress version
    - Database name, size, table count
    - Charset information
    - Backup timestamp

- **URL Replacement** (for non-production):
  - **Staging**: Replaces `.com` with `.staging.com`
  - **Development**: Generates `.test` URL variants
  - Creates separate backup file with replaced URLs

- **Retention Policy**:
  - 30-day automatic cleanup
  - Removes old `.sql.gz` and `.txt` files

- **Colored Logging**:
  - Timestamps on all messages
  - Color-coded output (green=success, red=error, yellow=warning)

#### Usage

```bash
# Production backup (no URL replacement)
./db-backup.sh example.com production

# Staging backup (with URL replacement)
./db-backup.sh demo.example.com staging

# Development backup (with URL replacement)
./db-backup.sh example.com development
```

#### Output Files

```
/srv/backups/example.com/database/
├── production_db_20251231_120000.sql.gz
├── staging_db_with_urls_20251231_120000.sql.gz
└── backup_info_20251231_120000.txt
```

#### Directory Structure

```bash
/srv/backups/{site}/
└── database/
    ├── {env}_db_{timestamp}.sql.gz
    ├── {env}_db_with_urls_{timestamp}.sql.gz  # staging/dev only
    └── backup_info_{timestamp}.txt
```

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

### run-monitoring.sh (285 lines)

Orchestrator that runs all three monitoring scripts in sequence and generates a consolidated markdown summary report.

#### Features

- **Runs All Monitors**:
  - `traffic-monitor.sh` — traffic analysis
  - `security-monitor.sh` — security threat detection
  - `ai-bot-monitor.sh` — AI crawler analysis

- **Timestamped Output Files**:
  - `traffic-monitor-YYYY-MM-DD-HHmmss.txt`
  - `security-monitor-YYYY-MM-DD-HHmmss.txt`
  - `ai-bot-monitor-YYYY-MM-DD-HHmmss.txt`
  - `monitoring-summary-YYYY-MM-DD.md` — consolidated markdown report

- **Auto-Detects Context**:
  - Production server (`/srv/www` present): saves to `~/monitoring/`
  - Local or other context: saves to `./monitoring-reports/`

- **Summary Report Includes**:
  - Total requests, real user traffic, unique visitors, bandwidth
  - Security alert and warning counts with top alerts listed
  - AI crawler share of traffic and bandwidth
  - Top 10 most requested pages (real users)
  - Recommendations and next steps

#### Usage

```bash
# Remote execution (recommended — streams script over SSH)
ssh web@example.com 'bash -s' < scripts/monitoring/run-monitoring.sh

# Remote with custom hours window
ssh web@example.com 'bash -s' < scripts/monitoring/run-monitoring.sh 48

# Local execution on production server
./run-monitoring.sh 24
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

```bash
# Daily database backup at 2 AM
0 2 * * * /srv/scripts/backup/db-backup.sh example.com production > /var/log/db-backup.log 2>&1

# Weekly full site backup on Sundays at 3 AM
0 3 * * 0 /srv/scripts/backup/site-backup.sh example.com > /var/log/site-backup.log 2>&1

# Backup retention cleanup (30 days)
0 4 * * * find /srv/backups -name "*.gz" -mtime +30 -delete
```

### Monitoring Automation

```bash
# Run all monitors daily at 9 AM (traffic + security + AI bots + summary)
0 9 * * * /srv/scripts/monitoring/run-monitoring.sh 24 >> /var/log/monitoring.log 2>&1

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
