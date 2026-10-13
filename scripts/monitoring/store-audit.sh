#!/bin/bash
# store-audit.sh - Audit a store's public URL with Min and gate on the result
# Usage: bash store-audit.sh [--fail-under GRADE] [--fail-on CHECK[,CHECK...]]
#                            [--speed] [--no-product] [--json] [--endpoint URL] <url>
#
# Calls Min's hosted MCP server (the imagewize/min WordPress plugin with
# wordpress/mcp-adapter): audit-store, then audit-product (which includes the
# price/stock truth check), optionally audit-speed. Min scans the *public* URL,
# so this needs no SSH and runs from CI right after a deploy. It is the same
# engine and the same tool chain the wp-ops MCP server's store_audit tool uses.
#
# Without a gate flag it only reports. With one it becomes a deploy gate:
#   --fail-under B        exit 2 when the grade is worse than B (C, D or F)
#   --fail-on a,b         exit 2 when any named check has status fail or warn
#                         (ids as in the report, e.g. truth_check,ai_crawler_access)
#
# Credentials (an application password for a WordPress user allowed to run audits):
#   WP_OPS_MIN_MCP_USER      WordPress login
#   WP_OPS_MIN_MCP_PASSWORD  application password (spaces are fine)
#   WP_OPS_MIN_MCP_URL       optional, default https://imagewize.com/wp-json/min/mcp
# Each run counts against that user's daily scan limit and stores a lead record on
# the Min site. When GITHUB_STEP_SUMMARY is set the result is appended to it.
#
# Exit codes:
#   0  audit completed; no gate flag, or every gate passed
#   1  bad usage, missing credentials, or the audit could not be completed
#   2  a gate failed (grade under the threshold, or a --fail-on check failing)
#
# @desc     Audit a store's public URL with Min (AI-shopping readiness, truth check) and optionally gate on grade or checks
# @category monitoring
# @platform any
# @runs     local
# @mutates  false
# @requires curl,jq
# @arg      url  required  {https://shop.example.com}  Public store URL to audit
# @flag     --fail-under  optional  {B}  Exit 2 when the grade is worse than this (A-F)
# @flag     --fail-on     optional  {truth_check,ai_crawler_access}  Exit 2 when any of these checks has status fail or warn
# @flag     --speed       optional  {}  Also run PageSpeed (slow, up to a minute)
# @flag     --no-product  optional  {}  Skip the product-page checks, including the truth check
# @flag     --json        optional  {}  Print the condensed result as JSON only
# @flag     --endpoint    optional  {https://imagewize.com/wp-json/min/mcp}  Min MCP endpoint (default: WP_OPS_MIN_MCP_URL or imagewize.com)
# @example  wp-ops store-audit https://shop.example.com
# @example  wp-ops store-audit --fail-under B --fail-on truth_check https://shop.example.com

set -euo pipefail

DEFAULT_ENDPOINT="https://imagewize.com/wp-json/min/mcp"
GRADES="ABCDF"

usage() {
  cat >&2 <<'EOF'
Usage: store-audit.sh [--fail-under GRADE] [--fail-on CHECK[,CHECK...]]
                      [--speed] [--no-product] [--json] [--endpoint URL] <url>
Example: store-audit.sh --fail-under B --fail-on truth_check https://shop.example.com
Needs WP_OPS_MIN_MCP_USER and WP_OPS_MIN_MCP_PASSWORD (an application password).
EOF
}

die() {
  echo "store-audit: $*" >&2
  exit 1
}

fail_under=""
fail_on=""
want_speed=0
want_product=1
json_only=0
endpoint="${WP_OPS_MIN_MCP_URL:-$DEFAULT_ENDPOINT}"
url=""

while [ $# -gt 0 ]; do
  case "$1" in
    --fail-under)
      [ $# -ge 2 ] || { usage; die "--fail-under needs a grade (A-F)"; }
      fail_under="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
      shift 2
      ;;
    --fail-on)
      [ $# -ge 2 ] || { usage; die "--fail-on needs a comma-separated list of check ids"; }
      fail_on="$2"
      shift 2
      ;;
    --endpoint)
      [ $# -ge 2 ] || { usage; die "--endpoint needs a URL"; }
      endpoint="$2"
      shift 2
      ;;
    --speed) want_speed=1; shift ;;
    --no-product) want_product=0; shift ;;
    --json) json_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; die "unknown option: $1" ;;
    *)
      [ -z "$url" ] || { usage; die "only one URL at a time"; }
      url="$1"
      shift
      ;;
  esac
