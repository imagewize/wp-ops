# Post Expiry Noindex — WP-CLI Checks

Diagnostic commands to verify the post expiry noindex feature is working correctly.
Run these on the server via SSH from the WordPress root directory.

## 1. Check the expiry date meta is saved

```bash
wp post meta get {POST_ID} _post_expiry_date
```

Expected output: a date string in `YYYY-MM-DD` format, e.g. `2026-04-07`.

---

## 2. Check post category membership

```bash
wp post term list {POST_ID} category --fields=term_id,name
```

Confirm the post is in one of the categories listed in `$expiry_categories` in your `functions.php`.

---

## 3. Verify the full expiry logic

Bypasses `is_singular()` (which is always false in WP-CLI context) and tests the
category match, meta value, and timezone-aware expiry check directly:

```bash
wp eval '
$post_id = {POST_ID};
$cats = [{CAT_IDS}];
$in_cat = has_term($cats, "category", $post_id);
$expiry = get_post_meta($post_id, "_post_expiry_date", true);
$tz = wp_timezone();
$now = new DateTime("now", $tz);
$exp = new DateTime($expiry . " 00:00:00", $tz);
echo "In category: " . ($in_cat ? "yes" : "no") . "\n";
echo "Expiry date: $expiry\n";
echo "Expired: " . ($exp < $now ? "yes" : "no") . "\n";
'
```

Replace `{POST_ID}` with the post ID and `{CAT_IDS}` with a comma-separated list of
category IDs, e.g. `5734, 5739, 5827, 5874`.

All three lines should read `yes` / a valid date / `yes` for noindex to fire on the front-end.

---

## Notes

- The Yoast SEO dropdown in wp-admin always shows the stored setting ("Yes — default for Posts").
  It does **not** reflect the `wpseo_robots` filter override. Check the front-end `<meta name="robots">`
  tag instead.
- On staging with sitewide noindex enabled, the meta tag will show `noindex` regardless.
  Use check #3 above to confirm the logic fires correctly without relying on front-end output.
- `is_singular()` always returns false in `wp eval` — that is expected. Check #3 works around this.
