#!/bin/bash
#
# updown.io Webhook Handler
#
# This script can be called by updown.io webhooks to trigger log analysis
# when downtime is detected
#
# Setup:
# 1. Make this script executable and place on your server
# 2. Setup webhook in updown.io to POST to your endpoint
# 3. Use a simple webhook receiver (PHP, Node.js, etc.) to call this script
#
# Usage:
#   ./updown-webhook-handler.sh <site_url> <event_type>
#
# Example:
#   ./updown-webhook-handler.sh example.com down
#

set -e

# ============================================================================
# Configuration
# ============================================================================

SITE="${1:-example.com}"
EVENT="${2:-down}"

# Log file paths - set these according to your Trellis configuration:
# For per-site logs: LOG_FILE="/srv/www/${SITE}/logs/access.log"
# For global logs: LOG_FILE="/var/log/nginx/access.log"
LOG_FILE="${LOG_FILE:-/srv/www/${SITE}/logs/access.log}"
ERROR_LOG="${ERROR_LOG:-/srv/www/${SITE}/logs/error.log}"

MONITORING_DIR="/home/web/monitoring"
REPORTS_DIR="/home/web/monitoring/updown-alerts"
ALERT_EMAIL="${ALERT_EMAIL:-}"

# ============================================================================
# Functions
# ============================================================================

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

create_reports_dir() {
    mkdir -p "$REPORTS_DIR"
}

# ============================================================================
# Event Handlers
# ============================================================================

handle_downtime() {
    log_message "Downtime detected for $SITE - analyzing logs..."

    local timestamp
    timestamp=$(date '+%Y-%m-%d-%H%M%S')
    local report_file="$REPORTS_DIR/downtime-$timestamp.txt"

    {
        echo "================================================================================"
        echo "DOWNTIME ALERT: $SITE"
        echo "Time: $(date)"
        echo "================================================================================"
        echo ""

        echo "--- Recent Server Errors (5xx) ---"
        grep 'HTTP/1.[01]" 5[0-9][0-9]' "$LOG_FILE" | tail -20 || echo "No 5xx errors found"
        echo ""

        echo "--- Recent Nginx Error Log ---"
        tail -30 "$ERROR_LOG" || echo "Cannot read error log"
        echo ""

        echo "--- Recent High Request IPs (last hour) ---"
        "$MONITORING_DIR/traffic-monitor.sh" "$LOG_FILE" 1 | grep -A 10 "Top 10 IP Addresses" || echo "Cannot run traffic analysis"
        echo ""

        echo "--- Security Issues (last hour) ---"
        "$MONITORING_DIR/security-monitor.sh" "$LOG_FILE" 1 100 | grep -E "\[ALERT\]|\[WARNING\]" || echo "No security alerts"
        echo ""

        echo "--- System Resources ---"
        echo "Disk usage:"
        df -h / || echo "Cannot check disk"
        echo ""
        echo "Memory:"
        free -h || echo "Cannot check memory"
        echo ""

        echo "--- Active Connections ---"
        ss -tn | grep -E ':80|:443' | wc -l || echo "Cannot check connections"
        echo ""

        echo "================================================================================"
        echo "Analysis complete. Check above for root cause."
        echo "================================================================================"
    } > "$report_file"

    # Display to stdout
    cat "$report_file"

    # Send email if configured
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &> /dev/null; then
        mail -s "[DOWNTIME] $SITE - $(date +%Y-%m-%d\ %H:%M)" "$ALERT_EMAIL" < "$report_file"
        log_message "Alert email sent to $ALERT_EMAIL"
    fi

    log_message "Downtime analysis saved to $report_file"
}

handle_uptime_restored() {
    log_message "Uptime restored for $SITE"

    local timestamp
    timestamp=$(date '+%Y-%m-%d-%H%M%S')
    local report_file="$REPORTS_DIR/recovery-$timestamp.txt"

    {
        echo "================================================================================"
        echo "UPTIME RESTORED: $SITE"
        echo "Time: $(date)"
        echo "================================================================================"
        echo ""

        echo "Site is back online. Recent activity:"
        echo ""

        echo "--- Recent Successful Requests ---"
        grep 'HTTP/1.[01]" 200' "$LOG_FILE" | tail -10 || echo "No 200 responses yet"
        echo ""

        echo "================================================================================"
    } > "$report_file"

    cat "$report_file"

    log_message "Recovery logged to $report_file"
}

handle_ssl_expiry() {
    log_message "SSL certificate expiry warning for $SITE"

    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &> /dev/null; then
        echo "SSL certificate for $SITE is expiring soon. Check updown.io for details." \
            | mail -s "[SSL WARNING] $SITE Certificate Expiring" "$ALERT_EMAIL"
    fi
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    create_reports_dir

    case "$EVENT" in
        down|downtime)
            handle_downtime
            ;;
        up|uptime)
            handle_uptime_restored
            ;;
        ssl)
            handle_ssl_expiry
            ;;
        *)
            log_message "Unknown event type: $EVENT"
            exit 1
            ;;
    esac
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
