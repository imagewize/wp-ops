# Automation Scripts

Production-ready Bash, PHP, and Python scripts for WordPress operations, GitHub integration, server monitoring, and backup automation.

## Overview

This directory contains utility scripts organized into functional areas:

- **GitHub Integration** - AI-powered pull request creation, manual GitHub release asset uploads, and repository traffic analytics
- **WordPress Management** - Plugin and theme release automation, WordPress.org SVN deployment, file synchronization
- **WooCommerce** - Product variation bulk creation
- **Image Utilities** - WebP conversion optimized for WordPress and Facebook OG images, square-canvas padding, and Openverse (CC-licensed) image search/download
- **Pattern Screenshots** - Playwright/sharp toolkit for screenshotting WordPress block patterns and converting them to WebP
- **Git Utilities** - Quick access to recent commit history
- **Content Reporting** - Published-post counts by year and month (blog posts only)
- **Operations** - Server resource/traffic/security monitoring and backup infrastructure
- **Webhook Integration** - Updown.io downtime alert handling

## Directory Structure

```
scripts/
├── backup/                      # Backup automation scripts
│   ├── db-backup.sh            # Back up a remote database over SSH straight to your machine
│   ├── db-pull.sh              # Pull a remote database into development via SSH
│   └── site-backup.sh          # Complete site backup (DB + files + config)
├── git/                         # Git/GitHub utilities
│   ├── create-pr.sh            # AI-powered GitHub PR creation
│   ├── gh-traffic.sh           # Fetch and display GitHub repository traffic statistics
│   └── git-log-oneline.sh      # Show recent git commits as one-liners
├── images/                      # Image resizing and conversion
│   ├── batch-resize.sh         # Batch resize and center-crop images for featured images
│   ├── convert-to-webp.sh      # JPG to WebP conversion with center-crop (Facebook OG)
│   ├── make-square-webp.sh     # Pad an image onto a square canvas and export as WebP
│   ├── openverse_search.py     # Search Openverse for CC-licensed images
│   ├── openverse_download.py   # Download Openverse image URLs, optionally converting to WebP
│   ├── svg-to-jpg.sh           # Render design SVGs to JPG via librsvg (native size or forced)
│   └── svg-to-png.sh           # Render design SVGs to PNG via librsvg (lossless, best for text)
├── misc/                        # Miscellaneous utilities
│   ├── convert-screenshot-for-claude.sh  # Convert PNG screenshots to JPEG for Claude Code compatibility
│   ├── find-and-replace-files.sh     # Batch find and replace files across directory trees
│   ├── post-count.sh                 # Count published blog posts by year/month (blog posts only)
│   └── README-FIND-AND-REPLACE.md    # Docs for find-and-replace-files.sh
├── monitoring/                  # Server monitoring and alerting
│   ├── 404-checker.sh          # Internal broken-link checker (homepage scan or recursive spider)
│   ├── ai-bot-monitor.sh       # AI crawler traffic analysis (GPTBot, ClaudeBot, etc.)
│   ├── error-monitor.sh        # Nginx/PHP-FPM/WordPress/MySQL/systemd error log review
│   ├── monitor.sh              # Orchestrator: runs all monitors and generates summary
│   ├── redirect-check.sh       # Mass URL redirect checker using curl
│   ├── security-monitor.sh     # Nginx security threat detection
│   ├── server-monitor.sh       # Live CPU/memory/disk/PHP-FPM/MySQL/nginx resource snapshot over SSH
│   ├── traffic-monitor.sh      # Nginx traffic analysis and reporting
│   ├── traffic-by-country.sh   # Filter Nginx logs by visitor country (geoip2fast) and show real visits
│   ├── cf7-smoke-test.js             # Playwright CF7 form submission smoke test
│   ├── updown-webhook-handler.sh     # Webhook event handler
│   └── updown-webhook-receiver.php   # Webhook HTTP receiver
├── patterns/                    # WordPress block pattern screenshot toolkit
│   ├── screenshot-patterns.sh  # End-to-end: create temp WP page, screenshot, delete, convert to WebP
│   ├── screenshot-url.js       # Generic Playwright URL/element screenshot primitive
│   ├── convert-to-webp.js      # Sharp-based PNG to WebP converter
│   ├── trim-screenshots.sh     # Trim whitespace from a directory of pattern screenshots (ImageMagick)
│   ├── center-screenshots.sh   # Center screenshots on a fixed canvas (ImageMagick)
│   └── README.md               # Setup and usage docs
├── release/                     # Release automation
│   ├── deploy-plugin-wporg.sh  # Publish a plugin to the WordPress.org directory via SVN
│   ├── release-plugin.sh       # WordPress plugin version release automation
│   ├── release-theme.sh        # WordPress theme version release automation
│   └── upload-release-asset.sh # Manual GitHub release zip upload (fallback for failed Actions)
├── sync/                        # File synchronization
│   ├── rsync-package-to-site.sh  # Push a plugin/theme working copy into a Bedrock site
│   └── rsync-theme.sh            # Theme file synchronization utility
└── woocommerce/                # WooCommerce automation
    └── create-product-variations.sh  # Bulk-create product variations via WP-CLI
```

