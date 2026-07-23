#!/bin/bash
set -e  # Exit on error

# Set your project slug here like example.com
PROJECT="site.com"

# Paths based on project
PROJECT_DIR=~/code/$PROJECT
TRELLIS_DIR=$PROJECT_DIR/trellis
BACKUP_DIR=~/trellis-backup-$(date +%Y%m%d_%H%M%S)
TEMP_DIR=~/trellis-temp
DIFF_DIR=~/trellis-diff

# Verify project exists
if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: Project directory not found: $PROJECT_DIR"
  echo "Please update the PROJECT variable in this script"
  exit 1
fi

echo "=== Trellis Updater for $PROJECT ==="
echo "Project: $PROJECT_DIR"
echo "Backup: $BACKUP_DIR"
echo ""

# Step 1: Create backup directory
mkdir -p $BACKUP_DIR

# Step 2: Back up the entire current Trellis directory including hidden files
echo "=== Backing up current Trellis directory ==="
cp -r $TRELLIS_DIR/ $BACKUP_DIR/
echo "✓ Backup created at: $BACKUP_DIR"
echo ""

# Step 3: Clone fresh Trellis to temporary directory
echo "=== Cloning latest Trellis from GitHub ==="
mkdir -p $TEMP_DIR
cd $TEMP_DIR
if [ -d "trellis" ]; then
  echo "Removing existing temp directory..."
  rm -rf trellis
fi
git clone --depth 1 git@github.com:roots/trellis.git
echo "✓ Latest Trellis cloned"
echo ""

# Step 4: Generate diff to see what would change
echo "=== Generating diff of changes ==="
mkdir -p $DIFF_DIR
diff -rq $TEMP_DIR/trellis/ $TRELLIS_DIR/ > $DIFF_DIR/changes.txt || true
echo "✓ Diff saved to: $DIFF_DIR/changes.txt"
echo ""

# Step 5: Remove .git directory from the cloned Trellis to prevent conflicts
echo "=== Preparing fresh Trellis for sync ==="
rm -rf $TEMP_DIR/trellis/.git
echo "✓ Removed .git directory from cloned Trellis"
echo ""

# Step 6: Update Trellis files using rsync with explicit excludes
echo "=== Syncing Trellis updates while preserving custom configurations ==="
# Note: Excludes are organized by category:
#   - Secrets & credentials (vault files, .vault_pass)
#   - Git & CI/CD (.git, .github)
#   - Site-specific configs (wordpress_sites.yml, hosts/)
#   - Custom PHP/server settings (main.yml files with php_memory_limit, PHP-FPM settings)
#   - Custom SMTP settings (mail.yml with Brevo/Sendgrid credentials)
#   - Custom deploy hooks (build-before.yml, build-after.yml with memory limits)
#   - CLI config (trellis.cli.yml)
#   - Custom Ansible playbooks (database-*.yml, files-*.yml, uploads.yml)
#   - Custom Nginx configs (nginx-includes/)
#   - Custom documentation (docs/, CHANGELOG.md)
#   - Custom role templates (php-fpm-pool with request_terminate_timeout)
#   - Custom Nginx config (nginx.conf.j2 with rate limiting zone)
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
  --exclude="group_vars/all/security.yml" \
  --exclude="group_vars/production/main.yml" \
  --exclude="group_vars/staging/main.yml" \
  --exclude="group_vars/development/main.yml" \
  --exclude="deploy-hooks/" \
  --exclude="trellis.cli.yml" \
  --exclude="hosts/" \
  --exclude="database-backup.yml" \
  --exclude="database-pull.yml" \
  --exclude="database-push.yml" \
  --exclude="files-backup.yml" \
  --exclude="files-pull.yml" \
  --exclude="files-push.yml" \
  --exclude="uploads.yml" \
  --exclude="nginx-includes/" \
  --exclude="docs/" \
  --exclude="CHANGELOG.md" \
  --exclude="CHANGELOG-TRELLIS-DATABASE-UPLOADS-MIGRATION.md" \
  --exclude="roles/wordpress-setup/templates/php-fpm-pool-wordpress.conf.j2" \
  --exclude="roles/nginx/templates/nginx.conf.j2" \
  $TEMP_DIR/trellis/ $TRELLIS_DIR/

echo "✓ Trellis files updated"

