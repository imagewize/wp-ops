#!/bin/bash

# Trellis Database Backup Script
# Focused database backup using WP-CLI for WordPress sites on Trellis
#
# Runs on the server: it reads /srv/www/<site-name> and writes to
# /srv/backups/<site-name>/database, so both paths have to be the host's own.
# Stream it over SSH the same way as the monitoring scripts — nothing needs to
# be installed on the server.
#
# Usage:
#   ssh web@example.com 'bash -s' < ./db-backup.sh [site-name] [backup-type]
#   ./db-backup.sh example.com production     # on the server itself
#
# Backup types: production, staging, development
#
# staging and development additionally produce a second dump with the site URL
# rewritten for that environment; production produces the plain dump only.
#
# @desc     Back up a Trellis site database with WP-CLI, gzip it, and prune backups older than 30 days
# @category backup
# @runs     server
# @requires wp
# @arg      site-name    optional  {example.com}  Site directory under /srv/www
# @arg      backup-type  optional  {production|staging|development}  Backup type
# @example  ssh web@example.com 'bash -s' < db-backup.sh example.com production
# @doc      trellis/backup/README.md

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $(basename "$0") [site-name] [backup-type]"
    echo ""
    echo "Back up a Trellis site database with WP-CLI, gzip it, write a summary"
    echo "file alongside it, and prune backups older than 30 days."
    echo ""
    echo "Arguments:"
    echo "  site-name    Site directory under /srv/www (default: example.com)"
    echo "  backup-type  production | staging | development (default: production)"
    echo ""
    echo "Runs on the server — /srv/www and /srv/backups are the host's paths."
    echo "From your machine:"
    echo "  ssh web@example.com 'bash -s' < $(basename "$0") example.com production"
    echo ""
    echo "Writes to /srv/backups/<site-name>/database/ on the server. To pull a"
    echo "copy down to your machine instead, use the Ansible playbook:"
    echo "  wp-ops trellis/backup/database-pull -e site=example.com -e env=production"
    exit 0
fi

# Configuration
SITE_NAME="${1:-example.com}"
BACKUP_TYPE="${2:-production}"
SITE_PATH="/srv/www/$SITE_NAME"
BACKUP_DIR="/srv/backups/$SITE_NAME/database"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Validate inputs
if [ ! -d "$SITE_PATH" ]; then
    error "Site directory not found: $SITE_PATH"
    exit 1
fi

if ! command -v wp &> /dev/null; then
    error "WP-CLI not found. Please install WP-CLI."
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Change to WordPress directory
cd "$SITE_PATH/current" || {
    error "Cannot access WordPress directory: $SITE_PATH/current"
    exit 1
}

log "Starting database backup for $SITE_NAME ($BACKUP_TYPE environment)"

# Check if WordPress is installed
if ! wp core is-installed --quiet; then
    error "WordPress is not properly installed in $SITE_PATH/current"
    exit 1
fi

# Get database info
DB_NAME=$(wp config get DB_NAME --quiet)
DB_SIZE=$(wp db size --size_format=human --quiet)
log "Database: $DB_NAME ($DB_SIZE)"

# Perform database backup
BACKUP_FILE="$BACKUP_DIR/${BACKUP_TYPE}_db_$DATE.sql"
log "Creating database backup..."

if wp db export "$BACKUP_FILE" \
    --add-drop-table \
    --single-transaction \
    --default-character-set=utf8mb4 \
    --quiet; then

    # Compress the backup using gzip (optimal for single file)
    gzip "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.gz"

    BACKUP_SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    log "Database backup completed: $(basename "$BACKUP_FILE") ($BACKUP_SIZE)"
else
    error "Database backup failed"
    exit 1
fi

