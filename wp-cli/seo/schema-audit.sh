#!/usr/bin/env bash
#
# Schema Markup Audit Script
# Purpose: Check for schema markup on a site's pages and validate implementation
# Output: Text reports with schema detection results
#
# Usage: ./schema-audit.sh [OPTIONS] <site-url>
#
# Pages come from --pages if passed. Otherwise they come from the site's
# sitemap (wp-sitemap.xml, sitemap_index.xml, then sitemap.xml; only the page
# sitemaps when there is an index), capped at --max-pages. A site with no
# sitemap falls back to a list of common paths. URLs that don't return 200
# are listed separately and never counted as missing schema.
#
# Options:
#   --output DIR      Output directory (default: audits)
#   --pages P1,P2     Comma-separated page paths or full URLs to check (default: sitemap pages)
#   --max-pages N     Maximum number of sitemap pages to check (default: 25)
#   -h, --help        Show this help
#
# Requires: curl, perl
#
# @desc     Check a site's pages (from its sitemap) for JSON-LD schema markup
# @category seo
# @platform wordpress
# @runs     local
# @mutates  false
# @requires curl perl
# @arg      site-url  required  {https://example.com}  Site URL to check
# @flag     --output     optional  {audits}  Output directory
# @flag     --pages      optional  {/,/about/,/contact/}  Comma-separated page paths or URLs (default: sitemap pages)
# @flag     --max-pages  optional  {25}  Maximum number of sitemap pages to check
# @example  wp-ops schema-audit https://example.com --pages /,/services/,/contact/
# @doc      wp-cli/seo/README.md

set -euo pipefail

# Configuration
OUTPUT_DIR="audits"
MAX_PAGES=25
DATE=$(date +%Y-%m-%d)
SCHEMA_TYPES=("Organization" "LocalBusiness" "Service" "Product" "WebSite" "BreadcrumbList" "Article" "FAQPage" "HowTo" "Person")

# Checked in order: WordPress core, then the index Yoast / Rank Math / The SEO
# Framework serve, then the plain path most other generators use
SITEMAP_PATHS=("wp-sitemap.xml" "sitemap_index.xml" "sitemap.xml")

# Fallback when the site has no usable sitemap: common paths, several of which
# won't exist on any given site (name|path pairs)
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
            shift 2
            ;;
        --pages)
            CUSTOM_PAGES="$2"
            shift 2
            ;;
        --max-pages)
            MAX_PAGES="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS] <site-url>"
            echo ""
            echo "Options:"
            echo "  --output DIR      Output directory (default: audits)"
            echo "  --pages P1,P2     Comma-separated page paths or full URLs (default: sitemap pages)"
            echo "  --max-pages N     Maximum number of sitemap pages to check (default: 25)"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") https://example.com"
            echo "  $(basename "$0") https://example.com --output reports/seo"
            echo "  $(basename "$0") https://example.com --max-pages 50"
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

