# WordPress DB Template Override — WP-CLI

When a block theme template (e.g. `single-product.html`) is edited in the Site Editor, WordPress saves the modified version as a `wp_template` post in the database. This DB copy takes precedence over the file on disk, so changes to theme PHP pattern files (or template `.html` files) are silently ignored.

## Detecting the problem

Symptoms:
- You edited a PHP block pattern file but the frontend still shows old block markup.
- `data-image-sizing`, `data-block-name`, or other rendered attributes still reflect old values after a cache flush.
- `wp cache flush` does not help.

Confirm a DB override exists:

```bash
# List all DB-stored templates for a site (or multisite subsite)
wp post list --post_type=wp_template \
  --fields=ID,post_name,post_status \
  --path=web/wp \
  --url=https://example.com/store/

# Inspect the stored content for a specific template
wp post get <ID> --field=post_content --path=web/wp --url=https://example.com/store/ | head -100
```

If the output contains static block markup (rather than a `<!-- wp:pattern {"slug":"..."} /-->` reference), the pattern was frozen/inlined when the template was saved.

## Option A — Delete the DB override (restores file-system template)

Use this when you want the theme file to fully control the template:

```bash
wp post delete <ID> --force --path=web/wp --url=https://example.com/store/
```

After deletion, WordPress falls back to the theme's `.html` template file, and dynamic `<!-- wp:pattern -->` references are re-evaluated from PHP on each request.

## Option B — Surgically update the DB template content

Use this when only part of the template needs updating (the DB copy has other customisations worth keeping):

```bash
wp eval '
$post_id = <ID>;
$content = get_post($post_id)->post_content;

$old = "<!-- wp:woocommerce/product-image {\"showSaleBadge\":false,\"imageSizing\":\"thumbnail\",\"isDescendentOfQueryLoop\":true} -->\n<!-- wp:woocommerce/product-sale-badge {\"align\":\"right\"} /-->\n<!-- /wp:woocommerce/product-image -->";

$new = "<!-- wp:woocommerce/product-image {\"showSaleBadge\":false,\"isDescendentOfQueryLoop\":true,\"aspectRatio\":\"3/4\"} -->\n<!-- wp:woocommerce/product-sale-badge {\"isDescendentOfQueryLoop\":true,\"align\":\"right\"} /-->\n<!-- /wp:woocommerce/product-image -->\n\n<!-- wp:woocommerce/product-button {\"textAlign\":\"center\",\"width\":100,\"isDescendentOfQueryLoop\":true} /-->";

if (strpos($content, $old) !== false) {
    $new_content = str_replace($old, $new, $content);
    wp_update_post(["ID" => $post_id, "post_content" => $new_content]);
    echo "Updated successfully\n";
} else {
    echo "Old string not found — check the content manually\n";
    echo substr($content, strpos($content, "product-image"), 300) . "\n";
}
' --path=web/wp --url=https://example.com/store/
```

Flush the cache afterwards:

```bash
wp cache flush --path=web/wp --url=https://example.com/store/
```

## Trellis VM variant

Prefix all `wp` commands with the Trellis shell wrapper:

```bash
trellis vm shell --workdir /srv/www/demo.imagewize.com/current -- \
  wp post list --post_type=wp_template --fields=ID,post_name,post_status \
  --path=web/wp --url=http://demo.imagewize.test/store/

trellis vm shell --workdir /srv/www/demo.imagewize.com/current -- \
  wp post delete <ID> --force --path=web/wp --url=http://demo.imagewize.test/store/

trellis vm shell --workdir /srv/www/demo.imagewize.com/current -- \
  wp cache flush --path=web/wp --url=http://demo.imagewize.test/store/
```

## Preventing re-freeze

Once you delete or repair the DB override, avoid editing the template in the Site Editor unless you intend to create a new DB override. Prefer editing the theme `.html` template file or the referenced PHP pattern files directly.

For development, enable `WP_DEVELOPMENT_MODE=theme` in `config/environments/development.php` (Bedrock) so WordPress skips pattern caching and picks up PHP file changes immediately.
