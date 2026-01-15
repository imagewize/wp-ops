#!/bin/bash

# Set your project slug here like example.com
PROJECT="site.com"

# Paths based on project
PROJECT_DIR=~/code/$PROJECT
TRELLIS_DIR=$PROJECT_DIR/trellis
BACKUP_DIR=~/trellis-backup
TEMP_DIR=~/trellis-temp
DIFF_DIR=~/trellis-diff

# Step 1: Create backup directory
mkdir -p $BACKUP_DIR

# Step 2: Back up the entire current Trellis directory including hidden files
cp -r $TRELLIS_DIR/ $BACKUP_DIR/

# Step 3: Clone fresh Trellis to temporary directory
mkdir -p $TEMP_DIR
cd $TEMP_DIR
git clone git@github.com:roots/trellis.git

# Step 4: Generate diff to see what would change
mkdir -p $DIFF_DIR
diff -rq $TEMP_DIR/trellis/ $TRELLIS_DIR/ > $DIFF_DIR/changes.txt

# Step 5: Remove .git directory from the cloned Trellis to prevent conflicts
rm -rf $TEMP_DIR/trellis/.git

# Step 6: Update Trellis files using rsync with explicit excludes
# Note: Excludes are organized by category:
#   - Secrets & credentials (vault files, .vault_pass)
#   - Git & CI/CD (.git, .github)
#   - Site-specific configs (wordpress_sites.yml, hosts/)
#   - Custom PHP/server settings (main.yml files with php_memory_limit, PHP-FPM settings)
#   - Custom SMTP settings (mail.yml with Brevo/Sendgrid credentials)
#   - Custom deploy hooks (build-before.yml, build-after.yml with memory limits)
#   - CLI config (trellis.cli.yml)
rsync -av --delete \
  --exclude=".vault_pass" \
  --exclude="ansible.cfg" \
  --exclude=".trellis/" \
  --exclude=".git/" \
  --exclude=".github/" \
  --exclude="group_vars/all/vault.yml" \
  --exclude="group_vars/development/vault.yml" \
  --exclude="group_vars/development/wordpress_sites.yml" \
  --exclude="group_vars/production/vault.yml" \
  --exclude="group_vars/production/wordpress_sites.yml" \
  --exclude="group_vars/staging/vault.yml" \
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
  $TEMP_DIR/trellis/ $TRELLIS_DIR/

# Step 6b: Verify critical files were preserved
echo ""
echo "=== Verifying critical files ==="
if [ ! -f "$TRELLIS_DIR/.vault_pass" ]; then
  echo "WARNING: .vault_pass is missing! Restore from backup:"
  echo "  cp $BACKUP_DIR/.vault_pass $TRELLIS_DIR/"
fi
if ! grep -q "vault_password_file" "$TRELLIS_DIR/ansible.cfg" 2>/dev/null; then
  echo "WARNING: ansible.cfg missing vault_password_file! Restore from backup:"
  echo "  cp $BACKUP_DIR/ansible.cfg $TRELLIS_DIR/"
fi
if ! grep -q "smtp-relay.brevo.com\|smtp.sendgrid.net" "$TRELLIS_DIR/group_vars/all/mail.yml" 2>/dev/null; then
  echo "WARNING: mail.yml may have been overwritten with example values! Restore from backup:"
  echo "  cp $BACKUP_DIR/group_vars/all/mail.yml $TRELLIS_DIR/group_vars/all/"
  echo "  Or manually update mail_smtp_server, mail_user, mail_admin, mail_hostname"
fi
for env in all development production staging; do
  if [ ! -f "$TRELLIS_DIR/group_vars/$env/vault.yml" ]; then
    echo "WARNING: group_vars/$env/vault.yml is missing! Restore from backup:"
    echo "  cp $BACKUP_DIR/group_vars/$env/vault.yml $TRELLIS_DIR/group_vars/$env/"
  fi
done
echo "=== Verification complete ==="

# Step 7: Clean up temporary directory
# rm -rf $TEMP_DIR

# Step 8: Return to project directory
# cd $PROJECT_DIR

# Step 9: Check status of changes
# git status

# Step 10: Review diff of changes
# git diff trellis/

# Step 11: Add changes if everything looks good
# git add trellis/

# Step 12: Commit the changes
# git commit -m "Update Trellis to latest version while preserving custom configurations"
