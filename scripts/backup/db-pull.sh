#!/bin/bash

# Trellis Database Pull Script
# Pull a remote site's database into local development via SSH, with URL
# search-replace and optional multisite domain fixup.
#
# Runs on your machine, inside a Trellis project. Uses `trellis vm shell` to
# reach the local development VM, and SSHes from inside it straight to the
# remote host. Both dumps are kept in the site's database_backup/ directory:
# the local database as it was before the pull
# (<site>_development_<date>.sql.gz) and the remote one that was imported
# (<site>_<environment>_<date>.sql.gz, the same naming `db-backup` uses, so
# its retention pruning covers these too). The remote dump is checked for a
# complete gzip stream and mysqldump footer before anything is imported.
#
# Usage:
#   TRELLIS_DIR=/path/to/trellis ./db-pull.sh [site-name] [environment] [options]
#   wp-ops db-pull example.com production
#
# Options:
#   --host HOST    SSH host to pull from (default: site-name)
#   --multisite    Also fix wp_blogs/wp_site domains and scope search-replace with --url
#   --yes, -y      Skip the confirmation prompt
#
# For a from-scratch look at each underlying step, or the Ansible-playbook
# alternative, see trellis/backup/README.md.
#
# @desc     Pull a remote site's database into development via SSH, with URL search-replace (shell, no Ansible)
# @category backup
# @platform trellis
# @runs     local
# @requires trellis
# @arg      site-name    optional  {example.com}  Site name as in wordpress_sites.yml
# @arg      environment  optional  {production|staging}  Remote environment to pull from
# @flag     --host       optional  {example.com}  SSH host to pull from (default: site-name)
# @flag     --multisite  optional  {}  Also fix wp_blogs/wp_site domains and scope search-replace with --url
# @flag     --yes        optional  {}  Skip the confirmation prompt
# @example  wp-ops db-pull example.com production
# @example  wp-ops db-pull network.example.com production --multisite --yes

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [site-name] [environment] [options]"
    echo ""
    echo "Pull a remote site's database into local development via SSH, with"
    echo "URL search-replace. Keeps both the pre-pull local dump and the pulled"
    echo "remote dump in database_backup/, and verifies the remote dump before"
    echo "importing it."
    echo ""
    echo "Trellis projects only: it drives the local dev site through"
    echo "'trellis vm shell', so this has no equivalent for a non-Trellis"
    echo "WordPress checkout."
    echo ""
    echo "Arguments:"
    echo "  site-name    Site name under /srv/www, as in wordpress_sites.yml (default: example.com)"
    echo "  environment  production | staging (default: production) — used for messaging only"
    echo ""
    echo "Options:"
    echo "  --host HOST  SSH host to pull from (default: site-name)"
    echo "  --multisite  Also fix wp_blogs/wp_site domains and scope search-replace with --url"
    echo "  --yes, -y    Skip the confirmation prompt"
    echo ""
    echo "Runs 'trellis vm shell' against your Trellis project. If TRELLIS_DIR"
    echo "isn't set, it's auto-detected from the current directory (and"
    echo "confirmed interactively) — set it explicitly to skip that or run"
    echo "from outside the project:"
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

# Walk up from $PWD looking for a Trellis project, stopping below $HOME.
# Mirrors go/internal/detect.TrellisDir: startDir itself can be the trellis/
# directory (ansible.cfg + group_vars/ directly inside it), or a parent can
# hold trellis/ansible.cfg — trusted only when we started there, or the
# directory walked up through on the way is that parent's own Bedrock site
# (web/wp/), so a sibling checkout that merely happens to sit near an
# unrelated trellis/ isn't picked up by accident.
detect_trellis_dir() {
    local start="$PWD"
    local dir="$start"
    local previous="$start"

    while [[ -n "$dir" && "$dir" != "/" && "$dir" != "$HOME" ]]; do
        if [[ -f "$dir/ansible.cfg" && -d "$dir/group_vars" ]]; then
            echo "$dir"
            return 0
        fi

        if [[ -f "$dir/trellis/ansible.cfg" ]]; then
            if [[ "$dir" == "$start" || -d "$previous/web/wp" ]]; then
                echo "$dir/trellis"
                return 0
            fi
        fi

        previous="$dir"
        dir="$(dirname "$dir")"
    done

    return 1
}

