#!/bin/bash
#
# Time to First Byte (TTFB) Test Script
# Purpose: Measure server response time for a WordPress URL, averaged over
#          several requests, and write a detailed report with optimization
#          recommendations.
#
# Usage: ./ttfb-test.sh <url>
#   Example: ./ttfb-test.sh https://example.com/blog/
#
# TTFB Benchmarks (Google Core Web Vitals):
#   Good: < 800ms
#   Needs Improvement: 800ms - 1800ms
#   Poor: > 1800ms
#
# @desc     Measure TTFB for a URL over several requests and write a report with recommendations
# @category monitoring
# @platform any
# @runs     local
# @requires curl bc
# @arg      url  required  {https://example.com}  URL to test
# @example  wp-ops ttfb-test https://example.com
# @doc      docs/wordpress-utilities/speed-optimization/README.md

set -e

TEST_URL="$1"
if [ -z "$TEST_URL" ]; then
  echo "Usage: $0 <url>"
  exit 1
fi

# Configuration
OUTPUT_DIR="audits"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
REPORT_FILE="${OUTPUT_DIR}/ttfb-test-${DATE}.txt"
ITERATIONS=5  # Number of tests to run for averaging

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo "=========================================="
echo "Time to First Byte (TTFB) Test"
echo "URL: ${TEST_URL}"
echo "Iterations: ${ITERATIONS}"
echo "Date: ${DATE}"
echo "=========================================="
echo ""

# Function to measure TTFB
measure_ttfb() {
  local url=$1

  # Use curl with -w flag to get timing information
  # Format: time_namelookup,time_connect,time_appconnect,time_pretransfer,time_starttransfer,time_total
  curl -o /dev/null -s -w "%{time_namelookup},%{time_connect},%{time_appconnect},%{time_pretransfer},%{time_starttransfer},%{time_total},%{http_code}\n" "$url"
}

# Function to convert seconds to milliseconds
to_ms() {
  echo "scale=0; $1 * 1000 / 1" | bc
}

# Run multiple tests
echo "Running ${ITERATIONS} TTFB measurements..."
echo ""

declare -a ttfb_values
declare -a dns_values
declare -a connect_values
declare -a ssl_values

for i in $(seq 1 $ITERATIONS); do
  echo -n "Test $i/$ITERATIONS... "

  # Get timing data
  timing_data=$(measure_ttfb "$TEST_URL")

  # Parse timing data
  IFS=',' read -r dns_time connect_time ssl_time pretransfer_time ttfb total_time http_code <<< "$timing_data"

  # Convert to milliseconds
  dns_ms=$(to_ms "$dns_time")
  connect_ms=$(to_ms "$connect_time")
  ssl_ms=$(to_ms "$ssl_time")
  ttfb_ms=$(to_ms "$ttfb")
  total_ms=$(to_ms "$total_time")

  # Store TTFB values for averaging
  ttfb_values+=("$ttfb_ms")
  dns_values+=("$dns_ms")
  connect_values+=("$connect_ms")
  ssl_values+=("$ssl_ms")

  echo "TTFB: ${ttfb_ms}ms (HTTP ${http_code})"

  # Small delay between tests
  sleep 1
done

echo ""
echo "=========================================="
echo "Calculating Statistics..."
echo "=========================================="
echo ""

# Calculate average TTFB
sum=0
for val in "${ttfb_values[@]}"; do
  sum=$((sum + val))
done
avg_ttfb=$((sum / ITERATIONS))

# Calculate min and max
min_ttfb=${ttfb_values[0]}
max_ttfb=${ttfb_values[0]}
for val in "${ttfb_values[@]}"; do
  if [ "$val" -lt "$min_ttfb" ]; then
    min_ttfb=$val
  fi
  if [ "$val" -gt "$max_ttfb" ]; then
    max_ttfb=$val
  fi
done

# Calculate average DNS
sum_dns=0
for val in "${dns_values[@]}"; do
  sum_dns=$((sum_dns + val))
done
avg_dns=$((sum_dns / ITERATIONS))

# Calculate average Connect
sum_connect=0
for val in "${connect_values[@]}"; do
  sum_connect=$((sum_connect + val))
done
avg_connect=$((sum_connect / ITERATIONS))

# Calculate average SSL
sum_ssl=0
for val in "${ssl_values[@]}"; do
  sum_ssl=$((sum_ssl + val))
done
avg_ssl=$((sum_ssl / ITERATIONS))

# Determine performance rating
if [ "$avg_ttfb" -lt 800 ]; then
  rating="GOOD"
  rating_color="${GREEN}"
  rating_icon="✓"
elif [ "$avg_ttfb" -lt 1800 ]; then
  rating="NEEDS IMPROVEMENT"
  rating_color="${YELLOW}"
  rating_icon="⚠"
else
  rating="POOR"
  rating_color="${RED}"
  rating_icon="❌"
fi

# Display results
echo "TTFB RESULTS"
echo "------------"
echo -e "Average TTFB: ${rating_color}${avg_ttfb}ms${NC} (${rating_icon} ${rating})"
echo "Min TTFB: ${min_ttfb}ms"
echo "Max TTFB: ${max_ttfb}ms"
echo ""

echo "TIMING BREAKDOWN (Average)"
echo "--------------------------"
echo "DNS Lookup: ${avg_dns}ms"
echo "TCP Connect: ${avg_connect}ms"
echo "SSL/TLS Handshake: ${avg_ssl}ms"
echo ""

