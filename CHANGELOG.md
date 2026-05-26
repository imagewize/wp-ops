# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.9.0] - 2026-05-26

### Added

- **Upload Release Asset Script** - New [`scripts/upload-release-asset.sh`](scripts/upload-release-asset.sh) for manually attaching a zipped plugin or theme to a GitHub Release when the Actions release event fails to fire (e.g. after a repository rename):
  - Verifies the target release exists before doing any work
  - Runs `npm ci && npx webpack` automatically if `package.json` is present
  - Zips the project respecting `.distignore` exclusions (falls back to excluding only `.git` if no `.distignore`)
  - Detects and prompts before overwriting an existing asset on the release
  - Uploads via `gh release upload` and prints the attached asset size and release URL
  - Cleans up the local zip on completion

## [2.8.1] - 2026-05-24

### Changed

- **Traffic Monitor Admin Path Filtering** - Updated [`scripts/monitoring/traffic-monitor.sh`](scripts/monitoring/traffic-monitor.sh) to exclude WordPress admin and API paths from page view analysis:
  - Added `ADMIN_PATTERN` variable filtering `/wp/wp-login.php`, `/wp/wp-admin/`, `/wp-json/`, `/xmlrpc.php`, and `/wp-cron.php`
  - Prevents admin/API traffic from skewing content page view statistics

## [2.8.0] - 2026-05-22

### Added

- **404 Checker Script** - New [`scripts/monitoring/404-checker.sh`](scripts/monitoring/404-checker.sh) for scanning internal links for broken responses:
  - **Global mode** (default) — fetches homepage, extracts and checks all internal links (~30s)
  - **Spider mode** — recursive `wget` spider to configurable depth (default: 3, ~5-10 min)
  - Filters out assets (CSS, JS, images, fonts), feeds, sitemaps, and WordPress admin/API paths to avoid noise
  - Color-coded output (green OK, yellow warnings, red errors, cyan progress)
  - `--output FILE` flag to append broken-link results to a file alongside stdout
  - `--timeout N` flag to control per-request curl max-time (default: 10s)
  - `--level N` flag to control spider recursion depth
  - Exit codes: `0` (no broken links), `1` (broken links found), `2` (usage error / missing dependency)
  - Cross-platform: uses `bash` parameter expansion instead of GNU-specific `sed` flags for macOS/BSD compatibility

## [2.7.3] - 2026-05-12

### Added

- **WP Template DB Override WP-CLI Snippet** - New [`wordpress-utilities/snippets/wp-template-db-override-wpcli.md`](wordpress-utilities/snippets/wp-template-db-override-wpcli.md) for managing block theme template overrides:
  - Detect DB-stored templates (`wp_template` post type) that override theme files
  - Option A: Delete DB override to restore file-system template control
  - Option B: Surgically update specific block markup in the DB copy via `wp eval` + `str_replace`
  - Trellis VM variants for all commands
  - Prevention guidance with `WP_DEVELOPMENT_MODE=theme`

## [2.7.2] - 2026-05-12

### Documentation

- **CLAUDE.md create-pr.sh usage** - Corrected GitHub PR Creation examples to show `--no-interactive` flag:
  - Passing positional args alone does not suppress the AI prompt; `--no-interactive` is required for scripted use
  - Added explicit examples for non-interactive AI, no-AI, and update-mode invocations

- **.vibe/prompts/wp-ops.md create-pr.sh usage** - Updated Git Workflow step 5 to reflect the same fix:
  - Clarified interactive vs. fully non-interactive invocation
  - Added note that positional args without `--no-interactive` still trigger prompts

## [2.7.1] - 2026-05-12

### Documentation

- **CLAUDE.md Structure Update** - Synced repository structure section to match current repo:
  - Added `trellis/security/` (fail2ban and manual IP blocking guides)
  - Added `wordpress-utilities/snippets/` (PHP snippets and WP-CLI references)
  - Added `scripts/woocommerce/`, `batch-resize.sh`, `convert-to-webp.sh`, `find-and-replace-files.sh`, `git-log-oneline.sh`, and `release-plugin.sh` to scripts listing

- **.vibe/prompts/wp-ops.md Structure Update** - Synced project structure to match current repo:
  - Added `trellis/security/` and `wp-cli/security/` subdirectories
  - Added `wordpress-utilities/` section (`age-verification/`, `analytics/`, `snippets/`, `speed-optimization/`)
  - Added `scripts/woocommerce/`, `batch-resize.sh`, `find-and-replace-files.sh`, and `release-plugin.sh` to scripts listing

## [2.7.0] - 2026-05-12

### Added

- **Batch Resize Script** - New [`scripts/batch-resize.sh`](scripts/batch-resize.sh) for processing one or more images:
  - Batch resize with center-crop (maintains aspect ratio, then crops to exact dimensions)
  - Perfect for creating WordPress featured images from screenshots
  - Custom output naming with automatic numbering (`-o`/`--output` prefix)
  - Configurable dimensions (`-w`/`--width`, `-H`/`--height`), format (`-f`/`--format`: jpg, png, webp), and quality (`-q`/`--quality`)
  - **Dry-run mode** (`-d`/`--dry-run`) to preview changes safely
  - **Delete originals** (`--delete`) option for cleanup after conversion
  - WebP output via `cwebp` pipe (consistent with `convert-to-webp.sh`; validated upfront before processing)

- **WooCommerce Variation Creation Script** - New [`scripts/woocommerce/create-product-variations.sh`](scripts/woocommerce/create-product-variations.sh) for bulk-creating product variations via WP-CLI:
  - Creates all combinations of attribute values for a variable product
  - Configurable via environment variables (product ID, price, attributes, etc.)
  - Trellis VM compatible with `--workdir` and `--url` support
  - Success/failure tracking with detailed output
  - See companion snippet [`wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md`](wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md) for attribute setup

### Documentation

- **scripts/README.md** - Updated directory structure and script count (16 → 18)
  - Added `batch-resize.sh` to root-level scripts list
  - Added WooCommerce subdirectory with `create-product-variations.sh` to directory structure
  - Added comprehensive documentation section for batch-resize.sh with usage examples

- **wordpress-utilities/snippets/README.md** - Added WooCommerce product attributes WP-CLI snippet:
  - New entry for [`woocommerce-product-attributes-wpcli.md`](wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md)
  - Comprehensive guide for creating and managing WooCommerce attributes and terms via WP-CLI

## [2.6.0] - 2026-05-05

### Added

- **Admin User Creation Snippets** - New snippets in [`wordpress-utilities/snippets/`](wordpress-utilities/snippets/):
  - [`admin-user-creation.php`](wordpress-utilities/snippets/admin-user-creation.php) - Temporary admin user creation for functions.php with placeholder values and safety checks
  - [`admin-user-creation-wpcli.md`](wordpress-utilities/snippets/admin-user-creation-wpcli.md) - Comprehensive WP-CLI guide with secure password generation, emergency recovery, batch creation, and cleanup commands

## [2.5.15] - 2026-05-01

### Added

- **Find and Replace Files Script** - New [`scripts/find-and-replace-files.sh`](scripts/find-and-replace-files.sh) utility for batch operations across projects:
  - Finds all instances of a file by name recursively through directory trees
  - Replaces multiple copies with an updated version in one operation
  - **Dry-run mode** (`-n`/`--dry-run`) to preview changes before applying
  - **List-only mode** (`-l`/`--list`) to just locate files
  - **Size display** (`-s`/`--size`) to show file sizes and line counts
  - Configurable search directory (`-d`/`--directory`) and max depth (`-m`/`--maxdepth`)
  - Preserves file permissions (executable flags)
  - Safe handling of filenames with spaces (null-terminated output)

### Documentation

- **README for Find and Replace Script** - New [scripts/README-FIND-AND-REPLACE.md](scripts/README-FIND-AND-REPLACE.md) with:
  - Comprehensive usage examples and options reference
  - Use cases for batch script updates and file synchronization
  - Best practices for dry-run workflow
- **scripts/README.md** - Updated directory structure and script count (15 → 16)
  - Added `find-and-replace-files.sh` to root-level scripts list

## [2.5.14] - 2026-05-01

### Added

- **One-Step Resize and Convert to WebP Documentation** - Enhanced [nginx/image-optimization/RESIZE-AND-CONVERSION.md](nginx/image-optimization/RESIZE-AND-CONVERSION.md) with a new dedicated section:
  - One-step pipe-based workflow combining ImageMagick resize with `cwebp` conversion
  - Reference to existing [`scripts/convert-to-webp.sh`](scripts/convert-to-webp.sh) as the recommended reusable tool
  - Usage examples for different dimensions and quality settings
  - Links to full script documentation in scripts/README.md

