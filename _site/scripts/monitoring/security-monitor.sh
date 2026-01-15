#!/bin/bash
#
# Security Monitor - Detect malicious activity in Nginx logs
#
# Usage:
#   ./security-monitor.sh [log_file] [hours] [alert_threshold]
#
# Examples:
#   ./security-monitor.sh                                                # Default: example.com, last 24h
#   ./security-monitor.sh /srv/www/demo.example.com/logs/access.log 1 50     # Demo site, 1 hour, alert > 50
#   ./security-monitor.sh /var/log/nginx/access.log 24 100                     # Global logs, 24h, alert > 100
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
ALERT_THRESHOLD="${3:-100}"  # Alert if single IP exceeds this many requests

# WordPress attack patterns
WP_LOGIN_PATTERN='wp-login\.php'
WP_ADMIN_PATTERN='wp-admin'
XMLRPC_PATTERN='xmlrpc\.php'

# Security threat patterns
SQL_INJECTION_PATTERN='(union.*select|concat\(|script>|javascript:|<script|SELECT.*FROM|INSERT.*INTO)'
DIRECTORY_TRAVERSAL_PATTERN='(\.\./|%2e%2e|%252e|\.\.\\)'
NULL_BYTE_PATTERN='%00'
SHELL_INJECTION_PATTERN='(;.*ls|;.*cat|;.*wget|;.*curl|`.*`|\$\(.*\))'

# File scanning patterns
SCAN_PATTERNS='(\.env|\.git|\.svn|wp-config\.php|phpinfo|eval\(|base64_decode|\.bak|\.sql|\.zip|\.tar\.gz)'

# Suspicious user agent patterns
SUSPICIOUS_UA_PATTERN='(sqlmap|nikto|nmap|masscan|nessus|openvas|acunetix|^-$|^$)'

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
    echo -e "\n${RED}==============================================================================${NC}"
    echo -e "${RED}$1${NC}"
    echo -e "${RED}==============================================================================${NC}\n"
}

print_section() {
    echo -e "\n${YELLOW}--- $1 ---${NC}\n"
}

