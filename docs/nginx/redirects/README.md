# Nginx Redirect Configuration

Trellis nginx-includes templates for managing SEO redirects and URL rewrites.

## Overview

This directory contains example nginx redirect configurations that can be used in Trellis projects. Redirects are managed via nginx-includes templates that are deployed during provisioning.

## Directory Structure

```
redirects/
├── README.md                           # This file
└── examples/
    ├── example.com/
    │   └── seo-redirects.conf.j2       # SEO redirect examples
    └── generic/
        ├── wordpress-permalinks.conf.j2 # Common WordPress redirects
        └── ssl-redirects.conf.j2        # HTTP to HTTPS redirects
```

## How Nginx Includes Work in Trellis

Trellis supports nginx-includes templates that are deployed to the server during provisioning. These templates are stored in your project's `trellis/nginx-includes/` directory.

### Include Scopes

1. **Global includes** (`nginx-includes/all/`): Apply to all sites
2. **Site-specific includes** (`nginx-includes/{site-key}/`): Apply to specific sites only

### Directory Structure in Your Project

```
trellis/
└── nginx-includes/
    ├── all/                          # Global includes (all sites)
    │   └── assets-expiry.conf.j2     # Browser caching rules
    └── example.com/                # Site-specific includes
        └── seo-redirects.conf.j2     # SEO redirects (example.com only)
```

### Deployment Location

Templates are deployed to `/etc/nginx/includes.d/` on the server:

```
/etc/nginx/includes.d/
├── all/
│   └── assets-expiry.conf         # Rendered from all/assets-expiry.conf.j2
└── example.com/
    └── seo-redirects.conf         # Rendered from example.com/seo-redirects.conf.j2
```

## Using the Examples

### 1. Copy Example to Your Project

```bash
# Copy site-specific redirect template
cp ~/code/trellis-tools/redirects/examples/example.com/seo-redirects.conf.j2 \
   ~/code/yourproject.com/trellis/nginx-includes/yoursite.com/

# Or copy to global includes (applies to all sites)
cp ~/code/trellis-tools/redirects/examples/generic/wordpress-permalinks.conf.j2 \
   ~/code/yourproject.com/trellis/nginx-includes/all/
```

### 2. Edit the Template

Edit the `.conf.j2` file to add your site-specific redirects:

```nginx
# SEO Redirects - Fix 404 Errors
# Date: 2025-11-30

# Old URL structure -> New URL structure
location = /old-page/ {
    return 301 /new-page/;
}

# Old category -> New category
location = /category/old-category/ {
    return 301 /category/new-category/;
}
```

### 3. Deploy to Production

```bash
cd trellis

# Deploy nginx-includes only (fast)
trellis provision --tags nginx-includes production

# Or deploy with full wordpress-setup
trellis provision --tags wordpress-setup production
```

### 4. Verify Deployment

```bash
# Check the config file was deployed
ssh root@yoursite.com "cat /etc/nginx/includes.d/yoursite.com/seo-redirects.conf"

# Test nginx config is valid
ssh root@yoursite.com "nginx -t"

# Test a redirect
curl -I https://yoursite.com/old-url
# Should show: HTTP/2 301
# Location: https://yoursite.com/new-url/
```

## Redirect Best Practices

### 1. Use Permanent Redirects (301)

```nginx
# ✅ Good - Permanent redirect (SEO-friendly)
location = /old-page/ {
    return 301 /new-page/;
}

# ⚠️ Temporary redirect (use sparingly)
location = /maintenance/ {
    return 302 /temporary-page/;
}
```

### 2. Match Exact Paths with `=`

```nginx
# ✅ Fast - Exact match (stops processing)
location = /old-page/ {
    return 301 /new-page/;
}

# ⚠️ Slower - Prefix match (continues processing)
location /old-page/ {
    return 301 /new-page/;
}
```

### 3. Use Regex for Pattern Matching

```nginx
# Redirect all portfolio items to main portfolio page
location ~ ^/portfolio-item/.*$ {
    return 301 /portfolio/;
}

# Redirect old date-based URLs to new structure
location ~ ^/(\d{4})/(\d{2})/(.*)$ {
    return 301 /$3;
}
```

### 4. Preserve Query Strings

```nginx
# Query strings are automatically preserved
location = /old-page/ {
    return 301 /new-page/;
}
# /old-page/?utm_source=google -> /new-page/?utm_source=google
```

### 5. Add Comments and Dates

```nginx
# SEO Redirects - Fix 404 Errors
# Date: 2025-11-30
# Reason: Content restructure after site migration

location = /old-page/ {
    return 301 /new-page/;
}
```

## Common Redirect Patterns

### WordPress Permalinks

