# Migrating Multiple WordPress Sites to Trellis

This guide covers strategies and best practices for migrating **multiple WordPress sites to a single Trellis server**. This is particularly useful for agencies, consultants, or anyone consolidating multiple client sites onto modern infrastructure.

## Prerequisites

Before using this guide, you should:

1. **Read the [core migration guide](REGULAR-TO-TRELLIS.md)** - This document assumes you understand the basic single-site migration process
2. Have a working Trellis installation
3. Understand Bedrock directory structure
4. Be familiar with WP-CLI commands

## Table of Contents

- [Overview](#overview)
- [Time-Saving Tips for Multiple Sites](#time-saving-tips-for-multiple-sites)
- [Managing Multiple Sites on One Server](#managing-multiple-sites-on-one-server)
- [Common Pitfalls When Migrating Multiple Sites](#common-pitfalls-when-migrating-multiple-sites)
- [Multi-Site Troubleshooting](#multi-site-troubleshooting)

## Overview

One of Trellis's strengths is the ability to host **multiple WordPress sites on a single server**. When migrating multiple sites, you can save significant time by:

- Batching preparation work
- Configuring all sites before first provision
- Running operations in parallel
- Using reusable scripts and templates
- Learning from the first migration to speed up subsequent ones

**Expected Timeline:**
- **First site**: 3-5 hours (learning curve)
- **Second site**: 2-3 hours (process is familiar)
- **Third site**: 2-2.5 hours (optimized workflow)
- **Total for 3 sites**: 8-10 hours (vs. 12-15 hours without optimization)

## Time-Saving Tips for Multiple Sites

When migrating three sites to a single Trellis server, use these strategies to minimize time and maximize efficiency.

### 1. Batch Preparation Phase

Before starting any migrations, prepare all three sites at once:

**Checklist for all sites:**
- [ ] Download all databases from old hosting (export as `.sql` or `.sql.gz`)
- [ ] Download all file backups (themes, plugins, uploads) to organized local folders
- [ ] Document all active plugins for each site in a spreadsheet
- [ ] Generate all WordPress salts at once (visit https://roots.io/salts.html three times, save to text files)
- [ ] Create all three Git repositories on GitHub/GitLab
- [ ] Document any special configurations from old `wp-config.php` files

**Organize your downloads:**
```bash
# Create organized backup structure
mkdir -p ~/migrations/site1/{database,files}
mkdir -p ~/migrations/site2/{database,files}
mkdir -p ~/migrations/site3/{database,files}

# This organization saves time when you're ready to migrate each site
```

### 2. Use Descriptive Directory Names from Start

Instead of using generic `site/` directory, use descriptive names immediately to avoid confusion:

```bash
# For first site
trellis new example.com
cd example.com
mv site site-example

# Update trellis/group_vars/*/wordpress_sites.yml
# Change: local_path: ../site
# To:     local_path: ../site-example

# Then add second and third sites
composer create-project roots/bedrock site-clienttwo
composer create-project roots/bedrock site-clientthree
```

**Benefits:**
- No confusion about which site is which
- Easier to reference in commands
- Clear Git history
- Better for team collaboration

### 3. Configure All Sites Before First Provision

Add all three sites to `wordpress_sites.yml` before provisioning. This way:

- **Single provisioning run** sets up all three databases
- **All SSL certificates** created at once with Let's Encrypt
- **Nginx configured** for all sites simultaneously
- **Saves ~30 minutes** vs. provisioning three times

**Example `trellis/group_vars/production/wordpress_sites.yml`:**
```yaml
wordpress_sites:
  example.com:
    site_hosts:
      - canonical: example.com
    local_path: ../site-example
    repo: git@github.com:yourusername/trellis-multi.git
    repo_subtree_path: site-example
    # ... rest of config ...

  clienttwo.com:
    site_hosts:
      - canonical: clienttwo.com
    local_path: ../site-clienttwo
    repo: git@github.com:yourusername/trellis-multi.git
    repo_subtree_path: site-clienttwo
    # ... rest of config ...

  clientthree.com:
    site_hosts:
      - canonical: clientthree.com
    local_path: ../site-clientthree
    repo: git@github.com:yourusername/trellis-multi.git
    repo_subtree_path: site-clientthree
    # ... rest of config ...
```

Then run once:
```bash
trellis provision production
```

### 4. Parallel Operations

Take advantage of independent operations that can run simultaneously:

**While database is importing on Site 1:**
```bash
# In one terminal: Import database for site 1
ssh admin@server "cd /srv/www/example.com/current && wp db import /tmp/backup1.sql"

# In another terminal: Upload files for site 2
rsync -avz ~/migrations/site2/files/uploads/ admin@server:/srv/www/clienttwo.com/shared/uploads/

# In another terminal: Work on site 3 locally
cd ~/code/trellis-project/site-clientthree
# Copy theme and plugins
```

**While running search-replace on one site:**
- Deploy the next site
- Prepare the third site's uploads for transfer
- Run tests on a completed site

### 5. Create Reusable Scripts

Save time by scripting repetitive tasks:

**Script: `migrate-uploads.sh`**
```bash
#!/bin/bash
# Usage: ./migrate-uploads.sh site1 example.com

SITE_NAME=$1
DOMAIN=$2
LOCAL_UPLOADS=~/migrations/$SITE_NAME/files/uploads
SERVER_PATH=/srv/www/$DOMAIN/shared/uploads

echo "Migrating uploads for $DOMAIN..."
rsync -avz --progress $LOCAL_UPLOADS/ admin@your.server.ip:$SERVER_PATH/

echo "Setting permissions..."
ssh admin@your.server.ip "sudo chown -R web:www-data $SERVER_PATH && sudo chmod -R 775 $SERVER_PATH"

echo "Done!"
```

**Script: `import-database.sh`**
```bash
#!/bin/bash
# Usage: ./import-database.sh site1 example.com

SITE_NAME=$1
DOMAIN=$2
LOCAL_DB=~/migrations/$SITE_NAME/database/backup.sql

echo "Uploading database for $DOMAIN..."
scp $LOCAL_DB admin@your.server.ip:/tmp/backup-$SITE_NAME.sql

echo "Importing database..."
ssh admin@your.server.ip "cd /srv/www/$DOMAIN/current && wp db import /tmp/backup-$SITE_NAME.sql && rm /tmp/backup-$SITE_NAME.sql"

echo "Done!"
```

### 6. Use Workflow B for Maximum Efficiency

For three sites, **Workflow B** (Local-First Migration) with backup playbooks is most efficient:

**Advantages for multiple sites:**
1. Test each migration locally before production
2. Use automated playbooks for consistency
3. Easy to repeat if something goes wrong
4. Can work on next site while previous deploys

**Timeline for three sites using Workflow B:**
- **Day 1 (4-5 hours):** Site 1 - Full setup, local test, push to production
- **Day 2 (3 hours):** Site 2 - Faster since server/process established
- **Day 3 (2.5 hours):** Site 3 - Fastest, everything is familiar

**Total: 9-10.5 hours** vs. 12-15 hours with direct migration

### 7. Maintain a Migration Checklist

Track progress across all sites with a simple checklist:

```markdown
## Migration Progress Tracker

### Site 1: example.com
- [x] Backups downloaded
- [x] Bedrock created (site-example)
- [x] Theme/plugins copied
- [x] Deployed to production
- [x] Database migrated
- [x] Uploads synced
- [x] Paths converted
- [x] Tested
- [x] DNS updated

### Site 2: clienttwo.com
- [x] Backups downloaded
- [x] Bedrock created (site-clienttwo)
- [ ] Theme/plugins copied
- [ ] Deployed to production
...
```

### 8. Common Configuration Across Sites

If all three sites share similar requirements, create templates:

**Template: Search-replace commands**
```bash
# Save as search-replace-template.sh
# Update domain for each site

DOMAIN=$1
wp search-replace '/wp-content/themes/' '/app/themes/' --all-tables
wp search-replace '/wp-content/plugins/' '/app/plugins/' --all-tables
wp search-replace "https://$DOMAIN/wp-content/uploads/" "https://$DOMAIN/app/uploads/" --all-tables --precise
wp search-replace "http://$DOMAIN/wp-content/uploads/" "https://$DOMAIN/app/uploads/" --all-tables --precise
wp cache flush
wp rewrite flush
```

**Usage:**
```bash
# Run on each site
ssh admin@server "cd /srv/www/example.com/current && bash" < search-replace-template.sh example.com
```

### Summary: Optimal Multi-Site Migration Strategy

1. ✅ **Batch prepare** all three sites upfront (1 hour)
2. ✅ **Configure all sites** in Trellis before provisioning (30 mins)
3. ✅ **Provision once** for all three sites (15 mins)
4. ✅ **Use Workflow B** with backup playbooks (most efficient)
5. ✅ **Run operations in parallel** where possible
6. ✅ **Create reusable scripts** for repetitive tasks
7. ✅ **Track progress** with checklist

**Expected timeline for three sites: 8-10 hours total** (vs. 12-15 hours without optimization)

## Managing Multiple Sites on One Server

One of Trellis's strengths is the ability to host **multiple WordPress sites on a single server**. This is common for agencies or when consolidating multiple client sites.

### Important: Directory Structure for Multiple Sites

When you use `trellis new example.com`, it creates a directory structure with a `site/` folder for your Bedrock installation. However, when managing **multiple sites on the same server**, you should:

1. **Use descriptive directory names** instead of generic `site/`
2. **Each site gets its own Bedrock installation** in the Trellis project
3. **All sites share the same Trellis configuration**

### Scenario 1: First Site on Server (Using trellis new)

For your first site, you can use `trellis new`:

```bash
cd ~/code

# This creates the Trellis project with default 'site/' directory
trellis new example.com
cd example.com

# Your structure:
# example.com/
# ├── trellis/
# └── site/         # Bedrock for example.com
```

**However**, if you know you'll be adding more sites later, it's better to rename `site/` immediately:

```bash
# Rename site to something descriptive
mv site site-imagewize

# Update trellis/group_vars/*/wordpress_sites.yml
# Change: local_path: ../site
# To:     local_path: ../site-imagewize
```

### Scenario 2: Adding a Second Site to Existing Trellis

When you need to add a second site to your existing Trellis server:

#### Step 1: Create New Bedrock Installation

Use Composer to create a new Bedrock installation with a descriptive name:

```bash
# Navigate to your Trellis project root
cd ~/code/example.com  # Your existing Trellis project

# Create new Bedrock installation for second site
composer create-project roots/bedrock site-clientname

# Or for a specific site
composer create-project roots/bedrock site-name
```

This creates:
```
example.com/
├── trellis/
├── site-imagewize/    # First site
└── site-name/ # Second site
```

#### Step 2: Configure the New Site in Trellis

**Edit development configuration** - `trellis/group_vars/development/wordpress_sites.yml`:

```yaml
wordpress_sites:
  # First site
  example.com:
    site_hosts:
      - canonical: imagewize.test
    local_path: ../site-imagewize
    # ... other settings ...

  # Second site (NEW)
  jasperfrumau.com:
    site_hosts:
      - canonical: jasperfrumau.test
    local_path: ../site-jasperfrumau  # Points to new Bedrock directory
    admin_email: admin@jasperfrumau.com
    multisite:
      enabled: false
    ssl:
      enabled: false  # Development doesn't need SSL
    cache:
      enabled: false
```

**Edit production configuration** - `trellis/group_vars/production/wordpress_sites.yml`:

```yaml
wordpress_sites:
  # First site
  example.com:
    site_hosts:
      - canonical: example.com
        redirects:
          - www.example.com
    local_path: ../site-imagewize
    repo: git@github.com:yourusername/example.com.git
    repo_subtree_path: site-imagewize
    branch: main
    multisite:
      enabled: false
    ssl:
      enabled: true
      provider: letsencrypt
    cache:
      enabled: true

  # Second site (NEW)
  jasperfrumau.com:
    site_hosts:
      - canonical: jasperfrumau.com
        redirects:
          - www.jasperfrumau.com
    local_path: ../site-jasperfrumau
    repo: git@github.com:yourusername/example.com.git  # Same repo!
    repo_subtree_path: site-jasperfrumau  # Different path in repo
    branch: main
    multisite:
      enabled: false
    ssl:
      enabled: true
      provider: letsencrypt
    cache:
      enabled: true
```

**Edit vault for both environments** - `trellis/group_vars/*/vault.yml`:

```bash
# Edit development vault
cd trellis
trellis vault edit development

# Edit production vault
trellis vault edit production
```

Add configuration for the new site:

```yaml
vault_wordpress_sites:
  # First site
  example.com:
    env:
      db_password: "secure_password_1"
      # ... salts ...

  # Second site (NEW)
  jasperfrumau.com:
    env:
      db_password: "secure_password_2"  # Different password!
      # Generate new salts at: https://roots.io/salts.html
      auth_key: "generateme"
      secure_auth_key: "generateme"
      logged_in_key: "generateme"
      nonce_key: "generateme"
      auth_salt: "generateme"
      secure_auth_salt: "generateme"
      logged_in_salt: "generateme"
      nonce_salt: "generateme"
```

#### Step 3: Add New Site to Git Repository

Since both sites share the same Trellis configuration, they should be in the same Git repository:

```bash
# From project root
cd ~/code/example.com

# Add new Bedrock installation
git add site-jasperfrumau/

# Commit
git commit -m "Add jasperfrumau.com site"

# Push
git push origin main
```

#### Step 4: Re-Provision Server (REQUIRED for New Sites)

**IMPORTANT:** When adding a new site to an existing server, you **MUST re-provision** to create the necessary infrastructure for the new site:

```bash
cd trellis

# Re-provision production to create infrastructure for new site
trellis provision production
```

**What this does for the new site:**
- ✅ Creates new MySQL database (`jasperfrumau_production`)
- ✅ Creates new database user with credentials from vault
- ✅ Generates Nginx virtual host configuration (`/etc/nginx/sites-available/jasperfrumau.com.conf`)
- ✅ Requests and installs Let's Encrypt SSL certificate for new domain
- ✅ Creates base directory structure (`/srv/www/jasperfrumau.com/`)
- ✅ Updates firewall rules if needed

**Without re-provisioning:**
- ❌ Database won't exist → deployment fails
- ❌ No Nginx config → site shows 502 Bad Gateway
- ❌ No SSL certificate → HTTPS won't work
- ❌ No directory structure → deployment fails

**Alternative (Advanced):** If you only changed Nginx-related settings and know the database already exists:
```bash
# Only update Nginx configuration (faster, but less safe)
ansible-playbook server.yml -e env=production --tags nginx
```

**Best practice:** Always use full `trellis provision production` when adding a new site. It's safer and ensures everything is configured correctly.

#### Step 5: Deploy the New Site

```bash
cd trellis

# Deploy the new site
trellis deploy production jasperfrumau.com

# Or deploy all sites
trellis deploy production
```

#### Step 6: Migrate the Second Site's Data

Follow the same migration steps as the first site:

1. **Import database** to the new site:
   ```bash
   ssh admin_user@your.server.ip.address
   cd /srv/www/jasperfrumau.com/current
   wp db import /path/to/backup.sql
   ```

2. **Transfer uploads**:
   ```bash
   rsync -avz --progress /path/to/backup/wp-content/uploads/ \
     admin_user@your.server.ip.address:/srv/www/jasperfrumau.com/shared/uploads/
   ```

3. **Update paths** (choose your strategy from [main guide](REGULAR-TO-TRELLIS.md#8-choose-your-path-migration-strategy))

### Directory Structure Example

Here's what a multi-site Trellis setup looks like:

```
example.com/                    # Project root (Git repository)
├── .git/
├── trellis/                      # Shared Trellis configuration
│   ├── group_vars/
│   │   ├── all/
│   │   ├── development/
│   │   │   ├── wordpress_sites.yml    # Both sites configured here
│   │   │   └── vault.yml              # Both sites' dev secrets
│   │   └── production/
│   │       ├── wordpress_sites.yml    # Both sites configured here
│   │       └── vault.yml              # Both sites' prod secrets
│   └── hosts/
│       ├── development
│       └── production              # Same server IP for both sites
├── site-imagewize/                # First site (Bedrock)
│   ├── composer.json
│   ├── config/
│   └── web/
│       └── app/
│           ├── themes/
│           └── plugins/
└── site-jasperfrumau/             # Second site (Bedrock)
    ├── composer.json
    ├── config/
    └── web/
        └── app/
            ├── themes/
            └── plugins/
```

### On the Server

Each site gets its own directory structure:

```
/srv/www/
├── example.com/
│   ├── current -> releases/20241023...
│   ├── releases/
│   │   └── 20241023.../
│   └── shared/
│       └── uploads/
└── jasperfrumau.com/
    ├── current -> releases/20241023...
    ├── releases/
    │   └── 20241023.../
    └── shared/
        └── uploads/
```

### Best Practices for Multiple Sites

1. **Use descriptive directory names**: `site-clientname` instead of `site/`, `site1/`, `site2/`

2. **Separate databases**: Each site gets its own MySQL database automatically

3. **Separate database passwords**: Use different passwords in vault for each site

4. **Same server, same Trellis**: All sites on the same server share one Trellis configuration

5. **One Git repository**: Keep all sites and Trellis in the same repository using `repo_subtree_path`

6. **Consider resource limits**: Monitor server resources (RAM, CPU) as you add more sites

7. **SSL certificates**: Let's Encrypt handles multiple domains automatically

### Common Commands for Multiple Sites

```bash
# Deploy specific site
trellis deploy production example.com

# Deploy all sites
trellis deploy production

# Re-provision to update all sites
trellis provision production

# SSH and access specific site
ssh admin_user@your.server.ip.address
cd /srv/www/example.com/current

# WP-CLI for specific site
wp --path=/srv/www/example.com/current/web plugin list
wp --path=/srv/www/jasperfrumau.com/current/web plugin list
```

### When NOT to Use Multiple Sites on One Server

Consider separate servers if:
- Sites have vastly different traffic patterns
- Different PHP version requirements
- Regulatory/security isolation requirements
- One site is mission-critical and needs dedicated resources

## Common Pitfalls When Migrating Multiple Sites

Avoid these common mistakes when migrating multiple WordPress sites to a single Trellis server.

### 1. Forgetting to Update `local_path` for Each Site

**Problem:** All sites point to `../site` instead of unique paths like `../site-example`, `../site-clienttwo`.

**Symptom:** Deployments fail or deploy the wrong site's code.

**Solution:** Always verify unique paths in `wordpress_sites.yml`:

```yaml
wordpress_sites:
  example.com:
    local_path: ../site-example  # ✅ Unique path
    # ...

  clienttwo.com:
    local_path: ../site-clienttwo  # ✅ Unique path
    # ...
```

**How to check:**
```bash
# From trellis directory
grep -A 5 "local_path" group_vars/production/wordpress_sites.yml
```

### 2. Reusing Database Passwords Across Sites

**Problem:** Copy-pasting vault configuration without changing passwords for each site.

**Security Risk:** If one site is compromised, all sites are at risk.

**Solution:** Generate unique passwords for each site:

```bash
# Generate secure password for each site
openssl rand -base64 32

# Edit vault and paste unique password for each site
trellis vault edit production
```

**Vault structure should look like:**
```yaml
vault_wordpress_sites:
  example.com:
    env:
      db_password: "unique_password_1_here"  # Different!
      # ...

  clienttwo.com:
    env:
      db_password: "unique_password_2_here"  # Different!
      # ...
```

### 3. Not Testing Path Conversions Thoroughly

**Problem:** Assuming search-replace worked without verification.

**Symptom:** Some images or assets still have old paths, causing 404 errors.

**Solution:** Always verify after running search-replace:

```bash
# SSH into server
cd /srv/www/example.com/current

# Check for any remaining wp-content references
wp db search 'wp-content/uploads' --all-tables
wp db search 'wp-content/themes' --all-tables
wp db search 'wp-content/plugins' --all-tables

# Should return no results if conversion was successful
```

**If you find remaining references:**
```bash
# Run additional search-replace for specific cases
wp search-replace '//example.com/wp-content/' '//example.com/app/' --all-tables --precise
```

### 4. Skipping DNS Propagation Time

**Problem:** Going live immediately after DNS change, causing confusion when some users see old site and others see new site.

**Impact:** Mixed analytics, confused users, potential lost transactions.

**Solution:**

```bash
# 24-48 hours BEFORE migration:
# Lower TTL on DNS records (via your DNS provider)
# Change from 3600 (1 hour) to 300 (5 minutes)

# After DNS update:
# Check DNS propagation
dig example.com +short

# Check from multiple global locations
# Use: https://www.whatsmydns.net/

# Keep old server running for 24-48 hours as fallback
```

### 5. Incorrect File Permissions on Uploads

**Problem:** Uploads directory has wrong owner or permissions after transfer.

**Symptom:** Can't upload new media, or existing images don't display.

**Solution:** Always set correct permissions after file transfer:

```bash
# After rsync/scp of uploads
ssh admin@server

# Set ownership (web:www-data is the Trellis default)
sudo chown -R web:www-data /srv/www/example.com/shared/uploads

# Set permissions (775 allows web server to write)
sudo chmod -R 775 /srv/www/example.com/shared/uploads

# Verify
ls -la /srv/www/example.com/shared/uploads
```

### 6. Not Updating All Environment Files

**Problem:** Updating `production/wordpress_sites.yml` but forgetting `development/wordpress_sites.yml`.

**Symptom:** Local development breaks or uses wrong configuration.

**Solution:** Always update both environments:

```bash
# Update both files when adding a new site
trellis/group_vars/development/wordpress_sites.yml
trellis/group_vars/production/wordpress_sites.yml

# And both vault files
trellis vault edit development
trellis vault edit production
```

### 7. Mixing Up `repo_subtree_path` Values

**Problem:** Multiple sites pointing to same subtree path in Git repo.

**Symptom:** Deployment pulls wrong code for a site.

**Solution:** Ensure each site has unique `repo_subtree_path`:

```yaml
wordpress_sites:
  example.com:
    repo: git@github.com:user/trellis-multi.git
    repo_subtree_path: site-example  # ✅ Unique

  clienttwo.com:
    repo: git@github.com:user/trellis-multi.git
    repo_subtree_path: site-clienttwo  # ✅ Unique
```

### 8. Forgetting to Re-Provision After Adding New Site

**Problem:** Adding second or third site to config but not re-provisioning server before deployment.

**Symptom:**
- Deployment fails with database connection errors
- Site shows 502 Bad Gateway (no Nginx config)
- SSL certificate missing or invalid
- Directory structure `/srv/www/newsitedomain.com/` doesn't exist

**Why this happens:** When you add a new site to `wordpress_sites.yml`, Trellis doesn't automatically create the infrastructure. You must re-provision to:
- Create MySQL database for the new site
- Generate Nginx virtual host configuration
- Request and install Let's Encrypt SSL certificate
- Create base directory structure

**Solution:** Always re-provision after adding sites to configuration:

```bash
cd trellis

# STEP 1: Add new site to wordpress_sites.yml
# STEP 2: Re-provision to create all infrastructure
trellis provision production

# STEP 3: Now you can deploy the new site
trellis deploy production example.com

# Alternative: Just update Nginx if that's all that changed
# (Use this only if you know the database and other components exist)
ansible-playbook server.yml -e env=production --tags nginx
```

**Best Practice for Multiple Sites:**
Configure all three sites in `wordpress_sites.yml` BEFORE the first provision. This way you provision once and create infrastructure for all sites simultaneously.

### 9. Using Same WordPress Salts Across Sites

**Problem:** Copy-pasting salts from first site to second and third sites.

**Security Risk:** Reduces security isolation between sites.

**Solution:** Generate unique salts for each site:

```bash
# Visit https://roots.io/salts.html three times
# Save each set of salts separately
# Paste unique salts into vault for each site

trellis vault edit production
```

### 10. Not Testing Locally First (When Using Workflow B)

**Problem:** Pushing directly to production without local testing.

**Risk:** Database issues, path problems, or plugin conflicts discovered only in production.

**Solution:** Always test in local development first:

```bash
# Start local VM
trellis vm start

# Import database locally
cd ~/code/trellis-project/site-example
wp db import ~/migrations/site1/database/backup.sql

# Test at https://example.test
# Fix any issues locally before pushing to production
```

### 11. Incorrect Branch Names in Configuration

**Problem:** Configuration uses `branch: main` but Git repo uses `master` (or vice versa).

**Symptom:** Deployment fails with "branch not found" error.

**Solution:** Verify branch name matches your Git repository:

```bash
# Check what branch your repo uses
cd ~/code/trellis-project
git branch

# Update wordpress_sites.yml to match
wordpress_sites:
  example.com:
    branch: main  # or 'master' - must match your repo!
```

### 12. Overwriting Production Database Accidentally

**Problem:** Running database-push playbook and forgetting it will overwrite production.

**Risk:** Loss of production data (orders, users, posts created since migration).

**Solution:** Always use the backup features:

```bash
# The database-push playbook includes automatic backup
# But verify backup exists before running:

# Manual backup before push
ssh admin@server "cd /srv/www/example.com/current && wp db export /tmp/pre-push-backup.sql"

# Then run push
ansible-playbook database-push.yml -e site=example.com -e env=production

# Playbook will create backup automatically in site/database_backup/
```

### Prevention Checklist

Before migrating sites 2 and 3, verify these for each site:

- [ ] Unique `local_path` in `wordpress_sites.yml`
- [ ] Unique database password in vault
- [ ] Unique WordPress salts in vault
- [ ] Unique `repo_subtree_path` (if using same Git repo)
- [ ] Correct branch name (`main` vs `master`)
- [ ] Both development and production configs updated
- [ ] File permissions set correctly after upload
- [ ] Path conversions verified with `wp db search`
- [ ] DNS TTL lowered 24 hours before switching
- [ ] Local testing completed (if using Workflow B)

## Multi-Site Troubleshooting

### Issue: Wrong Site Code Deployed

**Symptom:** After deployment, site shows content or theme from a different site.

**Cause:** Usually due to incorrect `local_path` or `repo_subtree_path` configuration.

**Solution:**

```bash
# Verify configuration
cd trellis
grep -A 10 "example.com:" group_vars/production/wordpress_sites.yml

# Check that:
# 1. local_path points to correct Bedrock directory
# 2. repo_subtree_path matches the directory name in Git

# If incorrect, fix the configuration and redeploy
trellis deploy production example.com
```

### Issue: Database Connection Error on One Site Only

**Symptom:** One site works, but newly added site shows database connection error.

**Cause:** Usually means re-provision wasn't run, so database doesn't exist.

**Solution:**

```bash
# Check if database exists
ssh admin@server
mysql -u root -p -e "SHOW DATABASES;"

# If database is missing, re-provision
cd trellis
trellis provision production

# This will create the missing database
```

### Issue: SSL Certificate Not Created for New Site

**Symptom:** HTTPS doesn't work for newly added site, or shows certificate for wrong domain.

**Cause:** Re-provision wasn't run, or DNS doesn't point to server yet.

**Solution:**

```bash
# Ensure DNS points to your server
dig newsitedomain.com +short

# Re-provision to request SSL certificate
cd trellis
trellis provision production

# Or just update SSL certificates
trellis provision production --tags letsencrypt

# Verify certificate was created
ssh admin@server
sudo certbot certificates
```

### Issue: Site Shows 502 Bad Gateway

**Symptom:** New site shows "502 Bad Gateway" error.

**Cause:** Nginx configuration doesn't exist for this site.

**Solution:**

```bash
# Check if Nginx config exists
ssh admin@server
ls -la /etc/nginx/sites-available/ | grep newsitedomain

# If missing, re-provision
cd trellis
trellis provision production

# If config exists but not enabled, check symlink
ls -la /etc/nginx/sites-enabled/ | grep newsitedomain

# Reload Nginx
sudo systemctl reload nginx
```

### Issue: Confusion About Which Database Belongs to Which Site

**Symptom:** Unsure which database to import data into for multi-site setup.

**Solution:**

Each site gets its own database. The naming convention is:

```
{site_key}_{environment}
```

For example:
```yaml
wordpress_sites:
  example.com:         # site_key is example.com
    # Database will be: example_com_production

  client-two.com:      # site_key is client-two.com
    # Database will be: client_two_com_production
```

**List all databases:**
```bash
ssh admin@server
mysql -u root -p -e "SHOW DATABASES;"
```

**Check which database a site uses:**
```bash
ssh admin@server
cd /srv/www/example.com/current
wp db query "SELECT DATABASE();"
```

## Additional Resources

- [Core Migration Guide](REGULAR-TO-TRELLIS.md) - Single-site migration process
- [Trellis Documentation](https://roots.io/trellis/docs/)
- [Bedrock Documentation](https://roots.io/bedrock/docs/)
- [Roots Discourse Community](https://discourse.roots.io/)

## Need More Help?

- Review the [core migration guide](REGULAR-TO-TRELLIS.md) for detailed migration steps
- Check the main [Migration README](README.md) for other scenarios
- See [Backup Tools](../../trellis/backup/README.md) for data management
- Visit [Provisioning Guide](../../trellis/provision/README.md) for server setup help
