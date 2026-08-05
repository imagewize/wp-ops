#!/usr/bin/env bash
# 404-checker.sh — Check internal links for broken responses (4xx/5xx)
#
# Usage: ./404-checker.sh [OPTIONS] <site-url>
#
# Modes:
#   global  (default) — fetch homepage, check all internal links (~30s)
#   spider             — recursive wget spider, depth 3 (~5-10 min)
#
# Examples:
#   ./404-checker.sh https://example.com
#   ./404-checker.sh --mode spider https://example.com
#   ./404-checker.sh --output results.txt https://example.com
#
# @desc     Check a site's internal links for broken (4xx/5xx) responses
# @category monitoring
# @platform any
# @runs     local
# @requires curl
# @arg      site-url  required  {https://example.com}  Site to check
# @flag     --mode     optional  {global|spider}  global checks homepage links (~30s); spider recursively crawls (~5-10 min)
# @flag     --output   optional  Append broken-link results to this file
# @flag     --timeout  optional  {10}  curl max-time per request, in seconds
# @flag     --level    optional  {3}  Spider depth for --mode spider
# @example  wp-ops scripts/monitoring/404-checker https://example.com
# @example  wp-ops scripts/monitoring/404-checker --mode spider https://example.com

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
MODE="global"
OUTPUT=""
TIMEOUT=10
LEVEL=3
SITE=""
BROKEN=0

# ── Helpers ──────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <site-url>

Options:
  --mode global   Check all links found on the homepage (fast, ~30s) [default]
  --mode spider   Recursive wget spider to depth $LEVEL (slow, ~5-10 min)
  --output FILE   Append broken-link results to FILE (default: stdout only)
  --timeout N     curl max-time per request in seconds (default: $TIMEOUT)
  --level N       Spider depth for --mode spider (default: $LEVEL)
  -h, --help      Show this help

Exit codes:
  0   No broken links found
  1   One or more broken links found
  2   Usage error or missing dependency
EOF
  exit 2
}

log()  { printf "${CYAN}[%s]${NC} %s\n" "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*" >&2; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2; }
err()  { printf "${RED}[ERR]${NC} %s\n" "$*" >&2; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)    MODE="$2";    shift 2 ;;
    --output)  OUTPUT="$2";  shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --level)   LEVEL="$2";   shift 2 ;;
    -h|--help) usage ;;
    http*)     SITE="${1%/}"; shift ;;
    *)         err "Unknown option: $1"; usage ;;
  esac
done

if [[ -z "$SITE" ]]; then
  err "Site URL is required."
  usage
fi

# Use bash parameter expansion — avoids BSD vs GNU sed \? differences
DOMAIN="${SITE#*://}"   # strip scheme (https:// or http://)
DOMAIN="${DOMAIN%%/*}"  # strip any path component

# Escape dots in domain for use in grep regex
DOMAIN_RE="${DOMAIN/./\\.}"

# ── Output helper ─────────────────────────────────────────────────────────────
report() {
  if [[ -n "$OUTPUT" ]]; then
    printf '%s\n' "$1" | tee -a "$OUTPUT"
  else
    printf '%s\n' "$1"
  fi
}

report_header() {
  if [[ -n "$OUTPUT" ]]; then
    printf '=== 404 Checker: %s | mode=%s | %s ===\n' \
      "$SITE" "$MODE" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT"
  fi
}

# ── Single URL check ──────────────────────────────────────────────────────────
check_url() {
  local url="$1" status
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" -L "$url" 2>/dev/null) \
    || status="ERR"
  printf '%s  %s' "$status" "$url"
}

