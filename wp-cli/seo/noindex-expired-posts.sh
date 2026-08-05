#!/usr/bin/env bash
#
# noindex-expired-posts.sh — Set Yoast's noindex on posts past their expiry date
#
# The batch counterpart to the post-expiry-noindex.php snippet. That snippet
# hooks Yoast's wpseo_robots filter and re-evaluates the expiry date on every
# front-end request; this writes Yoast's own noindex meta once, so the result
# is visible in wp-admin, survives without the filter installed, and can run
# from cron instead of on each page view.
#
# The two are complementary rather than alternatives: the snippet also renders
# the "Noindex After Date" meta box that sets _post_expiry_date in the first
# place. Keep it for the editor UI; use this to apply the outcome in bulk.
#
# Usage: ./noindex-expired-posts.sh [OPTIONS]
#
# Options:
#   --meta-key KEY     Expiry date meta key (default: _post_expiry_date)
#   --category IDS     Comma-separated category IDs to limit to (default: all)
#   --post-type TYPE   Post type to scan (default: post)
#   --dry-run          Show what would change, write nothing
#   --revert           Clear noindex from posts no longer expired
#   --path PATH        WordPress path for WP-CLI (default: WP-CLI's own default)
#   --host HOST        SSH user@host to run WP-CLI on (default: run locally)
#   --site-path PATH   Site root to cd into on the server; required with --host
#   -h, --help         Show this help
#
# Requires: WP-CLI, and Yoast SEO for the meta key to have any effect
#
# Expiry dates are compared as dates in MySQL, so they follow the site's stored
# YYYY-MM-DD values; a post expires once its date is strictly before today.
#
# @desc     Set Yoast's noindex on published posts whose expiry date has passed
# @category seo
# @platform wordpress
# @runs     local
# @requires wp
# @flag     --meta-key   optional  {_post_expiry_date}  Expiry date meta key
# @flag     --category   optional  {12,34}  Comma-separated category IDs to limit to
# @flag     --post-type  optional  {post}  Post type to scan
# @flag     --dry-run    optional  Show what would change without writing
# @flag     --revert     optional  Clear noindex from posts no longer expired
# @flag     --path       optional  {web/wp}  WordPress path for WP-CLI
# @flag     --host       optional  {web@example.com}  SSH user@host to run WP-CLI on
# @flag     --site-path  optional  {/var/www/example.com}  Site root on the server, required with --host
# @example  wp-ops noindex-expired-posts --dry-run
# @example  wp-ops noindex-expired-posts --category 12,34 --path web/wp
# @doc      docs/wordpress-utilities/snippets/post-expiry-noindex-wpcli-checks.md

set -euo pipefail

# Yoast SEO stores its per-post robots override here; 1 means noindex.
YOAST_NOINDEX_KEY="_yoast_wpseo_meta-robots-noindex"

META_KEY="_post_expiry_date"
CATEGORIES=""
POST_TYPE="post"
DRY_RUN=0
REVERT=0
WP_PATH=""
SSH_HOST=""
SITE_PATH=""

usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --meta-key KEY     Expiry date meta key (default: _post_expiry_date)"
    echo "  --category IDS     Comma-separated category IDs to limit to"
    echo "  --post-type TYPE   Post type to scan (default: post)"
    echo "  --dry-run          Show what would change, write nothing"
    echo "  --revert           Clear noindex from posts no longer expired"
    echo "  --path PATH        WordPress path for WP-CLI"
    echo "  --host HOST        SSH user@host to run WP-CLI on"
    echo "  --site-path PATH   Site root to cd into on the server (with --host)"
    echo "  -h, --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") --dry-run"
    echo "  $(basename "$0") --category 12,34 --path web/wp"
    echo "  $(basename "$0") --revert"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --meta-key)  META_KEY="$2"; shift 2 ;;
        --category)  CATEGORIES="$2"; shift 2 ;;
        --post-type) POST_TYPE="$2"; shift 2 ;;
        --dry-run)   DRY_RUN=1; shift ;;
        --revert)    REVERT=1; shift ;;
        --path)      WP_PATH="$2"; shift 2 ;;
        --host)      SSH_HOST="$2"; shift 2 ;;
        --site-path) SITE_PATH="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -n "$SSH_HOST" ] && [ -z "$SITE_PATH" ]; then
    echo "Error: --site-path is required with --host (the directory to cd into on the server)." >&2
    exit 1
fi

# wp_run invokes WP-CLI locally or over SSH. --path is appended only when set,
# so a plain install (Valet, Herd, public_html) uses WP-CLI's own defaults
# rather than being forced into Bedrock's web/wp layout.
wp_run() {
    if [ -n "$SSH_HOST" ]; then
        local quoted="" arg
        for arg in "$@"; do quoted+=" $(printf '%q' "$arg")"; done
        if [ -n "$WP_PATH" ]; then quoted+=" $(printf '%q' "--path=$WP_PATH")"; fi
        ssh "$SSH_HOST" "cd $(printf '%q' "$SITE_PATH") && wp$quoted"
    elif [ -n "$WP_PATH" ]; then
        wp "$@" --path="$WP_PATH"
    else
        wp "$@"
    fi
}

