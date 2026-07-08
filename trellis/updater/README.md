# Trellis Updater

A Bash script to safely update your [Roots Trellis](https://roots.io/trellis/) installation while preserving your custom configurations.

## Features

- Creates a backup of your current Trellis directory
- Downloads the latest version of Trellis
- Generates a diff to see what would change
- Updates your Trellis files while preserving important configurations:
  - Vault files with passwords and sensitive data
  - WordPress site configurations
  - User configurations
  - Host configurations
  - Trellis CLI configuration
- Commits changes to your Git repository

## What This Script Preserves

The updater script specifically preserves the following files/directories:

### Secrets & Credentials
- `.vault_pass` - Vault password file
- `ansible.cfg` - Contains `vault_password_file` setting (CRITICAL!)
- `group_vars/all/vault.yml`
- `group_vars/development/vault.yml`
- `group_vars/production/vault.yml`
- `group_vars/staging/vault.yml`

### Git & CI/CD
- `.git/`
- `.github/`
- `.trellis/`

### Site-Specific Configurations
- `group_vars/development/wordpress_sites.yml`
- `group_vars/production/wordpress_sites.yml`
- `group_vars/staging/wordpress_sites.yml`
- `group_vars/all/users.yml`
- `hosts/` directory
- `trellis.cli.yml`

### Custom PHP/Server Settings
- `group_vars/all/main.yml` - PHP memory limits, timezone, etc.
- `group_vars/production/main.yml` - PHP-FPM pool settings, MariaDB config
- `group_vars/staging/main.yml` - Environment-specific overrides
- `group_vars/development/main.yml` - Development settings

### Custom SMTP Settings
- `group_vars/all/mail.yml` - SMTP server configuration (Brevo/Sendgrid credentials)

### Custom Deploy Hooks
- `deploy-hooks/` - Custom deployment scripts (e.g., memory limits for wp acorn)

### Custom Ansible Playbooks
- `database-backup.yml`, `database-pull.yml`, `database-push.yml` - Database management
- `files-backup.yml`, `files-pull.yml`, `files-push.yml` - Uploads management
- `uploads.yml` - Uploads sync playbook

### Custom Nginx Configurations
- `nginx-includes/` - Custom Nginx configs (SEO redirects, asset expiry, security rules)

### Custom Documentation
- `docs/` - Project-specific documentation
- `CHANGELOG.md` - Trellis upgrade changelog
- `CHANGELOG-TRELLIS-DATABASE-UPLOADS-MIGRATION.md` - Migration notes

## Post-Upgrade Manual Review

After upgrading, you should manually review and potentially merge changes from the new Trellis version:

1. **Role template changes** - Check if upstream changed any templates you've customized:
   - `roles/mariadb/templates/` - If you added custom MariaDB settings
   - `roles/wordpress-setup/templates/` - If you modified PHP-FPM pool templates

2. **New variables** - Check upstream `main.yml` files for new useful variables you may want to adopt

3. **Galaxy roles** - Run `ansible-galaxy install -r galaxy.yml` to update dependencies

## Prerequisites

- Ansible 2.10+ (check with `ansible --version`)
- Git access to roots/trellis repository
- Backup of your current Trellis configuration (script creates this automatically)

## Usage

1. **Fetch latest upstream changes** (if using upstream remote):
```bash
cd ~/code/your-site-name
git fetch upstream  # Assuming you have upstream remote configured
git log HEAD..upstream/master | head -20  # Review what's new
```

2. **Edit the script to set your project slug**:
```bash
# Open the script and update line 4
PROJECT="your-site-name"  # e.g., "example.com"
```

3. **Make the script executable** (first time only):
```bash
chmod +x trellis-updater.sh
```

4. **Run the updater script**:
```bash
./trellis-updater.sh
```

5. **Review the changes**:
```bash
# Check diff summary
cat ~/trellis-diff/changes.txt

# Review detailed changes
cd ~/code/your-site-name
git status
git diff trellis/

# Check specific files
git diff trellis/requirements.txt
git diff trellis/CHANGELOG.md
```

6. **Update Ansible Galaxy roles**:
```bash
cd ~/code/your-site-name/trellis
ansible-galaxy install -r galaxy.yml --force
```

7. **Test in development** (if applicable):
```bash
# Quick VM test (if VM is running)
trellis vm shell --workdir /srv/www/yoursite.com/current -- wp --version --path=web/wp

# Or full provision (takes longer)
# trellis provision development
```

8. **Commit the changes**:
```bash
git add trellis/
git commit -m "Update Trellis to latest version

- Fetch upstream changes from roots/trellis
- Preserve custom configurations (vault, wordpress_sites, PHP settings, SMTP)
- Update Galaxy roles
- Tested in development environment"

git push origin main
```

## What Changed in This Version

**Script Improvements (2026-02-09)**:
- ✅ Added timestamped backups (`~/trellis-backup-YYYYMMDD_HHMMSS`)
- ✅ Added error handling (`set -e`)
- ✅ Added project directory validation
- ✅ Added progress messages with checkmarks
- ✅ Improved diff handling (won't fail on differences)
- ✅ Added `--depth 1` to git clone (faster)
- ✅ Added comprehensive summary with next steps
- ✅ Added automatic cleanup of existing temp directories

## Troubleshooting & Tips

### Ansible Version Compatibility
Recent Trellis versions support Ansible 2.10+ and have removed the `ansible-core<2.19.0` constraint. If you're upgrading from an older Trellis version:

```bash
# Check your Ansible version
ansible --version

# Expected: ansible-core 2.10.0 or higher
# Note: Homebrew ansible 13.x includes ansible-core 2.20.x (compatible)
```

### Backup Directory Issues
The script now uses timestamped backups (`~/trellis-backup-YYYYMMDD_HHMMSS/`). Each run creates a new backup, so you can safely run multiple times without overwriting previous backups.

### MariaDB Template Customizations
The rsync command will overwrite role templates. If you have customizations in:
- `roles/mariadb/templates/50-server.cnf.j2` (e.g., `max_allowed_packet`, `max_connections`)
- `roles/wordpress-setup/templates/php-fpm-pool-wordpress.conf.j2`

You'll need to re-apply them after the upgrade. Check with:
```bash
git diff trellis/roles/mariadb/templates/50-server.cnf.j2
```

### Testing Without Full Provision
Instead of running `trellis provision development` (which takes time), you can verify the upgrade works with quick VM checks:
```bash
# If VM is already running
trellis vm shell --workdir /srv/www/yoursite.com/current -- wp --version --path=web/wp
trellis vm shell --workdir /srv/www/yoursite.com/current -- wp db check --path=web/wp
```

### Galaxy Roles
Always use `--force` flag when updating Galaxy roles after an upgrade:
```bash
ansible-galaxy install -r galaxy.yml --force
```

### Diff Review Tips
The generated diff at `~/trellis-diff/changes.txt` shows file-level changes. For detailed line-by-line review:
```bash
git diff trellis/
```

Look specifically for:
- New roles (e.g., `roles/redis/` in v1.26.0+)
- Changed defaults in `roles/*/defaults/main.yml`
- Template changes that might conflict with your customizations

### Vault Password / Provision Failures
If you see "Attempting to decrypt but no vault secrets found" when running `trellis provision`:

1. **Check `.vault_pass` exists:**
   ```bash
   ls -la ~/code/yoursite.com/trellis/.vault_pass
   ```

2. **Check `ansible.cfg` has vault setting:**
   ```bash
   grep vault_password_file ~/code/yoursite.com/trellis/ansible.cfg
   ```
   Should show: `vault_password_file = .vault_pass`

3. **Check vault.yml files exist:**
   ```bash
   ls -la ~/code/yoursite.com/trellis/group_vars/*/vault.yml
   ```

4. **Restore from backup if missing:**
   ```bash
   cp ~/trellis-backup/.vault_pass ~/code/yoursite.com/trellis/
   cp ~/trellis-backup/ansible.cfg ~/code/yoursite.com/trellis/
   cp ~/trellis-backup/group_vars/*/vault.yml ~/code/yoursite.com/trellis/group_vars/*/
   ```

## Requirements

- Git
- Bash
- rsync

## License

MIT License. See [LICENSE.md](../../LICENSE.md) for details.