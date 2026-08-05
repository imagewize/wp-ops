#!/usr/bin/env bash
#
# svg-to-jpg.sh — Export design SVGs to JPG (raster previews).
#
# Renders each .svg next to its source as a .jpg at the SVG's native size,
# flattened on white at quality 90. Uses librsvg (rsvg-convert) for accurate
# font + gradient rendering, then ImageMagick to encode JPG.
#
# The .svg stays the source of truth — these JPGs are throwaway exports for
# platforms that need a raster (WordPress featured images, LinkedIn, Mastodon).
# Re-run after editing any SVG. Keep the exports out of git.
#
# By default each SVG is rendered at its native viewBox size. Pass -w/-h to
# force output dimensions (useful for platform specs, e.g. Mastodon's
# recommended 1920x1080 landscape), or -s to scale by a multiplier for sharper
# output on high-DPI screens. Since the source is vector, upscaling is lossless.
#
# Paths are resolved relative to the current directory.
#
# Usage:
#   svg-to-jpg.sh                            # default: designs/linkedin
#   svg-to-jpg.sh designs/business-cards     # one or more dirs/files
#   svg-to-jpg.sh path/to/banner.svg
#   svg-to-jpg.sh -w 1920 -h 1080 designs/mastodon   # force size
#   svg-to-jpg.sh -s 2 designs/featured-images       # 2x scale
#
# Options:
#   -w N   output width in px  (aspect ratio preserved if only one of -w/-h set)
#   -h N   output height in px
#   -s N   scale multiplier (e.g. 2 = twice native size); ignored if -w/-h given
#   -q N   JPEG quality 1-100 (default 90)
#
# Requirements (install via brew if missing):
#   brew install librsvg imagemagick
#   brew install --cask font-montserrat   # if your SVGs use Montserrat
#
# @desc     Export design SVGs to JPG with librsvg, at native size or forced dimensions
# @category images
# @platform any
# @runs     local
# @requires rsvg-convert magick
# @arg      target  optional  {designs/linkedin}  Directory or .svg file to export (repeatable)
# @flag     -w      optional  {1920}  Output width in px
# @flag     -h      optional  {1080}  Output height in px
# @flag     -s      optional  {2}  Scale multiplier; ignored if -w/-h given
# @flag     -q      optional  {90}  JPEG quality 1-100
# @example  wp-ops svg-to-jpg designs/linkedin
# @example  wp-ops svg-to-jpg -w 1920 -h 1080 designs/mastodon

set -euo pipefail

QUALITY=90
WIDTH=""
HEIGHT=""
SCALE=""

while getopts ":w:h:s:q:" opt; do
  case "$opt" in
    w) WIDTH="$OPTARG" ;;
    h) HEIGHT="$OPTARG" ;;
    s) SCALE="$OPTARG" ;;
    q) QUALITY="$OPTARG" ;;
    :) echo "ERROR: -$OPTARG requires a value" >&2; exit 1 ;;
    \?) echo "ERROR: unknown option -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

# Build the rsvg-convert sizing flags from the options above.
RSVG_SIZE=()
if [ -n "$WIDTH" ]; then RSVG_SIZE+=(-w "$WIDTH"); fi
if [ -n "$HEIGHT" ]; then RSVG_SIZE+=(-h "$HEIGHT"); fi
if [ ${#RSVG_SIZE[@]} -eq 0 ] && [ -n "$SCALE" ]; then RSVG_SIZE+=(-z "$SCALE"); fi

TMP_PNG="$(mktemp -t svg2jpg).png"
trap 'rm -f "$TMP_PNG"' EXIT

# --- dependency checks ---------------------------------------------------------
for bin in rsvg-convert magick; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: '$bin' not found. Install with:" >&2
    echo "  brew install librsvg imagemagick" >&2
    exit 1
  fi
done

# --- resolve targets (default to designs/linkedin under the cwd) ---------------
TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  if [ -d "designs/linkedin" ]; then
    TARGETS=("designs/linkedin")
  else
    echo "ERROR: no target given and ./designs/linkedin does not exist." >&2
    echo "Usage: $(basename "$0") [-w N] [-h N] [-s N] [-q N] <dir-or-file>..." >&2
    exit 1
  fi
fi

# Collect SVG files from the given dirs/files.
svgs=()
for t in "${TARGETS[@]}"; do
  if [ -d "$t" ]; then
    while IFS= read -r f; do svgs+=("$f"); done < <(find "$t" -type f -name '*.svg' | sort)
  elif [ -f "$t" ] && [[ "$t" == *.svg ]]; then
    svgs+=("$t")
  else
    echo "WARN: skipping '$t' (not a directory or .svg file)" >&2
  fi
done

if [ ${#svgs[@]} -eq 0 ]; then
  echo "No .svg files found." >&2
  exit 1
fi

# --- convert -------------------------------------------------------------------
count=0
for svg in "${svgs[@]}"; do
  jpg="${svg%.svg}.jpg"
  rsvg-convert ${RSVG_SIZE[@]+"${RSVG_SIZE[@]}"} "$svg" -o "$TMP_PNG"
  magick "$TMP_PNG" -background white -flatten -quality "$QUALITY" "$jpg"
  printf "  %-58s -> %s\n" "$svg" "$(magick identify -format '%wx%h %b' "$jpg")"
  count=$((count + 1))
done

echo "Done. Exported $count JPG(s)."
