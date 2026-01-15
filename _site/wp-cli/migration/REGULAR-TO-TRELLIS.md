# Migrating from Regular WordPress to Trellis with Bedrock

This guide covers the complete process of migrating a **single WordPress site** from standard hosting (shared hosting, Plesk, cPanel, etc.) to a [Roots Trellis](https://roots.io/trellis/) server running [Bedrock](https://roots.io/bedrock/). This is particularly useful when you need to modernize your WordPress infrastructure while maintaining a non-Sage theme.

> **Migrating multiple sites?** See the [Multi-Site Migration Guide](MULTI-SITE-MIGRATION.md) for strategies on migrating 2+ sites to a single Trellis server, including time-saving tips and batch operations.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Migration Approaches](#migration-approaches)
- [Choosing Your Migration Workflow](#choosing-your-migration-workflow)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Quick Migration Checklist (Per Site)](#quick-migration-checklist-per-site)
- [Step-by-Step Migration Process](#step-by-step-migration-process)
  - [Migration Workflow Overview](#migration-workflow-overview)
  - [1. Set Up Trellis and Bedrock Locally](#1-set-up-trellis-and-bedrock-locally)
  - [2. Provision Your Server](#2-provision-your-server)
  - [3. Prepare Your Existing WordPress Site](#3-prepare-your-existing-wordpress-site)
  - [4. Transfer Theme and Plugins to Local Bedrock](#4-transfer-theme-and-plugins-to-local-bedrock)
  - [5. Deploy Bedrock to Server](#5-deploy-bedrock-to-server)
  - [6. Migrate the Database](#6-migrate-the-database)
  - [7. Migrate Uploads](#7-migrate-uploads)
  - [Alternative: Using Automated Backup Playbooks](#alternative-using-automated-backup-playbooks-workflow-b)
  - [8. Choose Your Path Migration Strategy](#8-choose-your-path-migration-strategy)
  - [9. Test and Verify](#9-test-and-verify)
  - [10. Test with /etc/hosts Before DNS Cutover](#10-test-with-etchosts-before-dns-cutover)
  - [WordPress Cron: System Cron vs WP-Cron](#wordpress-cron-system-cron-vs-wp-cron)
  - [11. DNS and Go-Live](#11-dns-and-go-live)
- [Troubleshooting](#troubleshooting)
- [Post-Migration Optimization](#post-migration-optimization)

## Overview

Bedrock restructures WordPress directories from the traditional layout to a more modern, secure structure:

**Traditional WordPress:**
```
/
├── wp-admin/
├── wp-content/
│   ├── themes/
│   ├── plugins/
│   └── uploads/
├── wp-includes/
└── wp-config.php
```

**Bedrock Structure:**
```
/
├── web/
│   ├── app/
│   │   ├── themes/
│   │   ├── plugins/
│   │   ├── uploads/
│   │   └── mu-plugins/
│   ├── wp/              # WordPress core (subdirectory)
│   └── wp-config.php
├── config/
│   └── application.php
└── composer.json
```

## Prerequisites

- SSH access to your destination server (or a fresh server to provision)
- Root or sudo access for Trellis provisioning
- **Trellis CLI** installed (see installation below)
- Ansible installed locally (Trellis CLI will prompt if needed)
- WP-CLI installed on destination server (Trellis installs this automatically)
- Database backup of your existing site
- Download of your existing site's files (themes, plugins, uploads)
- Git repository for your project (GitHub, GitLab, Bitbucket, etc.)

## Migration Approaches

You have two main approaches for handling file paths:

### Approach A: Full Bedrock Adoption (Recommended)
Convert all database paths to Bedrock structure (`/app/uploads/`, `/app/themes/`). This is the cleanest approach and fully embraces Bedrock conventions.

**Pros:**
- Full compatibility with Bedrock ecosystem
- Cleaner, more maintainable structure
- Better for long-term maintenance

**Cons:**
- Requires database search-replace operations
- More steps in initial migration

### Approach B: Path Compatibility Mode
Keep using `/wp-content/uploads/` paths in the database by modifying Bedrock's configuration.

**Pros:**
- Minimal database changes
- Faster initial migration
- Useful if you need to maintain compatibility with legacy systems

**Cons:**
- Goes against Bedrock conventions
- May cause confusion for other developers
- Could complicate future updates

## Choosing Your Migration Workflow

You have two primary workflows for migrating your site(s), depending on whether you want to test locally first or migrate directly to production.

### Workflow A: Direct Server-to-Server Migration
**Best for:** Sites currently on shared hosting without local dev environment, or when you need to go live quickly.

**Process:**
1. Set up Trellis and Bedrock locally (Steps 1-2)
2. Deploy empty Bedrock to server (Step 5)
3. **Manually** transfer database and files from old hosting to new server (Steps 6-7)
4. Apply path conversions (Step 8)
5. Test and go live (Steps 9-10)

**Time per site:** 3-4 hours (first site), 2-3 hours (additional sites)

**Pros:**
- Fewer steps overall
- No need to set up local development environment
- Direct migration from old to new hosting

**Cons:**
- Less opportunity to test before going live
- Manual file transfers can be error-prone
- Harder to repeat if something goes wrong

### Workflow B: Local-First Migration (Recommended)
**Best for:** When you want to test locally before going live, or when managing multiple sites.

**Process:**
1. Set up Trellis and Bedrock locally (Steps 1-2)
2. Start local development environment (`trellis vm start`)
3. Import database and files to local environment
4. Test everything locally at `https://example.test`
5. Provision production server (Step 2)
6. **Use automated backup playbooks** to push from local to production
7. Test production and go live

**Time per site:** 4-5 hours (first site), 2.5-3.5 hours (additional sites)

**Pros:**
- Test thoroughly before going live
- Repeatable, automated process using playbooks
- Safer - production remains untouched until ready
- Easy to iterate if issues are found

**Cons:**
- Requires local development setup
- Additional step to transfer data twice (old → local → production)
- Requires Vagrant/VirtualBox for local VM

**Recommended for:** Three-site migration projects where consistency and testing are important.

## Pre-Migration Checklist

Before starting the migration:

- [ ] **Backup everything** from your current site
  - Database export (`.sql` or `.sql.gz`)
  - Complete file backup (themes, plugins, uploads)
  - Copy of `wp-config.php` for reference
- [ ] Document all active plugins and their versions
- [ ] Note any custom configurations or constants in `wp-config.php`
- [ ] Identify any hardcoded URLs in theme files
- [ ] Check for any symlinks or special file permissions
- [ ] Verify PHP version compatibility (source vs. destination)
- [ ] Test your site backup locally if possible

## Quick Migration Checklist (Per Site)

Use this condensed checklist to track progress for each site during migration.

### Pre-Migration (15-30 mins)
- [ ] Download database backup (`.sql` or `.sql.gz`)
- [ ] Download files (themes, plugins, uploads)
- [ ] Document active plugins and versions
- [ ] Generate WordPress salts (https://roots.io/salts.html)
- [ ] Create Git repository on GitHub/GitLab
- [ ] Note any custom `wp-config.php` settings

### Trellis Setup (First Site: 60 mins, Additional: 15 mins)
- [ ] Create Bedrock installation with descriptive name (`site-example`)
- [ ] Configure `wordpress_sites.yml` for development and production
- [ ] Edit vault files with database credentials and salts
- [ ] Update `hosts/production` with server IP
- [ ] Provision server (first site only - run once for all sites)
- [ ] Commit Trellis configuration to Git

### Site Preparation (30 mins)
- [ ] Copy theme to `site/web/app/themes/`
- [ ] Copy plugins to `site/web/app/plugins/`
- [ ] Add plugins to `composer.json` where possible
- [ ] Run `composer install`
- [ ] Commit and push to Git repository

### Deployment (15 mins)
- [ ] Deploy to production: `trellis deploy production`
- [ ] Verify deployment created correct directory structure
- [ ] Check symlinks are correct

### Data Migration (45-60 mins)

**Option A: Manual Migration (Workflow A)**
- [ ] Import database via WP-CLI or MySQL
- [ ] Update domain URLs with search-replace
- [ ] rsync/scp uploads directory
- [ ] Set correct permissions on uploads
- [ ] Run path conversion search-replace commands

**Option B: Automated with Playbooks (Workflow B - Recommended)**
- [ ] Import database and uploads to local development
- [ ] Test locally at `https://example.test`
- [ ] Run `ansible-playbook database-push.yml`
- [ ] Run `ansible-playbook files-push.yml`
- [ ] Verify on production

### Path Conversion (15 mins)
- [ ] Run search-replace for `/wp-content/themes/` → `/app/themes/`
- [ ] Run search-replace for `/wp-content/uploads/` → `/app/uploads/`
- [ ] Run search-replace for `/wp-content/plugins/` → `/app/plugins/`
- [ ] Verify no remaining `wp-content` references
- [ ] Flush cache and permalinks

### Testing (30 mins)
- [ ] Verify homepage loads correctly
- [ ] Check all images display properly
- [ ] Test navigation menus
- [ ] Verify forms work
- [ ] Test admin panel access
- [ ] Check plugin functionality
- [ ] Test media upload
- [ ] Check browser console for errors

### Pre-DNS Testing with /etc/hosts (15 mins)
- [ ] Add server IP to local `/etc/hosts` file
- [ ] Flush local DNS cache
- [ ] Test site with production domain (via /etc/hosts)
- [ ] Verify all functionality works with real domain
- [ ] Fix any issues found during testing
- [ ] Re-enable SSL with `provider: letsencrypt` in wordpress_sites.yml
- [ ] Commit configuration changes
- [ ] Remove `/etc/hosts` entry when ready for DNS cutover

### Go-Live (20 mins)
- [ ] Lower DNS TTL 24 hours before migration
- [ ] Update DNS A record to new server IP
- [ ] Monitor DNS propagation (`dig example.com +short`)
- [ ] Wait for DNS to propagate (5-30 minutes typically)
- [ ] Run `trellis provision production --tags letsencrypt`
- [ ] Verify SSL certificate is valid (`sudo certbot certificates`)
- [ ] Test HTTPS in browser (no warnings)
- [ ] Test site from multiple locations
- [ ] Keep old server running 24-48 hours

### Post-Migration (15 mins)
- [ ] Set up automated backups
- [ ] Enable Redis caching
- [ ] Configure monitoring
- [ ] Document any issues encountered
- [ ] Update team documentation

**Total Time Estimates:**
- **First site:** 4-6 hours (includes learning curve and server setup)
- **Second site:** 2.5-3.5 hours (server already provisioned)
- **Third site:** 2-3 hours (process is familiar)

**For three sites: 8-12 hours total**

## Step-by-Step Migration Process

### Migration Workflow Overview

The migration process follows this sequence:

1. **Local Setup**: Set up Trellis and Bedrock locally
2. **Configure Environments**: Configure your server settings and site configuration
3. **Provision Server**: Provision your production/staging server (creates directory structure, installs software)
4. **Prepare Bedrock Site**: Add your theme and plugins to local Bedrock site
5. **Initial Deployment**: Deploy Bedrock to server (creates `/srv/www/example.com/` structure)
6. **Migrate Database**: Import and transform database on server
7. **Migrate Uploads**: Transfer uploads directory to server
8. **Path Migration**: Choose and implement path migration strategy
9. **Test & Verify**: Comprehensive testing
10. **Test with /etc/hosts**: Test site using local DNS before DNS cutover
11. **DNS & Go-Live**: Update DNS, get Let's Encrypt SSL, and go live

### 1. Set Up Trellis and Bedrock Locally

#### Install Trellis CLI

First, install the Trellis CLI if you haven't already:

```bash
# macOS (using Homebrew)
brew install roots/tap/trellis-cli

# Linux (using installation script)
curl -sL https://roots.io/trellis/cli/get | bash

# Verify installation
trellis --version
```

For other installation methods, see [Trellis CLI Installation](https://roots.io/trellis/docs/installation/).

#### Create New Trellis Project

The modern way to set up Trellis and Bedrock is using the Trellis CLI:

```bash
# Navigate to your projects directory
cd ~/code

# Create new project (this creates both Trellis and Bedrock)
trellis new example.com

# Navigate into the project
cd example.com
```

This command automatically:
- Creates the project directory
- Clones Trellis
- Clones Bedrock (in the `site/` directory)
- Installs Ansible Galaxy dependencies
- Initializes a Git repository
- Sets up basic configuration

#### Review and Configure Your Site

Now review and configure your site settings:

**1. Review development configuration:**

Edit `trellis/group_vars/development/wordpress_sites.yml` - this is already pre-configured for local development with `trellis vm`.

**2. Configure production environment:**

**Edit `trellis/group_vars/production/wordpress_sites.yml`:**

```yaml
wordpress_sites:
  example.com:
    site_hosts:
      - canonical: example.com
        redirects:
          - www.example.com
    local_path: ../site
    repo: git@github.com:yourusername/example.com.git  # Your Git repo URL
    repo_subtree_path: site
    branch: main  # Or master, depending on your Git setup
    multisite:
      enabled: false
    ssl:
      enabled: true
      provider: letsencrypt
    cache:
      enabled: true  # Enable FastCGI cache and Redis
```

**3. Configure production vault (encrypted secrets):**

Use Trellis CLI to edit the encrypted vault file:

```bash
# Edit production vault file
cd trellis
trellis vault edit production

# This opens the vault file in your default editor
# Update the WordPress salts and database password:
```

```yaml
vault_wordpress_sites:
  example.com:
    env:
      db_password: "generate_secure_password_here"
      # Generate salts at: https://roots.io/salts.html
      auth_key: "generateme"
      secure_auth_key: "generateme"
      logged_in_key: "generateme"
      nonce_key: "generateme"
      auth_salt: "generateme"
      secure_auth_salt: "generateme"
      logged_in_salt: "generateme"
      nonce_salt: "generateme"
```

**Important:** Generate WordPress salts at [https://roots.io/salts.html](https://roots.io/salts.html)

**4. Add your production server IP:**

Edit `trellis/hosts/production`:
```ini
[production]
your.server.ip.address

[web]
your.server.ip.address
```

**5. (Optional) Test locally first:**

Before provisioning production, you can test locally using Vagrant:

```bash
# Start local development VM
trellis vm start

# This provisions a local VM and deploys your site
# Access at: https://example.test
```

**6. Create Git repository and push:**

```bash
# From project root (example.com/)
cd ~/code/example.com

# Add all files (Git repo already initialized by trellis new)
git add .

# Initial commit
git commit -m "Initial Trellis and Bedrock setup"

# Create repository on GitHub/GitLab, then add remote
git remote add origin git@github.com:yourusername/example.com.git

# Push to remote
git push -u origin main
```

### 2. Provision Your Server

**IMPORTANT**: You must provision your server before deploying. This step installs all necessary software (Nginx, PHP, MariaDB, etc.) and creates the directory structure.

**Prerequisites for provisioning:**
- Fresh Ubuntu 22.04 or 24.04 server
- Root or sudo user access
- SSH key-based authentication set up

```bash
# From the trellis directory
cd ~/code/example.com/trellis

# Provision production server (this will take 10-15 minutes)
trellis provision production

# Alternative: Use ansible-playbook directly
# ansible-playbook server.yml -e env=production
```

This command will:
- Install and configure Nginx
- Install PHP and required extensions
- Install and configure MariaDB (MySQL)
- Create the directory structure at `/srv/www/example.com/`
- Set up SSL certificates with Let's Encrypt
- Configure Redis (if enabled)
- Set up proper user permissions

**Troubleshooting Provisioning:**

If provisioning fails, check:
```bash
# Verify SSH access to server (default user is usually 'root' or 'admin')
ssh root@your.server.ip.address

# Or if using a different user
ssh admin_user@your.server.ip.address

# Check Ansible can connect (from trellis directory)
cd ~/code/example.com/trellis
ansible production -m ping

# Verify server meets requirements (Ubuntu 22.04 or 24.04)
ssh root@your.server.ip.address "lsb_release -a"

# Check Ansible version (should be 2.10+)
ansible --version
```

For detailed provisioning commands and troubleshooting, see the [Provisioning Guide](../../trellis/provision/README.md).

### 3. Prepare Your Existing WordPress Site

On your current hosting:

```bash
# Export the database
wp db export backup.sql --add-drop-table

# Or if WP-CLI is not available, use phpMyAdmin or command line:
mysqldump -u username -p database_name > backup.sql

# Create a compressed archive of your files
tar -czf site-backup.tar.gz wp-content/

# Or download specific directories:
# themes, plugins, and uploads
```

### 4. Transfer Theme and Plugins to Local Bedrock

Copy your theme(s) and plugins to your **local** Bedrock directory structure:

```bash
# In your local Bedrock directory (site/)

# Copy theme (from your backup)
cp -r /path/to/backup/wp-content/themes/your-theme web/app/themes/

# Copy plugins (from your backup)
cp -r /path/to/backup/wp-content/plugins/* web/app/plugins/

# Note: Try to install plugins via Composer when possible
# Example: composer require wpackagist-plugin/plugin-name
```

**Update `site/composer.json`** to include plugins available via Composer:

```json
{
  "require": {
    "php": ">=8.0",
    "roots/bedrock": "^1.21",
    "wpackagist-plugin/wordpress-seo": "^22.0",
    "wpackagist-plugin/wordfence": "^7.11"
  }
}
```

Run `composer install` to install plugins via Composer.

**Commit your changes to Git:**

```bash
# In your project root (not trellis directory)
cd /path/to/example.com

# Initialize git if not already done
git init

# Add site directory
git add site/

# Commit
git commit -m "Initial Bedrock setup with theme and plugins"

# Add remote (create repo on GitHub/GitLab first)
git remote add origin git@github.com:yourusername/example.com.git

# Push to remote
git push -u origin main
```

### 5. Deploy Bedrock to Server

Now deploy your Bedrock site to the provisioned server. This creates the directory structure and symlinks.

**Important for Multiple Sites:** If you're adding a second or third site to an already-provisioned server, you must **re-provision first** to create the new site's infrastructure (database, Nginx configuration, SSL certificate, and directory structure):

```bash
# From trellis directory
cd trellis

# FIRST: Re-provision if adding a new site to existing server
# This creates database, Nginx config, SSL cert for the new site
trellis provision production

# THEN: Deploy the site
trellis deploy production
```

**For the first site only** (server not yet provisioned), you can skip directly to deploy since you already provisioned in Step 2.

**What deployment does:**

This will:
- Clone your Git repository to `/srv/www/example.com/releases/TIMESTAMP/`
- Run `composer install` to install WordPress core and plugins
- Create symlinks:
  - `/srv/www/example.com/current` → latest release
  - `/srv/www/example.com/current/web/app/uploads` → `/srv/www/example.com/shared/uploads`
- Create `.env` file with database credentials
- Set proper permissions

**Verify deployment:**

```bash
# SSH into server
ssh admin_user@your.server.ip.address

# Check directory structure was created
ls -la /srv/www/example.com/
# Should show: current, releases, shared

# Check current symlink
ls -la /srv/www/example.com/current
# Should point to latest release

# Check uploads symlink
ls -la /srv/www/example.com/current/web/app/
# Should show: uploads -> ../../../shared/uploads
```

At this point, if you visit your domain (assuming DNS is pointed), you'll see the WordPress installation screen. **Don't run it yet** - we need to import your database first.

### 6. Migrate the Database

#### Option A: Using WP-CLI (Recommended)

On your source site, export the database:

```bash
# On source server or via SSH
wp db export source-backup.sql --add-drop-table
```

Import to your Trellis/Bedrock environment:

```bash
# SSH into your Trellis server
cd /srv/www/example.com/current

# Import the database
wp db import /path/to/source-backup.sql

# Update the site URL if domain is changing
wp search-replace 'http://old-domain.com' 'https://example.com' --dry-run
wp search-replace 'http://old-domain.com' 'https://example.com'

# Also replace without protocol
wp search-replace 'old-domain.com' 'example.com'
```

#### Option B: Manual Import

```bash
# Copy database dump to server
scp backup.sql admin_user@your.server.ip.address:/tmp/

# SSH into server
ssh admin_user@your.server.ip.address

# Import database (get credentials from .env file)
cd /srv/www/example.com/current
cat .env | grep DB_

# Import
mysql -u db_user -p database_name < /tmp/backup.sql

# Clean up
rm /tmp/backup.sql
```

### 7. Migrate Uploads

Transfer your uploads directory to the server's **shared** uploads directory. You have several options:

#### Option A: Using rsync (Recommended)

Best for large uploads directories - resumable and preserves permissions:

```bash
# From your local machine
rsync -avz --progress /path/to/backup/wp-content/uploads/ \
  admin_user@your.server.ip.address:/srv/www/example.com/shared/uploads/

# Set correct permissions on server
ssh admin_user@your.server.ip.address \
  "sudo chown -R web:www-data /srv/www/example.com/shared/uploads && \
   sudo chmod -R 775 /srv/www/example.com/shared/uploads"
```

#### Option B: Using SCP

For smaller uploads directories:

```bash
# From your local machine
scp -r /path/to/backup/wp-content/uploads/* \
  admin_user@your.server.ip.address:/tmp/uploads/

# SSH into server and move to correct location
ssh admin_user@your.server.ip.address

# Move uploads and set permissions
sudo mv /tmp/uploads/* /srv/www/example.com/shared/uploads/
sudo chown -R web:www-data /srv/www/example.com/shared/uploads
sudo chmod -R 775 /srv/www/example.com/shared/uploads
```

#### Option C: Using Trellis Backup Tools

If you want to use this repository's backup tools for ongoing sync:

```bash
# First, manually copy uploads using rsync or scp (Option A or B above)
# Then set up automated sync using the backup playbooks

# See: ../../trellis/backup/README.md for details
ansible-playbook backup/trellis/files-pull.yml -e site=example.com -e env=production
```

**Verify uploads are accessible:**

```bash
# SSH into server
ssh admin_user@your.server.ip.address

# Check uploads directory
ls -la /srv/www/example.com/shared/uploads/

# Verify symlink works
ls -la /srv/www/example.com/current/web/app/uploads
# Should show it's a symlink to ../../../shared/uploads

# Test a sample file is accessible
ls -la /srv/www/example.com/shared/uploads/2024/
```

### Alternative: Using Automated Backup Playbooks (Workflow B)

If you're following **Workflow B** (Local-First Migration) and have set up your local development environment with the database and files already imported, you can use the automated backup playbooks instead of manual Steps 6-7.

#### Prerequisites for Using Backup Playbooks

1. Local development environment is running (`trellis vm start`)
2. Database and uploads are already in your local Bedrock installation
3. Production server is provisioned and deployed
4. Backup playbooks are available in this repository at `../../trellis/backup/`

#### Push Database Using Playbook (Alternative to Step 6)

```bash
# From trellis directory
cd trellis

# Push database from development to production
ansible-playbook ../../trellis/backup/database-push.yml -e site=example.com -e env=production
```

**What this playbook does automatically:**
- Exports database from local development environment
- Creates backup of production database (saved to `site/database_backup/`)
- Imports development database to production
- Performs search-replace for domain URLs (old domain → new domain)
- Performs search-replace for path conversions (wp-content → app) if needed
- Cleans up temporary files
- Provides detailed progress output

#### Push Files Using Playbook (Alternative to Step 7)

```bash
# From trellis directory
cd trellis

# Push uploads from development to production
ansible-playbook ../../trellis/backup/files-push.yml -e site=example.com -e env=production
```

**What this playbook does automatically:**
- Syncs uploads directory from local to production
- Preserves file permissions and ownership
- Shows progress during transfer
- Includes confirmation prompt before overwriting
- Handles symlinks correctly
- Sets correct permissions on destination

#### When to Use the Backup Playbooks

**✅ Use backup playbooks when:**
- You have local development environment running
- Files and database are already in local Bedrock structure
- You want automated, repeatable process
- Migrating multiple sites (consistency is key)
- You need to test migrations before going live
- You want built-in safety features (backups, confirmations)

**❌ Don't use backup playbooks when:**
- Migrating directly from old server to production (use manual rsync/wp db import)
- Local development environment is not set up
- You need to customize the migration process significantly
- Source files are not yet in Bedrock structure locally

#### Benefits of Using Backup Playbooks for Migration

1. **Automated Path Conversion**: The database-push playbook can handle path conversions automatically
2. **Built-in Backups**: Production database is backed up before import
3. **Repeatable**: Easy to re-run if something goes wrong
4. **Consistent**: Same process for all three sites
5. **Time-Saving**: Faster than manual operations for multiple sites
6. **Error Handling**: Better error messages and rollback capabilities

For detailed documentation on the backup playbooks, see [backup/README.md](../../trellis/backup/README.md).

### 8. Choose Your Path Migration Strategy

#### Strategy A: Full Bedrock Adoption (Recommended)

Update all file paths in the database to match Bedrock structure:

```bash
# SSH into Trellis server
cd /srv/www/example.com/current

# Preview theme path changes
wp search-replace '/wp-content/themes/' '/app/themes/' --all-tables --dry-run

# Apply theme path changes
wp search-replace '/wp-content/themes/' '/app/themes/' --all-tables

# Preview uploads path changes
wp search-replace 'https://example.com/wp-content/uploads/' 'https://example.com/app/uploads/' --all-tables --precise --dry-run

# Apply uploads path changes
wp search-replace 'https://example.com/wp-content/uploads/' 'https://example.com/app/uploads/' --all-tables --precise

# Also handle protocol-relative and non-HTTPS URLs
wp search-replace '//example.com/wp-content/uploads/' '//example.com/app/uploads/' --all-tables --precise
wp search-replace 'http://example.com/wp-content/uploads/' 'https://example.com/app/uploads/' --all-tables --precise

# Search for any remaining wp-content references
wp search-replace '/wp-content/plugins/' '/app/plugins/' --all-tables
```

**After path migration:**

```bash
# Flush caches and permalinks
wp cache flush
wp rewrite flush

# Regenerate thumbnails if needed
wp media regenerate --yes
```

#### Strategy B: Path Compatibility Mode

Keep existing paths by modifying Bedrock configuration:

**Edit `site/config/application.php`:**

```php
/**
 * Custom Content Directory
 * Keep wp-content paths for compatibility with existing database
 */
Config::define('CONTENT_DIR', '/wp-content');
Config::define('WP_CONTENT_DIR', $webroot_dir . Config::get('CONTENT_DIR'));
Config::define('WP_CONTENT_URL', Config::get('WP_HOME') . Config::get('CONTENT_DIR'));
```

**Adjust your directory structure:**

```bash
# On Trellis server, create symlinks or move directories
cd /srv/www/example.com/current/web

# Option 1: Rename app to wp-content (if you want actual directory)
mv app wp-content

# Option 2: Create symlink (more flexible)
ln -s app wp-content
```

**Important:** If using this approach, ensure your deployment process maintains this structure.

#### Strategy C: Hybrid Approach

Use Bedrock structure for new uploads but keep compatibility for existing ones:

**Edit `site/config/application.php`:**

```php
/**
 * Hybrid Content Directory
 * New uploads go to /app/uploads, but old paths still work
 */
Config::define('CONTENT_DIR', '/app');
Config::define('UPLOADS', 'uploads'); // Still uses /app/uploads for new

// Add rewrite rules in Nginx or .htaccess to redirect old paths
```

**Add to Trellis Nginx configuration** (`trellis/roles/wordpress-setup/templates/wordpress-site.conf.j2`):

```nginx
# Redirect old wp-content paths to new app paths
location ~ ^/wp-content/uploads/(.*)$ {
    return 301 /app/uploads/$1;
}

location ~ ^/wp-content/themes/(.*)$ {
    return 301 /app/themes/$1;
}
```

**Important**: If using Strategy B or C, you'll need to re-provision or reload Nginx:

```bash
# From trellis directory
cd trellis

# Re-provision with nginx tag only
trellis provision --tags nginx production

# Or just reload Nginx
ssh admin_user@your.server.ip.address "sudo systemctl reload nginx"
```

### 9. Test and Verify

Comprehensive testing checklist:

```bash
# Verify WordPress installation
wp core verify-checksums

# Check database
wp db check

# List active plugins
wp plugin list --status=active

# Check theme status
wp theme list

# Test search-replace was successful
wp db search 'wp-content/uploads' --all-tables

# Verify upload functionality
# Upload a test image via WordPress admin
```

**Manual Testing:**
- [ ] Homepage loads correctly
- [ ] All images display properly
- [ ] Theme styles are applied
- [ ] Navigation menus work
- [ ] Forms submit correctly
- [ ] Admin panel is accessible
- [ ] Plugins function as expected
- [ ] Custom post types display
- [ ] Search functionality works
- [ ] User login/logout works
- [ ] Media library displays all images
- [ ] Upload new media works

**Performance Testing:**
```bash
# Check site load time
curl -o /dev/null -s -w "Time: %{time_total}s\n" https://example.com

# Test HTTPS
curl -I https://example.com | grep "HTTP"

# Verify cache headers
curl -I https://example.com/app/uploads/2024/01/image.jpg | grep -i cache
```

### 10. Test with /etc/hosts Before DNS Cutover

**IMPORTANT**: Before changing DNS to point to your new server, test the site by temporarily mapping the domain to your new server's IP using your local `/etc/hosts` file. This allows you to verify everything works correctly without affecting live traffic.

#### Why Use /etc/hosts for Testing?

- ✅ Test the site with the actual production domain (not a temporary URL)
- ✅ Verify SSL certificates work (if using self-signed for testing)
- ✅ Find and fix issues before DNS cutover
- ✅ No impact on live traffic - old site remains accessible to everyone else
- ✅ Easy to switch back and forth between old and new server for comparison

#### Step 1: Add Entry to /etc/hosts

On your local computer (not the server), edit `/etc/hosts`:

```bash
# macOS/Linux
sudo nano /etc/hosts

# Windows
# Edit C:\Windows\System32\drivers\etc\hosts as Administrator
```

Add this line (replace with your actual server IP and domain):
```
123.456.789.123  example.com
123.456.789.123  www.example.com
```

**Save and close the file.**

#### Step 2: Flush DNS Cache

Clear your local DNS cache so the changes take effect:

```bash
# macOS (Big Sur and later)
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

# Linux
sudo systemd-resolve --flush-caches

# Windows (Command Prompt as Administrator)
ipconfig /flushdns
```

#### Step 3: Test the Site (Without SSL Initially)

At this point, SSL won't work yet because Let's Encrypt requires DNS to be pointed to your server. You have two options:

**Option A: Test Without SSL (Temporary)**

Temporarily disable SSL requirement in Trellis configuration:

Edit `trellis/group_vars/production/wordpress_sites.yml`:
```yaml
wordpress_sites:
  example.com:
    site_hosts:
      - canonical: example.com
    ssl:
      enabled: false  # Temporarily disable for testing
```

Re-provision to update Nginx configuration:
```bash
cd trellis
trellis provision production --tags nginx
```

Now test in browser:
```
http://example.com  # Note: HTTP, not HTTPS
```

**Option B: Use Self-Signed Certificate (Better for Testing)**

Keep SSL enabled but temporarily use a self-signed certificate:

```bash
# SSH into server
ssh admin@your.server.ip.address

# Create self-signed certificate for testing
sudo mkdir -p /etc/nginx/ssl/example.com
sudo openssl req -x509 -nodes -days 30 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/example.com/server.key \
  -out /etc/nginx/ssl/example.com/server.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=example.com"

# Update Nginx to use self-signed cert temporarily
# Edit: /etc/nginx/sites-available/example.com.conf
# Change ssl_certificate paths to point to self-signed cert

# Reload Nginx
sudo systemctl reload nginx
```

Test in browser (you'll see a certificate warning - this is expected):
```
https://example.com  # Accept the security warning
```

#### Step 4: Comprehensive Testing with Real Domain

Now that you can access the site using the production domain, test thoroughly:

- [ ] Homepage loads with correct domain in URL bar
- [ ] All images display (check absolute URLs work correctly)
- [ ] Navigation menus work
- [ ] Contact forms submit correctly
- [ ] WordPress admin accessible at `https://example.com/wp/wp-admin/`
- [ ] Media library shows all images
- [ ] Test uploading new media
- [ ] Check for any hardcoded URL issues
- [ ] Verify redirects (www to non-www or vice versa)

**Check for mixed content issues:**
```bash
# In browser console, look for:
# - Mixed content warnings
# - 404 errors on assets
# - JavaScript errors

# On server, check error logs
sudo tail -f /var/log/nginx/error.log
```

#### Step 5: Fix Any Issues Found

If you find issues during testing:

```bash
# Common fixes:
# 1. URL issues - run additional search-replace
ssh admin@server
cd /srv/www/example.com/current
wp search-replace 'http://example.com' 'https://example.com' --all-tables

# 2. Path issues - verify uploads path conversion
wp db search 'wp-content/uploads' --all-tables

# 3. Permission issues - fix uploads permissions
sudo chown -R web:www-data /srv/www/example.com/shared/uploads
sudo chmod -R 775 /srv/www/example.com/shared/uploads

# 4. Cache issues - flush all caches
wp cache flush
wp rewrite flush
```

#### Step 6: Prepare for DNS Cutover

Once testing is complete and everything works:

1. **Re-enable SSL with Let's Encrypt in Trellis** (if you disabled it for testing):

   Edit `trellis/group_vars/production/wordpress_sites.yml`:
   ```yaml
   wordpress_sites:
     example.com:
       site_hosts:
         - canonical: example.com
           redirects:
             - www.example.com
       ssl:
         enabled: true
         provider: letsencrypt  # Important: Set provider to letsencrypt
   ```

   **Important**: Make sure this configuration is in place BEFORE you change DNS. This way, after DNS propagation, you can simply run the provision command to get your SSL certificate.

2. **Commit this configuration** (if using version control):
   ```bash
   cd trellis
   git add group_vars/production/wordpress_sites.yml
   git commit -m "Re-enable SSL with Let's Encrypt for production"
   ```

3. **Remove /etc/hosts entry** from your local computer:
   ```bash
   sudo nano /etc/hosts
   # Delete or comment out the line you added:
   # 123.456.789.123  example.com
   ```

4. **Flush DNS cache again**:
   ```bash
   # macOS
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```

5. **Now proceed with DNS cutover** (see next section)

#### Notes About Let's Encrypt SSL

**IMPORTANT**: Let's Encrypt SSL certificates can only be generated **AFTER** DNS is pointed to your new server. This is because Let's Encrypt validates domain ownership by checking DNS.

**Timeline:**
1. ✅ **Before DNS cutover**: Test with `/etc/hosts` and either HTTP or self-signed certificate
2. ✅ **Update DNS**: Point your domain to new server IP
3. ✅ **Wait for DNS propagation**: Usually 5-30 minutes, but can take up to 48 hours
4. ✅ **Request Let's Encrypt SSL**: Trellis does this automatically on next provision

**After DNS is live and has propagated**, provision with the letsencrypt tag to get your certificate:

```bash
cd trellis

# Wait for DNS to propagate (check with: dig example.com +short)
# Should return your new server IP

# RECOMMENDED: Use --tags letsencrypt for faster, focused provisioning
trellis provision production --tags letsencrypt

# Alternative: Re-provision everything (takes longer)
trellis provision production
```

**Why use `--tags letsencrypt`?**
- ⚡ Much faster - only runs SSL certificate tasks
- ✅ Safer - doesn't re-run all provisioning tasks
- 🎯 Focused - specifically requests and installs Let's Encrypt certificate

**What Trellis does automatically:**
- Detects that DNS now points to the server
- Validates domain ownership via Let's Encrypt's DNS challenge
- Requests SSL certificate from Let's Encrypt
- Installs the certificate to `/etc/letsencrypt/`
- Updates Nginx configuration to use the certificate
- Sets up auto-renewal cron job (certificates renewed every 60 days)

**Verify SSL is active:**
```bash
# SSH into server
ssh admin@your.server.ip

# Check certificate details
sudo certbot certificates

# Should show:
# Certificate Name: example.com
# Domains: example.com www.example.com
# Expiry Date: [60 days from now]
# Certificate Path: /etc/letsencrypt/live/example.com/fullchain.pem
# Private Key Path: /etc/letsencrypt/live/example.com/privkey.pem
```

**Test SSL in browser:**
```
https://example.com  # Should show valid certificate, no warnings
```

**Check SSL grade:**
- Visit: https://www.ssllabs.com/ssltest/
- Should achieve A+ rating with Trellis's default SSL configuration

### WordPress Cron: System Cron vs WP-Cron

**IMPORTANT**: Trellis automatically disables WordPress's built-in WP-Cron and uses **system cron** instead for more reliable scheduled task execution.

#### What Changed After Migration

**Before (Traditional WordPress):**
- WP-Cron runs when someone visits your site
- Unreliable on low-traffic sites
- Can cause performance overhead

**After (Trellis):**
- System cron runs every 15 minutes via `/etc/cron.d/wordpress-{site}`
- Reliable, predictable execution
- No dependency on site traffic

#### Verification After Migration

```bash
# SSH into your Trellis server
ssh admin@your.server.ip

# 1. Verify WP-Cron is disabled
cd /srv/www/example.com/current
grep DISABLE_WP_CRON .env
# Should show: DISABLE_WP_CRON=true

# 2. Check system cron job exists
cat /etc/cron.d/wordpress-example_com
# Should show:
# #Ansible: example.com WordPress cron
# */15 * * * * web cd /srv/www/example.com/current && wp cron event run --due-now > /dev/null 2>&1

# 3. List WordPress scheduled events (these are preserved from your database)
wp cron event list

# 4. Manually test cron execution
sudo -u web bash -c "cd /srv/www/example.com/current && wp cron event run --due-now"
```

#### What You Need to Know

1. **Scheduled posts still work** - Your scheduled posts will publish on time via system cron
2. **Plugin schedules are preserved** - All scheduled tasks (backups, cache clearing, etc.) are stored in the database and migrate with your data
3. **More reliable** - Tasks run every 15 minutes regardless of site traffic
4. **No action needed** - Trellis configures this automatically during provisioning

#### Troubleshooting Cron Issues

If scheduled tasks aren't running after migration:

```bash
# Check if events are scheduled
wp cron event list

# Manually trigger overdue events
wp cron event run --due-now

# Check system cron logs
sudo grep -i cron /var/log/syslog | tail -20

# Verify cron service is running
sudo systemctl status cron
```

For detailed cron documentation, customization, and troubleshooting, see [provision/CRON.md](../../trellis/provision/CRON.md).

### 11. DNS and Go-Live

When ready to go live:

1. **Lower TTL** on your current DNS records (24 hours before migration)
   ```
   example.com. 300 IN A old.server.ip
   ```

2. **Update DNS** to point to your new Trellis server
   ```
   example.com. 300 IN A new.server.ip
   ```

3. **Monitor** DNS propagation:
   ```bash
   # Check DNS propagation locally
   dig example.com +short
   # Should return: 123.456.789.123 (your new server IP)

   # Check from multiple locations worldwide
   # Use: https://www.whatsmydns.net/
   ```

4. **Wait for DNS to fully propagate** (typically 5-30 minutes, but can take up to 48 hours)

5. **CRITICAL: Provision to get Let's Encrypt SSL certificate:**

   Once DNS is confirmed to point to your server:
   ```bash
   cd trellis

   # RECOMMENDED: Use --tags letsencrypt for fast SSL setup
   trellis provision production --tags letsencrypt
   ```

   This will:
   - Request SSL certificate from Let's Encrypt
   - Install certificate
   - Configure Nginx to use HTTPS
   - Set up automatic renewal

   **Verify SSL certificate:**
   ```bash
   # SSH into server
   ssh admin@server.ip

   # Check certificate was issued
   sudo certbot certificates
   # Should show valid certificate for example.com
   ```

6. **Test HTTPS in browser:**
   ```
   https://example.com  # Should load with valid SSL, no warnings
   ```

7. **Redirect old server** (optional, keep old hosting active for a few days):

   Add to old server's `.htaccess`:
   ```apache
   <IfModule mod_rewrite.c>
       RewriteEngine On
       RewriteCond %{HTTP_HOST} ^example\.com$ [OR]
       RewriteCond %{HTTP_HOST} ^www\.example\.com$
       RewriteRule ^(.*)$ https://example.com/$1 [R=301,L]
   </IfModule>
   ```

8. **Final verification:**
   ```bash
   # Check SSL score (should be A+)
   # Visit: https://www.ssllabs.com/ssltest/

   # Test all site functionality over HTTPS
   curl -I https://example.com | grep "HTTP"

   # Monitor server logs for any errors
   ssh admin@server.ip
   sudo tail -f /var/log/nginx/error.log
   ```

## Troubleshooting

### Issue: Images Not Displaying

**Symptoms:** Broken image links, 404 errors on media files

**Solutions:**

```bash
# 1. Check upload directory permissions
ls -la /srv/www/example.com/shared/uploads/
sudo chown -R web:www-data /srv/www/example.com/shared/uploads
sudo chmod -R 775 /srv/www/example.com/shared/uploads

# 2. Verify symlink is correct
ls -la /srv/www/example.com/current/web/app/
# Should show: uploads -> ../../../shared/uploads

# 3. Check for mixed path references
wp db search 'wp-content/uploads' --all-tables

# 4. Regenerate thumbnails
wp media regenerate --yes

# 5. Check Nginx error logs
sudo tail -f /var/log/nginx/error.log
```

### Issue: White Screen of Death (WSOD)

**Symptoms:** Blank white screen, no error messages

**Solutions:**

```bash
# 1. Enable debug mode
# Edit site/config/environments/production.php
Config::define('WP_DEBUG', true);
Config::define('WP_DEBUG_LOG', true);
Config::define('WP_DEBUG_DISPLAY', false);

# 2. Check PHP error logs
sudo tail -f /var/log/php8.2-fpm.log

# 3. Verify file permissions
sudo chown -R web:www-data /srv/www/example.com/current
sudo chmod -R 755 /srv/www/example.com/current

# 4. Check for plugin conflicts
wp plugin deactivate --all
wp plugin activate plugin-name  # Activate one by one
```

### Issue: Database Connection Errors

**Symptoms:** "Error establishing database connection"

**Solutions:**

```bash
# 1. Verify database credentials
cat site/.env | grep DB_

# 2. Check database exists
mysql -u db_user -p -e "SHOW DATABASES;"

# 3. Test database connection
wp db check

# 4. Verify MariaDB is running
sudo systemctl status mariadb

# 5. Check database user permissions
mysql -u root -p
# Then in MySQL:
SELECT user, host FROM mysql.user;
SHOW GRANTS FOR 'db_user'@'localhost';
```

### Issue: Permalinks Not Working (404 Errors)

**Symptoms:** Homepage works, but all other pages show 404

**Solutions:**

```bash
# 1. Flush rewrite rules
wp rewrite flush

# 2. Regenerate .htaccess (if using Apache)
wp rewrite flush --hard

# 3. Check Nginx configuration
sudo nginx -t

# 4. Verify WordPress .htaccess rules are in place
cat /srv/www/example.com/current/web/.htaccess

# 5. Restart Nginx
sudo systemctl restart nginx
```

### Issue: Plugin or Theme Compatibility

**Symptoms:** Plugins not working, theme breaking

**Solutions:**

```bash
# 1. Check for hardcoded paths in theme
grep -r "wp-content" /srv/www/example.com/current/web/app/themes/your-theme/

# 2. Search for ABSPATH usage
grep -r "ABSPATH" /srv/www/example.com/current/web/app/themes/your-theme/

# 3. Update plugins to latest versions
wp plugin update --all

# 4. Check plugin compatibility with PHP version
wp plugin list

# 5. Review plugin-specific logs
wp plugin deactivate problematic-plugin
# Check if issue resolves
```

### Issue: Slow Performance After Migration

**Symptoms:** Site loads slowly compared to old server

**Solutions:**

```bash
# 1. Enable object caching (Redis)
# Edit trellis/group_vars/production/wordpress_sites.yml
cache:
  enabled: true

# 2. Install Redis plugin
composer require wpackagist-plugin/redis-cache

# 3. Check query monitor for slow queries
composer require wpackagist-plugin/query-monitor --dev

# 4. Optimize database
wp db optimize

# 5. Check server resources
htop
free -h
df -h

# 6. Enable FastCGI cache in Nginx (already in Trellis)
# Verify it's working:
curl -I https://example.com | grep "X-FastCGI-Cache"
```

### Issue: Mixed Content Warnings (HTTP/HTTPS)

**Symptoms:** Browser shows "not secure" warnings, mixed content errors

**Solutions:**

```bash
# 1. Update all URLs to HTTPS
wp search-replace 'http://example.com' 'https://example.com' --all-tables --dry-run
wp search-replace 'http://example.com' 'https://example.com' --all-tables

# 2. Check for hardcoded HTTP URLs in theme
grep -r "http://" /srv/www/example.com/current/web/app/themes/your-theme/

# 3. Install SSL insecure content fixer plugin (temporary)
wp plugin install ssl-insecure-content-fixer --activate

# 4. Verify SSL certificate
sudo certbot certificates

# 5. Check browser console for specific mixed content URLs
# Fix them individually in database or theme files
```

## Post-Migration Optimization

After successful migration, consider these optimizations:

### 1. Set Up Backups

```bash
# Use the backup tools in this repository
# See: ../../trellis/backup/README.md

# Set up automated database backups
ansible-playbook backup/trellis/database-backup.yml -e site=example.com -e env=production

# Set up automated file backups
ansible-playbook backup/trellis/files-backup.yml -e site=example.com -e env=production
```

### 2. Enable Redis Object Caching

```bash
# Install Redis plugin
composer require wpackagist-plugin/redis-cache

# Activate and enable
wp plugin activate redis-cache
wp redis enable
```

### 3. Configure Browser Caching

See the [Browser Caching Guide](../../nginx/browser-caching/README.md) in this repository.

### 4. Optimize Images

See the [Image Optimization Guide](../../nginx/image-optimization/README.md) for WebP/AVIF support.

### 5. Set Up Monitoring

```bash
# Install monitoring tools
composer require wpackagist-plugin/query-monitor --dev

# Set up server monitoring
# Consider: New Relic, Datadog, or Prometheus
```

### 6. Security Hardening

```bash
# Install security plugin
composer require wpackagist-plugin/wordfence

# Disable file editing in WordPress admin
# Add to site/config/application.php:
Config::define('DISALLOW_FILE_EDIT', true);

# Set up fail2ban for SSH protection
sudo apt install fail2ban
```

### 7. Performance Monitoring

```bash
# Install performance monitoring
wp plugin install query-monitor --activate

# Check page load times
curl -o /dev/null -s -w "Total time: %{time_total}s\n" https://example.com

# Use tools like:
# - GTmetrix: https://gtmetrix.com/
# - Google PageSpeed Insights: https://pagespeed.web.dev/
# - Pingdom: https://tools.pingdom.com/
```

### 8. Regular Maintenance Schedule

Create a maintenance schedule:

```bash
# Weekly tasks
- Review error logs
- Update plugins and themes
- Check site backups
- Monitor site performance

# Monthly tasks
- Security audit
- Database optimization
- Review and update dependencies
- Check for WordPress core updates

# Quarterly tasks
- Full backup verification
- Disaster recovery drill
- Performance audit
- Security penetration testing
```

## Additional Resources

- [Trellis Documentation](https://roots.io/trellis/docs/)
- [Bedrock Documentation](https://roots.io/bedrock/docs/)
- [WP-CLI Commands](https://developer.wordpress.org/cli/commands/)
- [Roots Discourse Community](https://discourse.roots.io/)

## Need More Help?

- Review the main [Migration Guide](README.md) for other migration scenarios
- Check the [Backup Tools](../../trellis/backup/README.md) for data management
- See [Provisioning Guide](../../trellis/provision/README.md) for server setup help
