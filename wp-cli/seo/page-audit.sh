#!/usr/bin/env bash
#
# Page Structure & Orphaned Pages Audit Script
# Purpose: Identify orphaned pages, analyze internal linking, and export page inventory
# Output: CSV reports with orphaned pages and navigation analysis
#
# Usage: ./page-audit.sh [OPTIONS]
#
# Options:
#   --path PATH       WordPress path for WP-CLI (default: web/wp for Bedrock)
#   --output DIR      Output directory (default: audits)
#   --site-url URL    Site URL for reports (default: derived from wp_options)
#   -h, --help        Show this help
#
# Requires: WP-CLI access to WordPress installation
#
# @desc     Identify orphaned pages, analyze internal linking, and export a page inventory
# @category seo
# @platform wordpress
# @runs     local
# @mutates  false
# @requires wp
# @flag     --path      optional  {web/wp}  WordPress path for WP-CLI
# @flag     --output    optional  {audits}  Output directory
# @flag     --site-url  optional  {https://example.com}  Site URL for reports
# @example  wp-ops page-audit --path web/wp --output reports/seo
# @doc      wp-cli/seo/README.md

set -euo pipefail

# Configuration with defaults
WP_PATH="web/wp"
OUTPUT_DIR="audits"
SITE_URL=""
DATE=$(date +%Y-%m-%d)
PAGE_AUDIT_FILE="${OUTPUT_DIR}/page-audit-${DATE}.csv"
ORPHANED_PAGES_FILE="${OUTPUT_DIR}/orphaned-pages-${DATE}.csv"
NAVIGATION_FILE="${OUTPUT_DIR}/navigation-structure-${DATE}.txt"
REPORT_FILE="${OUTPUT_DIR}/page-audit-report-${DATE}.txt"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --path)
            WP_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            PAGE_AUDIT_FILE="${OUTPUT_DIR}/page-audit-${DATE}.csv"
            ORPHANED_PAGES_FILE="${OUTPUT_DIR}/orphaned-pages-${DATE}.csv"
            NAVIGATION_FILE="${OUTPUT_DIR}/navigation-structure-${DATE}.txt"
            REPORT_FILE="${OUTPUT_DIR}/page-audit-report-${DATE}.txt"
            shift 2
            ;;
        --site-url)
            SITE_URL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --path PATH       WordPress path for WP-CLI (default: web/wp)"
            echo "  --output DIR      Output directory (default: audits)"
            echo "  --site-url URL    Site URL for reports"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0")"
            echo "  $(basename "$0") --path web/wp --output reports/seo"
            echo "  $(basename "$0") --path /var/www/html --site-url https://example.com"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get site URL from database if not provided
if [[ -z "$SITE_URL" ]]; then
    SITE_URL=$(wp option get siteurl --path="$WP_PATH" 2>/dev/null || echo "unknown")
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo "=========================================="
echo "Page Structure Audit - ${SITE_URL}"
echo "Date: ${DATE}"
echo "=========================================="
echo ""

# 1. Export all published pages
echo "[1/8] Exporting all published pages..."
wp post list \
  --post_type=page \
  --post_status=publish \
  --fields=ID,post_title,post_name,post_date,post_modified,post_parent \
  --format=csv > "${PAGE_AUDIT_FILE}"

TOTAL_PAGES=$(wp post list --post_type=page --post_status=publish --format=count --path="$WP_PATH")
echo "✓ Found ${TOTAL_PAGES} published pages"
echo ""

# 2. Analyze navigation structure
echo "[2/8] Analyzing navigation menus..."
wp menu list --fields=term_id,name,slug,count --format=table > "${NAVIGATION_FILE}"

echo "" >> "${NAVIGATION_FILE}"
echo "=== TOP NAVIGATION MENU ===" >> "${NAVIGATION_FILE}"
echo "" >> "${NAVIGATION_FILE}"

# Find the primary menu - try common names
PRIMARY_MENU=""
for menu_name in "primary" "main" "top" "1-top-navigation" "primary-menu" "main-menu"; do
    if wp menu list --fields=name --format=csv 2>/dev/null | grep -qi "^${menu_name}$"; then
        PRIMARY_MENU="${menu_name}"
        break
    fi
done

# If we found a primary menu, export its items
if [[ -n "$PRIMARY_MENU" ]]; then
    echo "Exporting menu: ${PRIMARY_MENU}" >> "${NAVIGATION_FILE}"
    wp menu item list "${PRIMARY_MENU}" \
      --fields=db_id,title,url,menu_order,menu_item_parent \
      --format=table >> "${NAVIGATION_FILE}" 2>/dev/null || echo "Menu export failed" >> "${NAVIGATION_FILE}"
