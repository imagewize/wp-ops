#!/bin/bash

#
# Page Creation Script for Production
#
# This script deploys a WordPress page to production by:
# 1. Copying the HTML content file to the production server via SCP
# 2. Checking for existing pages/attachments with the same slug
# 3. Deleting conflicting content if needed
# 4. Creating the page with WP-CLI
# 5. Verifying the page was created successfully
#
# Usage: ./page-creation.sh <content-file> <page-title> <page-slug>
# Example: ./page-creation.sh about-page-content.html "About" "about"
#

set -e  # Exit on error

# Configuration
SERVER_USER="web"
SERVER_HOST="example.com"
SERVER_PATH="/srv/www/example.com/current"
WP_PATH="web/wp"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ $# -ne 3 ]; then
    print_error "Usage: $0 <content-file> <page-title> <page-slug>"
    print_error "Example: $0 about-page-content.html \"About\" \"about\""
    exit 1
fi

CONTENT_FILE="$1"
PAGE_TITLE="$2"
PAGE_SLUG="$3"

# Check if content file exists
if [ ! -f "$CONTENT_FILE" ]; then
    print_error "Content file not found: $CONTENT_FILE"
    exit 1
fi

print_info "Starting page creation process for: $PAGE_TITLE (slug: $PAGE_SLUG)"

# Step 1: Copy content file to production server
print_info "Step 1: Copying content file to production server..."
REMOTE_FILE="/tmp/$(basename $CONTENT_FILE)"
scp "$CONTENT_FILE" "$SERVER_USER@$SERVER_HOST:$REMOTE_FILE"

if [ $? -eq 0 ]; then
    print_info "✓ File copied successfully to $REMOTE_FILE"
else
    print_error "Failed to copy file to server"
    exit 1
fi

# Step 2: Check for existing pages/attachments with the same slug
print_info "Step 2: Checking for existing content with slug '$PAGE_SLUG'..."
EXISTING_CONTENT=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp post list --name=$PAGE_SLUG --post_type=any --format=ids --path=$WP_PATH")

if [ -n "$EXISTING_CONTENT" ]; then
    print_warning "Found existing content with IDs: $EXISTING_CONTENT"

    # Show details of existing content
    print_info "Details of existing content:"
    ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp post list --name=$PAGE_SLUG --post_type=any --format=table --path=$WP_PATH"

    read -p "Do you want to delete this content? (yes/no): " CONFIRM

    if [ "$CONFIRM" = "yes" ]; then
        print_info "Deleting conflicting content..."
        for ID in $EXISTING_CONTENT; do
            ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp post delete $ID --force --path=$WP_PATH"
            print_info "✓ Deleted post ID: $ID"
        done
    else
        print_warning "Aborting. Please resolve conflicts manually."
        # Clean up remote file
        ssh "$SERVER_USER@$SERVER_HOST" "rm -f $REMOTE_FILE"
        exit 1
    fi
else
    print_info "✓ No conflicting content found"
fi

# Step 3: Create the page
print_info "Step 3: Creating page '$PAGE_TITLE'..."

# Read content and create page via SSH
PAGE_ID=$(ssh "$SERVER_USER@$SERVER_HOST" bash -c "'
cd $SERVER_PATH
CONTENT=\$(cat $REMOTE_FILE)
wp post create \
  --post_type=page \
  --post_title=\"$PAGE_TITLE\" \
  --post_name=\"$PAGE_SLUG\" \
  --post_status=publish \
  --post_content=\"\$CONTENT\" \
  --path=$WP_PATH \
  --porcelain
'")

if [ $? -eq 0 ] && [ -n "$PAGE_ID" ]; then
    print_info "✓ Page created successfully with ID: $PAGE_ID"
else
    print_error "Failed to create page"
    # Clean up remote file
    ssh "$SERVER_USER@$SERVER_HOST" "rm -f $REMOTE_FILE"
    exit 1
fi

# Step 4: Verify the page
print_info "Step 4: Verifying page creation..."
PAGE_INFO=$(ssh "$SERVER_USER@$SERVER_HOST" "cd $SERVER_PATH && wp post get $PAGE_ID --fields=ID,post_title,post_name,post_status,post_type --format=json --path=$WP_PATH")

if [ $? -eq 0 ]; then
    print_info "✓ Page verification successful:"
    echo "$PAGE_INFO" | python3 -m json.tool
else
    print_warning "Page created but verification failed"
fi

# Step 5: Clean up remote file
print_info "Step 5: Cleaning up temporary files..."
ssh "$SERVER_USER@$SERVER_HOST" "rm -f $REMOTE_FILE"
print_info "✓ Cleanup complete"

# Step 6: Show page URL
print_info ""
print_info "================================================"
print_info "Page created successfully!"
print_info "Page ID: $PAGE_ID"
print_info "URL: https://example.com/$PAGE_SLUG/"
print_info "Admin URL: https://example.com/wp/wp-admin/post.php?post=$PAGE_ID&action=edit"
print_info "================================================"
print_info ""
print_info "Next steps:"
print_info "1. Visit the page: https://example.com/$PAGE_SLUG/"
print_info "2. Review the content and formatting"
print_info "3. Update SEO metadata (The SEO Framework)"
print_info "4. Add to navigation menu if needed"
