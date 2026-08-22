#!/bin/bash

# UpdraftPlus-to-Valet Sandbox Bootstrap
#
# Turns a directory of UpdraftPlus backup zips (db/plugins/themes/uploads[+N])
# into a running local WordPress site linked with Laravel Valet — no SSH or
# hosting access required. Built for the "handed a set of backup zips before
# you have server access" onboarding pattern: a client hands over an
# UpdraftPlus export, or you're evaluating a prospective site, and the only
# starting point is those files.
#
# Local-only, plain WordPress — no Trellis, no Bedrock, none of the
# detect_trellis_dir()-style helpers apply here.
#
# Usage:
#   ./updraft-to-valet.sh <backup-dir> <site-slug> --wp-version X.Y.Z [options]
#   wp-ops updraft-to-valet ~/Downloads/client-backup client --wp-version 6.7.1
#
# Options:
#   --wp-version VER      WordPress core version to install (required — the DB
#                         dump only tells you siteurl/ABSPATH, not the core
#                         version, so this can't be auto-detected)
#   --dest DIR            Site directory (default: ~/code/<site-slug>)
#   --secure               Run 'valet secure' after linking
#   --old-url URL          Override the URL auto-detected from the dump
#   --db-user USER         Local MySQL user (default: root)
#   --db-pass PASS         Local MySQL password (default: empty)
#   --db-host HOST         Local MySQL host (default: localhost)
#   --reset-password USER  wp-admin username to set a known local password for
#   --password PASS        Password to use with --reset-password (default: password)
#
# Steps: extract plugins/themes/uploads[+N] into wp-content/, download a
# matching WP core (--skip-content, so it never touches the restored
# wp-content), valet link (+ optional --secure), create the local DB and
# wp-config.php, import the dump, search-replace the old URL for
# https://<site-slug>.test (auto-detected from the dump itself, never
# hardcoded), and flush rewrites.
#
# Not handled here: any local PHP-FPM/MySQL environment repair (port
# conflicts between Homebrew PHP versions, etc.) — that's a one-time machine
# setup issue, not part of this repeatable workflow.
#
# @desc     Bootstrap a local Valet WordPress site from a directory of UpdraftPlus backup zips
# @category misc
# @platform wordpress
# @runs     local
# @requires wp valet unzip gzip
# @arg      backup-dir        required  {~/Downloads/client-backup}  Directory containing the UpdraftPlus zip/gz files
# @arg      site-slug         required  {client}  Site slug — used for ~/code/<slug>, the Valet link, and the wp_<slug> DB name
# @flag     --wp-version      required  {6.7.1}  WordPress core version to install
# @flag     --dest            optional  {~/code/client}  Site directory (default: ~/code/<site-slug>)
# @flag     --secure          optional  {}  Run 'valet secure' after linking
# @flag     --old-url         optional  {https://old-host.example.com}  Override the URL auto-detected from the dump's siteurl row
# @flag     --db-user         optional  {root}  Local MySQL user (default: root)
# @flag     --db-pass         optional  {}  Local MySQL password (default: empty)
# @flag     --db-host         optional  {localhost}  Local MySQL host (default: localhost)
# @flag     --reset-password  optional  {admin}  wp-admin username to set a known local password for
# @flag     --password        optional  {password}  Password to use with --reset-password (default: password)
# @example  wp-ops updraft-to-valet ~/Downloads/client-backup client --wp-version 6.7.1
# @example  wp-ops updraft-to-valet ~/Downloads/client-backup client --wp-version 6.6.2 --secure --reset-password admin
# @doc      scripts/README.md

set -euo pipefail

BACKUP_DIR=""
SLUG=""
WP_VERSION=""
SITE_DIR=""
SECURE=false
OLD_URL=""
DB_USER="root"
DB_PASS=""
DB_HOST="localhost"
RESET_USER=""
NEW_PASSWORD="password"

