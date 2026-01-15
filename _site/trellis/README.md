# Trellis Tools & Workflows

A comprehensive collection of Ansible playbooks, scripts, and documentation for managing WordPress sites with [Roots Trellis](https://roots.io/trellis/).

**Note**: Commands in this guide use `admin_user` as a placeholder for your Trellis admin username. Replace with your configured username (e.g., `admin`, `deploy`, `warden`, your name).

## Overview

This directory contains production-ready tools for:

- **Database & File Synchronization** - Backup, pull, and push operations with automatic URL replacement
- **Server Monitoring** - Nginx log analysis for traffic patterns and security threats
- **Security** - WordPress protection via fail2ban automatic IP blocking and manual deny rules
- **Provisioning & Setup** - Server configuration, PHP upgrades, and WordPress cron management
- **Safe Upgrades** - Trellis version updates while preserving custom configurations

## Directory Structure

```
trellis/
├── backup/          # Database & file sync Ansible playbooks
├── monitoring/      # Nginx log analysis & security monitoring
├── provision/       # Server setup & configuration guides
├── security/        # WordPress security tools (fail2ban, IP blocking)
└── updater/         # Safe Trellis version upgrade tools
```

## Quick Start

### Prerequisites

- Trellis-managed WordPress site
- Ansible installed (included with Trellis)
- SSH access to remote servers
- Site configuration in `group_vars/*/wordpress_sites.yml`

### Common Operations

All Ansible playbooks require `-e site=example.com -e env=<environment>` parameters:

```bash
# Database operations
ansible-playbook trellis/backup/database-backup.yml -e site=example.com -e env=production
ansible-playbook trellis/backup/database-pull.yml -e site=example.com -e env=production

# File operations
ansible-playbook trellis/backup/files-backup.yml -e site=example.com -e env=production
ansible-playbook trellis/backup/files-pull.yml -e site=example.com -e env=production

# Monitoring
ansible-playbook trellis/monitoring/quick-status.yml -e site=example.com -e env=production
ansible-playbook trellis/monitoring/traffic-report.yml -e site=example.com -e env=production -e hours=6

# Trellis upgrade
./trellis/updater/trellis-updater.sh
```

---

## 1. Backup & Synchronization

**Location:** `backup/`

Ansible playbooks for automated database and file operations between Trellis environments.

### Features

- **Database Operations**
  - Backup: Create timestamped database snapshots
  - Pull: Download from remote to development with automatic URL replacement
  - Push: Upload from development to remote with automatic URL replacement

- **File Operations**
  - Backup: Create timestamped uploads archives
  - Pull: Download WordPress uploads from remote to development
  - Push: Upload WordPress uploads from development to remote

- **Safety Features**
  - Automatic backups before destructive operations (pull/push)
  - URL search-replace when moving databases between environments
  - Timestamped backup files: `{site}_{env}_{YYYY_MM_DD}_{HH_MM_SS}.sql.gz`
  - Automatic cleanup of temporary files

### Available Playbooks

| Playbook | Purpose |
|----------|---------|
| `database-backup.yml` | Create database backup on remote server |
| `database-pull.yml` | Pull database from remote → development |
| `database-push.yml` | Push database from development → remote |
| `files-backup.yml` | Create uploads backup on remote server |
| `files-pull.yml` | Pull uploads from remote → development |
| `files-push.yml` | Push uploads from development → remote |

### Usage Examples

```bash
# Create production database backup
ansible-playbook backup/database-backup.yml -e site=example.com -e env=production

# Pull production database to development (with URL replacement)
ansible-playbook backup/database-pull.yml -e site=example.com -e env=production

# Push uploads to staging
ansible-playbook backup/files-push.yml -e site=example.com -e env=staging
```

**See also:** [backup/README.md](backup/README.md) for detailed documentation.

---

## 2. Server Monitoring

**Location:** `monitoring/`

Ansible playbooks for Nginx log analysis, traffic monitoring, and security threat detection.

### Features

- **Traffic Analysis**
  - Top requested pages (excluding bots)
  - Unique visitor counts
  - Traffic distribution by hour
  - User agent analysis
  - Response time statistics
  - Bandwidth usage

- **Security Monitoring**
  - DoS/DDoS detection (high request rates)
  - WordPress attack patterns (wp-login.php, xmlrpc.php brute force)
  - SQL injection attempts
  - Directory traversal attempts
  - Scanner detection (404 patterns)
  - Suspicious user agents
  - Referrer spam detection

- **Integration**
  - Works with Trellis per-site logs: `/srv/www/{site}/logs/access.log`
  - Complements external updown.io monitoring
  - Email alerts for security threats

### Available Playbooks

| Playbook | Purpose |
|----------|---------|
| `quick-status.yml` | One-minute server health check |
| `traffic-report.yml` | Generate traffic analysis reports |
| `security-scan.yml` | Detect attack patterns and threats |
| `setup-monitoring.yml` | Automated monitoring setup with cron |

### Usage Examples

```bash
# Quick server status check
ansible-playbook monitoring/quick-status.yml -e site=example.com -e env=production

# Traffic report for last 6 hours
ansible-playbook monitoring/traffic-report.yml -e site=example.com -e env=production -e hours=6

# Security scan with email alerts
ansible-playbook monitoring/security-scan.yml -e site=example.com -e env=production -e alert_email=admin@example.com

# Setup automated monitoring
ansible-playbook monitoring/setup-monitoring.yml -e site=example.com -e env=production
```

**See also:**
- [monitoring/README.md](monitoring/README.md) - Comprehensive monitoring documentation
- [monitoring/QUICK-REFERENCE.md](monitoring/QUICK-REFERENCE.md) - Command reference

---

## 3. Security

**Location:** `security/`

WordPress security protection through fail2ban automatic IP blocking and manual Nginx deny rules.

### Features

- **fail2ban Integration (Recommended)**
  - Automatic IP blocking after brute force attempts
  - Temporary bans (default: 10 minutes)
  - WordPress wp-login.php protection
  - XML-RPC abuse protection (optional)
  - Zero maintenance required

- **Manual IP Blocking (Advanced)**
  - Permanent Nginx-level IP blocks
  - Version-controlled deny lists
  - For extreme high-volume attacks
  - Works alongside fail2ban

- **Security Monitoring**
  - View banned IPs and attack patterns
  - Analyze WordPress login attempts
  - fail2ban log monitoring
  - Integration with malware scanners

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | Security overview and quick reference |
| `FAIL2BAN.md` | fail2ban setup, configuration, and monitoring |
| `MANUAL-IP-BLOCKING.md` | Permanent Nginx IP blocks for extreme cases |

### Quick Start

**Enable fail2ban WordPress protection:**

```bash
# 1. Edit trellis/group_vars/all/security.yml
# Set wordpress_wp_login enabled: "true"

# 2. Apply configuration
cd trellis
trellis provision --tags fail2ban production
```

**Monitor security activity:**

```bash
# Check fail2ban status
ssh admin_user@yoursite.com "sudo fail2ban-client status wordpress_wp_login"

# View recent bans
ssh admin_user@yoursite.com "sudo tail -50 /var/log/fail2ban.log"

# Analyze attack patterns
ssh web@yoursite.com "grep 'POST.*wp-login' /srv/www/yoursite.com/logs/access.log | awk '{print \$1}' | sort | uniq -c | sort -rn | head -20"
```

### Real-World Impact

**Before fail2ban** (November-December 2025):
- 1,420 wp-login attempts from single IP
- 860 attempts from another IP
- 742 attempts from third IP
- 40+ unique attacker IPs
- No automatic blocking

**After fail2ban enabled** (2026-01-01):
- Attackers blocked after 6 failed attempts
- 10-minute bans deter most attacks
- Zero maintenance required

**See also:**
- [security/README.md](security/README.md) - Complete security guide
- [security/FAIL2BAN.md](security/FAIL2BAN.md) - Automatic IP blocking setup
- [security/MANUAL-IP-BLOCKING.md](security/MANUAL-IP-BLOCKING.md) - Manual IP blocks
- [wp-cli/security](../wp-cli/security/) - Malware detection scanners

---

## 4. Provisioning & Setup

**Location:** `provision/`

Documentation and guides for server provisioning, configuration, and WordPress cron management.

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | Quick provisioning command reference |
| `CRON.md` | WordPress cron system configuration |
| `NEW-MACHINE.md` | New server setup guide |
| `PROJECT-SETUP.md` | Initial project setup guide |

### Key Topics

**Provisioning Commands**
- Development environment setup
- Staging/production deployment
- PHP version upgrades with correct tags
- Nginx configuration updates

**WordPress Cron Configuration**
- WP-Cron vs system cron
- Trellis default: system cron every 15 minutes
- Multisite cron configuration
- Verification and troubleshooting

**PHP Version Upgrades**

When upgrading PHP, **must** include these tags:

```bash
trellis provision --tags php,nginx,wordpress-setup,users,memcached production
```

Critical tags:
- `php` - Installs new version
- `nginx` - Updates PHP-FPM socket configuration
- `wordpress-setup` - Creates PHP version-specific pool configuration
- `users` - **Critical**: Updates sudoers for PHP-FPM reload (deployments fail without this)
- `memcached` - Installs version-specific memcached extension

**See also:** [provision/README.md](provision/README.md) and subdirectory documentation.

---

## 5. Trellis Updater

**Location:** `updater/`

Safe Trellis version upgrades while preserving custom configurations and sensitive data.

### Features

- **Automated Upgrade Process**
  1. Creates full backup of current Trellis directory → `~/trellis-backup/`
  2. Clones fresh Trellis to temporary directory → `~/trellis-temp/`
  3. Generates diff of changes → `~/trellis-diff/changes.txt`
  4. Updates files using rsync with explicit exclusions
  5. Verifies critical files were preserved
  6. Cleans up temporary files

- **What It Preserves (23+ exclusions)**
  - **Secrets:** `.vault_pass`, `ansible.cfg`, `vault.yml` files (all environments)
  - **Git/CI:** `.git/`, `.github/`, `.trellis/`
  - **Site Config:** `wordpress_sites.yml`, `users.yml`, `hosts/` directories
  - **Custom Settings:** `main.yml` files (PHP memory, timezone, pools), `mail.yml` (SMTP)
  - **Deploy Hooks:** `deploy-hooks/` directory
  - **CLI Config:** `trellis.cli.yml`

### Usage

```bash
# Edit script to set PROJECT="site.com"
cd /path/to/trellis
chmod +x ../wp-ops/trellis/updater/trellis-updater.sh
../wp-ops/trellis/updater/trellis-updater.sh

# Review changes
cat ~/trellis-diff/changes.txt

# Commit if satisfied
git add -A
git commit -m "Update Trellis to latest version"
```

**See also:**
- [updater/README.md](updater/README.md) - Complete updater documentation
- [updater/manual-update.md](updater/manual-update.md) - Manual update instructions

---

## Architecture Patterns

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

---

## Important Considerations

### Trellis Configuration

- Site names in Ansible commands must match keys in `group_vars/*/wordpress_sites.yml`
- The `local_path` variable defines where the Bedrock site is located
- Environment-specific vault files contain sensitive credentials

### Testing Operations

Before running operations on production:

1. Test on development environment first
2. Verify backup file creation and location
3. For pull/push operations, verify URL replacement is correct
4. Always check disk space before creating backups

### Security

- Backup files contain sensitive data - ensure proper permissions (750 or 700)
- Database vault passwords are required for remote operations
- Monitor backup script execution and access to backup files

---

## Troubleshooting

### Common Issues

1. **Variable errors**: Ensure `-e site=example.com -e env=production` parameters are provided
2. **Permission denied**: Check SSH keys and Trellis `users.yml` configuration
3. **Disk space**: Monitor available space before running backups
4. **Database connection**: Verify database credentials in vault files
5. **WP-CLI errors**: Ensure playbook is targeting correct WordPress directory

### Testing Backups

Always test your backups by:

1. Attempting restoration on a test environment
2. Verifying file integrity of compressed archives
3. Testing database imports for corruption
4. Checking backup file sizes for consistency

---

## Best Practices

1. **Regular testing**: Test backup restoration procedures monthly
2. **Multiple locations**: Store backups in multiple locations (local + remote)
3. **Version control**: Keep custom playbooks and configurations in version control
4. **Documentation**: Document site-specific procedures and schedules
5. **Monitoring**: Set up alerts for backup failures and security threats
6. **Retention policy**: Implement appropriate backup retention policies (30 days default)

---

## Integration Notes

These tools are designed to work alongside Trellis's built-in functionality:

- **Backup playbooks** complement Trellis deployment for database/file synchronization
- **Monitoring playbooks** provide server-side analysis alongside external monitoring (updown.io)
- **Provisioning guides** document Trellis-specific configuration patterns
- **Updater script** safely upgrades Trellis while preserving customizations

All tools follow Trellis conventions for directory structure, user permissions, and environment configuration.
