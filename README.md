<div align="center">
  <img src="assets/logo.svg" alt="WordPress Operations Logo" width="128" height="128">
    <h1>WP OPS</h1> 
</div>


<div align="center">
Tools, scripts, and guides for modern WordPress development & devops—optimized for <a href="https://roots.io/trellis/">Trellis</a>/<a href="https://roots.io/bedrock/">Bedrock</a> workflows.
</div>

## Contents

- [Trellis](#trellis)
- [WP-CLI](#wp-cli)
- [Nginx](#nginx)
- [Scripts](#scripts)
- [WordPress Utilities](#wordpress-utilities)

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
| **Troubleshooting** | Diagnose PHP-FPM, MariaDB, and server issues | [→](troubleshooting/README.md) |

## WP-CLI

| Tool | Description | Docs |
|------|-------------|------|
| **Content Creation** | Automated page creation and content management workflows | [→](wp-cli/content-creation/README.md) |
| **Migration Tools** | Migrate WordPress sites to Trellis/Bedrock (single and multi-site) | [→](wp-cli/migration/README.md) |
| **URL Update Methods** | WordPress URL update methods for migrations | [→](wp-cli/migration/URL-UPDATE-METHODS.md) |
| **Diagnostics** | Diagnostic tools for transients, caching, and performance | [→](wp-cli/diagnostics/README.md) |
| **Security Scanners** | Dual-scanner suite for malware detection and security auditing | [→](wp-cli/security/README.md) |

## Nginx

| Tool | Description | Docs |
|------|-------------|------|
| **Image Optimization** | WebP/AVIF configuration with automatic format serving | [→](nginx/image-optimization/README.md) |
| **Browser Caching** | Optimal static asset caching configuration | [→](nginx/browser-caching/README.md) |
| **Redirects** | Redirect configuration for SEO and URL management | [→](nginx/redirects/README.md) |

## Scripts

| Tool | Description | Docs |
|------|-------------|------|
| **PR Creation** | AI-powered GitHub PR descriptions (Claude/Codex) | [→](CREATE-PR.md) |
| **Plugin Release** | AI-powered version bumping and changelog generation for plugins | [→](scripts/release-plugin.sh) |
| **Theme Release** | AI-powered version bumping and changelog generation for themes | [→](scripts/release-theme.sh) |
| **Theme Sync** | Rsync script for theme synchronization | [→](scripts/rsync-theme.sh) |

## WordPress Utilities

| Tool | Description | Docs |
|------|-------------|------|
| **Snippets** | Self-contained PHP snippets ready to drop into themes or plugins | [→](wordpress-utilities/snippets/README.md) |
| **Age Verification** | Cookie-based age verification with modal interface and ACF integration | [→](wordpress-utilities/age-verification/README.md) |
| **Analytics** | Google Analytics, Matomo implementation and detection | [→](wordpress-utilities/analytics/README.md) |
| **Speed Optimization** | Performance testing and TTFB analysis with curl/wget | [→](wordpress-utilities/speed-optimization/README.md) |

## Requirements

- **Core**: Git, Bash, rsync
- **Tool-specific**: See individual docs for Ansible, WP-CLI, ImageMagick, etc.

## License

MIT License. See [LICENSE.md](LICENSE.md) for details.

---

Copyright © Imagewize