usage() {
    echo "Usage: $(basename "$0") <backup-dir> <site-slug> --wp-version X.Y.Z [options]"
    echo ""
    echo "Bootstrap a local Valet WordPress site from a directory of UpdraftPlus"
    echo "backup zips (db/plugins/themes/uploads[+N]) — no SSH or hosting access"
    echo "needed."
    echo ""
    echo "Arguments:"
    echo "  backup-dir   Directory containing the UpdraftPlus zip/gz files"
    echo "  site-slug    Site slug — used for ~/code/<slug>, the Valet link, and the DB name"
    echo ""
    echo "Options:"
    echo "  --wp-version VER       WordPress core version to install (required)"
    echo "  --dest DIR             Site directory (default: ~/code/<site-slug>)"
    echo "  --secure               Run 'valet secure' after linking"
    echo "  --old-url URL          Override the URL auto-detected from the dump"
    echo "  --db-user USER         Local MySQL user (default: root)"
    echo "  --db-pass PASS         Local MySQL password (default: empty)"
    echo "  --db-host HOST         Local MySQL host (default: localhost)"
    echo "  --reset-password USER  wp-admin username to set a known local password for"
    echo "  --password PASS        Password to use with --reset-password (default: password)"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Example:"
    echo "  $(basename "$0") ~/Downloads/client-backup client --wp-version 6.7.1"
}

# Positional args first, then flags — same convention as db-pull.sh/db-backup.sh.
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --wp-version)      WP_VERSION="$2"; shift 2 ;;
        --dest)            SITE_DIR="$2"; shift 2 ;;
        --secure)          SECURE=true; shift ;;
        --old-url)         OLD_URL="$2"; shift 2 ;;
        --db-user)         DB_USER="$2"; shift 2 ;;
        --db-pass)         DB_PASS="$2"; shift 2 ;;
        --db-host)         DB_HOST="$2"; shift 2 ;;
        --reset-password)  RESET_USER="$2"; shift 2 ;;
        --password)        NEW_PASSWORD="$2"; shift 2 ;;
        -h|--help)         usage; exit 0 ;;
        -*)                echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)                 POSITIONAL+=("$1"); shift ;;
    esac
done

if [ "${#POSITIONAL[@]}" -lt 2 ]; then
    echo "Error: backup-dir and site-slug are both required." >&2
    usage >&2
    exit 1
fi
BACKUP_DIR="${POSITIONAL[0]}"
SLUG="${POSITIONAL[1]}"

if [ -z "$WP_VERSION" ]; then
    echo "Error: --wp-version is required." >&2
    echo "The DB dump only tells you siteurl/ABSPATH, not the WP core version," >&2
    echo "so it can't be auto-detected — check the client's WP admin footer" >&2
    echo "or wp-includes/version.php from the backup if you don't already know it." >&2
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: $BACKUP_DIR is not a directory." >&2
    exit 1
fi
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd)"

for bin in wp valet unzip gzip; do
    command -v "$bin" >/dev/null 2>&1 || { echo "Error: '$bin' is required but not found on PATH." >&2; exit 1; }
done

SITE_DIR="${SITE_DIR:-$HOME/code/$SLUG}"
if [ -e "$SITE_DIR" ]; then
    echo "Error: $SITE_DIR already exists." >&2
    echo "Remove it or pass --dest to pick a different directory." >&2
    exit 1
fi

# MySQL identifiers don't tolerate hyphens without backticking everywhere, so
# the DB name swaps them for underscores even though the site slug (and the
# Valet link, and ~/code/<slug>) keep the hyphenated form.
DB_NAME="wp_${SLUG//-/_}"

echo "=== UpdraftPlus -> Valet sandbox: $SLUG ==="
echo "  Backup dir: $BACKUP_DIR"
echo "  Site dir:   $SITE_DIR"
echo "  WP version: $WP_VERSION"
echo "  DB:         $DB_NAME"
echo ""

