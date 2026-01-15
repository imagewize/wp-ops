#!/bin/bash

# Trellis Site Backup Script
# Complete backup solution for WordPress sites running on Trellis
#
# Usage: ./site-backup.sh [site-name]
# Example: ./site-backup.sh example.com

set -euo pipefail

# Configuration - Update these variables for your setup
SITE_NAME="${1:-example.com}"
SITE_PATH="/srv/www/$SITE_NAME"
BACKUP_ROOT="/srv/backups"
BACKUP_DIR="$BACKUP_ROOT/$SITE_NAME"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if site exists
if [ ! -d "$SITE_PATH" ]; then
    error "Site directory not found: $SITE_PATH"
    exit 1
fi

# Check if WP-CLI is available
if ! command -v wp &> /dev/null; then
    error "WP-CLI not found. Please install WP-CLI."
    exit 1
fi

# Create backup directories
mkdir -p "$BACKUP_DIR"/{database,files,config}

log "Starting backup for $SITE_NAME"
log "Backup location: $BACKUP_DIR"

# Change to WordPress directory
cd "$SITE_PATH/current" || {
    error "Cannot access WordPress directory: $SITE_PATH/current"
    exit 1
}

# 1. Database backup using WP-CLI
log "Backing up database..."
TEMP_SQL="/tmp/db_$DATE.sql"
if wp db export "$TEMP_SQL" --add-drop-table --quiet; then
    tar -czf "$BACKUP_DIR/database/db_$DATE.sql.tar.gz" -C /tmp "db_$DATE.sql"
    rm "$TEMP_SQL"
    log "Database backup completed: db_$DATE.sql.tar.gz"
else
    error "Database backup failed"
    exit 1
fi

# 2. WordPress uploads backup
log "Backing up WordPress uploads..."
if [ -d "$SITE_PATH/shared/uploads" ]; then
    tar -czf "$BACKUP_DIR/files/uploads_$DATE.tar.gz" \
        -C "$SITE_PATH/shared" uploads \
        --exclude=uploads/cache \
        --exclude=uploads/tmp \
        2>/dev/null || warning "Some upload files may have been skipped"
    log "Uploads backup completed: uploads_$DATE.tar.gz"
else
    warning "Uploads directory not found: $SITE_PATH/shared/uploads"
fi

# 3. Configuration files backup
log "Backing up configuration files..."
CONFIG_FILES=()

# Add .env files if they exist
[ -f "$SITE_PATH/current/.env" ] && CONFIG_FILES+=("current/.env")
[ -f "$SITE_PATH/shared/.env" ] && CONFIG_FILES+=("shared/.env")

# Add custom configurations
[ -f "$SITE_PATH/current/web/.htaccess" ] && CONFIG_FILES+=("current/web/.htaccess")
[ -f "$SITE_PATH/current/config/application.php" ] && CONFIG_FILES+=("current/config/application.php")

if [ ${#CONFIG_FILES[@]} -gt 0 ]; then
    tar -czf "$BACKUP_DIR/config/config_$DATE.tar.gz" \
        -C "$SITE_PATH" "${CONFIG_FILES[@]}" \
        2>/dev/null || warning "Some config files may have been skipped"
    log "Configuration backup completed: config_$DATE.tar.gz"
else
    warning "No configuration files found to backup"
fi

# 4. WordPress plugins and themes (excluding default twentytwenty themes)
log "Backing up plugins and themes..."
CONTENT_FILES=()

if [ -d "$SITE_PATH/current/web/app/plugins" ]; then
    CONTENT_FILES+=("current/web/app/plugins")
fi

if [ -d "$SITE_PATH/current/web/app/themes" ]; then
    CONTENT_FILES+=("current/web/app/themes")
fi

if [ -d "$SITE_PATH/current/web/app/mu-plugins" ]; then
    CONTENT_FILES+=("current/web/app/mu-plugins")
fi

if [ ${#CONTENT_FILES[@]} -gt 0 ]; then
    tar -czf "$BACKUP_DIR/files/content_$DATE.tar.gz" \
        -C "$SITE_PATH" "${CONTENT_FILES[@]}" \
        --exclude="*/cache" \
        --exclude="*/node_modules" \
        --exclude="*/.git" \
        2>/dev/null || warning "Some content files may have been skipped"
    log "Content backup completed: content_$DATE.tar.gz"
fi

# 5. Create backup manifest
log "Creating backup manifest..."
cat > "$BACKUP_DIR/manifest_$DATE.txt" << EOF
Backup Manifest for $SITE_NAME
Generated: $(date)
Backup ID: $DATE

Files included:
- Database: db_$DATE.sql.gz
- Uploads: uploads_$DATE.tar.gz
- Configuration: config_$DATE.tar.gz
- Content: content_$DATE.tar.gz

Site Information:
- Site Path: $SITE_PATH
- WordPress Version: $(wp core version --quiet 2>/dev/null || echo "Unknown")
- Active Theme: $(wp theme list --status=active --field=name --quiet 2>/dev/null || echo "Unknown")
- Active Plugins: $(wp plugin list --status=active --field=name --quiet 2>/dev/null | wc -l || echo "Unknown") plugins

Backup Statistics:
$(find "$BACKUP_DIR" -name "*_$DATE.*" -exec ls -lh {} \; | awk '{print "- " $9 ": " $5}')
EOF

# 6. Clean up old backups
log "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED_COUNT=0

for dir in database files config; do
    if [ -d "$BACKUP_DIR/$dir" ]; then
        DELETED=$(find "$BACKUP_DIR/$dir" -name "*.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
        DELETED_COUNT=$((DELETED_COUNT + DELETED))
    fi
done

# Clean up old manifests
MANIFEST_DELETED=$(find "$BACKUP_DIR" -name "manifest_*.txt" -mtime +$RETENTION_DAYS -delete -print | wc -l)
DELETED_COUNT=$((DELETED_COUNT + MANIFEST_DELETED))

if [ $DELETED_COUNT -gt 0 ]; then
    log "Cleaned up $DELETED_COUNT old backup files"
else
    log "No old backup files to clean up"
fi

# 7. Backup summary
log "Backup completed successfully for $SITE_NAME"
log "Backup files created:"
find "$BACKUP_DIR" -name "*_$DATE.*" -exec basename {} \; | sed 's/^/  - /'

# Calculate total backup size
TOTAL_SIZE=$(find "$BACKUP_DIR" -name "*_$DATE.*" -exec du -b {} \; | awk '{sum += $1} END {print sum}')
if [ -n "$TOTAL_SIZE" ]; then
    TOTAL_SIZE_HUMAN=$(numfmt --to=iec --suffix=B $TOTAL_SIZE)
    log "Total backup size: $TOTAL_SIZE_HUMAN"
fi

log "Backup manifest: manifest_$DATE.txt"
log "Backup process completed at $(date)"

exit 0