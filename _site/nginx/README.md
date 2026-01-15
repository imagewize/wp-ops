# Nginx Configuration Tools

Optimized Nginx configurations for WordPress sites running on [Roots Trellis](https://roots.io/trellis/), focusing on performance, image delivery, and SEO.

## Overview

This directory contains production-ready Nginx configurations for:

- **Browser Caching** - Static asset caching headers for improved page load times
- **Image Optimization** - Automatic WebP/AVIF content negotiation for modern browsers
- **URL Redirects** - SEO-friendly redirect management for migrations and permalink changes

## Directory Structure

```
nginx/
├── browser-caching/        # Browser caching headers for static assets
├── image-optimization/     # WebP/AVIF automatic serving
└── redirects/              # SEO redirect templates and examples
```

## Quick Start

### Prerequisites

- Trellis-managed WordPress site
- Nginx web server (included with Trellis)
- SSH access to server
- Basic understanding of Nginx configuration

### Common Deployment Pattern

1. **Copy configuration** to your Trellis project:
   ```bash
   # For site-specific configs
   cp nginx/image-optimization/nginx-includes/webp-avf.conf.j2 \
      ~/trellis/nginx-includes/

   # For global configs
   cp nginx/browser-caching/nginx-includes/all/assets-expiry.conf.j2 \
      ~/trellis/nginx-includes/all/
   ```

2. **Update Trellis configuration** in `group_vars/production/wordpress_sites.yml`:
   ```yaml
   wordpress_sites:
     example.com:
       nginx_includes:
         - nginx-includes/webp-avf.conf.j2
   ```

3. **Provision server** to apply changes:
   ```bash
   trellis provision --tags nginx-includes production
   ```

4. **Test configuration**:
   ```bash
   # Test Nginx syntax
   ssh web@example.com "sudo nginx -t"

   # Reload Nginx
   ssh web@example.com "sudo systemctl reload nginx"
   ```

---

## 1. Browser Caching

**Location:** `browser-caching/`

Implements HTTP caching headers for static assets to reduce server load and improve page performance.

### Features

- **Long-term caching** for static assets (1 year expiry)
- **File type coverage**:
  - Images: JPG, PNG, GIF, ICO, WebP, AVIF, SVG
  - Fonts: EOT, TTF, WOFF, WOFF2, OTF
  - Styles/Scripts: CSS, JS (including WordPress minified assets)
- **Cache validation** with ETag headers
- **Content negotiation** with Vary Accept headers
- **CSP headers** for SVG security
- **Performance optimization**: Disabled access logging for cached assets

### Configuration File

**`nginx-includes/all/assets-expiry.conf.j2`** (45 lines)
- Applies to all sites automatically when placed in `nginx-includes/all/`
- Uses Jinja2 templating for Trellis compatibility

### Performance Benefits

- Up to **70% bandwidth reduction** for repeat visitors
- Faster page loads (assets served from browser cache)
- Reduced server CPU/memory usage

### Usage

```bash
# Test cache headers with curl
curl -I https://example.com/wp-content/themes/theme/style.css

# Expected output:
# Cache-Control: public, max-age=31536000
# Expires: [one year from now]
# ETag: "..."
```

**See also:** [browser-caching/README.md](browser-caching/README.md) for detailed documentation.

---

## 2. Image Optimization

**Location:** `image-optimization/`

Automatic WebP and AVIF image serving based on browser support, with fallback to original formats.

### Features

- **Automatic format detection** from HTTP Accept headers
- **Priority order**: AVIF → WebP → Original
- **Browser support detection**:
  - AVIF: Chrome 85+, Firefox 93+, Safari 16+
  - WebP: Chrome, Firefox, Edge, Safari 14+
- **Fallback mechanism** for older browsers
- **No WordPress plugin required** (server-side implementation)
- **Transparent to WordPress** (original URLs work unchanged)

### Configuration File

**`nginx-includes/webp-avf.conf.j2`** (27 lines)
- Targets `/app/uploads/` directory only
- Uses HTTP Accept header mapping
- Rewrites URLs conditionally based on file existence
- Includes Vary header for proper CDN caching

### Image Conversion Tools

The directory includes comprehensive guides for:

- **ImageMagick** - Resize, crop, and optimize images
- **cwebp** - Convert to WebP format (quality 75-85 recommended)
- **cavif** - Convert to AVIF format (quality 70-80 recommended)
- **Batch processing scripts** for bulk conversion
- **Automation with cron** for ongoing optimization

### File Size Savings

- **WebP**: 25-35% smaller than JPEG
- **AVIF**: 50%+ smaller than JPEG
- Example: 80KB JPEG → 50KB WebP → 30KB AVIF

### Usage

```bash
# Convert single image to WebP
cwebp -q 80 image.jpg -o image.jpg.webp

# Convert to AVIF
cavif --quality 80 image.jpg

# Batch conversion
find uploads/ -name "*.jpg" -exec cwebp -q 80 {} -o {}.webp \;
```

**See also:**
- [image-optimization/README.md](image-optimization/README.md) - Nginx configuration and WordPress plugins
- [image-optimization/RESIZE-AND-CONVERSION.md](image-optimization/RESIZE-AND-CONVERSION.md) - Complete ImageMagick and conversion guide

---

## 3. URL Redirects

**Location:** `redirects/`

SEO-friendly redirect templates for URL migrations, permalink changes, and canonical URL enforcement.

### Features

- **Redirect types**: 301 (permanent), 302 (temporary), 303, 307, 308
- **Pattern matching**: Exact (`=`), regex (`~`), location blocks
- **Query string preservation** with `?` operator
- **Bulk redirects** (handles 10,000+ redirects efficiently - O(1) lookup)
- **WordPress-specific patterns**:
  - Permalink structure changes
  - Category/tag migrations
  - Custom post type URL updates
  - WWW/non-WWW canonicalization
  - HTTP → HTTPS enforcement

### Example Templates

**Generic redirects:**
- `ssl-redirects.conf.j2` - HTTPS enforcement for login/admin/checkout
- `wordpress-permalinks.conf.j2` - Common permalink migration patterns

**Real-world example:**
- `example.com/seo-redirects.conf.j2` - Production redirect patterns

### Configuration Examples

```nginx
# Exact match redirect (fastest)
location = /old-page/ {
    return 301 /new-page/;
}

# Regex pattern with query string preservation
location ~ ^/blog/(.*)$ {
    return 301 /news/$1$is_args$args;
}

# Category slug change
rewrite ^/category/old-slug/(.*)$ /category/new-slug/$1 permanent;
```

### Deployment

Site-specific configuration in `wordpress_sites.yml`:
```yaml
nginx_includes:
  - nginx-includes/seo-redirects.conf.j2
```

### Testing Redirects

```bash
# Test redirect with curl
curl -I https://example.com/old-url/

# Expected output:
# HTTP/2 301
# Location: https://example.com/new-url/

# Automated testing script
while IFS=',' read old new; do
  curl -Isw "%{http_code} %{redirect_url}\n" "$old" | grep -q "$new" && echo "✓ $old" || echo "✗ $old"
done < redirects.csv
```

### Finding URLs to Redirect

- **Google Search Console** - 404 errors report
- **Server logs** - Analyze 404s with `grep "\" 404 " access.log`
- **Screaming Frog** - Crawl site for broken links
- **Old sitemaps** - Compare old vs new URL structure

**See also:** [redirects/README.md](redirects/README.md) for comprehensive redirect management guide.

---

## Configuration Scopes

Nginx includes can be deployed at different scopes:

### Global (All Sites)

**Directory:** `nginx-includes/all/`

Files here apply to all sites on the server automatically.

**Use for:**
- Browser caching headers
- Security headers
- Rate limiting
- Default error pages

**Example:**
```bash
cp browser-caching/nginx-includes/all/assets-expiry.conf.j2 \
   ~/trellis/nginx-includes/all/
```

### Site-Specific

**Directory:** `nginx-includes/`

Files referenced in individual site configurations.

**Use for:**
- Image optimization (not all sites may need it)
- Site-specific redirects
- Custom rewrites
- Domain-specific rules

**Configuration in `wordpress_sites.yml`:**
```yaml
wordpress_sites:
  example.com:
    nginx_includes:
      - nginx-includes/webp-avf.conf.j2
      - nginx-includes/seo-redirects.conf.j2
```

---

## Deployment Workflow

### 1. Copy Configuration Files

```bash
# Navigate to your Trellis project
cd ~/trellis

# Copy desired configs
cp ../wp-ops/nginx/image-optimization/nginx-includes/webp-avf.conf.j2 \
   nginx-includes/

cp ../wp-ops/nginx/browser-caching/nginx-includes/all/assets-expiry.conf.j2 \
   nginx-includes/all/
```

### 2. Update Site Configuration

Edit `group_vars/production/wordpress_sites.yml`:

```yaml
wordpress_sites:
  example.com:
    # ... existing config ...
    nginx_includes:
      - nginx-includes/webp-avf.conf.j2
```

### 3. Test Configuration Locally

```bash
# Provision development environment first
trellis provision development

# SSH and test
trellis vm shell
sudo nginx -t
```

### 4. Deploy to Production

```bash
# Provision with nginx-includes tag only (fast)
trellis provision --tags nginx-includes production

# Or full provision if other changes needed
trellis provision production
```

### 5. Verify Deployment

```bash
# Check Nginx syntax
ssh web@example.com "sudo nginx -t"

# Test specific configurations
curl -I https://example.com/image.jpg
curl -I https://example.com/style.css

# Check redirects
curl -I https://example.com/old-url/
```

---

## Troubleshooting

### Common Issues

1. **Configuration not applied**
   - Verify file is in correct `nginx-includes/` directory
   - Check `wordpress_sites.yml` references correct file path
   - Re-provision with `--tags nginx-includes`

2. **Nginx syntax errors**
   - Test with `sudo nginx -t`
   - Check for typos in `.conf.j2` files
   - Verify Jinja2 template syntax
   - Review Nginx error log: `tail -f /var/log/nginx/error.log`

3. **Redirects creating loops**
   - Check for circular redirects (A → B → A)
   - Use exact match (`location =`) when possible
   - Test redirects in isolation before combining

4. **Images not serving WebP/AVIF**
   - Verify files exist with correct naming (e.g., `image.jpg.webp`)
   - Check browser Accept headers: `curl -H "Accept: image/webp" https://example.com/image.jpg`
   - Review rewrite log: Enable `rewrite_log on;` temporarily

5. **Cache headers not appearing**
   - Clear browser cache completely
   - Test with `curl -I` (bypasses browser cache)
   - Verify file extension matches config patterns
   - Check for conflicting WordPress plugins

### Testing Commands

```bash
# Test cache headers
curl -I https://example.com/wp-content/themes/theme/style.css | grep -i cache

# Test WebP serving
curl -H "Accept: image/webp" -I https://example.com/image.jpg | grep -i location

# Test AVIF serving
curl -H "Accept: image/avif" -I https://example.com/image.jpg | grep -i location

# Test redirect
curl -I https://example.com/old-url/ | grep -i location

# Check Nginx includes are loaded
ssh web@example.com "grep -r 'include.*nginx-includes' /etc/nginx/sites-enabled/"
```

---

## Performance Impact

### Browser Caching

- **First visit**: Normal load time
- **Repeat visits**: 50-70% faster (assets from cache)
- **Bandwidth savings**: Up to 70% for cached assets
- **Server load**: Reduced CPU/memory for static files

### Image Optimization

- **File size reduction**:
  - WebP: 25-35% smaller
  - AVIF: 50%+ smaller
- **Page load improvement**: 20-40% faster (varies by image count)
- **SEO benefit**: Improved Core Web Vitals (LCP, CLS)
- **Mobile benefit**: Critical for mobile users on slower connections

### Redirects

- **Performance**: O(1) lookup time (even with 10,000+ redirects)
- **Minimal overhead**: ~1ms per redirect
- **SEO benefit**: Preserves link equity and rankings
- **User experience**: Seamless navigation to new URLs

---

## Best Practices

1. **Test in development first** - Always test configs in Trellis development/staging before production
2. **Use version control** - Commit all Nginx configs to git
3. **Document custom configs** - Add comments explaining purpose and date
4. **Monitor after deployment** - Check logs for errors after provisioning
5. **Backup before changes** - Keep previous working configs accessible
6. **Use specific tags** - Provision with `--tags nginx-includes` for faster deployments
7. **Validate before reload** - Always run `nginx -t` before reloading
8. **Test edge cases** - Verify behavior with and without trailing slashes, query strings, etc.

---

## Integration with Trellis

All configurations use Jinja2 templating (`.conf.j2` extension) for Trellis compatibility:

- **Template variables**: Can use Trellis variables like `{{ site_name }}`
- **Conditional logic**: Can use Jinja2 conditionals for environment-specific configs
- **File deployment**: Trellis copies configs to `/etc/nginx/includes.d/`
- **Automatic reload**: Trellis reloads Nginx after provisioning
- **Validation**: Trellis validates Nginx syntax before applying

### Trellis Directory Mapping

```
Trellis project:           Production server:
nginx-includes/all/   →    /etc/nginx/includes.d/all/
nginx-includes/       →    /etc/nginx/includes.d/example.com/
```

---

## Further Reading

- [Nginx Documentation](https://nginx.org/en/docs/)
- [Trellis Nginx Configuration](https://roots.io/trellis/docs/nginx/)
- [ImageMagick Documentation](https://imagemagick.org/index.php)
- [WebP Conversion Guide](https://developers.google.com/speed/webp)
- [AVIF Format Specification](https://aomediacodec.github.io/av1-avif/)
- [HTTP Caching Best Practices](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching)

---

## Contributing

When adding new Nginx configurations:

1. Use `.conf.j2` extension for Trellis compatibility
2. Include comments explaining functionality
3. Test in development environment first
4. Document in subdirectory README
5. Provide usage examples
6. Include troubleshooting guidance
7. Consider performance and security implications
