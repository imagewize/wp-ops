#!/bin/bash

# Upload a zipped WordPress plugin or theme as a GitHub Release asset
# Useful when GitHub Actions release event fails to trigger (e.g. after repo rename)
#
# Usage:
#   ./upload-release-asset.sh <github-repo> <tag> [zip-name]
#   ./upload-release-asset.sh imagewize/warder-cookie-consent v1.3.1
#   ./upload-release-asset.sh imagewize/my-plugin v2.0.0 my-plugin.zip
#
# Run from the plugin/theme root directory.
# Requires: gh (GitHub CLI), zip, npm (if package.json is present)
# Respects .distignore if present to exclude dev files from the zip.
#
# @desc     Upload a zipped plugin/theme as a GitHub Release asset (for when the release workflow didn't trigger)
# @category release
# @platform any
# @runs     local
# @requires gh
# @arg      github-repo  required  {imagewize/warder-cookie-consent}  GitHub repo in owner/repo form
# @arg      tag          required  {v1.3.1}  Release tag to attach the asset to
# @arg      zip-name     optional  {warder-cookie-consent.zip}  Output zip filename (default: derived from repo slug)
# @example  wp-ops upload-release-asset imagewize/warder-cookie-consent v1.3.1

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo "Usage: $0 <github-repo> <tag> [zip-name]"
    echo "Example: $0 imagewize/warder-cookie-consent v1.3.1"
    exit 1
fi

REPO="$1"
TAG="$2"
REPO_SLUG="${REPO##*/}"
ZIP_NAME="${3:-${REPO_SLUG}.zip}"

echo -e "${BLUE}=== GitHub Release Asset Upload ===${NC}"
echo -e "Repo:  ${YELLOW}${REPO}${NC}"
echo -e "Tag:   ${YELLOW}${TAG}${NC}"
echo -e "Zip:   ${YELLOW}${ZIP_NAME}${NC}"
echo ""

if ! command -v gh &>/dev/null; then
    echo -e "${RED}Error: gh (GitHub CLI) is required but not installed${NC}"
    echo "Install: https://cli.github.com"
    exit 1
fi

if ! command -v zip &>/dev/null; then
    echo -e "${RED}Error: zip is required but not installed${NC}"
    exit 1
fi

# Verify the release exists and is published
echo -e "${BLUE}Step 1: Verifying release ${TAG} exists...${NC}"
RELEASE_STATE=$(gh release view "$TAG" --repo "$REPO" --json isDraft,isPrerelease --jq '"draft=\(.isDraft) prerelease=\(.isPrerelease)"' 2>/dev/null || true)
if [ -z "$RELEASE_STATE" ]; then
    echo -e "${RED}  ✗ Release ${TAG} not found on ${REPO}${NC}"
    exit 1
fi
echo -e "  ✓ Found release: ${RELEASE_STATE}"

# Build JS assets if package.json is present
if [ -f "package.json" ]; then
    echo -e "${BLUE}Step 2: Building JS assets...${NC}"
    if ! command -v npm &>/dev/null; then
        echo -e "${RED}  ✗ npm is required to build but not found${NC}"
        exit 1
    fi
    npm ci --silent
    npx webpack --no-stats
    echo "  ✓ Build complete"
else
    echo -e "${BLUE}Step 2: No package.json found, skipping JS build${NC}"
fi

# Create the zip
echo -e "${BLUE}Step 3: Creating ${ZIP_NAME}...${NC}"
if [ -f ".distignore" ]; then
    zip -r "$ZIP_NAME" . -x@.distignore
    echo "  ✓ Zipped (excluding .distignore entries)"
else
    echo -e "${YELLOW}  ⚠ No .distignore found — zipping everything except .git${NC}"
    zip -r "$ZIP_NAME" . -x ".git/*"
fi
ZIP_SIZE=$(du -sh "$ZIP_NAME" | cut -f1)
echo "  ✓ ${ZIP_NAME} created (${ZIP_SIZE})"

# Check if the asset already exists on the release
echo -e "${BLUE}Step 4: Checking for existing assets...${NC}"
EXISTING=$(gh release view "$TAG" --repo "$REPO" --json assets --jq ".assets[] | select(.name == \"${ZIP_NAME}\") | .name" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
    echo -e "${YELLOW}  ⚠ ${ZIP_NAME} already exists on this release${NC}"
    read -p "  Overwrite? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Upload cancelled."
        rm -f "$ZIP_NAME"
        exit 0
    fi
    gh release delete-asset "$TAG" "$ZIP_NAME" --repo "$REPO" --yes
    echo "  ✓ Removed existing asset"
fi

# Upload the asset
echo -e "${BLUE}Step 5: Uploading to release ${TAG}...${NC}"
gh release upload "$TAG" "$ZIP_NAME" --repo "$REPO"
echo "  ✓ Uploaded"

# Verify
UPLOADED=$(gh release view "$TAG" --repo "$REPO" --json assets --jq ".assets[] | select(.name == \"${ZIP_NAME}\") | \"\(.name) (\(.size / 1024 | floor)KB)\"")
echo ""
echo -e "${GREEN}=== Done ===${NC}"
echo -e "Asset attached: ${GREEN}${UPLOADED}${NC}"
echo -e "Release URL: https://github.com/${REPO}/releases/tag/${TAG}"

# Clean up
rm -f "$ZIP_NAME"
