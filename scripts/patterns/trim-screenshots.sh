#!/usr/bin/env bash
#
# Trim whitespace from pattern screenshots (in place), keeping aspect ratio.
# Originals are backed up before modification.
#
# Usage:
#   ./trim-screenshots.sh <screenshots-dir> [width]
#
# Example:
#   ./trim-screenshots.sh ./screenshots 900
#
# @desc     Trim whitespace from pattern screenshots in place, keeping aspect ratio (backs up originals first)
# @category patterns
# @runs     local
# @requires magick
# @arg      screenshots-dir  required  {./screenshots}  Directory of pattern-*.webp screenshots
# @arg      width            optional  {900}  Resize width after trimming
# @example  wp-ops scripts/patterns/trim-screenshots ./screenshots 900
# @doc      scripts/patterns/README.md

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ $# -lt 1 ]; then
    echo "Usage: $(basename "$0") <screenshots-dir> [width]"
    exit 1
fi

if ! command -v magick &> /dev/null && ! command -v identify &> /dev/null; then
    echo "Error: ImageMagick not found. Install with: brew install imagemagick"
    exit 1
fi

SCREENSHOTS_DIR="$(cd "$1" && pwd)"
WIDTH="${2:-900}"
BACKUP_DIR="$SCREENSHOTS_DIR/originals"

echo -e "${BLUE}Trim Pattern Screenshots${NC}"
echo -e "${BLUE}========================${NC}\n"

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

    echo -e "${BLUE}trim${NC} $filename"
    cp "$file" "$backup_file"

    current_dims=$(identify -format "%wx%h" "$file")

    magick "$file" \
        -trim \
        +repage \
        -resize "${WIDTH}x" \
        -quality 85 \
        "$file"

    new_dims=$(identify -format "%wx%h" "$file")
    file_size=$(du -h "$file" | cut -f1)

    echo -e "   ${current_dims} -> ${new_dims} (${file_size})"
    ((PROCESSED++))
done

echo ""
echo -e "${GREEN}Done.${NC} Processed: $PROCESSED  Skipped: $SKIPPED"
echo -e "\nTo restore originals: cp $BACKUP_DIR/*.webp $SCREENSHOTS_DIR/"
