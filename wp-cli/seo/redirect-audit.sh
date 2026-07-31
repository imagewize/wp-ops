#!/usr/bin/env bash

##############################################################################
# Comprehensive redirect chain audit for WordPress sites
# Tests HTTPS pages, HTTP->HTTPS redirects, and www canonicalization
#
# Usage:
#   ./redirect-audit.sh --url <site-url>
#   ./redirect-audit.sh --url https://example.com --verbose
#   ./redirect-audit.sh --url https://example.com/about/ --url https://example.com/contact/
#
# Output:
#   - Console summary with color-coded status
#   - Detailed report saved to results/audits/redirect-audit-[timestamp].md
#
# Requires: curl
##############################################################################
#
# @desc     Audit redirect chains: HTTPS pages, HTTP->HTTPS, and www canonicalization
# @category seo
# @runs     local
# @requires curl
# @flag     --url      required  {https://example.com}  URL to test (repeatable)
# @flag     --verbose  optional  {}  Show detailed curl output
# @flag     --output   optional  {results/audits}  Output directory for reports
# @example  wp-ops wp-cli/seo/redirect-audit --url https://example.com --verbose
# @doc      wp-cli/seo/README.md

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
REPORT_DIR="results/audits"
REPORT_FILE="${REPORT_DIR}/redirect-audit-${TIMESTAMP}.md"

# Default test URLs will be derived from the provided domain

# Parse arguments
VERBOSE=false
CUSTOM_URLS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -u|--url)
            CUSTOM_URLS+=("$2")
            shift 2
            ;;
        -o|--output)
            REPORT_DIR="$2"
            REPORT_FILE="${REPORT_DIR}/redirect-audit-${TIMESTAMP}.md"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -u, --url URL     Test a specific URL (can specify multiple times)"
            echo "  -v, --verbose     Show detailed curl output"
            echo "  -o, --output DIR  Output directory for reports (default: results/audits)"
            echo "  -h, --help        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $(basename "$0") --url https://example.com"
            echo "  $(basename "$0") --url https://example.com --verbose"
            echo "  $(basename "$0") --url https://example.com/about/ --url https://example.com/contact/"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate we have at least one URL
