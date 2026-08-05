#!/usr/bin/env bash
#
# Schema Markup Audit Script
# Purpose: Check for schema markup on key pages and validate implementation
# Output: Text reports with schema detection results
#
# Usage: ./schema-audit.sh [OPTIONS] <site-url>
#
# Options:
#   --output DIR      Output directory (default: audits)
#   --pages P1,P2    Comma-separated list of page paths to check (default: common pages)
#   -h, --help        Show this help
#
# Requires: curl, grep
#
# @desc     Check key pages for schema markup and validate implementation
# @category seo
# @platform wordpress
# @runs     local
# @requires curl
# @arg      site-url  required  {https://example.com}  Site URL to check
# @flag     --output  optional  {audits}  Output directory
# @flag     --pages   optional  {/,/about/,/contact/}  Comma-separated page paths to check
# @example  wp-ops schema-audit https://example.com --pages /,/services/,/contact/
# @doc      wp-cli/seo/README.md

set -euo pipefail

# Configuration
OUTPUT_DIR="audits"
DATE=$(date +%Y-%m-%d)
SCHEMA_AUDIT_FILE="${OUTPUT_DIR}/schema-audit-${DATE}.txt"

# Default pages to check for schema (name|url pairs)
DEFAULT_PAGES=(
  "Homepage|/"
  "Services|/services/"
  "About|/about/"
  "About Us|/about-us/"
  "Contact|/contact/"
  "Contact Us|/contact-us/"
  "Portfolio|/portfolio/"
  "Shop|/shop/"
  "Blog|/blog/"
  "Insights|/insights/"
  "News|/news/"
)

# Parse arguments
SITE_URL=""
CUSTOM_PAGES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_DIR="$2"
            SCHEMA_AUDIT_FILE="${OUTPUT_DIR}/schema-audit-${DATE}.txt"
            shift 2
            ;;
        --pages)
            CUSTOM_PAGES="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS] <site-url>"
            echo ""
            echo "Options:"
            echo "  --output DIR      Output directory (default: audits)"
            echo "  --pages P1,P2    Comma-separated list of page paths (e.g., /,/about/,/contact/)"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") https://example.com"
            echo "  $(basename "$0") https://example.com --output reports/seo"
            echo "  $(basename "$0") https://example.com --pages /,/services/,/contact/"
            exit 0
            ;;
        *)
            if [[ -z "$SITE_URL" ]]; then
                SITE_URL="$1"
            else
                echo "Unknown option: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate site URL
if [[ -z "$SITE_URL" ]]; then
    echo "Error: Site URL is required."
    echo "Example: $(basename "$0") https://example.com"
    exit 1
fi

# Ensure site URL ends with /
if [[ "$SITE_URL" != */ ]]; then
    SITE_URL="${SITE_URL}/"
fi

