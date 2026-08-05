#!/bin/bash
#
# Error Monitor - Surface errors from Nginx, PHP-FPM, WordPress, MySQL and systemd
#
# Complements the traffic/security/AI-bot monitors, which read the *access* log.
# This one answers "is anything broken?" rather than "who is visiting?".
#
# Runs on the server (it reads /srv/www/<domain>/logs/ and /var/log/ directly
# and needs GNU date), so invoke it the same way as the other monitors:
#
# Usage:
#   ssh web@example.com 'bash -s' < ./error-monitor.sh [domain] [hours] [output_file]
#   ./error-monitor.sh example.com 24        # on the server itself
#
# Examples:
#   ssh web@example.com 'bash -s' < scripts/monitoring/error-monitor.sh
#   ssh web@example.com 'bash -s' < scripts/monitoring/error-monitor.sh example.com 48
#   ssh root@example.com 'bash -s' < scripts/monitoring/error-monitor.sh example.com 24
#
# The systemd sections (critical errors, PHP segfaults, OOM kills) need journal
# read access. The web user usually lacks it, so those are reported as skipped
# rather than empty — connect as root, or add the user to the adm/systemd-journal
# group, to include them.
#
# @desc     Surface errors from Nginx, PHP-FPM, WordPress, MySQL, and systemd for a domain
# @category monitoring
# @platform trellis
# @runs     server
# @arg      domain       optional  {example.com}  Site domain (used to find /srv/www/<domain>/logs/)
# @arg      hours        optional  {24}  How many hours back to analyze
# @arg      output_file  optional  Path to save the report instead of printing it
# @example  ssh web@example.com 'bash -s' < error-monitor.sh
# @example  ssh root@example.com 'bash -s' < error-monitor.sh example.com 48
# @doc      trellis/monitoring/README.md

set -uo pipefail

# ============================================================================
# Configuration
# ============================================================================

DOMAIN="${1:-example.com}"
HOURS="${2:-24}"
OUTPUT_FILE="${3:-}"  # Optional: path to save report

SITE_ERROR_LOG="/srv/www/${DOMAIN}/logs/error.log"
NGINX_ERROR_LOG="/var/log/nginx/error.log"
# Acorn (Sage 10+) writes WordPress-side exceptions here. Sites not using Acorn
# simply won't have it, which is reported as "not found" rather than as a fault.
ACORN_LOG="/srv/www/${DOMAIN}/current/web/app/cache/acorn/logs/laravel.log"
MYSQL_ERROR_LOG="/var/log/mysql/error.log"

# How many matching lines to print per section. The counts are always exact —
# this only caps the excerpt.
SAMPLE_LINES=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $(basename "$0") [domain] [hours] [output_file]"
    echo ""
    echo "Runs on the server. From your machine:"
    echo "  ssh web@example.com 'bash -s' < $(basename "$0") example.com 24"
    exit 0
fi

# ============================================================================
# Time Filtering
# ============================================================================
#
# Every log here stamps its lines differently, so each gets its own cutoff in
# its own format and a plain string comparison does the rest — all four formats
# are zero-padded and therefore sort chronologically as text. No gawk needed
# (unlike the access-log monitors, which parse Nginx's combined-format date).

if ! date -d "1 hour ago" +%s >/dev/null 2>&1; then
    echo "Error: GNU date is required (this script is meant to run on the server)." >&2
    echo "From your machine: ssh web@${DOMAIN} 'bash -s' < $(basename "$0")" >&2
    exit 1
fi

CUTOFF_NGINX=$(date -d "${HOURS} hours ago" +'%Y/%m/%d %H:%M:%S')   # 2026/07/31 11:07:01
CUTOFF_ISO=$(date -d "${HOURS} hours ago" +'%Y-%m-%d %H:%M:%S')     # 2026-07-31 11:07:01
CUTOFF_COMPACT=$(date -d "${HOURS} hours ago" +'%Y%m%d%H%M%S')      # 20260731110701