# --- Step 1: find the UpdraftPlus backup set -------------------------------
#
# UpdraftPlus names every file in one backup run with the same hash:
#   backup_<date>_<site>_<hash>-db.gz
#   backup_<date>_<site>_<hash>-plugins.zip
#   backup_<date>_<site>_<hash>-themes.zip
#   backup_<date>_<site>_<hash>-uploads.zip   (uploads2.zip, uploads3.zip, ... if multipart)
#   backup_<date>_<site>_<hash>-others.zip
#
# The db file is the anchor: everything else is matched against its hash so
# a directory holding more than one backup run doesn't get mixed together.
echo "Detecting UpdraftPlus backup set..."

# mapfile/readarray and namerefs (local -n) are Bash 4+; macOS ships Bash 3.2
# at /bin/bash, so each match set is read into its own array by hand instead
# (same NUL-delimited read pattern as find-and-replace-files.sh) rather than
# through a shared helper.
DB_CANDIDATES=()
while IFS= read -r -d $'\0' entry; do
    DB_CANDIDATES+=("$entry")
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "backup_*-db.gz" -print0)
if [ "${#DB_CANDIDATES[@]}" -eq 0 ]; then
    echo "Error: no UpdraftPlus database backup found (backup_*-db.gz) in $BACKUP_DIR." >&2
    exit 1
fi
if [ "${#DB_CANDIDATES[@]}" -gt 1 ]; then
    echo "Error: found more than one database backup — point --backup-dir at a single backup set:" >&2
    printf '  %s\n' "${DB_CANDIDATES[@]}" >&2
    exit 1
fi
DB_FILE="${DB_CANDIDATES[0]}"

HASH=$(basename "$DB_FILE" | sed -E 's/^backup_.+_([^_]+)-db\.gz$/\1/')
if [ -z "$HASH" ] || [ "$HASH" = "$(basename "$DB_FILE")" ]; then
    echo "Error: could not parse the UpdraftPlus hash out of $(basename "$DB_FILE")." >&2
    exit 1
fi
echo "  DB dump:    $(basename "$DB_FILE")"
echo "  Hash:       $HASH"

PLUGIN_ZIPS=()
while IFS= read -r -d $'\0' entry; do
    PLUGIN_ZIPS+=("$entry")
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*_${HASH}-plugins.zip" -print0)

THEME_ZIPS=()
while IFS= read -r -d $'\0' entry; do
    THEME_ZIPS+=("$entry")
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*_${HASH}-themes.zip" -print0)

UPLOAD_ZIPS=()
while IFS= read -r -d $'\0' entry; do
    UPLOAD_ZIPS+=("$entry")
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*_${HASH}-uploads*.zip" -print0)

OTHER_ZIPS=()
while IFS= read -r -d $'\0' entry; do
    OTHER_ZIPS+=("$entry")
done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "*_${HASH}-others.zip" -print0)

for label in "plugins:${#PLUGIN_ZIPS[@]}" "themes:${#THEME_ZIPS[@]}" "uploads:${#UPLOAD_ZIPS[@]}" "others:${#OTHER_ZIPS[@]}"; do
    name="${label%%:*}"; count="${label##*:}"
    if [ "$count" -eq 0 ]; then
        echo "  ${name}: none found — skipping"
    else
        echo "  ${name}: ${count} file(s)"
    fi
done
echo ""

# --- Step 2: extract wp-content -------------------------------------------
mkdir -p "$SITE_DIR/wp-content"