else
    echo "Primary navigation menu not found. Tried: primary, main, top, 1-top-navigation, primary-menu, main-menu" >> "${NAVIGATION_FILE}"
    echo "Available menus:" >> "${NAVIGATION_FILE}"
    wp menu list --fields=name --format=csv >> "${NAVIGATION_FILE}" 2>/dev/null || true
fi

echo "✓ Navigation structure exported"
echo ""

# 3. Check for key business pages
echo "[3/8] Checking key business pages..."

# Check if critical pages exist
declare -A KEY_PAGES=(
  ["home"]="/"
  ["about"]="/about/ or /about-us/"
  ["contact"]="/contact/ or /contact-us/"
  ["services"]="/services/"
  ["portfolio"]="/portfolio/"
  ["blog"]="/blog/ or /insights/ or /news/"
  ["shop"]="/shop/"
)

echo "" > "${OUTPUT_DIR}/missing-pages-${DATE}.txt"
for page_slug in "${!KEY_PAGES[@]}"; do
  PAGE_EXISTS=$(wp post list --name="${page_slug}" --post_type=page --format=count --path="$WP_PATH" 2>/dev/null || echo "0")
  if [ "$PAGE_EXISTS" -eq 0 ]; then
    echo "⚠ Missing: ${page_slug} (${KEY_PAGES[$page_slug]})"
    echo "${page_slug} - ${KEY_PAGES[$page_slug]}" >> "${OUTPUT_DIR}/missing-pages-${DATE}.txt"
  else
    echo "✓ Found: ${page_slug}"
  fi
done
echo ""

# 4. Analyze service pages
echo "[4/8] Analyzing service pages..."
SERVICES_PAGE_ID=$(wp post list --name="services" --post_type=page --field=ID --path="$WP_PATH" 2>/dev/null || echo "0")
if [[ "$SERVICES_PAGE_ID" != "0" && -n "$SERVICES_PAGE_ID" ]]; then
    wp post list \
      --post_type=page \
      --post_parent="$SERVICES_PAGE_ID" \
      --fields=ID,post_title,post_name \
      --format=table 2>/dev/null || echo "No service subpages found"
else
    echo "No 'services' parent page found"
fi
echo ""

# 5. Analyze page hierarchy
echo "[5/8] Analyzing page hierarchy..."
wp db query "
  SELECT
    p.post_title,
    p.post_name,
    p.post_parent,
    parent.post_title as parent_page
  FROM wp_posts p
  LEFT JOIN wp_posts parent ON p.post_parent = parent.ID
  WHERE p.post_type='page'
    AND p.post_status='publish'
  ORDER BY p.post_parent, p.post_title
" --skip-column-names --path="$WP_PATH" > "${OUTPUT_DIR}/page-hierarchy-${DATE}.txt" 2>/dev/null || echo "Hierarchy query failed" > "${OUTPUT_DIR}/page-hierarchy-${DATE}.txt"

echo "✓ Page hierarchy exported to page-hierarchy-${DATE}.txt"
echo ""

# 6. Check for orphaned pages (pages not in navigation)
echo "[6/8] Identifying potential orphaned pages..."

# Get all menu item URLs from primary menu
if [[ -n "$PRIMARY_MENU" ]]; then
    wp menu item list "${PRIMARY_MENU}" --field=url 2>/dev/null | sort | uniq > "${OUTPUT_DIR}/menu-urls-${DATE}.txt" || touch "${OUTPUT_DIR}/menu-urls-${DATE}.txt"
else
    # Try to get URLs from all menus
    wp menu item list --all --field=url 2>/dev/null | sort | uniq > "${OUTPUT_DIR}/menu-urls-${DATE}.txt" || touch "${OUTPUT_DIR}/menu-urls-${DATE}.txt"
fi

# This is a simplified check - for full orphaned page detection, use Screaming Frog or Ahrefs
echo "post_title,post_name,url,post_parent" > "${ORPHANED_PAGES_FILE}"
wp post list \
  --post_type=page \
  --post_status=publish \
  --fields=post_title,post_name,url,post_parent \
  --format=csv --path="$WP_PATH" | tail -n +2 >> "${ORPHANED_PAGES_FILE}" 2>/dev/null || echo "Orphaned pages export failed"

PAGES_IN_MENU=$(wc -l < "${OUTPUT_DIR}/menu-urls-${DATE}.txt" 2>/dev/null | tr -d ' ' || echo "0")
echo "✓ Pages in navigation menus: ${PAGES_IN_MENU}"
echo "⚠ Full orphaned page detection requires Screaming Frog or Ahrefs crawl"
echo ""

# 7. Check for redirect opportunities (duplicate or similar page names)
echo "[7/8] Checking for duplicate or similar page names..."
wp db query "
  SELECT post_title, COUNT(*) as duplicate_count
  FROM wp_posts
  WHERE post_type='page'
    AND post_status='publish'
  GROUP BY post_title
  HAVING duplicate_count > 1
