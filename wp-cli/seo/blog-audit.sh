#!/usr/bin/env bash
#
# Blog Content Audit Script
# Purpose: Analyze blog posts for content categorization and quality metrics
# Output: CSV reports with content analysis and recommendations
#
# Usage: ./blog-audit.sh [OPTIONS]
#
# Options:
#   --path PATH       WordPress path for WP-CLI (default: web/wp for Bedrock)
#   --output DIR      Output directory (default: audits)
#   --site-url URL    Site URL for reports (default: derived from wp_options)
#   -h, --help        Show this help
#
# Requires: WP-CLI access to WordPress installation
#

set -euo pipefail

# Configuration with defaults
WP_PATH="web/wp"
OUTPUT_DIR="audits"
SITE_URL=""
DATE=$(date +%Y-%m-%d)
BLOG_AUDIT_FILE="${OUTPUT_DIR}/blog-audit-${DATE}.csv"
CATEGORY_AUDIT_FILE="${OUTPUT_DIR}/category-audit-${DATE}.csv"
REPORT_FILE="${OUTPUT_DIR}/blog-audit-report-${DATE}.txt"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --path)
            WP_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            BLOG_AUDIT_FILE="${OUTPUT_DIR}/blog-audit-${DATE}.csv"
            CATEGORY_AUDIT_FILE="${OUTPUT_DIR}/category-audit-${DATE}.csv"
            REPORT_FILE="${OUTPUT_DIR}/blog-audit-report-${DATE}.txt"
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
echo "Blog Content Audit - ${SITE_NAME}"
echo "URL: ${SITE_URL}"
echo "Date: ${DATE}"
echo "=========================================="
echo ""

# 1. Export all published blog posts
echo "[1/7] Exporting all published blog posts..."
wp post list \
  --post_type=post \
  --post_status=publish \
  --fields=ID,post_title,post_name,post_date,post_modified,comment_count,post_excerpt \
  --format=csv --path="$WP_PATH" > "${BLOG_AUDIT_FILE}"

TOTAL_POSTS=$(wp post list --post_type=post --post_status=publish --format=count --path="$WP_PATH")
echo "✓ Found ${TOTAL_POSTS} published posts"
echo ""

# 2. Export category analysis
echo "[2/7] Analyzing post categories..."
wp term list category \
  --fields=term_id,name,slug,count,description \
  --format=csv --path="$WP_PATH" > "${CATEGORY_AUDIT_FILE}"

TOTAL_CATEGORIES=$(wp term list category --format=count --path="$WP_PATH")
echo "✓ Found ${TOTAL_CATEGORIES} categories"
echo ""

# 3. Identify content by keywords
echo "[3/7] Analyzing content by keywords..."

# SME-focused content
SME_POSTS=$(wp post list --post_type=post --s="SME" --format=count --path="$WP_PATH" 2>/dev/null || echo "0")
BUSINESS_POSTS=$(wp post list --post_type=post --s="small business" --format=count --path="$WP_PATH" 2>/dev/null || echo "0")
CASE_STUDY_POSTS=$(wp post list --post_type=post --s="case study" --format=count --path="$WP_PATH" 2>/dev/null || echo "0")

# Technical content
TECHNICAL_POSTS=$(wp post list --post_type=post --s="WordPress" --format=count --path="$WP_PATH" 2>/dev/null || echo "0")
TUTORIAL_POSTS=$(wp post list --post_type=post --s="tutorial" --format=count --path="$WP_PATH" 2>/dev/null || echo "0")
GUIDE_POSTS=$(wp post list --post_type=post --s="guide" --format=count --path="$WP_PATH" 2>/dev/null || echo "0")

echo "   SME-focused content:"
echo "     - Posts mentioning 'SME': ${SME_POSTS}"
echo "     - Posts mentioning 'small business': ${BUSINESS_POSTS}"
echo "     - Posts mentioning 'case study': ${CASE_STUDY_POSTS}"
echo ""
echo "   Technical content:"
echo "     - Posts mentioning 'WordPress': ${TECHNICAL_POSTS}"
echo "     - Posts mentioning 'tutorial': ${TUTORIAL_POSTS}"
echo "     - Posts mentioning 'guide': ${GUIDE_POSTS}"
echo ""

