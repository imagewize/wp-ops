#!/bin/bash
#
# Publish (or update) a WordPress blog post from an HTML draft carrying the
# `<!-- SUGGESTED ... -->` header convention, on the local Trellis VM and/or
# production. Complements import-page-draft.sh, which updates an existing
# *page* by ID and does nothing with post metadata.
#
# What this adds over import-page-draft.sh:
#   - creates the post (import-page-draft.sh can only update an existing ID)
#   - parses the SUGGESTED header for slug/title/meta-title/meta/tags/category
#   - uploads a featured image, sets _thumbnail_id, and rewrites the Article
#     JSON-LD `image` field to the resulting *verified* upload URL
#   - sets The SEO Framework meta (_genesis_title / _genesis_description)
#   - assigns terms, warning rather than silently creating unknown tags
#   - preflights: duplicate slug, short body, JSON-LD block count
#   - verifies AFTER the write that the stored bytes and <script> count match
#     the source
#
# That last check is the reason this script exists. Every way a post write
# silently loses content here is invisible in a normal review: kses stripping
# JSON-LD, a self-closing block one-liner saving as an empty block, a stale
# render. None of them error. Comparing stored bytes and <script> count against
# the source catches all three at write time.
#
# NOTE ON --user: this script deliberately does NOT pass --user to WP-CLI.
# WP-CLI tears down kses filters at init priority 11 only when --user is
# ABSENT, so omitting it is what lets <script type="application/ld+json">
# survive the write. Passing --user for any account lacking unfiltered_html
# re-adds the filters and strips the schema. Do not "fix" this.
#
# Uses `wp eval-file` + file_get_contents() rather than passing the body as a
# shell argument — safer for large HTML containing quotes and JSON-LD.
#
# Usage:
#   TRELLIS_DIR=/path/to/trellis SITE_DIR=/path/to/bedrock-site \
#     ./publish-post.sh <draft-file> [site-name] [environment] [options]
#
# TRELLIS_DIR and SITE_DIR are only required for a local (or both) run —
# TRELLIS_DIR to run `trellis vm shell`, SITE_DIR the Bedrock checkout beside
# it whose /srv/www/<site>/current mount the VM sees. A production-only run
# needs neither.
#
# @desc     Publish or update a WordPress post from an HTML draft, with schema-integrity verification
# @category content
# @platform trellis
# @runs     local
# @requires ssh trellis
# @arg      draft-file   required  {post.html}  HTML draft with block markup and a SUGGESTED header
# @arg      site-name    optional  {example.com}  Site name under /srv/www (default: example.com)
# @arg      environment  optional  {local|production|both}  Where to publish (default: local)
# @flag     --image      optional  {featured.jpg}  Featured image to upload and attach
# @flag     --update     optional  {13681}  Update this existing post ID instead of creating a new post
# @flag     --status     optional  {publish|draft}  Post status (default: publish)
# @flag     --dry-run    optional  Parse and preflight only; make no changes
# @example  wp-ops publish-post post.html
# @example  wp-ops publish-post post.html example.com production --image featured.jpg
# @example  wp-ops publish-post post.html example.com production --update 13681

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

DRAFT_FILE="$1"; shift || true
SITE_NAME="example.com"
ENVIRONMENT="local"

# Positional site-name / environment, then flags in any order.
if [ -n "$1" ] && [[ "$1" != --* ]]; then SITE_NAME="$1"; shift; fi
if [ -n "$1" ] && [[ "$1" != --* ]]; then ENVIRONMENT="$1"; shift; fi

IMAGE_FILE=""
UPDATE_ID=""
POST_STATUS="publish"
DRY_RUN="no"

while [ $# -gt 0 ]; do
    case "$1" in
        --image)   IMAGE_FILE="$2"; shift 2 ;;
        --update)  UPDATE_ID="$2";  shift 2 ;;
        --status)  POST_STATUS="$2"; shift 2 ;;
        --dry-run) DRY_RUN="yes";   shift ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$DRAFT_FILE" ]; then
    print_error "Usage: $0 <draft-file> [site-name] [local|production|both] [--image f] [--update id] [--status s] [--dry-run]"
    exit 1
fi
if [ ! -f "$DRAFT_FILE" ]; then
    print_error "Draft file not found: $DRAFT_FILE"
    exit 1
fi
if [ -n "$IMAGE_FILE" ] && [ ! -f "$IMAGE_FILE" ]; then
    print_error "Image file not found: $IMAGE_FILE"
    exit 1
fi
case "$ENVIRONMENT" in
    local|production|both) ;;
    *) print_error "Invalid environment: $ENVIRONMENT (must be local, production, or both)"; exit 1 ;;