done

[ -n "$url" ] || { usage; exit 1; }
case "$url" in http://*|https://*) ;; *) die "URL must start with http:// or https://" ;; esac
if [ -n "$fail_under" ]; then
  case "$fail_under" in [ABCDF]) ;; *) die "--fail-under must be one of A B C D F" ;; esac
fi

command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required"
[ -n "${WP_OPS_MIN_MCP_USER:-}" ] && [ -n "${WP_OPS_MIN_MCP_PASSWORD:-}" ] ||
  die "set WP_OPS_MIN_MCP_USER and WP_OPS_MIN_MCP_PASSWORD (an application password)"

# The password never goes on a command line: the auth header lives in a 0600 file
# curl reads with -H @file, removed on exit.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"
umask 077
printf 'Authorization: Basic %s\n' \
  "$(printf '%s:%s' "$WP_OPS_MIN_MCP_USER" "$WP_OPS_MIN_MCP_PASSWORD" | base64 | tr -d '\n')" >"$tmp/auth"

session=""
rpc_id=0

# POST one JSON-RPC message; the body (JSON, or the data: lines of an SSE reply) goes
# to stdout. The first call stores the Mcp-Session-Id the server issues.
post() {
  local body="$1" max_time="${2:-60}" status
  local -a headers=(-H @"$tmp/auth" -H 'Content-Type: application/json'
    -H 'Accept: application/json, text/event-stream' -H 'MCP-Protocol-Version: 2025-06-18')
  [ -z "$session" ] || headers+=(-H "Mcp-Session-Id: $session")
  status="$(curl -sS --max-time "$max_time" -D "$tmp/resp.headers" -o "$tmp/resp.body" \
    -w '%{http_code}' -X POST "${headers[@]}" --data "$body" "$endpoint")" ||
    die "could not reach $endpoint"
  case "$status" in
    2*) ;;
    401|403) die "Min MCP rejected the credentials (HTTP $status)" ;;
    *) die "Min MCP returned HTTP $status" ;;
  esac
  if [ -z "$session" ]; then
    session="$(awk 'tolower($1)=="mcp-session-id:" {gsub("\r",""); print $2}' "$tmp/resp.headers")"
  fi
  if grep -q '^data:' "$tmp/resp.body" 2>/dev/null; then
    sed -n 's/^data: *//p' "$tmp/resp.body"
  else
    cat "$tmp/resp.body"
  fi
}

call_tool() {
  local name="$1" max_time="$2" reply
  rpc_id=$((rpc_id + 1))
  reply="$(post "$(jq -nc --argjson id "$rpc_id" --arg n "$name" --arg u "$url" \
    '{jsonrpc:"2.0",id:$id,method:"tools/call",params:{name:$n,arguments:{url:$u}}}')" "$max_time")"
  # JSON-RPC error, or a tool result flagged isError: report the message and stop.
  if printf '%s' "$reply" | jq -e '.error' >/dev/null 2>&1; then
    die "$name: $(printf '%s' "$reply" | jq -r '.error.message')"
  fi
  if [ "$(printf '%s' "$reply" | jq -r '.result.isError // false')" = "true" ]; then
    die "$name: $(printf '%s' "$reply" | jq -r '[.result.content[]?.text] | join(" ")')"
  fi
  # structuredContent when the server provides it, else the JSON in the text block.
  printf '%s' "$reply" | jq -c 'if .result.structuredContent then .result.structuredContent
    else (.result.content[0].text | fromjson) end' 2>/dev/null ||
    die "$name: unreadable tool result"
}

post '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"wp-ops store-audit","version":"1.0"}}}' 30 >/dev/null
[ -n "$session" ] || die "the server did not issue an MCP session (is this a Min MCP endpoint?)"
post '{"jsonrpc":"2.0","method":"notifications/initialized"}' 30 >/dev/null || true

[ "$json_only" -eq 1 ] || echo "Auditing $url ..." >&2
store="$(call_tool min-audit-store 120)"
product="null"
speed="null"
if [ "$want_product" -eq 1 ]; then
  [ "$json_only" -eq 1 ] || echo "  product-page checks ..." >&2
  product="$(call_tool min-audit-product 120)"
