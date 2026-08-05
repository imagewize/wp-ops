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
# @desc     Analyze legitimate traffic from an Nginx access log
# @category monitoring
# @platform trellis
# @runs     server
# @requires gawk
# @arg      log_file     optional  {/srv/www/example.com/logs/access.log}  Nginx access log path
# @arg      hours        optional  {24}  How many hours back to analyze
# @arg      output_file  optional  Path to save the report instead of printing it
# @example  ssh web@example.com 'bash -s' < traffic-monitor.sh
# @example  ssh web@example.com 'bash -s' < traffic-monitor.sh /srv/www/demo.example.com/logs/access.log 6
# @doc      trellis/monitoring/README.md

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
OUTPUT_FILE="${3:-}"  # Optional: path to save report

# Bot patterns to exclude from traffic analysis
BOT_PATTERN='updown\.io|[Bb]ot|[Ss]pider|[Cc]rawl|Geedo|Semrush|DuckDuckBot|AhrefsBot|MJ12bot|SemrushBot|DataForSeoBot|YandexBot|facebookexternalhit|Googlebot|bingbot|PetalBot|BLEXBot'

# Static file extensions to exclude from page view analysis
STATIC_PATTERN='\.(css|js|jpg|jpeg|png|gif|ico|woff|woff2|svg|webp|avif|ttf|eot|map|txt|xml)($|\?)'

# SEO-relevant bot patterns
SEO_BOTS='Googlebot|bingbot|Baiduspider|YandexBot|DuckDuckBot|Slurp'

# Admin and API paths to exclude from page view analysis
ADMIN_PATTERN='^/wp/wp-login\.php|^/wp/wp-admin/|^/wp-json/|^/xmlrpc\.php|^/wp-cron\.php'

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
    # Calculate exact cutoff epoch (N hours ago) using GNU date (Linux/Ubuntu)
    local cutoff_epoch
    cutoff_epoch=$(date -d "${HOURS} hours ago" +%s)

    # Parse nginx combined log timestamps and filter by actual time.
    # Requires gawk (Ubuntu ships mawk by default: apt install gawk); falls back to tail estimate if missing.
    # Nginx timestamp format: [DD/Mon/YYYY:HH:MM:SS +ZONE]
    if command -v gawk &>/dev/null; then
        gawk -v cutoff="$cutoff_epoch" '
        BEGIN {
            split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m)
            for (i = 1; i <= 12; i++) month[m[i]] = i
        }
        {
            if (match($0, /\[([0-9]{2})\/([A-Za-z]{3})\/([0-9]{4}):([0-9]{2}):([0-9]{2}):([0-9]{2})/, a)) {
                ts = mktime(a[3] " " month[a[2]] " " (a[1]+0) " " (a[4]+0) " " (a[5]+0) " " (a[6]+0))
                if (ts >= cutoff) print
            }
        }' "$LOG_FILE"
    else
        echo "Warning: gawk not found, falling back to line-based estimate" >&2
        local estimated_lines=$((HOURS * 1000))
        [[ $estimated_lines -gt 50000 ]] && estimated_lines=50000
        tail -n "$estimated_lines" "$LOG_FILE"
    fi
}

# ============================================================================
# SEO Analysis Functions
# ============================================================================

analyze_404_errors() {
    print_section "404 Errors - Broken Links & SEO Issues"

    local results
    results=$(grep 'HTTP/1.[01]" 404' "$TEMP_LOG" \
        | grep -vE "$BOT_PATTERN" \
        | awk '{print $7}' \
        | cut -d'?' -f1 \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -20)

    if [[ -z "$results" ]]; then
        echo "No 404 errors detected from real users"
        return
    fi

    echo "$results" | while read -r count url; do
        printf "${YELLOW}%8d${NC}  %s\n" "$count" "$url"
    done

    echo ""
    echo -e "${CYAN}Action:${NC} Create redirects for high-traffic 404s or restore missing content"
}

