#!/usr/bin/env bash
#
# wp-db-backup.sh — Back up any WordPress site's database, Trellis or not
#
# The host-agnostic counterpart to db-backup.sh. That one assumes a Trellis
# box: it SSHes as web@, cds into /srv/www/<site>/current, and takes the WP
# path as given. Everything here is discovered instead — the install layout,
# the site URL, the backup filename — so it runs against a Valet or Herd site,
# a cPanel account, a plain public_html, or a Bedrock checkout, locally or
# over SSH.
#
# Usage:
#   ./wp-db-backup.sh [options]
#   wp-ops wp-db-backup --path ~/code/example
#
# Options:
#   --path PATH        WordPress directory (default: current directory)
#   --host HOST        SSH user@host to back up from (default: run locally)
#   --site-path PATH   Directory on the server; required with --host
#   --dest DIR         Local destination directory (default: database_backup)
#   --name NAME        Backup basename (default: derived from the site URL)
#   --wp-bin PATH      wp binary or .phar to use (default: wp)
#   --php-bin PATH     PHP binary to run --wp-bin with, for cPanel/Plesk
#   -h, --help         Show this help
#
# Requires: WP-CLI on whichever side runs it, and gzip locally
#
# The dump is streamed: `wp db export -` on one end, gzip into a local file on
# the other. Nothing is written on the server, so nothing needs cleaning up
# there and no writable backup directory has to exist. WP-CLI sends PHP
# notices and its own warnings to stderr, so the SQL on stdout stays clean
# even on a site that is noisy about deprecations.
#
# @desc     Back up any WordPress site's database (Valet, Herd, cPanel, Bedrock) to a local .sql.gz
# @category backup
# @platform wordpress
# @runs     local
# @requires wp gzip
# @flag     --path       optional  {~/code/example}  WordPress directory (default: current directory)
# @flag     --host       optional  {user@example.com}  SSH user@host to back up from
# @flag     --site-path  optional  {/home/user/public_html}  Directory on the server, required with --host
# @flag     --dest       optional  {database_backup}  Local destination directory
# @flag     --name       optional  {example_com}  Backup basename (default: derived from the site URL)
# @flag     --wp-bin     optional  {~/wp-cli.phar}  wp binary or .phar to use
# @flag     --php-bin    optional  {/opt/plesk/php/8.2/bin/php}  PHP binary to run --wp-bin with
# @example  wp-ops wp-db-backup --path ~/code/example
# @example  wp-ops wp-db-backup --host user@example.com --site-path /home/user/public_html
# @doc      scripts/backup/README.md

set -euo pipefail

SITE_DIR=""
SSH_HOST=""
SITE_PATH=""
DEST_DIR="database_backup"
NAME=""
WP_BIN="wp"
PHP_BIN=""

usage() {
    echo "Usage: $(basename "$0") [options]"
    echo ""
    echo "Back up any WordPress site's database to a local .sql.gz."
    echo "Detects the install layout rather than assuming one, so Valet/Herd,"
    echo "cPanel, plain public_html, and Bedrock all work."
    echo ""
    echo "Options:"
    echo "  --path PATH        WordPress directory (default: current directory)"
    echo "  --host HOST        SSH user@host to back up from (default: run locally)"
    echo "  --site-path PATH   Directory on the server; required with --host"
    echo "  --dest DIR         Local destination directory (default: database_backup)"
    echo "  --name NAME        Backup basename (default: derived from the site URL)"
    echo "  --wp-bin PATH      wp binary or .phar to use (default: wp)"
    echo "  --php-bin PATH     PHP binary to run --wp-bin with, for cPanel/Plesk"
    echo "  -h, --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") --path ~/code/example"
    echo "  $(basename "$0") --host user@example.com --site-path /home/user/public_html"
    echo "  $(basename "$0") --host user@example.com --site-path ~/public_html \\"
    echo "      --wp-bin ~/wp-cli.phar --php-bin /opt/plesk/php/8.2/bin/php"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --path)      SITE_DIR="$2"; shift 2 ;;
        --host)      SSH_HOST="$2"; shift 2 ;;
        --site-path) SITE_PATH="$2"; shift 2 ;;
        --dest)      DEST_DIR="$2"; shift 2 ;;
        --name)      NAME="$2"; shift 2 ;;
        --wp-bin)    WP_BIN="$2"; shift 2 ;;
        --php-bin)   PHP_BIN="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ -n "$SSH_HOST" ] && [ -z "$SITE_PATH" ]; then
    echo "Error: --site-path is required with --host." >&2
    echo "There is no /srv/www convention to fall back on outside Trellis." >&2
    exit 1
