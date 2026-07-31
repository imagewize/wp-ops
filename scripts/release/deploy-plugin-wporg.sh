#!/bin/bash

# WordPress.org SVN Plugin Deploy Script
# Publishes a plugin from its Git working tree to the WordPress.org plugin
# directory (SVN): syncs trunk/, creates tags/<version>/, and uploads the
# marketing assets/ (banners, icon, screenshots).
#
# Generic — works for any plugin. It reuses the same conventions as the
# imagewize GitHub release flow:
#   - .distignore   → files excluded from trunk/tags (same filter as the release zip)
#   - .wordpress-org/ → banners, icon, screenshots uploaded to SVN /assets
#
# Usage:
#   ./deploy-plugin-wporg.sh <slug> [version] [options]
#
#   <slug>      WordPress.org plugin slug (e.g. warder-cookie-consent)
#   [version]   Release version (default: read from the main plugin file's Version: header)
#
# Options:
#   --plugin-dir <path>   Plugin git working tree (default: current directory)
#   --assets-dir <path>   Marketing assets dir (default: <plugin-dir>/.wordpress-org)
#   --build "<cmd>"       Build command to run first (e.g. "npm ci && npx webpack")
#   --svn-dir <path>      SVN checkout location (default: <plugin-dir>/../<slug>-svn)
#   --username <user>     WordPress.org SVN username (case-sensitive!)
#   -m, --message <msg>   Commit message (default: "Release <version>")
#   --commit              Actually run `svn ci` (prompts for SVN password).
#                         Without this, the script stages everything and prints
#                         the exact commit command for you to run/review.
#   --force               Allow re-deploying a tag that already exists (rare).
#   -h, --help            Show this help.
#
# Examples:
#   # Prepare a release (stage + review), then commit manually:
#   cd ~/code/warder-cookie-consent
#   ~/code/wp-ops/scripts/release/deploy-plugin-wporg.sh warder-cookie-consent --build "npm ci && npx webpack"
#
#   # One shot, build + commit:
#   ~/code/wp-ops/scripts/release/deploy-plugin-wporg.sh warder-cookie-consent 2.1.4 \
#     --build "npm ci && npx webpack" --username Rhand --commit
#
# Requirements: svn, zip, rsync, and (if --build is used) the build toolchain.

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

err()  { echo -e "${RED}✗ $1${NC}" >&2; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
info() { echo -e "${BLUE}$1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

SVN_BASE="https://plugins.svn.wordpress.org"

# Defaults
PLUGIN_DIR="$(pwd)"
ASSETS_DIR=""
BUILD_CMD=""
SVN_DIR=""
SVN_USER=""
COMMIT_MSG=""
DO_COMMIT=false
FORCE=false
SLUG=""
VERSION=""

# Parse args
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --plugin-dir) PLUGIN_DIR="$2"; shift 2;;
        --assets-dir) ASSETS_DIR="$2"; shift 2;;
        --build)      BUILD_CMD="$2"; shift 2;;
        --svn-dir)    SVN_DIR="$2"; shift 2;;
        --username)   SVN_USER="$2"; shift 2;;
        -m|--message) COMMIT_MSG="$2"; shift 2;;
        --commit)     DO_COMMIT=true; shift;;
        --force)      FORCE=true; shift;;
        -h|--help)    sed -n '3,46p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
        -*)           err "Unknown option: $1"; exit 1;;
        *)            POSITIONAL+=("$1"); shift;;
    esac
done
set -- "${POSITIONAL[@]}"
SLUG="${1:-}"
VERSION="${2:-}"

# Validate prerequisites
for bin in svn zip rsync; do
    command -v "$bin" >/dev/null 2>&1 || { err "'$bin' is required but not installed."; exit 1; }
done

[ -n "$SLUG" ] || { err "Plugin slug is required. Usage: $0 <slug> [version] [options]"; exit 1; }

PLUGIN_DIR="$(cd "$PLUGIN_DIR" && pwd)"
cd "$PLUGIN_DIR"
[ -z "$ASSETS_DIR" ] && ASSETS_DIR="$PLUGIN_DIR/.wordpress-org"

info "=== WordPress.org SVN Deploy: $SLUG ==="
echo ""

# Locate the main plugin file (root-level .php containing "Plugin Name:")
MAIN_FILE=""
for f in "$PLUGIN_DIR"/*.php; do
    [ -f "$f" ] || continue
    if grep -q "Plugin Name:" "$f"; then MAIN_FILE="$f"; break; fi
done
[ -n "$MAIN_FILE" ] || { err "Could not find the main plugin file (a root *.php with 'Plugin Name:')."; exit 1; }
ok "Main plugin file: $(basename "$MAIN_FILE")"

# Resolve version from the header if not given
if [ -z "$VERSION" ]; then
    VERSION="$(grep -m1 -E '^[[:space:]]*\*?[[:space:]]*Version:' "$MAIN_FILE" | sed -E 's/.*Version:[[:space:]]*//' | tr -d '[:space:]')"
fi
[ -n "$VERSION" ] || { err "Could not determine version. Pass it explicitly: $0 $SLUG <version>"; exit 1; }
ok "Version: $VERSION"
[ -z "$COMMIT_MSG" ] && COMMIT_MSG="Release $VERSION"

