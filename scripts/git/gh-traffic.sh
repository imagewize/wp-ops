#!/bin/bash

# gh-traffic.sh - Fetch and display GitHub repository traffic statistics
# See --help for usage information
#
# Author: wp-ops
# Created: 2026-07-09
#
# @desc     Fetch and display GitHub repo traffic: views, clones, and referrers (14-day window)
# @category git
# @platform any
# @runs     local
# @requires gh jq
# @arg      owner/repo  required  {imagewize/nynaeve}  GitHub repository (repeatable)
# @flag     --clones     optional  {}  Include clone counts (machine traffic: CI, mirrors, bots)
# @flag     --referrers  optional  {}  Include top referring sites
# @flag     --all        optional  {}  Include every section (views, clones, referrers)
# @flag     --days       optional  {14}  Limit the day-series sections to the last N days (max: 14)
# @flag     --json       optional  {}  Output raw JSON instead of formatted tables
# @flag     --quiet      optional  {}  Suppress header rows in table output
# @example  wp-ops gh-traffic imagewize/nynaeve --quiet
# @example  wp-ops gh-traffic imagewize/nynaeve imagewize/wp-ops --all

set -euo pipefail

# Default values
JSON_OUTPUT=false
QUIET=false
DAYS=14
SHOW_VIEWS=false
SHOW_CLONES=false
SHOW_REFERRERS=false
REPOS=()

# Help function
display_help() {
    cat <<'EOF'
gh-traffic.sh - Fetch and display GitHub repository traffic statistics

Fetches view, clone, and referrer data for one or more GitHub repositories and
displays each as a formatted table. Uses GitHub's traffic API, which retains 14
days of data.

Usage:
  ./gh-traffic.sh [options] owner/repo [owner/repo ...]

Options:
  -h, --help            Show this help message and exit
  -c, --clones          Include clone counts alongside views
  -r, --referrers       Include the top referring sites
  -a, --all             Include every section (views, clones, referrers)
  -d, --days N          Limit day-series sections to the last N days (default: 14, max: 14)
  -j, --json            Output raw JSON instead of formatted tables
  -q, --quiet           Suppress header rows in table output

Arguments:
  owner/repo            GitHub repository in format owner/repo (required, repeatable)

Sections:
  With no section flag, only views are shown — the same default this script has
  always had. --clones, --referrers, and --all opt into the rest.

Examples:
  # Views only (default)
  ./scripts/git/gh-traffic.sh imagewize/nynaeve

  # Everything, for several repos in one pass
  ./scripts/git/gh-traffic.sh --all imagewize/nynaeve imagewize/wp-ops

  # Views and clones for the last 7 days
  ./scripts/git/gh-traffic.sh --clones --days 7 imagewize/nynaeve

  # Machine-readable output
  ./scripts/git/gh-traffic.sh --all --json imagewize/nynaeve

Requirements:
  - GitHub CLI (gh) installed and authenticated
  - jq for JSON processing
  - Push access to each repository (GitHub restricts traffic data to maintainers)
  - column for table formatting (if not using --json)

Reading the numbers:
  Views count page loads by humans; clones count `git clone`, which is dominated
  by CI runners, mirrors, and package resolvers rather than people. A repo with 3
  unique viewers and 200 unique cloners is being fetched by automation, not read.

Note:
  GitHub's traffic API only retains 14 days of data, so this will always show a
  maximum two-week window. Referrer data has no day series — it is always the
  full 14-day window, so --days does not apply to it. For longer-term tracking,
  run this periodically and append results to a CSV via cron.

Author: wp-ops
Created: 2026-07-09
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            ;;
        -c|--clones)
            SHOW_CLONES=true
            shift
            ;;
        -r|--referrers)
            SHOW_REFERRERS=true
            shift
            ;;
        -a|--all)
            SHOW_VIEWS=true
            SHOW_CLONES=true
            SHOW_REFERRERS=true
            shift
            ;;
        -d|--days)
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                DAYS="$2"
                if [[ "$DAYS" -gt 14 ]]; then
                    echo "Error: Maximum days is 14 (GitHub API limit)" >&2
                    exit 1
                fi
                if [[ "$DAYS" -lt 1 ]]; then
                    echo "Error: --days must be at least 1" >&2
                    exit 1
                fi
                shift 2
            else
                echo "Error: --days requires a numeric argument" >&2
                exit 1
            fi
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
        *)
            REPOS+=("$1")
            shift
            ;;
    esac
done

# Views are the default section, but only when nothing else was asked for —
# `--clones` alone means clones alone, the same way `--all` means all three.
if [[ "$SHOW_CLONES" = false && "$SHOW_REFERRERS" = false ]]; then
    SHOW_VIEWS=true
fi

# Validate repository arguments
if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "Error: At least one repository argument is required" >&2
    echo "Usage: $0 [options] owner/repo [owner/repo ...]" >&2
    exit 1
fi

for repo in "${REPOS[@]}"; do
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        echo "Error: Invalid repository format '$repo'. Use owner/repo (e.g., imagewize/nynaeve)" >&2
        exit 1
    fi
done

# Check for required commands
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is required but not installed" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

if [[ "$JSON_OUTPUT" = false ]] && ! command -v column &>/dev/null; then
    echo "Error: column command is required for table output but not installed" >&2
    exit 1
fi

# The traffic endpoints are maintainer-only, so a 403 here means "you don't have
# push access to this repo" far more often than it means anything is broken.
# Reporting that plainly beats letting gh's raw HTTP error surface.
# Tracks whether any repo/section failed, so a partial run still exits nonzero
# — the tables for the repos that did work are worth printing, but a caller
# scripting this needs to know the picture is incomplete.
FAILED=false

