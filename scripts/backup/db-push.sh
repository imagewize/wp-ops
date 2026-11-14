#!/bin/bash

# Trellis Database Push Script
# Push the local development database to a remote environment over SSH, with
# URL search-replace. The counterpart of db-pull.
#
# Runs on your machine, inside a Trellis project. Uses `trellis vm shell` to
# reach the local development VM, and SSHes from inside it straight to the
# remote host, the same way db-pull does.
#
# Order of work, chosen so a failure leaves the remote site untouched:
#   1. Read both sites' URLs.
#   2. Back up the remote database to database_backup/ and verify the dump.
#   3. Export development with its URLs already rewritten to the remote's
#      (`wp search-replace --export`), so the remote never serves .test URLs,
#      not even between import and search-replace. Check every table is there.
#   4. Import on the remote, fix multisite domains in the same SSH session,
#      flush the cache.
#   5. Check the remote home URL.
# If step 4 or 5 fails, the backup from step 2 is imported straight back.
#
# Multisite is detected from the development site, not passed as a flag:
# forgetting it would leave the remote network pointing at .test domains.
#
# Usage:
#   wp-ops db-push example.com staging
#   wp-ops db-push example.com production
#
# @desc     Push the development database to a remote environment via SSH, with URL search-replace (shell, no Ansible)
# @category backup
# @platform trellis
# @runs     local
# @mutates  true
# @requires trellis
# @arg      site-name    required  {example.com}  Site name as in wordpress_sites.yml
# @arg      environment  required  {staging|production}  Remote environment to overwrite
# @flag     --host       optional  {example.com}  SSH host to push to (default: site-name)
# @flag     --yes        optional  {}  Skip the confirmation prompt
# @example  wp-ops db-push example.com staging
# @example  wp-ops db-push example.com production --host 203.0.113.10

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") <site-name> <environment> [options]"
    echo ""
    echo "Push the local development database to a remote environment via SSH,"
    echo "with URL search-replace. Backs up and verifies the remote database"
    echo "first, and rewrites URLs during the export, so the remote never serves"
    echo "development URLs."
    echo ""
    echo "Arguments (both required):"
    echo "  site-name    Site name under /srv/www, as in wordpress_sites.yml"
    echo "  environment  staging | production: the remote database to overwrite"
    echo ""
    echo "Options:"
    echo "  --host HOST  SSH host to push to (default: site-name)"
    echo "  --yes, -y    Skip the confirmation prompt"
    echo ""
    echo "Runs 'trellis vm shell' against your Trellis project. TRELLIS_DIR is"
    echo "used when set. Otherwise the project is detected from the current"
    echo "directory and always confirmed, because this writes to a remote site."
    echo ""
    echo "Both dumps stay in the site's database_backup/:"
    echo "  <site>_<environment>_<date>.sql.gz         the remote, before the push"
    echo "  <site>_push_to_<environment>_<date>.sql.gz what was pushed"
    echo ""
    echo "Email addresses on the development domain (form senders, comment"
    echo "authors) are not rewritten: only URLs and multisite domains are."
}

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2; }

# Walk up from $PWD looking for a Trellis project, stopping below $HOME.
# Same implementation as scripts/backup/db-pull.sh; mirrors
# go/internal/detect.TrellisDir.
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

# Always confirms a detected TRELLIS_DIR, even one found in the current
# directory: a push writes to a remote site, like the database-push and
# files-push playbooks, which go/cmd/trellis.go also always confirms.
confirm_trellis_dir() {
    local detected="$1"

    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "TRELLIS_DIR is not set." >&2
        echo "" >&2
        echo "Detected a candidate at $detected, but a push won't assume it" >&2
        echo "non-interactively. Set it explicitly:" >&2
        echo "" >&2
        echo "  export TRELLIS_DIR=$detected" >&2
        echo "" >&2
        return 1
    fi

    echo "TRELLIS_DIR is not set."
    echo "Detected from the current directory: $detected"
    echo ""
    read -p "Use it for this push? [y/N] " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]] && return 0

    echo "Cancelled. Set it explicitly instead:"
    echo ""
    echo "  export TRELLIS_DIR=/path/to/your/trellis"
    echo ""
    return 1
}

POSITIONAL=()
REMOTE_HOST=""
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
        --yes|-y)
            SKIP_CONFIRM=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            usage >&2
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# No defaults: a push names its target out loud.
if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
    error "Both site-name and environment are required."
    usage >&2
    exit 1
fi

