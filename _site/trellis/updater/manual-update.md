# Step 1: Create backup directory
First, create a directory to store your backup for safety:

```bash
mkdir -p ~/trellis-backup
```

# Step 2: Back up the entire current trellis directory including hidden files
Copy your entire existing Trellis setup to the backup location, preserving all permissions and hidden files:

```bash
cp -ra ~/code/website.com/trellis/ ~/trellis-backup/
```

# Step 3: Clone fresh Trellis to temporary directory
Create a temporary directory and clone the latest version of Trellis from the official repository:

```bash
mkdir -p ~/trellis-temp
cd ~/trellis-temp
git clone git@github.com:roots/trellis.git
```

# Step 4: Generate diff to see what would change
Compare the fresh clone with your existing setup to understand what changes would be made:

```bash
mkdir -p ~/trellis-diff
diff -rq ~/trellis-temp/trellis/ ~/code/website.com/trellis/ > ~/trellis-diff/changes.txt
```

# Step 5: Remove .git directory from the cloned Trellis to prevent conflicts
Delete the Git repository information from the fresh clone to prevent conflicts during the update:

```bash
rm -rf ~/trellis-temp/trellis/.git
```

# Step 6: Update Trellis files using rsync with explicit excludes
Copy all new files to your existing Trellis setup, while carefully excluding your custom configurations and sensitive files:

```bash
rsync -av \
  --exclude=".vault_pass" \
  --exclude="ansible.cfg" \
  --exclude=".trellis/" \
  --exclude=".git/" \
  --exclude=".github/" \
  --exclude="group_vars/all/vault.yml" \
  --exclude="group_vars/development/vault.yml" \
  --exclude="group_vars/production/vault.yml" \
  --exclude="group_vars/staging/vault.yml" \
  --exclude="group_vars/development/wordpress_sites.yml" \
  --exclude="group_vars/production/wordpress_sites.yml" \
  --exclude="group_vars/staging/wordpress_sites.yml" \
  --exclude="group_vars/all/users.yml" \
  --exclude="group_vars/all/main.yml" \
  --exclude="group_vars/all/mail.yml" \
  --exclude="group_vars/production/main.yml" \
  --exclude="group_vars/staging/main.yml" \
  --exclude="group_vars/development/main.yml" \
  --exclude="deploy-hooks/" \
  --exclude="trellis.cli.yml" \
  --exclude="hosts/" \
  ~/trellis-temp/trellis/ ~/code/website.com/trellis/
```

**Note:** The excluded files contain your custom configurations:
- `main.yml` files: PHP/server settings (memory limits, PHP-FPM pool config, MariaDB settings)
- `mail.yml`: SMTP server configuration (Brevo/Sendgrid credentials)
- `deploy-hooks/`: Custom deployment scripts
These are excluded to preserve your customizations.

# Step 7: Clean up temporary directory
Remove the temporary directory as it's no longer needed:

```bash
rm -rf ~/trellis-temp
```

# Step 8: Return to project directory
Navigate back to your main project directory:

```bash
cd ~/code/website.com
```

# Step 9: Check status of changes
Review what files have changed in your Git repository:

```bash
git status
```

# Step 10: Review diff of changes
Examine the specific changes made to your Trellis files:

```bash
git diff trellis/
```

# Step 11: Add changes if everything looks good
Stage the updated files for committing:

```bash
git add trellis/
```

# Step 12: Commit the changes
Save the changes with a descriptive commit message:

```bash
git commit -m "Update Trellis to latest version while preserving custom configurations"