### Changed

- **Create PR Script Help Documentation** - Updated [`scripts/create-pr.sh`](scripts/create-pr.sh) with `--help`/`--h` flag support:
  - Added help function with clean usage, options, arguments, and examples display
  - Updated header comments to reflect new options
- **CREATE-PR.md Documentation** - Enhanced [CREATE-PR.md](CREATE-PR.md) with comprehensive updates:
  - Added `--help` flag documentation and examples
  - Added Vibe CLI support throughout (AI backend, installation, environment variables)
  - Updated AI backend options to include vibe alongside claude and codex
  - Added note about help message availability
- **.vibe/prompts/wp-ops.md Workflow** - Updated [.vibe/prompts/wp-ops.md](.vibe/prompts/wp-ops.md) with detailed standard workflow:
  - Step-by-step branch creation, atomic commits, CHANGELOG updates, push, and PR creation
  - Added create-pr.sh usage examples
  - Enhanced Git Workflow section with clear process

## [2.5.13] - 2025-05-06

### Added

- **Git Log Oneline Script** - New [scripts/git-log-oneline.sh](scripts/git-log-oneline.sh) utility for showing recent git commits as compact one-liners:
  - Displays short commit hash and message on a single line per commit
  - Accepts optional argument for number of commits to show (default: 10)
  - Includes input validation and error handling
  - Useful for quickly reviewing recent work before creating PRs or checking recent changes

## [2.5.12] - 2026-04-30

### Changed

- **convert-to-webp.sh IM7 Compatibility** - Updated [scripts/convert-to-webp.sh](scripts/convert-to-webp.sh) to use `magick` (ImageMagick 7+) with automatic fallback to `convert` (ImageMagick 6) for backwards compatibility, fixing deprecation warning in newer ImageMagick versions

## [2.5.11] - 2026-04-30

### Added

- **WebP Featured Image Conversion Script** - New [scripts/convert-to-webp.sh](scripts/convert-to-webp.sh) for converting JPG images to WebP format optimized for WordPress featured images and Facebook Open Graph sharing:
  - Defaults to 800×419 px (1.91:1 ratio — Facebook OG minimum-compliant, above 600×315 floor)
  - Uses ImageMagick center-crop (`-resize WxH^` + `-gravity center -extent`) to avoid distortion on non-1.91:1 sources
  - Pipes cropped output directly to `cwebp -q 82` for efficient single-step conversion
  - Accepts optional arguments: output filename, quality (default 82), width (default 800), height (default 419)

- **WebP Featured Image Snippet** - New [wordpress-utilities/snippets/webp-featured-image.md](wordpress-utilities/snippets/webp-featured-image.md) with command reference for WebP conversion:
  - Single image and batch conversion examples using ImageMagick + cwebp pipeline
  - Quality settings guidance and Nginx integration notes
  - Batch convert with existing WebP check (skip already-converted files)
  - Complete workflow example for uploads directories

- **Mistral Vibe CLI Project Configuration** - New [.vibe/](:.vibe/) directory with project-specific Vibe CLI setup:
  - `config.toml` — model settings (mistral-medium-3.5), tool permissions, session logging config
  - `prompts/wp-ops.md` — project system prompt covering repo structure, coding style, safety rules, and git workflow

### Changed

- **scripts/README.md** - Added Image Utilities as a fifth functional area:
  - Updated script count from 13 to 14
  - Added `convert-to-webp.sh` to directory structure
  - Added quick start example for image conversion
  - Added dedicated Image Utilities section with usage, requirements, and cross-reference to the snippet

- **wordpress-utilities/snippets/README.md** - Added entry for `webp-featured-image.md` with feature summary and setup steps

## [2.5.10] - 2026-04-23

### Changed

- **redirect-check.sh Moved to Monitoring** - Relocated [scripts/monitoring/redirect-check.sh](scripts/monitoring/redirect-check.sh) from `wordpress-utilities/snippets/` to `scripts/monitoring/` where it better fits alongside other diagnostic shell scripts:
  - Replaced hardcoded `imagewize.com` example URLs with `example.com` placeholders
  - Updated [wordpress-utilities/snippets/README.md](wordpress-utilities/snippets/README.md) to remove the entry
  - Updated [scripts/README.md](scripts/README.md) with the script in the directory tree, Quick Start section, and a full Monitoring Scripts entry

## [2.5.9] - 2026-04-22

### Added

- **Google Organic Referrals Quick Reference** - New [scripts/monitoring/GOOGLE-ORGANIC-REFERRALS.md](scripts/monitoring/GOOGLE-ORGANIC-REFERRALS.md) with Nginx access log commands for extracting organic traffic data:
  - Full organic landing page breakdown with hit counts sorted by most visited
  - Bot and crawler noise filtering (Googlebot, AhrefsBot, SemrushBot, etc.)
  - Distinct organic landing page count over a 24h window
  - Per-slug organic traffic check
  - Category-scoped hit lookup excluding bots

- **Post Expiry Noindex WP-CLI Checks** - New [wordpress-utilities/snippets/post-expiry-noindex-wpcli-checks.md](wordpress-utilities/snippets/post-expiry-noindex-wpcli-checks.md) with diagnostic commands for verifying the post expiry noindex feature:
  - Check `_post_expiry_date` meta is saved correctly
  - Verify post category membership against configured expiry categories
  - Timezone-aware expiry logic test via `wp eval` that bypasses `is_singular()` (always false in WP-CLI context)
  - Notes on Yoast SEO admin UI limitations and staging noindex behaviour

### Changed

- **RESIZE-AND-CONVERSION.md WordPress Featured Image Workflow** - Added new [WordPress Featured Image from macOS Screenshot](nginx/image-optimization/RESIZE-AND-CONVERSION.md) section:
  - Uses built-in `sips` to scale Retina screenshots (2× resolution) to 1200px wide before converting
  - `cwebp` conversion at quality 85 — ~95% size reduction vs unscaled PNG
  - One-liner workflow with input/output path variables
  - Naming convention guidance (`{post-slug}-{descriptor}.webp`)
  - Comparison of `sips` vs ImageMagick for single-file proportional resizes

## [2.5.8] - 2026-04-06

### Changed

- **README restructured** - Reorganized [README.md](README.md) for clarity and conciseness:
  - Grouped tools into sections (Trellis, WP-CLI, Nginx, Scripts, WordPress Utilities) with a TOC
  - Shortened descriptions and removed redundant label text in the Docs column
  - Removed empty Quick Start section
  - Moved Troubleshooting under Trellis
  - Added missing Snippets entry to the tools table

## [2.5.7] - 2026-04-06

### Added

- **WordPress Snippets Directory** - New [wordpress-utilities/snippets/](wordpress-utilities/snippets/) directory for small, self-contained PHP snippets:
  - `post-expiry-noindex.php` — Auto-noindex posts past their expiry date via Yoast SEO's `wpseo_robots` filter, evaluated in the site's configured WordPress timezone (not UTC); adds a "Noindex After Date" meta box to the post sidebar; scoped to configurable category IDs; outputs `noindex, follow`
  - `README.md` — Snippet index with usage notes, dependencies (Yoast SEO, WP 5.3+), and setup instructions
- Updated [wordpress-utilities/README.md](wordpress-utilities/README.md) to document the new Snippets section

## [2.5.6] - 2026-03-28

### Added

- **AI Bot Monitor** - New [scripts/monitoring/ai-bot-monitor.sh](scripts/monitoring/ai-bot-monitor.sh) script for analyzing AI crawler traffic from Nginx logs:
  - Detects 20+ AI crawlers (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, CCBot, Bytespider, etc.)
  - Reports requests and bandwidth per crawler, top scraped pages (overall + per bot), traffic by hour, HTTP status codes, robots.txt compliance, and IP breakdown
  - Optional operator IP cross-check to distinguish tool sessions from autonomous crawlers
  - Accepts optional `output_file` argument to save report to disk
  - Uses gawk-based timestamp filtering for accurate time windows

- **Run Monitoring Orchestrator** - New [scripts/monitoring/run-monitoring.sh](scripts/monitoring/run-monitoring.sh) script that runs all three monitors in sequence:
  - Runs `traffic-monitor.sh`, `security-monitor.sh`, and `ai-bot-monitor.sh` with timestamped output files
  - Generates a consolidated `monitoring-summary-YYYY-MM-DD.md` markdown report with key metrics
  - Auto-detects production vs. local context for output directory selection
  - Designed for remote execution: `ssh web@example.com 'bash -s' < run-monitoring.sh`

### Changed

