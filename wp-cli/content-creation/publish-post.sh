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
#   - uploads a featured image, sets _thumbnail_id and its alt text, and
#     rewrites the Article JSON-LD `image` field to the resulting *verified*
#     upload URL — the attachment URL differs per environment, so the body is
#     rebuilt per target rather than shared
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
# TRELLIS_DIR and SITE_DIR are only needed for a local (or both) run. TRELLIS_DIR
# is auto-detected from the current directory when unset, the same way
# scripts/backup/db-pull.sh does it; SITE_DIR defaults to the Bedrock checkout
# beside it. A production-only run needs neither.
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
# @flag     --alt        optional  {Alt text}  Alt text for the uploaded image (default: the post title)
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

# Walk up from $PWD looking for a Trellis project, stopping below $HOME.
# Mirrors go/internal/detect.TrellisDir and scripts/backup/db-pull.sh.
detect_trellis_dir() {
    local start="$PWD"
    local dir="$start"
    local previous="$start"

    while [[ -n "$dir" && "$dir" != "/" && "$dir" != "$HOME" ]]; do
        if [[ -f "$dir/ansible.cfg" && -d "$dir/group_vars" ]]; then
            echo "$dir"; return 0
        fi
        if [[ -f "$dir/trellis/ansible.cfg" ]]; then
            if [[ "$dir" == "$start" || -d "$previous/web/wp" ]]; then
                echo "$dir/trellis"; return 0
            fi
        fi
        previous="$dir"
        dir="$(dirname "$dir")"
    done
    return 1
}

# Confirms an auto-detected TRELLIS_DIR before using it — this writes content,
# so a non-interactive session refuses to guess rather than silently proceeding.
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
    [[ $REPLY =~ ^[Yy]$ ]] && return 0

    echo "Cancelled. Set it explicitly instead:"
    echo ""
    echo "  export TRELLIS_DIR=/path/to/your/project"
    echo ""
    return 1
}

DRAFT_FILE="$1"; shift || true
SITE_NAME="example.com"
ENVIRONMENT="local"

if [ -n "$1" ] && [[ "$1" != --* ]]; then SITE_NAME="$1"; shift; fi
if [ -n "$1" ] && [[ "$1" != --* ]]; then ENVIRONMENT="$1"; shift; fi

IMAGE_FILE=""
IMAGE_ALT=""
UPDATE_ID=""
POST_STATUS="publish"
DRY_RUN="no"

while [ $# -gt 0 ]; do
    case "$1" in
        --image)   IMAGE_FILE="$2"; shift 2 ;;
        --alt)     IMAGE_ALT="$2";  shift 2 ;;
        --update)  UPDATE_ID="$2";  shift 2 ;;
        --status)  POST_STATUS="$2"; shift 2 ;;
        --dry-run) DRY_RUN="yes";   shift ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$DRAFT_FILE" ]; then
    print_error "Usage: $0 <draft-file> [site-name] [local|production|both] [--image f] [--alt t] [--update id] [--status s] [--dry-run]"
    exit 1
fi
[ ! -f "$DRAFT_FILE" ] && { print_error "Draft file not found: $DRAFT_FILE"; exit 1; }
[ -n "$IMAGE_FILE" ] && [ ! -f "$IMAGE_FILE" ] && { print_error "Image file not found: $IMAGE_FILE"; exit 1; }
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
TITLE=$(sed -n 's/^<!-- SUGGESTED TITLE:[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')
SLUG=$(sed -n 's/^<!-- SUGGESTED POST SLUG:[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')
META_TITLE=$(sed -n 's/^<!-- SUGGESTED META TITLE[[:space:]]*([^)]*):[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')
META_DESC=$(sed -n 's/^<!-- SUGGESTED META[[:space:]]*(max[^)]*):[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')
TAGS=$(sed -n 's/^<!-- SUGGESTED TAGS:[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')
CATEGORY=$(sed -n 's/^<!-- SUGGESTED CATEGORY:[[:space:]]*\(.*\)[[:space:]]*-->$/\1/p' "$DRAFT_FILE" | head -1 | sed 's/[[:space:]]*$//')

SLUG="${SLUG#/}"; SLUG="${SLUG%/}"
[ -z "$IMAGE_ALT" ] && IMAGE_ALT="$TITLE"

[ -z "$TITLE" ] && { print_error "No '<!-- SUGGESTED TITLE: ... -->' found in $DRAFT_FILE"; exit 1; }
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

STAMP=$(date +%s)