if [[ ! "$MAX_PAGES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --max-pages must be a positive whole number."
    exit 1
fi

# Normalize to scheme + host with no trailing slash, so "${ORIGIN}/path/"
# never produces the "//path/" a site answers with a 301
if [[ "$SITE_URL" != http://* && "$SITE_URL" != https://* ]]; then
    SITE_URL="https://${SITE_URL}"
fi
ORIGIN=$(echo "$SITE_URL" | sed -E 's|^(https?://[^/]+).*|\1|')
DOMAIN=$(echo "$ORIGIN" | sed -E 's|^https?://||')
SCHEMA_AUDIT_FILE="${OUTPUT_DIR}/schema-audit-${DATE}.txt"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Print the <loc> values of a sitemap or sitemap index, one per line
parse_locs() {
  perl -0777 -ne 'while (/<loc>\s*(?:<!\[CDATA\[)?\s*(.*?)\s*(?:\]\]>)?\s*<\/loc>/gis) { (my $u = $1) =~ s/&amp;/&/g; print "$u\n" }' "$1"
}

# "Homepage" for the root, the path for anything else
page_label() {
  local path="/${1#*://*/}"
  if [[ "$path" == "/" ]]; then echo "Homepage"; else echo "$path"; fi
}

# Fill PAGES_TO_CHECK from the first sitemap that lists URLs on this site.
# Sets SITEMAP_URL and SITEMAP_TOTAL; returns 1 when no sitemap qualifies.
discover_sitemap_pages() {
  local path url child page
  local urls_file="${WORK_DIR}/urls.txt"
  for path in "${SITEMAP_PATHS[@]}"; do
    url="${ORIGIN}/${path}"
    curl -s -f -L --max-time 30 "$url" -o "${WORK_DIR}/sitemap.xml" 2>/dev/null || continue

    : > "$urls_file"
    if grep -qi '<sitemapindex' "${WORK_DIR}/sitemap.xml"; then
      parse_locs "${WORK_DIR}/sitemap.xml" > "${WORK_DIR}/children.txt"
      # Page sitemaps only (wp-sitemap-posts-page-1.xml, page-sitemap.xml),
      # when the index has any
      if grep -qiE '/[^/]*page[^/]*$' "${WORK_DIR}/children.txt"; then
        grep -iE '/[^/]*page[^/]*$' "${WORK_DIR}/children.txt" > "${WORK_DIR}/children-pages.txt"
        mv "${WORK_DIR}/children-pages.txt" "${WORK_DIR}/children.txt"
      fi
      while IFS= read -r child; do
        if curl -s -f -L --max-time 30 "$child" -o "${WORK_DIR}/child.xml" 2>/dev/null; then
          parse_locs "${WORK_DIR}/child.xml" >> "$urls_file"
        fi
      done < "${WORK_DIR}/children.txt"
    elif grep -qi '<urlset' "${WORK_DIR}/sitemap.xml"; then
      parse_locs "${WORK_DIR}/sitemap.xml" > "$urls_file"
    fi

    # Same host only, homepage first, duplicates dropped, order kept
    { echo "${ORIGIN}/"; grep -E "^https?://${DOMAIN//./\\.}(/|$)" "$urls_file" || true; } \
      | awk '!seen[$0]++' > "${WORK_DIR}/pages.txt"
    SITEMAP_TOTAL=$(wc -l < "${WORK_DIR}/pages.txt" | tr -d ' ')
    # Only the homepage we added ourselves means the sitemap listed nothing here
    if [[ "$SITEMAP_TOTAL" -le 1 ]]; then
      continue
    fi

    SITEMAP_URL="$url"
    PAGES_TO_CHECK=()
    while IFS= read -r page; do
      PAGES_TO_CHECK+=("$(page_label "$page")|${page}")
    done < <(head -n "$MAX_PAGES" "${WORK_DIR}/pages.txt")
    return 0
  done
  return 1
}

# Pick the page list: --pages, else the sitemap, else the common paths
PAGE_SOURCE=""
SITEMAP_URL=""
SITEMAP_TOTAL=0
PAGES_TO_CHECK=()
if [[ -n "$CUSTOM_PAGES" ]]; then
    PAGE_SOURCE="custom"
    IFS=',' read -ra custom <<< "$CUSTOM_PAGES"
    for page in "${custom[@]}"; do
        if [[ "$page" == http://* || "$page" == https://* ]]; then
            page_url="$page"
        else
            page_url="${ORIGIN}/${page#/}"
        fi
        PAGES_TO_CHECK+=("$(page_label "$page_url")|${page_url}")
    done
elif discover_sitemap_pages; then
    PAGE_SOURCE="sitemap"
else
    PAGE_SOURCE="default"
    for entry in "${DEFAULT_PAGES[@]}"; do
        PAGES_TO_CHECK+=("${entry%%|*}|${ORIGIN}${entry##*|}")
    done
fi

case "$PAGE_SOURCE" in
    sitemap)
        if [[ ${#PAGES_TO_CHECK[@]} -lt $SITEMAP_TOTAL ]]; then
            SOURCE_LINE="first ${#PAGES_TO_CHECK[@]} of ${SITEMAP_TOTAL} URLs from ${SITEMAP_URL} (raise --max-pages or pass --pages to check others)"
        else
            SOURCE_LINE="${#PAGES_TO_CHECK[@]} URLs from ${SITEMAP_URL}"
        fi
        ;;
    default) SOURCE_LINE="${#PAGES_TO_CHECK[@]} common paths (no sitemap found), so some are expected not to exist" ;;
    custom)  SOURCE_LINE="${#PAGES_TO_CHECK[@]} passed in --pages" ;;
esac

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "Schema Markup Audit - ${DOMAIN}"
echo "Date: ${DATE}"
echo "Pages: ${SOURCE_LINE}"
echo "=========================================="
echo ""

# Start report
cat > "${SCHEMA_AUDIT_FILE}" <<EOF
========================================
SCHEMA MARKUP AUDIT
Site: ${ORIGIN}/
Date: ${DATE}
Pages: ${SOURCE_LINE}
========================================

EOF

PAGES_WITH_SCHEMA=0
PAGES_WITHOUT_SCHEMA=0
MISSING_SCHEMA=()
NOT_CHECKED=()

for page_entry in "${PAGES_TO_CHECK[@]}"; do
  page_name="${page_entry%%|*}"
  full_url="${page_entry#*|}"
  body="${WORK_DIR}/page.html"

  # One request per page: body to a file, status and redirect target on stdout.
  # Redirects are not followed, so a URL that redirects is reported, not audited.
  result=$(curl -s --max-time 30 -o "$body" -w '%{http_code} %{redirect_url}' "$full_url" 2>/dev/null) || true
  http_status="${result%% *}"
  redirect_url="${result#* }"
  [[ "$result" != *" "* ]] && redirect_url=""
  [[ -z "$http_status" || "$http_status" == "000" ]] && http_status=0

  if [[ "$http_status" != "200" ]]; then
    status_text="HTTP ${http_status}"
    [[ "$http_status" == "0" ]] && status_text="no response"
    [[ -n "$redirect_url" ]] && status_text="${status_text} → ${redirect_url}"
    echo "⚠ Not checked: ${page_name} (${status_text})"
    NOT_CHECKED+=("${page_name} (${full_url}): ${status_text}")
    continue
  fi

  echo "" >> "${SCHEMA_AUDIT_FILE}"
  echo "=== ${page_name} ===" >> "${SCHEMA_AUDIT_FILE}"
  echo "URL: ${full_url}" >> "${SCHEMA_AUDIT_FILE}"
  echo "" >> "${SCHEMA_AUDIT_FILE}"

  # JSON-LD blocks, which may span lines and carry extra attributes
  # (Yoast adds class="yoast-schema-graph")
  SCHEMA_CONTENT=$(perl -0777 -ne 'while (/<script[^>]*type=["\x27]application\/ld\+json["\x27][^>]*>(.*?)<\/script>/gis) { print "$1\n" }' "$body")

  if [[ -z "$SCHEMA_CONTENT" ]]; then
    PAGES_WITHOUT_SCHEMA=$((PAGES_WITHOUT_SCHEMA + 1))
    MISSING_SCHEMA+=("${page_name} (${full_url})")
    echo "❌ ${page_name}: No schema"
    echo "Status: ❌ NO SCHEMA FOUND" >> "${SCHEMA_AUDIT_FILE}"
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    echo "---" >> "${SCHEMA_AUDIT_FILE}"
  else
    PAGES_WITH_SCHEMA=$((PAGES_WITH_SCHEMA + 1))
    echo "✓ ${page_name}: Schema markup found"
    echo "Status: ✓ SCHEMA PRESENT" >> "${SCHEMA_AUDIT_FILE}"
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    for schema_type in "${SCHEMA_TYPES[@]}"; do
      # "@type": "X" or "@type": ["Y", "X"]
      if echo "$SCHEMA_CONTENT" | grep -qE "\"@type\"[[:space:]]*:[[:space:]]*(\[[^]]*)?\"${schema_type}\""; then
        echo "   ✓ ${schema_type} schema detected"
        echo "   - ${schema_type} schema: ✓" >> "${SCHEMA_AUDIT_FILE}"
      fi
    done
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    echo "Raw Schema:" >> "${SCHEMA_AUDIT_FILE}"
    echo "$SCHEMA_CONTENT" >> "${SCHEMA_AUDIT_FILE}"
    echo "" >> "${SCHEMA_AUDIT_FILE}"
    echo "---" >> "${SCHEMA_AUDIT_FILE}"
  fi

  sleep 1  # Be nice to the server
done

REACHABLE=$((PAGES_WITH_SCHEMA + PAGES_WITHOUT_SCHEMA))

# Generate summary
cat >> "${SCHEMA_AUDIT_FILE}" <<EOF

========================================
SCHEMA AUDIT SUMMARY
========================================

Pages Checked: ${REACHABLE} (of ${#PAGES_TO_CHECK[@]} URLs; the rest did not return 200)
Pages with Schema: ${PAGES_WITH_SCHEMA}
Pages without Schema: ${PAGES_WITHOUT_SCHEMA}

EOF

if [[ $PAGES_WITHOUT_SCHEMA -gt 0 ]]; then
    echo "PAGES NEEDING SCHEMA MARKUP:" >> "${SCHEMA_AUDIT_FILE}"
    for page in "${MISSING_SCHEMA[@]}"; do
        echo "- ${page}" >> "${SCHEMA_AUDIT_FILE}"
    done
    echo "" >> "${SCHEMA_AUDIT_FILE}"
fi

# Not-found URLs are not schema problems, so they get their own section. From
# a sitemap they are still worth fixing: the sitemap lists a URL that
# redirects or is gone.
if [[ ${#NOT_CHECKED[@]} -gt 0 ]]; then
    case "$PAGE_SOURCE" in
        sitemap) heading="NOT CHECKED: sitemap URLs that did not return 200 (the sitemap lists a redirect or a missing page):" ;;
        default) heading="NOT CHECKED: common paths that don't exist on this site (not a schema problem):" ;;
        *)       heading="NOT CHECKED: URLs that did not return 200:" ;;
    esac
    echo "$heading" >> "${SCHEMA_AUDIT_FILE}"
    for page in "${NOT_CHECKED[@]}"; do
        echo "- ${page}" >> "${SCHEMA_AUDIT_FILE}"
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

echo ""
echo "=========================================="
echo "Schema Audit Complete!"
echo "=========================================="
echo "Pages with schema: ${PAGES_WITH_SCHEMA}/${REACHABLE} reachable"
echo "Pages without schema: ${PAGES_WITHOUT_SCHEMA}/${REACHABLE} reachable"
if [[ ${#NOT_CHECKED[@]} -gt 0 ]]; then
    echo "Not checked (did not return 200): ${#NOT_CHECKED[@]}"
fi
echo ""
echo "Full report saved to: ${SCHEMA_AUDIT_FILE}"
echo ""
echo "View report: cat ${SCHEMA_AUDIT_FILE}"