## Quick Start

### Prerequisites

- Bash shell (included on all Linux/macOS systems)
- Git (for GitHub integration scripts)
- WP-CLI (for WordPress backup/release scripts)
- Claude CLI, Codex, or Mistral Vibe (optional, for AI features)
- PHP (for webhook receiver)
- Python 3 (for `openverse_search.py`/`openverse_download.py` — stdlib only, no pip installs needed)

### Common Operations

```bash
# Batch resize screenshots to 1200x630 with custom naming
./scripts/images/batch-resize.sh -w 1200 -H 630 -o "my-featured-image" *.png

# Bulk-create WooCommerce product variations
./scripts/woocommerce/create-product-variations.sh

# Convert JPG to WebP for Facebook OG / featured image (800x419, center crop)
./scripts/images/convert-to-webp.sh image.jpg

# Pad an image onto a square canvas and export as WebP
./scripts/images/make-square-webp.sh logo.png logo-square.webp

# Search Openverse for CC0-licensed images
./scripts/images/openverse_search.py "wordpress hosting" --limit 3

# Download Openverse image URLs and convert to WebP
./scripts/images/openverse_download.py --url https://example.com/photo.jpg --convert-webp

# Render design SVGs to JPG (native size, or forced to a platform spec)
./scripts/images/svg-to-jpg.sh designs/linkedin
./scripts/images/svg-to-jpg.sh -w 1920 -h 1080 designs/mastodon

# Render design SVGs to PNG (lossless — prefer for banners with text or logos)
./scripts/images/svg-to-png.sh designs/linkedin

# Create GitHub PR with AI description
./scripts/git/create-pr.sh main "Add feature name"

# Show GitHub repository traffic statistics
./scripts/git/gh-traffic.sh imagewize/nynaeve

# Show recent git commits as one-liners
./scripts/git/git-log-oneline.sh
./scripts/git/git-log-oneline.sh 25

# Count published blog posts by year (production, over SSH)
./scripts/misc/post-count.sh --ssh web@example.com

# Count just this year's blog posts, or a month-by-month breakdown
./scripts/misc/post-count.sh --ssh web@example.com --year 2026
./scripts/misc/post-count.sh --ssh web@example.com --months 2026

# Release WordPress theme version
./scripts/release/release-theme.sh theme-name 1.2.5

# Publish a plugin to WordPress.org via SVN (stage + review, then commit)
cd ~/code/my-plugin
~/code/wp-ops/scripts/release/deploy-plugin-wporg.sh my-plugin --build "npm ci && npx webpack"

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

## WooCommerce

### create-product-variations.sh (71 lines)

Bulk-create WooCommerce product variations via WP-CLI. Generates all combinations of specified attribute values for a variable product.

#### Features

- **Bulk Variation Creation**: Creates all combinations of attribute values in one run
- **Configurable via Environment Variables**: Product ID, price, attributes, Trellis VM settings
- **Trellis VM Compatible**: Uses `trellis vm shell` with configurable workdir and URL
- **Success/Failure Tracking**: Counts created and failed variations with detailed output
- **Companion Documentation**: See [`wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md`](../docs/wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md) for attribute setup

#### Configuration

Edit the configuration section at the top of the script:

```bash
TRELLIS_DIR="${TRELLIS_DIR:-/path/to/trellis}"
WORKDIR="${WORKDIR:-/srv/www/example.com/current}"
SITE_URL="${SITE_URL:-http://example.test/store}"  # include /store for multisite
PRODUCT_ID="${PRODUCT_ID:-36}"                      # parent variable product ID
REGULAR_PRICE="${REGULAR_PRICE:-99}"
WP_USER="${WP_USER:-admin}"
WP_PATH="${WP_PATH:-web/wp}"

