<div align="center">
  <img src="assets/logo.svg" alt="WordPress Operations Logo" width="128" height="128">
    <h1>WP OPS</h1> 
</div>


<div align="center">
Tools, scripts, and guides for modern WordPress development & devops—optimized for <a href="https://roots.io/trellis/">Trellis</a>/<a href="https://roots.io/bedrock/">Bedrock</a> workflows.
</div>

## Tools

| Tool | Description | Documentation |
|------|-------------|---------------|
| **Trellis Updater** | Safely update Trellis while preserving custom configurations | [→ Guide](trellis/updater/README.md) |
| **Backup Tools** | Ansible playbooks for database and files backup/push/pull operations | [→ Guide](trellis/backup/README.md) |
| **Provisioning Reference** | Common Trellis provisioning commands and workflows | [→ Guide](trellis/provision/README.md) |
| **New Machine Setup** | Set up macOS for Trellis development (tools, SSH, VM architecture) | [→ Guide](trellis/provision/NEW-MACHINE.md) |
| **Project Setup** | Clone and configure an existing Trellis/Bedrock project | [→ Guide](trellis/provision/PROJECT-SETUP.md) |
| **Monitoring** | Nginx log monitoring for traffic analysis and security threat detection | [→ Guide](trellis/monitoring/README.md) |
| **Security** | WordPress protection via fail2ban automatic IP blocking and manual deny rules | [→ Guide](trellis/security/README.md) |
| **Content Creation** | Automated page creation and WP-CLI content management workflows | [→ Guide](wp-cli/content-creation/README.md) |
| **Migration Tools** | Migrate WordPress sites to Trellis/Bedrock (single and multi-site) | [→ Guide](wp-cli/migration/README.md) |
| **URL Update Methods** | Generic WordPress URL update methods for migrations | [→ Guide](wp-cli/migration/URL-UPDATE-METHODS.md) |
| **Diagnostics** | WordPress diagnostic tools for transients, caching, and performance issues | [→ Guide](wp-cli/diagnostics/README.md) |
| **Security Scanners** | Dual-scanner suite for WordPress malware detection and security auditing | [→ Guide](wp-cli/security/README.md) |
| **Image Optimization** | Nginx WebP/AVIF configuration with automatic format serving | [→ Guide](nginx/image-optimization/README.md) |
| **Browser Caching** | Nginx configuration for optimal static asset caching | [→ Guide](nginx/browser-caching/README.md) |
| **Redirects** | Nginx redirect configuration for SEO and URL management | [→ Guide](nginx/redirects/README.md) |
| **Troubleshooting** | Diagnose and resolve PHP-FPM, MariaDB, and server issues | [→ Guide](troubleshooting/README.md) |
| **PR Creation Script** | AI-powered GitHub PR descriptions with multi-AI backend support (Claude/Codex) | [→ Guide](CREATE-PR.md) |
| **Plugin Release** | AI-powered version bumping and changelog generation for WordPress plugins | [→ Script](scripts/release-plugin.sh) |
| **Theme Release** | AI-powered version bumping and changelog generation for WordPress themes | [→ Script](scripts/release-theme.sh) |
| **Theme Sync** | Rsync script for theme synchronization | [→ Script](scripts/rsync-theme.sh) |
| **Age Verification** | Cookie-based age verification system with modal interface and ACF integration | [→ Guide](wordpress-utilities/age-verification/README.md) |
| **Analytics** | Implementation and detection of Google Analytics, Matomo, and other analytics tools | [→ Guide](wordpress-utilities/analytics/README.md) |
| **Speed Optimization** | Performance testing tools and TTFB analysis with curl/wget | [→ Guide](wordpress-utilities/speed-optimization/README.md) |

## Quick Start

Choose the tool you need and follow its dedicated guide for detailed setup and usage instructions.

## Requirements

- **Core**: Git, Bash, rsync
- **Tool-specific**: See individual documentation for Ansible, WP-CLI, ImageMagick, etc.

## Credits

Logo design inspired by [Opsgenie icon](https://blade-ui-kit.com/blade-icons/si-opsgenie) from [Blade Icons](https://blade-ui-kit.com/blade-icons).

## License

MIT License. See [LICENSE.md](LICENSE.md) for details.

---

Copyright © Imagewize