#!/usr/bin/env bash
#
# svg-to-png.sh — Export design SVGs to PNG (lossless raster previews).
#
# Renders each .svg next to its source as a .png, flattened on white. Uses
# librsvg (rsvg-convert) for accurate font + gradient rendering, then
# ImageMagick to flatten.
#
# Prefer PNG over JPG for any banner/card with text or logos — JPG compression
# blurs fine text edges (wordmark, descriptor strip, URL). LinkedIn banners
# should be uploaded as PNG. The .svg remains the source of truth; keep the
# exports out of git and re-run after editing any SVG.
#
# By default each SVG is rendered at its native viewBox size. Pass -w/-h to
# force output dimensions, or -s to scale by a multiplier for sharper output on
# high-DPI screens. Since the source is vector, upscaling is lossless.
#
# Paths are resolved relative to the current directory.
#
# Usage:
#   svg-to-png.sh                            # default: designs/linkedin
#   svg-to-png.sh designs/business-cards     # one or more dirs/files
#   svg-to-png.sh path/to/banner.svg
#   svg-to-png.sh -w 1584 -h 396 designs/linkedin    # force LinkedIn banner size
#
# Options:
#   -w N   output width in px  (aspect ratio preserved if only one of -w/-h set)
#   -h N   output height in px
#   -s N   scale multiplier (e.g. 2 = twice native size); ignored if -w/-h given
#
# Requirements (install via brew if missing):
#   brew install librsvg imagemagick
#   brew install --cask font-montserrat   # if your SVGs use Montserrat
#
# @desc     Export design SVGs to PNG with librsvg — lossless, best for text/logo banners
# @category images
# @runs     local
# @requires rsvg-convert magick
# @arg      target  optional  {designs/linkedin}  Directory or .svg file to export (repeatable)
# @flag     -w      optional  {1584}  Output width in px
# @flag     -h      optional  {396}  Output height in px
# @flag     -s      optional  {2}  Scale multiplier; ignored if -w/-h given
# @example  wp-ops svg-to-png designs/linkedin
# @example  wp-ops svg-to-png -w 1584 -h 396 designs/linkedin/banner.svg

set -euo pipefail

WIDTH=""
HEIGHT=""
SCALE=""

while getopts ":w:h:s:" opt; do
  case "$opt" in
    w) WIDTH="$OPTARG" ;;
    h) HEIGHT="$OPTARG" ;;
    s) SCALE="$OPTARG" ;;
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

TMP_PNG="$(mktemp -t svg2png).png"
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
    echo "Usage: $(basename "$0") [-w N] [-h N] [-s N] <dir-or-file>..." >&2
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
  png="${svg%.svg}.png"
  rsvg-convert ${RSVG_SIZE[@]+"${RSVG_SIZE[@]}"} "$svg" -o "$TMP_PNG"
  magick "$TMP_PNG" -background white -flatten "$png"
  printf "  %-58s -> %s\n" "$svg" "$(magick identify -format '%wx%h %b' "$png")"
  count=$((count + 1))
done

echo "Done. Exported $count PNG(s)."