" --skip-column-names --path="$WP_PATH" > "${OUTPUT_DIR}/duplicate-page-titles-${DATE}.txt" 2>/dev/null || echo "" > "${OUTPUT_DIR}/duplicate-page-titles-${DATE}.txt"

DUPLICATE_COUNT=$(wc -l < "${OUTPUT_DIR}/duplicate-page-titles-${DATE}.txt" 2>/dev/null | tr -d ' ' || echo "0")
echo "   - Duplicate page titles found: ${DUPLICATE_COUNT}"
echo ""

# 8. Generate comprehensive report
echo "[8/8] Generating page audit report..."

MISSING_PAGES_COUNT=$(wc -l < "${OUTPUT_DIR}/missing-pages-${DATE}.txt" 2>/dev/null | tr -d ' ' || echo "0")

SITE_NAME=$(wp option get blogname --path="$WP_PATH" 2>/dev/null || echo "WordPress Site")

cat > "${REPORT_FILE}" <<EOF
========================================
PAGE STRUCTURE AUDIT REPORT
${SITE_NAME}
URL: ${SITE_URL}
Date: ${DATE}
========================================

PAGE INVENTORY
--------------
Total Published Pages: ${TOTAL_PAGES}
Pages in Navigation Menus: ${PAGES_IN_MENU}
Missing Key Business Pages: ${MISSING_PAGES_COUNT}
Duplicate Page Titles: ${DUPLICATE_COUNT}

KEY BUSINESS PAGES STATUS
-------------------------
EOF

# Add key pages status to report
for page_slug in "${!KEY_PAGES[@]}"; do
  PAGE_EXISTS=$(wp post list --name="${page_slug}" --post_type=page --format=count --path="$WP_PATH" 2>/dev/null || echo "0")
  if [ "$PAGE_EXISTS" -eq 0 ]; then
    echo "[ ] ${page_slug} - MISSING (${KEY_PAGES[$page_slug]})" >> "${REPORT_FILE}"
  else
    PAGE_URL=$(wp post list --name="${page_slug}" --post_type=page --field=url --path="$WP_PATH" 2>/dev/null || echo "")
    echo "[✓] ${page_slug} - ${PAGE_URL}" >> "${REPORT_FILE}"
  fi
done

cat >> "${REPORT_FILE}" <<EOF

ORPHANED PAGES DETECTION
-------------------------
⚠ This script provides basic analysis only.

For comprehensive orphaned page detection, run:
1. Screaming Frog crawl of ${SITE_URL}
2. Filter for pages with 0 internal links
3. Export to CSV and compare with ${ORPHANED_PAGES_FILE}

Alternatively:
1. Ahrefs Site Audit
2. Navigate to "Internal pages" > "Orphan pages"
3. Export CSV for comparison

DUPLICATE PAGE TITLES
---------------------
EOF

if [[ "$DUPLICATE_COUNT" -gt 0 ]]; then
    cat "${OUTPUT_DIR}/duplicate-page-titles-${DATE}.txt" >> "${REPORT_FILE}"
else
    echo "None found" >> "${REPORT_FILE}"
fi

cat >> "${REPORT_FILE}" <<EOF

RECOMMENDATIONS
---------------
1. Create missing key business pages (see missing-pages list)
2. Review navigation structure in ${NAVIGATION_FILE}
3. Run Screaming Frog crawl to identify true orphaned pages
4. Fix duplicate page titles (${DUPLICATE_COUNT} found)
5. Add internal links to important pages not in navigation
6. Consider creating a sitemap page or XML sitemap

NEXT STEPS
----------
[ ] Review ${PAGE_AUDIT_FILE} for complete page inventory
[ ] Check ${OUTPUT_DIR}/missing-pages-${DATE}.txt for pages to create
[ ] Review ${NAVIGATION_FILE} for navigation improvements
[ ] Run Screaming Frog crawl for full orphaned pages analysis
[ ] Update internal linking strategy based on findings
[ ] Fix ${DUPLICATE_COUNT} duplicate page titles

OUTPUT FILES
------------
- ${PAGE_AUDIT_FILE}
- ${ORPHANED_PAGES_FILE}
- ${NAVIGATION_FILE}
- ${OUTPUT_DIR}/page-hierarchy-${DATE}.txt
- ${OUTPUT_DIR}/missing-pages-${DATE}.txt
- ${OUTPUT_DIR}/duplicate-page-titles-${DATE}.txt
- ${REPORT_FILE}

========================================
EOF

echo "✓ Page audit complete!"
echo ""
echo "Reports saved to:"
echo "  - ${PAGE_AUDIT_FILE}"
echo "  - ${ORPHANED_PAGES_FILE}"
echo "  - ${REPORT_FILE}"
echo ""
echo "View full report: cat ${REPORT_FILE}"