# Use custom pages if provided, otherwise use defaults
if [[ -n "$CUSTOM_PAGES" ]]; then
    IFS=',' read -ra PAGES_TO_CHECK <<< "$CUSTOM_PAGES"
    # Convert to name|url format
    PAGES_TO_CHECK=()
    for page in ${CUSTOM_PAGES//,/ }; do
        page_name=$(echo "$page" | sed 's|/||g' | sed 's|-| |g' | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
        PAGES_TO_CHECK+=("${page_name}|${page}")
    done
else
    PAGES_TO_CHECK=("${DEFAULT_PAGES[@]}")
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Extract domain for display
DOMAIN=$(echo "$SITE_URL" | sed -E 's|^https?://||' | sed -E 's|/.*||')

echo "=========================================="
echo "Schema Markup Audit - ${DOMAIN}"
echo "Date: ${DATE}"
echo "=========================================="
echo ""

# Start report
cat > "${SCHEMA_AUDIT_FILE}" <<EOF
========================================
SCHEMA MARKUP AUDIT
Site: ${SITE_URL}
Date: ${DATE}
========================================

EOF

# Function to check schema on a page
check_schema() {
  local page_name=$1
  local page_url=$2
  local full_url="${SITE_URL}${page_url}"

  echo "Checking: ${page_name} (${page_url})"
  echo "" >> "${SCHEMA_AUDIT_FILE}"
  echo "=== ${page_name} ===" >> "${SCHEMA_AUDIT_FILE}"
  echo "URL: ${full_url}" >> "${SCHEMA_AUDIT_FILE}"
  echo "" >> "${SCHEMA_AUDIT_FILE}"

  # Check if page exists (returns 200)
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${full_url}" 2>/dev/null || echo "0")

  if [ "$HTTP_STATUS" != "200" ]; then
    echo "   ⚠ Skipping: Page not found (HTTP ${HTTP_STATUS})"
    echo "Status: ⚠ PAGE NOT FOUND (HTTP ${HTTP_STATUS})" >> "${SCHEMA_AUDIT_FILE}"
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    echo "---" >> "${SCHEMA_AUDIT_FILE}"
    return
  fi

  # Fetch page and look for JSON-LD schema. Plugins like Yoast/Rank Math add
  # extra attributes (e.g. class="yoast-schema-graph") to the script tag, so
  # match on the type attribute rather than requiring an exact opening tag.
  SCHEMA_CONTENT=$(curl -s "${full_url}" | grep -oE '<script[^>]*type="application/ld\+json"[^>]*>.*</script>' || echo "")

  if [ -z "$SCHEMA_CONTENT" ]; then
    echo "   ❌ No JSON-LD schema found"
    echo "Status: ❌ NO SCHEMA FOUND" >> "${SCHEMA_AUDIT_FILE}"
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    echo "---" >> "${SCHEMA_AUDIT_FILE}"
    return
  fi

  # Extract and analyze schema
  echo "   ✓ Schema markup found"
  echo "Status: ✓ SCHEMA PRESENT" >> "${SCHEMA_AUDIT_FILE}"
  echo "" >> "${SCHEMA_AUDIT_FILE}"

  # Check for specific schema types
  SCHEMA_TYPES=("Organization" "LocalBusiness" "Service" "Product" "WebSite" "BreadcrumbList" "Article" "FAQPage" "HowTo")
  
  for schema_type in "${SCHEMA_TYPES[@]}"; do
    if echo "$SCHEMA_CONTENT" | grep -q "\"@type\":.*\"${schema_type}\""; then
      echo "   ✓ ${schema_type} schema detected"
      echo "   - ${schema_type} schema: ✓" >> "${SCHEMA_AUDIT_FILE}"
    fi
  done

  # Save raw schema for review
  echo "" >> "${SCHEMA_AUDIT_FILE}"
  echo "Raw Schema:" >> "${SCHEMA_AUDIT_FILE}"
  echo "$SCHEMA_CONTENT" | sed -E 's/<script[^>]*type="application\/ld\+json"[^>]*>//g' | sed 's/<\/script>//g' >> "${SCHEMA_AUDIT_FILE}"
  echo "" >> "${SCHEMA_AUDIT_FILE}"
  echo "---" >> "${SCHEMA_AUDIT_FILE}"
}

# Check each page
PAGES_WITH_SCHEMA=0
PAGES_WITHOUT_SCHEMA=0
TOTAL_PAGES=${#PAGES_TO_CHECK[@]}

for page_entry in "${PAGES_TO_CHECK[@]}"; do
  # Split name and URL
  page_name="${page_entry%%|*}"
  page_url="${page_entry##*|}"

  # Check if page exists (returns 200)
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${SITE_URL}${page_url}" 2>/dev/null || echo "0")

  if [ "$HTTP_STATUS" != "200" ]; then
    echo "⚠ Skipping ${page_name}: Page not found (HTTP ${HTTP_STATUS})"
    echo "=== ${page_name} ===" >> "${SCHEMA_AUDIT_FILE}"
    echo "URL: ${SITE_URL}${page_url}" >> "${SCHEMA_AUDIT_FILE}"
    echo "Status: ⚠ PAGE NOT FOUND (HTTP ${HTTP_STATUS})" >> "${SCHEMA_AUDIT_FILE}"
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    echo "---" >> "${SCHEMA_AUDIT_FILE}"
    continue
  fi

  # Check schema
  SCHEMA_FOUND=$(curl -s "${SITE_URL}${page_url}" | grep -cE '<script[^>]*type="application/ld\+json"[^>]*>' || echo "0")

  if [ "$SCHEMA_FOUND" -gt 0 ]; then
    PAGES_WITH_SCHEMA=$((PAGES_WITH_SCHEMA + 1))
    check_schema "$page_name" "$page_url"
  else
    PAGES_WITHOUT_SCHEMA=$((PAGES_WITHOUT_SCHEMA + 1))
    echo "❌ ${page_name}: No schema"
    echo "=== ${page_name} ===" >> "${SCHEMA_AUDIT_FILE}"
    echo "URL: ${SITE_URL}${page_url}" >> "${SCHEMA_AUDIT_FILE}"
    echo "Status: ❌ NO SCHEMA FOUND" >> "${SCHEMA_AUDIT_FILE}"
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    echo "---" >> "${SCHEMA_AUDIT_FILE}"
  fi

  echo ""
  sleep 1  # Be nice to the server

done

# Generate summary
cat >> "${SCHEMA_AUDIT_FILE}" <<EOF

========================================
SCHEMA AUDIT SUMMARY
========================================

Pages Checked: ${TOTAL_PAGES}
Pages with Schema: ${PAGES_WITH_SCHEMA}
Pages without Schema: ${PAGES_WITHOUT_SCHEMA}

EOF

if [[ $PAGES_WITHOUT_SCHEMA -gt 0 ]]; then
    cat >> "${SCHEMA_AUDIT_FILE}" <<EOF
PAGES NEEDING SCHEMA MARKUP:
EOF
    # Re-run to list pages without schema
    for page_entry in "${PAGES_TO_CHECK[@]}"; do
        page_name="${page_entry%%|*}"
        page_url="${page_entry##*|}"
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${SITE_URL}${page_url}" 2>/dev/null || echo "0")
        if [ "$HTTP_STATUS" = "200" ]; then
            SCHEMA_FOUND=$(curl -s "${SITE_URL}${page_url}" | grep -cE '<script[^>]*type="application/ld\+json"[^>]*>' || echo "0")
            if [ "$SCHEMA_FOUND" -eq 0 ]; then
                echo "- ${page_name} (${SITE_URL}${page_url})" >> "${SCHEMA_AUDIT_FILE}"
            fi
        fi
    done
    echo "" >> "${SCHEMA_AUDIT_FILE}"
fi

cat >> "${SCHEMA_AUDIT_FILE}" <<EOF
RECOMMENDED SCHEMA BY PAGE TYPE
--------------------------------

Homepage (/)
  - Organization schema (company info, logo, social profiles)
  - WebSite schema (site search, site name)
  ✓ Check: Google Rich Results Test

Services Pages (/services/, etc.)
  - Service schema (service name, description, provider, area served)
  - BreadcrumbList schema (navigation breadcrumbs)
  ✓ Check: Google Rich Results Test

Contact Page (/contact/, /contact-us/)
  - LocalBusiness schema (address, phone, hours, geo coordinates)
  - Organization schema (if not on homepage)
  ✓ Check: Google Rich Results Test

Portfolio/Case Studies (/portfolio/, etc.)
  - Article schema (for case study posts)
  - BreadcrumbList schema
  ✓ Check: Google Rich Results Test

Shop/Packages (/shop/, etc.)
  - Product schema (for each package/product)
  - Offer schema (pricing, availability)
  ✓ Check: Google Merchant Center validation

Blog/Articles (/blog/, /insights/, /news/)
  - Article schema (headline, date, author, image)
  - BreadcrumbList schema
  - Person schema (for authors)
  ✓ Check: Google Rich Results Test

VALIDATION TOOLS
----------------
1. Google Rich Results Test: https://search.google.com/test/rich-results
2. Schema.org Validator: https://validator.schema.org/
3. Google Search Console: Rich Results report
4. Google Merchant Center: For product schema validation

NEXT STEPS
----------
[ ] Review pages without schema markup (listed above)
[ ] Implement missing Organization schema on homepage
[ ] Add LocalBusiness schema to contact page
[ ] Add Service schema to all service pages
[ ] Validate schema using Google Rich Results Test
[ ] Monitor Google Search Console for schema errors
[ ] Fix any schema validation errors found

========================================
EOF

echo "=========================================="
echo "Schema Audit Complete!"
echo "=========================================="
echo "Pages with schema: ${PAGES_WITH_SCHEMA}/${TOTAL_PAGES}"
echo "Pages without schema: ${PAGES_WITHOUT_SCHEMA}/${TOTAL_PAGES}"
echo ""
echo "Full report saved to: ${SCHEMA_AUDIT_FILE}"
echo ""
echo "View report: cat ${SCHEMA_AUDIT_FILE}"
