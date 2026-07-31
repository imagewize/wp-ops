#!/bin/bash
# check-ips.sh — Look up IP addresses against AbuseIPDB threat intelligence
#
# Usage:
#   ./check-ips.sh <ip1> [ip2 ip3 ...]
#
# API key loaded from trellis/security/.env (ABUSEIPDB_KEY=xxx)
# Get a free key at https://www.abuseipdb.com/register (1,000 checks/day)
#
# Requirements:
#   brew install jq curl

set -euo pipefail

# Load API key from a .env file next to this script if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

if [[ $# -eq 0 ]]; then
  echo "Usage: ./check-ips.sh <ip1> [ip2 ip3 ...]"
  exit 1
fi

for IP in "$@"; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $IP"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  RESPONSE=$(curl -s --max-time 10 --connect-timeout 5 \
    -G https://api.abuseipdb.com/api/v2/check \
    --data-urlencode "ipAddress=$IP" \
    -d maxAgeInDays=90 \
    -H "Key: $ABUSEIPDB_KEY" \
    -H "Accept: application/json")

  # Check for API errors (throttle, invalid key, etc.)
  if echo "$RESPONSE" | jq -e '.errors' &>/dev/null; then
    echo "$RESPONSE" | jq '.errors[]'
  elif [[ -z "$RESPONSE" ]]; then
    echo "  [ERROR] No response (timeout or network issue)"
  else
    echo "$RESPONSE" | jq '{
        score:     .data.abuseConfidenceScore,
        reports:   .data.totalReports,
        lastSeen:  .data.lastReportedAt,
        country:   .data.countryCode,
        isp:       .data.isp,
        usageType: .data.usageType,
        domain:    .data.domain,
        tor:       .data.isTor
      }'
  fi
  echo ""
  # Respect AbuseIPDB rate limit (1 req/sec on free tier)
  sleep 1
done