# Optional build
if [ -n "$BUILD_CMD" ]; then
    info "Running build: $BUILD_CMD"
    ( eval "$BUILD_CMD" )
    ok "Build complete"
fi

# Guard: refuse to overwrite an already-published tag unless --force
info "Checking remote for existing tag $VERSION ..."
if svn ls "$SVN_BASE/$SLUG/tags/$VERSION/" >/dev/null 2>&1; then
    if [ "$FORCE" = true ]; then
        warn "tags/$VERSION already exists on the remote — proceeding because --force was given."
    else
        err "tags/$VERSION is already published. Bump the version, or pass --force to overwrite."
        exit 1
    fi
else
    ok "tags/$VERSION is free"
fi

# Checkout (or update) the SVN working copy
[ -z "$SVN_DIR" ] && SVN_DIR="$PLUGIN_DIR/../$SLUG-svn"
if [ -d "$SVN_DIR/.svn" ]; then
    info "Updating existing SVN checkout: $SVN_DIR"
    svn up "$SVN_DIR" >/dev/null
else
    info "Checking out $SVN_BASE/$SLUG ..."
    svn co "$SVN_BASE/$SLUG" "$SVN_DIR" >/dev/null
fi
SVN_DIR="$(cd "$SVN_DIR" && pwd)"
mkdir -p "$SVN_DIR/trunk" "$SVN_DIR/tags" "$SVN_DIR/assets"
ok "Working copy: $SVN_DIR"

# Build a clean, .distignore-filtered payload (identical to the release zip)
PAYLOAD="$(mktemp -d)"
trap 'rm -rf "$PAYLOAD"' EXIT
info "Assembling filtered payload ..."
if [ -f "$PLUGIN_DIR/.distignore" ]; then
    ( cd "$PLUGIN_DIR" && zip -r -q "$PAYLOAD/p.zip" . -x@.distignore )
    ok "Filtered via .distignore"
else
    warn "No .distignore found — shipping everything except .git/"
    ( cd "$PLUGIN_DIR" && zip -r -q "$PAYLOAD/p.zip" . -x '.git/*' )
fi
mkdir -p "$PAYLOAD/files"
unzip -q "$PAYLOAD/p.zip" -d "$PAYLOAD/files"

# Reconcile a versioned dir with SVN: schedule adds for new files, deletes for missing
svn_reconcile() {
    local dir="$1"
    ( cd "$dir" && svn add --force . --quiet >/dev/null 2>&1 || true )
    # Remove files that disappeared from the working copy
    ( cd "$dir" && svn status | awk '/^!/{ $1=""; sub(/^[[:space:]]+/,""); print }' \
        | while IFS= read -r missing; do [ -n "$missing" ] && svn rm --quiet "$missing" >/dev/null 2>&1 || true; done )
}

# Sync trunk
info "Syncing trunk/ ..."
rsync -a --delete --exclude='.svn' "$PAYLOAD/files/" "$SVN_DIR/trunk/"
svn_reconcile "$SVN_DIR/trunk"
ok "trunk/ synced"

# Create the version tag (fresh copy of the payload)
info "Building tags/$VERSION/ ..."
rsync -a --delete --exclude='.svn' "$PAYLOAD/files/" "$SVN_DIR/tags/$VERSION/"
svn_reconcile "$SVN_DIR/tags/$VERSION"
ok "tags/$VERSION/ staged"

# Sync marketing assets
if [ -d "$ASSETS_DIR" ] && [ -n "$(ls -A "$ASSETS_DIR" 2>/dev/null)" ]; then
    info "Syncing assets/ from $(basename "$ASSETS_DIR")/ ..."
    rsync -a --delete --exclude='.svn' "$ASSETS_DIR/" "$SVN_DIR/assets/"
    svn_reconcile "$SVN_DIR/assets"
    ok "assets/ synced ($(ls -1 "$SVN_DIR/assets" | grep -v '^.svn$' | wc -l | tr -d ' ') files)"
else
    warn "No assets dir at $ASSETS_DIR — skipping banners/icon/screenshots"
fi

# Review
echo ""
info "=== svn status (what will be committed) ==="
svn status "$SVN_DIR" | sed 's/^/  /'
echo ""

# Commit or print the command
if [ "$DO_COMMIT" = true ]; then
    info "Committing to WordPress.org ..."
    if [ -n "$SVN_USER" ]; then
        svn ci "$SVN_DIR" -m "$COMMIT_MSG" --username "$SVN_USER"
    else
        svn ci "$SVN_DIR" -m "$COMMIT_MSG"
    fi
    echo ""
    ok "Committed. Verify: $SVN_BASE/$SLUG/tags/"
    info "Public page: https://wordpress.org/plugins/$SLUG (assets appear within minutes)"
else
    info "=== Staged and ready. Review above, then commit: ==="
    USER_FLAG=""; [ -n "$SVN_USER" ] && USER_FLAG=" --username $SVN_USER"
    echo -e "  ${GREEN}svn ci \"$SVN_DIR\" -m \"$COMMIT_MSG\"$USER_FLAG${NC}"
    echo ""
    warn "Nothing was uploaded yet (no --commit). The checkout is kept at: $SVN_DIR"
fi
