# WordPress Snippets

Small, self-contained snippets for WordPress. PHP snippets are ready to copy into `functions.php` or a custom plugin. Shell scripts can be run directly for diagnostics.

## Available Snippets

### [admin-user-creation.php](admin-user-creation.php)

Create a temporary administrator user via `functions.php`. **REMOVE THIS CODE IMMEDIATELY after the user is created** for security.

**Features:**
- One-time user creation on page load
- Checks if user already exists before creating
- Uses placeholder values that must be replaced (prevents accidental commits)
- Logs creation result to error log
- Safety check: aborts if placeholder values aren't replaced

**Security Warning:**
- NEVER commit this to version control
- Remove the code immediately after first login
- WP-CLI method (`admin-user-creation-wpcli.md`) is preferred when available

**Setup:**
1. Copy into your theme's `functions.php` or a mu-plugin
2. Replace `REPLACE_ME_USERNAME`, `REPLACE_ME@examp.le`, and `REPLACE_ME_PASSWORD`
3. Load any page on your site once to trigger creation
4. Log in with the new credentials
5. **IMMEDIATELY remove this code from functions.php**

### [admin-user-creation-wpcli.md](admin-user-creation-wpcli.md)

**Recommended approach** for creating WordPress administrator users safely from the command line.

**Features:**
- No code to add/remove from WordPress files
- Credentials aren't stored in files
- Full control via command line
- Secure random password generation examples
- Batch user creation from CSV files
- Emergency lockout recovery workflow

**Quick Start:**
```bash
wp user create temp_admin temp@example.com --role=administrator --user_pass="$(openssl rand -base64 16)"
```

### [post-expiry-noindex.php](post-expiry-noindex.php)

Auto-noindex posts past their expiry date via Yoast SEO, evaluated in the site's configured WordPress timezone.

**Features:**
- Adds a "Noindex After Date" meta box to the post edit sidebar
- Hooks into Yoast's `wpseo_robots` filter — no manual Yoast config needed
- Expiry triggers at **midnight in the site's local timezone** (reads from Settings → General → Timezone), not UTC
- Scoped to specific categories — set `$expiry_categories` to limit which post categories are affected
- Outputs `noindex, follow` — removes from search results but keeps links crawlable

**Use Cases:**
- Race tips, event previews, or time-sensitive posts that should drop out of search results after the event
- Any content with a natural expiry date

**Dependencies:**
- Yoast SEO (free or premium)
- WordPress 5.3+ (`wp_timezone()` added in 5.3)

**Setup:**
1. Copy `post-expiry-noindex.php` into your child theme's `functions.php` (or a custom plugin)
2. Replace `$expiry_categories = [ 0 ]` with your actual category IDs
3. Edit any post — the "Noindex After Date" field appears in the sidebar under Post settings

### [webp-featured-image.md](webp-featured-image.md)

Converts images to WebP format optimized for WordPress featured images and Facebook Open Graph sharing. Uses the command `cwebp -q 82 -resize 800 419 image.jpg -o image.webp` to create 800×419 images that hit Facebook's 1.91:1 ratio requirement while fitting WordPress content columns (typically 645px wide).

**Features:**
- Single image and batch conversion examples
- Quality 82 for optimal balance of size and quality
- Metadata preservation option
- Nginx integration notes for automatic WebP serving

**Dependencies:**
- `webp` package (provides `cwebp` command)

**Setup:**
1. Install `cwebp` (see Installation section in the snippet)
2. Run the conversion command on your images
3. Use with Nginx `webp-avf.conf.j2` from `nginx/image-optimization/` for automatic serving
