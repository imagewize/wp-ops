#!/bin/bash
#
# Run Monitoring - Combined traffic, security, and AI bot monitoring
#
# This script runs traffic-monitor.sh, security-monitor.sh, and ai-bot-monitor.sh
# and saves timestamped reports to an output directory.
#
# Usage:
#   ssh web@example.com 'bash -s' < ./run-monitoring.sh [hours]
#   ./run-monitoring.sh 24              # Run locally on production server
#
# Examples:
#   # From local machine (recommended):
#   ssh web@example.com 'bash -s' < scripts/monitoring/run-monitoring.sh
#
#   # On production server:
#   cd /srv/www/example.com/current
#   ./run-monitoring.sh 24
#

set -e

# ============================================================================
# Configuration
# ============================================================================

HOURS="${1:-24}"
LOG_FILE="/srv/www/example.com/logs/access.log"
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
DATESTAMP=$(date +"%Y-%m-%d")

# Output directory (adjust based on execution context)
if [[ -d "/srv/www/example.com" ]]; then
    # Running on production server
    OUTPUT_DIR="${HOME}/monitoring"
    mkdir -p "$OUTPUT_DIR"
else
    # Running locally or from different context
    OUTPUT_DIR="./monitoring-reports"
    mkdir -p "$OUTPUT_DIR"
fi

TRAFFIC_REPORT="${OUTPUT_DIR}/traffic-monitor-${TIMESTAMP}.txt"
SECURITY_REPORT="${OUTPUT_DIR}/security-monitor-${TIMESTAMP}.txt"
AI_BOT_REPORT="${OUTPUT_DIR}/ai-bot-monitor-${TIMESTAMP}.txt"
SUMMARY_REPORT="${OUTPUT_DIR}/monitoring-summary-${DATESTAMP}.md"

# Colors for output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Helper Functions
# ============================================================================

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_info "Starting monitoring analysis for last ${HOURS} hours..."
    echo ""

    # Check if log file exists
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Error: Log file not found: $LOG_FILE" >&2
        exit 1
    fi

    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Run traffic monitor
    print_info "Running traffic analysis..."
    if [[ -f "${SCRIPT_DIR}/traffic-monitor.sh" ]]; then
        bash "${SCRIPT_DIR}/traffic-monitor.sh" "$LOG_FILE" "$HOURS" "$TRAFFIC_REPORT"
        print_success "Traffic report saved: $TRAFFIC_REPORT"
    else
        echo "Warning: traffic-monitor.sh not found in ${SCRIPT_DIR}"
    fi

    echo ""

    # Run security monitor
    print_info "Running security analysis..."
    if [[ -f "${SCRIPT_DIR}/security-monitor.sh" ]]; then
        bash "${SCRIPT_DIR}/security-monitor.sh" "$LOG_FILE" "$HOURS" 100 "$SECURITY_REPORT"
        print_success "Security report saved: $SECURITY_REPORT"
    else
        echo "Warning: security-monitor.sh not found in ${SCRIPT_DIR}"
    fi

    echo ""

    # Run AI bot monitor
    print_info "Running AI crawler analysis..."
    if [[ -f "${SCRIPT_DIR}/ai-bot-monitor.sh" ]]; then
        bash "${SCRIPT_DIR}/ai-bot-monitor.sh" "$LOG_FILE" "$HOURS" "$AI_BOT_REPORT"
        print_success "AI bot report saved: $AI_BOT_REPORT"
    else
        echo "Warning: ai-bot-monitor.sh not found in ${SCRIPT_DIR}"
    fi

    echo ""

    # Generate summary report
    print_info "Generating markdown summary..."
    generate_summary

    print_success "All monitoring reports generated successfully!"
    echo ""
    echo "Reports saved to:"
    echo "  - Traffic:  $TRAFFIC_REPORT"
    echo "  - Security: $SECURITY_REPORT"
    echo "  - AI Bots:  $AI_BOT_REPORT"
    echo "  - Summary:  $SUMMARY_REPORT"
}

# ============================================================================
# Summary Report Generator
# ============================================================================