# Write the header-stripped body to $1. Kept as a function because the Article
# JSON-LD `image` is rewritten per environment (attachment URLs differ), so the
# body is rebuilt for each target rather than shared.
prepare_body() {
    local out="$1" image_url="$2"
    grep -v '^<!-- SUGGESTED ' "$DRAFT_FILE" | grep -v '^{{--' | sed '/./,$!d' > "$out"

    if [ -n "$image_url" ]; then
        # Parse the JSON properly rather than sed-ing at it: the Article block is
        # real JSON-LD and a regex edit silently corrupts it on any nesting.
        local result
        result=$(python3 - "$out" "$image_url" <<'PY'
import sys, json, re
path, url = sys.argv[1], sys.argv[2]
src = open(path, encoding='utf-8').read()
changed = []

def repl(m):
    try:
        d = json.loads(m.group(1))
    except Exception:
        return m.group(0)
    if d.get('@type') != 'Article':
        return m.group(0)
    d['image'] = url
    changed.append(True)
    return ('<script type="application/ld+json">\n'
            + json.dumps(d, indent=2, ensure_ascii=False)
            + '\n</script>')

out = re.sub(r'<script type="application/ld\+json">(.*?)</script>', repl, src, flags=re.S)
if changed:
    open(path, 'w', encoding='utf-8').write(out)
print('injected' if changed else 'no-article-block')
PY
)
        if [ "$result" == "injected" ]; then
            print_info "Article schema image set to $image_url"
        else
            print_warn "No Article JSON-LD block found — image URL not injected into schema"
        fi
    fi
}

# Echoes "bytes ldjson scripts" for the prepared body at $1.
body_stats() {
    local f="$1"
    echo "$(wc -c < "$f" | tr -d ' ') $(grep -c 'application/ld+json' "$f" || true) $(grep -c '<script' "$f" || true)"
}

# ---------------------------------------------------------------------------
# Preflight (uses a body with no image URL — counts are unaffected by it)
# ---------------------------------------------------------------------------
PREFLIGHT_FILE="/tmp/tmp-publish-preflight-$STAMP.html"
prepare_body "$PREFLIGHT_FILE" ""
read -r PF_BYTES PF_LD PF_SC <<<"$(body_stats "$PREFLIGHT_FILE")"
print_info "Body: $PF_BYTES bytes, $PF_LD JSON-LD block(s), $PF_SC script tag(s)"

if [ "$PF_BYTES" -lt 500 ]; then
    print_error "Body is only $PF_BYTES bytes — refusing to publish a near-empty post"
    rm -f "$PREFLIGHT_FILE"; exit 1
fi
for bad in 'wp:columns' 'wp:callout' 'wp:acf/' 'wp:nynaeve/'; do
    grep -q "$bad" "$PREFLIGHT_FILE" && print_warn "Draft contains '$bad' — this renders as a broken block in posts"
done
# A self-closing custom block never hydrates when written via WP-CLI: Gutenberg
# builds its InnerBlocks template client-side on insert, so piping the one-liner
# into post_content saves a genuinely empty block with no visible output.
if grep -qE '<!-- wp:[a-z0-9-]+/[a-z0-9-]+ \{[^}]*\} /-->' "$PREFLIGHT_FILE"; then
    print_warn "Draft contains a self-closing custom block (\`/-->\`) — it will save EMPTY via WP-CLI."
    print_warn "Hand-build the full serialized markup instead."
fi
rm -f "$PREFLIGHT_FILE"

if [ "$DRY_RUN" == "yes" ]; then
    print_info "Dry run — no changes made."
    exit 0
fi