# Create additional backup with URL replacement for staging/development
if [ "$BACKUP_TYPE" != "production" ]; then
    log "Creating backup with URL replacement for $BACKUP_TYPE environment..."

    # Define URL mappings
    case "$BACKUP_TYPE" in
        "staging")
            PROD_URL=$(wp option get home --quiet)
            STAGING_URL=$(echo "$PROD_URL" | sed 's/\.com/.staging.com/g')
            ;;
        "development")
            PROD_URL=$(wp option get home --quiet)
            DEV_URL=$(echo "$PROD_URL" | sed 's/https\?:\/\/[^\/]*/http:\/\/'"${SITE_NAME%.*}"'.test/g')
            ;;
    esac

    if [ -n "${STAGING_URL:-}" ] || [ -n "${DEV_URL:-}" ]; then
        REPLACEMENT_FILE="$BACKUP_DIR/${BACKUP_TYPE}_db_with_urls_$DATE.sql"
        TARGET_URL="${STAGING_URL:-$DEV_URL}"

        if wp db export "$REPLACEMENT_FILE" \
            --add-drop-table \
            --single-transaction \
            --default-character-set=utf8mb4 \
            --quiet; then

            # Perform URL replacement
            wp search-replace "$PROD_URL" "$TARGET_URL" \
                --dry-run \
                --quiet > /dev/null && \
            wp search-replace "$PROD_URL" "$TARGET_URL" \
                --skip-columns=guid \
                --quiet

            # Export again with replaced URLs
            wp db export "$REPLACEMENT_FILE" \
                --add-drop-table \
                --single-transaction \
                --default-character-set=utf8mb4 \
                --quiet

            gzip "$REPLACEMENT_FILE"
            log "URL-replaced backup created: $(basename "$REPLACEMENT_FILE.gz")"

            # Restore original URLs
            wp search-replace "$TARGET_URL" "$PROD_URL" \
                --skip-columns=guid \
                --quiet
        fi
    fi
fi

# Create backup info file
INFO_FILE="$BACKUP_DIR/backup_info_$DATE.txt"
cat > "$INFO_FILE" << EOF
Database Backup Information
==========================
Site: $SITE_NAME
Environment: $BACKUP_TYPE
Date: $(date)
WordPress Version: $(wp core version --quiet)

Database Information:
- Name: $DB_NAME
- Size: $DB_SIZE
- Tables: $(wp db query "SHOW TABLES;" --skip-column-names --quiet | wc -l)
- Charset: $(wp config get DB_CHARSET --quiet)

Backup Files:
- Main backup: $(basename "$BACKUP_FILE")
EOF

if [ -f "$BACKUP_DIR/${BACKUP_TYPE}_db_with_urls_$DATE.sql.gz" ]; then
    echo "- URL-replaced backup: ${BACKUP_TYPE}_db_with_urls_$DATE.sql.gz" >> "$INFO_FILE"
fi

echo "" >> "$INFO_FILE"
echo "File sizes:" >> "$INFO_FILE"
find "$BACKUP_DIR" -name "*_$DATE.*" -exec ls -lh {} \; | awk '{print "- " $9 ": " $5}' >> "$INFO_FILE"

# Clean up old backups
log "Cleaning up old database backups (older than $RETENTION_DAYS days)..."
DELETED_COUNT=$(find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
INFO_DELETED=$(find "$BACKUP_DIR" -name "backup_info_*.txt" -mtime +$RETENTION_DAYS -delete -print | wc -l)
TOTAL_DELETED=$((DELETED_COUNT + INFO_DELETED))

if [ $TOTAL_DELETED -gt 0 ]; then
    log "Cleaned up $TOTAL_DELETED old backup files"
else
    log "No old backup files to clean up"
fi

# Final summary
log "Database backup completed successfully"
log "Backup location: $BACKUP_DIR"
log "Info file: $(basename "$INFO_FILE")"

# Show recent backups
log "Recent database backups:"
find "$BACKUP_DIR" -name "*.sql.gz" -mtime -7 -exec ls -lh {} \; | \
    awk '{print "  " $6 " " $7 " " $8 " - " $9 " (" $5 ")"}' | \
    sort -r

exit 0