- **traffic-monitor.sh Accurate Time Filtering** - Updated [scripts/monitoring/traffic-monitor.sh](scripts/monitoring/traffic-monitor.sh) to use gawk-based timestamp parsing instead of tail-line estimation:
  - Replaced `tail -n estimated_lines` with exact epoch-based filtering via `gawk`; falls back to tail estimate if gawk is unavailable
  - Added optional `output_file` third argument — pipes output to both stdout and file via `tee`
  - Increased top pages from 10 to 50 results
  - Improved "Analyzing..." label to show exact cutoff timestamp

- **security-monitor.sh Accurate Time Filtering** - Updated [scripts/monitoring/security-monitor.sh](scripts/monitoring/security-monitor.sh) with the same gawk-based timestamp filtering:
  - Replaced tail estimation with exact epoch-based filtering; gawk fallback preserved
  - Added optional `output_file` fourth argument for saving reports to disk
  - Added cutoff timestamp label to analysis header

## [2.5.5] - 2026-03-25

### Added

- **Trellis Updater php-fpm-pool Template Preservation** - Extended [trellis/updater/trellis-updater.sh](trellis/updater/trellis-updater.sh) to preserve custom PHP-FPM pool template:
  - Added `--exclude="roles/wordpress-setup/templates/php-fpm-pool-wordpress.conf.j2"` to rsync exclusion list
  - Added comment noting this preserves custom `request_terminate_timeout` settings

### Changed

- **create-pr.sh Update Mode Prompts** - Fixed [scripts/create-pr.sh](scripts/create-pr.sh) interactive mode to skip base branch and PR title prompts when running with `--update` flag
- **create-pr.sh Vibe stdin Fix** - Fixed Vibe CLI invocation to use `< /dev/null` to prevent stdin blocking in non-interactive contexts

### Documentation

- **CLAUDE.md Git Conventions** - Updated Git Commit and PR Conventions section:
  - Added atomic commits policy (one logical change per commit)
  - Replaced co-authorship attribution note with a no-Claude-mentions policy

## [2.5.4] - 2026-02-18

### Added

- **Trellis Updater security.yml Preservation** - Extended `trellis/updater/trellis-updater.sh` and `trellis/updater/manual-update.md` to preserve `group_vars/all/security.yml` during Trellis updates:
  - Added `--exclude="group_vars/all/security.yml"` to rsync exclusion list in both the automated script and manual update guide
  - Added post-update verification check in `trellis-updater.sh` that warns when the `wordpress_wp_login` fail2ban jail is missing or disabled
  - Documented `security.yml` in the manual update notes with a warning about fail2ban jail configuration (bantime, maxretry, IP whitelist)

## [2.5.3] - 2026-02-10

### Added

- ** Multi Site site addition issues and solutions** 
  - Added Multi site site addition trouble shooting section including commands to deal with issues when ID, slug and or name don't match post addition new site

## [2.5.2] - 2026-02-10

### Added

- **Mistral Vibe AI Support for PR Creation** - Enhanced [scripts/create-pr.sh](scripts/create-pr.sh) with Mistral Vibe CLI integration:
  - Added `--ai=vibe` flag for explicit Mistral Vibe selection alongside Claude and Codex
  - Automatic detection of Vibe CLI with multi-tool selection prompt
  - Environment variable support for custom Vibe command (`VIBE_COMMAND`) and arguments (`VIBE_CLI_ARGS`)
  - Vibe-specific command execution with `-p` flag and `--output text` parameter
  - Interactive AI tool selection now includes Vibe when multiple CLIs are available
  - Updated [scripts/README.md](scripts/README.md) with Vibe installation instructions and usage examples

### Changed

- **PR Creation Script AI Backend** - Updated [scripts/create-pr.sh](scripts/create-pr.sh) option parsing and execution logic:
  - Extended AI tool validation to accept "claude", "codex", or "vibe"
  - Enhanced non-interactive mode to support Vibe as fallback option
  - Updated error messages to include Vibe in supported AI tools list
  - Modified AI tool detection to check for all three CLI tools (Claude, Codex, Vibe)

## [2.5.1] - 2026-02-10

### Changed

- **Trellis Updater File Preservation** - Extended [trellis/updater/trellis-updater.sh](trellis/updater/trellis-updater.sh) to preserve additional custom files:
  - **Custom Ansible playbooks** - Database and files management playbooks (`database-backup.yml`, `database-pull.yml`, `database-push.yml`, `files-backup.yml`, `files-pull.yml`, `files-push.yml`, `uploads.yml`)
  - **Custom Nginx configurations** - Project-specific Nginx includes (`nginx-includes/` directory)
  - **Custom documentation** - Project docs and changelogs (`docs/`, `CHANGELOG.md`, `CHANGELOG-TRELLIS-DATABASE-UPLOADS-MIGRATION.md`)
  - Updated [trellis/updater/README.md](trellis/updater/README.md) to document newly preserved file categories

### Improved

- Trellis updater script now preserves a more comprehensive set of custom configurations during version updates
- Better documentation of which files and directories are excluded from rsync during Trellis updates

## [2.5.0] - 2026-01-30

### Added

- **SEO-Focused Traffic Analysis Enhancements** - Major upgrade to [scripts/monitoring/traffic-monitor.sh](scripts/monitoring/traffic-monitor.sh) with comprehensive SEO analytics:
  - **404 Error Analysis** - Identifies broken links and missing content from real users (excluding bots) with actionable redirect recommendations
  - **Search Engine Crawler Activity** - Tracks Googlebot, Bingbot, DuckDuckBot, Baiduspider, Yandex, and Slurp activity with most-crawled pages analysis
  - **Mobile vs Desktop Traffic** - Device type breakdown with mobile-first indexing recommendations based on traffic percentages
  - **Organic Search Traffic Sources** - Identifies which search engines are sending traffic with robust filtering to exclude spoofed referrers
  - **Top Landing Pages (External Traffic)** - Shows which content pages attract external visitors, excluding admin pages and malware scans
  - **Social Media Traffic** - Tracks referrals from Facebook, Twitter, LinkedIn, Instagram, Pinterest, Reddit, YouTube, and t.co
  - **Redirect Analysis (301/302)** - Lists all redirects with color-coded SEO impact indicators (301 = permanent, 302 = temporary)
  - **URL Depth Analysis** - Analyzes site structure with recommendations to keep content within 3 clicks for better crawling
  - New configuration variable `SEO_BOTS` for targeting legitimate search engine crawlers

### Improved

- **Advanced Referrer Filtering** - Enhanced fake referrer detection to block sophisticated attack patterns:
  - Filters spoofed search engine referrers (e.g., `imagewize.com//yahoo.php` masquerading as Yahoo traffic)
  - Blocks attack patterns: `.php` files, `/config/`, `//`, `/./`, `.env`, `.git`, `.yml`, `.dockerenv`
  - Excludes WordPress admin/malware scans: `wp-login`, `wp-admin`, `xmlrpc.php`, `/db.php`, `seotheme`, `timthumb`
  - Removes Magento config scans (`/app/etc/`), random PHP shells (8-character filenames), and AWS config scans (`.ebextensions`)
  - Prevents same-domain referrers from appearing in external referrer lists
  - Social media filters now require actual platform domains (facebook.com, twitter.com, etc.)

- **Separation of Concerns** - Clear division between traffic analysis (traffic-monitor.sh) and security monitoring (security-monitor.sh):
  - Traffic monitor focuses on SEO insights, content performance, and user behavior
  - Security monitor handles threat detection, brute force attempts, and malicious activity
  - No duplication of security-focused analysis between scripts

### Changed

- **Enhanced External Referrers Section** - Now uses site domain extraction from log file path for accurate same-domain filtering
- **Improved Landing Pages Analysis** - Multi-layer filtering pipeline to show only legitimate content pages
- **Better Organic Search Detection** - Domain-specific matching (google.com, bing.com) instead of keyword matching to prevent spoofing
- Updated report structure with dedicated "SEO & Content Analysis" section following standard traffic metrics

## [2.4.2] - 2026-01-21

### Fixed

- **Plugin Release Script Version Update** - Replaced fragile `sed` pattern matching with robust `awk`-based version updates in [scripts/release-plugin.sh](scripts/release-plugin.sh):
  - Replaced two `sed` commands with single `awk` script for plugin file version updates
  - More reliable pattern matching for plugin header "Version:" field
  - More reliable pattern matching for `define( 'ELAYNE_BLOCKS_VERSION', ... )` constant
  - Eliminates dependency on POSIX character classes in sed (which vary by platform)
  - Single temp file operation instead of multiple in-place edits
  - More portable solution that works consistently across macOS, Linux, and BSD systems

