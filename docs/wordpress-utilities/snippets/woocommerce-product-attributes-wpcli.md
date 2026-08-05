# WooCommerce Product Attributes via WP-CLI

Create, manage, and populate WooCommerce product attributes (color, size, material, etc.) from the command line using WP-CLI's WooCommerce extension.

## Prerequisites

- WooCommerce installed and active
- WP-CLI with WooCommerce support (`wp wc` commands available)
- An existing WordPress admin user (passed via `--user=admin`)

---

## Create a Product Attribute

### Local development (Trellis VM)

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test wc product_attribute create \
    --name="Leather Colour" \
    --slug="pa_leather-colour" \
    --type="select" \
    --user=admin \
    --path=web/wp 2>&1
```

### Production / staging (via SSH)

```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  wp wc product_attribute create \
    --name='Leather Colour' \
    --slug='pa_leather-colour' \
    --type='select' \
    --user=admin \
    --path=web/wp"
```

---

## Common Attribute Examples

```bash
# Color
wp wc product_attribute create --name="Color" --slug="pa_color" --type="select" --user=admin --path=web/wp

# Size
wp wc product_attribute create --name="Size" --slug="pa_size" --type="select" --user=admin --path=web/wp

# Material
wp wc product_attribute create --name="Material" --slug="pa_material" --type="select" --user=admin --path=web/wp

# Leather Colour (custom niche attribute)
wp wc product_attribute create --name="Leather Colour" --slug="pa_leather-colour" --type="select" --user=admin --path=web/wp

# Width
wp wc product_attribute create --name="Width" --slug="pa_width" --type="select" --user=admin --path=web/wp
```

---

## Add Terms (Values) to an Attribute

Use `wp term create <taxonomy> "<value>"` with the attribute's taxonomy slug (`pa_` prefix).
Omitting `--url` targets the **main site** — always pass `--url` for a sub-site store.

### Regular site

```bash
# Direct WP-CLI
wp term create pa_leather-colour "Black" --user=admin --path=web/wp
wp term create pa_style "A4 with Notepad" --user=admin --path=web/wp

# Via Trellis VM
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp term create pa_leather-colour "Black" --user=admin --path=web/wp 2>&1
```

### Sub-site (WooCommerce store at `/store`)

Without `--url` the term lands on the main site, not the store — this is the most common mistake.

```bash
# Direct WP-CLI
wp --url=http://example.test/store term create pa_leather-colour "Black" --user=admin --path=web/wp
wp --url=http://example.test/store term create pa_style "A4 with Notepad" --user=admin --path=web/wp

# Via Trellis VM
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store term create pa_leather-colour "Black" \
    --user=admin --path=web/wp 2>&1
```

---

## List Attributes and Terms

```bash
# List all global product attributes
wp wc product_attribute list --user=admin --path=web/wp --format=table

# List all terms for attribute ID 1
wp wc product_attribute_term list 1 --user=admin --path=web/wp --format=table
```

---

## Delete an Attribute

```bash
# Delete attribute by ID (also removes all its terms)
wp wc product_attribute delete 1 --user=admin --path=web/wp
```

---

## Trellis VM — Full Workflow Example

Create a "Leather Colour" attribute and populate it with values, all in one session:

```bash
cd /path/to/trellis

# 1. Create the attribute
trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test wc product_attribute create \
    --name="Leather Colour" --slug="pa_leather-colour" --type="select" \
    --user=admin --path=web/wp 2>&1

# 2. Get the new attribute ID
trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test wc product_attribute list \
    --user=admin --path=web/wp --format=table 2>&1

# 3. Add terms — use --url to target sub-site store, omit for main site
for TERM in "Black" "Brown" "Tan" "Burgundy" "Navy"; do
  trellis vm shell --workdir /srv/www/example.test/current -- \
    wp --url=http://example.test/store term create pa_leather-colour "$TERM" \
      --user=admin --path=web/wp 2>&1
done
```

---

## Create a Product Variation

Create a variation on an existing variable product. The number after `create` is the **parent product ID**.
Attributes must reference taxonomy slugs (`pa_` prefix) and values that already exist as terms.

### Sub-site via Trellis VM

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store wc product_variation create 36 \
    --attributes='[{"attribute": "pa_leather-colour", "value": "Tan"}, {"attribute": "pa_style", "value": "A4 Slim"}]' \
    --regular_price=99 \
    --user=admin \
    --path=web/wp 2>&1 | grep -E "Success|Error"
```