# Step 6b: Diff excluded files against upstream to catch missed updates
echo ""
echo "=== Checking excluded files for upstream changes ==="
EXCLUDED_FILES=(
  "ansible.cfg"
  "group_vars/all/main.yml"
  "group_vars/all/mail.yml"
  "group_vars/all/security.yml"
  "group_vars/all/users.yml"
  "group_vars/production/main.yml"
  "group_vars/staging/main.yml"
  "group_vars/development/main.yml"
  "group_vars/development/wordpress_sites.yml"
  "group_vars/production/wordpress_sites.yml"
  "group_vars/staging/wordpress_sites.yml"
  "roles/wordpress-setup/templates/php-fpm-pool-wordpress.conf.j2"
  "roles/nginx/templates/nginx.conf.j2"
)

UPSTREAM_CHANGES_DIR=$DIFF_DIR/excluded-file-diffs
mkdir -p $UPSTREAM_CHANGES_DIR
UPSTREAM_CHANGE_COUNT=0

for file in "${EXCLUDED_FILES[@]}"; do
  UPSTREAM="$TEMP_DIR/trellis/$file"
  LOCAL="$TRELLIS_DIR/$file"

  # Skip files that don't exist upstream (our custom additions)
  if [ ! -f "$UPSTREAM" ]; then
    continue
  fi

  # Skip files that don't exist locally yet
  if [ ! -f "$LOCAL" ]; then
    echo "  NEW upstream: $file (not present locally)"
    cp "$UPSTREAM" "$UPSTREAM_CHANGES_DIR/$(echo $file | tr '/' '_').new"
    UPSTREAM_CHANGE_COUNT=$((UPSTREAM_CHANGE_COUNT + 1))
    continue
  fi

  # Generate diff if files differ
  if ! diff -q "$UPSTREAM" "$LOCAL" > /dev/null 2>&1; then
    diff -u "$LOCAL" "$UPSTREAM" > "$UPSTREAM_CHANGES_DIR/$(echo $file | tr '/' '_').diff" || true
    echo "  CHANGED upstream: $file"
    UPSTREAM_CHANGE_COUNT=$((UPSTREAM_CHANGE_COUNT + 1))
  fi
done

if [ "$UPSTREAM_CHANGE_COUNT" -eq 0 ]; then
  echo "✓ No upstream changes in excluded files"
else
  echo ""
  echo "⚠ $UPSTREAM_CHANGE_COUNT excluded file(s) have upstream changes."
  echo "  Diffs saved to: $UPSTREAM_CHANGES_DIR/"
  echo "  Review these diffs to cherry-pick upstream fixes without losing customizations."
  echo "  Tip: ask Claude Code to review the diffs in $UPSTREAM_CHANGES_DIR/"
fi
echo ""

# Step 6c: Verify critical files were preserved
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
if ! grep -q 'wordpress_wp_login' "$TRELLIS_DIR/group_vars/all/security.yml" 2>/dev/null || \
   grep -A3 'wordpress_wp_login' "$TRELLIS_DIR/group_vars/all/security.yml" | grep -q 'enabled: "false"'; then
  echo "WARNING: security.yml fail2ban wordpress_wp_login jail may be disabled! Verify:"
  echo "  grep -A5 'wordpress_wp_login' $TRELLIS_DIR/group_vars/all/security.yml"
  echo "  It should be: enabled: \"true\""
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
echo "✓ All critical files verified"
echo "=== Verification complete ==="
echo ""

# Step 7: Show summary
echo "=== Update Summary ==="
echo "Next steps:"
echo "1. Review changes: cd $PROJECT_DIR && git diff trellis/"
echo "2. Check diff summary: cat $DIFF_DIR/changes.txt"
echo "3. Review excluded file diffs: ls $DIFF_DIR/excluded-file-diffs/"
echo "   (or ask Claude Code to review them for upstream fixes you should merge)"
echo "4. Update Galaxy roles: cd $TRELLIS_DIR && ansible-galaxy install -r galaxy.yml --force"
echo "5. Test in development (if applicable)"
echo "6. Commit changes: git add trellis/ && git commit -m 'Update Trellis to latest version'"
echo ""
echo "Backup location: $BACKUP_DIR"
echo "Temp directory: $TEMP_DIR (manually remove when done)"
echo ""

# Step 8: Return to project directory
cd $PROJECT_DIR

# Commented out: Manual steps for user to review and execute
# git status
# git diff trellis/
# git add trellis/
# git commit -m "Update Trellis to latest version while preserving custom configurations"
# cd trellis && ansible-galaxy install -r galaxy.yml --force
