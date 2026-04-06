# WordPress Snippets

Small, self-contained PHP snippets for WordPress themes and plugins. Each file is ready to copy into `functions.php` or a custom plugin with minimal adjustment.

## Available Snippets

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
