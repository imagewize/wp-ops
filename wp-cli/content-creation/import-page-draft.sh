#!/bin/bash
#
# Import an HTML draft (Gutenberg block markup) into an existing WordPress
# page, on the local Trellis VM and/or production. Complements
# page-creation.sh, which only creates new pages — this updates one that
# already exists.
#
# Draft files start with notes for humans: Blade `{{-- ... --}}` comments and
# HTML comments (SUGGESTED, NOTE, PAGE, FEATURED IMAGE, …). This script strips
# every one of them before the first block, plus Blade comments anywhere.
# Before #246 it stripped only `{{--` lines, so the HTML-comment notes were
# stored and shipped in the public page source. A non-block HTML comment left
# further down (a stray `<!-- CTA: … -->`) is refused unless
# --allow-html-comments is passed.
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
# @flag     --allow-html-comments  optional  Import even though the body has non-block HTML comments (stray notes)
# @example  wp-ops import-page-draft draft.html 7673
# @example  wp-ops import-page-draft draft.html 7673 example.com both template-no-header.blade.php

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

# The one flag may appear anywhere; everything else is positional.
ALLOW_HTML_COMMENTS="no"
ARGS=()
for arg in "$@"; do
    if [ "$arg" == "--allow-html-comments" ]; then ALLOW_HTML_COMMENTS="yes"; else ARGS+=("$arg"); fi
done
set -- "${ARGS[@]}"

DRAFT_FILE="$1"
PAGE_ID="$2"
SITE_NAME="${3:-example.com}"
ENVIRONMENT="${4:-local}"
TEMPLATE="$5"

if [ -z "$DRAFT_FILE" ] || [ -z "$PAGE_ID" ]; then
    print_error "Usage: $0 <draft-file> <page-id> [site-name] [environment] [template] [--allow-html-comments]"
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

print_step "Stripping draft header comments"
# Same rule as strip_draft_comments in publish-post.sh and stripDraftHeader()
# in the MCP's publishPost.ts — keep the three in step.
python3 - "$DRAFT_FILE" "$STRIPPED_FILE" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
s = re.sub(r'^[ \t]*\{\{--.*?--\}\}[ \t]*\n?', '', s, flags=re.S | re.M)
s = re.sub(r'^<!--\s*SUGGESTED .*?-->[ \t]*\n?', '', s, flags=re.M)
while True:
    t = s.lstrip()
    m = re.match(r'<!--(?!\s*/?wp:).*?-->', t, re.S)
    if not m:
        s = t
        break
    s = t[m.end():]
open(sys.argv[2], 'w', encoding='utf-8').write(s)
PY

STRAY_COMMENTS=$(python3 - "$STRIPPED_FILE" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
for c in re.findall(r'<!--(?!\s*/?wp:)(?!\s*(?:more|nextpage|noteaser)\b).*?-->', s, re.S):
    print(re.sub(r'\s+', ' ', c)[:70])
PY
)
if [ -n "$STRAY_COMMENTS" ]; then
    STRAY_COUNT=$(printf '%s\n' "$STRAY_COMMENTS" | wc -l | tr -d ' ')
    STRAY_FIRST=$(printf '%s\n' "$STRAY_COMMENTS" | head -1)
    if [ "$ALLOW_HTML_COMMENTS" == "yes" ]; then
        print_warn "$STRAY_COUNT non-block HTML comment(s) in the body, e.g. $STRAY_FIRST — importing anyway (--allow-html-comments)"
    else
        print_error "Draft body contains $STRAY_COUNT non-block HTML comment(s), e.g. $STRAY_FIRST"
        echo "        These are stored and shipped in the public page source. Remove them, or" >&2
        echo "        pass --allow-html-comments if they are intended." >&2
        rm -f "$STRIPPED_FILE"; exit 1
    fi
fi

update_local() {
    if [ -z "$TRELLIS_DIR" ] || [ -z "$SITE_DIR" ]; then
        print_error "TRELLIS_DIR and SITE_DIR must be set for a local update:"
        echo "  TRELLIS_DIR=/path/to/trellis SITE_DIR=/path/to/bedrock-site $0 ..." >&2
        exit 1
    fi

    print_step "Updating local page $PAGE_ID"
    cp "$STRIPPED_FILE" "$SITE_DIR/$TMP_NAME"

    # wp_update_post() calls wp_unslash() internally and expects slashed input, so an
    # unslashed body loses every literal backslash. Page drafts carrying code (regex
    # backreferences, \n in printf, escaped quotes) are silently corrupted without this.
    (cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
        wp eval 'wp_update_post(array("ID" => '"$PAGE_ID"', "post_content" => wp_slash(file_get_contents("'"$SERVER_PATH"'/'"$TMP_NAME"'"))));' \
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

    # See the note in update_local(): wp_update_post() unslashes, so slash the body first.
    ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp eval 'wp_update_post(array(\"ID\" => $PAGE_ID, \"post_content\" => wp_slash(file_get_contents(\"$SERVER_PATH/$TMP_NAME\"))));' --path=$WP_PATH"

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
