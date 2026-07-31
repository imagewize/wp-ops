#!/bin/bash

# WordPress Plugin Release Script with AI Integration (Claude/Codex)
# Automates version bumping and changelog updates for plugin releases
#
# Usage:
#   ./release-plugin.sh <version> [--commit] [--ai=claude|codex]
#   ./release-plugin.sh 2.5.3          # Generate changelog with AI
#   ./release-plugin.sh 2.5.3 --commit # Auto-commit changes
#
# What it does:
# 1. Compares current branch to main branch
# 2. Uses AI CLI (Claude or Codex) to analyze changes and generate changelog
# 3. Updates version in elayne-blocks.php, readme.txt, and CHANGELOG.md
# 4. Creates professional changelog entries in both formats
# 5. Shows git diff for review
# 6. Optionally commits changes with standardized message
#
# Requirements:
# - claude or codex CLI installed and authenticated
# - git repository with main branch
#
# @desc     Bump plugin version and generate an AI changelog entry (Claude or Codex)
# @category release
# @runs     local
# @requires claude
# @arg      version    required  {2.5.3}  New plugin version
# @flag     --commit   optional  {}  Auto-commit the version bump and changelog
# @flag     --ai       optional  {claude|codex}  AI CLI to use (default: claude, or the only one installed)
# @example  wp-ops scripts/release/release-plugin 2.5.3 --commit

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# CLI command names can be overridden via environment if needed
CLAUDE_COMMAND=${CLAUDE_COMMAND:-claude}
CODEX_COMMAND=${CODEX_COMMAND:-codex}

# Parse options
AUTO_COMMIT=false
AI_TOOL="claude"
AI_TOOL_SPECIFIED=false
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
    --commit)
        AUTO_COMMIT=true
        ;;
    --ai=*)
        AI_TOOL="${1#--ai=}"
        AI_TOOL_SPECIFIED=true
        ;;
    --ai)
        if [ -n "${2:-}" ]; then
            AI_TOOL="$2"
            AI_TOOL_SPECIFIED=true
            shift
        else
            echo -e "${RED}Error: --ai requires a value (claude or codex).${NC}"
            exit 1
        fi
        ;;
    *)
        ARGS+=("$1")
        ;;
    esac
    shift
done
set -- "${ARGS[@]}"

AI_TOOL=$(echo "$AI_TOOL" | tr '[:upper:]' '[:lower:]')
if [ "$AI_TOOL" != "claude" ] && [ "$AI_TOOL" != "codex" ]; then
    echo -e "${RED}Error: Unsupported AI tool '$AI_TOOL'. Use 'claude' or 'codex'.${NC}"
    exit 1
fi

# Prompt for AI tool if not specified and multiple CLIs are available
AVAILABLE_AI_TOOLS=()
command -v "$CLAUDE_COMMAND" &> /dev/null && AVAILABLE_AI_TOOLS+=("claude")
command -v "$CODEX_COMMAND" &> /dev/null && AVAILABLE_AI_TOOLS+=("codex")