TODAY=$(date +%Y-%m-%d)

if [ -n "$SSH_HOST" ]; then
    echo "Target:    $SSH_HOST:$SITE_PATH"
else
    echo "Target:    local WordPress install"
fi
echo "Post type: $POST_TYPE"
echo "Meta key:  $META_KEY"
echo "Today:     $TODAY"
[ -n "$CATEGORIES" ] && echo "Categories: $CATEGORIES"
echo ""

if [ "$REVERT" -eq 1 ]; then
    # Start from what is currently flagged, then clear anything whose expiry
    # is gone or moved into the future — the case where an editor extended a
    # date and the post should be indexable again.
    if [ -n "$CATEGORIES" ]; then
        IDS=$(wp_run post list --post_type="$POST_TYPE" --post_status=publish \
            --cat="$CATEGORIES" \
            --meta_key="$YOAST_NOINDEX_KEY" --meta_value=1 --format=ids)
    else
        IDS=$(wp_run post list --post_type="$POST_TYPE" --post_status=publish \
            --meta_key="$YOAST_NOINDEX_KEY" --meta_value=1 --format=ids)
    fi

    if [ -z "$IDS" ]; then
        echo "No posts currently carry the Yoast noindex flag. Nothing to revert."
        exit 0
    fi

    CLEARED=0
    for id in $IDS; do
        EXPIRY=$(wp_run post meta get "$id" "$META_KEY" 2>/dev/null || true)
        # Still expired — leave it flagged.
        if [ -n "$EXPIRY" ] && [[ "$EXPIRY" < "$TODAY" ]]; then
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  would clear noindex: post $id (expiry: ${EXPIRY:-none})"
        else
            wp_run post meta delete "$id" "$YOAST_NOINDEX_KEY" >/dev/null 2>&1 || true
            echo "  cleared noindex: post $id (expiry: ${EXPIRY:-none})"
        fi
        CLEARED=$((CLEARED + 1))
    done

    echo ""
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$CLEARED post(s) would have noindex cleared. Nothing was written."
    else
        echo "$CLEARED post(s) had noindex cleared."
    fi
    exit 0
fi

# Apply: published posts whose expiry date is strictly before today. One query
# rather than a per-post meta read, so this stays cheap over SSH.
if [ "$DRY_RUN" -eq 1 ]; then
    echo "Expired posts (dry run — nothing will be written):"
    echo ""
    if [ -n "$CATEGORIES" ]; then
        wp_run post list --post_type="$POST_TYPE" --post_status=publish \
            --cat="$CATEGORIES" \
            --meta_key="$META_KEY" --meta_value="$TODAY" --meta_compare="<" --meta_type=DATE \
            --fields=ID,post_title,post_date --format=table
    else
        wp_run post list --post_type="$POST_TYPE" --post_status=publish \
            --meta_key="$META_KEY" --meta_value="$TODAY" --meta_compare="<" --meta_type=DATE \
            --fields=ID,post_title,post_date --format=table
    fi
    echo ""
    echo "Re-run without --dry-run to set ${YOAST_NOINDEX_KEY}=1 on these posts."
    exit 0
fi

if [ -n "$CATEGORIES" ]; then
    IDS=$(wp_run post list --post_type="$POST_TYPE" --post_status=publish \
        --cat="$CATEGORIES" \
        --meta_key="$META_KEY" --meta_value="$TODAY" --meta_compare="<" --meta_type=DATE \
        --format=ids)
else
    IDS=$(wp_run post list --post_type="$POST_TYPE" --post_status=publish \
        --meta_key="$META_KEY" --meta_value="$TODAY" --meta_compare="<" --meta_type=DATE \
        --format=ids)
fi

if [ -z "$IDS" ]; then
    echo "No expired posts found. Nothing to do."
    exit 0
fi

UPDATED=0
SKIPPED=0
for id in $IDS; do
    CURRENT=$(wp_run post meta get "$id" "$YOAST_NOINDEX_KEY" 2>/dev/null || true)
    if [ "$CURRENT" = "1" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    wp_run post meta update "$id" "$YOAST_NOINDEX_KEY" 1 >/dev/null
    echo "  noindexed: post $id"
    UPDATED=$((UPDATED + 1))
done

echo ""
echo "$UPDATED post(s) set to noindex, $SKIPPED already flagged."
echo ""
echo "Verify one on the front end:"
echo "  curl -s <post-url> | grep -i '<meta name=\"robots\"'"