# Nginx error log: "2026/07/31 11:07:01 [error] 12345#0: ..."
filter_nginx() {
    awk -v cutoff="$CUTOFF_NGINX" '
        substr($0, 5, 1) == "/" && substr($0, 8, 1) == "/" {
            show = (($1 " " $2) >= cutoff)
        }
        show
    ' "$1" 2>/dev/null
}

# PHP-FPM log: "[31-Jul-2026 11:07:01] WARNING: ..."
# Continuation lines (stack traces) carry no stamp, so they inherit the
# decision made for the entry that opened the block.
filter_php_fpm() {
    awk -v cutoff="$CUTOFF_COMPACT" '
        BEGIN {
            split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", names, " ")
            for (i = 1; i <= 12; i++) month[names[i]] = sprintf("%02d", i)
        }
        substr($0, 1, 1) == "[" && substr($0, 4, 1) == "-" && substr($0, 8, 1) == "-" {
            stamp = substr($0, 9, 4) month[substr($0, 5, 3)] substr($0, 2, 2)
            time = substr($0, 14, 8)
            gsub(/:/, "", time)
            show = ((stamp time) >= cutoff)
        }
        show
    ' "$1" 2>/dev/null
}

# Acorn/Laravel log: "[2026-07-31 11:07:01] production.ERROR: ..."
filter_acorn() {
    awk -v cutoff="$CUTOFF_ISO" '
        substr($0, 1, 1) == "[" && substr($0, 6, 1) == "-" && substr($0, 9, 1) == "-" {
            show = (substr($0, 2, 19) >= cutoff)
        }
        show
    ' "$1" 2>/dev/null
}

# MySQL/MariaDB error log: "2026-07-31 11:07:01 0 [Note] ..."
filter_mysql() {
    awk -v cutoff="$CUTOFF_ISO" '
        substr($0, 5, 1) == "-" && substr($0, 8, 1) == "-" {
            show = (substr($0, 1, 19) >= cutoff)
        }
        show
    ' "$1" 2>/dev/null
}

# ============================================================================
# Helpers
# ============================================================================

print_header() {
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "${BOLD}━━━ $1 ━━━${NC}"
}

# An empty $(...) still counts as one line under `wc -l <<<`, so count here
# instead and keep every caller honest about "0".
count_lines() {
    if [[ -z "$1" ]]; then
        echo 0
    else
        printf '%s\n' "$1" | wc -l | tr -d ' '
    fi
}

# "1 entries in the last 1 hours" reads like a bug in the script rather than a
# quiet hour, and these reports get pasted into tickets.
plural() {
    local count="$1" singular="$2" plural="${3:-${2}s}"
    if [[ "$count" -eq 1 ]]; then echo "$singular"; else echo "$plural"; fi
}

# Reports both the count for the window and an excerpt, from a single read of
# the log — so the number and the lines below it can never disagree.
report_log() {
    local label="$1" path="$2" lines="$3" count="$4"

    print_section "$label"
    if [[ ! -f "$path" ]]; then
        echo -e "${BLUE}ℹ Not found: ${path}${NC}"
    elif [[ ! -r "$path" ]]; then
        echo -e "${YELLOW}⚠ Not readable by $(whoami): ${path}${NC}"
    elif [[ "$count" -eq 0 ]]; then
        echo -e "${GREEN}✓ No entries in the last ${HOURS}h${NC}"
    else
        echo -e "${YELLOW}${count} $(plural "$count" entry entries) in the last ${HOURS}h${NC} ${BLUE}(${path})${NC}"
        echo ""
        printf '%s\n' "$lines" | tail -n "$SAMPLE_LINES"
        [[ "$count" -gt "$SAMPLE_LINES" ]] && echo -e "${BLUE}… showing last ${SAMPLE_LINES} of ${count}${NC}"
    fi
    echo ""
}

read_log() {
    local path="$1" filter="$2"
    [[ -f "$path" && -r "$path" ]] || return 0
    "$filter" "$path"
}

have_journal() {
    journalctl -n 0 >/dev/null 2>&1
}

# ============================================================================
# Main
# ============================================================================