### With SKU and stock management

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store wc product_variation create 36 \
    --attributes='[{"attribute": "pa_leather-colour", "value": "Tan"}, {"attribute": "pa_style", "value": "A4 Slim"}]' \
    --regular_price=99 \
    --sku="PROD-36-TAN-A4SL" \
    --stock_quantity=10 \
    --manage_stock=true \
    --user=admin \
    --path=web/wp 2>&1 | grep -E "Success|Error"
```

> The `| grep -E "Success|Error"` tail strips the limactl/trellis noise and shows only the result line.

---

## Update a Product Variation

Update an existing product variation by post ID.

> **Multisite warning:** Products and variations live on the sub-site, not the main site.
> Always use `--url=http://example.test/store` (with the store path).
> Omitting `/store` targets the main site — WP-CLI returns `Warning: Invalid post ID`
> because the post ID does not exist there.

### Sub-site via Trellis VM (correct)

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store post update 36 \
    --post_type=product_variation --path=web/wp 2>&1
```

### Main site — will fail with "Invalid post ID" (wrong)

```bash
# Missing /store in --url — WP-CLI targets main site where the post doesn't exist
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test post update 36 \
    --post_type=product --path=web/wp 2>&1
# Warning: Invalid post ID.
```

### Update variation meta (price, stock, SKU) — sub-site

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store post meta update 36 _price "29.99" --path=web/wp 2>&1
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store post meta update 36 _regular_price "29.99" --path=web/wp 2>&1
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store post meta update 36 _stock_status "instock" --path=web/wp 2>&1
```

---

## Direct Database Queries via `wp db query`

Use `wp db query` for raw SQL when WP-CLI commands are not enough.

> **Common mistake — double `wp`:** Writing `wp --url=... wp db query` causes
> `Error: 'wp' is not a registered wp command`. The `--url` flag belongs to the
> same `wp` invocation as the subcommand — never repeat `wp`.

```bash
# Wrong — double wp
wp --url=http://example.test/store wp db query "SELECT ..." --path=web/wp

# Correct
wp --url=http://example.test/store db query "SELECT ..." --path=web/wp
```

> **Multisite table prefix:** Sub-site tables use a numeric prefix (`wp_2_posts`,
> `wp_10_posts`, etc.), not `wp_posts`. Query `wp_blogs` to find the right site ID,
> then derive the prefix as `wp_<id>_`.

```bash
# Find the site ID and URL for all sub-sites
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store db query "SELECT blog_id, domain, path FROM wp_blogs" \
    --path=web/wp 2>&1

# Update a post on sub-site with table prefix wp_10_
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store db query \
    "UPDATE wp_10_posts SET post_type = 'product' WHERE ID = 36" \
    --path=web/wp 2>&1

# Check a post type on sub-site
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store post get 36 --field=post_type --path=web/wp 2>&1
```

---

## List WooCommerce Products

### Local development (Trellis VM)

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store post list \
    --post_type='product' \
    --format=csv \
    --path=web/wp 2>&1
```

### With additional fields

```bash
cd /path/to/trellis && trellis vm shell --workdir /srv/www/example.test/current -- \
  wp --url=http://example.test/store post list \
    --post_type='product' \
    --fields=ID,post_title,post_status \
    --format=table \
    --path=web/wp 2>&1
```

### Production (via SSH)

```bash
ssh web@example.com "cd /srv/www/example.com/current && \
  wp post list --post_type='product' --format=csv --path=web/wp"
```

---

## Notes

- **Multisite:** All WooCommerce operations (products, variations, terms) must target the sub-site with `--url=http://example.test/store`. Without it, WP-CLI targets the main site and returns `Warning: Invalid post ID` or silently creates terms in the wrong place.
- Slugs must be prefixed with `pa_` (WooCommerce convention) when created via `wp wc product_attribute create`.
- The `--type` option accepts `select` (dropdown) or `button` (swatches via plugins).
- `--user` must be a valid WooCommerce-capable admin login; numeric user IDs also work.
- The `2>&1` redirect captures WP-CLI warnings alongside output — useful when piping or logging.

## See Also

- [WP-CLI WooCommerce commands](https://github.com/woocommerce/woocommerce/wiki/WC-CLI-Overview)
- [Admin User Creation via WP-CLI](admin-user-creation-wpcli.md)
