#!/usr/bin/env bash
# traffic-by-country.sh
# Filter Nginx access logs by country and show real page visits.
#
# Pulls the log from the server over SSH, resolves every unique client IP to a
# country with geoip2fast, then reports only the requests from the country you
# asked about — with bots, static assets, attack probes, Tor exits, and
# redirect/404 responses filtered out, so what's left is real page views.
#
# Useful for checking whether outreach prospects actually visited after an
# email went out, or auditing geo-specific traffic to localized pages.
#
# Usage:
#   ./traffic-by-country.sh [OPTIONS] [COUNTRY_CODE] [DATE_FILTER]
#
# Options:
#   --host HOST          SSH user@host to pull logs from (default: web@example.com)
#   --log PATH           Nginx access log path on the server
#   -q, --quick          Quick mode: last 10,000 log lines only (fast)
#   -p, --pattern PAT    Filter for specific URL pattern (e.g., "/nl-" or "/dutch-")
#   -h, --hours N        Last N hours of traffic (implies -q)
#   --show-bots          Include bot traffic in results (default: exclude)
#
# Examples:
#   ./traffic-by-country.sh --host web@example.com NL           # All NL traffic, current week
#   ./traffic-by-country.sh NL "29/May/2026"                    # NL traffic on a specific date
#   ./traffic-by-country.sh -q NL                               # Quick: last 10k lines, NL only
#   ./traffic-by-country.sh -q -p "/nl-|/dutch-" NL             # Quick: NL visits to Dutch pages
#   ./traffic-by-country.sh -q --hours 24 NL                    # Last 24h of NL traffic
#   ./traffic-by-country.sh DE                                  # German traffic
#
# Requirements:
#   - geoip2fast installed locally (brew install geoip2fast)
#   - SSH access to the server
#   - python3
#
# @desc     Filter a server's Nginx access log by visitor country and show real page visits
# @category monitoring
# @runs     local
# @requires ssh python3 geoip2fast
# @arg      country-code  optional  {NL}  Two-letter ISO country code to filter for
# @arg      date-filter   optional  {29/May/2026}  Only lines matching this date string
# @flag     --host        optional  {web@example.com}  SSH user@host to pull logs from
# @flag     --log         optional  {/srv/www/example.com/logs/access.log}  Nginx access log path on the server
# @flag     --quick       optional  Only pull the last 10,000 log lines
# @flag     --pattern     optional  {/nl-|/dutch-}  Only count requests whose URL matches this regex
# @flag     --hours       optional  {24}  Only pull the last N hours (implies --quick)
# @flag     --show-bots   optional  Include bot traffic instead of filtering it out
# @example  wp-ops traffic-by-country --host web@example.com NL
# @example  wp-ops traffic-by-country -q --hours 24 --pattern "/contact/" US
# @doc      scripts/README.md

set -euo pipefail

# --- Defaults ---
COUNTRY="NL"
DATE_FILTER=""
QUICK_MODE=false
URL_PATTERN=""
HOURS_BACK=0
SHOW_BOTS=false
SSH_HOST="web@example.com"
LOG_BASE=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            SSH_HOST="$2"
            shift 2
            ;;
        --log)
            LOG_BASE="$2"
            shift 2
            ;;
        -q|--quick)
            QUICK_MODE=true
            shift
            ;;
        -p|--pattern)
            URL_PATTERN="$2"
            shift 2
            ;;
        -h|--hours)
            HOURS_BACK="$2"
            QUICK_MODE=true
            shift 2
            ;;
        --show-bots)
            SHOW_BOTS=true
            shift
            ;;
        --help)
            sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [OPTIONS] [COUNTRY_CODE] [DATE_FILTER]"
            echo "  --host HOST      SSH user@host to pull logs from"
            echo "  --log PATH       Nginx access log path on the server"
            echo "  -q, --quick      Quick mode (last 10k lines)"
            echo "  -p, --pattern P  Filter by URL pattern"
            echo "  -h, --hours N    Last N hours (implies -q)"
            echo "  --show-bots      Include bot traffic"
            exit 1
            ;;
        *)
            # Positional: could be country or date filter
            if [[ "$1" =~ ^[A-Z]{2}$ ]]; then
                COUNTRY="$1"
            elif [ -z "$DATE_FILTER" ]; then
                DATE_FILTER="$1"
            fi
            shift
            ;;
    esac