```nginx
# Old post URLs -> New permalink structure
location ~ ^/\d{4}/\d{2}/(.*)$ {
    return 301 /$1;
}
```

### Category Consolidation

```nginx
# Merge old categories into new category
location ~ ^/category/old-cat-1/(.*)$ {
    return 301 /category/new-category/$1;
}

location ~ ^/category/old-cat-2/(.*)$ {
    return 301 /category/new-category/$1;
}
```

### Custom Post Type URLs

```nginx
# Old CPT slug -> New CPT slug
location ~ ^/old-portfolio/(.*)$ {
    return 301 /portfolio/$1;
}
```

### Language/Locale Redirects

```nginx
# Redirect old language URLs to new structure
location ~ ^/en-us/(.*)$ {
    return 301 /en/$1;
}
```

## Testing Redirects

### Manual Testing with curl

```bash
# Test redirect (follow redirects with -L)
curl -I https://yoursite.com/old-url

# Expected output:
# HTTP/2 301
# Location: https://yoursite.com/new-url/
```

### Automated Testing

Create a test script to verify all redirects:

```bash
#!/bin/bash
# test-redirects.sh

SITE="https://yoursite.com"

# Test each redirect
curl -I -s "$SITE/old-page/" | grep -q "301" && echo "✅ /old-page/ -> 301" || echo "❌ /old-page/ failed"
curl -I -s "$SITE/another-page/" | grep -q "301" && echo "✅ /another-page/ -> 301" || echo "❌ /another-page/ failed"
```

## Finding URLs to Redirect

### 1. Check Google Search Console

- **Coverage Report**: Find 404 errors
- **Performance Report**: Find URLs with impressions but low clicks

### 2. Analyze Server Logs

```bash
# Find 404 errors in nginx logs
ssh root@yoursite.com "grep ' 404 ' /srv/www/yoursite.com/logs/access.log | awk '{print \$7}' | sort | uniq -c | sort -rn | head -20"
```

### 3. Use Screaming Frog SEO Spider

- Crawl your site
- Filter by "Response Code = 404"
- Identify broken internal links

### 4. Check Old Sitemaps

- Compare old sitemap.xml with current sitemap
- Find removed URLs that should redirect

## Rollback

If redirects cause issues, you can remove them:

```bash
# 1. Remove or comment out redirects in the .conf.j2 file

# 2. Re-deploy
cd trellis
trellis provision --tags nginx-includes production

# 3. Or manually remove on server
ssh root@yoursite.com "rm /etc/nginx/includes.d/yoursite.com/seo-redirects.conf && nginx -t && systemctl reload nginx"
```

## Performance Considerations

### Redirect Limits

- Nginx handles thousands of redirects efficiently
- Each redirect is compiled to a hash table (O(1) lookup)
- No significant performance impact up to ~10,000 redirects

### Optimization Tips

1. **Use exact matches** (`location =`) when possible (fastest)
2. **Group similar patterns** with regex instead of individual rules
3. **Place most frequently accessed redirects first**
4. **Monitor redirect chains** (redirect should go directly to final URL)

## Troubleshooting

### Redirects Not Working

```bash
# 1. Verify file was deployed
ssh root@yoursite.com "ls -la /etc/nginx/includes.d/yoursite.com/"

# 2. Check nginx config syntax
ssh root@yoursite.com "nginx -t"

# 3. Check nginx error log
ssh root@yoursite.com "tail -f /var/log/nginx/error.log"

# 4. Verify nginx was reloaded
ssh root@yoursite.com "systemctl status nginx"
```

### 404 Instead of Redirect

- Check if redirect location path is exact match (`=`)
- Verify trailing slashes (nginx treats `/page` and `/page/` differently)
- Check if another location block takes precedence

### Redirect Loops

```bash
# Test for loops
curl -I -L https://yoursite.com/page/

# If it hangs or shows many redirects, you have a loop
```

Fix by checking your redirect chain:
```nginx
# ❌ Bad - Creates loop
location = /page-a/ { return 301 /page-b/; }
location = /page-b/ { return 301 /page-a/; }

# ✅ Good - Direct to final destination
location = /page-a/ { return 301 /final-page/; }
location = /page-b/ { return 301 /final-page/; }
```

## Documentation

- [Roots Trellis Nginx Includes Docs](https://roots.io/trellis/docs/nginx-includes/)
- [Nginx Location Directive](http://nginx.org/en/docs/http/ngx_http_core_module.html#location)
- [Nginx Return Directive](http://nginx.org/en/docs/http/ngx_http_rewrite_module.html#return)

## Version History

- **2025-11-30** - Initial version with SEO redirect examples and comprehensive documentation
