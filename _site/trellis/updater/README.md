# Trellis Updater

A Bash script to safely update your [Roots Trellis](https://roots.io/trellis/) installation while preserving your custom configurations.

## Chapter Purpose

This chapter walks through updating Trellis while keeping your project-specific settings intact.

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

## Post-Upgrade Manual Review

After upgrading, you should manually review and potentially merge changes from the new Trellis version:

1. **Role template changes** - Check if upstream changed any templates you've customized:
   - `roles/mariadb/templates/` - If you added custom MariaDB settings
   - `roles/wordpress-setup/templates/` - If you modified PHP-FPM pool templates

2. **New variables** - Check upstream `main.yml` files for new useful variables you may want to adopt

3. **Galaxy roles** - Run `ansible-galaxy install -r galaxy.yml` to update dependencies

## Usage

1. Edit the script to set your project slug:
```bash
# Set your project slug here like example.com
PROJECT="your-site-name"
```

2. Make the script executable:
```bash
chmod +x updates/trellis-updater.sh
```

3. Run the script:
```bash
./updates/trellis-updater.sh
```

4. Review the changes in your Git repository before pushing them.

## Troubleshooting & Tips

### Backup Directory Issues
The script uses `~/trellis-backup/` by default. If you get errors like `mkdir: : No such file or directory`, ensure you're using absolute paths in the script variables.

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