fi

if [ -z "$SSH_HOST" ]; then
    SITE_DIR="${SITE_DIR:-$PWD}"
    if [ ! -d "$SITE_DIR" ]; then
        echo "Error: $SITE_DIR is not a directory." >&2
        exit 1
    fi
    # Resolve to an absolute path so the WP-CLI --path is unambiguous
    # regardless of where the caller ran us from.
    SITE_DIR="$(cd "$SITE_DIR" && pwd)"
fi

# wp_cmd assembles the WP-CLI invocation. A --php-bin turns it into
# "<php> <wp>", which is how shared hosts with a wp-cli.phar and a
# non-default PHP are reached — same shape as the MCP server's registry
# (mcp-server/src/tools/wpCli.ts), rather than a second convention.
# display_errors=stderr is the reason to reach for --php-bin even when the
# PHP binary is otherwise fine: WP-CLI's shebang wrapper gives no way to pass
# -d, so on a host where PHP prints deprecations they land on stdout and
# corrupt the dump. Routing them to stderr keeps them visible without mixing
# them into the SQL.
wp_cmd() {
    if [ -n "$PHP_BIN" ]; then
        printf '%s -d display_errors=stderr %s' \
            "$(printf '%q' "$PHP_BIN")" "$(printf '%q' "$WP_BIN")"
    else
        printf '%s' "$(printf '%q' "$WP_BIN")"
    fi
}

# remote_sh runs a snippet on the server, or locally when --host is absent,
# so layout detection is written once for both.
remote_sh() {
    if [ -n "$SSH_HOST" ]; then
        ssh -o BatchMode=yes "$SSH_HOST" "$1"
    else
        bash -c "$1"
    fi
}

# wp_run invokes WP-CLI *from the site directory*, which matters for more
# than tidiness: WP-CLI discovers wp-cli.yml by walking up from the working
# directory, not from --path. Running it from elsewhere silently drops the
# site's own config — including any `require` it sets. Found the hard way on
# a Valet site whose wp-cli.yml loads a deprecation suppressor: without the
# cd, PHP's "Deprecated:" notice went to stdout and ended up as the first
# line of the SQL dump.
wp_run() {
    remote_sh "cd $(printf '%q' "$BASE_DIR") && $(wp_cmd) $1"
}

BASE_DIR="${SSH_HOST:+$SITE_PATH}"
BASE_DIR="${BASE_DIR:-$SITE_DIR}"

# Layout detection. wp-load.php is the marker: it sits in the WordPress core
# directory, which is the site root for a classic install but web/wp for
# Bedrock. site-backup.sh hard-codes the Bedrock answer and breaks on
# everything else; asking the filesystem costs one round trip and covers
# both, plus the wordpress/ subdirectory some shared hosts default to.
echo "Detecting WordPress layout..."

WP_PATH=""
for candidate in "" "web/wp" "wordpress"; do
    probe="${BASE_DIR}${candidate:+/$candidate}"
    if remote_sh "test -f $(printf '%q' "$probe/wp-load.php")" 2>/dev/null; then
        WP_PATH="$probe"
        break
    fi
done

if [ -z "$WP_PATH" ]; then
    echo "Error: no wp-load.php found under $BASE_DIR (checked ., web/wp, wordpress)." >&2
    echo "Point --path (or --site-path) at the WordPress directory." >&2
    exit 1
fi

case "$WP_PATH" in
    "$BASE_DIR") LAYOUT="classic (wp-content/)" ;;
    */web/wp)    LAYOUT="Bedrock (web/app/)" ;;
    *)           LAYOUT="core in $(basename "$WP_PATH")/" ;;
esac
echo "  Layout: $LAYOUT"