# UpdraftPlus zips have varied, across versions, in whether their entries
# already carry a "wp-content/" prefix or start directly at "plugins/" —
# check each zip's own layout rather than assuming one.
extract_updraft_zip() {
    local zip="$1"
    local first_entry
    first_entry=$(unzip -Z1 "$zip" | head -1)
    if [[ "$first_entry" == wp-content/* ]]; then
        unzip -q -o "$zip" -d "$SITE_DIR"
    else
        unzip -q -o "$zip" -d "$SITE_DIR/wp-content"
    fi
}

echo "Extracting wp-content..."
# ${ARR[@]:-} rather than ${ARR[@]}: Bash 3.2 (macOS's /bin/bash) treats a
# zero-element array as unset for [@] expansion under `set -u`, so an empty
# PLUGIN_ZIPS/etc. would otherwise abort the script here instead of just
# contributing zero words. The ":-" default (one empty-string word) is caught
# by the -n check below the same as an unset array would be, with none of
# the abort.
for zip in "${PLUGIN_ZIPS[@]:-}" "${THEME_ZIPS[@]:-}" "${UPLOAD_ZIPS[@]:-}" "${OTHER_ZIPS[@]:-}"; do
    [ -n "$zip" ] || continue
    echo "  $(basename "$zip")"
    extract_updraft_zip "$zip"
done
echo ""

# --- Step 3: WordPress core -------------------------------------------------
# --skip-content is the point: default `wp core download` bundles its own
# wp-content (default theme, akismet, hello dolly) and would otherwise land
# on top of what was just restored.
echo "Downloading WordPress core $WP_VERSION (--skip-content)..."
wp core download --version="$WP_VERSION" --skip-content --path="$SITE_DIR"
echo ""

# --- Step 4: Valet link -----------------------------------------------------
echo "Linking with Valet..."
(cd "$SITE_DIR" && valet link "$SLUG")
if [ "$SECURE" = true ]; then
    (cd "$SITE_DIR" && valet secure "$SLUG")
fi
echo ""

# --- Step 5: local database --------------------------------------------------
echo "Creating local database..."
wp config create \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --dbhost="$DB_HOST" \
    --path="$SITE_DIR" \
    --skip-check
wp db create --path="$SITE_DIR"
echo ""

# --- Step 6: auto-detect the old URL, before it's buried in a live DB ------
#
# Read straight off the compressed dump rather than hardcoding anything: the
# siteurl option's INSERT row is what UpdraftPlus (and everything else)
# treats as ground truth for "what URL was this site running on".
if [ -z "$OLD_URL" ]; then
    echo "Detecting old site URL from the dump..."
    OLD_URL=$(gunzip -c "$DB_FILE" 2>/dev/null \
        | grep -m1 -oE "'siteurl',[[:space:]]*'https?://[^']+'" \
        | sed -E "s/^.*'(https?:\/\/[^']+)'\$/\1/" || true)
fi
if [ -z "$OLD_URL" ]; then
    echo "Error: could not auto-detect the old site URL from the dump's siteurl row." >&2
    echo "Pass it explicitly: --old-url https://the-old-host.example.com" >&2
    exit 1
fi
NEW_URL="https://${SLUG}.test"
echo "  Old URL: $OLD_URL"
echo "  New URL: $NEW_URL"
echo ""

# --- Step 7: import the dump -------------------------------------------------
echo "Importing database..."
TMP_SQL=$(mktemp -t "updraft-to-valet-${SLUG}.XXXXXX.sql")
trap 'rm -f "$TMP_SQL"' EXIT
gunzip -c "$DB_FILE" > "$TMP_SQL"
wp db import "$TMP_SQL" --path="$SITE_DIR"
rm -f "$TMP_SQL"
trap - EXIT
echo ""

# --- Step 8: search-replace and flush ---------------------------------------
echo "Search-replacing $OLD_URL -> $NEW_URL..."
wp search-replace "$OLD_URL" "$NEW_URL" --all-tables --precise --path="$SITE_DIR"
wp rewrite flush --path="$SITE_DIR"
echo ""

# --- Step 9: optional local password reset ----------------------------------
if [ -n "$RESET_USER" ]; then
    wp user update "$RESET_USER" --user_pass="$NEW_PASSWORD" --path="$SITE_DIR"
    echo "Password for '$RESET_USER' reset to: $NEW_PASSWORD"
    echo ""
fi

echo "=== Done ==="
echo "  Site:  $NEW_URL"
echo "  Path:  $SITE_DIR"
echo "  DB:    $DB_NAME"
if [ -n "$RESET_USER" ]; then
    echo "  Login: $RESET_USER / $NEW_PASSWORD"
fi
