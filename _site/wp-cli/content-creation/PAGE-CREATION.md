# WordPress Page Creation Guide - Trellis/Bedrock

Complete guide for creating WordPress pages on Trellis VM (local development) and production servers using WP-CLI and Gutenberg blocks.

**Last Updated:** November 25, 2025
**Environment:** Trellis VM (Lima-based) with Bedrock/WordPress
**Compatibility:** Trellis 1.x, Bedrock, WordPress 6.x+

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local Development (Trellis VM)](#local-development-trellis-vm)
3. [Production Deployment](#production-deployment)
4. [Content Preparation](#content-preparation)
5. [Automated Script Details](#automated-script-details)
6. [Common Issues & Solutions](#common-issues--solutions)
7. [Best Practices](#best-practices)
8. [Examples](#examples)
9. [Adding Patterns to Existing Pages](#adding-patterns-to-existing-pages)

---

## Prerequisites

### Required Tools
- **Trellis CLI** - For VM access
- **WP-CLI** - WordPress command-line interface (available in VM)
- **Text Editor** - For preparing block content

### Required Access
- **Local:** Trellis VM running at project location
- **Production:** SSH access to production server
- **Permissions:** WordPress admin or WP-CLI access

### Project Structure
```
~/code/example.com/
├── site/                    # Bedrock WordPress installation
│   └── web/app/
│       ├── themes/your-theme/  # Custom Sage theme
│       └── plugins/your-patterns-plugin/ # Block patterns plugin (optional)
└── trellis/                 # Trellis configuration
```

**Note:** Replace `example.com` with your actual domain throughout this guide.

---

## Local Development (Trellis VM)

### Step 1: Prepare Block Content

Create an HTML file with Gutenberg block markup:

```bash
# Create your content file (can be anywhere, will be copied to site directory)
nano about-page-content.html
```

**Tip:** See [examples/example-page-content.html](examples/example-page-content.html) in this directory for a complete example using WordPress Gutenberg blocks.

**Content Structure:**
- Use WordPress Gutenberg block comments (`<!-- wp:block-name -->`)
- Follow your theme's block patterns for consistency (if using a patterns plugin)
- Include proper spacing variables (`var:preset|spacing|*`)
- Use your theme's color palette (check `theme.json` for available colors)

**Example Block Pattern:**
```html
<!-- wp:group {"align":"full","backgroundColor":"base","style":{"spacing":{"padding":{"top":"var:preset|spacing|60","bottom":"var:preset|spacing|60"}}},"layout":{"type":"default"}} -->
<div class="wp-block-group alignfull has-base-background-color has-background" style="padding-top:var(--wp--preset--spacing--60);padding-bottom:var(--wp--preset--spacing--60)">
    <!-- wp:heading {"textAlign":"center","level":1,"fontSize":"5xl"} -->
    <h1 class="wp-block-heading has-text-align-center has-5-xl-font-size">Your Heading</h1>
    <!-- /wp:heading -->
</div>
<!-- /wp:group -->
```

### Step 2: Check for Conflicting Slugs

Before creating the page, verify the desired slug is available:

```bash
cd ~/code/example.com/trellis
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post list --name=about --post_type=any --path=web/wp \
  --fields=ID,post_type,post_title,post_name,post_status
```

**Note:** Replace `example.com` with your actual domain name.

**Common Conflicts:**
- **Attachments** with the same slug (e.g., `about` from uploaded images)
- **Draft pages** that were previously created
- **Trashed posts** that haven't been permanently deleted

**Resolution:**
```bash
# Delete conflicting attachments/posts (use actual IDs from above command)
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post delete 2366 1366 --force --path=web/wp
```

### Step 3: Copy Content File to Accessible Location

The Trellis VM can access files in the synced project directory:

```bash
# Copy content to site directory (accessible by VM at /srv/www/example.com/current/)
cp about-page-content.html ~/code/example.com/site/about-page-content.html
```

**Why this step?**
- Lima (Trellis VM) syncs your project directory (e.g., `~/code/example.com/`) to `/srv/www/example.com/current/` inside the VM
- Files outside this directory are not accessible by the VM
- Automatic real-time sync means no manual file transfer needed

### Step 4: Create the Page via WP-CLI

Use WP-CLI to create the page from the VM:

```bash
cd ~/code/example.com/trellis

# Method: Read file in VM and create page
trellis vm shell --workdir /srv/www/example.com/current -- bash -c '
CONTENT=$(cat /srv/www/example.com/current/site/about-page-content.html)
wp post create \
  --post_type=page \
  --post_title="About" \
  --post_name="about" \
  --post_status=publish \
  --post_content="$CONTENT" \
  --path=web/wp
'
```

**Command Breakdown:**
- `trellis vm shell` - Access Trellis VM
- `--workdir` - Set working directory in VM
- `bash -c` - Execute bash commands in VM
- `CONTENT=$(cat ...)` - Read file content into variable
- `wp post create` - Create new WordPress post/page
- `--post_type=page` - Create a page (not post)
- `--post_status=publish` - Publish immediately
- `--path=web/wp` - WordPress installation path in Bedrock

**Expected Output:**
```
Success: Created post 12306.
```

### Step 5: Verify Page Creation

```bash
# Check page details (replace 12306 with your actual page ID)
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post get 12306 --path=web/wp \
  --fields=ID,post_title,post_name,post_status,post_type

# Verify content was saved correctly (search for a unique phrase from your content)
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post get 12306 --path=web/wp --field=post_content | grep -o "Your Unique Phrase"
```

### Step 6: Update Slug (If Needed)

If WordPress created the page with an auto-incremented slug (e.g., `about-2`):

```bash
# Update to correct slug after removing conflicts
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post update 12306 --post_name=about --path=web/wp
```

### Step 7: Flush Cache & Test

```bash
# Flush WordPress cache
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp cache flush --path=web/wp

# Test page in browser (replace example.test with your local domain)
open https://example.test/about/
```

### Step 8: Clean Up

```bash
# Remove temporary content file
rm ~/code/example.com/site/about-page-content.html
```

---

## Production Deployment

### CRITICAL: URL Sanitization Before Production

**IMPORTANT**: When deploying content created locally to production, always check for and fix local development URLs.

**Why this is necessary:**
- PHP pattern files use `get_template_directory_uri()` which returns environment-specific URLs
- When patterns are inserted into pages/posts, these URLs get **hardcoded in the database**
- Content created locally will contain `http://demo.imagewize.test` or `http://example.test` URLs
- Must be replaced with production URLs before going live to avoid mixed content warnings

**Pre-Deployment URL Audit:**
```bash
# STEP 1: Check if any local dev URLs exist in production database
ssh web@example.com "cd /srv/www/example.com/current && \
  wp db query \"SELECT ID, post_title, post_name FROM wp_posts \
  WHERE post_content LIKE '%example.test%' OR post_content LIKE '%.test%';\" \
  --path=web/wp"

# For multisite (e.g., demo.example.com):
ssh web@demo.example.com "cd /srv/www/demo.example.com/current && \
  wp db query \"SELECT ID, post_title, post_name FROM wp_posts \
  WHERE post_content LIKE '%demo.example.test%';\" \
  --path=web/wp --url=https://demo.example.com"
```

**If Dev URLs Found - Fix Before Going Live:**
```bash
# STEP 2: Backup database before making changes
ssh web@example.com "cd /srv/www/example.com/current && \
  wp db export /tmp/backup_before_url_fix_\$(date +%Y%m%d_%H%M%S).sql.gz --path=web/wp"

# STEP 3: Replace dev URLs with production URLs
ssh web@example.com "cd /srv/www/example.com/current && \
  wp search-replace 'http://example.test' 'https://example.com' \
  --all-tables --precise --path=web/wp"

# For multisite:
ssh web@demo.example.com "cd /srv/www/demo.example.com/current && \
  wp search-replace 'http://demo.example.test' 'https://demo.example.com' \
  --all-tables --precise --path=web/wp --url=https://demo.example.com"

# STEP 4: Flush cache
ssh web@example.com "cd /srv/www/example.com/current && wp cache flush --path=web/wp"
```

**STEP 5: Verify in Browser**
- Open browser console (F12)
- Check for mixed content warnings (HTTP resources on HTTPS page)
- Look for any requests to `.test` domains
- Hard refresh (Cmd+Shift+R) to clear browser cache

---

### Option 1: Automated Script (Recommended)

Use the provided [page-creation.sh](page-creation.sh) script for automated deployment:

**Features:**
- Automated file transfer via SCP
- Conflict detection and resolution
- Interactive prompts for safety
- Automatic cleanup
- Comprehensive verification

**Usage:**
```bash
# Basic usage
./page-creation.sh about-page-content.html "About" "about"

# The script will:
# 1. Copy the HTML file to production server
# 2. Check for existing pages/attachments with the same slug
# 3. Prompt for deletion if conflicts exist
# 4. Create the page with WP-CLI
# 5. Verify creation and display page URL
# 6. Clean up temporary files
```

**Script Configuration:**
Edit these variables in the script to match your server:
```bash
SERVER_USER="web"
SERVER_HOST="example.com"
SERVER_PATH="/srv/www/example.com/current"
WP_PATH="web/wp"
```

**Example Output:**
```
[INFO] Starting page creation process for: About (slug: about)
[INFO] Step 1: Copying content file to production server...
[INFO] ✓ File copied successfully to /tmp/about-page-content.html
[INFO] Step 2: Checking for existing content with slug 'about'...
[INFO] ✓ No conflicting content found
[INFO] Step 3: Creating page 'About'...
[INFO] ✓ Page created successfully with ID: 12345
[INFO] Step 4: Verifying page creation...
[INFO] ✓ Page verification successful
[INFO] Step 5: Cleaning up temporary files...
[INFO] ✓ Cleanup complete

================================================
Page created successfully!
Page ID: 12345
URL: https://example.com/about/
Admin URL: https://example.com/wp/wp-admin/post.php?post=12345&action=edit
================================================
```

### Option 2: Manual Production Deployment

**Step 1: Prepare Content**
```bash
# Copy content file to server-accessible location
# Replace web@example.com with your actual server user and domain
scp about-page-content.html web@example.com:/tmp/
```

**Step 2: Create Page**
```bash
# SSH to production (replace with your actual server)
ssh web@example.com
cd /srv/www/example.com/current

# Create page
CONTENT=$(cat /tmp/about-page-content.html)
wp post create \
  --post_type=page \
  --post_title="About" \
  --post_name="about" \
  --post_status=publish \
  --post_content="$CONTENT" \
  --path=web/wp

# Clean up
rm /tmp/about-page-content.html
```

**Step 3: Verify**
```bash
# Check page was created
wp post list --post_type=page --name=about --path=web/wp \
  --fields=ID,post_title,post_name,post_status

# Flush cache
wp cache flush --path=web/wp

# Test in browser (replace with your actual domain)
curl -I https://example.com/about/
```

### Option 2: Export/Import via Database

**Step 1: Export Page from Development**
```bash
# Export specific page
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post list --post_type=page --name=about --path=web/wp \
  --format=json > about-page-export.json
```

**Step 2: Recreate on Production**
```bash
# Read JSON and create matching page on production
ssh web@example.com "cd /srv/www/example.com/current && \
  wp post create --post_type=page --post_title='About' \
  --post_name='about' --post_status=publish \
  --post_content='<content here>' --path=web/wp"
```

### Option 3: WordPress Export/Import (WXR)

**For multiple pages or complex content:**

```bash
# Local: Export page (replace 12306 with your actual page ID)
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp export --path=web/wp --post__in=12306 --dir=/tmp

# Copy to production
scp web@example.com:/tmp/export.xml /tmp/
ssh web@example.com
wp import /tmp/export.xml --path=/srv/www/example.com/current/web/wp --authors=skip
```

---

## Content Preparation

### Using Block Patterns Plugin (Optional)

If your project includes a custom block patterns plugin:

**Location:** `~/code/example.com/site/web/app/plugins/your-patterns-plugin/patterns/`

**Common Pattern Types:**
- Hero sections with buttons
- Feature grids and layouts
- Testimonials and reviews
- Team member grids
- Pricing tables
- Contact information blocks
- Call-to-action sections

**Pattern Structure:**
```php
return array(
    'title'   => 'Pattern Name',
    'content' => '<!-- wp:group -->...'
);
```

**Note:** Pattern availability depends on your specific theme and plugins.

### Block Content Guidelines

**1. No Fixed Font Sizes**
```html
<!-- ❌ BAD -->
<h1 style="font-size:3rem">Heading</h1>

<!-- ✅ GOOD -->
<h1 class="wp-block-heading has-5-xl-font-size">Heading</h1>
```

**2. Use Theme Color Palette**
```html
<!-- ✅ Use named colors -->
textColor="primary"
backgroundColor="base"

<!-- ❌ Avoid inline colors -->
style="color:#ff6b35"
```

**3. Use Spacing Variables**
```html
<!-- ✅ Use preset spacing -->
style="padding-top:var(--wp--preset--spacing--60)"

<!-- ❌ Avoid fixed spacing -->
style="padding-top:60px"
```

**4. Responsive Design**
- Use `alignfull` for full-width sections
- Use `alignwide` for constrained wide sections
- Rely on theme's responsive breakpoints

### SEO Considerations

**Page Title:**
- Keep under 60 characters
- Include primary keyword
- Consider your SEO plugin's title suffix (e.g., "| Your Site Name")

**Meta Description:**
- Maximum 155 characters
- Set via your SEO plugin's meta box (e.g., The SEO Framework, Yoast, Rank Math)
- Focus on your unique value proposition

**Heading Structure:**
- One H1 per page (page title)
- Use H2 for main sections
- Use H3 for subsections
- Maintain proper hierarchy

---

## Automated Script Details

The [page-creation.sh](page-creation.sh) script provides a streamlined workflow with built-in safety checks.

### Script Workflow

1. **Argument Validation**
   - Requires exactly 3 arguments: content file, page title, page slug
   - Validates content file exists locally
   - Provides usage examples if arguments are missing

2. **File Transfer**
   - Uses SCP to copy HTML content to `/tmp/` on production server
   - Verifies successful transfer before proceeding
   - Exits with error if transfer fails

3. **Conflict Detection**
   - Checks for existing posts/pages/attachments with the same slug
   - Displays details of conflicting content in table format
   - Prompts for confirmation before deletion
   - Supports deleting multiple conflicting items

4. **Page Creation**
   - Reads content file on remote server
   - Creates page with specified title, slug, and published status
   - Returns page ID for verification
   - Handles errors gracefully

5. **Verification**
   - Retrieves page details via WP-CLI
   - Displays JSON formatted page information
   - Shows page URL and admin edit URL

6. **Cleanup**
   - Removes temporary content file from server
   - Runs regardless of success/failure (when reached)

### Script Customization

**Server Configuration:**
```bash
SERVER_USER="web"          # SSH user for production server
SERVER_HOST="example.com"  # Production server hostname
SERVER_PATH="/srv/www/example.com/current"  # Bedrock root path
WP_PATH="web/wp"           # WordPress installation path (Bedrock structure)
```

**Color Output:**
- Green `[INFO]` - Successful operations
- Yellow `[WARN]` - Warnings (conflicts found, etc.)
- Red `[ERROR]` - Errors requiring attention

### Security Considerations

- Script uses `set -e` to exit immediately on any command failure
- Requires explicit "yes" confirmation for destructive operations
- Uses `--force` flag when deleting to permanently remove content
- Cleans up temporary files even on failure
- Content files stored in `/tmp/` with unique names

### Requirements

- **SSH access** to production server with key-based authentication
- **SCP** enabled on production server
- **WP-CLI** installed on production server
- **Python 3** for JSON formatting (verification step)
- **Bash** shell (tested with bash 4.0+)

## Common Issues & Solutions

### Issue 1: Slug Already Exists

**Symptom:** Page created with slug `about-2` instead of `about`

**Cause:** Another post/attachment already uses the `about` slug

**Solution:**
```bash
# Find conflicting posts
wp post list --name=about --post_type=any --path=web/wp

# Delete conflicts
wp post delete <ID> --force --path=web/wp

# Update page slug
wp post update <PAGE_ID> --post_name=about --path=web/wp
```

### Issue 2: Content Not Displaying

**Symptom:** Page shows blank or incorrect content

**Causes:**
1. Cache not flushed
2. File content not properly escaped
3. Block markup errors

**Solutions:**
```bash
# Flush all caches
wp cache flush --path=web/wp

# Check content was saved
wp post get <ID> --path=web/wp --field=post_content | head -20

# Validate block markup
wp block validate <ID> --path=web/wp
```

### Issue 3: Cannot Run WP-CLI from Host

**Symptom:** `Error: Can't read wp-config.php file`

**Cause:** Local MariaDB/MySQL running on port 3306 conflicts with VM

**Solution:** Always run WP-CLI commands from within Trellis VM:
```bash
# ✅ CORRECT: Run in VM
trellis vm shell --workdir /srv/www/example.com/current -- wp <command>

# ❌ WRONG: Run on host
wp <command> --path=~/code/example.com/site/web/wp
```

### Issue 4: File Sync Issues

**Symptom:** Changes not appearing in VM

**Cause:** Lima file sync delay or WordPress cache

**Solutions:**
```bash
# Check if file exists in VM
trellis vm shell -- ls -la /srv/www/example.com/current/site/

# Flush WordPress cache
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp cache flush --path=web/wp

# Hard refresh browser (Cmd+Shift+R on Mac, Ctrl+Shift+R on Linux/Windows)
```

### Issue 5: Command Substitution Not Working

**Symptom:** Content shows literal `$(cat ...)` instead of file contents

**Cause:** Shell escaping issues with nested quotes

**Solution:** Use proper quoting in bash:
```bash
# ✅ CORRECT: Single quotes for outer bash -c, double for inner
bash -c 'CONTENT=$(cat file.html) && wp post create --post_content="$CONTENT"'

# ❌ WRONG: Double quotes everywhere
bash -c "CONTENT=$(cat file.html) && wp post create --post_content=\"$CONTENT\""
```

---

## Best Practices

### Development Workflow

1. **Always work locally first**
   - Test on Trellis VM (e.g., `https://example.test`)
   - Verify content displays correctly
   - Check responsive design at different viewports

2. **Version control content files**
   - Store block content in version control
   - Use descriptive filenames (`about-page-content.html`)
   - Document any custom blocks or patterns used

3. **Use patterns for consistency**
   - Leverage your theme's block patterns (if available)
   - Maintain consistent spacing and colors from your theme
   - Reuse existing blocks when possible

4. **Test before production**
   - Verify all links work
   - Check images display correctly
   - Test contact forms/CTAs
   - Validate schema markup

### Security Best Practices

1. **Avoid inline scripts**
   - Don't include `<script>` tags in content
   - Use theme/plugin for JavaScript functionality

2. **Sanitize user input**
   - Escape special characters in dynamic content
   - Use WordPress sanitization functions

3. **Limit permissions**
   - Use `web` user for WP-CLI on production
   - Don't use `root` for content operations

### Performance Optimization

1. **Optimize images before uploading**
   - Use WebP format
   - Compress to appropriate size
   - Include alt text for SEO

2. **Minimize inline styles**
   - Use theme classes instead of inline CSS
   - Rely on theme spacing/typography system

3. **Lazy load off-screen content**
   - Use native lazy loading for images
   - Defer non-critical content

### SEO Optimization

1. **Set page metadata**
   - Title tag (via your SEO plugin)
   - Meta description (155 chars max)
   - Open Graph tags (if supported by your SEO plugin)

2. **Optimize heading structure**
   - One H1 per page
   - Logical H2-H6 hierarchy
   - Include target keywords

3. **Add internal links**
   - Link to relevant service pages
   - Link to blog posts
   - Use descriptive anchor text

4. **Schema markup** (if implemented)
   - Verify schema presence with your schema validation tools
   - Add enhanced Organization schema for About page
   - Include BreadcrumbList for navigation

---

## Examples

### Example 1: Using Automated Script (Production)

```bash
# 1. Prepare your content file (use examples/example-page-content.html as a template)
nano about-page-content.html

# 2. Run the automated script
./page-creation.sh about-page-content.html "About" "about"

# 3. Follow prompts if conflicts exist
# The script handles everything else automatically!
```

### Example 2: Complete Local Development Workflow

### Full Command Sequence

```bash
# 1. Navigate to project
cd ~/code/example.com/trellis

# 2. Check for conflicts
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post list --name=about --post_type=any --path=web/wp \
  --fields=ID,post_type,post_title,post_name

# 3. Delete conflicts if found (use actual IDs from step 2)
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post delete 2366 1366 --force --path=web/wp

# 4. Copy content file
cp about-page-content.html ~/code/example.com/site/about-page-content.html

# 5. Create page
trellis vm shell --workdir /srv/www/example.com/current -- bash -c '
CONTENT=$(cat /srv/www/example.com/current/site/about-page-content.html)
wp post create \
  --post_type=page \
  --post_title="About" \
  --post_name="about" \
  --post_status=publish \
  --post_content="$CONTENT" \
  --path=web/wp
'

# 6. Verify creation (replace 12306 with the ID from step 5 output)
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp post get 12306 --path=web/wp \
  --fields=ID,post_title,post_name,post_status

# 7. Flush cache
trellis vm shell --workdir /srv/www/example.com/current -- \
  wp cache flush --path=web/wp

# 8. Clean up
rm ~/code/example.com/site/about-page-content.html

# 9. Test in browser (replace example.test with your local domain)
open https://example.test/about/
```

---

## Related Documentation

- **Trellis Documentation:** [roots.io/trellis](https://roots.io/trellis/)
- **Bedrock Documentation:** [roots.io/bedrock](https://roots.io/bedrock/)
- **WP-CLI Documentation:** [wp-cli.org](https://wp-cli.org/)
- **WordPress Block Editor:** [wordpress.org/gutenberg](https://wordpress.org/gutenberg/)
- **Your Project README:** Check your project's `CLAUDE.md` or `README.md` for project-specific instructions

---

## Quick Reference

### Key Paths

| Description | Local Path | VM Path |
|-------------|------------|---------|
| Project Root | `~/code/example.com` | `/srv/www/example.com/current` |
| WordPress | `site/web/wp` | `web/wp` |
| Theme | `site/web/app/themes/your-theme` | `web/app/themes/your-theme` |
| Plugins | `site/web/app/plugins` | `web/app/plugins` |
| Uploads | `site/web/app/uploads` | `web/app/uploads` |

**Note:** Replace `example.com` and `your-theme` with your actual domain and theme name.

### Essential Commands

```bash
# Access VM shell
trellis vm shell

# Run WP-CLI command
trellis vm shell --workdir /srv/www/example.com/current -- wp <command> --path=web/wp

# List pages
wp post list --post_type=page --path=web/wp

# Get page details
wp post get <ID> --path=web/wp

# Update page
wp post update <ID> --post_title="New Title" --path=web/wp

# Delete page
wp post delete <ID> --force --path=web/wp

# Flush cache
wp cache flush --path=web/wp
```

---

## Adding Patterns to Existing Pages

This section covers how to update existing pages with block patterns, useful for pattern showcase pages or major content updates.

### Method 1: Update Page via Trellis VM (Local)

**Use case:** Adding all theme patterns to a showcase page on local development site.

#### Step 1: Find the Page ID

```bash
# List pages to find the ID
trellis vm shell --workdir /srv/www/demo.example.com/current -- \
  wp post list --post_type=page --url=https://demo.example.test/ \
  --fields=ID,post_title,post_name --path=web/wp
```

Example output:
```
ID    post_title                post_name
100   89+ Professional Patterns  patterns
1848  Heroes                     heroes
```

#### Step 2: Create Content File in VM

Create the HTML content file directly in the Trellis VM's `/tmp` directory:

```bash
trellis vm shell --workdir /srv/www/demo.example.com/current -- bash << 'VMEOF'
cat > /tmp/page-content.html << 'EOF'
<!-- wp:heading {"textAlign":"center","fontSize":"xxx-large"} -->
<h2 class="wp-block-heading has-text-align-center has-xxx-large-font-size">Hero Patterns</h2>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","fontSize":"medium"} -->
<p class="has-text-align-center has-medium-font-size">Explore all hero patterns available in the theme.</p>
<!-- /wp:paragraph -->

<!-- wp:spacer {"height":"60px"} -->
<div style="height:60px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:pattern {"slug":"elayne/hero-modern-dark"} /-->

<!-- wp:spacer {"height":"40px"} -->
<div style="height:40px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:pattern {"slug":"elayne/hero-modern-light"} /-->
EOF

# Update the page with content
CONTENT=$(cat /tmp/page-content.html)
wp post update 1848 --post_content="$CONTENT" --url=https://demo.imagewize.test/ --path=web/wp

# Verify the update
wp post get 1848 --url=https://demo.imagewize.test/ --fields=ID,post_title,post_status --path=web/wp
VMEOF
```

**Important Notes:**
- Use heredoc with quoted delimiters (`'EOF'`) to prevent variable expansion
- The content file is created in VM's `/tmp` directory (not host machine)
- Pattern slugs must match your theme's registered patterns (e.g., `elayne/hero-modern-dark`)
- For multisite, always include `--url=https://yoursite.test/` parameter

#### Step 3: Verify in Browser

Visit the updated page to confirm patterns are displaying correctly:
```
https://demo.imagewize.test/heroes/
```

### Method 2: Batch Add Patterns by Category

**Use case:** Creating a comprehensive patterns page organized by category.

```bash
trellis vm shell --workdir /srv/www/demo.example.com/current -- bash << 'VMEOF'
cat > /tmp/patterns-showcase.html << 'EOF'
<!-- wp:heading {"textAlign":"center","fontSize":"xxx-large"} -->
<h2 class="wp-block-heading has-text-align-center has-xxx-large-font-size">89+ Professional Patterns</h2>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","fontSize":"medium"} -->
<p class="has-text-align-center has-medium-font-size">Explore all professionally designed patterns organized by category.</p>
<!-- /wp:paragraph -->

<!-- wp:spacer {"height":"60px"} -->
<div style="height:60px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:heading {"level":2,"fontSize":"xx-large"} -->
<h2 class="wp-block-heading has-xx-large-font-size">Hero Sections (4)</h2>
<!-- /wp:heading -->

<!-- wp:paragraph {"fontSize":"base"} -->
<p class="has-base-font-size">Powerful first impressions with full-width hero patterns.</p>
<!-- /wp:paragraph -->

<!-- wp:spacer {"height":"40px"} -->
<div style="height:40px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:pattern {"slug":"elayne/hero-modern-dark"} /-->
<!-- wp:pattern {"slug":"elayne/hero-modern-light"} /-->
<!-- wp:pattern {"slug":"elayne/hero-two-tone"} /-->
<!-- wp:pattern {"slug":"elayne/hero-with-cta"} /-->

<!-- Add more categories and patterns... -->
EOF

CONTENT=$(cat /tmp/patterns-showcase.html)
wp post update 100 --post_content="$CONTENT" --url=https://demo.imagewize.test/ --path=web/wp
VMEOF
```

### Method 3: Finding Pattern Slugs

To discover available patterns in your theme:

```bash
# Find all pattern files
find /path/to/theme/patterns -name "*.php" -type f ! -name "template-*" | sort

# Extract pattern slugs from PHP files
grep -h "Slug:" /path/to/theme/patterns/*.php | awk '{print $3}'

# For Elayne theme example:
find ~/code/example.com/demo/web/app/themes/elayne/patterns \
  -name "*.php" -type f ! -name "template-*" ! -name "header-*" ! -name "footer-*" \
  -exec basename {} .php \;
```

### Real-World Example: Elayne Theme Pattern Showcase

Complete example updating two pages on Elayne demo site:

**1. Heroes page (ID: 1848) - Show all hero patterns:**
```bash
trellis vm shell --workdir /srv/www/demo.example.com/current -- bash << 'VMEOF'
cat > /tmp/heroes-content.html << 'EOF'
<!-- wp:heading {"textAlign":"center","fontSize":"xxx-large"} -->
<h2 class="wp-block-heading has-text-align-center has-xxx-large-font-size">Hero Patterns</h2>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center","fontSize":"medium"} -->
<p class="has-text-align-center has-medium-font-size">Explore all hero patterns available in the Elayne theme. Each pattern is designed to make a strong first impression.</p>
<!-- /wp:paragraph -->

<!-- wp:spacer {"height":"60px"} -->
<div style="height:60px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:pattern {"slug":"elayne/hero-modern-dark"} /-->
<!-- wp:spacer {"height":"40px"} -->
<div style="height:40px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:pattern {"slug":"elayne/hero-modern-light"} /-->
<!-- wp:spacer {"height":"40px"} -->
<div style="height:40px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:pattern {"slug":"elayne/hero-two-tone"} /-->
<!-- wp:spacer {"height":"40px"} -->
<div style="height:40px" aria-hidden="true" class="wp-block-spacer"></div>
<!-- /wp:spacer -->

<!-- wp:pattern {"slug":"elayne/hero-with-cta"} /-->
EOF

CONTENT=$(cat /tmp/heroes-content.html)
wp post update 1848 --post_content="$CONTENT" --url=https://demo.imagewize.test/ --path=web/wp
VMEOF
```

**2. Patterns page (ID: 100) - Show all patterns by category:**
```bash
# See full example in trellis-tools/content-creation/examples/elayne-patterns-showcase.html
# This would include all 24+ patterns organized into categories:
# - Hero Sections (4)
# - Features & Services (3)
# - Testimonials (3)
# - Statistics (2)
# - Call-to-Action (1)
# - Contact (2)
# - Team (1)
# - Blog & Posts (5)
# - Support & Information (2)
# - Pricing (1)
```

### Tips for Pattern Pages

1. **Use consistent spacing:**
   - 60-80px spacers between sections
   - 40px spacers between patterns in same category

2. **Add descriptive headings:**
   - Category heading (H2, xx-large font)
   - Category description (paragraph, base font)

3. **Pattern slugs must be exact:**
   - Format: `theme-name/pattern-slug` (e.g., `elayne/hero-modern-dark`)
   - Check theme's patterns directory for correct slugs
   - Case-sensitive!

4. **Test on mobile:**
   - Patterns should be responsive by default
   - Verify spacing and layout on different screen sizes

### Troubleshooting Pattern Updates

**Problem:** Pattern not rendering
```bash
# Verify pattern slug exists
grep -r "Slug: elayne/hero-modern-dark" ~/code/example.com/demo/web/app/themes/elayne/patterns/

# Check pattern is registered (from VM)
trellis vm shell --workdir /srv/www/demo.example.com/current -- \
  wp block-pattern list --url=https://demo.example.test/ --path=web/wp
```

**Problem:** Content not updating
```bash
# Flush WordPress cache
trellis vm shell --workdir /srv/www/demo.example.com/current -- \
  wp cache flush --url=https://demo.example.test/ --path=web/wp

# For multisite, flush network cache
trellis vm shell --workdir /srv/www/demo.example.com/current -- \
  wp cache flush --network --path=web/wp
```

**Problem:** Page shows old content
- Clear browser cache (Cmd+Shift+R)
- Disable page caching plugin temporarily
- Check WordPress development mode is enabled for theme work

---

**Document Version:** 1.1
**Last Updated:** December 14, 2025
**Author:** Claude Code Documentation
**Status:** Production Ready
