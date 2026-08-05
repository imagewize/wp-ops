#!/usr/bin/env bash
# Pad an image onto a square canvas and export it as WebP
#
# @desc     Pad an image onto a square canvas and export it as WebP
# @category images
# @platform any
# @runs     local
# @requires magick
# @arg      input           required  {input.webp}  Source image
# @arg      output          required  {output.webp}  Output WebP path
# @flag     --size          optional  {2000}  Square canvas size in pixels (default: max dimension)
# @flag     --quality       optional  {85}  WebP quality (0-100)
# @flag     --background    optional  {white}  Background color
# @flag     --left-pad      optional  {200}  Add left padding by right-aligning after resize
# @example  wp-ops scripts/images/make-square-webp input.webp output.webp --left-pad 200 --size 2000
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./make-square-webp.sh <input> <output> [options]

Options:
  --size <px>       Square canvas size in pixels (defaults to max dimension)
  --quality <0-100> WebP quality (default: 85)
  --background <c>  Background color (default: white)
  --left-pad <px>   Add left padding by right-aligning after resize

Examples:
  ./make-square-webp.sh input.webp output.webp
  ./make-square-webp.sh input.webp output.webp --left-pad 200 --size 2000
USAGE
}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

input=$1
output=$2
shift 2

size=""
quality=85
background="white"
left_pad=""

while [ $# -gt 0 ]; do
  case "$1" in
    --size)
      size=$2
      shift 2
      ;;
    --quality|-q)
      quality=$2
      shift 2
      ;;
    --background)
      background=$2
      shift 2
      ;;
    --left-pad)
      left_pad=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ ! -f "$input" ]; then
  echo "Input not found: $input" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "Missing ImageMagick (magick)." >&2
  exit 1
fi

if ! command -v cwebp >/dev/null 2>&1; then
  echo "Missing cwebp." >&2
  exit 1
fi

if [ -z "$size" ]; then
  size=$(magick identify -format "%w %h" "$input" | awk '{print ($1>$2)?$1:$2}')
fi

temp_output=$(mktemp -t square-webp-XXXXXX.webp)

if [ -n "$left_pad" ]; then
  if ! [[ "$left_pad" =~ ^[0-9]+$ ]]; then
    echo "--left-pad must be a number of pixels." >&2
    exit 1
  fi

  resize_width=$((size - left_pad))
  if [ "$resize_width" -le 0 ]; then
    echo "--left-pad is too large for the chosen size." >&2
    exit 1
  fi

  # Resize to create a left margin, then right-align on the square canvas.
  magick "$input" \
    -resize "${resize_width}x${size}" \
    -background "$background" \
    -gravity east \
    -extent "${size}x${size}" \
    "$temp_output"
else
  magick "$input" \
    -background "$background" \
    -gravity center \
    -extent "${size}x${size}" \
    "$temp_output"
fi

cwebp -q "$quality" "$temp_output" -o "$output" >/dev/null
rm -f "$temp_output"

echo "Saved: $output"
