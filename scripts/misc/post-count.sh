#!/usr/bin/env bash
# post-count.sh — Count published WordPress posts by year (blog posts only)
#
# Counts real blog posts (post_type=post, post_status=publish by default) grouped
# by the year of post_date. Custom post types, pages, nav menu items, attachments,
# revisions, and drafts are excluded unless you override --type / --status.
#
# Runs `wp db query` against a WordPress install. Run it where WP-CLI works — inside
# the Trellis VM, on the production server, or from your host via --ssh (which wraps
# the query in an ssh call to the server).
#
# Usage: ./post-count.sh [OPTIONS]
#
# Options:
#   --year YYYY       Only this year — prints a single total
#   --months YYYY     Monthly breakdown (YYYY-MM) for the given year
#   --type TYPE       post_type to count (default: post)
#   --status STATUS   post_status to count (default: publish)
#   --path PATH       WordPress path passed to WP-CLI (default: web/wp)
#   --ssh HOST        Run remotely over ssh, e.g. web@example.com
#   --site DIR        Remote site dir to cd into with --ssh
#                     (default: /srv/www/example.com/current)
#   -h, --help        Show this help
#
# Examples:
#   # All years, blog posts only (run inside VM or on server)
#   ./post-count.sh
#
#   # From your host, hit production over SSH
#   ./post-count.sh --ssh web@example.com
#
#   # Just 2026's blog-post total
#   ./post-count.sh --ssh web@example.com --year 2026
#
#   # Month-by-month for 2026
#   ./post-count.sh --ssh web@example.com --months 2026
#
#   # aseonomics.com on the same server
#   ./post-count.sh --ssh web@example.com --site /srv/www/aseonomics.com/current

# @desc     Count published WordPress posts by year (or month), locally or over SSH
# @category misc
# @platform wordpress
# @runs     local
# @mutates  false
# @requires wp
# @flag     --year     optional  {2026}  Only this year — prints a single total
# @flag     --months   optional  {2026}  Monthly breakdown (YYYY-MM) for the given year
# @flag     --type     optional  {post}  post_type to count
# @flag     --status   optional  {publish}  post_status to count
# @flag     --path     optional  {web/wp}  WordPress path passed to WP-CLI
# @flag     --ssh      optional  {web@example.com}  Run remotely over ssh
# @flag     --site     optional  {/srv/www/example.com/current}  Remote site dir to cd into with --ssh
# @example  wp-ops post-count --ssh web@example.com --year 2026

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
YEAR=""
MONTHS=""
PTYPE="post"
PSTATUS="publish"
WP_PATH="web/wp"
SSH_HOST=""
SITE_DIR="/srv/www/example.com/current"

usage() {
  # Print the leading comment block (from line 2 until the first non-comment line)
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
  exit "${1:-0}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --year)    YEAR="$2";    shift 2 ;;
    --months)  MONTHS="$2";  shift 2 ;;
    --type)    PTYPE="$2";   shift 2 ;;
    --status)  PSTATUS="$2"; shift 2 ;;
    --path)    WP_PATH="$2"; shift 2 ;;
    --ssh)     SSH_HOST="$2"; shift 2 ;;
    --site)    SITE_DIR="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) printf "${RED}Unknown option: %s${NC}\n" "$1" >&2; usage 2 ;;
  esac
done

# Validate year-like arguments
for y in "$YEAR" "$MONTHS"; do
  if [[ -n "$y" && ! "$y" =~ ^[0-9]{4}$ ]]; then
    printf "${RED}Year must be a 4-digit number (got: %s)${NC}\n" "$y" >&2
    exit 2
  fi
done

# ── Build the SQL ─────────────────────────────────────────────────────────────
WHERE="post_type='${PTYPE}' AND post_status='${PSTATUS}'"

if [[ -n "$MONTHS" ]]; then
  SQL="SELECT DATE_FORMAT(post_date,'%Y-%m') AS month, COUNT(*) AS posts
       FROM wp_posts WHERE ${WHERE} AND YEAR(post_date)=${MONTHS}
       GROUP BY month ORDER BY month;"
  HEADER="Monthly ${PTYPE} count (${PSTATUS}) for ${MONTHS}"
elif [[ -n "$YEAR" ]]; then
  SQL="SELECT COUNT(*) AS posts FROM wp_posts
       WHERE ${WHERE} AND YEAR(post_date)=${YEAR};"
  HEADER="${PTYPE} count (${PSTATUS}) for ${YEAR}"
else
  SQL="SELECT YEAR(post_date) AS year, COUNT(*) AS posts FROM wp_posts
       WHERE ${WHERE} GROUP BY year ORDER BY year DESC;"
  HEADER="${PTYPE} count (${PSTATUS}) by year"
fi

# Collapse whitespace so it travels cleanly over ssh
SQL="$(printf '%s' "$SQL" | tr '\n' ' ' | tr -s ' ')"

# ── Run the query ─────────────────────────────────────────────────────────────
printf "${CYAN}=== %s ===${NC}\n" "$HEADER"
[[ -n "$SSH_HOST" ]] && printf "${CYAN}Site: %s (%s)${NC}\n" "$SITE_DIR" "$SSH_HOST"
printf "\n"

if [[ -n "$SSH_HOST" ]]; then
  ssh "$SSH_HOST" "cd '${SITE_DIR}' && wp db query \"${SQL}\" --path='${WP_PATH}'"
else
  if ! command -v wp >/dev/null 2>&1; then
    printf "${RED}wp (WP-CLI) not found. Run this inside the Trellis VM / on the server, or use --ssh.${NC}\n" >&2
    exit 2
  fi
  wp db query "${SQL}" --path="${WP_PATH}"
fi

printf "\n${GREEN}Done.${NC}\n"
