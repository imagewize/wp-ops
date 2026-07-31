#!/usr/bin/env bash

#
# Convert Screenshot for Claude Code
#
# Converts PNG screenshots to JPEG format for compatibility with Claude Code's
# VSCode extension, which has a known issue incorrectly labeling PNGs as JPEG.
#
# Usage:
#   ./convert-screenshot-for-claude.sh <png-file>
#   ./convert-screenshot-for-claude.sh --help
#
# Examples:
#   ./convert-screenshot-for-claude.sh .playwright/screenshots/test-screenshot.png
#   ./convert-screenshot-for-claude.sh ~/code/example.com/.playwright/screenshots/theme-unit-test-comments-desktop-2025-11-20-01-09-34.png
#
# Output:
#   Creates a JPEG file with the same name + '-for-claude.jpg' suffix
#   Example: test-screenshot.png -> test-screenshot-for-claude.jpg
#
# @desc     Convert a PNG screenshot to JPEG (Claude Code's VSCode extension mislabels PNGs)
# @category misc
# @runs     local
# @requires convert
# @arg      png-file  required  {test-screenshot.png}  PNG file to convert
# @flag     --quality optional  {90}  JPEG quality (1-100)
# @example  wp-ops scripts/misc/convert-screenshot-for-claude .playwright/screenshots/test.png
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${CYAN}ℹ ${NC}$1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_header() {
    echo -e "${MAGENTA}$1${NC}"
}

show_help() {
    cat << EOF
${MAGENTA}Convert Screenshot for Claude Code${NC}

Converts PNG screenshots to JPEG format for compatibility with Claude Code's
VSCode extension.

${CYAN}Background:${NC}
Claude Code has a known issue where it incorrectly labels PNG screenshots
with 'image/jpeg' media type, causing API errors. This script converts PNGs
to actual JPEG files as a workaround.

${CYAN}Usage:${NC}
  ./convert-screenshot-for-claude.sh <png-file>
  ./convert-screenshot-for-claude.sh --help

${CYAN}Examples:${NC}
  ${GREEN}# Convert a screenshot${NC}
  ./convert-screenshot-for-claude.sh .playwright/screenshots/test.png

  ${GREEN}# Convert with full path${NC}
  ./convert-screenshot-for-claude.sh ~/code/example.com/.playwright/screenshots/screenshot.png

${CYAN}Output:${NC}
  Creates JPEG file with '-for-claude.jpg' suffix:
    test-screenshot.png → test-screenshot-for-claude.jpg

${CYAN}Options:${NC}
  --help, -h          Show this help message
  --quality=N         JPEG quality (1-100, default: 90)

${CYAN}Requirements:${NC}
  - ImageMagick (convert command)

EOF
    exit 0
}

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
fi

# Parse arguments
QUALITY=90
PNG_FILE=""

for arg in "$@"; do
    if [[ "$arg" == --quality=* ]]; then
        QUALITY="${arg#*=}"
    elif [[ ! "$arg" == --* ]]; then
        PNG_FILE="$arg"
    fi
done

# Check if file provided
if [ -z "$PNG_FILE" ]; then
    log_error "No PNG file provided"
    echo ""
    echo "Usage: ./convert-screenshot-for-claude.sh <png-file>"
    echo "Run with --help for more information"
    exit 1
fi

# Check if file exists
if [ ! -f "$PNG_FILE" ]; then
    log_error "File not found: $PNG_FILE"
    exit 1
fi

# Check if ImageMagick is installed
if ! command -v convert &> /dev/null; then
    log_error "ImageMagick not found"
    echo ""
    echo "Please install ImageMagick:"
    echo "  macOS: brew install imagemagick"
    echo "  Ubuntu: sudo apt-get install imagemagick"
    exit 1
fi

# Verify it's a PNG file
if [[ ! "$PNG_FILE" =~ \.png$ ]]; then
    log_warning "File doesn't have .png extension: $PNG_FILE"
    log_warning "Attempting conversion anyway..."
fi

# Generate output filename
BASENAME=$(basename "$PNG_FILE" .png)
DIRNAME=$(dirname "$PNG_FILE")
OUTPUT_FILE="$DIRNAME/${BASENAME}-for-claude.jpg"

# Header
log_header "════════════════════════════════════════════════════"
log_header "  Convert Screenshot for Claude Code"
log_header "════════════════════════════════════════════════════"
echo ""

log_info "Input:   $PNG_FILE"
log_info "Output:  $OUTPUT_FILE"
log_info "Quality: $QUALITY%"
echo ""

# Convert PNG to JPEG
log_info "Converting PNG to JPEG..."

if convert "$PNG_FILE" -quality "$QUALITY" "$OUTPUT_FILE" 2>/dev/null; then
    log_success "Conversion complete"
    echo ""

    # Get file sizes
    if command -v du &> /dev/null; then
        ORIGINAL_SIZE=$(du -h "$PNG_FILE" | cut -f1)
        NEW_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
        log_info "Original: $ORIGINAL_SIZE (PNG)"
        log_info "Converted: $NEW_SIZE (JPEG)"
        echo ""
    fi

    log_success "JPEG file created: $OUTPUT_FILE"
    echo ""
    log_info "You can now view this file in Claude Code without media type errors"
    echo ""
else
    log_error "Conversion failed"
    echo ""
    echo "Common issues:"
    echo "  - File may be corrupted"
    echo "  - Not a valid PNG file"
    echo "  - Insufficient permissions"
    exit 1
fi

exit 0