# ---------------------------------------------------------------------------
# PHP worker
# ---------------------------------------------------------------------------
build_php() {
    local remote_body="$1" thumb_id="$2" bytes="$3" ldjson="$4" scripts="$5"
    cat <<PHP
<?php
\$body = file_get_contents( '$remote_body' );
if ( \$body === false || strlen( \$body ) < 500 ) { echo "ABORT: body missing or too short\n"; return; }
if ( strlen( \$body ) !== $bytes ) { echo "ABORT: body length changed in transit\n"; return; }

\$update_id = '$UPDATE_ID';
\$slug      = '$SLUG';

if ( \$update_id ) {
    if ( ! get_post( (int) \$update_id ) ) { echo "ABORT: post \$update_id not found\n"; return; }
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
        \$term = get_term_by( 'name', \$t, 'post_tag' );
        if ( ! \$term ) { \$term = get_term_by( 'slug', sanitize_title( \$t ), 'post_tag' ); }
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
echo "ldjson=\$ld/$ldjson\n";
echo "scripts=\$sc/$scripts\n";
echo "status=" . \$saved->post_status . "\n";
if ( \$stored !== $bytes ) { echo "VERIFY_FAIL: stored bytes differ from source — content was altered on write\n"; }
elseif ( \$ld !== $ldjson || \$sc !== $scripts ) { echo "VERIFY_FAIL: script/JSON-LD blocks were stripped (kses?)\n"; }
else { echo "VERIFY_OK\n"; }
PHP
}

report() {
    local out="$1" label="$2"
    echo "$out" | grep -E '^(WARN|ABORT|ERROR):' | while read -r l; do print_warn "$l"; done
    if echo "$out" | grep -q '^VERIFY_OK'; then
        print_info "$label: $(echo "$out" | sed -n 's/^permalink=//p')"
        print_info "$label: verified — $(echo "$out" | sed -n 's/^stored_bytes=//p') bytes stored, JSON-LD $(echo "$out" | sed -n 's/^ldjson=//p'), scripts $(echo "$out" | sed -n 's/^scripts=//p')"
    else
        print_error "$label: verification FAILED"
        echo "$out" | sed 's/^/    /'
        return 1
    fi
}

publish_local() {
    if [ -z "$TRELLIS_DIR" ]; then
        local detected
        if detected=$(detect_trellis_dir); then
            confirm_trellis_dir "$detected" || exit 1
            TRELLIS_DIR="$detected"
        else
            print_error "TRELLIS_DIR is not set and no Trellis project was found from $PWD."
            echo "  export TRELLIS_DIR=/path/to/trellis" >&2
            exit 1
        fi
    fi
    # The Bedrock checkout sits beside trellis/ in a standard Trellis project.
    [ -z "$SITE_DIR" ] && SITE_DIR="$(dirname "$TRELLIS_DIR")/site"
    if [ ! -d "$SITE_DIR" ]; then
        print_error "SITE_DIR not found: $SITE_DIR — set it explicitly."
        exit 1
    fi

    local thumb="" image_url=""
    if [ -n "$IMAGE_FILE" ]; then
        print_step "Uploading featured image (local)"
        local base; base=$(basename "$IMAGE_FILE")
        cp "$IMAGE_FILE" "$SITE_DIR/$base"
        thumb=$(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
            wp media import "$SERVER_PATH/$base" --title="$TITLE" --alt="$IMAGE_ALT" --porcelain --path="$WP_PATH" | tail -1 | tr -dc '0-9')
        rm -f "$SITE_DIR/$base"
        if [ -n "$thumb" ]; then
            image_url=$(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
                wp post get "$thumb" --field=guid --path="$WP_PATH" | tail -1 | tr -d '\r')
            print_info "Local attachment $thumb — $image_url"
        else
            print_warn "Image upload returned no attachment ID — continuing without a featured image"
        fi
    fi

    print_step "Publishing to local"
    local body="/tmp/tmp-publish-local-$STAMP.html"
    prepare_body "$body" "$image_url"
    read -r B L S <<<"$(body_stats "$body")"

    cp "$body" "$SITE_DIR/$(basename "$body")"
    build_php "$SERVER_PATH/$(basename "$body")" "$thumb" "$B" "$L" "$S" > "$SITE_DIR/$(basename "$body").php"

    local out
    out=$(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
        wp eval-file "$SERVER_PATH/$(basename "$body").php" --path="$WP_PATH")
    (cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- wp cache flush --path="$WP_PATH" >/dev/null)
    rm -f "$SITE_DIR/$(basename "$body")" "$SITE_DIR/$(basename "$body").php" "$body"

    report "$out" "Local"
}

publish_production() {
    local thumb="" image_url=""
    if [ -n "$IMAGE_FILE" ]; then
        print_step "Uploading featured image (production)"
        local base; base=$(basename "$IMAGE_FILE")
        scp -q "$IMAGE_FILE" "$SERVER_USER@$SERVER_HOST:/tmp/$base"
        thumb=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp media import /tmp/$base --title=\"$TITLE\" --alt=\"$IMAGE_ALT\" --porcelain --path=$WP_PATH" | tail -1 | tr -dc '0-9')
        ssh "$SERVER_USER@$SERVER_HOST" "rm -f /tmp/$base"
        if [ -n "$thumb" ]; then
            image_url=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp post get $thumb --field=guid --path=$WP_PATH" | tr -d '\r')
            print_info "Production attachment $thumb — $image_url"
        else
            print_warn "Image upload returned no attachment ID — continuing without a featured image"
        fi
    fi

    print_step "Publishing to production"
    local body="/tmp/tmp-publish-prod-$STAMP.html"
    prepare_body "$body" "$image_url"
    read -r B L S <<<"$(body_stats "$body")"

    local base; base=$(basename "$body")
    scp -q "$body" "$SERVER_USER@$SERVER_HOST:$SERVER_PATH/$base"
    build_php "$SERVER_PATH/$base" "$thumb" "$B" "$L" "$S" | ssh "$SERVER_USER@$SERVER_HOST" "cat > $SERVER_PATH/$base.php"

    local out
    out=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp eval-file $SERVER_PATH/$base.php --path=$WP_PATH")
    ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp cache flush --path=$WP_PATH >/dev/null; rm -f $SERVER_PATH/$base $SERVER_PATH/$base.php"
    rm -f "$body"

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

print_info "Done."
