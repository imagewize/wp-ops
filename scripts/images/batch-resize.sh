#!/bin/bash
# batch-resize.sh - Batch resize and center-crop images for featured images
#
# Usage: ./batch-resize.sh -w WIDTH -H HEIGHT [options] file1 [file2 ...]
#
# Options:
#   -w, --width WIDTH    Output width in pixels (required)
#   -H, --height HEIGHT   Output height in pixels (required)
#   -o, --output PREFIX   Output filename prefix (default: auto-generated from input)
#   -f, --format FORMAT   Output format: jpg, png, webp (default: jpg)
#   -q, --quality QUALITY Quality for jpg/webp (1-100, default: 85)
#   -d, --dry-run         Show what would be done without processing
#   --delete              Delete original files after successful conversion
#   -h, --help            Show this help message
#
# Examples:
#   # Resize all screenshots to 1200x630 with auto naming
#   ./batch-resize.sh -w 1200 -H 630 *.png
#
#   # Resize to 800x419 with custom prefix, keep as JPG
#   ./batch-resize.sh -w 800 -H 419 -o "featured-post" image1.png image2.png
#
#   # Resize to WebP format with quality 90
#   ./batch-resize.sh -w 1920 -H 1080 -f webp -q 90 screenshot.png
#
#   # Dry run to preview changes
#   ./batch-resize.sh -w 1200 -H 630 -d *.jpg
#
# @desc     Batch resize and center-crop images for featured images
# @category images
# @runs     local
# @requires magick
# @arg      files      required  {*.png}  One or more input image files
# @flag     --width    required  {1200}  Output width in pixels
# @flag     --height   required  {630}  Output height in pixels
# @flag     --output   optional  {featured-post}  Output filename prefix
# @flag     --format   optional  {jpg|png|webp}  Output format (default: jpg)
# @flag     --quality  optional  {85}  Quality for jpg/webp, 1-100
# @flag     --dry-run  optional  {}  Show what would be done without processing
# @flag     --delete   optional  {}  Delete original files after successful conversion
# @example  wp-ops scripts/images/batch-resize -w 1200 -H 630 *.png

set -euo pipefail

# Defaults
WIDTH=""
HEIGHT=""
OUTPUT_PREFIX=""
FORMAT="jpg"
QUALITY=85
DRY_RUN=false
DELETE_ORIGINAL=false

# Help function
display_help() {
    cat <<'EOF'
batch-resize.sh - Batch resize and center-crop images

Usage: ./batch-resize.sh -w WIDTH -H HEIGHT [options] file1 [file2 ...]

Required:
  -w, --width WIDTH    Output width in pixels
  -H, --height HEIGHT   Output height in pixels

Options:
  -o, --output PREFIX   Output filename prefix (default: auto from input)
  -f, --format FORMAT   Output format: jpg, png, webp (default: jpg)
  -q, --quality QUALITY Quality for jpg/webp, 1-100 (default: 85)
  -d, --dry-run         Show what would be done without processing
  --delete              Delete original files after successful conversion
  -h, --help            Show this help message

Description:
  Resizes one or more images using center-crop (maintains aspect ratio,
  then crops to exact dimensions). Perfect for WordPress featured images.

Examples:
  # Resize all PNGs to 1200x630 (Facebook OG ratio)
  ./batch-resize.sh -w 1200 -H 630 *.png

  # Resize with custom output names
  ./batch-resize.sh -w 800 -H 419 -o "featured-post" screenshot1.jpg screenshot2.jpg

  # Convert to WebP with high quality
  ./batch-resize.sh -w 1920 -H 1080 -f webp -q 90 screenshot.png

  # Preview changes without modifying files
  ./batch-resize.sh -w 1200 -H 630 -d *.jpg

  # Process and delete originals (use with caution!)
  ./batch-resize.sh -w 800 -H 600 --delete image.png
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            ;;
        -w|--width)
            WIDTH="${2:-}"
            shift
            ;;
        -H|--height)
            HEIGHT="${2:-}"
            shift
            ;;
        -o|--output)
            OUTPUT_PREFIX="${2:-}"
            shift
            ;;
        -f|--format)
            FORMAT="${2:-}"
            shift
            ;;
        -q|--quality)
            QUALITY="${2:-}"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            ;;
        --delete)
            DELETE_ORIGINAL=true
            ;;
        *)
            break
            ;;
    esac
    shift
done

# Remaining arguments are input files
INPUT_FILES=("$@")

# Validate required parameters
if [[ -z "$WIDTH" || -z "$HEIGHT" ]]; then
    echo "Error: Both -w (width) and -H (height) are required."
    echo "Use --help for usage information."
    exit 1
fi

