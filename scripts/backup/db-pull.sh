#!/bin/bash

# Trellis Database Pull Script
# Pull a remote site's database into local development via SSH, with URL
# search-replace and optional multisite domain fixup.
#
# Runs on your machine, inside a Trellis project. Uses `trellis vm shell` to
# reach the local development VM, and SSHes from inside it straight to the
# remote host — the dump streams over that pipe with no intermediate file on
# either end.
#
# Usage:
#   TRELLIS_DIR=/path/to/trellis ./db-pull.sh [site-name] [environment] [options]
#   wp-ops db-pull example.com production
#
# Options:
#   --host HOST    SSH host to pull from (default: site-name)
#   --multisite    Also fix wp_blogs domains and scope search-replace with --url
#   --yes, -y      Skip the confirmation prompt
#
# For a from-scratch look at each underlying step, or the Ansible-playbook
# alternative, see trellis/backup/README.md.
#
# @desc     Pull a remote site's database into development via SSH, with URL search-replace
# @category backup
# @runs     local
# @requires trellis
# @arg      site-name    optional  {example.com}  Site name as in wordpress_sites.yml
# @arg      environment  optional  {production|staging}  Remote environment to pull from
# @flag     --host       optional  {example.com}  SSH host to pull from (default: site-name)
# @flag     --multisite  optional  {}  Also fix wp_blogs domains and scope search-replace with --url
# @flag     --yes        optional  {}  Skip the confirmation prompt
# @example  wp-ops db-pull example.com production
# @example  wp-ops db-pull network.example.com production --multisite --yes
# @doc      trellis/backup/README.md

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [site-name] [environment] [options]"
    echo ""
    echo "Pull a remote site's database into local development via SSH, with"
    echo "URL search-replace. Streams the dump straight from the remote host"
    echo "into the local VM's database — no intermediate file either side."
    echo ""
    echo "Arguments:"
    echo "  site-name    Site name under /srv/www, as in wordpress_sites.yml (default: example.com)"
    echo "  environment  production | staging (default: production) — used for messaging only"
    echo ""
    echo "Options:"
    echo "  --host HOST  SSH host to pull from (default: site-name)"
    echo "  --multisite  Also fix wp_blogs domains and scope search-replace with --url"
    echo "  --yes, -y    Skip the confirmation prompt"
    echo ""
    echo "Requires TRELLIS_DIR set to your Trellis project (used to run"
    echo "'trellis vm shell'):"
    echo "  TRELLIS_DIR=/path/to/trellis $(basename "$0") example.com production"
    echo ""
    echo "For automated/repeatable pulls instead, use the Ansible playbook:"
    echo "  wp-ops trellis database-pull -e site=example.com -e env=production"
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
MULTISITE=false
SKIP_CONFIRM=false

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
        --multisite)
            MULTISITE=true
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRM=true
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

if [[ "$ENVIRONMENT" == "development" ]]; then
    error "development is not a valid source environment (can't pull development into itself)."
    exit 1
fi

TRELLIS_DIR="${TRELLIS_DIR:-}"
if [[ -z "$TRELLIS_DIR" ]]; then
    error "TRELLIS_DIR is not set. Point it at your Trellis project:"
    echo "  export TRELLIS_DIR=/path/to/trellis" >&2
    exit 1
fi

if [[ ! -f "$TRELLIS_DIR/ansible.cfg" ]]; then
    error "TRELLIS_DIR ($TRELLIS_DIR) doesn't look like a Trellis project (no ansible.cfg found)."
    exit 1
fi

if ! command -v trellis &> /dev/null; then
    error "trellis CLI not found. Install it: https://github.com/roots/trellis-cli"
    exit 1
fi

REMOTE_PATH="/srv/www/${SITE_NAME}/current"
WORKDIR="/srv/www/${SITE_NAME}/current"
WP_PATH="web/wp"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Database Pull: ${SITE_NAME} (${ENVIRONMENT})${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will replace your local development database.${NC}"
echo -e "  Remote: web@${REMOTE_HOST}:${REMOTE_PATH}"
echo -e "  Local:  ${TRELLIS_DIR} (${WORKDIR})"
[[ "$MULTISITE" == true ]] && echo -e "  Multisite domain fixup: enabled"
echo ""

if [[ "$SKIP_CONFIRM" == true ]]; then
    log "Skipping confirmation (--yes)."
else
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Aborted."
        exit 0
    fi
fi

SEARCH_REPLACE_CMD="wp search-replace \"\$PROD_URL\" \"\$DEV_URL\" --all-tables --precise --path=${WP_PATH}"
MULTISITE_STEPS=""
FLUSH_STEP_NUM=6
if [[ "$MULTISITE" == true ]]; then
    SEARCH_REPLACE_CMD="${SEARCH_REPLACE_CMD} --url=\"\$PROD_URL\""
    FLUSH_STEP_NUM=7
    MULTISITE_STEPS="
echo ''
echo '=== Step 6: Fixing multisite blog domains ==='
PROD_HOST=\$(echo \"\$PROD_URL\" | sed -E 's#^https?://##; s#/.*##')
DEV_HOST=\$(echo \"\$DEV_URL\" | sed -E 's#^https?://##; s#/.*##')
wp db query \"UPDATE wp_blogs SET domain = REPLACE(domain, '\${PROD_HOST}', '\${DEV_HOST}');\" --path=${WP_PATH}
"
fi

PULL_COMMAND="
set -e
mkdir -p database_backup

echo '=== Step 1: Reading current development URL ==='
DEV_URL=\$(wp option get siteurl --path=${WP_PATH})
echo \"  Development: \$DEV_URL\"

echo ''
echo '=== Step 2: Backing up current development database ==='
wp db export database_backup/dev_backup_\$(date +%Y%m%d_%H%M%S).sql.gz --path=${WP_PATH} && echo '✓ Backup created'

echo ''
echo '=== Step 3: Pulling ${ENVIRONMENT} database from ${REMOTE_HOST} ==='
PROD_URL=\$(ssh -o StrictHostKeyChecking=no web@${REMOTE_HOST} 'cd ${REMOTE_PATH} && wp option get siteurl --path=${WP_PATH}')
echo \"  ${ENVIRONMENT}: \$PROD_URL\"
ssh -o StrictHostKeyChecking=no web@${REMOTE_HOST} 'cd ${REMOTE_PATH} && wp db export - --path=${WP_PATH}' | gzip > /tmp/${SITE_NAME//./_}_import.sql.gz && echo '✓ Downloaded'

echo ''
echo '=== Step 4: Importing into development ==='
gunzip < /tmp/${SITE_NAME//./_}_import.sql.gz | wp db import - --path=${WP_PATH} && echo '✓ Imported'
rm -f /tmp/${SITE_NAME//./_}_import.sql.gz

echo ''
echo '=== Step 5: Running search-replace for URLs ==='
${SEARCH_REPLACE_CMD}
${MULTISITE_STEPS}
echo ''
echo '=== Step ${FLUSH_STEP_NUM}: Flushing cache ==='
wp cache flush --path=${WP_PATH} && echo '✓ Cache flushed'

echo ''
echo '=== Database pull complete! ==='
echo \"Your local site (\$DEV_URL) now has the ${ENVIRONMENT} database.\"
"

(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$WORKDIR" -- bash -c "$PULL_COMMAND")

echo ""
echo -e "${GREEN}Database pull complete.${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Visit your local site in the browser"
echo -e "  2. Check that URLs are correct"
echo -e "  3. Test site functionality"

exit 0