# Confirms an auto-detected TRELLIS_DIR before using it — this backs a
# destructive operation (it overwrites the local dev database), so a
# non-interactive session refuses to guess rather than silently proceeding.
# Mirrors go/internal/detect.Confirm.
confirm_trellis_dir() {
    local detected="$1"

    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "TRELLIS_DIR is not set." >&2
        echo "" >&2
        echo "Detected a candidate at $detected, but wp-ops won't assume it" >&2
        echo "non-interactively. Set it explicitly:" >&2
        echo "" >&2
        echo "  export TRELLIS_DIR=$detected" >&2
        echo "" >&2
        return 1
    fi

    echo "TRELLIS_DIR is not set."
    echo "Detected from the current directory: $detected"
    echo ""
    read -p "Use it for this command? [y/N] " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi

    echo "Cancelled. Set it explicitly instead:"
    echo ""
    echo "  export TRELLIS_DIR=/path/to/your/project"
    echo ""
    return 1
}

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
    if detected="$(detect_trellis_dir)"; then
        if ! confirm_trellis_dir "$detected"; then
            exit 1
        fi
        TRELLIS_DIR="$detected"
    else
        error "TRELLIS_DIR is not set. Point it at your Trellis project:"
        echo "  export TRELLIS_DIR=/path/to/trellis" >&2
        exit 1
    fi
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

MULTISITE_STEPS=""
FLUSH_STEP_NUM=6
if [[ "$MULTISITE" == true ]]; then
    FLUSH_STEP_NUM=7
    MULTISITE_STEPS="
echo ''
echo '=== Step 6: Fixing multisite network and blog domains ==='
PROD_HOST=\$(echo \"\$PROD_URL\" | sed -E 's#^https?://##; s#/.*##')
DEV_HOST=\$(echo \"\$DEV_URL\" | sed -E 's#^https?://##; s#/.*##')
wp db query \"UPDATE wp_blogs SET domain = REPLACE(domain, '\${PROD_HOST}', '\${DEV_HOST}');\" --path=${WP_PATH}
wp db query \"UPDATE wp_site SET domain = REPLACE(domain, '\${PROD_HOST}', '\${DEV_HOST}');\" --path=${WP_PATH}
echo '✓ Domains updated'
"
fi

# Search-replace step, run inside the VM. Quoted heredoc: nothing in it is
# expanded here; it reads PROD_URL/PROD_HOME/DEV_URL/DEV_HOME, WP_PATH and
# MULTISITE from the pull script it is spliced into.
#
# Every --all-tables --precise pass walks the whole database in PHP, so
# siteurl gets no pass of its own when it is home plus the same suffix on both
# ends (Bedrock's /wp, or no suffix at all): replacing home already fixes it.
# Home and its pre-HTTPS http:// form stay two plain passes: a single
# --regex pass covering both was ~10x slower (77s vs 7s on imagewize.com),
# since regex mode unserializes every value.
SEARCH_REPLACE_STEP=$(cat <<'EOS'
echo ''
echo '=== Step 5: Search-replace URLs ==='
sr() {
  local extra=()
  [ "$MULTISITE" = true ] && extra+=(--url="$PROD_URL")
  # --report-changed-only: the full per-table report is ~160 rows of zeros.
  wp search-replace "$@" --all-tables --precise --report-changed-only --path="$WP_PATH" "${extra[@]}"
}
SITEURL_COVERED=no
case "$PROD_URL" in "$PROD_HOME"*)
  case "$DEV_URL" in "$DEV_HOME"*)
    [ "${PROD_URL#"$PROD_HOME"}" = "${DEV_URL#"$DEV_HOME"}" ] && SITEURL_COVERED=yes ;;
  esac ;;
esac
if [ "$SITEURL_COVERED" = no ]; then
  echo "  siteurl: $PROD_URL -> $DEV_URL"
  sr "$PROD_URL" "$DEV_URL"
fi
echo "  home:    $PROD_HOME -> $DEV_HOME"
sr "$PROD_HOME" "$DEV_HOME"
PROD_HOME_HTTP=$(echo "$PROD_HOME" | sed -E 's#^https://#http://#')
if [ "$PROD_HOME_HTTP" != "$PROD_HOME" ]; then
  echo "  pre-HTTPS links: $PROD_HOME_HTTP -> $DEV_HOME"
  sr "$PROD_HOME_HTTP" "$DEV_HOME"
fi
EOS
)