analyze_search_crawlers() {
    print_section "Search Engine Crawler Activity"

    local crawler_results
    crawler_results=$(grep -E "$SEO_BOTS" "$TEMP_LOG" \
        | awk -F'"' '{print $6}' \
        | sed 's/\/.*//' \
        | sort \
        | uniq -c \
        | sort -rn)

    if [[ -z "$crawler_results" ]]; then
        echo "No search engine crawler activity detected"
        return
    fi

    echo "$crawler_results" | while read -r count bot; do
        printf "${GREEN}%8d${NC}  %s\n" "$count" "$bot"
    done

    # What pages are crawlers indexing?
    echo ""
    echo "Most crawled pages:"
    grep -E "$SEO_BOTS" "$TEMP_LOG" \
        | awk '{print $7}' \
        | cut -d'?' -f1 \
        | grep -vE "$STATIC_PATTERN" \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r count url; do
            printf "${CYAN}%8d${NC}  %s\n" "$count" "$url"
        done
}

analyze_device_types() {
    print_section "Device Type Analysis (Mobile-First Indexing)"

    # Mobile patterns
    local mobile_count
    mobile_count=$(awk -F'"' '{print $6}' "$TEMP_LOG" \
        | grep -vE "$BOT_PATTERN" \
        | grep -iE 'Mobile|Android|iPhone|iPad|iPod' \
        | wc -l | tr -d ' ')

    # Desktop patterns
    local desktop_count
    desktop_count=$(awk -F'"' '{print $6}' "$TEMP_LOG" \
        | grep -vE "$BOT_PATTERN" \
        | grep -viE 'Mobile|Android|iPhone|iPad|iPod' \
        | grep -vE '^-$|^$' \
        | wc -l | tr -d ' ')

    local total=$((mobile_count + desktop_count))

    if [[ $total -eq 0 ]]; then
        echo "No device data available"
        return
    fi

    local mobile_pct=$((mobile_count * 100 / total))
    local desktop_pct=$((100 - mobile_pct))

    echo -e "Mobile traffic:  ${GREEN}${mobile_count}${NC} (${mobile_pct}%)"
    echo -e "Desktop traffic: ${CYAN}${desktop_count}${NC} (${desktop_pct}%)"

    echo ""
    if [[ $mobile_pct -gt 60 ]]; then
        echo -e "${GREEN}✓${NC} Mobile-first indexing priority confirmed"
    elif [[ $mobile_pct -gt 40 ]]; then
        echo -e "${YELLOW}!${NC} Balanced mobile/desktop traffic - ensure responsive design"
    else
        echo -e "${CYAN}i${NC} Desktop-heavy traffic - verify mobile experience"
    fi
}

analyze_organic_search() {
    print_section "Organic Search Traffic Sources"

    local search_results
    search_results=$(awk -F'"' '{print $4}' "$TEMP_LOG" \
        | grep -iE 'google\.com|bing\.com|yahoo\.com|duckduckgo\.com|baidu\.com|yandex\.' \
        | grep -vE '(\.php|/config/|//|/\.)' \
        | sed 's/\?.*//' \
        | sort \
        | uniq -c \
        | sort -rn)

    if [[ -z "$search_results" ]]; then
        echo "No organic search referrals detected"
        return
    fi

    echo "$search_results" | while read -r count referrer; do
        printf "${GREEN}%8d${NC}  %s\n" "$count" "$referrer"
    done
}

analyze_landing_pages() {
    print_section "Top Landing Pages (External Traffic)"

    # Get domain from log file path for better filtering
    local site_domain
    site_domain=$(echo "$LOG_FILE" | grep -oE '[^/]+\.com' | head -1 || echo "")

    local landing_results
    landing_results=$(awk -F'"' '$4 !~ /^-$/ && $4 !~ /localhost/ {print $0}' "$TEMP_LOG" \
        | awk -F'"' '$4 !~ /'"${site_domain}"'/ {print $0}' \
        | awk '{print $7}' \
        | cut -d'?' -f1 \
        | grep -vE "$STATIC_PATTERN" \
        | grep -vE '(wp-login|wp-admin|wp-plain|xmlrpc\.php|/db\.php|\.env|\.git|\.yml|\.config|\.dockerenv|alfacgiapi|ALFA_DATA|/config/|//\.|yahoo_mail|googlemail|\.ebextensions|seotheme|timthumb|/app/etc/|[a-z]{8}\.php$)' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10)

    if [[ -z "$landing_results" ]]; then
        echo "No external landing page data available"
        return
    fi

    echo "$landing_results" | while read -r count url; do
        printf "${MAGENTA}%8d${NC}  %s\n" "$count" "$url"
    done
}