# Validate width and height are numbers
if ! [[ "$WIDTH" =~ ^[0-9]+$ ]] || ! [[ "$HEIGHT" =~ ^0*[1-9][0-9]*$ ]]; then
    echo "Error: Width and height must be positive integers."
    exit 1
fi

# Validate format
case "$FORMAT" in
    jpg|jpeg|png|webp)
        # Valid format
        ;;
    *)
        echo "Error: Unsupported format '$FORMAT'. Use jpg, png, or webp."
        exit 1
        ;;
esac

# Validate quality
if ! [[ "$QUALITY" =~ ^[0-9]+$ ]] || [[ "$QUALITY" -lt 1 || "$QUALITY" -gt 100 ]]; then
    echo "Error: Quality must be a number between 1 and 100."
    exit 1
fi

# Check if input files provided
if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
    echo "Error: No input files specified."
    echo "Use --help for usage information."
    exit 1
fi

# Check all input files exist
for file in "${INPUT_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file"
        exit 1
    fi
done

# Detect ImageMagick command
if command -v magick >/dev/null 2>&1; then
    IM_CMD="magick"
elif command -v convert >/dev/null 2>&1; then
    IM_CMD="convert"
else
    echo "Error: Neither magick nor convert found. Please install ImageMagick."
    exit 1
fi

# Check cwebp availability upfront when WebP output is requested
if [[ "$FORMAT" == "webp" ]] && ! command -v cwebp >/dev/null 2>&1; then
    echo "Error: WebP output requires cwebp. Install with: brew install webp"
    exit 1
fi

# Process each file
file_count=${#INPUT_FILES[@]}
for i in "${!INPUT_FILES[@]}"; do
    input_file="${INPUT_FILES[$i]}"
    file_index=$((i + 1))
    
    # Determine output filename
    if [[ -n "$OUTPUT_PREFIX" ]]; then
        # Use custom prefix with numbering
        output_file="${OUTPUT_PREFIX}-${file_index}.${FORMAT}"
    else
        # Auto-generate from input filename
        basename=$(basename "$input_file")
        name_no_ext="${basename%.*}"
        output_file="${name_no_ext}-${WIDTH}x${HEIGHT}.${FORMAT}"
    fi
    
    # Get directory of input file
    input_dir=$(dirname "$input_file")
    
    # Output file in same directory as input by default
    # Unless output prefix contains a path
    if [[ "$OUTPUT_PREFIX" == /* || "$OUTPUT_PREFIX" == *\/* ]]; then
        # Output prefix contains a path
        output_path="$output_file"
    else
        # Output in same directory as first input file
        output_path="${input_dir}/${output_file}"
    fi
    
    # Display or execute
    if [[ "$DRY_RUN" == true ]]; then
        # Show what would be done
        if [[ "$FORMAT" == "webp" ]]; then
            echo "[DRY RUN] $IM_CMD \"$input_file\" -resize ${WIDTH}x${HEIGHT}^ -gravity center -extent ${WIDTH}x${HEIGHT} miff:- | cwebp -q $QUALITY -- - -o \"$output_path\""
        else
            echo "[DRY RUN] $IM_CMD \"$input_file\" -resize ${WIDTH}x${HEIGHT}^ -gravity center -extent ${WIDTH}x${HEIGHT} -quality $QUALITY \"$output_path\""
        fi
        echo "  Input:  $input_file"
        echo "  Output: $output_path"
        if [[ "$DELETE_ORIGINAL" == true ]]; then
            echo "  Would delete: $input_file"
        fi
        echo ""
    else
        echo "Processing $file_index/$file_count: $input_file"
        
        # Execute the command
        if [[ "$FORMAT" == "webp" ]]; then
            "$IM_CMD" "$input_file" -resize "${WIDTH}x${HEIGHT}^" -gravity center -extent "${WIDTH}x${HEIGHT}" miff:- \
                | cwebp -q "$QUALITY" -- - -o "$output_path"
        else
            "$IM_CMD" "$input_file" -resize "${WIDTH}x${HEIGHT}^" -gravity center -extent "${WIDTH}x${HEIGHT}" -quality "$QUALITY" "$output_path"
        fi
        
        # Verify output
        if [[ -f "$output_path" ]]; then
            file_size=$(stat -f%z "$output_path" 2>/dev/null || stat -c%s "$output_path" 2>/dev/null || echo "unknown")
            size_kb=$((file_size / 1024))
            echo "  Saved: $output_path (${WIDTH}x${HEIGHT}, q${QUALITY}, ${size_kb}KB)"
            
            # Delete original if requested
            if [[ "$DELETE_ORIGINAL" == true ]]; then
                rm -v "$input_file"
            fi
        else
            echo "Error: Failed to create output file: $output_path"
            exit 1
        fi
        echo ""
    fi
done

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run complete. No files were modified."
else
    echo "Batch resize complete. Processed $file_count file(s)."
fi
