#!/bin/bash
#
# Remote TTFB test with multiple user agents. Runs curl on the server itself
# (via SSH) rather than from your machine, so DNS/network distance to the
# server doesn't skew the measurement — and tests how the server responds to
# common crawler user agents (Googlebot, AhrefsBot, Screaming Frog) alongside
# a default request, which matters when a WAF or caching layer treats bots
# differently from regular visitors.
#
# Usage:
#   ./remote-ttfb-ua.sh <ssh-host> <url1> [url2 ...]
#   ./remote-ttfb-ua.sh web@example.com https://example.com/ https://example.com/blog/
#
# Requires: SSH access to the given host, with wp-ops not needed there — this
# only shells out to curl on the remote side.
#
# @desc     Measure TTFB from the server itself, across multiple user agents (default, Googlebot, AhrefsBot, Screaming Frog)
# @category monitoring
# @platform any
# @runs     local
# @requires ssh
# @arg      ssh-host  required  {web@example.com}  SSH user@host to run curl from
# @arg      url       required  {https://example.com}  URL to test (repeatable)
# @example  wp-ops remote-ttfb-ua web@example.com https://example.com/
# @doc      docs/wordpress-utilities/speed-optimization/README.md

set -euo pipefail

SSH_HOST="${1:-}"
shift || true
urls=("$@")

if [ -z "$SSH_HOST" ] || [ "${#urls[@]}" -eq 0 ]; then
  echo "Usage: $0 <ssh-host> <url1> [url2 ...]"
  echo "Example: $0 web@example.com https://example.com/"
  exit 1
fi

DATE=$(date +%Y-%m-%d_%H-%M-%S)
OUT_DIR="audits"
OUT_FILE="${OUT_DIR}/remote-ttfb-ua-${DATE}.txt"

mkdir -p "${OUT_DIR}"

ssh "${SSH_HOST}" "bash -s -- ${urls[@]}" <<'SH' > "${OUT_FILE}"
set -euo pipefail

urls=("$@")

declare -A uas
uas[default]=""
uas[googlebot]="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
uas[ahrefs]="Mozilla/5.0 (compatible; AhrefsBot/7.0; +http://ahrefs.com/robot/)"
uas[screamingfrog]="Mozilla/5.0 (compatible; Screaming Frog SEO Spider/20.0; +http://www.screamingfrog.co.uk/seo-spider/)"

for label in "${!uas[@]}"; do
  ua="${uas[$label]}"
  echo "===== UA: ${label} ====="
  for url in "${urls[@]}"; do
    echo "URL: ${url}"
    if [ -n "$ua" ]; then
      curl -s -o /dev/null -D - -A "$ua" -w "ttfb=%{time_starttransfer} total=%{time_total} code=%{http_code}\n" "$url"
    else
      curl -s -o /dev/null -D - -w "ttfb=%{time_starttransfer} total=%{time_total} code=%{http_code}\n" "$url"
    fi
    echo ""
  done
  echo ""
  echo ""
done
SH

echo "Saved: ${OUT_FILE}"
