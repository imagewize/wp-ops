# Nginx Redirect Configuration

Why a redirect may not deploy, and why a 301 drops the query string: [My Trellis Nginx Redirect Did Nothing](https://wpvilla.in/trellis-nginx-redirect-not-deployed-query-string-dropped/).

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

Do not use `--tags nginx`. The includes are templated by the `wordpress-setup`
role, so that run finishes without deploying the file.

### 4. Verify Deployment

```bash
# Check the config file was deployed
ssh web@yoursite.com "ls -la --time-style=full-iso /etc/nginx/includes.d/yoursite.com/"
ssh web@yoursite.com "grep -n 'old-url' /etc/nginx/includes.d/yoursite.com/seo-redirects.conf"

# Test nginx config is valid
ssh -t admin_user@yoursite.com "sudo nginx -t"

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

### 4. Query Strings Are Not Preserved by `return`

```nginx
# The query string is dropped
location = /old-page/ {
    return 301 /new-page/;
}
# /old-page/?utm_source=google -> /new-page/

# Append it to keep it
location = /old-page/ {
    return 301 /new-page/$is_args$args;
}
# /old-page/?utm_source=google -> /new-page/?utm_source=google
```

`return` does not carry the query string over (`rewrite` does). Keep it for
redirects people reach from campaigns; drop it when the destination is another
site and the old parameters mean nothing there.

### 5. Add Comments and Dates

```nginx
# SEO Redirects - Fix 404 Errors
# Date: 2025-11-30
# Reason: Content restructure after site migration

location = /old-page/ {
    return 301 /new-page/;
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


## Finding URLs to redirect

Start from your 404s: Google Search Console's coverage report, or `wp-ops 404-checker`, or the nginx access log. Compare the old and new sitemaps for removed URLs.

## Rollback

If redirects cause issues, you can remove them:

```bash
# 1. Remove or comment out redirects in the .conf.j2 file

# 2. Re-deploy
cd trellis
trellis provision --tags nginx-includes production

# 3. Or manually remove on server
ssh -t admin_user@yoursite.com "sudo rm /etc/nginx/includes.d/yoursite.com/seo-redirects.conf && sudo nginx -t && sudo systemctl reload nginx"
```


## Troubleshooting

### Redirects Not Working

```bash
# 1. Verify file was deployed
ssh web@yoursite.com "ls -la --time-style=full-iso /etc/nginx/includes.d/yoursite.com/"

# 2. Check nginx config syntax
ssh -t admin_user@yoursite.com "sudo nginx -t"

# 3. Check nginx error log
ssh -t admin_user@yoursite.com "sudo tail -f /var/log/nginx/error.log"

# 4. Verify nginx was reloaded
ssh -t admin_user@yoursite.com "sudo systemctl status nginx"
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
