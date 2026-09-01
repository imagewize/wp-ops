#!/bin/bash
#
# Verify that a published WordPress post survived the write intact — that its
# JSON-LD, custom blocks and internal links are actually stored and actually
# rendering. Run it against any post, not just one this toolkit published.
#
# Why this is a command and not a mental checklist: every way content silently
# disappears on this stack is invisible to a normal review.
#
#   - kses strips <script type="application/ld+json"> when WP-CLI runs with a
#     --user that lacks unfiltered_html. The post saves fine. The schema is
#     just gone.
#   - A self-closing custom block one-liner (`<!-- wp:ns/block {...} /-->`)
#     piped into post_content saves as a genuinely EMPTY block — no output, not
#     even a broken-block placeholder. A post_content diff shows nothing wrong.
#   - A cached page can keep serving the previous render after an update.
#
# All three produce a post that looks correct in the editor and in a diff, and
# is wrong on the live page. This compares what is STORED against what RENDERS.
#
# Usage:
#   ./verify-post.sh <post-id-or-slug> [site-name] [environment]
#
# @desc     Verify a published post's JSON-LD, blocks and links survived the write and render live
# @category content
# @platform trellis
# @runs     local
# @requires ssh trellis
# @arg      post         required  {13681}  Post ID or slug to verify
# @arg      site-name    optional  {example.com}  Site name under /srv/www (default: example.com)
# @arg      environment  optional  {local|production}  Where to check (default: production)
# @example  wp-ops verify-post 13681 example.com production
# @example  wp-ops verify-post my-post-slug example.com production

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
print_pass()  { echo -e "  ${GREEN}PASS${NC}  $1"; }
print_fail()  { echo -e "  ${RED}FAIL${NC}  $1"; }

POST_REF="$1"
SITE_NAME="${2:-example.com}"
ENVIRONMENT="${3:-production}"

if [ -z "$POST_REF" ]; then
    print_error "Usage: $0 <post-id-or-slug> [site-name] [local|production]"
    exit 1
fi
case "$ENVIRONMENT" in
    local|production) ;;
    *) print_error "Invalid environment: $ENVIRONMENT (must be local or production)"; exit 1 ;;
esac

SERVER_USER="web"
SERVER_HOST="$SITE_NAME"
SERVER_PATH="/srv/www/$SITE_NAME/current"
WP_PATH="web/wp"

# PHP worker: report what is STORED for the post, as key=value lines.
# __POST_REF__ is substituted below rather than read from the environment —
# env vars don't survive `trellis vm shell` and ssh consistently.
read -r -d '' PHP_SRC <<'PHP' || true
$ref = '__POST_REF__';
$post = ctype_digit( $ref ) ? get_post( (int) $ref ) : get_page_by_path( trim( $ref, '/' ), OBJECT, 'post' );
if ( ! $post ) { echo "ABORT: post '$ref' not found\n"; return; }
$c = $post->post_content;
echo "id=" . $post->ID . "\n";
echo "status=" . $post->post_status . "\n";
echo "permalink=" . get_permalink( $post->ID ) . "\n";
echo "stored_bytes=" . strlen( $c ) . "\n";
echo "ldjson=" . substr_count( $c, 'application/ld+json' ) . "\n";
echo "scripts=" . substr_count( $c, '<script' ) . "\n";
echo "thumbnail=" . ( get_post_thumbnail_id( $post->ID ) ?: '0' ) . "\n";
echo "meta_title=" . ( get_post_meta( $post->ID, '_genesis_title', true ) ?: '' ) . "\n";
echo "meta_desc_len=" . strlen( (string) get_post_meta( $post->ID, '_genesis_description', true ) ) . "\n";
preg_match_all( '/<!-- wp:([a-z0-9-]+\/[a-z0-9-]+) (\{[^}]*\} )?\/-->/', $c, $m );
echo "selfclosing=" . count( $m[0] ) . "\n";
echo "selfclosing_names=" . implode( ',', array_unique( $m[1] ) ) . "\n";
preg_match_all( '/href="(\/[^"#][^"]*)"/', $c, $lm );
echo "internal_links=" . count( array_unique( $lm[1] ) ) . "\n";
echo "internal_list=" . implode( ' ', array_unique( $lm[1] ) ) . "\n";
PHP

# Substitute the post reference into the worker source.
PHP_BODY="${PHP_SRC//__POST_REF__/$POST_REF}"

run_wp_eval() {
    if [ "$ENVIRONMENT" == "local" ]; then
        if [ -z "$TRELLIS_DIR" ]; then
            print_error "TRELLIS_DIR must be set for a local check"; exit 1
        fi
        # `wp eval` takes bare source — no opening tag.
        (cd "$TRELLIS_DIR" && trellis vm shell --workdir "$SERVER_PATH" -- \
            wp eval "$PHP_BODY" --path="$WP_PATH")
    else
        # `wp eval-file` include()s the file, so it needs a real opening tag —
        # without one WP-CLI echoes the source verbatim instead of running it.
        printf '<?php\n%s\n' "$PHP_BODY" | ssh "$SERVER_USER@$SERVER_HOST" \
            "cat > /tmp/wpops-verify.php && cd $SERVER_PATH && wp eval-file /tmp/wpops-verify.php --path=$WP_PATH; rm -f /tmp/wpops-verify.php"
    fi
}

print_step "Reading stored content for '$POST_REF' ($ENVIRONMENT)"
STORED=$(run_wp_eval)

