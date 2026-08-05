#!/bin/bash

# Trellis Database Backup Script
# Back up a remote site's database over SSH, straight to your machine.
#
# Runs on your machine — no /srv/backups involved. A stock Trellis box
# provisions and chowns /srv/www, never /srv/backups itself, so the old
# server-side version of this script (which wrote there) failed with a
# permission error on every site's first run. This version never touches
# that path: it SSHes into the site's own web dir (already web-user-writable
# since Trellis deploys there), runs `wp db export` over that connection, and
# gzips the stream straight into a local database_backup/ directory. No
# remote temp file, so nothing needs cleaning up on the server either.
#
# Usage:
#   ./db-backup.sh [site-name] [environment] [options]
#   wp-ops db-backup example.com production
#
# Options:
#   --host HOST   SSH host to back up from (default: site-name)
#   --dest DIR    Local destination directory (default: database_backup)
#
# @desc     Back up a remote site's database over SSH straight to your machine
# @category backup
# @platform trellis
# @runs     local
# @requires ssh
# @arg      site-name    optional  {example.com}  Site name under /srv/www, as in wordpress_sites.yml
# @arg      environment  optional  {production|staging}  Remote environment to back up
# @flag     --host       optional  {example.com}  SSH host to back up from (default: site-name)
# @flag     --dest       optional  {database_backup}  Local destination directory
# @example  wp-ops db-backup example.com production
# @doc      trellis/backup/README.md

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [site-name] [environment] [options]"
    echo ""
    echo "Back up a remote site's database over SSH, straight to your machine."
    echo "Streams 'wp db export' over the SSH connection and gzips it locally —"
    echo "no file is ever written to the server."
    echo ""
    echo "Arguments:"
    echo "  site-name    Site name under /srv/www, as in wordpress_sites.yml (default: example.com)"
    echo "  environment  production | staging (default: production) — used for messaging only"
    echo ""
    echo "Options:"
    echo "  --host HOST  SSH host to back up from (default: site-name)"
    echo "  --dest DIR   Local destination directory (default: database_backup)"
    echo ""
    echo "Backing up development? It's already local — just run:"
    echo "  wp db export --path=web/wp"
    echo ""
    echo "For automated/repeatable backups instead, use the Ansible playbook:"
    echo "  wp-ops database-backup example.com production"
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2; }
warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }

# Parse arguments
POSITIONAL=()
REMOTE_HOST=""
DEST_DIR="database_backup"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --host)
            REMOTE_HOST="${2:-}"
            shift 2
            ;;
        --dest)
            DEST_DIR="${2:-}"
            shift 2
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

SITE_NAME="${POSITIONAL[0]:-example.com}"
ENVIRONMENT="${POSITIONAL[1]:-production}"
REMOTE_HOST="${REMOTE_HOST:-$SITE_NAME}"

if [[ "$ENVIRONMENT" == "development" ]]; then
    error "development is already local — no SSH hop needed. Run this instead:"
    echo "  wp db export --path=web/wp" >&2
    exit 1
fi

REMOTE_PATH="/srv/www/${SITE_NAME}/current"
WP_PATH="web/wp"
DATE=$(date +%Y_%m_%d_%H_%M_%S)
BACKUP_FILE="${SITE_NAME//./_}_${ENVIRONMENT}_${DATE}.sql.gz"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Database Backup: ${SITE_NAME} (${ENVIRONMENT})${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "  Remote: web@${REMOTE_HOST}:${REMOTE_PATH}"
echo -e "  Local:  ${DEST_DIR}/${BACKUP_FILE}"
echo ""

mkdir -p "$DEST_DIR"

log "Exporting ${ENVIRONMENT} database from ${REMOTE_HOST}..."
if ! ssh -o StrictHostKeyChecking=no "web@${REMOTE_HOST}" \
    "cd ${REMOTE_PATH} && wp db export - --path=${WP_PATH}" | gzip > "${DEST_DIR}/${BACKUP_FILE}"; then
    error "Database export failed."
    rm -f "${DEST_DIR}/${BACKUP_FILE}"
    exit 1
fi

BACKUP_SIZE=$(ls -lh "${DEST_DIR}/${BACKUP_FILE}" | awk '{print $5}')
log "Backup complete: ${DEST_DIR}/${BACKUP_FILE} (${BACKUP_SIZE})"

# Prune this site's old local backups (default 30 days), same as the old
# server-side script did for /srv/backups.
RETENTION_DAYS=30
DELETED_COUNT=$(find "$DEST_DIR" -name "${SITE_NAME//./_}_*.sql.gz" -mtime "+${RETENTION_DAYS}" -delete -print | wc -l | tr -d ' ')
if [[ "$DELETED_COUNT" -gt 0 ]]; then
    log "Cleaned up ${DELETED_COUNT} old backup(s) older than ${RETENTION_DAYS} days."
fi

exit 0