main() {
    if [[ -n "$OUTPUT_FILE" ]]; then
        exec > >(tee "$OUTPUT_FILE")
    fi

    local window="${HOURS} $(plural "$HOURS" hour)"

    print_header "Error Monitor - ${DOMAIN} - Last ${window}"
    echo ""
    echo -e "${BLUE}Generated:${NC} $(date)"
    echo -e "${BLUE}Host:${NC} $(hostname)"
    echo -e "${BLUE}Since:${NC} ${CUTOFF_ISO}"
    echo ""

    # --- Log files ---------------------------------------------------------

    local nginx_lines nginx_count
    nginx_lines=$(read_log "$NGINX_ERROR_LOG" filter_nginx)
    nginx_count=$(count_lines "$nginx_lines")
    report_log "Nginx Error Log (global)" "$NGINX_ERROR_LOG" "$nginx_lines" "$nginx_count"

    # Severity breakdown is only meaningful for the Nginx logs, whose lines are
    # tagged [error]/[crit]/[warn]/…; a bare count hides a single [emerg] among
    # hundreds of routine [notice]s.
    if [[ "$nginx_count" -gt 0 ]]; then
        print_section "Nginx Severity Breakdown"
        printf '%s\n' "$nginx_lines" \
            | grep -oE '\[(emerg|alert|crit|error|warn|notice|info)\]' \
            | sort | uniq -c | sort -rn
        echo ""
    fi

    local site_lines site_count
    site_lines=$(read_log "$SITE_ERROR_LOG" filter_nginx)
    site_count=$(count_lines "$site_lines")
    report_log "Nginx Error Log (${DOMAIN})" "$SITE_ERROR_LOG" "$site_lines" "$site_count"

    # PHP-FPM's log is version-stamped (php8.3-fpm.log), and a server mid-upgrade
    # has more than one. Glob rather than asking `php -v`, which reports the CLI
    # version and can differ from the version FPM actually runs.
    print_section "PHP-FPM Error Log"
    local php_total=0 php_log php_lines php_count found_php=0
    for php_log in /var/log/php*-fpm.log; do
        [[ -f "$php_log" ]] || continue
        found_php=1
        php_lines=$(read_log "$php_log" filter_php_fpm)
        php_count=$(count_lines "$php_lines")
        php_total=$((php_total + php_count))
        if [[ "$php_count" -eq 0 ]]; then
            echo -e "${GREEN}✓ No entries in the last ${HOURS}h${NC} ${BLUE}(${php_log})${NC}"
        else
            echo -e "${YELLOW}${php_count} $(plural "$php_count" entry entries) in the last ${HOURS}h${NC} ${BLUE}(${php_log})${NC}"
            echo ""
            printf '%s\n' "$php_lines" | tail -n "$SAMPLE_LINES"
            [[ "$php_count" -gt "$SAMPLE_LINES" ]] && echo -e "${BLUE}… showing last ${SAMPLE_LINES} of ${php_count}${NC}"
            echo ""
        fi
    done
    [[ "$found_php" -eq 0 ]] && echo -e "${BLUE}ℹ No /var/log/php*-fpm.log found${NC}"
    echo ""

    local acorn_lines acorn_count
    acorn_lines=$(read_log "$ACORN_LOG" filter_acorn)
    acorn_count=$(count_lines "$acorn_lines")
    report_log "WordPress/Acorn Log" "$ACORN_LOG" "$acorn_lines" "$acorn_count"

    local mysql_lines mysql_count
    mysql_lines=$(read_log "$MYSQL_ERROR_LOG" filter_mysql)
    mysql_count=$(count_lines "$mysql_lines")
    report_log "MySQL/MariaDB Error Log" "$MYSQL_ERROR_LOG" "$mysql_lines" "$mysql_count"

    # --- systemd journal ---------------------------------------------------

    local critical_count=0 segfault_count=0 oom_count=0
    local journal_available=0
    have_journal && journal_available=1

    if [[ "$journal_available" -eq 0 ]]; then
        print_section "System Journal"
        echo -e "${YELLOW}⚠ Skipped — $(whoami) cannot read the journal.${NC}"
        echo -e "${BLUE}  Critical errors, PHP segfaults and OOM kills are not included.${NC}"
        echo -e "${BLUE}  Connect as root, or: sudo usermod -aG adm,systemd-journal $(whoami)${NC}"
        echo ""
    else
        local critical_lines segfault_lines oom_lines

        print_section "System Journal (Priority: error and above)"
        critical_lines=$(journalctl --since "${HOURS} hours ago" -p err --no-pager 2>/dev/null | grep -v '^-- No entries' || true)
        critical_count=$(count_lines "$critical_lines")
        if [[ "$critical_count" -eq 0 ]]; then
            echo -e "${GREEN}✓ No critical system errors${NC}"
        else
            echo -e "${RED}⚠ ${critical_count} critical system errors${NC}"
            echo ""
            printf '%s\n' "$critical_lines" | tail -n 20
        fi
        echo ""

        print_section "PHP Segmentation Faults"
        segfault_lines=$(journalctl --since "${HOURS} hours ago" --no-pager 2>/dev/null | grep -i 'segfault.*php' || true)
        segfault_count=$(count_lines "$segfault_lines")
        if [[ "$segfault_count" -eq 0 ]]; then
            echo -e "${GREEN}✓ No PHP segmentation faults${NC}"
        else
            echo -e "${RED}⚠ ${segfault_count} PHP segmentation faults${NC}"
            echo ""
            printf '%s\n' "$segfault_lines" | tail -n 10
        fi
        echo ""

        print_section "Out of Memory Events"
        oom_lines=$(journalctl -k --since "${HOURS} hours ago" --no-pager 2>/dev/null | grep -iE 'out of memory|oom[-_]kill' || true)
        oom_count=$(count_lines "$oom_lines")
        if [[ "$oom_count" -eq 0 ]]; then
            echo -e "${GREEN}✓ No OOM killer events${NC}"
        else
            echo -e "${RED}⚠ ${oom_count} out-of-memory events${NC}"
            echo ""
            printf '%s\n' "$oom_lines" | tail -n 10
            echo ""
            echo -e "${BLUE}  See troubleshooting/OOM.md for diagnosis and swap setup.${NC}"
        fi
        echo ""
    fi

    # --- Summary -----------------------------------------------------------

    print_section "Summary"
    local total=$((nginx_count + site_count + php_total + acorn_count + mysql_count + critical_count + segfault_count + oom_count))

    if [[ "$total" -eq 0 ]]; then
        echo -e "${GREEN}✓ No log entries in the last ${window}${NC}"
    else
        echo -e "${YELLOW}${total} log $(plural "$total" entry entries) in the last ${window}${NC}"
        echo ""
        echo "Breakdown:"
        [[ "$nginx_count" -gt 0 ]]    && echo "  - Nginx (global):        $nginx_count"
        [[ "$site_count" -gt 0 ]]     && echo "  - Nginx (${DOMAIN}):     $site_count"
        [[ "$php_total" -gt 0 ]]      && echo "  - PHP-FPM:               $php_total"
        [[ "$acorn_count" -gt 0 ]]    && echo "  - WordPress/Acorn:       $acorn_count"
        [[ "$mysql_count" -gt 0 ]]    && echo "  - MySQL/MariaDB:         $mysql_count"
        [[ "$critical_count" -gt 0 ]] && echo "  - System (priority err): $critical_count"
        [[ "$segfault_count" -gt 0 ]] && echo "  - PHP segfaults:         $segfault_count"
        [[ "$oom_count" -gt 0 ]]      && echo "  - OOM kills:             $oom_count"
        echo ""
        echo -e "${BLUE}Counts include informational lines — check the severity breakdown${NC}"
        echo -e "${BLUE}and excerpts above before treating a total as a problem.${NC}"
    fi
    echo ""

    if [[ "$segfault_count" -gt 0 || "$oom_count" -gt 0 ]]; then
        echo -e "${RED}Segfaults or OOM kills need attention first — they take down requests${NC}"
        echo -e "${RED}mid-flight and are not visible in the access log.${NC}"
        echo ""
    fi

    print_header "Monitor Complete"

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo ""
        echo "Report saved to: $OUTPUT_FILE"
    fi
}

main "$@"
