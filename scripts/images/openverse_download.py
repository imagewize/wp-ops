#!/usr/bin/env python3
"""Download Openverse image URLs and optionally convert to WebP."""
#
# @desc     Download Openverse image URLs (single, repeated, or from a manifest file) and optionally convert to WebP
# @category images
# @runs     local
# @requires python3
# @flag     --url           optional  {https://...}  Image URL (repeatable)
# @flag     --manifest      optional  {urls.txt}  Text file: '<url> <optional-filename>' per line
# @flag     --out-dir       optional  {.}  Output directory
# @flag     --convert-webp  optional  {}  Convert downloaded images to .webp
# @flag     --quality       optional  {75}  WebP quality
# @flag     --resize        optional  {0}  Resize width (0 to skip)
# @flag     --keep-original optional  {}  Keep the original file after WebP conversion
# @example  wp-ops scripts/images/openverse_download --url https://example.com/img.jpg --convert-webp

import argparse
import os
import sys
import urllib.parse
import urllib.request
import subprocess

DEFAULT_USER_AGENT = "wp-ops-openverse-download/1.0"


def iter_manifest(path):
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            url = parts[0]
            name = parts[1] if len(parts) > 1 else None
            yield url, name


def download(url, dest_path, user_agent, referer):
    headers = {"User-Agent": user_agent}
    if referer:
        headers["Referer"] = referer
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        data = resp.read()
    with open(dest_path, "wb") as handle:
        handle.write(data)


def convert_to_webp(src_path, out_path, quality, resize_width):
    cmd = ["cwebp", "-q", str(quality)]
    if resize_width:
        cmd += ["-resize", str(resize_width), "0"]
    cmd += [src_path, "-o", out_path]
    subprocess.run(cmd, check=True)


def main():
    parser = argparse.ArgumentParser(description="Download Openverse image URLs.")
    parser.add_argument("--url", action="append", help="Image URL (repeatable)")
    parser.add_argument("--manifest", help="Text file: '<url> <optional-filename>' per line")
    parser.add_argument("--out-dir", default=".", help="Output directory")
    parser.add_argument("--user-agent", default=DEFAULT_USER_AGENT, help="User-Agent header")
    parser.add_argument("--referer", help="Referer header")
    parser.add_argument("--convert-webp", action="store_true", help="Convert to .webp")
    parser.add_argument("--quality", type=int, default=75, help="WebP quality (default: 75)")
    parser.add_argument("--resize", type=int, default=0, help="Resize width (0 to skip)")
    parser.add_argument("--keep-original", action="store_true", help="Keep original after conversion")
    args = parser.parse_args()

    items = []
    if args.url:
        for u in args.url:
            items.append((u, None))
    if args.manifest:
        items.extend(iter_manifest(args.manifest))

    if not items:
        print("No URLs provided. Use --url or --manifest.", file=sys.stderr)
        return 1

    os.makedirs(args.out_dir, exist_ok=True)

    for url, name in items:
        if not name:
            parsed = urllib.parse.urlparse(url)
            name = os.path.basename(parsed.path) or "download"
        dest_path = os.path.join(args.out_dir, name)

        try:
            download(url, dest_path, args.user_agent, args.referer)
        except Exception as exc:
            print(f"Download failed for {url}: {exc}", file=sys.stderr)
            continue

        if args.convert_webp:
            base, _ext = os.path.splitext(dest_path)
            out_path = base + ".webp"
            try:
                convert_to_webp(dest_path, out_path, args.quality, args.resize)
                if not args.keep_original:
                    os.remove(dest_path)
            except Exception as exc:
                print(f"WebP conversion failed for {dest_path}: {exc}", file=sys.stderr)
                continue

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
