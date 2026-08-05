#!/bin/bash
#
# create-product-variations.sh - Bulk-create WooCommerce product variations via WP-CLI
#
# Usage:
#   ./create-product-variations.sh [-d|--dry-run]
#
# Options:
#   -d, --dry-run   Print the wp wc product_variation create commands without running them
#
# Examples:
#   ./create-product-variations.sh                        # Uses config below
#   ./create-product-variations.sh --dry-run               # Preview without creating anything
#   PRODUCT_ID=42 ./create-product-variations.sh          # Override product ID inline
#
# Notes:
#   - Targets the WooCommerce sub-site store via --url (multisite).
#     Omit SITE_URL's store path and terms/variations land on the main site.
#   - Attribute values must already exist as terms before running this script.
#     See: wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md
#
# @desc     Bulk-create WooCommerce product variations via WP-CLI over Trellis vm shell
# @category misc
# @platform trellis
# @runs     local
# @requires trellis
# @flag     --dry-run  optional  {}  Print the planned wp wc product_variation create commands without running them
# @example  wp-ops scripts/woocommerce/create-product-variations
# @example  wp-ops scripts/woocommerce/create-product-variations --dry-run
# @doc      docs/wordpress-utilities/snippets/woocommerce-product-attributes-wpcli.md
#

set -euo pipefail

# ============================================================================
# Argument parsing
# ============================================================================

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    -d|--dry-run)
      DRY_RUN=1
      ;;
  esac
done

# ============================================================================
# Configuration
# ============================================================================

TRELLIS_DIR="${TRELLIS_DIR:-/path/to/trellis}"
WORKDIR="${WORKDIR:-/srv/www/example.com/current}"
SITE_URL="${SITE_URL:-http://example.test/store}"   # include /store for multisite
PRODUCT_ID="${PRODUCT_ID:-36}"                       # parent variable product ID
REGULAR_PRICE="${REGULAR_PRICE:-99}"
WP_USER="${WP_USER:-admin}"
WP_PATH="${WP_PATH:-web/wp}"

# Attribute arrays — edit to match your product's registered attributes
ATTR1_SLUG="pa_leather-colour"
ATTR1_VALUES=("Tan" "Black" "Cognac" "Chestnut" "Navy")

ATTR2_SLUG="pa_style"
ATTR2_VALUES=("A4 with Notepad" "A4 Slim" "A5 with Notepad")

# ============================================================================
# Main
# ============================================================================

CREATED=0
FAILED=0

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[DRY RUN] Previewing variations for product ID ${PRODUCT_ID} on ${SITE_URL}"
else
  echo "Creating variations for product ID ${PRODUCT_ID} on ${SITE_URL}"
fi
echo "Attributes: ${ATTR1_SLUG} × ${ATTR2_SLUG}"
echo "---"

for val1 in "${ATTR1_VALUES[@]}"; do
  for val2 in "${ATTR2_VALUES[@]}"; do
    WP_CMD=(wp --url="$SITE_URL" wc product_variation create "$PRODUCT_ID" \
      --attributes="[{\"attribute\": \"${ATTR1_SLUG}\", \"value\": \"${val1}\"}, {\"attribute\": \"${ATTR2_SLUG}\", \"value\": \"${val2}\"}]" \
      --regular_price="$REGULAR_PRICE" \
      --user="$WP_USER" \
      --path="$WP_PATH")

    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[DRY RUN] ${val1} / ${val2} — ${WP_CMD[*]}"
      continue
    fi

    RESULT=$(cd "$TRELLIS_DIR" && trellis vm shell --workdir "$WORKDIR" -- \
      "${WP_CMD[@]}" 2>&1 | grep -E "Success|Error|Created")

    if echo "$RESULT" | grep -q "Success\|Created"; then
      echo "[OK]   ${val1} / ${val2} — ${RESULT}"
      CREATED=$((CREATED + 1))
    else
      echo "[FAIL] ${val1} / ${val2} — ${RESULT}"
      FAILED=$((FAILED + 1))
    fi
  done
done

echo "---"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete: $(( ${#ATTR1_VALUES[@]} * ${#ATTR2_VALUES[@]} )) variation(s) would be created. No changes made."
else
  echo "Done: ${CREATED} created, ${FAILED} failed."
fi