analyze_social_traffic() {
    print_section "Social Media Traffic"

    # Get domain from log file path for better filtering
    local site_domain
    site_domain=$(echo "$LOG_FILE" | grep -oE '[^/]+\.com' | head -1 || echo "")

    local social_results
    social_results=$(awk -F'"' '{print $4}' "$TEMP_LOG" \
        | grep -iE 'facebook\.com|twitter\.com|linkedin\.com|instagram\.com|pinterest\.com|reddit\.com|youtube\.com|t\.co|x\.com' \
        | grep -viE "${site_domain}|\.ebextensions|\.env|\.config" \
        | sed 's/\?.*//' \
        | sort \
        | uniq -c \
        | sort -rn)

    if [[ -z "$social_results" ]]; then
        echo "No social media referrals detected"
        return
    fi

    echo "$social_results" | while read -r count referrer; do
        printf "${MAGENTA}%8d${NC}  %s\n" "$count" "$referrer"
    done
}

analyze_redirects() {
    print_section "Redirects (301/302) - SEO Impact"

    local redirect_results
    redirect_results=$(grep 'HTTP/1.[01]" 30[12]' "$TEMP_LOG" \
        | awk '{print $7, $9}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -20)

    if [[ -z "$redirect_results" ]]; then
        echo "No redirects detected"
        return
    fi

    echo "$redirect_results" | while read -r count url code; do
        local color=$CYAN
        [[ "$code" == "301" ]] && color=$GREEN
        printf "%8d  ${color}%s${NC}  %s\n" "$count" "$code" "$url"
    done

    echo ""
    echo -e "${CYAN}Note:${NC} 301 = Permanent (passes SEO value), 302 = Temporary (doesn't pass full SEO value)"
}

analyze_url_depth() {
    print_section "URL Depth Analysis (Site Structure)"

    grep -vE "$BOT_PATTERN" "$TEMP_LOG" \
        | awk '{print $7}' \
        | grep -vE "$STATIC_PATTERN" \
        | awk '{
            depth = gsub(/\//, "/", $0)
            counts[depth]++
        }
        END {
            for (d in counts) {
                printf "%d %d\n", d, counts[d]
            }
        }' \
        | sort -n \
        | while read -r depth count; do
            local level_name="Root"
            case $depth in
                1) level_name="Root (/)" ;;
                2) level_name="Level 1 (/page/)" ;;
                3) level_name="Level 2 (/category/page/)" ;;
                4) level_name="Level 3 (/cat/subcat/page/)" ;;
                *) level_name="Level $((depth - 1))" ;;
            esac
            printf "${CYAN}%8d${NC}  %s\n" "$count" "$level_name"
        done

    echo ""
    echo -e "${CYAN}Best Practice:${NC} Keep important content within 3 clicks (depth ≤ 3) for better crawling"
}

# ============================================================================
# Main Analysis
# ============================================================================

main() {
    check_log_file

    # Setup output redirection if output file specified
    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > >(tee "$OUTPUT_FILE")
    fi

    print_header "Nginx Traffic Analysis Report - Last ${HOURS} Hours"
    echo "Log file: $LOG_FILE"
    echo "Generated: $(date)"

    # Create temporary file for filtered logs
    TEMP_LOG=$(mktemp)
    trap 'rm -f "$TEMP_LOG"' EXIT

    # Filter logs by actual timestamp
    local since_label
    since_label=$(date -d "${HOURS} hours ago" '+%Y-%m-%d %H:%M UTC')
    print_section "Analyzing traffic since ${since_label} (last ${HOURS} hours)..."
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
    print_section "Top 50 Most Requested Pages"

    grep 'HTTP/1.[01]" 200' "$TEMP_LOG" \
        | grep -vE "$BOT_PATTERN" \
        | grep -vE "$STATIC_PATTERN" \
        | awk '{print $7}' \
        | cut -d'?' -f1 \
        | grep -vE "$ADMIN_PATTERN" \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -50 \
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

    # SEO-focused analysis sections
    print_header "SEO & Content Analysis"

    analyze_404_errors
    analyze_search_crawlers
    analyze_device_types
    analyze_organic_search
    analyze_landing_pages
    analyze_social_traffic
    analyze_redirects
    analyze_url_depth

    print_header "Report Complete"

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo ""
        echo "Report saved to: $OUTPUT_FILE"
    fi
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