# Captures rather than streams, because `gh api` writes the API's JSON error
# body to stdout on a 4xx as well — passing that straight through would emit a
# second JSON value into --json output and corrupt the document.
fetch_traffic() {
    local repo="$1" endpoint="$2" body="" status=0
    body=$(gh api "repos/${repo}/traffic/${endpoint}" 2>/dev/null) || status=$?
    if [[ $status -ne 0 ]]; then
        echo "Error: could not fetch ${endpoint} for ${repo} — the traffic API needs push access to the repo, and the repo must exist." >&2
        FAILED=true
        return 1
    fi
    printf '%s' "$body"
}

# JSON counterpart to fetch_traffic: a section that can't be fetched becomes an
# explicit null rather than an empty slot, which would make the document
# unparseable for every other repo in the same run.
fetch_traffic_json() {
    if ! fetch_traffic "$1" "$2"; then
        printf 'null'
    fi
}

# Renders one day-series section (views or clones). GitHub's series carries one
# object per day with a zero-filled tail, so `tail -n` over the non-zero rows is
# what --days actually means here.
#
# The totals need care: the API's top-level `uniques` is deduplicated across the
# whole 14-day window, so it is NOT the sum of the daily uniques (one person
# visiting on three days counts once there, three times in the column). Summing
# it would silently overcount, so the two are printed as separate labelled rows
# rather than folded into one "Total".
print_series() {
    local endpoint="$1" label="$2" payload="$3"

    local rows
    rows=$(printf '%s' "$payload" | jq -r \
        ".${endpoint}[] | select(.count > 0) | [.timestamp[:10], (.count|tostring), (.uniques|tostring)] | @tsv")
    # GitHub returns the series oldest-first with a zero-filled tail, so the
    # last N non-zero rows are what "--days N" means.
    if [[ -n "$rows" ]]; then
        rows=$(printf '%s\n' "$rows" | tail -n "$DAYS")
    fi

    local total_count window_uniques
    total_count=$(printf '%s\n' "$rows" | awk -F'\t' '{s += $2} END {print s + 0}')
    window_uniques=$(printf '%s' "$payload" | jq -r '.uniques')

    echo "${label} (last ${DAYS} day(s) with activity)"
    {
        if [[ "$QUIET" = false ]]; then
            printf 'Date\t%s\tUnique\n' "$label"
        fi
        if [[ -n "$rows" ]]; then
            printf '%s\n' "$rows"
        fi
        printf 'Total\t%s\t-\n' "$total_count"
        printf 'Unique (14d)\t-\t%s\n' "$window_uniques"
    } | column -t -s $'\t'
    echo
}

print_referrers() {
    local payload="$1"
    local rows
    rows=$(printf '%s' "$payload" | jq -r '.[] | [.referrer, (.count|tostring), (.uniques|tostring)] | @tsv')

    echo "Referrers (top 10, 14-day window)"
    {
        if [[ "$QUIET" = false ]]; then
            printf 'Source\tViews\tUnique\n'
        fi
        if [[ -n "$rows" ]]; then
            printf '%s\n' "$rows"
        else
            printf '(none)\t-\t-\n'
        fi
    } | column -t -s $'\t'
    echo
}

if [[ "$JSON_OUTPUT" = true ]]; then
    # One object per repo, carrying only the requested sections. Emitted as a
    # JSON array so multi-repo output stays parseable as a single document.
    echo "["
    first=true
    for repo in "${REPOS[@]}"; do
        [[ "$first" = true ]] || echo ","
        first=false
        echo "  {"
        printf '    "repo": "%s"' "$repo"
        if [[ "$SHOW_VIEWS" = true ]]; then
            printf ',\n    "views": '
            fetch_traffic_json "$repo" "views"
        fi
        if [[ "$SHOW_CLONES" = true ]]; then
            printf ',\n    "clones": '
            fetch_traffic_json "$repo" "clones"
        fi
        if [[ "$SHOW_REFERRERS" = true ]]; then
            printf ',\n    "referrers": '
            fetch_traffic_json "$repo" "popular/referrers"
        fi
        printf '\n  }'
    done
    echo
    echo "]"
    [[ "$FAILED" = true ]] && exit 1
    exit 0
fi

for repo in "${REPOS[@]}"; do
    echo "=== ${repo} ==="
    echo

    # Two things going on here:
    #
    #   - `if payload=$(...)` rather than `payload=$(...) && ...`, because under
    #     `set -e` the latter aborts the whole run when one repo is unreadable,
    #     and a 403 on one repo shouldn't stop the other five from reporting.
    #   - the explicit `else FAILED=true`, because command substitution runs
    #     fetch_traffic in a subshell, so the FAILED it sets there is discarded.
    #     (The --json path calls fetch_traffic_json directly, no subshell, so
    #     the assignment inside fetch_traffic does survive for that one.)
    if [[ "$SHOW_VIEWS" = true ]]; then
        if payload=$(fetch_traffic "$repo" "views"); then
            print_series "views" "Views" "$payload"
        else FAILED=true; fi
    fi
    if [[ "$SHOW_CLONES" = true ]]; then
        if payload=$(fetch_traffic "$repo" "clones"); then
            print_series "clones" "Clones" "$payload"
        else FAILED=true; fi
    fi
    if [[ "$SHOW_REFERRERS" = true ]]; then
        if payload=$(fetch_traffic "$repo" "popular/referrers"); then
            print_referrers "$payload"
        else FAILED=true; fi
    fi
done

[[ "$FAILED" = true ]] && exit 1
exit 0
