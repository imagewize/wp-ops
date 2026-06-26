#!/bin/bash
#
# AI Bot Monitor - Analyze AI crawler traffic from Nginx logs
#
# Usage:
#   ./ai-bot-monitor.sh [log_file] [hours] [output_file]
#
# Examples:
#   ./ai-bot-monitor.sh                                                # Default: example.com, last 24h
#   ./ai-bot-monitor.sh /srv/www/demo.example.com/logs/access.log 6 # Demo site, last 6 hours
#   ./ai-bot-monitor.sh /srv/www/example.com/logs/access.log 168    # Last 7 days
#

set -e

# ============================================================================
# Configuration
# ============================================================================

LOG_FILE="${1:-/srv/www/example.com/logs/access.log}"
HOURS="${2:-24}"
OUTPUT_FILE="${3:-}"

# Operator IP ranges to flag separately in the report.
# Requests matching these IPs + an AI crawler UA are likely tool sessions
# (e.g. Claude Code fetching pages), not autonomous crawlers.
# Add Jakarta direct IPs, ProtonVPN Singapore exit nodes, etc.
# Supports partial prefix matching (e.g. "103.76." matches 103.76.x.x).
# Leave empty to disable: OPERATOR_IP_PATTERN=""
OPERATOR_IP_PATTERN=""

# Known Anthropic AWS CIDR ranges (for reference — not used for filtering,
# but useful to confirm ClaudeBot traffic is from Anthropic infrastructure).
# Source: observed server logs + AWS IP range data.
# Note: ClaudeBot UA + these IPs = could be either:
#   (a) Anthropic's autonomous training/indexing crawler, OR
#   (b) A user on claude.ai asking Claude to browse your site in real time.
# These are indistinguishable from IP + UA alone.
#
# ANTHROPIC_AWS_CIDRS=(
#   3.12.0.0/16   3.14.0.0/15   3.20.0.0/14   3.128.0.0/15
#   3.132.0.0/14  3.136.0.0/13  3.144.0.0/13  13.58.0.0/15
#   18.116.0.0/14 18.216.0.0/14 18.220.0.0/14 18.224.0.0/14
#   52.14.0.0/16
# )

# Known AI crawler user agent patterns and their display names.
# Format: "pattern|Display Name"
declare -a AI_BOTS=(
    "GPTBot|OpenAI GPTBot"
    "ChatGPT-User|OpenAI ChatGPT-User"
    "OAI-SearchBot|OpenAI SearchBot"
    "ClaudeBot|Anthropic ClaudeBot"
    "anthropic-ai|Anthropic anthropic-ai"
    "Google-Extended|Google-Extended (Gemini training)"
    "PerplexityBot|PerplexityBot"
    "MistralAI-User|Mistral MistralAI-User (live fetch)"
    "MistralAI-Index|Mistral MistralAI-Index (crawler)"
    "DeepSeekBot|DeepSeek DeepSeekBot"
    "CCBot|Common Crawl CCBot"
    "Bytespider|ByteDance Bytespider"
    "Amazonbot|Amazon Amazonbot"
    "cohere-ai|Cohere cohere-ai"
    "YouBot|You.com YouBot"
    "Diffbot|Diffbot"
    "meta-externalagent|Meta AI meta-externalagent"
    "Applebot-Extended|Apple Applebot-Extended"
    "ImagesiftBot|ImagesiftBot"
    "omgilibot|Omgili omgilibot"
    "AI2Bot|Allen AI AI2Bot"
    "iaskspider|iAsk.ai spider"
    "Kangaroo Bot|Kangaroo Bot"
)

# Combined pattern for matching any AI bot (used for aggregate queries)
AI_PATTERN='GPTBot|ChatGPT-User|OAI-SearchBot|ClaudeBot|anthropic-ai|Google-Extended|PerplexityBot|MistralAI-User|MistralAI-Index|DeepSeekBot|CCBot|Bytespider|Amazonbot|cohere-ai|YouBot|Diffbot|meta-externalagent|Applebot-Extended|ImagesiftBot|omgilibot|AI2Bot|iaskspider|Kangaroo Bot'

# Static file extensions to exclude from page analysis
STATIC_PATTERN='\.(css|js|jpg|jpeg|png|gif|ico|woff|woff2|svg|webp|avif|ttf|eot|map|txt|xml)($|\?)'

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

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
    local cutoff_epoch
    cutoff_epoch=$(date -d "${HOURS} hours ago" +%s)

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
# Main Analysis
# ============================================================================