# The site URL comes from the database, not from a config file — there is no
# wordpress_sites.yml to read outside Trellis, and it is what the backup gets
# named after.
# Last line only, and it has to look like a URL: a stray notice on stdout
# would otherwise end up in the filename.
SITE_URL=$(wp_run "option get siteurl --path=$(printf '%q' "$WP_PATH") --skip-plugins --skip-themes" 2>/dev/null | grep -E '^https?://' | tail -1 || true)

if [ -z "$SITE_URL" ]; then
    echo "Error: could not read siteurl via WP-CLI at $WP_PATH." >&2
    echo "Check that WP-CLI runs there and the database is reachable:" >&2
    echo "  ${WP_BIN} option get siteurl --path=${WP_PATH}" >&2
    exit 1
fi

if [ -z "$NAME" ]; then
    # https://example.com/blog -> example_com_blog
    NAME=$(echo "$SITE_URL" | sed -e 's|^https\{0,1\}://||' -e 's|/$||' | tr './' '__')
fi

DATE=$(date +%Y_%m_%d_%H_%M_%S)
BACKUP_FILE="${NAME}_${DATE}.sql.gz"

mkdir -p "$DEST_DIR"

echo "  Site:   $SITE_URL"
if [ -n "$SSH_HOST" ]; then
    echo "  Source: $SSH_HOST:$WP_PATH"
else
    echo "  Source: $WP_PATH"
fi
echo "  Local:  ${DEST_DIR}/${BACKUP_FILE}"
echo ""
echo "Exporting database..."

# pipefail (set above) is what makes this safe: without it the exit status
# would be gzip's, and a WP-CLI failure would leave a valid gzip of an error
# message sitting there looking like a backup.
if ! wp_run "db export - --path=$(printf '%q' "$WP_PATH") --skip-plugins --skip-themes" \
        | gzip > "${DEST_DIR}/${BACKUP_FILE}"; then
    echo "Error: database export failed." >&2
    rm -f "${DEST_DIR}/${BACKUP_FILE}"
    exit 1
fi

if ! gzip -t "${DEST_DIR}/${BACKUP_FILE}" 2>/dev/null; then
    echo "Error: the backup did not gzip cleanly — removing it." >&2
    rm -f "${DEST_DIR}/${BACKUP_FILE}"
    exit 1
fi

# Both ends of the dump are checked, and the first line is the one that
# matters most: anything a plugin or PHP itself prints to stdout lands there,
# ahead of the SQL, and gzips into a file that looks perfectly healthy while
# failing on import. A trailing "Dump completed" alone does not catch it.
# The `|| true` is load-bearing: head closes the pipe after one line, gzip
# dies of SIGPIPE, and pipefail would otherwise abort the script here — on a
# backup that is perfectly fine.
FIRST_LINE=$(gzip -dc "${DEST_DIR}/${BACKUP_FILE}" 2>/dev/null | head -1 || true)
case "$FIRST_LINE" in
    --*|/*|"") ;;
    *)
        echo "Error: the dump does not start with SQL — something wrote to stdout ahead of it:" >&2
        echo "  ${FIRST_LINE:0:120}" >&2
        echo "" >&2
        echo "Usually PHP notices from a host whose display_errors goes to stdout." >&2
        echo "Re-run through PHP directly so they are routed to stderr instead:" >&2
        echo "  $(basename "$0") --php-bin php --wp-bin \"\$(command -v wp)\" ${SITE_DIR:+--path $SITE_DIR}" >&2
        echo "" >&2
        echo "Removing the backup; it would fail on import." >&2
        rm -f "${DEST_DIR}/${BACKUP_FILE}"
        exit 1
        ;;
esac

if ! gzip -dc "${DEST_DIR}/${BACKUP_FILE}" 2>/dev/null | tail -5 | grep -q "Dump completed"; then
    echo "Warning: the dump has no 'Dump completed' marker — it may be truncated." >&2
    echo "Inspect it before relying on it: gzip -dc ${DEST_DIR}/${BACKUP_FILE} | tail" >&2
fi

BACKUP_SIZE=$(ls -lh "${DEST_DIR}/${BACKUP_FILE}" | awk '{print $5}')
echo ""
echo "Backup complete: ${DEST_DIR}/${BACKUP_FILE} (${BACKUP_SIZE})"
echo ""
echo "Restore it with:"
echo "  gzip -dc ${DEST_DIR}/${BACKUP_FILE} | ${WP_BIN} db import - --path=${WP_PATH}"