# Attribute arrays — edit to match your product's registered attributes
ATTR1_SLUG="pa_leather-colour"
ATTR1_VALUES=("Tan" "Black" "Cognac" "Chestnut" "Navy")

ATTR2_SLUG="pa_style"
ATTR2_VALUES=("A4 with Notepad" "A4 Slim" "A5 with Notepad")
```

#### Usage

```bash
# Run with default configuration
./scripts/woocommerce/create-product-variations.sh

# Override product ID inline
PRODUCT_ID=42 ./scripts/woocommerce/create-product-variations.sh

# Full configuration override
PRODUCT_ID=42 REGULAR_PRICE=129 ./scripts/woocommerce/create-product-variations.sh
```

#### Example Output

```
Creating variations for product ID 36 on http://example.test/store
Attributes: pa_leather-colour × pa_style
---
[OK]   Tan / A4 with Notepad — Success: Variation created (ID: 37)
[OK]   Tan / A4 Slim — Success: Variation created (ID: 38)
[OK]   Tan / A5 with Notepad — Success: Variation created (ID: 39)
[OK]   Black / A4 with Notepad — Success: Variation created (ID: 40)
...
---
Done: 15 created, 0 failed.
```

#### Notes

- **Multisite**: The `--url` parameter must include the store path (e.g., `http://example.test/store`) for sub-site stores
- **Prerequisite**: Attribute values must already exist as terms before running this script
- **Dependencies**: WooCommerce installed and active, WP-CLI with WooCommerce extension


## Image Utilities

### batch-resize.sh

Batch resize one or more images with center-crop. Perfect for creating WordPress featured images from screenshots or other source images. Maintains aspect ratio during resize, then crops to exact dimensions.

#### Requirements

```bash
brew install imagemagick webp   # macOS
sudo apt-get install imagemagick webp  # Ubuntu/Debian
```

#### Usage

```bash
# Resize all PNGs to 1200x630 (Facebook OG ratio) with auto naming
./scripts/images/batch-resize.sh -w 1200 -H 630 *.png

# Resize with custom output prefix
./scripts/images/batch-resize.sh -w 800 -H 419 -o "featured-post" screenshot1.png screenshot2.png

# Convert to WebP format with high quality
./scripts/images/batch-resize.sh -w 1920 -H 1080 -f webp -q 90 screenshot.png

# Preview changes without modifying files (dry run)
./scripts/images/batch-resize.sh -w 1200 -H 630 -d *.jpg

# Process and delete originals after conversion (use with caution!)
./scripts/images/batch-resize.sh -w 800 -H 600 --delete image.png
```

#### Output

```
Processing 1/3: screenshot1.png
  Saved: featured-post-1.jpg (1200x630, q85, 120KB)

Processing 2/3: screenshot2.png
  Saved: featured-post-2.jpg (1200x630, q85, 115KB)

Processing 3/3: screenshot3.png
  Saved: featured-post-3.jpg (1200x630, q85, 118KB)

Batch resize complete. Processed 3 file(s).
```