main() {
    check_log_file

    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > >(tee "$OUTPUT_FILE")
    fi

    print_header "AI Crawler Traffic Report - Last ${HOURS} Hours"
    echo "Log file: $LOG_FILE"
    echo "Generated: $(date)"

    TEMP_LOG=$(mktemp)
    trap 'rm -f "$TEMP_LOG"' EXIT

    local since_label
    since_label=$(date -d "${HOURS} hours ago" '+%Y-%m-%d %H:%M UTC')
    print_section "Analyzing traffic since ${since_label} (last ${HOURS} hours)..."
    filter_recent_logs > "$TEMP_LOG"

    local total_requests
    total_requests=$(wc -l < "$TEMP_LOG" | tr -d ' ')
    echo "Total requests in period: $total_requests"

    # -----------------------------------------------------------------------
    # Overall AI bot summary
    # -----------------------------------------------------------------------
    print_section "AI Crawler Overview"

    local ai_requests
    ai_requests=$(grep -cE "$AI_PATTERN" "$TEMP_LOG" || true)
    local human_requests=$((total_requests - ai_requests))

    echo "Total AI crawler requests: $ai_requests"
    echo "Total non-AI requests:     $human_requests"

    if [[ "$total_requests" -gt 0 ]]; then
        local pct
        pct=$(awk "BEGIN {printf \"%.1f\", ($ai_requests / $total_requests) * 100}")
        echo "AI share of all traffic:   ${pct}%"
    fi

    # -----------------------------------------------------------------------
    # Breakdown by AI bot
    # -----------------------------------------------------------------------
    print_section "Requests by AI Crawler"

    printf "${YELLOW}%-10s  %-45s  %s${NC}\n" "Requests" "Crawler" "Bytes (est.)"

    for bot_entry in "${AI_BOTS[@]}"; do
        local pattern="${bot_entry%%|*}"
        local label="${bot_entry##*|}"

        local count
        count=$(grep -cE "$pattern" "$TEMP_LOG" || true)

        if [[ "$count" -gt 0 ]]; then
            local bytes
            bytes=$(grep -E "$pattern" "$TEMP_LOG" | awk '{sum += $10} END {printf "%d", sum+0}')
            local mb
            mb=$(awk "BEGIN {printf \"%.2f\", $bytes / 1024 / 1024}")
            printf "${RED}%10d${NC}  %-45s  %s MB\n" "$count" "$label" "$mb"
        fi
    done

    # -----------------------------------------------------------------------
    # Top pages scraped by AI bots
    # -----------------------------------------------------------------------
    print_section "Top 30 Pages Scraped by AI Crawlers"

    grep -E "$AI_PATTERN" "$TEMP_LOG" \
        | grep 'HTTP/1.[01]" 200' \
        | grep -vE "$STATIC_PATTERN" \
        | awk '{print $7}' \
        | cut -d'?' -f1 \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -30 \
        | while read -r count url; do
            printf "${GREEN}%8d${NC}  %s\n" "$count" "$url"
        done

    # -----------------------------------------------------------------------
    # Top pages per major bot
    # -----------------------------------------------------------------------
    print_section "Top 10 Pages per Major AI Crawler"

    for bot_entry in "GPTBot|OpenAI GPTBot" "ClaudeBot|Anthropic ClaudeBot" "CCBot|Common Crawl" "PerplexityBot|PerplexityBot" "Google-Extended|Google-Extended" "Bytespider|ByteDance Bytespider"; do
        local pattern="${bot_entry%%|*}"
        local label="${bot_entry##*|}"

        local count
        count=$(grep -cE "$pattern" "$TEMP_LOG" || true)
        [[ "$count" -eq 0 ]] && continue

        echo -e "${YELLOW}${label} (${count} total requests):${NC}"
        grep -E "$pattern" "$TEMP_LOG" \
            | grep 'HTTP/1.[01]" 200' \
            | grep -vE "$STATIC_PATTERN" \
            | awk '{print $7}' \
            | cut -d'?' -f1 \
            | sort \
            | uniq -c \
            | sort -rn \
            | head -10 \
            | while read -r c url; do
                printf "  ${GREEN}%6d${NC}  %s\n" "$c" "$url"
            done
        echo ""
    done

    # -----------------------------------------------------------------------
    # AI traffic by hour
    # -----------------------------------------------------------------------
    print_section "AI Crawler Traffic by Hour"

    grep -E "$AI_PATTERN" "$TEMP_LOG" \
        | awk '{print $4}' \
        | cut -c 14-15 \
        | sort -n \
        | uniq -c \
        | while read -r count hour; do
            local bar_length=$((count / 5))
            [[ $bar_length -lt 1 ]] && bar_length=1
            local bar
            bar=$(printf '%*s' "$bar_length" | tr ' ' '#')
            hour=$((10#$hour))
            printf "%02d:00  ${RED}%8d${NC}  %s\n" "$hour" "$count" "$bar"
        done

    # -----------------------------------------------------------------------
    # HTTP status codes for AI bots
    # -----------------------------------------------------------------------
    print_section "HTTP Status Codes Returned to AI Crawlers"

    grep -E "$AI_PATTERN" "$TEMP_LOG" \
        | awk '{print $9}' \
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

    # -----------------------------------------------------------------------
    # Bandwidth consumed by AI bots
    # -----------------------------------------------------------------------
    print_section "Bandwidth Consumed by AI Crawlers"

    local ai_bytes
    ai_bytes=$(grep -E "$AI_PATTERN" "$TEMP_LOG" | awk '{sum += $10} END {print sum+0}')

    if [[ "$ai_bytes" -gt 0 ]]; then
        local ai_mb=$((ai_bytes / 1024 / 1024))
        local ai_gb
        ai_gb=$(awk "BEGIN {printf \"%.3f\", $ai_bytes / 1024 / 1024 / 1024}")
        echo "Total bytes served to AI crawlers: $ai_bytes"
        echo "Megabytes: ${ai_mb} MB"
        echo "Gigabytes: ${ai_gb} GB"

        local total_bytes
        total_bytes=$(awk '{sum += $10} END {print sum+0}' "$TEMP_LOG")
        if [[ "$total_bytes" -gt 0 ]]; then
            local bw_pct
            bw_pct=$(awk "BEGIN {printf \"%.1f\", ($ai_bytes / $total_bytes) * 100}")
            echo "AI share of total bandwidth: ${bw_pct}%"
        fi
    else
        echo "Bandwidth data not available in log format"
    fi

    # -----------------------------------------------------------------------
    # IP addresses used by AI crawlers
    # -----------------------------------------------------------------------
    print_section "Top 10 IP Addresses Used by AI Crawlers"

    grep -E "$AI_PATTERN" "$TEMP_LOG" \
        | awk '{print $1}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r count ip; do
            printf "${CYAN}%8d${NC}  %s\n" "$count" "$ip"
        done

    # -----------------------------------------------------------------------
    # Operator IP cross-check (flag AI requests from known operator ranges)
    # -----------------------------------------------------------------------
    if [[ -n "$OPERATOR_IP_PATTERN" ]]; then
        print_section "Operator IP Cross-Check"
        echo "Checking for AI crawler UA requests originating from operator IP ranges..."
        echo "(Matches may indicate tool sessions, not autonomous crawlers)"
        echo ""

        local op_hits
        op_hits=$(grep -E "$AI_PATTERN" "$TEMP_LOG" \
            | awk '{print $1, $0}' \
            | grep -E "$OPERATOR_IP_PATTERN" \
            | wc -l | tr -d ' ')

        if [[ "$op_hits" -gt 0 ]]; then
            echo -e "${YELLOW}Found ${op_hits} AI crawler request(s) from operator IP ranges:${NC}"
            echo ""
            grep -E "$AI_PATTERN" "$TEMP_LOG" \
                | awk '{print $1, $0}' \
                | grep -E "$OPERATOR_IP_PATTERN" \
                | awk '{print $1}' \
                | sort | uniq -c | sort -rn \
                | while read -r count ip; do
                    printf "${YELLOW}%8d${NC}  %s\n" "$count" "$ip"
                done
        else
            echo -e "${GREEN}No AI crawler requests from known operator IP ranges.${NC}"
            echo "All AI traffic appears to be autonomous crawlers."
        fi
    fi

    # -----------------------------------------------------------------------
    # Robots.txt hits from AI bots (did they check before crawling?)
    # -----------------------------------------------------------------------
    print_section "Robots.txt Compliance Check"

    local robots_hits
    robots_hits=$(grep -E "$AI_PATTERN" "$TEMP_LOG" | grep -c '/robots.txt' || true)
    local non_robots_hits=$((ai_requests - robots_hits))

    echo "AI requests to /robots.txt: $robots_hits"
    echo "AI requests bypassing robots.txt check: $non_robots_hits"

    if [[ "$robots_hits" -eq 0 ]] && [[ "$ai_requests" -gt 0 ]]; then
        echo -e "${YELLOW}Warning: No robots.txt requests detected — crawlers may be ignoring it${NC}"
    fi

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