fi
if [ "$want_speed" -eq 1 ]; then
  [ "$json_only" -eq 1 ] || echo "  PageSpeed (can take a minute) ..." >&2
  speed="$(call_tool min-audit-speed 180)"
fi

# The product step returns the refreshed report, so its grade supersedes the first.
result="$(jq -nc --arg url "$url" --argjson store "$store" --argjson product "$product" --argjson speed "$speed" '
  ($product // $store) as $r
  | {
      url: $url,
      grade: ($r.aeo.grade // null),
      score: ($r.aeo.score // null),
      top_issue: ($r.aeo.top_issue // null),
      service: ($r.service_match // null),
      comparison: ($r.comparison.message.en // null),
      product_found: ($r.meta.product_found // null),
      speed: (if $speed then {grade: ($speed.performance.grade // null), score: ($speed.performance.score // null)} else null end),
      failing: [($r.aeo.checks // {}) | to_entries[] | select(.value.status == "fail" or .value.status == "warn")
                | {id: .key, status: .value.status, evidence: (.value.evidence // "")}]
                | sort_by(if .status == "fail" then 0 else 1 end),
      actions: [($r.actions // [])[] | {check, status, service, en}]
    }')"

# ── Gates ────────────────────────────────────────────────────────────────────
grade="$(jq -r '.grade // empty' <<<"$result")"
reasons=()

if [ -n "$fail_under" ]; then
  if [ -z "$grade" ]; then
    reasons+=("no grade was returned, so --fail-under $fail_under cannot pass")
  else
    prefix_g="${GRADES%%"$grade"*}"
    prefix_t="${GRADES%%"$fail_under"*}"
    # Position in A..F: a longer prefix means a worse grade.
    if [ "${#prefix_g}" -gt "${#prefix_t}" ]; then
      reasons+=("grade $grade is worse than the required $fail_under")
    fi
  fi
fi

if [ -n "$fail_on" ]; then
  IFS=',' read -r -a wanted <<<"$fail_on"
  for id in "${wanted[@]}"; do
    id="$(printf '%s' "$id" | tr -d '[:space:]')"
    [ -n "$id" ] || continue
    hit="$(jq -r --arg id "$id" '.failing[] | select(.id == $id) | "\(.status): \(.evidence)"' <<<"$result")"
    [ -z "$hit" ] || reasons+=("$id is $hit")
  done
fi

gate_failed=0
[ "${#reasons[@]}" -eq 0 ] || gate_failed=1

# ── Output ───────────────────────────────────────────────────────────────────
if [ "$json_only" -eq 1 ]; then
  jq --argjson failed "$gate_failed" --argjson reasons "$(printf '%s\n' "${reasons[@]:-}" | jq -R . | jq -sc 'map(select(. != ""))')" \
    '. + {gate_failed: ($failed == 1), gate_reasons: $reasons}' <<<"$result"
else
  jq -r '
    "Store audit for \(.url): grade \(.grade // "?") (\(.score // "?")/100)",
    (.comparison // empty),
    (if .speed then "Speed (PageSpeed): \(.speed.grade // "?") (\(.speed.score // "?"))" else empty end),
    "",
    (if (.failing | length) == 0 then "No failing or warning checks."
     else "Failing / warning checks:", (.failing[] | "  \(if .status == "fail" then "FAIL" else "warn" end)  \(.id): \(.evidence)") end),
    (if (.actions | length) > 0 then "", "Recommended fixes:", (.actions[] | "  - [\(.service)] \(.en)") else empty end)
  ' <<<"$result"
  if [ "$gate_failed" -eq 1 ]; then
    echo
    echo "GATE FAILED:"
    printf '  - %s\n' "${reasons[@]}"
  fi
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    jq -r '"## Store audit: \(.url)\n\n**Grade \(.grade // "?")** (\(.score // "?")/100)\n"' <<<"$result"
    if [ "$gate_failed" -eq 1 ]; then
      echo "**Gate failed**"
      printf -- '- %s\n' "${reasons[@]}"
      echo
    fi
    jq -r 'if (.failing | length) == 0 then "No failing or warning checks."
      else "| Check | Status | Evidence |\n|---|---|---|", (.failing[] | "| `\(.id)` | \(.status) | \(.evidence | gsub("\\|"; "/")) |") end' <<<"$result"
  } >>"$GITHUB_STEP_SUMMARY"
fi

[ "$gate_failed" -eq 0 ] || exit 2
exit 0