SITE_NAME="${POSITIONAL[0]}"
ENVIRONMENT="${POSITIONAL[1]}"
REMOTE_HOST="${REMOTE_HOST:-$SITE_NAME}"

if [[ "$ENVIRONMENT" == "development" ]]; then
    error "development is not a valid target (you can't push development into itself)."
    exit 1
fi

TRELLIS_DIR="${TRELLIS_DIR:-}"
if [[ -z "$TRELLIS_DIR" ]]; then
    if detected="$(detect_trellis_dir)"; then
        confirm_trellis_dir "$detected" || exit 1
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
echo -e "${BLUE}Database Push: ${SITE_NAME} -> ${ENVIRONMENT}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${RED}WARNING: This replaces the ${ENVIRONMENT} database with your development database.${NC}"
echo -e "  From:   ${TRELLIS_DIR} (${WORKDIR})"
echo -e "  To:     web@${REMOTE_HOST}:${REMOTE_PATH}"
echo -e "  Content, orders, users and comments created on ${ENVIRONMENT} since"
echo -e "  your last pull are lost (the backup taken first keeps them)."
echo ""

if [[ "$SKIP_CONFIRM" == true ]]; then
    log "Skipping confirmation (--yes)."
elif [[ ! -t 0 ]]; then
    error "No terminal to confirm on. Re-run with --yes to push without a prompt."
    exit 1
elif [[ "$ENVIRONMENT" == "production" ]]; then
    read -r -p "Type the site name (${SITE_NAME}) to push to production: " REPLY
    if [[ "$REPLY" != "$SITE_NAME" ]]; then
        log "Aborted."
        exit 0
    fi
else
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Aborted."
        exit 0
    fi
fi

DATE=$(date +%Y_%m_%d_%H_%M_%S)
SITE_SLUG="${SITE_NAME//./_}"
REMOTE_BACKUP="database_backup/${SITE_SLUG}_${ENVIRONMENT}_${DATE}.sql.gz"
PUSH_DUMP="database_backup/${SITE_SLUG}_push_to_${ENVIRONMENT}_${DATE}.sql.gz"

# The script that runs inside the VM. Quoted heredoc: nothing is expanded here.
# Its inputs are the assignments prepended below, quoted with printf %q.
# read -d '' rather than $(cat <<EOS): see the bash 3.2 note in db-pull.sh.
IFS= read -r -d '' PUSH_STEPS <<'EOS' || true
set -eo pipefail
exec </dev/null
mkdir -p database_backup

# -n is not used: the import step feeds the dump on stdin.
rssh() { ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "web@$REMOTE_HOST" "$@"; }
untouched() { echo "✗ $1 — nothing was pushed, $ENVIRONMENT is untouched"; exit 1; }

echo '=== Step 1: Reading URLs ==='
DEV_URL=$(wp option get siteurl --path="$WP_PATH")
DEV_HOME=$(wp option get home --path="$WP_PATH")
PREFIX=$(wp db prefix --path="$WP_PATH")
MULTISITE=$(wp eval 'echo is_multisite() ? "yes" : "no";' --path="$WP_PATH")
REMOTE_URLS=$(rssh "cd $REMOTE_PATH && wp option get siteurl --path=$WP_PATH && wp option get home --path=$WP_PATH" </dev/null)
PROD_URL=$(printf '%s\n' "$REMOTE_URLS" | sed -n 1p)
PROD_HOME=$(printf '%s\n' "$REMOTE_URLS" | sed -n 2p)
[ -n "$PROD_URL" ] && [ -n "$PROD_HOME" ] || untouched "Could not read siteurl/home from $REMOTE_HOST"
[ "$DEV_HOME" != "$PROD_HOME" ] || untouched "Development and $ENVIRONMENT share the home URL $DEV_HOME"
echo "  development: $DEV_HOME (siteurl $DEV_URL)"
echo "  $ENVIRONMENT: $PROD_HOME (siteurl $PROD_URL)"
echo "  multisite:   $MULTISITE"

echo ''
echo "=== Step 2: Backing up the $ENVIRONMENT database ==="
rssh "set -o pipefail; cd $REMOTE_PATH && wp db export - --path=$WP_PATH | gzip" </dev/null > "$REMOTE_BACKUP"
gzip -t "$REMOTE_BACKUP" || untouched "Backup is not valid gzip"
gzip -dc "$REMOTE_BACKUP" | tail -n 3 | grep -q -- '-- Dump completed' || untouched "Backup is incomplete (no Dump completed footer)"
echo "✓ $REMOTE_BACKUP ($(du -h "$REMOTE_BACKUP" | cut -f1), verified)"