### convert-to-webp.sh

Converts a JPG to WebP at 800×419 (1.91:1 Facebook Open Graph ratio) using a center crop so non-standard source images aren't distorted. Quality and dimensions are configurable.

#### Requirements

```bash
brew install imagemagick webp   # macOS
sudo apt-get install imagemagick webp  # Ubuntu/Debian
```

#### Usage

```bash
# Defaults: 800x419, quality 82
./scripts/images/convert-to-webp.sh featured.jpg

# Custom output filename
./scripts/images/convert-to-webp.sh featured.jpg hero.webp

# Custom quality and dimensions
./scripts/images/convert-to-webp.sh featured.jpg hero.webp 90 1200 630
```

#### Output

```
Saved: featured.webp (800x419, q82)
```

See also: `wordpress-utilities/snippets/webp-featured-image.md` for batch conversion commands.

### make-square-webp.sh

Pads an image onto a square canvas (letterboxing rather than cropping) and exports it as WebP — useful for logos, icons, or artwork that shouldn't be cropped to fit a square slot. Supports an optional left-margin offset for off-center source art.

#### Requirements

```bash
brew install imagemagick webp   # macOS
sudo apt-get install imagemagick webp  # Ubuntu/Debian
```

#### Usage

```bash
# Square canvas sized to the image's longest side, white background
./scripts/images/make-square-webp.sh logo.png logo-square.webp

# Fixed 2000px canvas, custom quality and background
./scripts/images/make-square-webp.sh logo.png logo-square.webp --size 2000 --quality 90 --background transparent

# Right-align the source art with a 200px left margin (asymmetric artwork)
./scripts/images/make-square-webp.sh logo.png logo-square.webp --left-pad 200 --size 2000
```

#### Output

```
Saved: logo-square.webp
```

### openverse_search.py / openverse_download.py

