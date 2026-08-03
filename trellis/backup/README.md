# Trellis Backup Integration

Ansible playbooks for automated database backup, synchronization, and management across Trellis environments.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
  - [Database Backup](#database-backup)
  - [Database Pull](#database-pull)
    - [Alternative: Direct Shell Script Method](#alternative-direct-shell-script-method)
  - [Database Push](#database-push)
  - [Files Backup](#files-backup)
  - [Files Pull](#files-pull)
  - [Files Push](#files-push)
- [Configuration](#configuration)
  - [Site Configuration](#site-configuration)
  - [Backup Directory Structure](#backup-directory-structure)
- [File Naming Convention](#file-naming-convention)
- [Compression Methods](#compression-methods)
- [URL Search and Replace](#url-search-and-replace)
- [Security Considerations](#security-considerations)
- [Error Handling](#error-handling)
- [Automation](#automation)
  - [Scheduled Backups](#scheduled-backups)
  - [Cleanup Script](#cleanup-script)
- [Integration with CI/CD](#integration-with-cicd)
- [Troubleshooting](#troubleshooting)
  - [Debug Mode](#debug-mode)
  - [Manual Verification](#manual-verification)
  - [Log Monitoring](#log-monitoring)
- [Best Practices](#best-practices)
- [Support](#support)

## Overview

This directory contains Ansible playbooks that integrate with your existing Trellis setup to provide automated database and files operations:

### Database Operations
- **database-backup.yml** - Create database backups from any environment
- **database-pull.yml** - Pull database from remote environment to development
- **database-push.yml** - Push database from development to remote environment

### Files Operations
- **files-backup.yml** - Create WordPress uploads backups from any environment
- **files-pull.yml** - Pull WordPress uploads from remote environment to development
- **files-push.yml** - Push WordPress uploads from development to remote environment

## Prerequisites

- Working Trellis installation with configured environments
- Ansible installed and configured
- SSH access to all target environments
- WP-CLI available on all servers (included with Trellis)

## Installation

1. Copy the playbook files to your Trellis directory:
   ```bash
   # From your trellis-tools directory
   cp -r backup/trellis/* /path/to/your/trellis/
   ```

2. Or reference them directly from this repository:
   ```bash
   # Run from your Trellis directory
   ansible-playbook /path/to/trellis-tools/backup/trellis/database-backup.yml -e site=example.com -e env=production
   ```

## Usage

All playbooks require two variables:
- `site` - The site name as defined in your Trellis configuration
- `env` - The environment (development, staging, production)

**Via wp-ops:** these playbooks are also runnable through the [`wp-ops`](../../README.md) CLI (`wp-ops trellis --help` to list them), e.g. `wp-ops trellis database-backup -e site=example.com -e env=production`. Requires `TRELLIS_DIR` set to your Trellis project — see [trellis/README.md](../README.md#via-the-wp-ops-cli).

### Database Backup

Creates a compressed database backup and stores it in the `database_backup` directory.

```bash
# Backup production database
ansible-playbook database-backup.yml -e site=example.com -e env=production

# Backup staging database
ansible-playbook database-backup.yml -e site=example.com -e env=staging

# Backup development database
ansible-playbook database-backup.yml -e site=example.com -e env=development
```

**What it does:**
- Creates timestamped compressed SQL backup
- For remote environments: downloads backup to development server
- Stores backup in `web/app/database_backup/` directory
- Automatically cleans up temporary files

### Database Pull

Pulls database from a remote environment to development with automatic URL replacement.

```bash
# Pull production database to development
ansible-playbook database-pull.yml -e site=example.com -e env=production

# Pull staging database to development
ansible-playbook database-pull.yml -e site=example.com -e env=staging
```

**What it does:**
- Creates backup of current development database
- Exports database from remote environment
- Downloads and imports to development
- Performs URL search-replace for local development URLs
- Cleans up temporary files

**Note:** Cannot pull from development to development (will abort with error).

#### Alternative: Direct Shell Script Method

For interactive development work, you can use a direct shell script approach that runs inside the Trellis VM. This method is **simpler and faster** than the Ansible playbook, using SSH pipes to stream the database directly without intermediate files.

**Prefer [`scripts/backup/db-pull.sh`](../../scripts/backup/db-pull.sh)** (`wp-ops db-pull example.com production`) over hand-copying the inline command below — it's this same approach, generalized: it reads the production and development URLs at run time via WP-CLI instead of hardcoding them, backs up the current development database first, prompts for confirmation (`--yes` to skip), and supports multisite via `--multisite`. The raw steps are kept below for reference and for cases where you want to run/adapt them by hand.

**Standard site example:**

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.com/current -- bash -c "
echo '=== Backing up current development database ==='
wp db export /tmp/dev_backup_\$(date +%Y%m%d_%H%M%S).sql.gz --path=web/wp

echo ''
echo '=== Pulling production database dump ==='
ssh -o StrictHostKeyChecking=no web@example.com 'cd /srv/www/example.com/current && wp db export - --path=web/wp' | gzip > /tmp/prod_import.sql.gz

echo ''
echo '=== Importing production database to development ==='
gunzip < /tmp/prod_import.sql.gz | wp db import - --path=web/wp

echo ''
echo '=== Running search-replace for URLs ==='
wp search-replace 'https://example.com' 'https://example.test' --all-tables --precise --path=web/wp

echo ''
echo '=== Flushing cache ==='
wp cache flush --path=web/wp

echo ''
echo '=== Database pull complete! ==='
"
```

**Multisite example:**

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.com/current -- bash -c "
echo '=== Backing up current development database ==='
wp db export /tmp/dev_backup_\$(date +%Y%m%d_%H%M%S).sql.gz --path=web/wp

echo ''
echo '=== Pulling production database dump ==='
ssh -o StrictHostKeyChecking=no web@example.com 'cd /srv/www/example.com/current && wp db export - --path=web/wp' | gzip > /tmp/prod_import.sql.gz

echo ''
echo '=== Importing production database to development ==='
gunzip < /tmp/prod_import.sql.gz | wp db import - --path=web/wp

echo ''
echo '=== Running search-replace for URLs (multisite) ==='
wp search-replace 'https://example.com' 'http://example.test' --all-tables --precise --path=web/wp --url=https://example.com

echo ''
echo '=== Fixing multisite blog domains ==='
wp db query \"UPDATE wp_blogs SET domain = REPLACE(domain, 'example.com', 'example.test');\" --path=web/wp

echo ''
echo '=== Flushing cache ==='
wp cache flush --path=web/wp

echo ''
echo '=== Database pull complete! ==='
"
```

**Advantages of this approach:**
- Single command execution with full visibility
- Streams database via SSH pipe (no intermediate transfer files)
- Includes cache flushing step
- Progress messages show exactly what's happening
- Faster than Ansible playbook for quick manual operations

**When to use:**
- Manual, interactive development work
- Quick database syncs during active development
- When you want full visibility into each step
- Testing or troubleshooting database operations

**When to use Ansible playbooks instead:**
- Automated/scheduled operations
- CI/CD pipelines
- When you need consistent, repeatable automation
- Managing multiple sites or environments

**Multisite notes:**
- Include `--url=https://example.com` parameter in `wp search-replace`
- This ensures WordPress knows which site context to use for the search-replace operation
- **Critical**: Must update `wp_blogs` table domains separately with direct SQL query
- The `wp_blogs` table stores the domain for each site in the network
- Use `wp db query "UPDATE wp_blogs SET domain = REPLACE(domain, 'production.com', 'local.test');"` to update all blog domains
- Both `wp search-replace` (for content/options) and `wp_blogs` update (for network domains) are required for proper multisite operation

### Practical Example: HTTPS Migration for Theme Assets Across Multiple Subsites

When migrating a multisite from HTTP to HTTPS, you may need to update hardcoded theme asset URLs. This practical example shows the replacement of HTTP theme paths across multiple subsites:

```bash
# ALWAYS run dry-run first to preview changes
wp search-replace 'http://example.com/app/themes' 'https://example.com/app/themes' \
  --all-tables \
  --precise \
  --url=https://example.com/spa \
  --path=web/wp \
  --dry-run \
  --report-changed-only

# If dry-run output looks correct, execute the actual replacement
wp search-replace 'http://example.com/app/themes' 'https://example.com/app/themes' \
  --all-tables \
  --precise \
  --url=https://example.com/spa \
  --path=web/wp \
  --report-changed-only
```

**Expected output shows replacements across main site and subsites:**
```
+-------------+--------------+--------------+------+
| Table       | Column       | Replacements | Type |
+-------------+--------------+--------------+------+
| wp_10_posts | post_content | 8            | PHP  |
| wp_2_posts  | post_content | 10           | PHP  |
| wp_5_posts  | post_content | 13           | PHP  |
| wp_6_posts  | post_content | 10           | PHP  |
| wp_8_posts  | post_content | 11           | PHP  |
| wp_9_posts  | post_content | 4            | PHP  |
| wp_posts    | post_content | 25           | PHP  |
+-------------+--------------+--------------+------+
Success: Made 81 replacements.
```

This command will:
- Search across all tables (`--all-tables`)
- Only replace exact matches (`--precise`)
- Target the multisite context (`--url=...`)
- Show a detailed report of changes (`--report-changed-only`)

> **Critical:** Even when specifying `--url=`, WP-CLI may find matches across multiple subsites if the search string exists in their content. Always use `--dry-run` first!

### Database Push

Pushes database from development to a remote environment with URL replacement.

```bash
# Push development database to staging
ansible-playbook database-push.yml -e site=example.com -e env=staging

# Push development database to production (use with caution!)
ansible-playbook database-push.yml -e site=example.com -e env=production
```

**What it does:**
- Creates backup of target environment database
- Exports development database
- Uploads and imports to target environment
- Performs URL search-replace for target environment URLs
- Cleans up temporary files

**Note:** Cannot push from development to development (will abort with error).

### Files Backup

Creates a compressed backup of WordPress uploads directory and stores it in the `files_backup` directory.

```bash
# Backup production uploads
ansible-playbook files-backup.yml -e site=example.com -e env=production

# Backup staging uploads
ansible-playbook files-backup.yml -e site=example.com -e env=staging

# Backup development uploads
ansible-playbook files-backup.yml -e site=example.com -e env=development
```

**What it does:**
- Creates timestamped compressed uploads backup
- For remote environments: downloads backup to development server
- Stores backup in `web/app/files_backup/` directory
- Automatically cleans up temporary files

### Files Pull

Pulls WordPress uploads from a remote environment to development.

```bash
# Pull production uploads to development
ansible-playbook files-pull.yml -e site=example.com -e env=production

# Pull staging uploads to development
ansible-playbook files-pull.yml -e site=example.com -e env=staging
```

**What it does:**
- Creates backup of current development uploads
- Creates archive of uploads from remote environment
- Downloads and extracts to development
- Cleans up temporary files

**Note:** Cannot pull from development to development (will abort with error).

### Files Push

Pushes WordPress uploads from development to a remote environment.

```bash
# Push development uploads to staging
ansible-playbook files-push.yml -e site=example.com -e env=staging

# Push development uploads to production (use with caution!)
ansible-playbook files-push.yml -e site=example.com -e env=production
```

**What it does:**
- Creates backup of target environment uploads
- Creates archive of development uploads
- Uploads and extracts to target environment
- Cleans up temporary files

**Note:** Cannot push from development to development (will abort with error).

## Configuration

### Site Configuration

Ensure your site is properly configured in your Trellis `group_vars` files:

```yaml
# group_vars/development/wordpress_sites.yml
wordpress_sites:
  example.com:
    site_hosts:
      - canonical: example.test
    local_path: ../site # Path to your Bedrock installation
    # ... other configuration
```

```yaml
# group_vars/production/wordpress_sites.yml
wordpress_sites:
  example.com:
    site_hosts:
      - canonical: example.com
    # ... other configuration
```

### Backup Directory Structure

Backups are stored in the following structure:
```
site/current/web/app/
├── database_backup/
│   ├── example_com_production_2023_12_01_14_30_45.sql.gz
│   ├── example_com_staging_2023_12_01_15_15_22.sql.gz
│   └── example_com_development_2023_12_01_16_45_33.sql.gz
└── files_backup/
    ├── example_com_production_uploads_2023_12_01_14_30_45.tar.gz
    ├── example_com_staging_uploads_2023_12_01_15_15_22.tar.gz
    └── example_com_development_uploads_2023_12_01_16_45_33.tar.gz
```

## File Naming Convention

Backup files use the following naming patterns:

### Database Backups
```
{site_name}_{environment}_{date}_{time}.sql.gz
```

### Files Backups
```
{site_name}_{environment}_uploads_{date}_{time}.tar.gz
```

Where:
- `site_name` - Site name with dots replaced by underscores
- `environment` - development, staging, or production
- `date` - YYYY_MM_DD format
- `time` - HH_MM_SS format

Examples:
- `example_com_production_2023_12_01_14_30_45.sql.gz`
- `example_com_production_uploads_2023_12_01_14_30_45.tar.gz`
- `mysite_co_uk_staging_2023_12_01_15_15_22.sql.gz`
- `mysite_co_uk_staging_uploads_2023_12_01_15_15_22.tar.gz`

## Compression Methods

Different compression methods are used based on backup type for optimal performance:

- **Database backups: `.sql.gz`** - Uses `gzip` compression for single SQL files. Faster with direct piping (`wp db export - | gzip`) without temporary files.
- **Files backups: `.tar.gz`** - Uses `tar` + `gzip` for directory archives. Required for preserving directory structure and handling multiple files efficiently.

## URL Search and Replace

The playbooks automatically handle URL replacement when moving databases between environments:

### Pull Operations
- **From Production**: `https://example.com` → `http://example.test`
- **From Staging**: `https://staging.example.com` → `http://example.test`

### Push Operations
- **To Production**: `http://example.test` → `https://example.com`
- **To Staging**: `http://example.test` → `https://staging.example.com`

URLs are determined from your Trellis site configuration using the `canonical` hostname.

## Security Considerations

1. **Backup Storage**: Backups contain sensitive data. Ensure proper file permissions on backup directories.

2. **Production Pushes**: Be extremely cautious when pushing to production. Always test on staging first.

3. **Database Credentials**: All database operations use WP-CLI, which reads credentials from WordPress configuration.

4. **SSH Access**: Ensure SSH keys are properly configured for all target environments.

## Error Handling

### Common Errors and Solutions

**"Site folder doesn't exist"**
- Verify the site name matches your Trellis configuration
- Check that the site has been deployed to the target environment

**"Cannot pull/push from development to development"**
- These operations are blocked by design
- Use `database-backup.yml` for development backups

**"WP-CLI command failed"**
- Verify WordPress is properly installed
- Check database connectivity
- Ensure WP-CLI is available on the server

**Permission denied errors**
- Verify SSH access to target servers
- Check file permissions in WordPress directories

## Automation

### Scheduled Backups

Add to your server's crontab for automated backups:

```bash
# Daily production backup at 2 AM
0 2 * * * cd /path/to/trellis && ansible-playbook database-backup.yml -e site=example.com -e env=production

# Weekly staging backup on Sundays at 3 AM
0 3 * * 0 cd /path/to/trellis && ansible-playbook database-backup.yml -e site=example.com -e env=staging
```

### Cleanup Script

Create a cleanup script to manage old backups:

```bash
#!/bin/bash
# cleanup-backups.sh

SITE_PATH="/srv/www/example.com/current/web/app"
RETENTION_DAYS=30

# Clean up old database backups
find "$SITE_PATH/database_backup" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

# Clean up old files backups
find "$SITE_PATH/files_backup" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Database Sync
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Source environment'
        required: true
        default: 'production'
        type: choice
        options:
        - production
        - staging

jobs:
  sync-database:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup SSH
        uses: webfactory/ssh-agent@v0.7.0
        with:
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}

      - name: Pull database
        run: |
          cd trellis
          ansible-playbook database-pull.yml -e site=example.com -e env=${{ github.event.inputs.environment }}
```

## Troubleshooting

### Debug Mode

Run playbooks with verbose output for debugging:

```bash
ansible-playbook database-backup.yml -e site=example.com -e env=production -vvv
```

### Manual Verification

Verify backup integrity:

```bash
# Test database backup file
gunzip -t /path/to/backup.sql.gz

# Check database backup contents
gunzip -c /path/to/backup.sql.gz | head -20

# Test files backup file
tar -tzf /path/to/uploads.tar.gz

# Check files backup contents
tar -xzOf /path/to/uploads.tar.gz | head -20
```

### Log Monitoring

Monitor backup operations:

```bash
# Check Ansible logs
tail -f /var/log/ansible.log

# Check WordPress logs
tail -f /srv/www/example.com/shared/logs/error.log
```

## Best Practices

1. **Test First**: Always test pull/push operations on staging before production
2. **Backup Before Push**: The playbooks automatically create backups, but verify they complete successfully
3. **Monitor Disk Space**: Regular backups can consume significant disk space
4. **Document Procedures**: Keep a record of when and why database operations are performed
5. **Verify URLs**: Check that URL replacements work correctly after pull/push operations
6. **Regular Cleanup**: Implement automated cleanup of old backup files

## Support

For issues specific to these playbooks:
1. Check the Ansible output for specific error messages
2. Verify your Trellis configuration is correct
3. Test SSH connectivity to target servers
4. Ensure WP-CLI is working on all environments

For general Trellis support, refer to the [official Trellis documentation](https://roots.io/trellis/docs/).