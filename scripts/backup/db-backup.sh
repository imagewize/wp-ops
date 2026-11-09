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
#   --keep-days N Prune this site+environment's backups older than N days (default: 180)
#   --keep-min N  Never prune the newest N backups, whatever their age (default: 10)
#   --no-prune    Keep every backup
#
# @desc     Back up a remote site's database over SSH straight to your machine (shell, no Ansible)
# @category backup
# @platform trellis
# @runs     local
# @requires ssh
# @arg      site-name    optional  {example.com}  Site name under /srv/www, as in wordpress_sites.yml
# @arg      environment  optional  {production|staging}  Remote environment to back up
# @flag     --host       optional  {example.com}  SSH host to back up from (default: site-name)
# @flag     --dest       optional  {database_backup}  Local destination directory
# @flag     --keep-days  optional  {180}  Prune this site+environment's backups older than N days
# @flag     --keep-min   optional  {10}  Never prune the newest N backups, whatever their age
# @flag     --no-prune   optional  {}  Keep every backup
# @example  wp-ops db-backup example.com production

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
    echo "  --keep-days N  Prune this site+environment's backups older than N days (default: 180)"
    echo "  --keep-min N   Never prune the newest N backups, whatever their age (default: 10)"
    echo "  --no-prune     Keep every backup"
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
KEEP_DAYS=180
KEEP_MIN=10
PRUNE=true

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
        --keep-days)
            KEEP_DAYS="${2:-}"
            shift 2
            ;;
        --keep-min)
            KEEP_MIN="${2:-}"
            shift 2
            ;;
        --no-prune)
            PRUNE=false
            shift
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

for n in "$KEEP_DAYS" "$KEEP_MIN"; do
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        error "--keep-days and --keep-min take a whole number of days/backups (got '${n}')."
        exit 1
    fi
done

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

# A dropped SSH connection can leave a gzip stream that is valid but cut
# short, so check both the archive and mysqldump's closing footer before
# calling it a backup (and, below, before pruning anything on its strength).
if ! gzip -t "${DEST_DIR}/${BACKUP_FILE}" 2>/dev/null; then
    error "Backup is not a valid gzip archive: ${DEST_DIR}/${BACKUP_FILE}"
    exit 1
fi
if ! gzip -dc "${DEST_DIR}/${BACKUP_FILE}" | tail -n 3 | grep -q -- '-- Dump completed'; then
    error "Backup has no '-- Dump completed' footer — the export was cut short: ${DEST_DIR}/${BACKUP_FILE}"
    exit 1
fi

BACKUP_SIZE=$(ls -lh "${DEST_DIR}/${BACKUP_FILE}" | awk '{print $5}')
log "Backup complete and verified: ${DEST_DIR}/${BACKUP_FILE} (${BACKUP_SIZE})"

# Prune this site+environment's old local backups. Scoped to the environment
# so a staging run never deletes production dumps, and the newest KEEP_MIN are
# always kept — a site you back up rarely shouldn't end up with none at all.
if [[ "$PRUNE" == true ]]; then
    PREFIX="${SITE_NAME//./_}_${ENVIRONMENT}_"
    DELETED_COUNT=0
    # Timestamped names sort chronologically, so reverse-sorted = newest first.
    while IFS= read -r old; do
        [[ -n "$old" ]] || continue
        if [[ -n "$(find "$old" -mtime "+${KEEP_DAYS}" -print)" ]]; then
            rm -f "$old"
            DELETED_COUNT=$((DELETED_COUNT + 1))
        fi
    done < <(find "$DEST_DIR" -maxdepth 1 -name "${PREFIX}*.sql.gz" | sort -r | tail -n "+$((KEEP_MIN + 1))")
    if [[ "$DELETED_COUNT" -gt 0 ]]; then
        log "Pruned ${DELETED_COUNT} ${ENVIRONMENT} backup(s) older than ${KEEP_DAYS} days (newest ${KEEP_MIN} always kept)."
    fi
fi

exit 0