esac
case "$POST_STATUS" in
    publish|draft|pending|private) ;;
    *) print_error "Invalid status: $POST_STATUS"; exit 1 ;;
esac

SERVER_USER="web"
SERVER_HOST="$SITE_NAME"
SERVER_PATH="/srv/www/$SITE_NAME/current"
WP_PATH="web/wp"

# ---------------------------------------------------------------------------
# Parse the SUGGESTED header
# ---------------------------------------------------------------------------
header_value() {
    # $1 = label regex after "SUGGESTED "; returns text after the first colon,
    # trimmed, with the trailing "-->" removed.
    sed -n "s/^<!-- SUGGESTED $1[^:]*:[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p" "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//'
}

SLUG=$(header_value "POST SLUG")
TITLE=$(header_value "TITLE")
META_TITLE=$(header_value "META TITLE")
META_DESC=$(header_value "META")
TAGS=$(header_value "TAGS")
CATEGORY=$(header_value "CATEGORY")

# "SUGGESTED TITLE" also matches the "SUGGESTED META TITLE" pattern's prefix in
# some drafts; re-read TITLE strictly so it can't pick up the meta title.
TITLE=$(sed -n 's/^<!-- SUGGESTED TITLE:[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')
META_DESC=$(sed -n 's/^<!-- SUGGESTED META (max[^)]*):[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')

SLUG="${SLUG#/}"; SLUG="${SLUG%/}"

if [ -z "$TITLE" ]; then
    print_error "No '<!-- SUGGESTED TITLE: ... -->' found in $DRAFT_FILE"
    exit 1
fi
if [ -z "$SLUG" ] && [ -z "$UPDATE_ID" ]; then
    print_error "No '<!-- SUGGESTED POST SLUG: /slug/ -->' found and --update not given"
    exit 1
fi

print_info "Title:      $TITLE"
print_info "Slug:       $SLUG"
print_info "Meta title: $META_TITLE (${#META_TITLE} chars)"
print_info "Meta desc:  ${#META_DESC} chars"
print_info "Tags:       ${TAGS:-<none>}"
print_info "Category:   ${CATEGORY:-<none>}"

[ "${#META_TITLE}" -gt 55 ] && print_warn "Meta title is ${#META_TITLE} chars (>55) — will truncate once '| Site' is appended"
[ "${#META_DESC}" -gt 155 ] && print_warn "Meta description is ${#META_DESC} chars (>155) — will truncate in SERPs"

# ---------------------------------------------------------------------------
# Body: strip the SUGGESTED header and any Blade doc-comments
# ---------------------------------------------------------------------------
TMP_NAME="tmp-publish-$(date +%s).html"
BODY_FILE="/tmp/$TMP_NAME"
grep -v '^<!-- SUGGESTED ' "$DRAFT_FILE" | grep -v '^{{--' | sed '/./,$!d' > "$BODY_FILE"

BODY_BYTES=$(wc -c < "$BODY_FILE" | tr -d ' ')
SRC_LDJSON=$(grep -c 'application/ld+json' "$BODY_FILE" || true)
SRC_SCRIPTS=$(grep -c '<script' "$BODY_FILE" || true)

print_info "Body: $BODY_BYTES bytes, $SRC_LDJSON JSON-LD block(s), $SRC_SCRIPTS script tag(s)"

if [ "$BODY_BYTES" -lt 500 ]; then
    print_error "Body is only $BODY_BYTES bytes — refusing to publish a near-empty post"
    rm -f "$BODY_FILE"; exit 1
fi

# Broken-block preflight: these render as "unsupported block" placeholders.
for bad in 'wp:columns' 'wp:callout' 'wp:acf/' 'wp:nynaeve/'; do
    if grep -q "$bad" "$BODY_FILE"; then
        print_warn "Draft contains '$bad' — this renders as a broken block in posts"
    fi
done
# A self-closing custom block never hydrates when written via WP-CLI: Gutenberg
# builds its InnerBlocks template client-side on insert, so piping the one-liner
# into post_content saves a genuinely empty block with no visible output.
if grep -qE '<!-- wp:[a-z0-9-]+/[a-z0-9-]+ \{[^}]*\} /-->' "$BODY_FILE"; then
    print_warn "Draft contains a self-closing custom block (\`/-->\`) — it will save EMPTY via WP-CLI."
    print_warn "Hand-build the full serialized markup instead."
fi

if [ "$DRY_RUN" == "yes" ]; then
    print_info "Dry run — no changes made."
    rm -f "$BODY_FILE"; exit 0
fi

