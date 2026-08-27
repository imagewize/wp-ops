#!/usr/bin/env bash
#
# Orphan Links Audit Script
# Purpose: Find published posts/pages with zero internal links pointing at them
# Output: CSV report of orphaned content
#
# This is the inbound-link sibling of orphan-pages-audit.sh. The two answer
# different questions and are both worth running:
#
#   orphan-pages-audit.sh   pages missing from the navigation menus
#   orphan-links-audit.sh   pages nothing else links to in its content (this one)
#
# A page can sit in the nav and still have zero in-content links, or be linked
# from a dozen posts while absent from every menu.
#
# Usage: ./orphan-links-audit.sh [OPTIONS]
#
# Options:
#   --host HOST       SSH user@host to run WP-CLI on (default: run locally)
#   --site-path PATH  Site root on the server, for the SSH cd (default: /srv/www/<domain>/current)
#   --path PATH       WordPress path for WP-CLI (default: web/wp for Bedrock)
#   --output DIR      Output directory (default: audits)
#   -h, --help        Show this help
#
# Requires: WP-CLI access to the WordPress installation (locally or over SSH)
#
# Caveat: link detection is a substring match of each page's slug against other
# published post_content, so a slug that happens to appear as plain text counts
# as a link, and a page linked only by ID (or by a slug-less shortlink) reads as
# orphaned. Treat the output as a shortlist to review, not a verdict.
#
# @desc     Find published posts/pages that no other content links to internally
# @category seo
# @platform wordpress
# @runs     local
# @mutates  false
# @requires wp
# @flag     --host       optional  {web@example.com}  SSH user@host to run WP-CLI on
# @flag     --site-path  optional  {/srv/www/example.com/current}  Site root on the server
# @flag     --path       optional  {web/wp}  WordPress path for WP-CLI
# @flag     --output     optional  {audits}  Output directory
# @example  wp-ops orphan-links-audit --host web@example.com
# @example  wp-ops orphan-links-audit --path web/wp --output reports/seo
# @doc      wp-cli/seo/README.md

set -euo pipefail

SSH_HOST=""
SITE_PATH=""
WP_PATH="web/wp"
OUTPUT_DIR="audits"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            SSH_HOST="$2"
            shift 2
            ;;
        --site-path)
            SITE_PATH="$2"
            shift 2
            ;;
        --path)
            WP_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo "  --host HOST       SSH user@host to run WP-CLI on (default: run locally)"
            echo "  --site-path PATH  Site root on the server for the SSH cd"
            echo "  --path PATH       WordPress path for WP-CLI (default: web/wp)"
            echo "  --output DIR      Output directory (default: audits)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Default the server-side site root to the domain implied by the SSH host.
if [ -n "$SSH_HOST" ] && [ -z "$SITE_PATH" ]; then
    SITE_PATH="/srv/www/${SSH_HOST#*@}/current"
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/orphan-links-$TIMESTAMP.csv"

echo "========================================="
echo "Orphan Links Audit"
echo "========================================="
if [ -n "$SSH_HOST" ]; then
    echo "Target: $SSH_HOST:$SITE_PATH"
else
    echo "Target: local ($WP_PATH)"
fi
echo ""

# Count how many other published posts reference each post's slug; keep the zeroes.
read -r -d '' QUERY <<'SQL' || true
SELECT
    p.ID,
    p.post_title,
    p.post_type,
    p.post_date,
    p.post_status,
    p.guid,
    COUNT(DISTINCT l.ID) as internal_links
FROM wp_posts p
LEFT JOIN wp_posts l ON (
    l.post_content LIKE CONCAT('%', p.post_name, '%')
    AND l.ID != p.ID
    AND l.post_status = 'publish'
)
WHERE p.post_type IN ('post', 'page')
AND p.post_status = 'publish'
GROUP BY p.ID
HAVING internal_links = 0
ORDER BY p.post_date DESC
SQL

echo "Analyzing internal links..."
echo ""

if [ -n "$SSH_HOST" ]; then
    RAW=$(ssh "$SSH_HOST" "cd $SITE_PATH && wp db query \"$QUERY\" --path=$WP_PATH --skip-column-names")
else
    RAW=$(wp db query "$QUERY" --path="$WP_PATH" --skip-column-names)
fi

printf '%s\n' "$RAW" | awk -F'\t' '
    BEGIN {print "ID,Title,Type,Date,Status,URL,Internal Links"}
    NF {gsub(/,/, " ", $2); print $1","$2","$3","$4","$5","$6","$7}
' > "$OUTPUT_FILE"

ORPHAN_COUNT=$(tail -n +2 "$OUTPUT_FILE" | wc -l | xargs)

echo "Audit complete."
echo ""
echo "Results:"
echo "  Total orphaned by inbound links: $ORPHAN_COUNT"
echo "  Output file: $OUTPUT_FILE"
echo ""

if [ "$ORPHAN_COUNT" -gt 0 ]; then
    echo "Breakdown by content type:"
    tail -n +2 "$OUTPUT_FILE" | cut -d',' -f3 | sort | uniq -c | sort -rn
    echo ""
fi

echo "Next steps:"
echo "1. Review $OUTPUT_FILE"
echo "2. Categorize by topic/value"
echo "3. Add internal links from relevant pages"
echo ""
