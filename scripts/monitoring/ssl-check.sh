#!/bin/bash
# ssl-check.sh - Check a domain's TLS certificate validity dates, issuer and subject
# Usage: bash ssl-check.sh <domain>
#
# @desc     Check a domain's TLS certificate expiry, issuer and subject via openssl
# @category monitoring
# @platform any
# @runs     local
# @mutates  false
# @requires openssl
# @arg      domain  required  {www.example.com}  Domain to check (no scheme, no port)
# @example  wp-ops ssl-check www.example.com

set -euo pipefail

domain="${1:-}"

if [ -z "$domain" ]; then
  echo "Usage: $0 <domain>" >&2
  echo "Example: $0 www.example.com" >&2
  exit 1
fi

cert=$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null \
  | openssl x509 -noout -dates -issuer -subject 2>/dev/null || true)

if [ -z "$cert" ]; then
  echo "Could not retrieve a certificate for $domain — connection failed, no cert presented, or the host doesn't answer on 443." >&2
  exit 1
fi

echo "$cert"

not_after=$(echo "$cert" | sed -n 's/^notAfter=//p')
if [ -n "$not_after" ]; then
  # macOS and GNU date disagree on flags for parsing an arbitrary date string,
  # so try both rather than requiring GNU coreutils.
  expiry_epoch=$(date -j -f "%b %e %T %Y %Z" "$not_after" +%s 2>/dev/null \
    || date -d "$not_after" +%s 2>/dev/null || true)
  now_epoch=$(date +%s)

  if [ -n "$expiry_epoch" ]; then
    days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    if [ "$days_left" -lt 0 ]; then
      echo "EXPIRED $(( -days_left )) day(s) ago"
    else
      echo "Expires in $days_left day(s)"
    fi
  fi
fi
