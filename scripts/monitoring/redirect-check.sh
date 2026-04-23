#!/bin/bash
# redirect-check.sh - Mass check URLs for redirects using curl
# Usage: bash redirect-check.sh [url1] [url2] ...
#   or edit the URLs array below

# Check if URLs are provided as arguments, otherwise use defaults
if [ $# -gt 0 ]; then
  urls=("$@")
else
  urls=(
    "https://example.com/contact-us/"
    "https://example.com/contact-us"
    "https://example.com/social-media-marketing/"
    "https://example.com/web-development/"
    "https://example.com/services/online-marketing/"
    "https://example.com/services/e-commerce__trashed/woocommerce/"
    "https://example.com/services/e-commerce__trashed/something/"
    "https://example.com/author/adminbkk/"
    "https://example.com/?page_id=11708"
    "https://example.com/cart/"
    "https://example.com/checkout/"
    "https://example.com/my-account/"
  )
fi

# Check each URL for redirects
for url in "${urls[@]}"; do
  result=$(curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}" -L --max-redirs 0 "$url")
  echo "$url => $result"
done
