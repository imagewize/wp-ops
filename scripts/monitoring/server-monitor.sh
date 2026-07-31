#!/usr/bin/env bash
#
# Server Resource Monitor
# Live CPU, memory, disk, and process usage snapshot over SSH.
#
# Usage:
#   ./server-monitor.sh <ssh-target> [php-fpm-pool-pattern]
#
# Examples:
#   ./server-monitor.sh web@example.com
#   ./server-monitor.sh root@example.com "php-fpm: pool wordpress"
#
# @desc     Live CPU, memory, disk, and PHP-FPM process snapshot of a server over SSH
# @category monitoring
# @runs     local
# @requires ssh
# @arg      ssh-target            required  {web@example.com}  SSH target to connect to
# @arg      php-fpm-pool-pattern  optional  {php-fpm: pool}  Pattern to match PHP-FPM pool processes
# @example  wp-ops scripts/monitoring/server-monitor web@example.com
# @doc      trellis/monitoring/README.md

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $(basename "$0") <ssh-target> [php-fpm-pool-pattern]"
  echo "Example: $(basename "$0") web@example.com"
  echo "         $(basename "$0") root@example.com \"php-fpm: pool wordpress\""
  exit 0
fi

if [ $# -lt 1 ]; then
  echo "Usage: $(basename "$0") <ssh-target> [php-fpm-pool-pattern]"
  echo "Example: $(basename "$0") web@example.com"
  exit 1
fi

SERVER="$1"
# Matches any pool by default; pass a specific pool name (e.g. "php-fpm: pool wordpress") to narrow it.
PHP_FPM_PATTERN="${2:-php-fpm: pool}"

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Server Resource Monitor - $SERVER${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Generated:${NC} $(date)"
echo ""

# System uptime and load
echo -e "${BOLD}━━━ System Uptime & Load ━━━${NC}"
ssh "$SERVER" "uptime"
echo ""

# Memory usage
echo -e "${BOLD}━━━ Memory Usage ━━━${NC}"
ssh "$SERVER" "free -h"
echo ""

# Memory usage by percentage
echo -e "${BOLD}━━━ Memory Usage (Percentage) ━━━${NC}"
ssh "$SERVER" "free | awk 'NR==2{printf \"Memory: %s/%s (%.2f%% used)\n\", \$3,\$2,\$3*100/\$2 }'"
echo ""

# Disk usage
echo -e "${BOLD}━━━ Disk Usage ━━━${NC}"
ssh "$SERVER" "df -h /"
echo ""

# Disk usage by percentage
echo -e "${BOLD}━━━ Disk Usage (Percentage) ━━━${NC}"
ssh "$SERVER" "df -h / | awk 'NR==2{printf \"Disk: %s/%s (%s used)\n\", \$3,\$2,\$5}'"
echo ""

# Top 15 memory-consuming processes
echo -e "${BOLD}━━━ Top 15 Memory Consumers ━━━${NC}"
echo -e "${YELLOW}USER       PID  %CPU %MEM    VSZ    RSS  COMMAND${NC}"
ssh "$SERVER" "ps aux --sort=-%mem | head -16 | tail -15"
echo ""

# PHP-FPM process count and memory
echo -e "${BOLD}━━━ PHP-FPM Pool Statistics ━━━${NC}"
ssh "$SERVER" "
ps aux | grep '$PHP_FPM_PATTERN' | grep -v grep | wc -l | awk '{print \"PHP-FPM workers: \" \$1}'
ps aux | grep '$PHP_FPM_PATTERN' | grep -v grep | awk '{sum+=\$6} END {printf \"Total RSS memory: %.2f MB\n\", sum/1024}'
ps aux | grep '$PHP_FPM_PATTERN' | grep -v grep | awk '{sum+=\$6; count++} END {if(count>0) printf \"Average per worker: %.2f MB\n\", sum/1024/count}'
"
echo ""

# MySQL/MariaDB memory usage
echo -e "${BOLD}━━━ MySQL/MariaDB Statistics ━━━${NC}"
ssh "$SERVER" "
ps aux | grep -E 'mysql|mariadb' | grep -v grep | awk '{
    printf \"Process: %s\n\", \$11
    printf \"Memory (RSS): %.2f MB\n\", \$6/1024
    printf \"CPU: %.1f%%\n\", \$3
}'
"
echo ""

# Nginx memory usage
echo -e "${BOLD}━━━ Nginx Statistics ━━━${NC}"
ssh "$SERVER" "
ps aux | grep nginx | grep -v grep | awk '{sum+=\$6; count++} END {
    printf \"Nginx workers: %d\n\", count
    printf \"Total memory: %.2f MB\n\", sum/1024
}'
"
echo ""

# System processes summary
echo -e "${BOLD}━━━ Process Summary ━━━${NC}"
ssh "$SERVER" "
echo \"Total processes: \$(ps aux | wc -l)\"
echo \"Running processes: \$(ps aux | grep -c ' R ')\"
echo \"Sleeping processes: \$(ps aux | grep -c ' S ')\"
"
echo ""

# Check for memory pressure / OOM killer events
echo -e "${BOLD}━━━ Recent OOM Killer Events (Last 7 Days) ━━━${NC}"
if ssh "$SERVER" "journalctl -k --since '7 days ago' | grep -i 'out of memory\|oom' | wc -l" | grep -q '^0$'; then
    echo -e "${GREEN}✓ No OOM killer events in last 7 days${NC}"
else
    echo -e "${RED}⚠ OOM killer events detected:${NC}"
    ssh "$SERVER" "journalctl -k --since '7 days ago' | grep -i 'out of memory\|oom' | tail -10"
fi
echo ""

# Swap usage
echo -e "${BOLD}━━━ Swap Usage ━━━${NC}"
ssh "$SERVER" "free -h | grep Swap"
swap_used=$(ssh "$SERVER" "free | awk 'NR==3{print \$3}'")
if [ "$swap_used" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warning: Swap is being used ($swap_used bytes)${NC}"
else
    echo -e "${GREEN}✓ No swap usage detected${NC}"
fi
echo ""

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Monitor Complete${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
