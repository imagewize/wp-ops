#!/usr/bin/env bash
#
# Orphan Pages Audit Script
# Purpose: Find WordPress pages that exist but are not linked from navigation menus
# Output: CSV reports with potential orphaned pages
#
# Usage: ./orphan-pages-audit.sh [OPTIONS]
#
# Options:
#   --path PATH       WordPress path for WP-CLI (default: web/wp for Bedrock)
#   --output DIR      Output directory (default: audits)
#   --site-url URL    Site URL for reports (default: derived from wp_options)
#   -h, --help        Show this help
#
# Requires: WP-CLI access to WordPress installation
#
# @desc     Find WordPress pages that exist but aren't linked from navigation menus
# @category seo
# @platform wordpress
# @runs     local
# @requires wp
# @flag     --path      optional  {web/wp}  WordPress path for WP-CLI
# @flag     --output    optional  {audits}  Output directory
# @flag     --site-url  optional  {https://example.com}  Site URL for reports
# @example  wp-ops orphan-pages-audit --path web/wp --output reports/seo
# @doc      wp-cli/seo/README.md

set -euo pipefail

# Configuration with defaults
WP_PATH="web/wp"
OUTPUT_DIR="audits"
SITE_URL=""
DATE=$(date +%Y-%m-%d)
ORPHANED_PAGES_FILE="${OUTPUT_DIR}/orphaned-pages-${DATE}.csv"
MENU_URLS_FILE="${OUTPUT_DIR}/menu-urls-${DATE}.txt"
REPORT_FILE="${OUTPUT_DIR}/orphan-pages-report-${DATE}.txt"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --path)
            WP_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            ORPHANED_PAGES_FILE="${OUTPUT_DIR}/orphaned-pages-${DATE}.csv"
            MENU_URLS_FILE="${OUTPUT_DIR}/menu-urls-${DATE}.txt"
            REPORT_FILE="${OUTPUT_DIR}/orphan-pages-report-${DATE}.txt"
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

# Get site name
SITE_NAME=$(wp option get blogname --path="$WP_PATH" 2>/dev/null || echo "WordPress Site")

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

echo "=========================================="
echo "Orphan Pages Audit - ${SITE_NAME}"
echo "URL: ${SITE_URL}"
echo "Date: ${DATE}"
echo "=========================================="
echo ""

# Export all published pages
echo "[1/4] Exporting all published pages..."
echo "ID,post_title,post_name,url,post_parent" > "${ORPHANED_PAGES_FILE}"
wp post list \
  --post_type=page \
  --post_status=publish \
  --fields=ID,post_title,post_name,url,post_parent \
  --format=csv --path="$WP_PATH" | tail -n +2 >> "${ORPHANED_PAGES_FILE}" 2>/dev/null

TOTAL_PAGES=$(wp post list --post_type=page --post_status=publish --format=count --path="$WP_PATH")
echo "✓ Found ${TOTAL_PAGES} published pages"
echo ""

# Export all menu URLs
echo "[2/4] Exporting navigation menu URLs..."

# Try to find and export from all menus
wp menu list --fields=term_id,name,slug --format=table --path="$WP_PATH" > "${OUTPUT_DIR}/menus-list-${DATE}.txt" 2>/dev/null

# Get URLs from all menus combined
wp menu item list --all --field=url --path="$WP_PATH" 2>/dev/null | sort | uniq > "${MENU_URLS_FILE}" || touch "${MENU_URLS_FILE}"

# Also try specific common menu names
for menu_name in "primary" "main" "top" "1-top-navigation" "primary-menu" "main-menu" "header" "navigation"; do
    if wp menu list --fields=name --format=csv --path="$WP_PATH" 2>/dev/null | grep -qi "^${menu_name}$"; then
        wp menu item list "${menu_name}" --field=url --path="$WP_PATH" 2>/dev/null | sort | uniq >> "${MENU_URLS_FILE}" || true
    fi
done

# Sort and deduplicate
sort "${MENU_URLS_FILE}" | uniq -i > "${MENU_URLS_FILE}.tmp" 2>/dev/null || true
mv "${MENU_URLS_FILE}.tmp" "${MENU_URLS_FILE}" 2>/dev/null || true

MENU_URL_COUNT=$(wc -l < "${MENU_URLS_FILE}" 2>/dev/null | tr -d ' ' || echo "0")
echo "✓ Found ${MENU_URL_COUNT} unique URLs in navigation menus"
echo ""

# Extract all page URLs from WordPress
echo "[3/4] Extracting all page URLs..."
wp post list \
  --post_type=page \
  --post_status=publish \
  --field=url \
  --path="$WP_PATH" 2>/dev/null | sort | uniq > "${OUTPUT_DIR}/all-page-urls-${DATE}.txt" || touch "${OUTPUT_DIR}/all-page-urls-${DATE}.txt"

ALL_URL_COUNT=$(wc -l < "${OUTPUT_DIR}/all-page-urls-${DATE}.txt" 2>/dev/null | tr -d ' ' || echo "0")
echo "✓ Found ${ALL_URL_COUNT} unique page URLs"
echo ""

# Find potential orphaned pages (pages not in any menu)
echo "[4/4] Identifying potential orphaned pages..."

# For each page URL, check if it's in menu URLs
# Note: This is a basic check - it compares the page URL with menu item URLs
# For a more comprehensive check, you'd need to resolve all menu item URLs and compare