if [ ${#AVAILABLE_AI_TOOLS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No AI CLI found (checked for '$CLAUDE_COMMAND' and '$CODEX_COMMAND').${NC}"
    exit 1
fi

if [ "$AI_TOOL_SPECIFIED" = false ]; then
    if [ ${#AVAILABLE_AI_TOOLS[@]} -gt 1 ]; then
        echo ""
        echo "Available AI tools: ${AVAILABLE_AI_TOOLS[*]}"
        read -p "Choose AI tool [default: $AI_TOOL]: " chosen_ai_tool
        if [ -n "$chosen_ai_tool" ]; then
            chosen_ai_tool=$(echo "$chosen_ai_tool" | tr '[:upper:]' '[:lower:]')
            if [[ " ${AVAILABLE_AI_TOOLS[*]} " =~ " ${chosen_ai_tool} " ]]; then
                AI_TOOL="$chosen_ai_tool"
            else
                echo -e "${YELLOW}⚠️  '$chosen_ai_tool' not available. Using '$AI_TOOL'.${NC}"
            fi
        fi
    else
        AI_TOOL="${AVAILABLE_AI_TOOLS[0]}"
    fi
fi

# Capitalized label for display (bash 3.2 compatible)
AI_TOOL_DISPLAY=$(printf '%s' "$AI_TOOL" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

if [ "$AI_TOOL" = "claude" ] && ! command -v "$CLAUDE_COMMAND" &> /dev/null; then
    echo -e "${RED}Error: Claude CLI is required but not installed${NC}"
    echo "Install with: npm install -g @anthropic-ai/claude-cli"
    echo "Or see: https://github.com/anthropics/claude-cli"
    exit 1
fi

if [ "$AI_TOOL" = "codex" ] && ! command -v "$CODEX_COMMAND" &> /dev/null; then
    echo -e "${RED}Error: Codex CLI is required but not installed${NC}"
    echo "Install with: npm install -g @openai/codex"
    exit 1
fi

# Check if version argument is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Version number required${NC}"
    echo "Usage: $0 <version> [--commit] [--ai=claude|codex]"
    echo "Example: $0 2.5.3"
    echo "Example: $0 2.5.3 --commit --ai=codex"
    exit 1
fi

NEW_VERSION="$1"

# Validate version format (semantic versioning: X.Y.Z)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid version format${NC}"
    echo "Version must be in format X.Y.Z (e.g., 2.5.3)"
    exit 1
fi

echo -e "${BLUE}=== Elayne Blocks Plugin Release Tool with ${AI_TOOL_DISPLAY} AI ===${NC}"
echo ""

# Get current version from elayne-blocks.php
CURRENT_VERSION=$(grep "^\s*\* Version:" elayne-blocks.php | sed 's/.*Version: //')
echo -e "Current version: ${YELLOW}$CURRENT_VERSION${NC}"
echo -e "New version:     ${GREEN}$NEW_VERSION${NC}"
echo ""

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
echo -e "Current branch:  ${BLUE}$CURRENT_BRANCH${NC}"
echo ""

# Confirm before proceeding
read -p "Continue with release? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Release cancelled."
    exit 0
fi

echo -e "${BLUE}Step 1: Analyzing changes from main branch...${NC}"

# Get git diff between current branch and main
GIT_DIFF=$(git diff main..HEAD | head -c 50000)  # Limit to ~50KB

if [ -z "$GIT_DIFF" ]; then
    echo -e "${YELLOW}  ⚠ Warning: No changes detected between main and $CURRENT_BRANCH${NC}"
    echo "  Are you on the correct branch?"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Release cancelled."
        exit 0
    fi
fi

echo "  ✓ Retrieved changes from git diff"

echo -e "${BLUE}Step 2: Using ${AI_TOOL_DISPLAY} AI to generate changelog...${NC}"

# Create prompt for AI CLI
AI_PROMPT="You are analyzing changes for the Elayne Blocks WordPress plugin release version $NEW_VERSION (previous version: $CURRENT_VERSION).

Based on the git diff below, generate TWO changelog formats:

1. **CHANGELOG.md format** (detailed, Keep a Changelog style):
   - Use headers: ### Changed, ### Added, ### Fixed, ### Technical
   - Include sub-sections with **bold titles** and bullet points
   - Be detailed and descriptive
   - Example:
     ### Added
     **Mega Menu Icon Features:**
     - Added new icon-based pattern for mega menu content
     - Supports custom icons with flexible positioning

2. **readme.txt format** (concise, WordPress.org style):
   - Single-line entries with prefixes: Changed, Added, Fixed
   - Condensed and abbreviated
   - Example:
     * Added: Mega Menu Icon Features pattern with custom icon support

Git diff:
\`\`\`
$GIT_DIFF
\`\`\`

Return ONLY valid JSON in this exact format (no markdown code blocks):
{
  \"changelog_md\": \"### Changed\\n...\",
  \"readme_txt\": \"* Changed: ...\"
}

Be concise but informative. Focus on user-visible changes."

# Call selected AI CLI
AI_RESPONSE=""
AI_EXIT_CODE=0
AI_TMP_ERROR=$(mktemp)

if [ "$AI_TOOL" = "codex" ]; then
    AI_COMMAND="$CODEX_COMMAND"
    AI_ARGS=()
    if [ -n "${CODEX_CLI_ARGS:-}" ]; then
        # shellcheck disable=SC2206
        AI_ARGS=($CODEX_CLI_ARGS)
    fi
    AI_TMP_OUTPUT=$(mktemp)
    set +e
    echo "$AI_PROMPT" | "$AI_COMMAND" "${AI_ARGS[@]}" exec --skip-git-repo-check --output-last-message "$AI_TMP_OUTPUT" - >"$AI_TMP_ERROR" 2>&1
    AI_EXIT_CODE=$?
    set -e
    if [ $AI_EXIT_CODE -eq 0 ]; then
        AI_RESPONSE=$(cat "$AI_TMP_OUTPUT")
    fi
    rm -f "$AI_TMP_OUTPUT"
else
    AI_COMMAND="$CLAUDE_COMMAND"
    AI_ARGS=()
    if [ -n "${CLAUDE_CLI_ARGS:-}" ]; then
        # shellcheck disable=SC2206
        AI_ARGS=($CLAUDE_CLI_ARGS)
    else
        AI_ARGS=(--print)
    fi
    set +e
    AI_RESPONSE=$(echo "$AI_PROMPT" | "$AI_COMMAND" "${AI_ARGS[@]}" 2>"$AI_TMP_ERROR")
    AI_EXIT_CODE=$?
    set -e
fi

if [ $AI_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}  ✗ ${AI_TOOL_DISPLAY} CLI call failed${NC}"
    echo "Error: $(cat "$AI_TMP_ERROR")"
    rm -f "$AI_TMP_ERROR"
    exit 1
fi
rm -f "$AI_TMP_ERROR"

# Parse JSON from AI response
# AI may wrap JSON in markdown code blocks, so extract it
CHANGELOG_JSON=$(echo "$AI_RESPONSE" | sed -n '/^{/,/^}/p')

if [ -z "$CHANGELOG_JSON" ]; then
    echo -e "${RED}  ✗ Failed to parse ${AI_TOOL_DISPLAY}'s response${NC}"
    echo "${AI_TOOL_DISPLAY} returned: $AI_RESPONSE"
    exit 1
fi

# Extract changelog entries from the AI's JSON response.
#
# Prefer jq: it's already part of this toolchain (create-pr.sh depends on it) and
# parses the object correctly no matter how the model formats it. The previous
# awk-only approach assumed both keys sat on a single line; when the model
# pretty-prints the JSON (one key per line), each value's closing quote lands at
# the end of its own line and the greedy `","readme_txt".*` / `"}$` patterns
# never matched — leaving a trailing `",` or `"` artifact in the changelog.
CHANGELOG_MD=""
README_TXT=""
if command -v jq > /dev/null 2>&1; then
    CHANGELOG_MD=$(printf '%s' "$CHANGELOG_JSON" | jq -r '.changelog_md // empty' 2>/dev/null)
    README_TXT=$(printf '%s' "$CHANGELOG_JSON" | jq -r '.readme_txt // empty' 2>/dev/null)
fi

# Fallback for when jq is unavailable (or the response wasn't strictly valid
# JSON). Locate the key on its line, then strip a closing quote that may be
# followed by `,` or `}` and trailing whitespace at end of line — covering both
# compact and pretty-printed shapes.
extract_json_string() {
    awk -v key="$1" '
        BEGIN { sep = "\"" key "\"[[:space:]]*:[[:space:]]*\"" }
        match($0, sep) {
            val = substr($0, RSTART + RLENGTH)
            sub(/","(changelog_md|readme_txt)".*/, "", val)   # another key on the same line
            sub(/"[[:space:]]*[},]?[[:space:]]*$/, "", val)   # closing quote at end of line
            gsub(/\\n/, "\n", val)
            gsub(/\\"/, "\"", val)
            print val
        }
    ' <<< "$CHANGELOG_JSON"
}
[ -z "$CHANGELOG_MD" ] && CHANGELOG_MD=$(extract_json_string "changelog_md")
[ -z "$README_TXT" ] && README_TXT=$(extract_json_string "readme_txt")

if [ -z "$CHANGELOG_MD" ] || [ -z "$README_TXT" ]; then
    echo -e "${RED}  ✗ Failed to extract changelog entries${NC}"
    echo "JSON: $CHANGELOG_JSON"
    exit 1
fi

echo "  ✓ Generated changelog with ${AI_TOOL_DISPLAY} AI"

# Date formats
CHANGELOG_DATE=$(date +%Y-%m-%d)  # 2026-01-20

echo -e "${BLUE}Step 3: Updating version numbers...${NC}"

# Update elayne-blocks.php (two places: plugin header and constant)
awk -v new_ver="$NEW_VERSION" '
/^[[:space:]]*\* Version:/ {
    match($0, /^[[:space:]]*\* Version: /);
    print substr($0, 1, RLENGTH-1) new_ver;
    next
}
/^define\( .ELAYNE_BLOCKS_VERSION./ {
    print "define( '\''ELAYNE_BLOCKS_VERSION'\'', '\''" new_ver "'\'' );"
    next
}
{ print }
' elayne-blocks.php > elayne-blocks.php.tmp && mv elayne-blocks.php.tmp elayne-blocks.php
echo "  ✓ Updated elayne-blocks.php"

# Update readme.txt stable tag
sed -i.bak "s/^Stable tag: .*/Stable tag: $NEW_VERSION/" readme.txt
echo "  ✓ Updated readme.txt"

# Remove backup files
rm -f elayne-blocks.php.bak readme.txt.bak

echo -e "${BLUE}Step 4: Updating CHANGELOG.md...${NC}"

# Create temporary file with changelog content
TEMP_CHANGELOG=$(mktemp)
echo -e "$CHANGELOG_MD" > "$TEMP_CHANGELOG"

# Create new release entry in CHANGELOG.md
# First, check if "Unreleased" section exists
if grep -q "^## \[Unreleased\]" CHANGELOG.md; then
    # Clear the Unreleased section and add new version
    awk -v version="$NEW_VERSION" -v date="$CHANGELOG_DATE" -v tmpfile="$TEMP_CHANGELOG" '
        /^## \[Unreleased\]/ {
            print $0
            print ""
            print "## [" version "] - " date
            print ""
            while ((getline line < tmpfile) > 0) {
                print line
            }
            close(tmpfile)
            print ""
            skip=1
            next
        }
        /^## \[/ && skip {
            skip=0
        }
        !skip {
            print $0
        }
    ' CHANGELOG.md > CHANGELOG.md.tmp
    mv CHANGELOG.md.tmp CHANGELOG.md
else
    # No Unreleased section, just prepend new version after main header
    awk -v version="$NEW_VERSION" -v date="$CHANGELOG_DATE" -v tmpfile="$TEMP_CHANGELOG" '
        /^## \[/ && !done {
            print "## [" version "] - " date
            print ""
            while ((getline line < tmpfile) > 0) {
                print line
            }
            close(tmpfile)
            print ""
            done=1
        }
        { print $0 }
    ' CHANGELOG.md > CHANGELOG.md.tmp
    mv CHANGELOG.md.tmp CHANGELOG.md
fi

# Clean up temp file
rm -f "$TEMP_CHANGELOG"

echo "  ✓ Added release entry to CHANGELOG.md"

echo -e "${BLUE}Step 5: Updating readme.txt changelog...${NC}"

# Create temporary file with readme content
TEMP_README=$(mktemp)
echo -e "$README_TXT" > "$TEMP_README"

# Add new changelog entry to readme.txt
# Insert after "== Changelog ==" line
awk -v version="$NEW_VERSION" -v tmpfile="$TEMP_README" '
    /^== Changelog ==/ {
        print $0
        print ""
        print "= " version " ="
        while ((getline line < tmpfile) > 0) {
            print line
        }
        close(tmpfile)
        print ""
        next
    }
    { print $0 }
' readme.txt > readme.txt.tmp
mv readme.txt.tmp readme.txt

# Clean up temp file
rm -f "$TEMP_README"

echo "  ✓ Added changelog entry to readme.txt"

echo ""
echo -e "${GREEN}=== Release preparation complete! ===${NC}"
echo ""
echo -e "${BLUE}Generated Changelog Preview:${NC}"
echo ""
echo -e "${YELLOW}CHANGELOG.md:${NC}"
echo "$CHANGELOG_MD" | head -20
echo ""
echo -e "${YELLOW}readme.txt:${NC}"
echo "$README_TXT" | head -10
echo ""
echo -e "${BLUE}Step 6: Review changes...${NC}"
echo ""

# Show git diff
git diff elayne-blocks.php readme.txt CHANGELOG.md

echo ""
echo -e "${YELLOW}=== Next Steps ===${NC}"
echo ""
echo "1. Review the changes above"
echo "2. Manually edit CHANGELOG.md and readme.txt if needed"
echo "3. Commit the changes:"
echo -e "   ${GREEN}git add elayne-blocks.php readme.txt CHANGELOG.md${NC}"
echo -e "   ${GREEN}git commit -m \"Elayne Blocks Version $NEW_VERSION\"${NC}"
echo ""
echo "4. Push and create PR:"
echo -e "   ${GREEN}git push origin $CURRENT_BRANCH${NC}"
echo -e "   ${GREEN}./create-pr.sh main \"Elayne Blocks Version $NEW_VERSION\"${NC}"
echo ""

# Optional auto-commit
if [ "$AUTO_COMMIT" = true ]; then
    echo -e "${BLUE}Auto-committing changes...${NC}"
    git add elayne-blocks.php readme.txt CHANGELOG.md
    git commit -m "Elayne Blocks Version $NEW_VERSION"
    echo -e "${GREEN}✓ Changes committed!${NC}"
    echo ""
    echo "Next: Push and create PR with:"
    echo -e "   ${GREEN}git push origin $CURRENT_BRANCH${NC}"
    echo -e "   ${GREEN}./create-pr.sh main \"Elayne Blocks Version $NEW_VERSION\"${NC}"
fi
