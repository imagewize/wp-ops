# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a collection of tools, scripts, and documentation for WordPress operations, server management, and [Roots Trellis](https://roots.io/trellis/) workflows. The repository contains Ansible playbooks, shell scripts, Nginx configurations, WP-CLI utilities, and comprehensive documentation.

## Repository Structure

- **trellis/** - Trellis-specific tools and workflows
  - `trellis/backup/` - Ansible playbooks for database/files backup, pull, and push operations
  - `trellis/monitoring/` - Nginx log monitoring and traffic analysis
  - `trellis/provision/` - Provisioning guides and command reference
  - `trellis/updater/` - Safe Trellis update scripts
- **wp-cli/** - WordPress command-line operations
  - `wp-cli/content-creation/` - WP-CLI content creation and block patterns
  - `wp-cli/diagnostics/` - WordPress diagnostic tools
  - `wp-cli/migration/` - WordPress migration documentation and URL update methods
  - `wp-cli/security/` - Malware detection and security scanning
- **nginx/** - Web server configurations
  - `nginx/browser-caching/` - Browser caching configuration
  - `nginx/image-optimization/` - WebP/AVIF configuration and guides
  - `nginx/redirects/` - SEO and URL redirect management
- **scripts/** - General utility scripts
  - `scripts/backup/` - Standalone backup shell scripts
  - `scripts/monitoring/` - Monitoring helper scripts
  - `scripts/create-pr.sh` - AI-powered GitHub PR creation
  - `scripts/release-theme.sh` - WordPress theme release automation
  - `scripts/rsync-theme.sh` - Theme synchronization
- **wordpress-utilities/** - Reusable WordPress components and utilities
  - `wordpress-utilities/age-verification/` - Cookie-based age verification system with modal and ACF integration
  - `wordpress-utilities/analytics/` - Analytics implementation and detection (Google Analytics, Matomo)
  - `wordpress-utilities/speed-optimization/` - Performance testing and TTFB analysis tools (curl, wget)
- **troubleshooting/** - Server and WordPress troubleshooting guides

## Key Technologies

- **Trellis**: WordPress server provisioning and deployment framework (Ansible-based)
- **Bedrock**: Modern WordPress boilerplate with Composer dependency management
- **Ansible**: Automation tool used by Trellis
- **WP-CLI**: WordPress command-line interface
- **Nginx**: Web server with custom configuration includes
- **Shell scripting**: Bash scripts for automation

## Common Commands

### Trellis Provisioning

Commands assume you're in a Trellis directory when working with Ansible playbooks:

```bash
# Provision with specific tags
trellis provision --tags php,nginx,composer production

# Deploy to environment
ansible-playbook deploy.yml -e env=staging
ansible-playbook deploy.yml -e env=production

# PHP version upgrade (requires specific tags)
trellis provision --tags php,nginx,wordpress-setup,users,memcached production
```

### Backup Operations

Ansible playbooks require `-e site=example.com -e env=<environment>` parameters:

```bash
# Database backup
ansible-playbook trellis/backup/database-backup.yml -e site=example.com -e env=production

# Database pull (from remote to development)
ansible-playbook trellis/backup/database-pull.yml -e site=example.com -e env=production

# Database push (from development to remote)
ansible-playbook trellis/backup/database-push.yml -e site=example.com -e env=staging

# Files (uploads) operations
ansible-playbook trellis/backup/files-backup.yml -e site=example.com -e env=production
ansible-playbook trellis/backup/files-pull.yml -e site=example.com -e env=production
ansible-playbook trellis/backup/files-push.yml -e site=example.com -e env=staging
```

### WP-CLI Operations

Common WordPress operations via command line:

```bash
# Local development (from Bedrock site directory)
wp post list --post_type=page --path=web/wp
wp post update 100 --post_content="$CONTENT" --path=web/wp

# Remote via Trellis
trellis vm shell --workdir /srv/www/example.com/current -- wp post list --path=web/wp
```

### Security Scanning

WordPress malware detection and security auditing:

```bash
# Run both scanners (recommended first scan)
wp eval-file wp-cli/security/scanner-wrapper.php

# Quick weekly check (1-2 seconds)
wp eval-file wp-cli/security/scanner-targeted.php

# Deep monthly scan (2-3 seconds)
wp eval-file wp-cli/security/scanner-general.php

# Scan specific directory
php wp-cli/security/scanner-targeted.php /path/to/wordpress

# Remote scan via Trellis
trellis ssh production -- "cd /srv/www/example.com/current && \
  wp eval-file /path/to/scanner-targeted.php"
```

**Execution methods** (when WP-CLI unavailable):
- Direct PHP: `php scanner-targeted.php /path/to/wordpress`
- cPanel/Plesk terminal: Use version-specific PHP binaries (e.g., `/opt/plesk/php/8.2/bin/php`)
- Browser access: Requires IP whitelist, delete files immediately after use (security risk)
- Local scan: Download WordPress via FTP and scan locally (safest for restricted hosting)
- See `wp-cli/security/README.md` for complete installation and troubleshooting guide

### Image Optimization

```bash
# Convert to WebP
cwebp -q 80 image.jpg -o image.jpg.webp

# Convert to AVIF
cavif --quality 80 image.jpg

# Batch conversion
find . -type f -name "*.jpg" -exec cwebp -q 80 {} -o {}.webp \;
```

### GitHub PR Creation

The create-pr.sh script uses Claude CLI to generate AI-powered PR descriptions:

```bash
# Interactive mode with AI description
./scripts/create-pr.sh

# Non-interactive with arguments
./scripts/create-pr.sh main "Add feature name"

# Skip AI generation (0 tokens)
./scripts/create-pr.sh --no-ai

# Update existing PR
./scripts/create-pr.sh --update
```

## Architecture and Patterns

### Ansible Playbook Structure

All Trellis integration playbooks follow this pattern:

1. **Variable validation** - Import `variable-check.yml` to validate required `site` and `env` parameters
2. **Host targeting** - Target specific environment: `hosts: web:&{{ env }}`
3. **Remote user** - Use web_user defined in Trellis: `remote_user: "{{ web_user }}"`
4. **Local delegation** - Tasks for development environment use `delegate_to: localhost` and `become: no`
5. **Backup before destructive operations** - Pull/push playbooks create backups automatically
6. **Cleanup** - Temporary files removed after operations

### File Naming Conventions

Backup files use timestamped naming:

- **Database backups**: `{site}_{env}_{YYYY_MM_DD}_{HH_MM_SS}.sql.gz`
- **Files backups**: `{site}_{env}_uploads_{YYYY_MM_DD}_{HH_MM_SS}.tar.gz`

### Compression Strategy

- **Database backups**: Use `.sql.gz` (gzip) for single SQL files with direct piping for performance
- **Files backups**: Use `.tar.gz` for directory archives to preserve structure

### URL Management in Database Operations

Pull/push playbooks automatically handle URL replacement using WP-CLI search-replace:

- Development URLs determined from `local_path` configuration
- Remote URLs extracted from `canonical` hostname in site configuration
- Replacement happens during database import with `wp search-replace`

**CRITICAL: Pattern URLs Get Hardcoded**

WordPress pattern files that use `get_template_directory_uri()` create **environment-specific URLs that get hardcoded into the database**:

- Pattern created locally: `http://example.test/app/themes/theme-name/patterns/images/image.webp`
- Saved to database: URL is hardcoded in `wp_posts.post_content`
- Problem: Moving database to production without search-replace causes mixed content warnings

**Always verify URLs after database operations:**

```bash
# Audit for dev URLs in production
ssh web@example.com "cd /srv/www/example.com/current && \
  wp db query \"SELECT COUNT(*) FROM wp_posts WHERE post_content LIKE '%.test%';\" --path=web/wp"

# If found, run search-replace
ssh web@example.com "cd /srv/www/example.com/current && \
  wp search-replace 'http://example.test' 'https://example.com' --all-tables --precise --path=web/wp"
```

**See also:** `wp-cli/content-creation/PAGE-CREATION.md` section "CRITICAL: URL Sanitization Before Production" for detailed workflows.

## Important Considerations

### Trellis Configuration

- Site names in Ansible commands must match keys in `group_vars/*/wordpress_sites.yml`
- The `local_path` variable defines where the Bedrock site is located
- Environment-specific vault files contain sensitive credentials

### PHP Version Upgrades

When upgrading PHP in Trellis, **must** include these tags:
- `php` - Installs new version
- `nginx` - Updates PHP-FPM socket configuration
- `wordpress-setup` - Creates PHP version-specific pool configuration
- `users` - **Critical**: Updates sudoers for PHP-FPM reload (deployments fail without this)
- `memcached` - Installs version-specific memcached extension

### WordPress Block Patterns

Content created with WP-CLI uses WordPress block markup format:

```html
<!-- wp:pattern {"slug":"theme-name/pattern-slug"} /-->
```

When updating post content via WP-CLI:
- Use heredocs with quoted delimiters: `<< 'EOF'`
- For complex content, use Python escaping method
- Always test locally before updating production

### Nginx Configuration

Custom Nginx includes (browser caching, image optimization) must be:
1. Copied to Trellis `nginx-includes/` directory
2. Referenced in `wordpress_sites.*.nginx_includes` configuration
3. Applied via `trellis provision <environment>`

## Development Workflow

### Creating a PR with AI Description

The create-pr.sh script is optimized for Claude CLI integration:

1. Runs locally, analyzes git history
2. Sends structured prompt to Claude (500-1,500 tokens vs 2,000-10,000 for manual)
3. Generates professional description with grouped sections
4. Creates clickable file links to GitHub
5. Automatically detects change categories

Use `--no-ai` flag for simple PRs to avoid token usage.

### Testing Backup Operations

Before running backup operations on production:

1. Test on development environment first
2. Verify backup file creation and location
3. For pull/push operations, verify URL replacement is correct
4. Always check disk space before creating backups

### Image Optimization Workflow

1. Resize/crop images with ImageMagick if needed
2. Convert to WebP/AVIF formats
3. Deploy Nginx configuration to serve optimized formats automatically
4. Original images serve as fallback for unsupported browsers

## Notes for AI Assistants

- When suggesting Ansible playbook modifications, maintain the existing error handling and backup patterns
- Database operations should always use WP-CLI through `wp` commands, not direct MySQL
- Shell scripts should follow the existing pattern of configuration variables at the top
- Nginx configuration files use Jinja2 templating (`.conf.j2` extension)
- All backup/pull/push operations require both `site` and `env` parameters
- The repository contains documentation-only tools; they're copied into Trellis projects for actual use