# ---------------------------------------------------------------------------
# PHP worker: create/update + meta + terms + post-write verification
# ---------------------------------------------------------------------------
build_php() {
    local remote_body="$1" thumb_id="$2"
    cat <<PHP
<?php
\$body = file_get_contents( '$remote_body' );
if ( \$body === false || strlen( \$body ) < 500 ) { echo "ABORT: body missing or too short\n"; return; }
\$src_ld = substr_count( \$body, 'application/ld+json' );
if ( \$src_ld !== $SRC_LDJSON ) { echo "ABORT: JSON-LD count changed in transit ({\$src_ld} != $SRC_LDJSON)\n"; return; }

\$update_id = '$UPDATE_ID';
\$slug      = '$SLUG';

if ( \$update_id ) {
    \$post = get_post( (int) \$update_id );
    if ( ! \$post ) { echo "ABORT: post \$update_id not found\n"; return; }
    \$id = wp_update_post( array( 'ID' => (int) \$update_id, 'post_content' => \$body ), true );
} else {
    \$existing = \$slug ? get_page_by_path( \$slug, OBJECT, 'post' ) : null;
    if ( \$existing ) { echo "ABORT: slug '\$slug' already exists as post {\$existing->ID} — pass --update {\$existing->ID}\n"; return; }
    \$id = wp_insert_post( array(
        'post_type'    => 'post',
        'post_status'  => '$POST_STATUS',
        'post_author'  => 1,
        'post_title'   => base64_decode( '$(printf '%s' "$TITLE" | base64)' ),
        'post_name'    => \$slug,
        'post_content' => \$body,
        'post_excerpt' => base64_decode( '$(printf '%s' "$META_DESC" | base64)' ),
    ), true );
}
if ( is_wp_error( \$id ) ) { echo "ERROR: " . \$id->get_error_message() . "\n"; return; }
\$id = (int) \$id;

\$meta_title = base64_decode( '$(printf '%s' "$META_TITLE" | base64)' );
\$meta_desc  = base64_decode( '$(printf '%s' "$META_DESC" | base64)' );
if ( \$meta_title ) { update_post_meta( \$id, '_genesis_title', \$meta_title ); }
if ( \$meta_desc )  { update_post_meta( \$id, '_genesis_description', \$meta_desc ); }
if ( '$thumb_id' )  { update_post_meta( \$id, '_thumbnail_id', (int) '$thumb_id' ); }

\$cat = trim( base64_decode( '$(printf '%s' "$CATEGORY" | base64)' ) );
if ( \$cat ) {
    \$term = get_term_by( 'name', \$cat, 'category' );
    if ( \$term ) { wp_set_post_categories( \$id, array( (int) \$term->term_id ) ); }
    else { echo "WARN: category '\$cat' does not exist — left uncategorized\n"; }
}

\$tags_raw = trim( base64_decode( '$(printf '%s' "$TAGS" | base64)' ) );
if ( \$tags_raw ) {
    \$assign = array(); \$missing = array();
    foreach ( array_map( 'trim', explode( ',', \$tags_raw ) ) as \$t ) {
        if ( \$t === '' ) { continue; }
        \$term = get_term_by( 'name', \$t, 'post_tag' ) ?: get_term_by( 'slug', sanitize_title( \$t ), 'post_tag' );
        if ( \$term ) { \$assign[] = \$term->name; } else { \$missing[] = \$t; }
    }
    if ( \$assign )  { wp_set_post_terms( \$id, \$assign, 'post_tag', false ); }
    if ( \$missing ) { echo "WARN: tag(s) not found, NOT created: " . implode( ', ', \$missing ) . "\n"; }
}

// Post-write verification — the point of this script.
\$saved  = get_post( \$id );
\$stored = strlen( \$saved->post_content );
\$ld     = substr_count( \$saved->post_content, 'application/ld+json' );
\$sc     = substr_count( \$saved->post_content, '<script' );
echo "id=\$id\n";
echo "permalink=" . get_permalink( \$id ) . "\n";
echo "stored_bytes=\$stored\n";
echo "source_bytes=$BODY_BYTES\n";
echo "ldjson=\$ld/$SRC_LDJSON\n";
echo "scripts=\$sc/$SRC_SCRIPTS\n";
echo "status=" . \$saved->post_status . "\n";
if ( \$stored !== $BODY_BYTES ) { echo "VERIFY_FAIL: stored bytes differ from source — content was altered on write\n"; }
elseif ( \$ld !== $SRC_LDJSON || \$sc !== $SRC_SCRIPTS ) { echo "VERIFY_FAIL: script/JSON-LD blocks were stripped (kses?)\n"; }
else { echo "VERIFY_OK\n"; }
PHP
}