echo ''
echo '=== Step 3: Exporting development with URLs rewritten ==='
SR_URL=()
[ "$MULTISITE" = yes ] && SR_URL=(--url="$DEV_HOME")
# Every table with the prefix, minus orphaned subsite tables: <prefix><id>_*
# where <id> has no row in <prefix>blogs. An import only drops the tables in
# its dump, so a subsite that exists only in development, or one removed
# from the network, leaves its tables behind. Pushing them would create
# unreachable tables on the remote.
TABLES=()
SKIPPED=""
BLOG_IDS=" "
if [ "$MULTISITE" = yes ]; then
    BLOG_IDS=" $(wp db query "SELECT blog_id FROM ${PREFIX}blogs" --skip-column-names --path="$WP_PATH" | tr '\n' ' ')"
fi
for t in $(wp db tables --all-tables-with-prefix --path="$WP_PATH"); do
    rest=${t#"$PREFIX"}
    id=${rest%%_*}
    if [ "$MULTISITE" = yes ] && [ "$rest" != "$t" ] && [ -n "$id" ] && [ -z "${id//[0-9]/}" ] \
        && [ "${BLOG_IDS#* "$id" }" = "$BLOG_IDS" ]; then
        case " $SKIPPED " in *" $id "*) ;; *) SKIPPED="$SKIPPED $id" ;; esac
        continue
    fi
    TABLES+=("$t")
done
[ -z "$SKIPPED" ] || echo "  skipping orphaned subsite tables (no ${PREFIX}blogs row) for blog IDs:$SKIPPED"
echo "  home: $DEV_HOME -> $PROD_HOME"
# --export leaves the development database as it is and writes the rewritten
# tables as SQL. Warnings (skipped serialized classes) go to the log. Named
# tables are intersected with the scope flags, and on multisite the default
# scope is the main site only, so --all-tables is needed for the list to stand.
wp search-replace "$DEV_HOME" "$PROD_HOME" "${TABLES[@]}" --all-tables --precise --path="$WP_PATH" "${SR_URL[@]}" \
    --export 2>"$PUSH_DUMP.log" | gzip > "$PUSH_DUMP"
