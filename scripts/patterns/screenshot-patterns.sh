#!/usr/bin/env bash
#
# Pattern Screenshot Tool
#
# Automates screenshotting WordPress block patterns and converting them to WebP:
#   1. Creates a temporary WordPress page containing the pattern
#   2. Screenshots the pattern element with Playwright
#   3. Deletes the temporary page
#   4. Converts all captured PNGs to WebP
#
# Configuration (environment variables):
#   WP_CLI_CMD         WP-CLI invocation prefix (default: "wp"). Point this at
#                       whatever actually runs WP-CLI for the target site:
#                         WP_CLI_CMD="wp --path=web/wp"
#                         WP_CLI_CMD="trellis vm shell --workdir /srv/www/example.com/current -- wp"
#                         WP_CLI_CMD="ssh web@example.com -- wp --path=/srv/www/example.com/current/web/wp"
#   SITE_URL            Base URL the temp page is reachable at (default: http://example.test)
#   PATTERN_NAMESPACE   Theme namespace used in the pattern slug, e.g. "moiraine" for
#                        <!-- wp:pattern {"slug":"moiraine/hero-dark"} /--> (required)
#   OUTPUT_DIR          Where PNG/WebP screenshots are saved (default: ./screenshots)
#   VIEWPORT_WIDTH      Screenshot viewport width (default: 1400)
#   VIEWPORT_HEIGHT     Screenshot viewport height (default: 900)
#
# Usage:
#   PATTERN_NAMESPACE=mytheme SITE_URL=http://example.test WP_CLI_CMD="wp --path=web/wp" \
#     ./screenshot-patterns.sh <pattern-slug> [pattern-slug2 ...]
#
# Requirements:
#   npm install   (from this directory, installs playwright + sharp)
#   npx playwright install chromium
#
# @desc     Screenshot WordPress block patterns end-to-end (temp page, Playwright capture, WebP convert)
# @category content
# @platform wordpress
# @runs     local
# @requires node
# @arg      pattern-slug  required  {hero-dark}  Pattern slug(s) to screenshot (repeatable)
# @example  PATTERN_NAMESPACE=mytheme SITE_URL=http://example.test wp-ops scripts/patterns/screenshot-patterns hero-dark
# @doc      scripts/patterns/README.md

set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
NC=$'\033[0m'

log_info()    { echo -e "${CYAN}i ${NC}$1"; }
log_success() { echo -e "${GREEN}+${NC} $1"; }
log_error()   { echo -e "${RED}x${NC} $1"; }
log_warning() { echo -e "${YELLOW}!${NC} $1"; }
log_header()  { echo -e "${MAGENTA}$1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WP_CLI_CMD="${WP_CLI_CMD:-wp}"
SITE_URL="${SITE_URL:-http://example.test}"
PATTERN_NAMESPACE="${PATTERN_NAMESPACE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/screenshots}"
VIEWPORT_WIDTH="${VIEWPORT_WIDTH:-1400}"
VIEWPORT_HEIGHT="${VIEWPORT_HEIGHT:-900}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
${MAGENTA}Pattern Screenshot Tool${NC}

Usage:
  PATTERN_NAMESPACE=<theme> [SITE_URL=...] [WP_CLI_CMD=...] $(basename "$0") <pattern-slug> [pattern-slug2 ...]

See the header comment in this script for full configuration docs.
EOF
    exit 0
fi

if [ -z "$PATTERN_NAMESPACE" ]; then
    log_error "PATTERN_NAMESPACE is required, e.g. PATTERN_NAMESPACE=moiraine $(basename "$0") hero-dark"
    exit 1
fi

if [ $# -eq 0 ]; then
    log_error "No pattern slugs provided"
    echo "Usage: PATTERN_NAMESPACE=<theme> $(basename "$0") <pattern-slug> [pattern-slug2 ...]"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/screenshot-url.js" ]; then
    log_error "screenshot-url.js not found next to this script"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

PATTERN_SLUGS=("$@")
log_header "════════════════════════════════════════════════════"
log_header "  Pattern Screenshot Tool"
log_header "════════════════════════════════════════════════════"
log_info "Namespace: $PATTERN_NAMESPACE  |  Site: $SITE_URL"
log_info "Patterns to screenshot: ${#PATTERN_SLUGS[@]}"
echo ""

SCREENSHOT_COUNT=0
FAILED_PATTERNS=()

for slug in "${PATTERN_SLUGS[@]}"; do
    log_info "Screenshotting pattern: $slug"

    temp_slug="pattern-screenshot-$slug"
    pattern_content="<!-- wp:pattern {\"slug\":\"$PATTERN_NAMESPACE/$slug\"} /-->"

    page_id=$($WP_CLI_CMD post create \
        --post_type=page \
        --post_title="Pattern Screenshot: $slug" \
        --post_name="$temp_slug" \
        --post_status=publish \
        --post_content="$pattern_content" \
        --porcelain | tail -n 1 | tr -d '[:space:]')

    if [[ ! "$page_id" =~ ^[0-9]+$ ]]; then
        log_error "Failed to create temp page for: $slug"
        FAILED_PATTERNS+=("$slug")
        echo ""
        continue
    fi

    page_url="$SITE_URL/$temp_slug/"

    if node "$SCRIPT_DIR/screenshot-url.js" "$page_url" \
        --out="$OUTPUT_DIR/pattern-$slug.png" \
        --width="$VIEWPORT_WIDTH" --height="$VIEWPORT_HEIGHT"; then
        log_success "Screenshot created: pattern-$slug.png"
        ((SCREENSHOT_COUNT++))
    else
        log_error "Failed to screenshot: $slug"
        FAILED_PATTERNS+=("$slug")
    fi

    $WP_CLI_CMD post delete "$page_id" --force > /dev/null
    echo ""
done

if [ $SCREENSHOT_COUNT -eq 0 ]; then
    log_error "No screenshots were created successfully"
    exit 1
fi

log_header "Converting to WebP"
log_header "────────────────────────────────────────────────────"
node "$SCRIPT_DIR/convert-to-webp.js" --all --dir="$OUTPUT_DIR"

echo ""
log_success "Successfully processed: $SCREENSHOT_COUNT pattern(s)"
if [ ${#FAILED_PATTERNS[@]} -gt 0 ]; then
    log_warning "Failed patterns: ${FAILED_PATTERNS[*]}"
fi
log_info "Output directory: $OUTPUT_DIR"