if echo "$STORED" | grep -q '^ABORT:'; then
    print_error "$(echo "$STORED" | grep '^ABORT:')"
    exit 1
fi

# $2 is the fallback when the key is absent, so a partial worker response
# produces a clean failure rather than "integer expression expected" noise.
val() {
    local v
    v=$(echo "$STORED" | sed -n "s/^$1=//p" | head -1)
    echo "${v:-$2}"
}

POST_ID=$(val id)
PERMALINK=$(val permalink)
STATUS=$(val status)
STORED_BYTES=$(val stored_bytes 0)
LDJSON=$(val ldjson 0)
SCRIPTS=$(val scripts 0)
THUMB=$(val thumbnail 0)
META_TITLE=$(val meta_title)
META_DESC_LEN=$(val meta_desc_len 0)
SELFCLOSING=$(val selfclosing 0)
SELFCLOSING_NAMES=$(val selfclosing_names)
INTERNAL_LINKS=$(val internal_links 0)
INTERNAL_LIST=$(val internal_list)

echo
print_info "Post $POST_ID ($STATUS) — $PERMALINK"
print_info "Stored: $STORED_BYTES bytes, $LDJSON JSON-LD block(s), $SCRIPTS script tag(s), thumbnail $THUMB"
echo

FAILED=0

print_step "Stored content"
if [ "$LDJSON" -gt 0 ]; then
    print_pass "$LDJSON JSON-LD block(s) present in post_content"
else
    print_warn "No JSON-LD in post_content (fine if the SEO plugin emits all schema)"
fi
if [ "$SELFCLOSING" -gt 0 ]; then
    print_fail "$SELFCLOSING self-closing custom block(s): $SELFCLOSING_NAMES"
    echo "        These save EMPTY when written via WP-CLI — hand-build the serialized markup."
    FAILED=1
else
    print_pass "No self-closing custom blocks (none can have saved empty)"
fi
if [ -n "$META_TITLE" ]; then
    if [ "${#META_TITLE}" -gt 55 ]; then
        print_warn "Meta title is ${#META_TITLE} chars (>55) — truncates once '| Site' is appended"
    else
        print_pass "Meta title set (${#META_TITLE} chars)"
    fi
else
    print_warn "No _genesis_title set — the SEO plugin will fall back to the post title"
fi
if [ "$META_DESC_LEN" -gt 155 ]; then
    print_warn "Meta description is $META_DESC_LEN chars (>155) — truncates in SERPs"
elif [ "$META_DESC_LEN" -gt 0 ]; then
    print_pass "Meta description set ($META_DESC_LEN chars)"
else
    print_warn "No _genesis_description set"
fi
[ "$THUMB" != "0" ] && print_pass "Featured image set (attachment $THUMB)" || print_warn "No featured image — og:image will fall back to the site logo"

echo
print_step "Live render"
HTTP=$(curl -s -o /tmp/wpops-verify-live.html -w '%{http_code}' "$PERMALINK" || echo 000)
if [ "$HTTP" != "200" ]; then
    print_fail "$PERMALINK returned HTTP $HTTP"
    FAILED=1
else
    print_pass "HTTP 200"
    LIVE_LD=$(grep -c 'application/ld+json' /tmp/wpops-verify-live.html || true)
    if [ "$LDJSON" -gt 0 ] && [ "$LIVE_LD" -lt "$LDJSON" ]; then
        print_fail "Only $LIVE_LD JSON-LD block(s) render, but $LDJSON are stored — stripped on output"
        FAILED=1
    else
        print_pass "$LIVE_LD JSON-LD block(s) render (>= $LDJSON stored)"
    fi

    # Schema types actually emitted
    TYPES=$(grep -o '"@type"[[:space:]]*:[[:space:]]*"[A-Za-z]*"' /tmp/wpops-verify-live.html | sed 's/.*"\([A-Za-z]*\)"$/\1/' | sort -u | tr '\n' ' ')
    [ -n "$TYPES" ] && print_info "  schema types: $TYPES"

    # Every internal link stored should resolve
    if [ "$INTERNAL_LINKS" -gt 0 ]; then
        BROKEN=0
        CHECKED=0
        BASE=$(echo "$PERMALINK" | sed -E 's#(https?://[^/]+).*#\1#')
        for path in $INTERNAL_LIST; do
            case "$path" in
                *\?*) continue ;;   # skip query-string CTAs
            esac
            CHECKED=$((CHECKED+1))
            CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE$path" || echo 000)
            if [ "$CODE" != "200" ]; then
                print_fail "internal link $path -> HTTP $CODE"
                BROKEN=$((BROKEN+1)); FAILED=1
            fi
        done
        # Report what was actually requested, not what was stored — query-string
        # links are skipped above, so the two numbers differ.
        [ "$BROKEN" -eq 0 ] && print_pass "$CHECKED internal link(s) all resolve"
    fi

    # An empty custom-block wrapper renders as a div with no text
    if grep -qE 'class="wp-block-[a-z0-9-]+-cta[^"]*"></div>' /tmp/wpops-verify-live.html; then
        print_fail "A CTA block wrapper rendered EMPTY on the live page"
        FAILED=1
    fi
fi

rm -f /tmp/wpops-verify-live.html
echo
if [ "$FAILED" -eq 0 ]; then
    print_info "All checks passed."
else
    print_error "One or more checks FAILED — see above."
    exit 1
fi
