#!/bin/bash
# check-deny-ips.sh — Verify every individual IP in a Trellis project's
# deny-ips.conf.j2 against AbuseIPDB, so stale blocks (score dropped to 0,
# no recent reports) are easy to spot and remove.
#
# Usage:
#   TRELLIS_DIR=/path/to/trellis ./check-deny-ips.sh [--full]
#
# Without flags: compact one-line-per-IP summary (score, reports, lastSeen)
# With --full:   full JSON output via wp-ops's check-ips.sh
#
# Subnet entries (CIDR blocks) in the conf are skipped — AbuseIPDB checks
# single IPs, not ranges — and reported as a count instead.
#
# API key loaded from trellis/security/.env (ABUSEIPDB_KEY=xxx), the same
# file check-ips.sh uses.
#
# @desc     Check every individual IP in a Trellis deny-ips.conf.j2 against AbuseIPDB
# @category security
# @platform trellis
# @runs     local
# @mutates  false
# @requires curl jq trellis
# @flag     --full  optional  {}  Full JSON output per IP via check-ips.sh, instead of the compact summary
# @example  wp-ops check-deny-ips
# @example  wp-ops check-deny-ips --full
# @doc      trellis/security/README.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${TRELLIS_DIR:-}" ]]; then
  echo "Error: TRELLIS_DIR is not set. Point it at your Trellis project:" >&2
  echo "  export TRELLIS_DIR=/path/to/trellis" >&2
  exit 1
fi

CONF="$TRELLIS_DIR/nginx-includes/all/deny-ips.conf.j2"
if [[ ! -f "$CONF" ]]; then
  echo "Error: deny-ips.conf.j2 not found at $CONF" >&2
  exit 1
fi

ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [[ -z "${ABUSEIPDB_KEY:-}" ]]; then
  echo "Error: ABUSEIPDB_KEY not set."
  echo "Add it to trellis/security/.env:"
  echo "  echo 'ABUSEIPDB_KEY=your_key_here' > trellis/security/.env"
  exit 1
fi
export ABUSEIPDB_KEY

ALL_ENTRIES=$(grep -E '^deny [0-9a-f:.]' "$CONF" | awk '{print $2}' | sed 's/;//')
IPS=$(echo "$ALL_ENTRIES" | grep -v '/' || true)
SUBNET_COUNT=$(echo "$ALL_ENTRIES" | grep -c '/' || true)

if [[ "${1:-}" == "--full" ]]; then
  if ! command -v wp-ops >/dev/null 2>&1; then
    echo "Error: wp-ops not found on PATH." >&2
    exit 1
  fi
  echo "$IPS" | xargs wp-ops check-ips
  exit 0
fi

# Compact summary mode
echo "$(echo "$IPS" | grep -c . || true) IPs checked, ${SUBNET_COUNT} subnet(s) skipped"
echo ""
printf "%-42s %-6s %-8s %-12s %s\n" "IP" "SCORE" "REPORTS" "LAST_SEEN" "NOTE"
printf '%s\n' "$(printf '─%.0s' {1..90})"

echo "$IPS" | while read -r IP; do
  [[ -z "$IP" ]] && continue
  RESP=$(curl -s --max-time 10 \
    -G https://api.abuseipdb.com/api/v2/check \
    --data-urlencode "ipAddress=$IP" \
    -d maxAgeInDays=90 \
    -H "Key: $ABUSEIPDB_KEY" \
    -H "Accept: application/json")

  SCORE=$(echo "$RESP" | jq -r '.data.abuseConfidenceScore // "ERR"')
  REPORTS=$(echo "$RESP" | jq -r '.data.totalReports // "?"')
  LAST=$(echo "$RESP" | jq -r '.data.lastReportedAt // "never"' | cut -c1-10)

  NOTE=""
  if [[ "$SCORE" =~ ^[0-9]+$ ]]; then
    if   (( SCORE == 0 ));  then NOTE="⚠ CONSIDER REMOVING (score 0)"
    elif (( SCORE <= 10 )); then NOTE="⚠ score dropped low"
    elif (( SCORE <= 25 )); then NOTE="~ borderline"
    fi
  fi

  printf "%-42s %-6s %-8s %-12s %s\n" "$IP" "$SCORE" "$REPORTS" "$LAST" "$NOTE"
  sleep 1
done
