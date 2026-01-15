#!/bin/bash
#
# Traffic Monitor - Analyze legitimate traffic from Nginx logs
#
# Usage:
#   ./traffic-monitor.sh [log_file] [hours]
#
# Examples:
#   ./traffic-monitor.sh                                           # Default: example.com, last 24h
#   ./traffic-monitor.sh /srv/www/demo.example.com/logs/access.log 6  # Demo site, last 6 hours
#   ./traffic-monitor.sh /var/log/nginx/access.log 24             # Global logs, last 24 hours
#

set -e

# ============================================================================
# Configuration
# ============================================================================

# Default log file - adjust to your site:
# Per-site logs (Trellis default):
#   /srv/www/example.com/logs/access.log
#   /srv/www/demo.example.com/logs/access.log
# Global logs (if configured):
#   /var/log/nginx/access.log
LOG_FILE="${1:-/srv/www/example.com/logs/access.log}"
HOURS="${2:-24}"

# Bot patterns to exclude from traffic analysis
BOT_PATTERN='updown\.io|[Bb]ot|[Ss]pider|[Cc]rawl|Geedo|Semrush|DuckDuckBot|AhrefsBot|MJ12bot|SemrushBot|DataForSeoBot|YandexBot|facebookexternalhit|Googlebot|bingbot|PetalBot|BLEXBot'

# Static file extensions to exclude from page view analysis
STATIC_PATTERN='\.(css|js|jpg|jpeg|png|gif|ico|woff|woff2|svg|webp|avif|ttf|eot|map|txt|xml)($|\?)'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}==============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==============================================================================${NC}\n"
}

print_section() {
    echo -e "\n${CYAN}--- $1 ---${NC}\n"
}

check_log_file() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${RED}Error: Log file not found: $LOG_FILE${NC}" >&2
        exit 1
    fi
}

filter_recent_logs() {
    # Simple approach: estimate lines based on hours
    # Average website gets ~500-1000 requests/hour
    # For accuracy, we'll scan more than needed and rely on the report time grouping
    local estimated_lines=$((HOURS * 1000))

    # Limit to reasonable max
    [[ $estimated_lines -gt 50000 ]] && estimated_lines=50000

    # Use tail to get recent lines (much faster than filtering entire log)
    tail -n "$estimated_lines" "$LOG_FILE"
}

# ============================================================================
# Main Analysis
# ============================================================================

main() {
    check_log_file

    print_header "Nginx Traffic Analysis Report - Last ${HOURS} Hours"
    echo "Log file: $LOG_FILE"
    echo "Generated: $(date)"

    # Create temporary file for filtered logs
    TEMP_LOG=$(mktemp)
    trap 'rm -f "$TEMP_LOG"' EXIT

    # Get recent logs (estimated based on traffic volume)
    print_section "Analyzing recent traffic (last ~${HOURS} hours)..."
    filter_recent_logs > "$TEMP_LOG"

    local total_requests
    total_requests=$(wc -l < "$TEMP_LOG" | tr -d ' ')
    echo "Total requests in period: $total_requests"

    # Traffic without bots
    print_section "Non-Bot Traffic Summary"

    local real_traffic
    real_traffic=$(grep -vE "$BOT_PATTERN" "$TEMP_LOG" | wc -l | tr -d ' ')
    echo "Requests from real users: $real_traffic"

    local bot_traffic=$((total_requests - real_traffic))
    echo "Requests from bots/crawlers: $bot_traffic"

    # Unique visitors (by IP)
    print_section "Unique Visitors"

    local unique_ips
    unique_ips=$(grep -vE "$BOT_PATTERN" "$TEMP_LOG" | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
    echo "Unique IP addresses: $unique_ips"

    # Status code breakdown
    print_section "HTTP Status Codes"

    awk '{print $9}' "$TEMP_LOG" \
        | grep -E '^[0-9]{3}$' \
        | sort \
        | uniq -c \
        | sort -rn \
        | while read -r count code; do
            case ${code:0:1} in
                2) color=$GREEN ;;
                3) color=$CYAN ;;
                4) color=$YELLOW ;;
                5) color=$RED ;;
                *) color=$NC ;;
            esac
            printf "${color}%8d${NC}  %s\n" "$count" "$code"
        done

    # Top pages (excluding bots and static files)
    print_section "Top 10 Most Requested Pages"

    grep 'HTTP/1.[01]" 200' "$TEMP_LOG" \
        | grep -vE "$BOT_PATTERN" \
        | grep -vE "$STATIC_PATTERN" \
        | awk '{print $7}' \
        | cut -d'?' -f1 \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r count url; do
            printf "${GREEN}%8d${NC}  %s\n" "$count" "$url"
        done

    # Top IP addresses (excluding bots)
    print_section "Top 10 IP Addresses"

    grep -vE "$BOT_PATTERN" "$TEMP_LOG" \
        | awk '{print $1}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r count ip; do
            printf "${CYAN}%8d${NC}  %s\n" "$count" "$ip"
        done

    # Traffic by hour
    print_section "Traffic by Hour"

    awk '{print $4}' "$TEMP_LOG" \
        | cut -c 14-15 \
        | sort -n \
        | uniq -c \
        | while read -r count hour; do
            # Create simple bar chart
            local bar_length=$((count / 10))
            [[ $bar_length -lt 1 ]] && bar_length=1
            local bar
            bar=$(printf '%*s' "$bar_length" | tr ' ' '#')
            # Strip leading zero to avoid octal interpretation
            hour=$((10#$hour))
            printf "%02d:00  ${GREEN}%8d${NC}  %s\n" "$hour" "$count" "$bar"
        done

    # Top referrers (excluding empty and same-domain)
    print_section "Top 10 External Referrers"

    awk -F'"' '{print $4}' "$TEMP_LOG" \
        | grep -vE '^-$|^$' \
        | grep -v "$(hostname)" \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r count referrer; do
            printf "${MAGENTA}%8d${NC}  %s\n" "$count" "$referrer"
        done

    # Top user agents (excluding bots)
    print_section "Top 10 User Agents"

    awk -F'"' '{print $6}' "$TEMP_LOG" \
        | grep -vE "$BOT_PATTERN" \
        | grep -vE '^-$|^$' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r count agent; do
            printf "${CYAN}%8d${NC}  %s\n" "$count" "${agent:0:80}"
        done

    # Request methods
    print_section "HTTP Methods"

    awk '{print $6}' "$TEMP_LOG" \
        | tr -d '"' \
        | sort \
        | uniq -c \
        | sort -rn \
        | while read -r count method; do
            printf "${GREEN}%8d${NC}  %s\n" "$count" "$method"
        done

    # Bandwidth estimate (if bytes sent available)
    print_section "Bandwidth Summary"

    local total_bytes
    total_bytes=$(awk '{sum += $10} END {print sum}' "$TEMP_LOG")

    if [[ -n "$total_bytes" ]] && [[ "$total_bytes" -gt 0 ]]; then
        local mb=$((total_bytes / 1024 / 1024))
        local gb
        gb=$(echo "scale=2; $total_bytes / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
        echo "Total bytes sent: $total_bytes"
        echo "Megabytes: ${mb} MB"
        [[ "$gb" != "N/A" ]] && echo "Gigabytes: ${gb} GB"
    else
        echo "Bandwidth data not available in log format"
    fi

    print_header "Report Complete"
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
