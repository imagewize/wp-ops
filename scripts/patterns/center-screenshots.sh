#!/usr/bin/env bash
#
# Center pattern screenshots on a fixed canvas (in place). Trims whitespace,
# resizes to a fixed width, then extends the canvas to WIDTHxHEIGHT with the
# pattern vertically centered (white background). Originals are backed up.
#
# Usage:
#   ./center-screenshots.sh <screenshots-dir> [width] [height]
#
# Example:
#   ./center-screenshots.sh ./screenshots 900 600
#
# @desc     Center pattern screenshots on a fixed canvas in place (backs up originals first)
# @category content
# @platform any
# @runs     local
# @requires magick
# @arg      screenshots-dir  required  {./screenshots}  Directory of pattern-*.webp screenshots
# @arg      width            optional  {900}  Target canvas width
# @arg      height           optional  {600}  Target canvas height
# @example  wp-ops center-screenshots ./screenshots 900 600
# @doc      scripts/patterns/README.md

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -lt 1 ]; then
    echo "Usage: $(basename "$0") <screenshots-dir> [width] [height]"
    exit 1
fi

if ! command -v magick &> /dev/null && ! command -v identify &> /dev/null; then
    echo "Error: ImageMagick not found. Install with: brew install imagemagick"
    exit 1
fi

SCREENSHOTS_DIR="$(cd "$1" && pwd)"
WIDTH="${2:-900}"
TARGET_HEIGHT="${3:-600}"
BACKUP_DIR="$SCREENSHOTS_DIR/originals"

echo -e "${BLUE}Center Pattern Screenshots${NC}"
echo -e "${BLUE}==========================${NC}"
echo -e "${BLUE}Target canvas: ${WIDTH}x${TARGET_HEIGHT}px${NC}\n"

mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW}Backups in: $BACKUP_DIR${NC}\n"

PROCESSED=0
SKIPPED=0

for file in "$SCREENSHOTS_DIR"/pattern-*.webp; do
    [ -f "$file" ] || continue

    filename=$(basename "$file")
    backup_file="$BACKUP_DIR/$filename"

    if [ -f "$backup_file" ]; then
        echo -e "${YELLOW}skip${NC} $filename (already processed)"
        ((SKIPPED++))
        continue
    fi

    echo -e "${BLUE}center${NC} $filename"
    cp "$file" "$backup_file"

    current_dims=$(identify -format "%wx%h" "$file")

    magick "$file" \
        -trim \
        +repage \
        -resize "${WIDTH}x" \
        -gravity center \
        -background white \
        -extent "${WIDTH}x${TARGET_HEIGHT}" \
        -quality 85 \
        "$file"

    new_dims=$(identify -format "%wx%h" "$file")
    file_size=$(du -h "$file" | cut -f1)

    echo -e "   ${current_dims} -> ${new_dims} (${file_size})"
    ((PROCESSED++))
done

echo ""
echo -e "${GREEN}Done.${NC} Processed: $PROCESSED  Skipped: $SKIPPED  Canvas: ${WIDTH}x${TARGET_HEIGHT}px"
echo -e "\nTo restore originals: cp $BACKUP_DIR/*.webp $SCREENSHOTS_DIR/"