## [2.4.1] - 2026-01-21

### Fixed

- **Plugin Release Script sed Pattern** - Fixed version update regex in [scripts/release-plugin.sh](scripts/release-plugin.sh) to correctly handle whitespace in plugin header:
  - Replaced `\s*` with `[[:space:]]*` for POSIX-compliant whitespace matching in sed
  - Ensures proper version number updates in plugin file headers
  - Resolves issues where version updates might fail due to whitespace variations

## [2.4.0] - 2026-01-20

### Added

- **WordPress Plugin Release Automation** - New AI-powered plugin release script with comprehensive changelog generation:
  - **[scripts/release-plugin.sh](scripts/release-plugin.sh)** - Automated version bumping and changelog generation for WordPress plugins (422 lines)
  - Multi-AI backend support (Claude CLI or Codex) with automatic detection and interactive selection
  - Semantic versioning validation (X.Y.Z format)
  - Updates three files automatically: main plugin file (version header and constant), readme.txt (stable tag and changelog), CHANGELOG.md (detailed version history)
  - AI-powered changelog generation in two formats:
    - **CHANGELOG.md**: Detailed Keep a Changelog format with sections (Changed, Added, Fixed, Technical)
    - **readme.txt**: Concise WordPress.org style with single-line entries
  - Git diff analysis between current branch and main branch
  - Interactive confirmation prompts with change preview
  - Optional `--commit` flag for automatic commits with standardized messages
  - `--ai=claude|codex` flag for explicit AI tool selection
  - Environment variable support for custom CLI commands and arguments (`CLAUDE_COMMAND`, `CODEX_COMMAND`, `CLAUDE_CLI_ARGS`, `CODEX_CLI_ARGS`)
  - Safety features: git diff preview, backup files (.bak), color-coded output, no-changes detection
  - Token usage: 500-1,500 tokens per release (~$0.01-0.05 cost)

### Changed

- Enhanced [scripts/README.md](scripts/README.md) with WordPress Plugin Release documentation:
  - Updated directory structure to include release-plugin.sh
  - Changed "Theme Management" to "WordPress Management" to reflect broader scope
  - Added comprehensive release-plugin.sh section (after create-pr.sh, before release-theme.sh)
  - Documented features, usage examples, workflow, changelog formats, AI tool selection, and requirements
  - Updated script count from 9 to 10 utility scripts
  - Reorganized functional areas to include "WordPress Management" category

- Updated main [README.md](README.md) tools table:
  - Added Plugin Release Script entry between PR Creation and Theme Release
  - Consistent tool ordering: PR Creation → Plugin Release → Theme Release → Theme Sync

### Improved

- Complete parity between plugin and theme release automation workflows
- Unified AI-powered changelog generation for both WordPress plugins and themes
- Consistent documentation structure across all release automation scripts
- Better developer experience with interactive AI tool selection when multiple CLIs available

## [2.3.6] - 2026-01-15

### Fixed

- **PR Update Handling** - Improved [scripts/create-pr.sh](scripts/create-pr.sh) to detect `gh pr view` failures before checking PR number, preventing false "no PR found" states when the GitHub CLI call fails

## [2.3.5] - 2026-01-10

### Added

- **Theme Release Script Multi-AI Support** - Enhanced [scripts/release-theme.sh](scripts/release-theme.sh) with flexible AI backend selection:
  - Added `--ai=claude|codex` flag for explicit AI tool selection
  - Interactive AI tool selection when both Claude and Codex CLIs are available
  - Environment variable support for custom CLI command names (`CLAUDE_COMMAND`, `CODEX_COMMAND`)
  - Support for custom AI CLI arguments via `CLAUDE_CLI_ARGS` and `CODEX_CLI_ARGS` environment variables
  - Improved error handling with detailed AI CLI failure messages

### Changed

- **Enhanced Theme Release Documentation** - Updated [scripts/README.md](scripts/README.md) with multi-AI backend documentation:
  - Updated release-theme.sh description to mention both Claude CLI and Codex support
  - Added `--ai` flag examples in Usage section
  - Enhanced Requirements section with both Claude and Codex installation instructions
  - Clarified AI-Generated Changelogs feature supports multiple AI backends

### Improved

- Refactored release-theme.sh option parsing to use `case` statement for better maintainability
- Enhanced AI CLI detection to check for both Claude and Codex availability
- More flexible AI tool configuration with environment variable overrides
- Better user experience with automatic AI tool selection based on availability

## [2.3.4] - 2026-01-09

### Changed

- **Standardized admin username placeholder across documentation** - Replaced hardcoded usernames with `admin_user` placeholder for better clarity and universality:
  - **[trellis/README.md](trellis/README.md)** - Updated fail2ban examples to use `admin_user` placeholder with note explaining to replace with configured username
  - **[trellis/provision/PROJECT-SETUP.md](trellis/provision/PROJECT-SETUP.md)** - Replaced `warden` references with `admin_user` throughout SSH and provisioning examples
  - **[trellis/security/MANUAL-IP-BLOCKING.md](trellis/security/MANUAL-IP-BLOCKING.md)** - Standardized all SSH commands to use `admin_user` placeholder with explanation
  - **[troubleshooting/MAIL.md](troubleshooting/MAIL.md)** - Added comprehensive SSH user access guide explaining `web`, `admin_user`, and `root` user roles with usage recommendations

### Added

- **Mail Troubleshooting Enhancement** - Expanded [troubleshooting/MAIL.md](troubleshooting/MAIL.md) with comprehensive WordPress email bounce diagnosis and solutions:
  - New "SSH User Access" section explaining when to use `web`, `admin_user`, and `root` users
  - New "Issue 2: WordPress Email Bounces - Non-Existent Admin Email" section covering:
    - Multisite network admin email configuration issues
    - WP-CLI commands for diagnosing and updating admin emails across sites
    - Comprehensive testing procedures for server-level and WordPress email functionality
    - Prevention best practices for initial setup and regular audits
    - Common pitfalls to avoid (non-existent subdomains, `.test` domains in production)
  - Detailed examples for single sites and multisite networks
  - Bulk operations for updating multiple subsites
  - Email monitoring and documentation recommendations

### Improved

- Better documentation clarity by using consistent placeholder usernames (`admin_user`) instead of specific usernames (`warden`, `admin`, `deploy`)
- Enhanced troubleshooting workflow with clear user role separation and appropriate permissions
- All SSH command examples now include contextual notes about which user to use and why

## [2.3.3] - 2026-01-07

### Added

- **Trellis Backup Documentation Enhancement** - Added alternative direct shell script method for database pull operations:
  - **[trellis/backup/README.md](trellis/backup/README.md)** - New section documenting shell script approach for interactive development
  - Standard site example with SSH pipe streaming from production to development
  - Multisite example with `--url` parameter for proper search-replace context
  - Comprehensive comparison of when to use shell scripts vs Ansible playbooks
  - Advantages: Single command execution, full visibility, SSH pipe streaming (no intermediate files), includes cache flushing
  - Use cases: Manual work, quick syncs, troubleshooting vs automation/CI-CD
  - Complete Table of Contents for improved navigation

### Changed

- Enhanced [trellis/backup/README.md](trellis/backup/README.md) with comprehensive Table of Contents
- Improved navigation with hierarchical TOC including all sections (Overview, Configuration, Automation, Troubleshooting)
- Added new "Alternative: Direct Shell Script Method" subsection under Database Pull with proper TOC linking

## [2.3.2] - 2026-01-03

### Fixed

- **Theme Release Script JSON Parsing** - Enhanced changelog extraction in [scripts/release-theme.sh](scripts/release-theme.sh) to properly handle escaped quotes and backslashes in Claude AI responses:
  - Replaced fragile `grep`/`sed` approach with robust `awk`-based JSON value extraction
  - Fixed issue where changelog entries containing escaped quotes (`\"`) would be truncated or malformed
  - Improved handling of escaped newlines (`\n`) in multi-line changelog content
  - More reliable parsing of Claude CLI JSON output for both `changelog_md` and `readme_txt` fields

## [2.3.1] - 2026-01-01

### Changed

- **Standardized placeholder domain across documentation** - Replaced `imagewize.com` with `example.com` for consistency in all generic examples and documentation:
  - Updated 13 files across scripts, documentation, and configuration examples
  - Affected files: PAGE-CREATION.md, MULTI-SITE-MIGRATION.md, CRON.md, PROJECT-SETUP.md, nginx/README.md, nginx/redirects/README.md, scripts/README.md, monitoring scripts, and more
  - Preserved historical references to `imagewize.com` in CHANGELOG.md to maintain accurate project history
  - Preserved real-world production data and case studies in security documentation (FAIL2BAN.md, security/README.md, MANUAL-IP-BLOCKING.md) which contain actual attack statistics and production examples
  - Enhanced documentation clarity by using industry-standard `example.com` placeholder domain (RFC 2606)