print_alert() {
    echo -e "${RED}[ALERT]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
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
# Security Checks
# ============================================================================

check_brute_force() {
    print_section "Brute Force Detection (wp-login.php)"

    local results
    results=$(grep -iE "$WP_LOGIN_PATTERN" "$TEMP_LOG" \
        | awk '{print $1}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -20)

    if [[ -z "$results" ]]; then
        print_info "No wp-login.php access detected"
        return
    fi

    echo "$results" | while read -r count ip; do
        if [[ $count -gt 10 ]]; then
            print_alert "IP $ip attempted wp-login.php ${count} times"
            echo -e "  ${RED}→${NC} Consider blocking this IP"
        else
            printf "${YELLOW}%8d${NC}  %s\n" "$count" "$ip"
        fi
    done
}

check_xmlrpc_abuse() {
    print_section "XML-RPC Abuse Detection"

    local results
    results=$(grep -iE "$XMLRPC_PATTERN" "$TEMP_LOG" \
        | awk '{print $1, $9}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -20)

    if [[ -z "$results" ]]; then
        print_info "No xmlrpc.php access detected"
        return
    fi

    echo "$results" | while read -r count ip status; do
        if [[ $count -gt 5 ]]; then
            print_alert "IP $ip hit xmlrpc.php ${count} times (status: $status)"
            echo -e "  ${RED}→${NC} Potential pingback/trackback spam or brute force"
        else
            printf "${YELLOW}%8d${NC}  %s (status: %s)\n" "$count" "$ip" "$status"
        fi
    done
}

check_high_request_ips() {
    print_section "High Request Volume IPs (Potential DoS/Scrapers)"

    awk '{print $1}' "$TEMP_LOG" \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -20 \
        | while read -r count ip; do
            if [[ $count -gt $ALERT_THRESHOLD ]]; then
                print_alert "IP $ip made ${count} requests (threshold: ${ALERT_THRESHOLD})"

                # Show what they're requesting
                local sample
                sample=$(grep "^$ip " "$TEMP_LOG" | awk '{print $7}' | head -5 | tr '\n' ' ')
                echo -e "  ${CYAN}Sample URLs:${NC} ${sample:0:100}..."
            else
                printf "${YELLOW}%8d${NC}  %s\n" "$count" "$ip"
            fi
        done
}

check_404_scanners() {
    print_section "404 Scanners (Directory/File Enumeration)"

    grep 'HTTP/1.[01]" 404' "$TEMP_LOG" \
        | awk '{print $1}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -15 \
        | while read -r count ip; do
            if [[ $count -gt 20 ]]; then
                print_warning "IP $ip generated ${count} 404 errors"

                # Show what they're scanning for
                local sample
                sample=$(grep "^$ip " "$TEMP_LOG" | grep ' 404 ' | awk '{print $7}' | head -3 | tr '\n' ' ')
                echo -e "  ${CYAN}Looking for:${NC} ${sample:0:100}..."
            else
                printf "${YELLOW}%8d${NC}  %s\n" "$count" "$ip"
            fi
        done
}

check_sql_injection() {
    print_section "SQL Injection Attempts"

    local results
    results=$(grep -iE "$SQL_INJECTION_PATTERN" "$TEMP_LOG" | head -20)

    if [[ -z "$results" ]]; then
        print_info "No SQL injection patterns detected"
        return
    fi

    echo "$results" | while IFS= read -r line; do
        local ip
        ip=$(echo "$line" | awk '{print $1}')
        local request
        request=$(echo "$line" | awk '{print $7}' | cut -c 1-100)
        print_alert "SQL injection attempt from $ip"
        echo -e "  ${CYAN}Request:${NC} $request"
    done
}

check_directory_traversal() {
    print_section "Directory Traversal Attempts"

    local results
    results=$(grep -iE "$DIRECTORY_TRAVERSAL_PATTERN" "$TEMP_LOG" | head -20)

    if [[ -z "$results" ]]; then
        print_info "No directory traversal patterns detected"
        return
    fi

    echo "$results" | while IFS= read -r line; do
        local ip
        ip=$(echo "$line" | awk '{print $1}')
        local request
        request=$(echo "$line" | awk '{print $7}' | cut -c 1-100)
        print_alert "Directory traversal attempt from $ip"
        echo -e "  ${CYAN}Request:${NC} $request"
    done
}

check_shell_injection() {
    print_section "Shell Injection Attempts"

    local results
    results=$(grep -iE "$SHELL_INJECTION_PATTERN" "$TEMP_LOG" | head -20)

    if [[ -z "$results" ]]; then
        print_info "No shell injection patterns detected"
        return
    fi

    echo "$results" | while IFS= read -r line; do
        local ip
        ip=$(echo "$line" | awk '{print $1}')
        local request
        request=$(echo "$line" | awk '{print $7}' | cut -c 1-100)
        print_alert "Shell injection attempt from $ip"
        echo -e "  ${CYAN}Request:${NC} $request"
    done
}

check_sensitive_files() {
    print_section "Sensitive File Access Attempts"

    local results
    results=$(grep -iE "$SCAN_PATTERNS" "$TEMP_LOG" | head -30)

    if [[ -z "$results" ]]; then
        print_info "No sensitive file access attempts detected"
        return
    fi

    echo "$results" | while IFS= read -r line; do
        local ip
        ip=$(echo "$line" | awk '{print $1}')
        local status
        status=$(echo "$line" | awk '{print $9}')
        local request
        request=$(echo "$line" | awk '{print $7}' | cut -c 1-80)

        if [[ "$status" == "200" ]]; then
            print_alert "SUCCESSFUL access to sensitive file from $ip (status: $status)"
        else
            print_warning "Attempted access to sensitive file from $ip (status: $status)"
        fi
        echo -e "  ${CYAN}Request:${NC} $request"
    done
}

check_suspicious_user_agents() {
    print_section "Suspicious User Agents"

    local results
    results=$(grep -iE "$SUSPICIOUS_UA_PATTERN" "$TEMP_LOG" \
        | awk -F'"' '{print $6}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -15)

    if [[ -z "$results" ]]; then
        print_info "No suspicious user agents detected"
        return
    fi

    echo "$results" | while read -r count agent; do
        print_warning "Suspicious user agent detected (${count} requests)"
        echo -e "  ${CYAN}Agent:${NC} ${agent:0:100}"
    done
}

check_empty_user_agents() {
    print_section "Empty/Missing User Agents"

    local count
    count=$(awk -F'"' '$6 == "" || $6 == "-"' "$TEMP_LOG" | wc -l | tr -d ' ')

    if [[ $count -eq 0 ]]; then
        print_info "No requests with empty user agents"
        return
    fi

    print_warning "Found ${count} requests with empty/missing user agent"

    # Show IPs with empty user agents
    awk -F'"' '$6 == "" || $6 == "-" {print $1}' "$TEMP_LOG" \
        | awk '{print $1}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | head -10 \
        | while read -r req_count ip; do
            printf "${YELLOW}%8d${NC}  %s\n" "$req_count" "$ip"
        done
}

check_post_requests() {
    print_section "POST Request Analysis"

    local total_posts
    total_posts=$(grep '"POST ' "$TEMP_LOG" | wc -l | tr -d ' ')

    echo "Total POST requests: $total_posts"

    # POST to non-standard endpoints (excluding wp-admin, wp-login, xmlrpc)
    local suspicious_posts
    suspicious_posts=$(grep '"POST ' "$TEMP_LOG" \
        | grep -vE 'wp-admin|wp-login|xmlrpc|wp-cron|admin-ajax' \
        | head -20)

    if [[ -n "$suspicious_posts" ]]; then
        echo ""
        print_warning "POST requests to unusual endpoints:"
        echo "$suspicious_posts" | while IFS= read -r line; do
            local ip
            ip=$(echo "$line" | awk '{print $1}')
            local request
            request=$(echo "$line" | awk '{print $7}' | cut -c 1-60)
            local status
            status=$(echo "$line" | awk '{print $9}')
            printf "  %s → ${CYAN}%s${NC} (status: %s)\n" "$ip" "$request" "$status"
        done
    fi
}

check_server_errors() {
    print_section "5xx Server Errors (Potential Attack Impact)"

    local error_count
    error_count=$(grep 'HTTP/1.[01]" 5[0-9][0-9]' "$TEMP_LOG" | wc -l | tr -d ' ')

    if [[ $error_count -eq 0 ]]; then
        print_info "No 5xx server errors detected"
        return
    fi

    print_warning "Found ${error_count} server errors (5xx)"

    # Group by status code
    grep 'HTTP/1.[01]" 5[0-9][0-9]' "$TEMP_LOG" \
        | awk '{print $9}' \
        | sort \
        | uniq -c \
        | sort -rn \
        | while read -r count code; do
            printf "${RED}%8d${NC}  HTTP %s\n" "$count" "$code"
        done

    echo ""
    echo "Recent 5xx errors:"
    grep 'HTTP/1.[01]" 5[0-9][0-9]' "$TEMP_LOG" \
        | tail -10 \
        | while IFS= read -r line; do
            local ip
            ip=$(echo "$line" | awk '{print $1}')
            local request
            request=$(echo "$line" | awk '{print $7}' | cut -c 1-50)
            local status
            status=$(echo "$line" | awk '{print $9}')
            printf "  %s → ${CYAN}%s${NC} (status: ${RED}%s${NC})\n" "$ip" "$request" "$status"
        done
}

# ============================================================================
# Reporting
# ============================================================================

generate_block_recommendations() {
    print_section "IP Block Recommendations"

    # Aggregate all malicious IPs
    local malicious_ips
    malicious_ips=$(mktemp)
    trap 'rm -f "$malicious_ips"' EXIT

    # High request volume
    awk '{print $1}' "$TEMP_LOG" \
        | sort \
        | uniq -c \
        | sort -rn \
        | awk -v threshold="$ALERT_THRESHOLD" '$1 > threshold {print $2}' \
        >> "$malicious_ips"

    # Brute force attempts
    grep -iE "$WP_LOGIN_PATTERN" "$TEMP_LOG" \
        | awk '{print $1}' \
        | sort \
        | uniq -c \
        | awk '$1 > 10 {print $2}' \
        >> "$malicious_ips"

    # Multiple 404s
    grep 'HTTP/1.[01]" 404' "$TEMP_LOG" \
        | awk '{print $1}' \
        | sort \
        | uniq -c \
        | awk '$1 > 20 {print $2}' \
        >> "$malicious_ips"

    # SQL injection attempts
    grep -iE "$SQL_INJECTION_PATTERN" "$TEMP_LOG" \
        | awk '{print $1}' \
        >> "$malicious_ips"

    # Unique malicious IPs
    local unique_ips
    unique_ips=$(sort -u "$malicious_ips")

    if [[ -z "$unique_ips" ]]; then
        print_info "No IPs recommended for blocking"
        return
    fi

    echo -e "${RED}Consider blocking these IPs:${NC}\n"
    echo "$unique_ips" | while read -r ip; do
        echo "deny $ip;"
    done

    echo ""
    echo -e "${CYAN}To block in Trellis:${NC}"
    echo "1. Create roles/wordpress-setup/templates/deny-ips.conf.j2"
    echo "2. Add the deny statements above"
    echo "3. Add to wordpress_sites YAML: nginx_includes: deny-ips.conf"
    echo "4. Run: trellis provision production"
}

# ============================================================================
# Main Analysis
# ============================================================================

main() {
    check_log_file

    print_header "Nginx Security Analysis Report - Last ${HOURS} Hours"
    echo "Log file: $LOG_FILE"
    echo "Alert threshold: $ALERT_THRESHOLD requests per IP"
    echo "Generated: $(date)"

    # Create temporary file for filtered logs
    TEMP_LOG=$(mktemp)
    trap 'rm -f "$TEMP_LOG"' EXIT

    # Filter logs by time period
    filter_recent_logs > "$TEMP_LOG"

    local total_requests
    total_requests=$(wc -l < "$TEMP_LOG" | tr -d ' ')
    echo "Total requests in period: $total_requests"

    # Run security checks
    check_high_request_ips
    check_brute_force
    check_xmlrpc_abuse
    check_404_scanners
    check_sql_injection
    check_directory_traversal
    check_shell_injection
    check_sensitive_files
    check_suspicious_user_agents
    check_empty_user_agents
    check_post_requests
    check_server_errors
    generate_block_recommendations

    print_header "Security Scan Complete"
    echo "Review alerts above and take appropriate action."
    echo ""
    echo "Recommended next steps:"
    echo "1. Block malicious IPs using Nginx deny rules"
    echo "2. Consider installing fail2ban for automatic blocking"
    echo "3. Check error logs: tail -50 /var/log/nginx/error.log"
    echo "4. Review successful attacks (200 status on sensitive files)"
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