echo "PERFORMANCE BENCHMARKS"
echo "----------------------"
echo "✓ Good: < 800ms"
echo "⚠ Needs Improvement: 800ms - 1800ms"
echo "❌ Poor: > 1800ms"
echo ""

# Generate detailed report
cat > "${REPORT_FILE}" <<EOF
========================================
TIME TO FIRST BYTE (TTFB) TEST REPORT
========================================

TEST CONFIGURATION
------------------
URL: ${TEST_URL}
Date: ${DATE}
Iterations: ${ITERATIONS}

TTFB RESULTS
------------
Average TTFB: ${avg_ttfb}ms
Min TTFB: ${min_ttfb}ms
Max TTFB: ${max_ttfb}ms
Rating: ${rating}

INDIVIDUAL MEASUREMENTS
-----------------------
EOF

# Add individual test results
for i in "${!ttfb_values[@]}"; do
  test_num=$((i + 1))
  echo "Test ${test_num}: ${ttfb_values[$i]}ms" >> "${REPORT_FILE}"
done

cat >> "${REPORT_FILE}" <<EOF

TIMING BREAKDOWN (Average)
--------------------------
DNS Lookup: ${avg_dns}ms
TCP Connect: ${avg_connect}ms
SSL/TLS Handshake: ${avg_ssl}ms

PERFORMANCE BENCHMARKS
----------------------
Good: < 800ms
Needs Improvement: 800ms - 1800ms
Poor: > 1800ms

CURL TIMING EXPLANATION
-----------------------
- time_namelookup: DNS lookup time
- time_connect: Time to establish TCP connection
- time_appconnect: Time to complete SSL/TLS handshake
- time_starttransfer: TTFB - Time until first byte received
- time_total: Total time for complete request

OPTIMIZATION RECOMMENDATIONS
-----------------------------
EOF

# Add recommendations based on results
if [ "$avg_ttfb" -ge 1800 ]; then
  cat >> "${REPORT_FILE}" <<EOF
❌ POOR TTFB DETECTED (${avg_ttfb}ms)

Critical Actions:
1. Check server resources (CPU, RAM, disk I/O)
2. Review database query performance with Query Monitor
3. Enable object caching (Redis/Memcached)
4. Optimize WordPress configuration
5. Consider upgrading hosting plan
6. Review active plugins and disable unnecessary ones
7. Check for slow database queries

EOF
elif [ "$avg_ttfb" -ge 800 ]; then
  cat >> "${REPORT_FILE}" <<EOF
⚠ TTFB NEEDS IMPROVEMENT (${avg_ttfb}ms)

Recommended Actions:
1. Enable page caching (already using Trellis/Nginx)
2. Optimize database queries
3. Enable Redis object caching
4. Review plugin performance
5. Consider CDN for static assets
6. Optimize WordPress autoload data

EOF
else
  cat >> "${REPORT_FILE}" <<EOF
✓ GOOD TTFB (${avg_ttfb}ms)

Your server response time is excellent.
Continue monitoring and maintain current optimizations.

EOF
fi

# Add DNS-specific recommendations if DNS is slow
if [ "$avg_dns" -ge 100 ]; then
  cat >> "${REPORT_FILE}" <<EOF
DNS Performance:
- Current DNS lookup: ${avg_dns}ms
- Consider using Cloudflare DNS (1.1.1.1) or Google DNS (8.8.8.8)
- Verify DNS provider performance

EOF
fi

# Add SSL-specific recommendations if SSL is slow
if [ "$avg_ssl" -ge 200 ]; then
  cat >> "${REPORT_FILE}" <<EOF
SSL/TLS Performance:
- Current SSL handshake: ${avg_ssl}ms
- Verify TLS 1.3 is enabled
- Consider OCSP stapling
- Check certificate chain optimization

EOF
fi

cat >> "${REPORT_FILE}" <<EOF
NEXT STEPS
----------
[ ] Review server response time in Google Search Console
[ ] Check PageSpeed Insights for server response recommendations
[ ] Monitor TTFB over time (weekly tests recommended)
[ ] Compare TTFB with competitors
[ ] If poor, investigate with Query Monitor plugin
[ ] Test different pages (blog posts, product pages, etc.)

RELATED TOOLS
-------------
- WebPageTest: https://www.webpagetest.org/
- GTmetrix: https://gtmetrix.com/
- Google PageSpeed Insights: https://pagespeed.web.dev/
- Pingdom: https://tools.pingdom.com/

========================================
EOF

echo "=========================================="
echo "Report saved to: ${REPORT_FILE}"
echo "=========================================="
echo ""
echo "View report: cat ${REPORT_FILE}"
echo ""

# Suggest next steps based on performance
if [ "$avg_ttfb" -ge 1800 ]; then
  echo -e "${RED}❌ Critical: TTFB is poor (${avg_ttfb}ms). Immediate optimization required.${NC}"
elif [ "$avg_ttfb" -ge 800 ]; then
  echo -e "${YELLOW}⚠ Warning: TTFB needs improvement (${avg_ttfb}ms). Consider optimizations.${NC}"
else
  echo -e "${GREEN}✓ Success: TTFB is good (${avg_ttfb}ms). Server performance is excellent.${NC}"
fi
echo ""