## [2.3.0] - 2026-01-01

### Added

- **Trellis fail2ban WordPress Protection Documentation**:
  - **[trellis/security/README.md](trellis/security/README.md)** - Security overview covering fail2ban automatic IP blocking and manual Nginx deny rules
  - **[trellis/security/FAIL2BAN.md](trellis/security/FAIL2BAN.md)** - Comprehensive fail2ban setup guide with WordPress wp-login.php protection, XML-RPC abuse prevention, configuration examples, monitoring commands, and troubleshooting
  - **[trellis/security/MANUAL-IP-BLOCKING.md](trellis/security/MANUAL-IP-BLOCKING.md)** - Advanced manual IP blocking via Nginx deny directives for extreme high-volume attacks, with implementation examples and best practices
  - Automatic IP blocking after brute force attempts (default: 6 failed attempts = 10 minute ban)
  - Zero-maintenance WordPress security via fail2ban (pre-installed in Trellis, disabled by default)
  - Real-world attack statistics showing 40+ unique attacker IPs with 20-200 failed login attempts each (Nov-Dec 2025)
  - Production impact demonstration: 1,420 wp-login attempts from single IP blocked automatically after enabling fail2ban
  - IP whitelist configuration to prevent self-lockout
  - Integration with [wp-cli/security](wp-cli/security/) malware scanners for comprehensive security workflow

### Changed

