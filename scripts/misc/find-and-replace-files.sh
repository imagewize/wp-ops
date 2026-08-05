#!/bin/bash
# find-and-replace-files.sh - Find and optionally replace multiple copies of a file
#
# Usage: ./find-and-replace-files.sh [options] <filename> [source_file]
#
# Options:
#   -d, --directory <dir>  Search directory (default: current directory)
#   -m, --maxdepth <n>    Maximum search depth (default: 5)
#   -n, --dry-run         Show what would be done without making changes
#   -l, --list            List found files without replacing
#   -s, --size           Also show file sizes in listing
#   -h, --help            Show this help message
#
# Examples:
#   # List all create-pr.sh files with sizes
#   ./find-and-replace-files.sh -l -s create-pr.sh
#
#   # Find and replace all create-pr.sh files with updated version
#   ./find-and-replace-files.sh create-pr.sh ~/wp-ops/scripts/git/create-pr.sh
#
#   # Dry run to see what would be replaced
#   ./find-and-replace-files.sh -n -d ~/code create-pr.sh ~/wp-ops/scripts/git/create-pr.sh
#
# @desc     Find (and optionally replace) multiple copies of a file across projects
# @category misc
# @platform any
# @runs     local
# @requires find
# @arg      filename     required  {create-pr.sh}  Name of file to search for
# @arg      source-file  optional  {~/wp-ops/scripts/git/create-pr.sh}  Replacement file (enables replace mode)
# @flag     --directory  optional  {~/code}  Search directory (default: current directory)
# @flag     --maxdepth   optional  {5}  Maximum search depth
# @flag     --dry-run    optional  {}  Show what would be done without making changes
# @flag     --list       optional  {}  List found files without replacing
# @flag     --size       optional  {}  Also show file sizes in listing
# @example  wp-ops scripts/misc/find-and-replace-files -l -s create-pr.sh
# @doc      scripts/misc/README-FIND-AND-REPLACE.md

set -euo pipefail

# Defaults
SEARCH_DIR="."
MAX_DEPTH=5
DRY_RUN=false
LIST_ONLY=false
SHOW_SIZES=false

# Help function
display_help() {
    cat <<'EOF'
find-and-replace-files.sh - Find and optionally replace multiple copies of a file

Usage: ./find-and-replace-files.sh [options] <filename> [source_file]

Options:
  -d, --directory <dir>  Search directory (default: current directory)
  -m, --maxdepth <n>    Maximum search depth (default: 5)
  -n, --dry-run         Show what would be done without making changes
  -l, --list            List found files without replacing
  -s, --size           Also show file sizes in listing
  -h, --help            Show this help message

Arguments:
  <filename>           Name of file to search for (required)
  [source_file]       Path to replacement file (optional, for replace mode)

Examples:
  # List all create-pr.sh files with sizes
  ./find-and-replace-files.sh -l -s create-pr.sh

  # Find and replace all create-pr.sh files with updated version
  ./find-and-replace-files.sh create-pr.sh ~/wp-ops/scripts/git/create-pr.sh

  # Dry run to see what would be replaced
  ./find-and-replace-files.sh -n -d ~/code create-pr.sh ~/wp-ops/scripts/git/create-pr.sh

  # Search with different depth
  ./find-and-replace-files.sh -m 3 -d /path/to/search create-pr.sh
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            ;;
        -d|--directory)
            SEARCH_DIR="${2:-}"
            shift
            ;;
        -m|--maxdepth)
            MAX_DEPTH="${2:-5}"
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            ;;
        -l|--list)
            LIST_ONLY=true
            ;;
        -s|--size)
            SHOW_SIZES=true
            ;;
        *)
            break
            ;;
    esac
    shift
done

# Remaining arguments
TARGET_FILE="${1:-}"
SOURCE_FILE="${2:-}"

# Validate
if [[ -z "$TARGET_FILE" ]]; then
    echo "Error: Target filename is required."
    echo "Use --help for usage information."
    exit 1
fi

if [[ ! -d "$SEARCH_DIR" ]]; then
    echo "Error: Search directory does not exist: $SEARCH_DIR"
    exit 1
fi

if [[ -n "$SOURCE_FILE" && ! -f "$SOURCE_FILE" ]]; then
    echo "Error: Source file does not exist: $SOURCE_FILE"
    exit 1
fi

# Check if we're in replace mode
REPLACE_MODE=false
if [[ -n "$SOURCE_FILE" && "$LIST_ONLY" == false ]]; then
    REPLACE_MODE=true
fi

# Find files
echo "Searching for '$TARGET_FILE' in $SEARCH_DIR (max depth: $MAX_DEPTH)..."
echo ""

# Use find to locate all files with the target name
# mapfile is Bash 4+, use alternative for macOS compatibility
FILES=()
while IFS= read -r -d $'\0' file; do
    FILES+=("$file")
done < <(find "$SEARCH_DIR" -maxdepth "$MAX_DEPTH" -name "$TARGET_FILE" -type f -print0 2>/dev/null)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No files named '$TARGET_FILE' found."
    exit 0
fi

# Display found files
if [[ "$SHOW_SIZES" == true || "$REPLACE_MODE" == true ]]; then
    for file in "${FILES[@]}"; do
        lines=$(wc -l < "$file" 2>/dev/null || echo "0")
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        size_kb=$((size / 1024))
        if [[ "$SHOW_SIZES" == true ]]; then
            printf "  %6d lines | %5d KB | %s\n" "$lines" "$size_kb" "$file"
        else
            printf "  %6d lines | %s\n" "$lines" "$file"
        fi
    done
else
    for file in "${FILES[@]}"; do
        printf "  %s\n" "$file"
    done
fi

echo ""

# If list only mode, exit here
if [[ "$LIST_ONLY" == true ]]; then
    echo "Found ${#FILES[@]} file(s)."
    exit 0
fi

# Replace mode
if [[ "$REPLACE_MODE" == true ]]; then
    echo "Replacing ${#FILES[@]} file(s) with: $SOURCE_FILE"
    echo ""
    
    for file in "${FILES[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            echo "  [DRY RUN] Would copy: $SOURCE_FILE -> $file"
        else
            cp -v "$SOURCE_FILE" "$file"
            # Make sure it's executable if source is executable
            if [[ -x "$SOURCE_FILE" ]]; then
                chmod +x "$file"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "Dry run complete. No files were modified."
    else
        echo ""
        echo "Updated ${#FILES[@]} file(s)."
    fi
fi
