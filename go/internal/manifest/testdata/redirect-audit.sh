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
# @mutates  false
# @requires curl
# @flag     --url      required  {https://example.com}  URL to test (repeatable)
# @flag     --verbose  optional  {}  Show detailed curl output
# @flag     --output   optional  {results/audits}  Output directory for reports
# @example  wp-ops wp-cli/seo/redirect-audit --url https://example.com --verbose
# @doc      wp-cli/seo/README.md

set -euo pipefail