EXPECTED=${#TABLES[@]}
EXPORTED=$(gzip -dc "$PUSH_DUMP" | grep -c '^CREATE TABLE' || true)
[ "$EXPORTED" = "$EXPECTED" ] || untouched "Export has $EXPORTED of $EXPECTED tables (see $PUSH_DUMP.log)"
echo "✓ $PUSH_DUMP ($(du -h "$PUSH_DUMP" | cut -f1), $EXPORTED tables)"

# Follow-up passes, run on the remote right after the import. Usually none:
# Bedrock's siteurl is home plus /wp on both ends, which the home pass covers.
DEV_HOST=$(echo "$DEV_HOME" | sed -E 's#^https?://##; s#/.*##')
PROD_HOST=$(echo "$PROD_HOME" | sed -E 's#^https?://##; s#/.*##')
AFTER=""
REMOTE_URL_ARG=""
q() { printf '%q' "$1"; }
# Multisite domains first: until wp_site and wp_blogs hold the remote host,
# WP-CLI can't bootstrap the network, so any search-replace pass below would
# fail. wp db query only needs the database credentials.
if [ "$MULTISITE" = yes ]; then
    echo "  multisite domains: $DEV_HOST -> $PROD_HOST"
    AFTER="$AFTER && wp db query $(q "UPDATE ${PREFIX}blogs SET domain = REPLACE(domain, '$DEV_HOST', '$PROD_HOST'); UPDATE ${PREFIX}site SET domain = REPLACE(domain, '$DEV_HOST', '$PROD_HOST');") --path=$WP_PATH"
    REMOTE_URL_ARG=" --url=$(q "$PROD_HOME")"
fi
case "$DEV_URL" in "$DEV_HOME"*) DEV_SUFFIX=${DEV_URL#"$DEV_HOME"} ;; *) DEV_SUFFIX="#" ;; esac
case "$PROD_URL" in "$PROD_HOME"*) PROD_SUFFIX=${PROD_URL#"$PROD_HOME"} ;; *) PROD_SUFFIX="!" ;; esac
if [ "$DEV_SUFFIX" != "$PROD_SUFFIX" ]; then
    echo "  siteurl needs its own pass: $DEV_URL -> $PROD_URL"
    AFTER="$AFTER && wp search-replace $(q "$DEV_URL") $(q "$PROD_URL") --all-tables --precise --report-changed-only --path=$WP_PATH$REMOTE_URL_ARG"
fi
# The development home in its other scheme (http vs https) is not covered by
# the home pass. Only add a pass when the export still contains it.
case "$DEV_HOME" in https://*) OTHER="http://${DEV_HOME#https://}" ;; *) OTHER="https://${DEV_HOME#http://}" ;; esac
if gzip -dc "$PUSH_DUMP" | grep -qF "$OTHER"; then
    echo "  other-scheme links need a pass: $OTHER -> $PROD_HOME"
    AFTER="$AFTER && wp search-replace $(q "$OTHER") $(q "$PROD_HOME") --all-tables --precise --report-changed-only --path=$WP_PATH$REMOTE_URL_ARG"
fi

echo ''
echo "=== Step 4: Importing on $ENVIRONMENT ==="
# Put the backup from step 2 back. A mysqldump file disables foreign-key
# checks itself, so it imports cleanly over a half-pushed database.
restore() {
    echo "✗ $1"
    echo "  Restoring the $ENVIRONMENT backup taken in step 2..."
    if rssh "set -o pipefail; cd $REMOTE_PATH && gzip -dc | wp db import - --path=$WP_PATH >/dev/null && (wp cache flush --path=$WP_PATH >/dev/null || true)" < "$REMOTE_BACKUP"; then
        echo "✓ $ENVIRONMENT is back to its state before the push."
    else
        echo "✗ The restore failed too. Restore by hand from the site directory on your machine:"
        echo "    gzip -dc $REMOTE_BACKUP | ssh web@$REMOTE_HOST 'cd $REMOTE_PATH && wp db import - --path=$WP_PATH'"
    fi
    exit 1
}

# One SSH session: the import, the follow-up fixes and the cache flush run back
# to back, so the remote is in a half-pushed state for as short a time as possible.
# The export, unlike a mysqldump file, does not switch off foreign-key checks,
# so a DROP TABLE on a table another one references fails halfway through
# (wp_slim_stats on demo.imagewize.com). Switch them off for the import session.
if ! rssh "set -o pipefail; cd $REMOTE_PATH && { echo 'SET FOREIGN_KEY_CHECKS=0;'; gzip -dc; } | wp db import - --path=$WP_PATH >/dev/null $AFTER && (wp cache flush --path=$WP_PATH >/dev/null || true)" < "$PUSH_DUMP"; then
    restore "The import or a follow-up step failed on $ENVIRONMENT."
fi
echo '✓ Imported'

echo ''
echo '=== Step 5: Checking the result ==='
NOW_HOME=$(rssh "cd $REMOTE_PATH && wp option get home --path=$WP_PATH" </dev/null || true)
if [ "$NOW_HOME" != "$PROD_HOME" ]; then
    restore "$ENVIRONMENT home is now '$NOW_HOME', expected $PROD_HOME."
fi
echo "✓ $ENVIRONMENT home is $NOW_HOME"
echo ''
echo "=== Done: $PROD_HOME now has the development database ==="
EOS

INPUTS="REMOTE_HOST=$(printf '%q' "$REMOTE_HOST")
REMOTE_PATH=$(printf '%q' "$REMOTE_PATH")
WP_PATH=$(printf '%q' "$WP_PATH")
ENVIRONMENT=$(printf '%q' "$ENVIRONMENT")
REMOTE_BACKUP=$(printf '%q' "$REMOTE_BACKUP")
PUSH_DUMP=$(printf '%q' "$PUSH_DUMP")
"

# The whole script sits in one { } block so bash parses it before running any
# of it, and nothing inside can read the rest of the script from stdin. Fed on
# stdin because `trellis vm shell` echoes its command line.
(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$WORKDIR" -- bash -s <<< "{
${INPUTS}
${PUSH_STEPS}
}")

echo ""
echo -e "${GREEN}Database push complete.${NC}"
echo ""
echo -e "Dumps kept in ${WORKDIR}/database_backup/ (the site's database_backup/ on your machine):"
echo -e "  ${ENVIRONMENT} before the push: ${REMOTE_BACKUP##*/}"
echo -e "  pushed:                ${PUSH_DUMP##*/}"
echo -e "Next: check ${SITE_NAME} on ${ENVIRONMENT} in the browser."

exit 0
