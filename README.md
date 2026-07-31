<div align="center">
  <img src="assets/logo.svg" alt="WordPress Operations Logo" width="128" height="128">
    <h1>WP OPS</h1> 
</div>


<div align="center">
Tools, scripts, and guides for modern WordPress development & devops—optimized for <a href="https://roots.io/trellis/">Trellis</a>/<a href="https://roots.io/bedrock/">Bedrock</a> workflows.
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

A single entry point for everything in this repo. Auto-discovers commands across every category and groups them by subdirectory.

```bash
./install.sh                 # add wp-ops to your PATH (one-time)
wp-ops                       # interactive category → command picker
wp-ops --help                # list all categories
wp-ops trellis --help        # list commands in one category
wp-ops <category> <command> [args...]
```

Ansible playbook commands (`wp-ops trellis <playbook>`, covering `trellis/backup/` and `trellis/monitoring/`) run against a real Trellis project's `ansible.cfg`, inventory, and `group_vars/`, so set `TRELLIS_DIR` first:

```bash
export TRELLIS_DIR=/path/to/your/trellis
wp-ops trellis database-backup -e site=example.com -e env=production
```

Likewise, WP-CLI script commands (`wp-ops wp-cli <script>`, `wp-ops bedrock <script>` — the security scanners, transient diagnostics, and the pattern-validate command) run against a real WordPress/Bedrock install via `wp`, so set `WP_SITE_DIR` first:

```bash
export WP_SITE_DIR=/path/to/your/bedrock-site
wp-ops wp-cli scanner-wrapper
wp-ops bedrock wp-cli-pattern-validate web/app/themes/your-theme/patterns/ --fix
```

`wordpress-utilities/` is different again — those files are copy-paste-into-a-theme reference snippets (PHP includes, CSS, browser JS), not scripts with meaningful "run" behavior. `wp-ops wordpress-utilities <snippet>` prints or clipboard-copies them instead of executing them:

```bash
wp-ops wordpress-utilities footer            # print to stdout
wp-ops wordpress-utilities footer --copy      # copy to clipboard
wp-ops wordpress-utilities footer --path      # print just the file path
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
| **Security** | fail2ban IP blocking and manual deny rules | [→](trellis/security/README.md) |

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

Standalone Bash/PHP utilities — see [scripts/README.md](scripts/README.md) for full docs, flags, and examples.

### Releases & GitHub

| Tool | Description | Docs |
|------|-------------|------|
| **PR Creation** | AI-powered GitHub PR descriptions (Claude/Codex) | [→](CREATE-PR.md) |
| **Plugin Release** | AI-powered version bumping and changelog generation for plugins | [→](scripts/release/release-plugin.sh) |
| **Theme Release** | AI-powered version bumping and changelog generation for themes | [→](scripts/release/release-theme.sh) |
| **WordPress.org Deploy** | Publish a plugin to the WordPress.org SVN directory | [→](scripts/README.md#deploy-plugin-wporgsh) |
| **Release Asset Upload** | Manually attach a zip to an existing GitHub release | [→](scripts/release/upload-release-asset.sh) |

### Monitoring & Security

| Tool | Description | Docs |
|------|-------------|------|
| **Run Monitoring** | Orchestrator: runs all monitors and generates a markdown summary | [→](scripts/monitoring/run-monitoring.sh) |
| **Traffic Monitor** | Nginx traffic analysis with bot filtering and reporting | [→](scripts/monitoring/traffic-monitor.sh) |
| **Security Monitor** | Nginx threat detection with IP block recommendations | [→](scripts/monitoring/security-monitor.sh) |
| **AI Bot Monitor** | AI crawler traffic analysis (GPTBot, ClaudeBot, etc.) | [→](scripts/monitoring/ai-bot-monitor.sh) |
| **404 Checker** | Internal broken-link checker — homepage scan or recursive spider | [→](scripts/README.md#404-checkersh) |
| **Redirect Check** | Mass URL redirect checker using curl | [→](scripts/README.md#redirect-checksh) |
| **CF7 Smoke Test** | Playwright post-deploy contact-form submission check | [→](scripts/monitoring/cf7-smoke-test.js) |
| **Updown Webhook** | updown.io downtime alert handler + PHP receiver | [→](scripts/monitoring/updown-webhook-handler.sh) |

### Content & Backups

| Tool | Description | Docs |
|------|-------------|------|
| **Post Count** | Count published blog posts by year/month (blog posts only, CPTs excluded) | [→](scripts/README.md#post-countsh) |
| **DB Backup** | Trellis-aware database backup with optional URL replacement | [→](scripts/backup/db-backup.sh) |
| **Site Backup** | Full site backup (database + uploads + config + content) | [→](scripts/backup/site-backup.sh) |

### Images, WooCommerce & Files

| Tool | Description | Docs |
|------|-------------|------|
| **Batch Resize** | Batch resize + center-crop images for featured images | [→](scripts/README.md#batch-resizesh) |
| **WebP Convert** | JPG→WebP at the Facebook OG ratio with center crop | [→](scripts/README.md#convert-to-webpsh) |
| **Product Variations** | Bulk-create WooCommerce product variations via WP-CLI | [→](scripts/woocommerce/create-product-variations.sh) |
| **Theme Sync** | Rsync a theme between Trellis and a standalone repo | [→](scripts/sync/rsync-theme.sh) |
| **Package → Site Sync** | Push a plugin/theme working copy into a Bedrock site to test unreleased changes | [→](scripts/README.md#rsync-package-to-sitesh) |
| **Find & Replace** | Batch find and replace files across directory trees | [→](scripts/misc/find-and-replace-files.sh) |
| **Git Log Oneline** | Show recent git commits as compact one-liners | [→](scripts/README.md#git-log-onelinesh) |

## MCP Server

Exposes wp-ops operations as [MCP](https://modelcontextprotocol.io) tools, so Claude (and other MCP-compatible clients) can call them directly instead of running the underlying scripts by hand. Scaffold stage — one tool implemented so far, more (backups, PR creation, releases, image optimization) planned. See [mcp-server/README.md](mcp-server/README.md) for setup, transports (stdio/Streamable HTTP), and Docker usage.

| Tool | Description | Docs |
|------|-------------|------|
| **security_scan** | Run the wp-cli security scanners against a registered site/environment (local or over SSH) | [→](mcp-server/README.md) |

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