DATE=$(date +%Y_%m_%d_%H_%M_%S)
SITE_SLUG="${SITE_NAME//./_}"
DEV_DUMP="database_backup/${SITE_SLUG}_development_${DATE}.sql.gz"
REMOTE_DUMP="database_backup/${SITE_SLUG}_${ENVIRONMENT}_${DATE}.sql.gz"
# -n: never read stdin (this script itself arrives on stdin, see below).
# LogLevel=ERROR: drop the "Permanently added ... to known hosts" chatter.
REMOTE_SSH="ssh -n -o StrictHostKeyChecking=no -o LogLevel=ERROR web@${REMOTE_HOST}"

# The whole script sits in one { } block: bash parses it completely before
# running any of it, so nothing inside can consume the rest of the script
# from stdin.
PULL_COMMAND="{
set -eo pipefail
exec </dev/null
WP_PATH=${WP_PATH}
MULTISITE=${MULTISITE}
mkdir -p database_backup

echo '=== Step 1: Reading current development URL ==='
DEV_URL=\$(wp option get siteurl --path=${WP_PATH})
DEV_HOME=\$(wp option get home --path=${WP_PATH})
echo \"  siteurl: \$DEV_URL\"
echo \"  home:    \$DEV_HOME\"

echo ''
echo '=== Step 2: Backing up current development database ==='
# wp db export never compresses, whatever the file is called — pipe it.
wp db export - --path=${WP_PATH} | gzip > ${DEV_DUMP}
echo \"✓ ${DEV_DUMP} (\$(du -h ${DEV_DUMP} | cut -f1))\"

echo ''
echo '=== Step 3: Downloading ${ENVIRONMENT} database from ${REMOTE_HOST} ==='
# Both URLs in one SSH round trip, one per line.
PROD_URLS=\$(${REMOTE_SSH} 'cd ${REMOTE_PATH} && wp option get siteurl --path=${WP_PATH} && wp option get home --path=${WP_PATH}')
PROD_URL=\$(printf '%s\\n' \"\$PROD_URLS\" | sed -n 1p)
PROD_HOME=\$(printf '%s\\n' \"\$PROD_URLS\" | sed -n 2p)
[ -n \"\$PROD_URL\" ] && [ -n \"\$PROD_HOME\" ] || { echo '✗ Could not read siteurl/home from ${REMOTE_HOST} — local database untouched'; exit 1; }
echo \"  siteurl: \$PROD_URL\"
echo \"  home:    \$PROD_HOME\"
# Compress on the remote so only the gzipped dump crosses the network.
${REMOTE_SSH} 'set -o pipefail; cd ${REMOTE_PATH} && wp db export - --path=${WP_PATH} | gzip' > ${REMOTE_DUMP}
gzip -t ${REMOTE_DUMP} || { echo '✗ Downloaded dump is not valid gzip — local database untouched'; exit 1; }
gzip -dc ${REMOTE_DUMP} | tail -n 3 | grep -q -- '-- Dump completed' || { echo '✗ Downloaded dump is incomplete (no Dump completed footer) — local database untouched'; exit 1; }
echo \"✓ ${REMOTE_DUMP} (\$(du -h ${REMOTE_DUMP} | cut -f1), verified)\"

echo ''
echo '=== Step 4: Importing into development ==='
gzip -dc ${REMOTE_DUMP} | wp db import - --path=${WP_PATH} >/dev/null
echo \"✓ Imported \$(wp db tables --all-tables-with-prefix --path=${WP_PATH} | wc -l | tr -d ' ') tables\"

${SEARCH_REPLACE_STEP}
${MULTISITE_STEPS}
echo ''
echo '=== Step ${FLUSH_STEP_NUM}: Flushing cache ==='
wp cache flush --path=${WP_PATH} >/dev/null && echo '✓ Cache flushed'

echo ''
echo \"=== Done: \$DEV_URL now has the ${ENVIRONMENT} database ===\"
}"

# Feed the script on stdin rather than as an argument: `trellis vm shell`
# echoes its full command line, which would print all of the above.
(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$WORKDIR" -- bash -s <<< "$PULL_COMMAND")

echo ""
echo -e "${GREEN}Database pull complete.${NC}"
echo ""
echo -e "Dumps kept in ${WORKDIR}/database_backup/ (the site's database_backup/ on your machine):"
echo -e "  before pull: ${DEV_DUMP##*/}"
echo -e "  pulled:      ${REMOTE_DUMP##*/}"
echo -e "Next: check the site in the browser."

exit 0