generate_summary() {
    cat > "$SUMMARY_REPORT" <<EOF
# Monitoring Summary Report

**Generated:** $(date)
**Period:** Last ${HOURS} hours
**Log File:** ${LOG_FILE}

## Quick Stats

EOF

    # Extract key metrics from traffic report if it exists
    if [[ -f "$TRAFFIC_REPORT" ]]; then
        echo "### Traffic Overview" >> "$SUMMARY_REPORT"
        echo "" >> "$SUMMARY_REPORT"

        # Total requests
        total_requests=$(grep "Total requests in period:" "$TRAFFIC_REPORT" | awk '{print $NF}')
        echo "- **Total Requests:** ${total_requests}" >> "$SUMMARY_REPORT"

        # Real user traffic
        real_traffic=$(grep "Requests from real users:" "$TRAFFIC_REPORT" | awk '{print $NF}')
        echo "- **Real User Requests:** ${real_traffic}" >> "$SUMMARY_REPORT"

        # Unique visitors
        unique_ips=$(grep "Unique IP addresses:" "$TRAFFIC_REPORT" | awk '{print $NF}')
        echo "- **Unique Visitors:** ${unique_ips}" >> "$SUMMARY_REPORT"

        # Bandwidth
        bandwidth_mb=$(grep "Megabytes:" "$TRAFFIC_REPORT" | awk '{print $2, $3}')
        echo "- **Bandwidth:** ${bandwidth_mb}" >> "$SUMMARY_REPORT"

        echo "" >> "$SUMMARY_REPORT"
    fi

    # Extract security alerts from security report if it exists
    if [[ -f "$SECURITY_REPORT" ]]; then
        echo "### Security Overview" >> "$SUMMARY_REPORT"
        echo "" >> "$SUMMARY_REPORT"

        # Count alerts and warnings
        alert_count=$(grep -c "\[ALERT\]" "$SECURITY_REPORT" || echo "0")
        warning_count=$(grep -c "\[WARNING\]" "$SECURITY_REPORT" || echo "0")

        echo "- **Security Alerts:** ${alert_count}" >> "$SUMMARY_REPORT"
        echo "- **Warnings:** ${warning_count}" >> "$SUMMARY_REPORT"

        echo "" >> "$SUMMARY_REPORT"

        # Add top security concerns if any
        if [[ $alert_count -gt 0 ]]; then
            echo "### Top Security Concerns" >> "$SUMMARY_REPORT"
            echo "" >> "$SUMMARY_REPORT"
            echo '```' >> "$SUMMARY_REPORT"
            grep "\[ALERT\]" "$SECURITY_REPORT" | head -10 >> "$SUMMARY_REPORT"
            echo '```' >> "$SUMMARY_REPORT"
            echo "" >> "$SUMMARY_REPORT"
        fi
    fi

    cat >> "$SUMMARY_REPORT" <<EOF
## Report Files

- [Traffic Analysis Report]($(basename "$TRAFFIC_REPORT"))
- [Security Analysis Report]($(basename "$SECURITY_REPORT"))
- [AI Crawler Report]($(basename "$AI_BOT_REPORT"))

## SEO Traffic Insights

EOF

    # Extract AI bot stats
    if [[ -f "$AI_BOT_REPORT" ]]; then
        echo "### AI Crawler Overview" >> "$SUMMARY_REPORT"
        echo "" >> "$SUMMARY_REPORT"

        ai_requests=$(grep "Total AI crawler requests:" "$AI_BOT_REPORT" | awk '{print $NF}')
        ai_share=$(grep "AI share of all traffic:" "$AI_BOT_REPORT" | awk '{print $NF}')
        ai_bw=$(grep "AI share of total bandwidth:" "$AI_BOT_REPORT" | awk '{print $NF}')

        echo "- **AI Crawler Requests:** ${ai_requests}" >> "$SUMMARY_REPORT"
        echo "- **AI Share of Traffic:** ${ai_share}" >> "$SUMMARY_REPORT"
        echo "- **AI Share of Bandwidth:** ${ai_bw}" >> "$SUMMARY_REPORT"
        echo "" >> "$SUMMARY_REPORT"
    fi

    # Extract top pages from traffic report for SEO analysis
    if [[ -f "$TRAFFIC_REPORT" ]]; then
        echo "### Most Requested Pages (Real Users)" >> "$SUMMARY_REPORT"
        echo "" >> "$SUMMARY_REPORT"
        echo '```' >> "$SUMMARY_REPORT"

        # Extract the "Top 50 Most Requested Pages" section
        awk '/Top 50 Most Requested Pages/,/^---/' "$TRAFFIC_REPORT" \
            | grep -E '^\s+[0-9]+\s+/' \
            | head -10 >> "$SUMMARY_REPORT" || echo "No page data available" >> "$SUMMARY_REPORT"

        echo '```' >> "$SUMMARY_REPORT"
        echo "" >> "$SUMMARY_REPORT"
    fi

    cat >> "$SUMMARY_REPORT" <<EOF
## Recommendations

### Traffic
- **Action Items:**
  - Review and optimize top-performing pages
  - Continue regular content publishing
  - Monitor traffic growth month-over-month

### Security
EOF

    if [[ -f "$SECURITY_REPORT" ]] && [[ $alert_count -gt 0 ]]; then
        cat >> "$SUMMARY_REPORT" <<EOF
- **Status:** ⚠️ Security alerts detected
- **Action Items:**
  - Review IP block recommendations in security report
  - Consider implementing fail2ban for automatic blocking
  - Monitor wp-login.php brute force attempts
EOF
    else
        cat >> "$SUMMARY_REPORT" <<EOF
- **Status:** ✅ No critical security issues detected
- **Action Items:**
  - Continue regular monitoring
  - Maintain current security posture
EOF
    fi

    cat >> "$SUMMARY_REPORT" <<EOF

## Next Steps

1. Review detailed reports for traffic patterns
2. Implement any recommended IP blocks
3. Schedule next monitoring run (weekly recommended)
4. Track traffic growth month-over-month
5. Correlate traffic changes with site activity

---

*Reports generated by wp-ops monitoring scripts*
EOF

    print_success "Summary report generated: $SUMMARY_REPORT"
}

# ============================================================================
# Script Entry Point
# ============================================================================

main "$@"