done

# Default the log path to the domain implied by the SSH host, Trellis-style.
if [ -z "$LOG_BASE" ]; then
    LOG_BASE="/srv/www/${SSH_HOST#*@}/logs/access.log"
fi

TMP_DIR="/tmp/traffic-country-$$"
mkdir -p "$TMP_DIR"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# --- Patterns ---
BOT_PATTERN='bot|Bot|crawler|spider|Prerender|GeedoShop|meta-externalagent|Googlebot|bingbot|AhrefsBot|SemrushBot|DataForSeoBot|PetalBot|YandexBot|DotBot|MJ12bot|Screaming|frog|ChatGPT|Claude|Amazonbot|Applebot|Bytespider|CCBot'
ASSET_PATTERN='\.(css|js|png|jpg|jpeg|gif|svg|woff|woff2|ttf|ico|webp|map)(\?|$)'
ATTACK_PATTERN='wp-login|xmlrpc|\.env|\.git/|phpinfo|wp-config|admin-ajax\.php'
TOR_PATTERN='192\.42\.116\.|192\.42\.117\.|192\.42\.118\.|192\.42\.119\.'

echo "=============================================================================="
echo "Traffic by Country: $COUNTRY"
echo "Server: $SSH_HOST"
echo "Log: $LOG_BASE"
if [ "$QUICK_MODE" = true ]; then
    if [ "$HOURS_BACK" -gt 0 ] 2>/dev/null; then
        echo "Mode: Last $HOURS_BACK hours (quick)"
    else
        echo "Mode: Last 10,000 lines (quick)"
    fi
else
    echo "Mode: Full (current + previous week)"
fi
if [ -n "$URL_PATTERN" ]; then
    echo "URL Pattern: $URL_PATTERN"
fi
if [ -n "$DATE_FILTER" ]; then
    echo "Date Filter: $DATE_FILTER"
fi
if [ "$SHOW_BOTS" = true ]; then
    echo "Bots: Included"
else
    echo "Bots: Excluded"
fi
echo "=============================================================================="
echo ""