A pair of scripts for sourcing openly-licensed (CC0/CC-BY, etc.) images from [Openverse](https://openverse.org/) — useful for placeholder or production imagery on client sites without a licensed stock photo budget. `openverse_search.py` queries the API and prints candidates; `openverse_download.py` downloads chosen URLs (individually or from a manifest file) and can convert them to WebP in the same pass. Both are stdlib-only Python — no `pip install` required.

#### Requirements

```bash
brew install webp   # macOS, only needed for --convert-webp
```

#### Usage

```bash
# Search for CC0 images (default), print top 5
./scripts/images/openverse_search.py "wordpress hosting"

# Narrow by license, provider, and result count
./scripts/images/openverse_search.py "coffee shop" --license by --provider flickr --limit 10

# Raw JSON output (for piping into another tool)
./scripts/images/openverse_search.py "coffee shop" --json

# Download a single URL, converting to WebP and discarding the original
./scripts/images/openverse_download.py --url https://example.com/photo.jpg \
  --out-dir ./downloads --convert-webp

# Download a batch from a manifest file ("<url> <optional-filename>" per line, # for comments)
./scripts/images/openverse_download.py --manifest images.txt --out-dir ./downloads --convert-webp --resize 1200
```

#### Example Output

```
$ ./scripts/images/openverse_search.py "wordpress hosting" --limit 2
1. title='Server room'
   creator='Jane Doe'
   creator_url='https://openverse.org/user/janedoe'
   source='flickr'
   license='cc0' '1.0'
   url='https://live.staticflickr.com/.../server-room.jpg'
   landing='https://openverse.org/image/.../server-room'
```

#### Notes

- Always double-check the license and attribution requirements on the `landing` page before using an image commercially — Openverse aggregates metadata from multiple sources and it isn't always perfectly accurate.
- `openverse_download.py` skips (and warns on, not aborts) any URL that fails to download or convert, so a bad link in a large manifest doesn't kill the whole batch.

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
- **`convert-to-webp.js`** — standalone sharp-based PNG → WebP converter, single file
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

## Content Reporting

### post-count.sh

Counts published WordPress **blog posts** grouped by the year of `post_date`. Answers "how many posts have we published this year?" without pulling in pages, nav menu items, attachments, revisions, custom post types, or drafts.

By default it counts `post_type=post` and `post_status=publish` only — so custom post types (e.g. an `iw_audit` CPT) and pages are **not** included. Override `--type` / `--status` if you need a different slice.

Runs `wp db query`, so run it where WP-CLI works: inside the Trellis VM, on the production server, or from your host with `--ssh` (which wraps the query in an `ssh` call to the server).

#### Features

- **Blog posts only by default** — `post_type=post`, `post_status=publish`; CPTs, pages, menus, attachments, revisions, and drafts excluded
- **Three modes**: all-years breakdown (default), single-year total (`--year`), or monthly breakdown (`--months`)
- **Remote or local**: `--ssh HOST` runs against production over SSH; without it, runs against the current WP install
- **Multi-site**: point `--site` at any web root on the server (e.g. aseonomics.com)
- **Overridable slice**: `--type` / `--status` for pages, drafts, or a custom post type

#### Usage

```bash
# All years, blog posts only (over SSH to production)
./scripts/misc/post-count.sh --ssh web@example.com

# Just 2026's blog-post total
./scripts/misc/post-count.sh --ssh web@example.com --year 2026

# Month-by-month for 2026
./scripts/misc/post-count.sh --ssh web@example.com --months 2026

# Run locally inside the Trellis VM / on the server (no --ssh needed)
./scripts/misc/post-count.sh --year 2026

# aseonomics.com on the same server
./scripts/misc/post-count.sh --ssh web@example.com --site /srv/www/aseonomics.com/current

# Count published pages instead of posts
./scripts/misc/post-count.sh --ssh web@example.com --type page

# Syntax
./scripts/misc/post-count.sh [--year YYYY | --months YYYY] [--type TYPE] [--status STATUS] \
                [--path WP_PATH] [--ssh HOST] [--site DIR]
```

#### Example Output

```
=== Monthly post count (publish) for 2026 ===
Site: /srv/www/example.com/current (web@example.com)

month	posts
2026-01	2
2026-02	13
2026-03	3
2026-04	12
2026-05	16
2026-06	12
2026-07	4

Done.
```

#### Requirements

- WP-CLI available where the query runs (Trellis VM, production, or reachable via `--ssh`)
- SSH access to the server when using `--ssh` (e.g. `web@example.com`)

---

## GitHub Integration

### create-pr.sh (635 lines)

Intelligent GitHub pull request creation with AI-powered descriptions using Claude CLI, Codex, or Mistral Vibe. Full docs — features, usage, flags, token-cost comparison, troubleshooting — live in [CREATE-PR.md](../CREATE-PR.md) at the repo root; this file doesn't duplicate them.

---

### upload-release-asset.sh (117 lines)

Manual GitHub Release asset uploader for WordPress plugins and themes. Useful when a GitHub Actions release workflow fails to trigger (e.g., after a repository rename), allowing you to attach a production zip to an existing release without re-running CI.

#### Features

- **Release Verification**: Confirms the target release exists on GitHub before doing any work
- **JS Build Step**: Runs `npm ci && npx webpack` if `package.json` is present in the working directory
- **Distignore Support**: Respects `.distignore` to exclude dev files from the zip; warns and zips everything (except `.git`) when absent
- **Duplicate Detection**: Checks if the asset name already exists on the release and prompts before overwriting
- **Upload Verification**: Confirms the uploaded asset is visible on the release and prints its size
- **Automatic Cleanup**: Removes the local zip file after a successful upload

#### Usage

```bash
# Run from the plugin/theme root directory
./scripts/release/upload-release-asset.sh <github-repo> <tag> [zip-name]

# Upload with auto-named zip (uses repo slug)
./scripts/release/upload-release-asset.sh imagewize/warder-cookie-consent v1.3.1

# Upload with custom zip name
./scripts/release/upload-release-asset.sh imagewize/my-plugin v2.0.0 my-plugin.zip
```

#### Example Output

```
=== GitHub Release Asset Upload ===
Repo:  imagewize/warder-cookie-consent
Tag:   v1.3.1
Zip:   warder-cookie-consent.zip

Step 1: Verifying release v1.3.1 exists...
  ✓ Found release: draft=false prerelease=false
Step 2: No package.json found, skipping JS build
Step 3: Creating warder-cookie-consent.zip...
  ✓ Zipped (excluding .distignore entries)
  ✓ warder-cookie-consent.zip created (142K)
Step 4: Checking for existing assets...
Step 5: Uploading to release v1.3.1...
  ✓ Uploaded

=== Done ===
Asset attached: warder-cookie-consent.zip (141KB)
Release URL: https://github.com/imagewize/warder-cookie-consent/releases/tag/v1.3.1
```

#### Requirements

- `gh` (GitHub CLI) — authenticated with `gh auth login`
- `zip` — standard on Linux; `brew install zip` on macOS if missing
- `npm` — only required when a `package.json` is present in the working directory

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
./scripts/release/release-plugin.sh 2.5.3

# Generate changelog and auto-commit
./scripts/release/release-plugin.sh 2.5.3 --commit

# Specify AI tool
./scripts/release/release-plugin.sh 2.5.3 --ai=codex
./scripts/release/release-plugin.sh 2.5.3 --commit --ai=claude

# Interactive AI tool selection (if both installed)
./scripts/release/release-plugin.sh 2.5.3
# Prompts: "Choose AI tool [default: claude]:"
```

#### Example Workflow

1. Create feature branch and make changes
2. Run release script:
   ```bash
   ./scripts/release/release-plugin.sh 2.5.3
   ```
3. Script analyzes `git diff main..HEAD`
4. AI generates professional changelog
5. Updates version in all three files
6. Shows preview of changes
7. Optionally commits changes
8. Push and create PR:
   ```bash
   git push origin feature-branch
   ./scripts/git/create-pr.sh main "Elayne Blocks Version 2.5.3"
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
./scripts/release/release-plugin.sh 2.5.3 --ai=claude
./scripts/release/release-plugin.sh 2.5.3 --ai=codex
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

### deploy-plugin-wporg.sh

Publishes a plugin from its Git working tree to the **WordPress.org plugin directory (SVN)** — syncs `trunk/`, creates `tags/<version>/`, and uploads the marketing `assets/` (banners, icon, screenshots). Generic: works for any plugin, for both the first publish and later updates. Complements `release-plugin.sh` (version bump) and `upload-release-asset.sh` (GitHub) by handling the WordPress.org side.

#### Features

- **Same filter as the release zip**: respects `.distignore`, so `trunk`/`tags` contain exactly what ships (falls back to "everything except `.git/`" if absent)
- **Marketing assets convention**: uploads `.wordpress-org/` (banners, icon, screenshots) to SVN `/assets`, kept out of the plugin download
- **Auto-detection**: finds the main plugin file (`Plugin Name:` header) and reads the version from its `Version:` header (or pass it explicitly)
- **Safe by default**: stages everything and prints the exact `svn ci` command for review; only commits with `--commit`
- **Idempotent**: re-running with no source changes produces an empty `svn status` (rsync + `svn add`/`svn rm` reconciliation handles adds, edits, and deletions)
- **Tag guard**: refuses to overwrite an already-published `tags/<version>` unless `--force`
- **Optional build**: `--build "npm ci && npx webpack"` runs before packaging

#### Usage

```bash
# Prepare a release (stage + review), then commit manually
cd ~/code/warder-cookie-consent
~/code/wp-ops/scripts/release/deploy-plugin-wporg.sh warder-cookie-consent --build "npm ci && npx webpack"

# One shot: build, stage, and commit (prompts for SVN password)
~/code/wp-ops/scripts/release/deploy-plugin-wporg.sh warder-cookie-consent 2.1.4 \
  --build "npm ci && npx webpack" --username Rhand --commit

# Explicit paths / custom checkout location
~/code/wp-ops/scripts/release/deploy-plugin-wporg.sh my-plugin 1.0.0 \
  --plugin-dir ~/code/my-plugin --assets-dir ~/code/my-plugin/.wordpress-org \
  --svn-dir /tmp/my-plugin-svn --commit
```

#### Example Output

```
=== WordPress.org SVN Deploy: warder-cookie-consent ===

  ✓ Main plugin file: warder-cookie-consent.php
  ✓ Version: 2.1.4
Checking remote for existing tag 2.1.4 ...
  ✓ tags/2.1.4 is free
Checking out https://plugins.svn.wordpress.org/warder-cookie-consent ...
  ✓ Working copy: /Users/me/code/warder-cookie-consent-svn
Assembling filtered payload ...
  ✓ Filtered via .distignore
Syncing trunk/ ...
  ✓ trunk/ synced
Building tags/2.1.4/ ...
  ✓ tags/2.1.4/ staged
Syncing assets/ from .wordpress-org/ ...
  ✓ assets/ synced (10 files)

=== svn status (what will be committed) ===
  A   trunk/readme.txt
  ...

=== Staged and ready. Review above, then commit: ===
  svn ci "/Users/me/code/warder-cookie-consent-svn" -m "Release 2.1.4" --username Rhand
```

#### Manual SVN equivalent (without the script)

The same publish done by hand — useful for understanding or one-off fixes:

```bash
# 1. Check out the plugin's SVN repo (on a first publish, trunk/tags/assets are empty)
svn co https://plugins.svn.wordpress.org/<slug> <slug>-svn
cd <slug>-svn

# 2. Sync the plugin into trunk/ (source = your .distignore-filtered build, e.g. the release zip contents)
rsync -a --delete --exclude='.svn' /path/to/plugin-payload/ trunk/

# 3. Freeze a version tag (copy of trunk)
rsync -a --delete --exclude='.svn' trunk/ tags/<version>/      # or: svn cp trunk tags/<version>

# 4. Upload marketing assets (banners, icon, screenshots) to the top-level /assets — NOT trunk
rsync -a --delete --exclude='.svn' /path/to/.wordpress-org/ assets/

# 5. Schedule adds, remove anything deleted, review, then commit
svn add --force trunk tags assets
svn status | awk '/^!/{print $2}' | xargs -r svn rm      # remove files dropped from the plugin
svn status                                               # review what will be committed
svn ci -m "Release <version>" --username Rhand           # prompts for SVN password
```

Key points: WordPress.org SVN is a **release system, not Git** — only push finished versions. `trunk/` is the current version, `tags/<version>/` are immutable releases users download, and `/assets` (banners/icon/screenshots) is a separate top-level dir that never ships in the plugin download.

#### Notes

- **SVN usernames are case-sensitive** (e.g. `Rhand`, not `rhand`). Find yours at profiles.wordpress.org → Account & Security, where you can also generate a dedicated SVN password (recommended over your account login password).
- The SVN checkout is kept (default `<plugin-dir>/../<slug>-svn`) and reused/updated on the next run; delete it anytime.
- Pairs with the `.wordpress-org/` + `.distignore` setup in the plugin repo: the same assets are version-controlled in Git and pushed to SVN here.

#### Requirements

- `svn`, `zip`, `rsync` (standard on macOS/Linux; `brew install subversion` if `svn` is missing)
- Active WordPress.org plugin SVN commit access

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
./scripts/release/release-theme.sh theme-name 1.2.5

# Release with automatic commit
./scripts/release/release-theme.sh theme-name 1.0.0 --commit

# Specify AI tool
./scripts/release/release-theme.sh theme-name 1.2.5 --ai=codex
./scripts/release/release-theme.sh theme-name 1.0.0 --commit --ai=claude

# Examples
./scripts/release/release-theme.sh elayne 1.2.5
./scripts/release/release-theme.sh nynaeve 2.0.0 --commit
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