report() {
    # Turn the PHP key=value output into human lines and set the exit status.
    local out="$1" label="$2"
    echo "$out" | grep -E '^(WARN|ABORT|ERROR):' | while read -r l; do print_warn "$l"; done
    if echo "$out" | grep -q '^VERIFY_OK'; then
        local url bytes ld sc
        url=$(echo "$out" | sed -n 's/^permalink=//p')
        bytes=$(echo "$out" | sed -n 's/^stored_bytes=//p')
        ld=$(echo "$out" | sed -n 's/^ldjson=//p')
        sc=$(echo "$out" | sed -n 's/^scripts=//p')
        print_info "$label: $url"
        print_info "$label: verified — $bytes bytes stored, JSON-LD $ld, scripts $sc"
    else
        print_error "$label: verification FAILED"
        echo "$out" | sed 's/^/    /'
        return 1
    fi
}

publish_local() {
    if [ -z "$TRELLIS_DIR" ] || [ -z "$SITE_DIR" ]; then
        print_error "TRELLIS_DIR and SITE_DIR must be set for a local publish:"
        echo "  TRELLIS_DIR=/path/to/trellis SITE_DIR=/path/to/bedrock-site $0 ..." >&2
        exit 1
    fi

    local thumb=""
    if [ -n "$IMAGE_FILE" ]; then
        print_step "Uploading featured image (local)"
        cp "$IMAGE_FILE" "$SITE_DIR/$(basename "$IMAGE_FILE")"
        thumb=$(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
            wp media import "$SERVER_PATH/$(basename "$IMAGE_FILE")" --title="$TITLE" --porcelain --path="$WP_PATH" | tail -1 | tr -dc '0-9')
        rm -f "$SITE_DIR/$(basename "$IMAGE_FILE")"
        print_info "Local attachment ID: $thumb"
    fi

    print_step "Publishing to local"
    cp "$BODY_FILE" "$SITE_DIR/$TMP_NAME"
    build_php "$SERVER_PATH/$TMP_NAME" "$thumb" > "$SITE_DIR/$TMP_NAME.php"

    local out
    out=$(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
        wp eval-file "$SERVER_PATH/$TMP_NAME.php" --path="$WP_PATH")
    (cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- wp cache flush --path="$WP_PATH" >/dev/null)
    rm -f "$SITE_DIR/$TMP_NAME" "$SITE_DIR/$TMP_NAME.php"

    report "$out" "Local"
}

publish_production() {
    local thumb=""
    if [ -n "$IMAGE_FILE" ]; then
        print_step "Uploading featured image (production)"
        scp -q "$IMAGE_FILE" "$SERVER_USER@$SERVER_HOST:/tmp/$(basename "$IMAGE_FILE")"
        thumb=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp media import /tmp/$(basename "$IMAGE_FILE") --title=\"$TITLE\" --porcelain --path=$WP_PATH" | tail -1 | tr -dc '0-9')
        ssh "$SERVER_USER@$SERVER_HOST" "rm -f /tmp/$(basename "$IMAGE_FILE")"
        print_info "Production attachment ID: $thumb"
    fi

    print_step "Publishing to production"
    scp -q "$BODY_FILE" "$SERVER_USER@$SERVER_HOST:$SERVER_PATH/$TMP_NAME"
    build_php "$SERVER_PATH/$TMP_NAME" "$thumb" | ssh "$SERVER_USER@$SERVER_HOST" "cat > $SERVER_PATH/$TMP_NAME.php"

    local out
    out=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp eval-file $SERVER_PATH/$TMP_NAME.php --path=$WP_PATH")
    ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp cache flush --path=$WP_PATH >/dev/null; rm -f $SERVER_PATH/$TMP_NAME $SERVER_PATH/$TMP_NAME.php"

    report "$out" "Production"
}

if [ "$ENVIRONMENT" == "local" ] || [ "$ENVIRONMENT" == "both" ]; then
    publish_local
fi

if [ "$ENVIRONMENT" == "production" ] || [ "$ENVIRONMENT" == "both" ]; then
    if [ -n "$UPDATE_ID" ]; then
        print_warn "About to OVERWRITE production post ID $UPDATE_ID on $SERVER_HOST"
    else
        print_warn "About to CREATE a '$POST_STATUS' post at /$SLUG/ on $SERVER_HOST"
    fi
    read -p "Type 'yes' to continue: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        print_warn "Skipped production publish."
    else
        publish_production
    fi
fi

rm -f "$BODY_FILE"
print_info "Done."