# ── Mode: global (homepage links) ────────────────────────────────────────────
run_global() {
  log "Fetching homepage: $SITE"

  local raw_html=""
  raw_html=$(curl -s --max-time 20 "$SITE" 2>/dev/null) || true

  if [[ -z "$raw_html" ]]; then
    warn "Could not fetch homepage — check the URL and your connection."
    return
  fi

  # Extract, filter, and normalise internal links.
  # Pipe through grep/sed in a subshell so non-zero exit codes don't abort.
  local raw_links=""
  raw_links=$(
    printf '%s\n' "$raw_html" \
      | grep -Eo 'href="[^"#]+"' \
      | sed 's/href="//;s/"$//' \
      | grep -vE '^(mailto:|tel:|javascript:|#|$)' \
      | grep -E "^(/|https?://${DOMAIN_RE})" \
      | grep -vE '\.(css|js|woff2?|ttf|eot|png|jpg|jpeg|gif|webp|svg|ico|xml|pdf)(\?|$)' \
      | grep -vE '/(wp-json|wp/xmlrpc|xmlrpc\.php|feed|sitemap)' \
      | sed "s|^/|${SITE}/|g" \
      | sed "s|${SITE}//|${SITE}/|g" \
      | sort -u
  ) 2>/dev/null || true

  local count=0
  if [[ -n "$raw_links" ]]; then
    count=$(printf '%s\n' "$raw_links" | wc -l | tr -d ' \t')
  fi
  log "Found $count internal links — checking each..."

  if [[ "$count" -eq 0 ]]; then
    warn "No internal links found on homepage. Check the URL and try again."
    return
  fi

  while IFS= read -r url; do
    [[ -z "$url" ]] && continue
    local result status
    result=$(check_url "$url")
    status="${result%%  *}"
    if [[ "$status" =~ ^[45] ]] || [[ "$status" == "ERR" ]]; then
      report "$result"
      err "Broken: $result"
      BROKEN=$((BROKEN + 1))
    fi
  done <<< "$raw_links"

  if [[ $BROKEN -eq 0 ]]; then
    ok "All $count links OK."
  else
    warn "$BROKEN broken link(s) found."
  fi
}

# ── Mode: spider (wget recursive) ────────────────────────────────────────────
run_spider() {
  if ! command -v wget &>/dev/null; then
    err "wget is required for spider mode. Install: brew install wget"
    exit 2
  fi

  local tmpfile
  tmpfile=$(mktemp /tmp/404-spider-XXXXXX.txt)
  trap 'rm -f "$tmpfile"' EXIT

  log "Starting recursive spider (depth $LEVEL) on $SITE ..."
  log "This may take several minutes."

  wget \
    --spider \
    --recursive \
    --level="$LEVEL" \
    --no-verbose \
    --output-file="$tmpfile" \
    --domains="$DOMAIN" \
    --reject-regex="(wp-admin|wp-login|feed|sitemap|\.xml$|\.pdf$|\.jpg$|\.jpeg$|\.png$|\.gif$|\.webp$|\.css$|\.js$|\.woff)" \
    "$SITE" 2>/dev/null || true

  log "Spider done — extracting broken links from log..."

  local prev_url=""
  while IFS= read -r line; do
    if echo "$line" | grep -qE 'https?://'; then
      prev_url=$(echo "$line" | grep -oE 'https?://[^[:space:]]+' | head -1) || true
    fi
    if echo "$line" | grep -qiE '(404|broken|Remote file does not exist|No such file)'; then
      if [[ -n "$prev_url" ]]; then
        report "404  $prev_url"
        err "Broken: 404  $prev_url"
        BROKEN=$((BROKEN + 1))
        prev_url=""
      fi
    fi
  done < "$tmpfile"

  if [[ $BROKEN -eq 0 ]]; then
    ok "Spider complete — no broken links found."
  else
    warn "$BROKEN broken link(s) found."
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  report_header

  case "$MODE" in
    global) run_global ;;
    spider) run_spider ;;
    *)      err "Unknown mode: $MODE"; usage ;;
  esac

  if [[ $BROKEN -gt 0 ]]; then
    exit 1
  fi
}

main