- Enhanced main [trellis/README.md](trellis/README.md) with new Security section (#3) including:
  - fail2ban WordPress protection features (automatic blocking, temporary bans, zero maintenance)
  - Manual IP blocking for extreme cases (high-volume attacks, persistent attackers)
  - Security monitoring tools (banned IPs, attack patterns, fail2ban logs)
  - Quick start guide for enabling WordPress protection
  - Real-world impact statistics (before/after fail2ban)
  - Cross-references to security documentation and malware scanners
- Renumbered existing sections: Provisioning & Setup (#3 → #4), Trellis Updater (#4 → #5)

### Improved

- Complete fail2ban WordPress jail configuration examples with recommended, stricter, and lenient settings
- Monitoring and management commands for checking status, viewing banned IPs, and manual IP management
- Self-lockout prevention with IP whitelist and emergency recovery procedures
- Detailed troubleshooting for common issues (jail not enabled, filter patterns, log paths)
- Clear comparison table showing when to use fail2ban vs manual IP blocks
- Integration workflow combining prevention (fail2ban), detection (malware scanners), and analysis (access logs)

## [2.2.2] - 2025-12-31

### Changed

- **Enhanced Trellis Provisioning Documentation**:
  - **[trellis/provision/README.md](trellis/provision/README.md)** - Added comprehensive Table of Contents with organized sections:
    - Setup Guides section linking to NEW-MACHINE.md and PROJECT-SETUP.md
    - Configuration Guides section linking to CRON.md
    - Command Reference section for general provisioning commands
  - Added "Quick Command Reference" introduction section explaining the purpose of provisioning commands and when to use them
  - Improved navigation with clear separation between initial setup guides and day-to-day command reference
  - Better workflow organization following natural user progression (machine setup → project setup → configuration → commands)

## [2.2.1] - 2025-12-31

### Added

- **Repository Logo** - Custom SVG logo with dark mode support:
  - **[assets/logo.svg](assets/logo.svg)** - Adaptive logo with theme-aware colors (gray-600 light mode, gray-400 dark mode)
  - Logo design inspired by Opsgenie icon from Blade Icons
  - Updated main [README.md](README.md) with centered logo header and credits section

- **WordPress Utilities Overview Documentation**:
  - **[wordpress-utilities/README.md](wordpress-utilities/README.md)** - Comprehensive guide to reusable WordPress components and tools
  - Detailed documentation for Age Verification, Analytics, and Speed Optimization utilities
  - Integration examples for theme functions, deployment scripts, and site audits
  - Best practices for security, performance, and maintenance
  - Coding standards and file organization guidelines
  - Contributing guidelines for adding new utilities

### Changed

- Enhanced main [README.md](README.md) header with visual logo and "WP OP" branding
- Added Credits section to main README acknowledging logo design inspiration

## [2.2.0] - 2025-12-31

### Added

- **WordPress Security Scanner Suite** - Comprehensive dual-scanner malware detection and security auditing system:
  - **[wp-cli/security/scanner-targeted.php](wp-cli/security/scanner-targeted.php)** - Site-specific threat detection for common WordPress vulnerabilities (Facebook redirects, file disclosure, SQL injection, PHP malware, code obfuscation) - Fast performance: ~1.7 seconds for 6,600 files
  - **[wp-cli/security/scanner-general.php](wp-cli/security/scanner-general.php)** - Broad-spectrum malware detection (known malware filenames, pharmaceutical spam, SEO spam, webshells, backdoor functions, encoding layers) - Comprehensive scan: ~2.5 seconds for 7,400 files
  - **[wp-cli/security/scanner-wrapper.php](wp-cli/security/scanner-wrapper.php)** - Wrapper script that runs both scanners sequentially for complete coverage
  - **[wp-cli/security/README.md](wp-cli/security/README.md)** - Complete documentation with installation, usage, troubleshooting, and hosting-specific guides (WP-CLI, direct PHP, cPanel/Plesk, browser access)
  - **[wp-cli/security/SECURITY-GUIDE.md](wp-cli/security/SECURITY-GUIDE.md)** - Detailed usage guide with scanning strategies, integration workflows, and security best practices
  - **[wp-cli/security/SCANNER-SUMMARY.md](wp-cli/security/SCANNER-SUMMARY.md)** - Quick reference guide for busy developers with common false positives and real threat examples
  - Multi-execution support: WP-CLI (`wp eval-file`), direct PHP, remote via SSH/Trellis, cron automation
  - Severity-based reporting (CRITICAL, HIGH, MEDIUM) with colored CLI output
  - Comprehensive hosting support: VPS/dedicated servers, shared hosting (SSH/FTP), cPanel/Plesk, Trellis/Bedrock
  - Security-conscious design with IP whitelisting for browser access (not recommended)

### Changed

- Updated main [README.md](README.md) to include Security Scanners tool in tools table
- Updated [CLAUDE.md](CLAUDE.md) repository structure documentation to include `wp-cli/security/` directory
- Enhanced [CLAUDE.md](CLAUDE.md) Common Commands section with Security Scanning examples and execution methods

### Improved

- Dual-scanner strategy provides both fast weekly monitoring (targeted) and comprehensive monthly audits (general)
- Extensive troubleshooting documentation covering WP-CLI installation, hosting restrictions, PHP versions, file permissions, and timeout/memory issues
- Clear separation between recommended (WP-CLI/direct PHP) and last-resort (browser) execution methods
- Integration guidance with wp-ops workflows (pre-deployment checks, post-deployment verification, incident response)

## [2.1.0] - 2025-12-31

### Added

- **WordPress Utilities Module** - New top-level directory for reusable WordPress components and tools:
  - **[wordpress-utilities/age-verification/](wordpress-utilities/age-verification/)** - Cookie-based age verification system with modal interface, ACF integration, and dynamic content filtering (JavaScript, CSS, PHP template)
  - **[wordpress-utilities/analytics/](wordpress-utilities/analytics/)** - Comprehensive analytics implementation guide covering Google Analytics (Site Kit and manual), Matomo (plugin and self-hosted), and detection methods using curl/grep
  - **[wordpress-utilities/speed-optimization/](wordpress-utilities/speed-optimization/)** - Performance testing tools with TTFB analysis using curl and wget, including Google's web.dev performance guidelines

- **WP-CLI Migration Enhancement**:
  - **[wp-cli/migration/URL-UPDATE-METHODS.md](wp-cli/migration/URL-UPDATE-METHODS.md)** - Generic WordPress URL update methods covering WP-CLI (recommended), wp-config.php constants, direct database updates, admin panel, and multisite network handling

### Changed

- **Repository Integration** - Merged [wordpress-tools](https://github.com/imagewize/wordpress-tools) repository into wp-ops for unified WordPress operations management
- Updated main [README.md](README.md) with four new tool entries: Age Verification, Analytics, Speed Optimization, and URL Update Methods
- Updated [CLAUDE.md](CLAUDE.md) repository structure documentation to reflect new `wordpress-utilities/` directory
- Created deprecation notice in wordpress-tools repository directing users to wp-ops

### Improved

- Consolidated WordPress operations tooling into single repository for better discoverability and maintenance
- Clear separation between infrastructure tools (Trellis, Nginx, Ansible) and WordPress application-level utilities
- Enhanced migration documentation with comprehensive URL update methods for all migration scenarios

## [2.0.1] - 2025-12-31

### Added

- Comprehensive README files for all top-level technology directories:
  - **[trellis/README.md](trellis/README.md)** - Complete guide to Trellis-specific tools including backup operations, monitoring, provisioning workflows, and Trellis updater
  - **[nginx/README.md](nginx/README.md)** - Nginx configuration management covering browser caching, image optimization (WebP/AVIF), URL redirects, and Trellis deployment workflows
  - **[wp-cli/README.md](wp-cli/README.md)** - WordPress CLI operations guide including content creation, diagnostics, and migration tools
  - **[scripts/README.md](scripts/README.md)** - Automation scripts documentation for GitHub integration, theme management, monitoring, and backup automation

### Changed

- Enhanced [trellis/README.md](trellis/README.md) with expanded sections:
  - Added detailed backup/restore workflows with example commands
  - Enhanced monitoring section with traffic analysis and security scanning examples
  - Improved provisioning quick reference with common command patterns
  - Updated Trellis updater documentation with troubleshooting guidance
  - Better organization of tools by functional area

### Improved

- Consistent documentation structure across all top-level directories
- Better discoverability of tools and features through comprehensive READMEs
- Cross-references between related tools and workflows
- Unified quick-start sections for common operations
- Enhanced navigation with detailed tables of contents

## [2.0.0] - 2025-12-31

### Changed

**BREAKING: Repository Restructuring and Rename**

- **Renamed repository** from `trellis-tools` to `wp-ops` to better reflect broader WordPress operations scope
- **Reorganized directory structure** into technology-based categories:
  - `trellis/` - Trellis-specific tools (backup, monitoring, provision, updater)
  - `wp-cli/` - WordPress CLI operations (content-creation, diagnostics, migration)
  - `nginx/` - Web server configurations (browser-caching, image-optimization, redirects)
  - `scripts/` - General utilities (create-pr.sh, release-theme.sh, rsync-theme.sh, plus backup and monitoring scripts)
  - `troubleshooting/` - Server and WordPress troubleshooting guides (remains at root)

### Migration Guide for Existing Users

**If you've cloned this repository:**

1. Update your git remote URL:
   ```bash
   cd trellis-tools
   git remote set-url origin https://github.com/imagewize/wp-ops.git
   git pull
   ```

2. Update any references in your scripts or documentation:
   - Old: `backup/trellis/database-backup.yml` → New: `trellis/backup/database-backup.yml`
   - Old: `provision/README.md` → New: `trellis/provision/README.md`
   - Old: `content-creation/` → New: `wp-cli/content-creation/`
   - Old: `image-optimization/` → New: `nginx/image-optimization/`
   - Old: `create-pr.sh` → New: `scripts/create-pr.sh`

3. All documentation and internal links have been updated automatically

**Note:** GitHub automatically redirects the old repository name, so existing clones will continue to work, but updating the remote URL is recommended.

## [1.17.0] - 2025-12-31

### Added
- New `release-theme.sh` script for AI-powered WordPress theme releases with Claude CLI integration
- Automated version bumping across `style.css`, `readme.txt`, and `CHANGELOG.md`
- Claude AI-powered changelog generation in two formats: detailed Keep a Changelog format and concise WordPress.org format
- Support for both demo/ and site/ Bedrock installation structures
- Interactive confirmation prompts and change preview before committing
- Automatic git diff analysis between current branch and main
- Optional `--commit` flag for automatic git commits with standardized messages
- Semantic versioning validation (X.Y.Z format)
- Dual changelog format generation:
  - **CHANGELOG.md**: Detailed with sections (Changed, Added, Fixed, Technical) and sub-sections
  - **readme.txt**: Concise single-line entries with CHANGED/ADDED/FIXED/TECHNICAL prefixes

### Changed
- Updated main README.md to include Theme Release tool in tools table between PR Creation and Theme Sync

## [1.16.3] - 2025-12-31

### Changed
- Enhanced rsync-theme.sh to preserve theme-repository-only files during sync
- Added `create-pr.sh` to exclusion list to protect theme repo's PR automation script from deletion
- Added `.distignore` to exclusion list to preserve WordPress.org deployment configuration in theme repo
- Updated example paths from 'nynaeve' theme to 'elayne' theme for better documentation clarity

### Fixed
- Theme sync now preserves files that exist only in standalone theme repository (not in Trellis project)

## [1.16.2] - 2025-12-31

### Added
- Critical URL sanitization section in PAGE-CREATION.md explaining hardcoded pattern URLs issue
- Pre-deployment URL audit commands for detecting local development URLs in production
- Step-by-step URL search-replace workflow with database backup procedures
- Browser verification steps for mixed content warnings
- CLAUDE.md section explaining how WordPress pattern URLs get hardcoded in database
- Search-replace examples for both single-site and multisite WordPress installations

### Changed
- Enhanced PAGE-CREATION.md with "CRITICAL: URL Sanitization Before Production" section
- Updated CLAUDE.md "URL Management in Database Operations" with pattern URL hardcoding warning
- Added cross-reference between CLAUDE.md and PAGE-CREATION.md for URL sanitization workflows

## [1.16.1] - 2025-12-30

### Changed
- Updated PROJECT-SETUP.md to use HTTP by default for local development instead of HTTPS
- Changed `WP_HOME` example from `https://yourproject.test` to `http://yourproject.test` for simpler local setup
- Updated all URL examples throughout the guide to use HTTP (with notes on HTTPS if SSL is enabled)
- Enhanced database pull section with URL search-replace guidance based on local SSL configuration
- Added dedicated multisite URL update section with WP-CLI `--network` flag examples
- Expanded troubleshooting section with new entries for 500 errors, WP-CLI autoloader issues, and SSH host key verification
- Added critical theme setup instructions after database pull (Composer/NPM install and build steps)
- Enhanced verification checklist to include theme dependency and asset build verification
- Added method 2 for direct rsync file sync when Ansible playbooks fail
- Updated quick reference commands to include theme setup workflow

### Added
- Multisite network URL update documentation with WP-CLI network commands
- Theme setup section explaining why Composer/NPM builds are required after database pulls
- Alternative MySQL-only commands for multisite URL updates (with warnings about limitations)
- SSH known_hosts configuration examples for production server access
- Theme asset build verification steps in checklist
- Explanation of Lima VM bidirectional file sync behavior

## [1.16.0] - 2025-12-30

### Added
- New project setup guide (provision/PROJECT-SETUP.md) for cloning and configuring existing Trellis/Bedrock projects
- Comprehensive project-specific documentation covering repository cloning, dependency installation, and VM provisioning
- Database and files setup options with Ansible playbook and direct VM command methods
- Theme development workflow with Vite dev server and HMR setup
- Production access configuration and deployment instructions
- Common project workflows including daily development, VM management, and WP-CLI operations
- Project-specific troubleshooting section with file sync, port conflicts, and SSL certificate issues
- Verification checklist for confirming successful project setup
- Quick reference commands for project management

### Changed
- **Breaking:** Refactored NEW-MACHINE.md to focus exclusively on macOS setup for Trellis development (machine setup only)
- Removed project-specific content from NEW-MACHINE.md (imagewize.com examples, ACF Pro setup, repository cloning)
- Generalized NEW-MACHINE.md with placeholder names (your-project, your-theme) for universal applicability
- Updated NEW-MACHINE.md to reference PROJECT-SETUP.md for next steps after machine configuration
- Updated main README.md to include both "New Machine Setup" and "Project Setup" guides with clear descriptions
- Reduced NEW-MACHINE.md from 804 lines to 318 lines for improved clarity and focus
- NEW-MACHINE.md now serves as a universal reference for any Trellis project

### Improved
- Clear separation of concerns between machine setup and project setup documentation
- Better navigation with cross-references between NEW-MACHINE.md and PROJECT-SETUP.md
- Enhanced reusability - PROJECT-SETUP.md serves as a template for any Trellis project
- Reduced confusion by eliminating the dual-purpose nature of the original NEW-MACHINE.md

## [1.15.0] - 2025-12-30

### Added
- Comprehensive new machine setup guide (provision/NEW-MACHINE.md) for setting up Trellis development environment
- Step-by-step instructions for installing required tools (Trellis CLI, Composer, PHP, Node.js, pnpm)
- Detailed explanation of host machine vs Trellis VM architecture and tool separation
- Complete workflow for cloning repository, installing dependencies, and configuring Trellis VM
- ACF Pro authentication setup instructions for Composer installation
- Database and files setup options (fresh installation vs production pull)
- Theme development workflow documentation with Vite dev server and HMR
- Production SSH access setup and deployment instructions
- Common development workflows (daily development, creating blocks, VM management)
- Troubleshooting section covering port conflicts, file sync, SSL certificates, and VM issues
- Verification checklist and quick reference commands
- Architecture diagrams explaining host/VM separation and development workflow
- Documentation on Lima VM vs Vagrant differences and file sync behavior

### Changed
- Updated main README.md to include "New Machine Setup" in tools table

## [1.14.0] - 2025-12-26

### Added
- New diagnostics directory with WordPress diagnostic tools for troubleshooting
- CLI transient diagnostic script (`diagnostic-transients.php`) for WP-CLI-based transient testing
- Browser-based transient debugger (`transient-debug-browser.php`) for web-accessible diagnostics
- Comprehensive diagnostic documentation covering transient storage, caching, and performance issues
- Security-conscious diagnostic tools with access controls and secret token protection
- Support for diagnosing external object cache conflicts (Redis, Memcached, LiteSpeed)
- Database performance metrics and wp_options table analysis
- Business hours logic testing for time-based cache lifetimes

### Changed
- Updated main README.md to include Diagnostics tool in tools table

## [1.13.1] - 2025-12-15

### Changed
- Updated `content-creation/PATTERN-REQUIREMENTS.md` to clarify metadata is recommended (not required), add guidance on block comment vs rendered HTML validation, extend checklist, and bump document version to 1.2

## [1.13.0] - 2025-12-15

### Added
- New `PATTERN-REQUIREMENTS.md` with comprehensive WordPress block pattern standards and validation checklist
- `AGENTS.md` contributor guide summarizing project structure, commands, coding conventions, and PR expectations

### Changed
- Reworked `content-creation/README.md` into a concise landing page with clear navigation to page creation workflows, pattern requirements, and automation scripts
- Moved the sample Gutenberg content file to `content-creation/examples/example-page-content.html` and updated references in `PAGE-CREATION.md`

## [1.12.2] - 2025-12-14

### Added
- New section "Adding Patterns to Existing Pages" to PAGE-CREATION.md with comprehensive examples
- Method 1: Update page via Trellis VM with heredoc pattern insertion
- Method 2: Batch add patterns by category for showcase pages
- Method 3: Finding pattern slugs from theme files
- Real-world Elayne theme pattern showcase examples (Heroes page and Patterns page)
- Tips for creating pattern showcase pages with consistent spacing and formatting
- Troubleshooting section for pattern rendering and content update issues
- VM-based content file creation examples using `/tmp` directory
- Multi-AI support in create-pr.sh with `--ai=claude|codex` option for flexible AI backend selection
- Interactive AI tool selection when both Claude and Codex CLIs are available
- Environment variable support for custom CLI command names (`CLAUDE_COMMAND`, `CODEX_COMMAND`)
- Support for custom AI CLI arguments via `CLAUDE_CLI_ARGS` and `CODEX_CLI_ARGS` environment variables

### Changed
- Updated PAGE-CREATION.md Table of Contents to include section 9
- Enhanced PAGE-CREATION.md with VM heredoc examples for multisite pattern updates
- Improved document version to 1.1 with updated timestamp (December 14, 2025)
- Refactored create-pr.sh option parsing to use `case` statement for better maintainability
- Enhanced AI CLI detection to check for both Claude and Codex availability
- Improved error handling in AI description generation with detailed error messages
- Updated CREATE-PR.md with multi-AI backend documentation and usage examples

## [1.12.1] - 2025-12-01

### Fixed
- **Critical:** Fixed timestamp filtering in monitoring scripts that prevented log analysis
- Fixed broken AWK timestamp parsing in `filter_recent_logs()` function (traffic-monitor.sh and security-monitor.sh)
- Fixed invalid octal number error when displaying hours 08 and 09 in traffic reports
- Replaced complex AWK-based timestamp filtering with simple tail-based line estimation (HOURS × 1000 requests)

### Changed
- Simplified log filtering approach using `tail -n` with estimated line count for better performance
- Updated monitoring scripts to process up to 50,000 most recent log lines (configurable based on time period)
- Improved monitoring script execution speed by eliminating per-line date command spawning

## [1.12.0] - 2025-12-01

### Added
- Comprehensive Nginx redirect configuration documentation and examples (redirects/)
- SEO redirect examples for fixing 404 errors and URL structure changes
- Generic redirect templates for common WordPress permalink migrations
- SSL/HTTPS redirect patterns for secure page enforcement
- Site-specific redirect example (imagewize.com/seo-redirects.conf.j2)
- Documentation covering Trellis nginx-includes deployment workflow
- Redirect best practices including exact path matching, regex patterns, and query string preservation
- Testing strategies for manual and automated redirect verification
- Performance considerations and optimization tips for large redirect sets
- Troubleshooting guide for common redirect issues (404s, loops, deployment problems)
- Methods for finding URLs to redirect using Google Search Console, server logs, and SEO tools

### Changed
- Updated main README.md to include Redirects tool in tools table

## [1.11.2] - 2025-11-29

### Fixed
- **Critical:** Fixed monitoring playbooks to use per-site log paths instead of global Nginx logs
- Updated all Ansible playbooks to default to `/srv/www/{{ site }}/logs/access.log` (Trellis standard)
- Updated traffic-report.yml, security-scan.yml, quick-status.yml to use `{{ project_root }}/logs/access.log`
- Updated setup-monitoring.yml wrapper scripts to use per-site logs in cron jobs
- Updated updown-webhook-handler.sh to default to per-site logs with environment variable override
- Updated shell scripts (traffic-monitor.sh, security-monitor.sh) to default to imagewize.com per-site logs

### Changed
- Added log path configuration documentation explaining per-site vs global logs
- Updated README.md with "Log File Locations" section and configuration override examples
- Updated QUICK-REFERENCE.md to show proper log path usage with `$LOG` variable
- All playbooks now support `-e log_file=/path/to/log` override for flexibility
- Modified all one-liner command examples to use configurable `$LOG` variable
- Shell scripts now default to `/srv/www/imagewize.com/logs/access.log` with examples for demo.imagewize.com and global logs

### Added
- Documentation explaining when to use per-site logs (default) vs global logs
- Examples showing how to override default log paths in Ansible playbooks
- Clear prerequisites about Trellis log configuration in both README and QUICK-REFERENCE
- Inline comments in shell scripts showing all available log path options

## [1.11.1] - 2025-11-29

### Changed
- Updated monitoring documentation to recommend root SSH access with key-based authentication
- Changed all monitoring examples from `web@example.com` to `root@example.com`
- Added "Alternative Access Methods" section with three options: sudo, adm group, and passwordless sudo
- Added security considerations emphasizing root password authentication must be disabled
- Updated QUICK-REFERENCE.md with root user examples and prerequisites note
- Clarified that root SSH access with keys is secure and practical for system administration tasks

## [1.11.0] - 2025-11-29

### Added
- Comprehensive monitoring tools for Nginx log analysis (monitoring/)
- Traffic analysis script (traffic-monitor.sh) with bot filtering, page views, unique visitors, and bandwidth tracking
- Security monitoring script (security-monitor.sh) for detecting bad actors, brute force attempts, SQL injection, and scanners
- Ansible playbooks for automated monitoring: quick-status.yml, traffic-report.yml, security-scan.yml, setup-monitoring.yml
- Automated monitoring setup with cron jobs for daily traffic reports and security scans
- updown.io webhook integration (updown-webhook-handler.sh and updown-webhook-receiver.php) for automatic log analysis on downtime
- Quick reference guide (QUICK-REFERENCE.md) with common monitoring commands and one-liners
- Comprehensive monitoring documentation covering traffic analysis, security monitoring, and updown.io integration
- IP blocking recommendations and fail2ban integration guidance
- GoAccess and AWStats tool integration examples
- Real-time monitoring commands and performance tracking

### Changed
- Updated main README.md to include Monitoring tools section

## [1.10.0] - 2025-11-28

### Added
- Comprehensive WordPress cron documentation (provision/CRON.md) covering system cron vs WP-Cron
- WordPress Cron section in migration guide explaining the transition from WP-Cron to system cron
- Multisite cron configuration documentation with real examples
- Cron verification commands and log examples from production systems
- Log filtering commands for monitoring specific sites on multi-site servers
- WordPress Cron section in provision/README.md with reference to detailed guide

### Changed
- Updated migration guide Table of Contents to include WordPress Cron section
- Enhanced provision documentation with cron reference and link to CRON.md

## [1.9.1] - 2025-11-27

### Added
- Theme screenshot example demonstrating proper screenshot formatting and dimensions

## [1.9.0] - 2025-11-26

- This update adds a new ImageMagick command to the RESIZE-AND-CONVERSION.md documentation, specifically for resizing screenshots to fit theme requirements (1200x900 pixels). The command ensures the screenshot is centered and cropped to the exact dimensions, which is useful for maintaining consistency in theme-related visuals.


### Added
- Automated page creation script (page-creation.sh) for deploying WordPress pages to production
- Example WordPress page content file (example-page-content.html) with Gutenberg block markup
- Script features: automated SCP file transfer, conflict detection/resolution, interactive prompts, verification, and cleanup
- Comprehensive automated script documentation section in PAGE-CREATION.md
- Quick Start section in content-creation README with script usage examples
- Files in This Directory section in content-creation README

### Changed
- Updated PAGE-CREATION.md to feature automated script as recommended Option 1 for production deployment
- Enhanced PAGE-CREATION.md with detailed script workflow, customization, security considerations, and requirements
- Reorganized PAGE-CREATION.md Table of Contents to include Automated Script Details and Examples sections
- Removed all references to external `seo-strategy` directory for self-contained documentation
- Updated all code examples to use generic paths and the included example-page-content.html file
- Enhanced content-creation README with script and example file references

## [1.8.0] - 2025-11-25

### Added
- Comprehensive WordPress page creation guide (PAGE-CREATION.md) with step-by-step instructions for Trellis/Bedrock
- Local development workflow using Trellis VM and WP-CLI for page creation
- Production deployment strategies (recreate, export/import, WXR)
- Content preparation guidelines for Gutenberg blocks and patterns
- Common issues and solutions for page creation workflows
- Best practices for development, security, performance, and SEO optimization
- Complete example workflows with full command sequences
- Quick reference guide with essential paths and commands

### Changed
- Enhanced content-creation README with Page Creation Guide reference
- Updated Related Guides section in content-creation README
- Added troubleshooting and additional resources sections to content-creation README

## [1.7.0] - 2025-11-25

### Added
- Out of Memory (OOM) troubleshooting guide with comprehensive WP-Cron memory leak diagnosis
- Mail configuration troubleshooting guide for SMTP issues after Trellis upgrades
- OOM guide includes PHP CLI memory limit analysis, WP-Cron investigation, and Action Scheduler debugging
- Mail guide includes symptoms, diagnosis steps, and prevention best practices
- Mail configuration verification step in trellis-updater.sh that checks for SMTP settings (Brevo/Sendgrid) after update
- `mail.yml` to rsync exclusion list in both trellis-updater.sh and manual-update.md
- Detailed mail.yml restoration instructions in updater script warnings

### Changed
- Updated troubleshooting README to include OOM and MAIL guides in guides table
- Enhanced trellis-updater.sh with mail.yml preservation and verification
- Enhanced manual-update.md with mail.yml exclusion and preservation notes
- Updated updater rsync comments to include SMTP settings preservation category
- Improved file verification warnings with specific restoration commands for mail.yml

## [1.6.0] - 2025-11-23

### Added
- New troubleshooting section with comprehensive server diagnostics guides
- PHP-FPM troubleshooting guide covering pool exhaustion, memory management, worker configuration, and the low-traffic recycling problem
- MariaDB troubleshooting guide covering startup failures, compression plugin issues, and connection problems
- Quick diagnostic commands reference for system health checks

## [1.5.3] - 2025-11-22

### Added
- Critical file verification step in trellis-updater.sh that checks for `.vault_pass`, `ansible.cfg`, and vault.yml files after update
- Vault password troubleshooting section in updater README with step-by-step recovery instructions
- `ansible.cfg` to rsync exclusion list to preserve vault_password_file setting

### Changed
- Updated preservation list in README to note `ansible.cfg` as CRITICAL for vault operations

## [1.5.2] - 2025-11-22

### Added
- Post-upgrade manual review section in updater README with guidance for role templates, new variables, and Galaxy roles
- Organized preservation list by category (Secrets, Git/CI, Site Config, PHP/Server Settings, Deploy Hooks)

### Changed
- Updated trellis-updater.sh to exclude custom PHP/server settings (`main.yml` files) and deploy hooks
- Updated manual-update.md rsync command with additional exclusions for `main.yml` files and `deploy-hooks/`
- Added explanatory comments in updater script for rsync exclude categories

## [1.5.1] - 2025-11-15

### Added
- CLAUDE.md file with comprehensive guidance for Claude Code AI assistant
- Architecture documentation for Ansible playbook structure and patterns
- File naming conventions and compression strategies documentation
- URL management patterns for database operations
- Development workflow guidance for PR creation and backup testing

### Changed
- Updated README with Content Creation Tools section (tool #6)
- Updated README with GitHub PR Creation Script section (tool #7)
- Renumbered Theme Sync Script to #8 and Provisioning Documentation to #9
- Enhanced Requirements section with tool-specific dependencies
- Improved documentation organization and cross-references

## [1.5.0] - 2025-11-15

### Added
- Content creation guide with WordPress block patterns and WP-CLI commands
- Image resizing and conversion guide (RESIZE-AND-CONVERSION.md) with comprehensive ImageMagick examples
- Detailed workflows for creating optimized avatars and thumbnails
- Batch processing examples for image conversion
- Quality settings recommendations for JPEG, WebP, and AVIF formats
- Responsive image workflow examples
- File size comparison data for different image formats

### Changed
- Enhanced image optimization documentation with better structure and cross-references
- Updated README to reference new image resizing guide
- Improved quality settings guidance across all image formats
- Added ImageMagick installation instructions to main image optimization README

## [1.4.0] - 2025-10-23

### Added
- Theme Rsync script for syncing theme files from Trellis to standalone theme repository
- Multi-site migration guide with strategies for migrating multiple WordPress sites to a single Trellis server
- Complete single-site migration guide: Regular WordPress to Trellis/Bedrock
- PR creation shell script for automated pull request workflows
- PHP upgrade additions to provisioning documentation

### Changed
- Updated migration documentation with comprehensive guides and best practices
- Enhanced main README with theme sync and migration guide references

## [1.3.0] - 2025-10-02

### Added
- Provisioning documentation with common Trellis commands and workflows
- Files backup, pull, and push playbooks for managing uploads
- Comprehensive backup documentation with Ansible playbooks and shell scripts
- Backup retention and compression strategies using tar.gz and sql.gz formats

### Changed
- Updated backup playbooks to follow Trellis conventions
- Enhanced database backup script with better export messages
- Improved backup clarification and organization
- Extended browser caching expiry dates for better performance
- Cleaned up assets configuration

### Fixed
- Database export message formatting
- Backup playbooks compatibility issues

### Removed
- Map directive from Nginx configuration

## [1.2.0] - 2025-05-27

### Added
- Site-wide browser caching configuration for static assets
- Assets expiry configuration for images, CSS, JavaScript, and fonts
- Cache headers for optimal performance

### Changed
- Refactored browser caching implementation for better coverage

### Removed
- Deprecated caching directory structure
- Acorn-specific caching references

## [1.1.0] - 2025-04-27

### Added
- WordPress migration tools and commands documentation
- Migration commands for domain changes, multisite handling, and Bedrock path conversions

## [1.0.0] - 2025-04-26

### Added
- Manual Trellis update documentation with step-by-step instructions
- Alternative to automated updater script

### Changed
- Renamed 'updates' directory to 'updater' for clarity

### Fixed
- Nginx configuration typo

## [1.0.0-beta.4] - 2025-04-26

### Added
- Image optimization configuration supporting WebP and AVIF formats
- Nginx configuration for automatic modern image format serving
- Image optimization documentation

### Changed
- Major restructuring of directory organization
- Updated documentation structure for better clarity
- New directory structure for better tool organization

## [1.0.0-beta.3] - 2025-04-24

### Removed
- Deleted files and directories cleanup

## [1.0.0-beta.2] - 2025-04-24

### Changed
- Updated README exclusion list for updater script

## [1.0.0-beta.1] - 2025-04-24

### Added
- Staging vault exclusion in updater script
- .github directory exclusion from updates

### Changed
- Modified copy command to use standard cp without -a flag

## [1.0.0-alpha.2] - 2025-04-24

### Added
- Script limitations documentation
- Note on commit deactivation option

## [1.0.0-alpha.1] - 2025-04-24

### Added
- Initial project setup
- README documentation
- MIT License
- Trellis updater script for safe Trellis updates
- Automated backup and update workflow
- Git integration for tracking changes