# Create a report of pages not found in menus
echo "Pages NOT in Navigation Menus:" > "${REPORT_FILE}"
echo "========================================" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# Simple method: pages whose URLs don't appear in menu URLs file
POTENTIAL_ORPHANS=0
while IFS= read -r page_url; do
    [[ -z "$page_url" ]] && continue
    if ! grep -qi "${page_url}" "${MENU_URLS_FILE}" 2>/dev/null; then
        # Get page details
        PAGE_ID=$(wp post list --post_type=page --post_status=publish --field=ID --path="$WP_PATH" 2>/dev/null | head -1 || echo "")
        PAGE_TITLE=$(wp post get "${PAGE_ID:-1}" --field=post_title --path="$WP_PATH" 2>/dev/null || echo "Unknown")
        echo "  - ${PAGE_TITLE} (${page_url})" >> "${REPORT_FILE}"
        ((POTENTIAL_ORPHANS++)) || true
    fi
done < "${OUTPUT_DIR}/all-page-urls-${DATE}.txt"

echo "" >> "${REPORT_FILE}"
echo "Found ${POTENTIAL_ORPHANS} potential orphaned pages" >> "${REPORT_FILE}"

# Generate summary
cat >> "${REPORT_FILE}" <<EOF

========================================
ORPHAN PAGES AUDIT SUMMARY
========================================

Site: ${SITE_NAME}
URL: ${SITE_URL}
Date: ${DATE}

Statistics:
  Total Published Pages: ${TOTAL_PAGES}
  URLs in Navigation Menus: ${MENU_URL_COUNT}
  Unique Page URLs: ${ALL_URL_COUNT}
  Potential Orphaned Pages: ${POTENTIAL_ORPHANS}

IMPORTANT NOTES
--------------
This script provides a BASIC orphaned page detection only.

Limitations:
1. Only checks if page URL appears directly in menu item URLs
2. Does not account for:
   - Pages linked from page content (internal links)
   - Pages in footer or other secondary navigation
   - Pages linked from widgets or sidebars
   - Redirects that may resolve to menu URLs
   - Homepage (always accessible)

For COMPREHENSIVE orphaned page detection:

Recommended Tools:
1. Screaming Frog SEO Spider (https://www.screamingfrog.com)
   - Crawl the entire site
   - Navigate to: Internal > Orphan Pages
   - Export the list

2. Ahrefs Site Audit (https://ahrefs.com/site-audit)
   - Run a site audit
   - Navigate to: Internal pages > Orphan pages
   - Export CSV

3. Sitebulb (https://sitebulb.com)
   - Run a site crawl
   - Check the orphan pages report

4. DeepCrawl (https://www.deepcrawl.com)
   - Enterprise-level crawling
   - Comprehensive orphan page detection

Manual Verification Method:
1. Export all page URLs from WordPress
2. Run a full site crawl with Screaming Frog
3. Export all crawled URLs from Screaming Frog
4. Compare the two lists to find pages not crawled
5. Pages that exist in WordPress but weren't crawled are likely orphaned

RECOMMENDATIONS
--------------
EOF

if [[ "$POTENTIAL_ORPHANS" -gt 0 ]]; then
    cat >> "${REPORT_FILE}" <<EOF
1. Review the ${POTENTIAL_ORPHANS} potential orphaned pages listed above
2. For each page, decide if it should be:
   - Added to navigation menus
   - Linked from other relevant pages
   - Deleted if no longer needed
3. Add internal links from related content to important orphaned pages
4. Consider creating a sitemap page that links to all pages
5. Use breadcrumb navigation to improve internal linking

HIGH PRIORITY PAGES TO FIX:
- Important business pages (services, about, contact)
- High-traffic pages (check Google Analytics)
- Conversion pages (contact forms, product pages)

MEDIUM PRIORITY:
- Blog posts and articles
- Category and tag archive pages
- Author pages

LOW PRIORITY:
- Old or outdated pages
- Test pages
- Staging content
EOF
else
    cat >> "${REPORT_FILE}" <<EOF
No orphaned pages detected with this basic check.

However, this does NOT guarantee there are no orphaned pages.
Use Screaming Frog or Ahrefs for comprehensive detection.
EOF
fi

cat >> "${REPORT_FILE}" <<EOF

NEXT STEPS
----------
[ ] Review the potential orphaned pages list above
[ ] Run Screaming Frog crawl for comprehensive detection
[ ] Add internal links to important orphaned pages
[ ] Update navigation menus to include missing pages
[ ] Consider creating a HTML sitemap
[ ] Set up regular audits (quarterly recommended)

OUTPUT FILES
------------
- ${ORPHANED_PAGES_FILE} - All published pages with URLs
- ${MENU_URLS_FILE} - All URLs found in navigation menus
- ${OUTPUT_DIR}/all-page-urls-${DATE}.txt - All page URLs from WordPress
- ${OUTPUT_DIR}/menus-list-${DATE}.txt - List of all menus
- ${REPORT_FILE} - This report

========================================
EOF

echo "✓ Orphan pages audit complete!"
echo ""
echo "Reports saved to:"
echo "  - ${ORPHANED_PAGES_FILE}"
echo "  - ${MENU_URLS_FILE}"
echo "  - ${REPORT_FILE}"
echo ""
echo "View full report: cat ${REPORT_FILE}"
echo ""
echo "⚠ IMPORTANT: This is a BASIC check only."
echo "For comprehensive orphaned page detection, use Screaming Frog or Ahrefs."
