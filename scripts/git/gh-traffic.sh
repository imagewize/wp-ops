#!/bin/bash

# gh-traffic.sh - Fetch and display GitHub repository traffic statistics
# See --help for usage information
#
# Author: wp-ops
# Created: 2026-07-09

set -euo pipefail

# Default values
JSON_OUTPUT=false
QUIET=false
DAYS=14

# Help function
display_help() {
    cat <<'EOF'
gh-traffic.sh - Fetch and display GitHub repository traffic statistics

Fetches view and unique visitor data for a GitHub repository and displays
it in a formatted table. Uses GitHub's traffic API which retains 14 days of data.

Usage:
  ./gh-traffic.sh [options] owner/repo

Options:
  -h, --help            Show this help message and exit
  -d, --days N          Number of days to fetch (default: 14, max: 14)
  -j, --json            Output raw JSON instead of formatted table
  -q, --quiet           Suppress header row in table output

Arguments:
  owner/repo            GitHub repository in format owner/repo (required)

Examples:
  # Show traffic for a specific repository
  ./scripts/git/gh-traffic.sh imagewize/nynaeve

  # Show traffic without header row
  ./scripts/git/gh-traffic.sh imagewize/nynaeve --quiet

  # Output as JSON
  ./scripts/git/gh-traffic.sh imagewize/nynaeve --json

Requirements:
  - GitHub CLI (gh) installed and authenticated
  - jq for JSON processing (if using --json, optional otherwise)
  - column for table formatting (if not using --json)

Note:
  GitHub's traffic API only retains 14 days of data, so this will always
  show a maximum two-week window. For longer-term tracking, consider running
  this script periodically and appending results to a CSV file via cron.

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
        -d|--days)
            if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
                DAYS="$2"
                if [[ "$DAYS" -gt 14 ]]; then
                    echo "Error: Maximum days is 14 (GitHub API limit)" >&2
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
            REPO="$1"
            shift
            ;;
    esac
done

# Validate repository argument
if [[ -z "${REPO:-}" ]]; then
    echo "Error: Repository argument is required" >&2
    echo "Usage: $0 [options] owner/repo" >&2
    exit 1
fi

# Validate repository format (owner/repo)
if [[ ! "$REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid repository format. Use owner/repo (e.g., imagewize/nynaeve)" >&2
    exit 1
fi

# Check for required commands
if ! command -v gh &>/dev/null; then
    echo "Error: GitHub CLI (gh) is required but not installed" >&2
    exit 1
fi

if [[ "$JSON_OUTPUT" = false ]] && ! command -v column &>/dev/null; then
    echo "Error: column command is required for table output but not installed" >&2
    exit 1
fi

# Fetch traffic data from GitHub API
if [[ "$JSON_OUTPUT" = true ]]; then
    # Raw JSON output
    gh api "repos/$REPO/traffic/views"
else
    # Formatted table output
    if [[ "$QUIET" = false ]]; then
        echo -e "Date\tViews\tUnique"
    fi
    
    gh api "repos/$REPO/traffic/views" --jq \
        '.views[] | select(.count > 0) | [.timestamp[:10], (.count|tostring), (.uniques|tostring)] | @tsv' \
        | column -t
fi
