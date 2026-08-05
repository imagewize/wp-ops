#!/bin/bash
#
# Import an HTML draft (Gutenberg block markup) into an existing WordPress
# page, on the local Trellis VM and/or production. Complements
# page-creation.sh, which only creates new pages — this updates one that
# already exists.
#
# Draft files may start with Blade `{{-- ... --}}` documentation comments
# (template/page-ID notes for humans) — this script strips those before
# import, since they are not valid post_content and WordPress would
# otherwise store them as literal text.
#
# Uses `wp eval` + `file_get_contents()` rather than `wp post update
# --post_content="$(cat file)"` — safer for large HTML with quotes/JSON-LD
# than passing the whole page as a shell argument.
#
# Usage:
#   TRELLIS_DIR=/path/to/trellis SITE_DIR=/path/to/bedrock-site \
#     ./import-page-draft.sh <draft-file> <page-id> [site-name] [environment] [template]
#
# TRELLIS_DIR and SITE_DIR are only required for a local (or both) update —
# TRELLIS_DIR to run `trellis vm shell`, SITE_DIR the Bedrock checkout beside
# it whose `/srv/www/<site>/current` mount the VM sees. A production-only
# import needs neither.
#
# @desc     Update an existing WordPress page from an HTML draft, locally and/or in production
# @category content
# @platform trellis
# @runs     local
# @requires ssh trellis
# @arg      draft-file   required  {draft.html}  Local HTML draft with block markup
# @arg      page-id      required  {7673}  WordPress page ID to update
# @arg      site-name    optional  {example.com}  Site name under /srv/www (default: example.com)
# @arg      environment  optional  {local|production|both}  Where to apply the update (default: local)
# @arg      template     optional  {template-no-header.blade.php}  Optional _wp_page_template value to set
# @example  wp-ops wp-cli/content-creation/import-page-draft draft.html 7673
# @example  wp-ops wp-cli/content-creation/import-page-draft draft.html 7673 example.com both template-no-header.blade.php

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

DRAFT_FILE="$1"
PAGE_ID="$2"
SITE_NAME="${3:-example.com}"
ENVIRONMENT="${4:-local}"
TEMPLATE="$5"

if [ -z "$DRAFT_FILE" ] || [ -z "$PAGE_ID" ]; then
    print_error "Usage: $0 <draft-file> <page-id> [site-name] [environment] [template]"
    exit 1
fi

if [ ! -f "$DRAFT_FILE" ]; then
    print_error "Draft file not found: $DRAFT_FILE"
    exit 1
fi

if [ "$ENVIRONMENT" != "local" ] && [ "$ENVIRONMENT" != "production" ] && [ "$ENVIRONMENT" != "both" ]; then
    print_error "Invalid environment: $ENVIRONMENT (must be local, production, or both)"
    exit 1
fi

SERVER_USER="web"
SERVER_HOST="$SITE_NAME"
SERVER_PATH="/srv/www/$SITE_NAME/current"
WP_PATH="web/wp"

TMP_NAME="tmp-import-$PAGE_ID-$(date +%s).html"
STRIPPED_FILE="/tmp/$TMP_NAME"

print_step "Stripping Blade doc-comments from draft"
grep -v '^{{--' "$DRAFT_FILE" > "$STRIPPED_FILE"

update_local() {
    if [ -z "$TRELLIS_DIR" ] || [ -z "$SITE_DIR" ]; then
        print_error "TRELLIS_DIR and SITE_DIR must be set for a local update:"
        echo "  TRELLIS_DIR=/path/to/trellis SITE_DIR=/path/to/bedrock-site $0 ..." >&2
        exit 1
    fi

    print_step "Updating local page $PAGE_ID"
    cp "$STRIPPED_FILE" "$SITE_DIR/$TMP_NAME"

    (cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
        wp eval 'wp_update_post(array("ID" => '"$PAGE_ID"', "post_content" => file_get_contents("'"$SERVER_PATH"'/'"$TMP_NAME"'")));' \
        --path="$WP_PATH")

    if [ -n "$TEMPLATE" ]; then
        (cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
            wp post meta update "$PAGE_ID" _wp_page_template "$TEMPLATE" --path="$WP_PATH")
    fi

    (cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- wp cache flush --path="$WP_PATH")
    rm -f "$SITE_DIR/$TMP_NAME"

    URL=$(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- wp eval "echo get_permalink($PAGE_ID);" --path="$WP_PATH" | tail -1)
    print_info "Local: $URL"
}

update_production() {
    print_step "Updating production page $PAGE_ID"
    scp "$STRIPPED_FILE" "$SERVER_USER@$SERVER_HOST:$SERVER_PATH/$TMP_NAME"

    ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp eval 'wp_update_post(array(\"ID\" => $PAGE_ID, \"post_content\" => file_get_contents(\"$SERVER_PATH/$TMP_NAME\")));' --path=$WP_PATH"

    if [ -n "$TEMPLATE" ]; then
        ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp post meta update $PAGE_ID _wp_page_template '$TEMPLATE' --path=$WP_PATH"
    fi

    ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp cache flush --path=$WP_PATH && rm -f $SERVER_PATH/$TMP_NAME"

    URL=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp eval 'echo get_permalink($PAGE_ID);' --path=$WP_PATH")
    print_info "Production: $URL"
}

if [ "$ENVIRONMENT" == "local" ] || [ "$ENVIRONMENT" == "both" ]; then
    update_local
fi

if [ "$ENVIRONMENT" == "production" ] || [ "$ENVIRONMENT" == "both" ]; then
    print_warn "About to write to PRODUCTION page ID $PAGE_ID on $SERVER_HOST"
    read -p "Type 'yes' to continue: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        print_warn "Skipped production update."
    else
        update_production
    fi
fi

rm -f "$STRIPPED_FILE"
print_info "Done."
