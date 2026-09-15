#!/bin/bash
# ssl-check.sh - Check TLS certificate validity dates, issuer, subject and hostname match
# Usage: bash ssl-check.sh [--warn-days N] <domain> [domain...]
#
# Without --warn-days it only reports. With it, it becomes an alert: exit 2 if
# any certificate expires within N days, has already expired, or doesn't match
# the hostname it was served for. Let's Encrypt stopped sending expiry reminder
# emails in June 2025, so a failed auto-renewal on a host we don't manage now
# goes unnoticed until visitors hit a browser warning —
# .github/workflows/ssl-expiry.yml runs this daily for exactly that.
#
# The hostname check matters as much as the expiry one: a shared host that
# loses a site's certificate can fall back to serving its own, which is valid
# for months and sails straight through an expiry-only check.
#
# Exit codes:
#   0  every certificate retrieved; with --warn-days, none expiring or mismatched
#   1  bad usage, or at least one certificate could not be retrieved
#   2  with --warn-days: at least one certificate is expiring, expired or mismatched
#
# @desc     Check TLS certificate expiry, issuer, subject and hostname match for one or more domains via openssl
# @category monitoring
# @platform any
# @runs     local
# @mutates  false
# @requires openssl
# @arg      domain  required  {www.example.com}  Domain to check (no scheme, no port); pass several to check them in one run
# @flag     --warn-days  optional  {21}  Exit 2 if a certificate expires within this many days, has expired, or doesn't match its hostname
# @example  wp-ops ssl-check www.example.com
# @example  wp-ops ssl-check --warn-days 21 www.example.com shop.example.com

set -euo pipefail

usage() {
  echo "Usage: $0 [--warn-days N] <domain> [domain...]" >&2
  echo "Example: $0 --warn-days 21 www.example.com shop.example.com" >&2
}

warn_days=""
domains=()

while [ $# -gt 0 ]; do
  case "$1" in
    --warn-days)
      if [ $# -lt 2 ]; then
        echo "--warn-days needs a number of days" >&2
        usage
        exit 1
      fi
      warn_days="$2"
      shift 2
      ;;
    --warn-days=*)
      warn_days="${1#--warn-days=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      domains+=("$1")
      shift
      ;;
  esac
done

if [ "${#domains[@]}" -eq 0 ]; then
  usage
  exit 1
fi

if [ -n "$warn_days" ] && ! [[ "$warn_days" =~ ^[0-9]+$ ]]; then
  echo "--warn-days must be a whole number of days, got: $warn_days" >&2
  exit 1
fi

unreachable=0
flagged=0

check_domain() {
  local domain="$1"
  local pem cert not_after expiry_epoch now_epoch days_left hostname_result
  local mismatch=0

  pem=$(echo | openssl s_client -connect "${domain}:443" -servername "$domain" 2>/dev/null \
    | openssl x509 2>/dev/null || true)

  if [ -z "$pem" ]; then
    echo "Could not retrieve a certificate for $domain — connection failed, no cert presented, or the host doesn't answer on 443." >&2
    unreachable=1
    return
  fi

  cert=$(printf '%s\n' "$pem" | openssl x509 -noout -dates -issuer -subject)
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

  # Read the verdict from -checkhost's output rather than its exit status. An
  # openssl without -checkhost gives no verdict at all, and the hostname check
  # is then skipped rather than reported as a mismatch.
  hostname_result=$(printf '%s\n' "$pem" | openssl x509 -noout -checkhost "$domain" 2>/dev/null || true)
  case "$hostname_result" in
    *"does NOT match"*)
      echo "Hostname $domain does NOT match this certificate"
      mismatch=1
      ;;
  esac

  if [ -n "$warn_days" ]; then
    if [ "$mismatch" -eq 1 ]; then
      flagged=1
    fi
    # -checkend exits non-zero when the certificate expires within the given
    # number of seconds — already-expired certificates included.
    if ! printf '%s\n' "$pem" | openssl x509 -noout -checkend $(( warn_days * 86400 )) >/dev/null; then
      echo "ALERT: expired or expires within $warn_days day(s)"
      flagged=1
    fi
  fi
}

multiple=0
if [ "${#domains[@]}" -gt 1 ]; then
  multiple=1
fi

for domain in "${domains[@]}"; do
  if [ "$multiple" -eq 1 ]; then
    echo "== $domain"
  fi
  check_domain "$domain"
  if [ "$multiple" -eq 1 ]; then
    echo
  fi
done

if [ "$unreachable" -eq 1 ]; then
  exit 1
fi

if [ "$flagged" -eq 1 ]; then
  exit 2
fi