if [[ ${#CUSTOM_URLS[@]} -eq 0 ]]; then
    echo "Error: At least one URL is required. Use --url to specify."
    echo "Example: $(basename "$0") --url https://example.com"
    exit 1
fi

# Extract domain from first URL for default tests
FIRST_URL="${CUSTOM_URLS[0]}"
# Remove protocol and path to get domain, and strip any leading "www." so the
# www test below builds "www.example.com" rather than "www.www.example.com"
# when the canonical URL passed in is already the www form.
DOMAIN=$(echo "$FIRST_URL" | sed -E 's|^https?://||' | sed -E 's|/.*||' | sed -E 's|^www\.||')

# If only domain was provided, add common paths
if [[ "$FIRST_URL" == "https://${DOMAIN}" || "$FIRST_URL" == "http://${DOMAIN}" ]]; then
    DEFAULT_URLS=(
        "https://${DOMAIN}/"
        "https://${DOMAIN}/about/"
        "https://${DOMAIN}/contact/"
        "https://${DOMAIN}/services/"
    )
else
    DEFAULT_URLS=("${CUSTOM_URLS[@]}")
fi

# If custom URLs were provided, use them; otherwise use defaults
if [[ ${#CUSTOM_URLS[@]} -gt 0 && "${CUSTOM_URLS[0]}" != "https://${DOMAIN}/" && "${CUSTOM_URLS[0]}" != "http://${DOMAIN}/" ]]; then
    TEST_URLS=("${CUSTOM_URLS[@]}")
else
    TEST_URLS=("${DEFAULT_URLS[@]}")
fi

# Create report directory if it doesn't exist
mkdir -p "$REPORT_DIR"

##############################################################################
# Functions
##############################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Redirect Chain Audit - ${DOMAIN}${NC}"
    echo -e "${BLUE}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

test_https_page() {
    local url="$1"
    local output

    echo -e "${YELLOW}Testing HTTPS:${NC} $url"

    output=$(curl -sI -L -w "\n__STATS__\nredirects:%{num_redirects}\nfinal_url:%{url_effective}\nhttp_code:%{http_code}\n" "$url" 2>&1)

    local redirects=$(echo "$output" | grep "^redirects:" | cut -d: -f2)
    local final_url=$(echo "$output" | grep "^final_url:" | cut -d: -f2-)
    local http_code=$(echo "$output" | grep "^http_code:" | cut -d: -f2)

    if [[ "$http_code" == "200" ]] && [[ "$redirects" == "0" ]]; then
        echo -e "  ${GREEN}✓${NC} Status: ${GREEN}200${NC} | Redirects: ${GREEN}0${NC}"
        echo -e "  ${GREEN}✓${NC} OPTIMAL - Direct load, no redirect chain"
        return 0
    elif [[ "$http_code" == "200" ]] && [[ "$redirects" -eq 1 ]]; then
        echo -e "  ${YELLOW}⚠${NC} Status: ${YELLOW}200${NC} | Redirects: ${YELLOW}1${NC}"
        echo -e "  ${YELLOW}⚠${NC} ACCEPTABLE - Single redirect, consider fixing"
        echo -e "  Final URL: $final_url"
        return 1
    elif [[ "$redirects" -gt 1 ]]; then
        echo -e "  ${RED}✗${NC} Status: $http_code | Redirects: ${RED}$redirects${NC}"
        echo -e "  ${RED}✗${NC} ISSUE - Multiple redirect chain detected!"
        echo -e "  Final URL: $final_url"
        return 2
    else
        echo -e "  ${RED}✗${NC} Status: ${RED}$http_code${NC}"
        echo -e "  ${RED}✗${NC} ERROR - Unexpected response"
        return 3
    fi

    if [[ "$VERBOSE" == true ]]; then
        echo "$output" | head -20
    fi

    echo ""
}

test_http_redirect() {
    local https_url="$1"
    local http_url="${https_url//https:/http:}"

    echo -e "${YELLOW}Testing HTTP→HTTPS:${NC} $http_url"

    local output=$(curl -sI "$http_url" 2>&1)
    local http_status=$(echo "$output" | grep "^HTTP" | head -1 | awk '{print $2}')
    local location=$(echo "$output" | grep -i "^Location:" | head -1 | cut -d' ' -f2- | tr -d '\r')

    if [[ "$http_status" == "301" ]] && [[ "$location" == "$https_url" ]]; then
        echo -e "  ${GREEN}✓${NC} Redirects: ${GREEN}301${NC} → $location"
        echo -e "  ${GREEN}✓${NC} CORRECT - Single hop HTTP→HTTPS redirect"
        return 0
    elif [[ "$http_status" == "301" ]]; then
        echo -e "  ${YELLOW}⚠${NC} Redirects: ${YELLOW}301${NC} → $location"
        echo -e "  ${YELLOW}⚠${NC} WARNING - Redirects but not to expected HTTPS URL"
        return 1
    else
        echo -e "  ${RED}✗${NC} Status: ${RED}$http_status${NC}"
        echo -e "  ${RED}✗${NC} ERROR - No redirect or incorrect status"
        return 2
    fi

    echo ""
}

test_www_redirect() {
    echo -e "${YELLOW}Testing WWW→non-WWW:${NC} http://www.${DOMAIN}/"

    local output=$(curl -sI "http://www.${DOMAIN}/" 2>&1)
    local http_status=$(echo "$output" | grep "^HTTP" | head -1 | awk '{print $2}')
    local location=$(echo "$output" | grep -i "^Location:" | head -1 | cut -d' ' -f2- | tr -d '\r')

    if [[ "$http_status" == "301" ]] && [[ "$location" == "https://${DOMAIN}/" ]]; then
        echo -e "  ${GREEN}✓${NC} Redirects: ${GREEN}301${NC} → $location"
        echo -e "  ${GREEN}✓${NC} CORRECT - Single hop www→non-www + HTTPS"
        return 0
    elif [[ "$http_status" == "301" ]]; then
        echo -e "  ${YELLOW}⚠${NC} Redirects: ${YELLOW}301${NC} → $location"
        echo -e "  ${YELLOW}⚠${NC} WARNING - Redirects but not to expected URL"
        return 1
    else
        echo -e "  ${RED}✗${NC} Status: ${RED}$http_status${NC}"
        echo -e "  ${RED}✗${NC} ERROR - No redirect or incorrect status"
        return 2
    fi

    echo ""
}

check_security_headers() {
    local url="$1"

    echo -e "${YELLOW}Checking Security Headers:${NC} $url"

    local output=$(curl -sI "$url" 2>&1)

    local hsts=$(echo "$output" | grep -i "strict-transport-security" || echo "")
    local csp=$(echo "$output" | grep -i "content-security-policy" || echo "")
    local xframe=$(echo "$output" | grep -i "x-frame-options" || echo "")
    local xcontent=$(echo "$output" | grep -i "x-content-type-options" || echo "")

    if [[ -n "$hsts" ]]; then
        echo -e "  ${GREEN}✓${NC} HSTS: Found"
    else
        echo -e "  ${RED}✗${NC} HSTS: Missing"
    fi

    if [[ -n "$csp" ]]; then
        echo -e "  ${GREEN}✓${NC} CSP: Found"
    else
        echo -e "  ${YELLOW}⚠${NC} CSP: Missing"
    fi

    if [[ -n "$xframe" ]]; then
        echo -e "  ${GREEN}✓${NC} X-Frame-Options: Found"
    else
        echo -e "  ${YELLOW}⚠${NC} X-Frame-Options: Missing"
    fi

    if [[ -n "$xcontent" ]]; then
        echo -e "  ${GREEN}✓${NC} X-Content-Type-Options: Found"
    else
        echo -e "  ${YELLOW}⚠${NC} X-Content-Type-Options: Missing"
    fi

    echo ""
}

##############################################################################
# Main Execution
##############################################################################

print_header

# Track results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test HTTPS pages
echo -e "${BLUE}[1/3] Testing HTTPS Pages (should return 200 with 0 redirects)${NC}"
echo ""

for url in "${TEST_URLS[@]}"; do
    if test_https_page "$url"; then
        ((PASSED_TESTS++))
    else
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
done

# Test HTTP redirects
echo -e "${BLUE}[2/3] Testing HTTP→HTTPS Redirects (should be single 301)${NC}"
echo ""

# Test just the homepage and one content page if available
if test_http_redirect "https://${DOMAIN}/"; then
    ((PASSED_TESTS++))
else
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

if [[ ${#TEST_URLS[@]} -gt 1 ]]; then
    if test_http_redirect "${TEST_URLS[1]}"; then
        ((PASSED_TESTS++))
    else
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
fi

# Test www redirect
echo -e "${BLUE}[3/3] Testing WWW Canonicalization${NC}"
echo ""

if test_www_redirect; then
    ((PASSED_TESTS++))
else
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# Check security headers
echo -e "${BLUE}[BONUS] Security Headers Check${NC}"
echo ""
check_security_headers "https://${DOMAIN}/"

# Print summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  SUMMARY${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo ""

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo -e "Your redirect configuration is optimal for SEO."
    OVERALL_STATUS="PASS"
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo -e "Review the output above for redirect chain issues."
    OVERALL_STATUS="FAIL"
fi

echo ""
echo -e "Detailed report saved to: ${BLUE}${REPORT_FILE}${NC}"
echo ""

# Generate markdown report
{
    echo "# Redirect Chain Audit - $(date '+%B %d, %Y')"
    echo ""
    echo "## Executive Summary"
    echo ""
    if [[ "$OVERALL_STATUS" == "PASS" ]]; then
        echo "**Status: ✅ HEALTHY - No redirect chain issues detected**"
    else
        echo "**Status: ⚠️ ISSUES DETECTED**"
    fi
    echo ""
    echo "Audit completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "### Test Results Summary"
    echo ""
    echo "- **Total Tests:** $TOTAL_TESTS"
    echo "- **Passed:** $PASSED_TESTS"
    echo "- **Failed:** $FAILED_TESTS"
    echo "- **Overall Status:** $OVERALL_STATUS"
    echo ""
    echo "## Pages Tested"
    echo ""
    for url in "${TEST_URLS[@]}"; do
        echo "- $url"
    done
    echo ""
    echo "## Audit Details"
    echo ""
    echo "### HTTPS Pages (Primary URLs)"
    echo ""
    echo "All HTTPS URLs should return **HTTP 200** with **0 redirects** for optimal SEO."
    echo ""
    for url in "${TEST_URLS[@]}"; do
        output=$(curl -sI -L -w "\n__STATS__\nredirects:%{num_redirects}\nfinal_url:%{url_effective}\nhttp_code:%{http_code}\n" "$url" 2>&1)
        redirects=$(echo "$output" | grep "^redirects:" | cut -d: -f2)
        http_code=$(echo "$output" | grep "^http_code:" | cut -d: -f2)

        if [[ "$redirects" == "0" ]] && [[ "$http_code" == "200" ]]; then
            status="✅ OPTIMAL"
        else
            status="⚠️ ISSUE"
        fi

        echo "- **$url**"
        echo "  - Status: $http_code"
        echo "  - Redirects: $redirects"
        echo "  - Result: $status"
        echo ""
    done
    echo ""
    echo "### HTTP to HTTPS Redirects"
    echo ""
    echo "HTTP requests should properly redirect to HTTPS with **single 301**:"
    echo ""
    echo '```'
    echo "http://${DOMAIN}/ → https://${DOMAIN}/ (301)"
    echo '```'
    echo ""
    echo "### WWW Canonicalization"
    echo ""
    echo '```'
    echo "http://www.${DOMAIN}/ → https://${DOMAIN}/ (301)"
    echo '```'
    echo ""
    echo "## Recommendations"
    echo ""
    if [[ "$OVERALL_STATUS" == "PASS" ]]; then
        echo "### High Priority: None Required"
        echo "Your redirect configuration is optimal. No action needed."
        echo ""
        echo "### Medium Priority: Monitoring"
        echo ""
        echo "1. **Monitor cache hit rates** - Check FastCGI cache performance"
        echo "2. **Verify sitemap URLs** - Ensure XML sitemap uses HTTPS URLs"
        echo "3. **Check robots.txt** - Confirm it's served over HTTPS without redirect"
    else
        echo "### High Priority: Fix Redirect Chains"
        echo ""
        echo "1. Review failed tests above"
        echo "2. Update canonical URLs to prevent redirects"
        echo "3. Check WordPress permalink settings"
        echo "4. Verify .htaccess or nginx configuration"
    fi
    echo ""
    echo "## Verification Commands"
    echo ""
    echo "To reproduce this audit:"
    echo ""
    echo '```bash'
    echo "$(basename "$0") --url https://${DOMAIN}/"
    echo '```'
    echo ""
    echo "Or run manual tests:"
    echo ""
    echo '```bash'
    echo "# Test HTTPS page"
    echo 'curl -sI -L -w "\nRedirects: %{num_redirects}\nFinal: %{url_effective}\n" \\'
    echo "  https://${DOMAIN}/"
    echo ""
    echo "# Test HTTP redirect"
    echo 'curl -sI http://'"${DOMAIN}"'/ | grep -E "HTTP|Location"'
    echo ""
    echo "# Test www redirect"
    echo 'curl -sI http://www.'"${DOMAIN}"'/ | grep -E "HTTP|Location"'
    echo '```'
    echo ""
    echo "---"
    echo ""
    echo "**Audit Date:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo "**Script:** $(basename "$0")"
    echo "**Domain:** ${DOMAIN}"
    echo "**Status:** $OVERALL_STATUS"
} > "$REPORT_FILE"

echo -e "${GREEN}✓${NC} Audit complete!"

# Exit with appropriate code
if [[ "$OVERALL_STATUS" == "PASS" ]]; then
    exit 0
else
    exit 1
fi