# 4. Check for posts without featured images
echo "[4/7] Checking for posts without featured images..."
POSTS_NO_FEATURED=$(wp post list \
  --post_type=post \
  --meta_key=_thumbnail_id \
  --meta_compare=NOT EXISTS \
  --format=count --path="$WP_PATH" 2>/dev/null || echo "0")

echo "   - Posts without featured images: ${POSTS_NO_FEATURED}"
echo ""

# 5. Analyze content length
echo "[5/7] Analyzing content length..."

# Get word counts for all posts
wp db query "
  SELECT
    ID,
    post_title,
    CHAR_LENGTH(post_content) as content_length,
    ROUND(CHAR_LENGTH(post_content) / 6) as word_count
  FROM wp_posts
  WHERE post_type='post'
    AND post_status='publish'
  ORDER BY word_count ASC
" --skip-column-names --path="$WP_PATH" > "${OUTPUT_DIR}/content-length-${DATE}.txt" 2>/dev/null || echo "Content length query failed"

# Count posts with thin content (< 800 words = < 4800 characters)
THIN_CONTENT_COUNT=$(wp db query "
  SELECT COUNT(*)
  FROM wp_posts
  WHERE post_type='post'
    AND post_status='publish'
    AND CHAR_LENGTH(post_content) < 4800
" --skip-column-names --path="$WP_PATH" 2>/dev/null || echo "0")

echo "   - Posts with < 800 words: ${THIN_CONTENT_COUNT}"
echo ""

# 6. Check for posts without categories
echo "[6/7] Checking for uncategorized posts..."
UNCATEGORIZED_POSTS=$(wp db query "
  SELECT COUNT(*)
  FROM wp_posts p
  LEFT JOIN wp_term_relationships tr ON (p.ID = tr.object_id)
  LEFT JOIN wp_term_taxonomy tt ON (tr.term_taxonomy_id = tt.term_taxonomy_id AND tt.taxonomy = 'category')
  WHERE p.post_type = 'post'
    AND p.post_status = 'publish'
    AND tt.term_id IS NULL
" --skip-column-names --path="$WP_PATH" 2>/dev/null || echo "0")

echo "   - Posts without categories: ${UNCATEGORIZED_POSTS}"
echo ""

# 7. Generate comprehensive report
echo "[7/7] Generating audit report..."

cat > "${REPORT_FILE}" <<EOF
========================================
BLOG CONTENT AUDIT REPORT
${SITE_NAME}
URL: ${SITE_URL}
Date: ${DATE}
========================================

CONTENT OVERVIEW
----------------
Total Published Posts: ${TOTAL_POSTS}
Total Categories: ${TOTAL_CATEGORIES}

CONTENT CATEGORIZATION
----------------------

SME-Focused Content:
  Posts mentioning "SME": ${SME_POSTS}
  Posts mentioning "small business": ${BUSINESS_POSTS}
  Posts mentioning "case study": ${CASE_STUDY_POSTS}
  Total SME-focused: $((SME_POSTS + BUSINESS_POSTS + CASE_STUDY_POSTS))

Technical Content:
  Posts mentioning "WordPress": ${TECHNICAL_POSTS}
  Posts mentioning "tutorial": ${TUTORIAL_POSTS}
  Posts mentioning "guide": ${GUIDE_POSTS}
  Total Technical: $((TECHNICAL_POSTS + TUTORIAL_POSTS + GUIDE_POSTS))

CONTENT QUALITY METRICS
-----------------------
Posts without featured images: ${POSTS_NO_FEATURED}
Posts with < 800 words: ${THIN_CONTENT_COUNT}
Posts without categories: ${UNCATEGORIZED_POSTS}

Content Length Distribution:
EOF

# Add content length distribution
if [[ -f "${OUTPUT_DIR}/content-length-${DATE}.txt" ]]; then
    echo "" >> "${REPORT_FILE}"
    echo "ID,Title,Content Length,Word Count" >> "${REPORT_FILE}"
    head -20 "${OUTPUT_DIR}/content-length-${DATE}.txt" >> "${REPORT_FILE}" 2>/dev/null || true
fi

cat >> "${REPORT_FILE}" <<EOF

RECOMMENDATIONS
---------------
1. Content Balance: Consider adding more SME-focused posts if targeting small businesses
2. Featured Images: Add featured images to ${POSTS_NO_FEATURED} posts
3. Content Depth: Review ${THIN_CONTENT_COUNT} thin content posts for expansion or consolidation
4. Categorization: Assign categories to ${UNCATEGORIZED_POSTS} uncategorized posts
5. Content Strategy: Plan regular publishing schedule for consistent fresh content

NEXT STEPS
----------
[ ] Review ${BLOG_AUDIT_FILE} for full post inventory
[ ] Check ${CATEGORY_AUDIT_FILE} for category organization opportunities
[ ] Review ${OUTPUT_DIR}/content-length-${DATE}.txt for posts needing expansion
[ ] Add featured images to all posts without them
[ ] Assign categories to all uncategorized posts
[ ] Plan content calendar for next quarter
[ ] Consider content audit every 6 months

DETAILED FINDINGS
----------------
EOF

if [[ "$POSTS_NO_FEATURED" -gt 0 ]]; then
    cat >> "${REPORT_FILE}" <<EOF

Posts without Featured Images:
EOF
    wp post list \
      --post_type=post \
      --meta_key=_thumbnail_id \
      --meta_compare=NOT EXISTS \
      --fields=ID,post_title,post_date \
      --format=table --path="$WP_PATH" >> "${REPORT_FILE}" 2>/dev/null || echo "  Could not retrieve list" >> "${REPORT_FILE}"
fi

if [[ "$THIN_CONTENT_COUNT" -gt 0 ]]; then
    cat >> "${REPORT_FILE}" <<EOF

Posts with Thin Content (< 800 words):
EOF
    wp db query "
      SELECT ID, post_title, ROUND(CHAR_LENGTH(post_content) / 6) as word_count
      FROM wp_posts
      WHERE post_type='post'
        AND post_status='publish'
        AND CHAR_LENGTH(post_content) < 4800
      ORDER BY word_count ASC
    " --skip-column-names --path="$WP_PATH" >> "${REPORT_FILE}" 2>/dev/null || echo "  Could not retrieve list" >> "${REPORT_FILE}"
fi

if [[ "$UNCATEGORIZED_POSTS" -gt 0 ]]; then
    cat >> "${REPORT_FILE}" <<EOF

Uncategorized Posts:
EOF
    wp db query "
      SELECT p.ID, p.post_title, p.post_date
      FROM wp_posts p
      LEFT JOIN wp_term_relationships tr ON (p.ID = tr.object_id)
      LEFT JOIN wp_term_taxonomy tt ON (tr.term_taxonomy_id = tt.term_taxonomy_id AND tt.taxonomy = 'category')
      WHERE p.post_type = 'post'
        AND p.post_status = 'publish'
        AND tt.term_id IS NULL
    " --skip-column-names --path="$WP_PATH" >> "${REPORT_FILE}" 2>/dev/null || echo "  Could not retrieve list" >> "${REPORT_FILE}"
fi

cat >> "${REPORT_FILE}" <<EOF

OUTPUT FILES
------------
- ${BLOG_AUDIT_FILE}
- ${CATEGORY_AUDIT_FILE}
- ${OUTPUT_DIR}/content-length-${DATE}.txt
- ${REPORT_FILE}

========================================
EOF

echo "✓ Blog audit complete!"
echo ""
echo "Reports saved to:"
echo "  - ${BLOG_AUDIT_FILE}"
echo "  - ${CATEGORY_AUDIT_FILE}"
echo "  - ${REPORT_FILE}"
echo ""
echo "View full report: cat ${REPORT_FILE}"
