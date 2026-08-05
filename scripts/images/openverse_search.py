#!/usr/bin/env python3
"""Query Openverse image API and print results."""
#
# @desc     Search the Openverse image API and print matching results
# @category images
# @platform any
# @runs     local
# @requires python3
# @arg      query            required  {sunset}  Search query
# @flag     --license        optional  {cc0}  License filter
# @flag     --license-type   optional  {all}  License type
# @flag     --page-size      optional  {5}  Results per page
# @flag     --limit          optional  {5}  Max results to print
# @flag     --mature         optional  {}  Include mature results
# @flag     --provider       optional  {flickr}  Source provider filter
# @flag     --json           optional  {}  Output raw JSON results
# @example  wp-ops scripts/images/openverse_search sunset --license cc0 --limit 10

import argparse
import json
import sys
import urllib.parse
import urllib.request

BASE_URL = "https://api.openverse.org/v1/images/"
DEFAULT_USER_AGENT = "wp-ops-openverse-search/1.0"


def build_url(query, license_value, license_type, page_size, mature, provider):
    params = {
        "q": query,
        "license": license_value,
        "license_type": license_type,
        "page_size": page_size,
        "mature": str(mature).lower(),
    }
    if provider:
        params["source"] = provider
    return BASE_URL + "?" + urllib.parse.urlencode(params)


def fetch_results(url, user_agent):
    req = urllib.request.Request(url, headers={"User-Agent": user_agent})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


def print_results(data, limit, output_json):
    results = data.get("results", [])[:limit]
    if output_json:
        print(json.dumps(results, indent=2))
        return

    for idx, item in enumerate(results, 1):
        print(f"{idx}. title={item.get('title')!r}")
        print(f"   creator={item.get('creator')!r}")
        print(f"   creator_url={item.get('creator_url')!r}")
        print(f"   source={item.get('source')!r}")
        print(f"   license={item.get('license')!r} {item.get('license_version')!r}")
        print(f"   url={item.get('url')!r}")
        print(f"   landing={item.get('foreign_landing_url')!r}")


def main():
    parser = argparse.ArgumentParser(description="Search Openverse images.")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--license", default="cc0", help="License filter (default: cc0)")
    parser.add_argument("--license-type", default="all", help="License type (default: all)")
    parser.add_argument("--page-size", type=int, default=5, help="Results per page (default: 5)")
    parser.add_argument("--limit", type=int, default=5, help="Max results to print (default: 5)")
    parser.add_argument("--mature", action="store_true", help="Include mature results")
    parser.add_argument("--provider", help="Source provider filter (e.g. flickr, stocksnap)")
    parser.add_argument("--json", action="store_true", help="Output raw JSON results")
    parser.add_argument("--user-agent", default=DEFAULT_USER_AGENT, help="User-Agent header")
    args = parser.parse_args()

    url = build_url(
        args.query,
        args.license,
        args.license_type,
        args.page_size,
        args.mature,
        args.provider,
    )

    try:
        data = fetch_results(url, args.user_agent)
    except Exception as exc:
        print(f"Error fetching Openverse results: {exc}", file=sys.stderr)
        return 1

    print_results(data, args.limit, args.json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
