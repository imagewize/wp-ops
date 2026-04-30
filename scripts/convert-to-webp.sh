#!/bin/bash
# Usage: ./convert-to-webp.sh <input.jpg> [output.webp] [quality] [width] [height]
set -e

INPUT="${1:-}"
OUTPUT="${2:-}"
QUALITY="${3:-82}"
WIDTH="${4:-800}"
HEIGHT="${5:-419}"

if [ -z "$INPUT" ]; then
  echo "Usage: $(basename "$0") <input.jpg> [output.webp] [quality] [width] [height]"
  echo "  Defaults: quality=82, width=800, height=419 (1.91:1 for Facebook OG)"
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: file not found: $INPUT"
  exit 1
fi

if [ -z "$OUTPUT" ]; then
  OUTPUT="${INPUT%.*}.webp"
fi

convert "$INPUT" -resize "${WIDTH}x${HEIGHT}^" -gravity center -extent "${WIDTH}x${HEIGHT}" miff:- \
  | cwebp -q "$QUALITY" -- - -o "$OUTPUT"

echo "Saved: $OUTPUT (${WIDTH}x${HEIGHT}, q${QUALITY})"