# --- Step 1: Pull logs ---
if [ "$QUICK_MODE" = true ]; then
    if [ "$HOURS_BACK" -gt 0 ] 2>/dev/null; then
        echo "Pulling last $HOURS_BACK hours of logs..."
        ssh "$SSH_HOST" "
            awk -v hours=$HOURS_BACK -v now=\$(date +%s) '
            \$4 ~ /^\[/ {
                cmd = \"date -d \"\$4\" +%s\"
                cmd | getline ts
                close(cmd)
                if (ts >= now - hours*3600) print
            }' ${LOG_BASE} 2>/dev/null | tail -10000
        " > "$TMP_DIR/combined.log"
    else
        echo "Quick mode: pulling last 10,000 log lines..."
        ssh "$SSH_HOST" "tail -10000 ${LOG_BASE} 2>/dev/null" > "$TMP_DIR/combined.log"
    fi
else
    echo "Full mode: pulling current + previous week logs..."
    ssh "$SSH_HOST" "
        { cat ${LOG_BASE}; cat ${LOG_BASE}.1; } 2>/dev/null
    " > "$TMP_DIR/combined.log"
fi

LINE_COUNT=$(wc -l < "$TMP_DIR/combined.log")
echo "Lines pulled: $LINE_COUNT"

# --- Step 2: Apply filters ---
LOG_FILE="$TMP_DIR/combined.log"

if [ -n "$DATE_FILTER" ]; then
    echo "Filtering for date: $DATE_FILTER"
    grep "$DATE_FILTER" "$LOG_FILE" > "$TMP_DIR/filtered.log" || true
    LOG_FILE="$TMP_DIR/filtered.log"
    echo "Lines after date filter: $(wc -l < "$LOG_FILE")"
fi

if [ -n "$URL_PATTERN" ]; then
    echo "Filtering for URL pattern: $URL_PATTERN"
    grep -E "$URL_PATTERN" "$LOG_FILE" > "$TMP_DIR/pattern-filtered.log" || true
    LOG_FILE="$TMP_DIR/pattern-filtered.log"
    echo "Lines after pattern filter: $(wc -l < "$LOG_FILE")"
fi

echo ""

# --- Step 3: Extract unique IPs ---
echo "Extracting unique IPs..."

if [ "$SHOW_BOTS" = true ]; then
    awk '{print $1}' "$LOG_FILE" | sort -u > "$TMP_DIR/ips.txt"
else
    grep -vE "$BOT_PATTERN" "$LOG_FILE" | awk '{print $1}' | sort -u > "$TMP_DIR/ips.txt"
fi

IP_COUNT=$(wc -l < "$TMP_DIR/ips.txt")
echo "Unique IPs to check: $IP_COUNT"
echo ""

# --- Step 4: GeoIP filter ---
echo "Running GeoIP lookup for country: $COUNTRY..."

python3 - <<PYEOF
import subprocess, json, re, sys

with open('$TMP_DIR/ips.txt') as f:
    ips = [l.strip() for l in f if l.strip()]

if not ips:
    print('No IPs to check.')
    with open('$TMP_DIR/country-ips.txt', 'w') as f:
        pass
    sys.exit(0)

hits = []
chunk_size = 500
for i in range(0, len(ips), chunk_size):
    chunk = ','.join(ips[i:i+chunk_size])
    try:
        r = subprocess.run(['geoip2fast', chunk], capture_output=True, text=True, timeout=30)
        for b in re.findall(r'\{[^{}]*\}', r.stdout, re.DOTALL):
            try:
                d = json.loads(b)
                if d.get('country_code') == '$COUNTRY':
                    hits.append(d['ip'])
            except Exception:
                pass
    except subprocess.TimeoutExpired:
        print(f'Warning: geoip2fast timeout on chunk {i//chunk_size + 1}')
        continue

with open('$TMP_DIR/country-ips.txt', 'w') as f:
    f.write('\n'.join(hits))
print(f'IPs from $COUNTRY: {len(hits)}')
PYEOF

if [ ! -s "$TMP_DIR/country-ips.txt" ]; then
    echo "No IPs found for $COUNTRY."
    exit 0
fi

echo ""

# --- Step 5: Show results ---
COUNTRY_IPS_FILE="$TMP_DIR/country-ips.txt"

# Count visits
TOTAL_VISITS=$(grep -cF -f "$COUNTRY_IPS_FILE" "$LOG_FILE" || echo 0)
REAL_VISITS=$(grep -F -f "$COUNTRY_IPS_FILE" "$LOG_FILE" | grep -vE "$BOT_PATTERN|$ATTACK_PATTERN|$TOR_PATTERN|$ASSET_PATTERN" | grep -v ' 301\b\| 302\b\| 404\b\| 444\b' | wc -l)
BOT_VISITS=$((TOTAL_VISITS - REAL_VISITS))

echo "=== Summary ==="
echo "Total requests from $COUNTRY IPs: $TOTAL_VISITS"
echo "Real page visits (non-bot, non-attack): $REAL_VISITS"
echo "Bot/scanner requests: $BOT_VISITS"
echo ""

# Show real visits
echo "=== Real Page Visits from $COUNTRY IPs ==="
echo ""

grep -F -f "$COUNTRY_IPS_FILE" "$LOG_FILE" \
  | grep -vE "$BOT_PATTERN|$ATTACK_PATTERN|$TOR_PATTERN" \
  | grep -vE "$ASSET_PATTERN" \
  | grep -v ' 301\b\| 302\b\| 404\b\| 444\b' \
  | awk '{print $4, $1, $6, $7, $9}' \
  | sort -t'[' -k1,1 \
  | column -t

echo ""

# Top pages
echo "=== Top Pages Visited by $COUNTRY IPs ==="
grep -F -f "$COUNTRY_IPS_FILE" "$LOG_FILE" \
  | grep -vE "$BOT_PATTERN|$ATTACK_PATTERN|$TOR_PATTERN" \
  | grep -vE "$ASSET_PATTERN" \
  | grep -v ' 301\b\| 302\b\| 404\b' \
  | awk '{print $7}' \
  | sort | uniq -c | sort -rn | head -20

echo ""

# Show IPs
echo "=== $COUNTRY IPs ==="
cat "$COUNTRY_IPS_FILE"

echo ""
echo "=============================================================================="
