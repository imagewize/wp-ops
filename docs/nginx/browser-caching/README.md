# Browser Caching for Trellis

This guide covers how to implement effective browser caching for your Trellis-managed WordPress sites. Proper caching can significantly reduce page load times, bandwidth usage, and server load.

## Table of Contents
- [Overview](#overview)
- [Nginx Configuration for Browser Caching](#nginx-configuration-for-browser-caching)
- [Implementation](#implementation)
- [File Types and Cache Duration](#file-types-and-cache-duration)
- [Testing Cache Implementation](#testing-cache-implementation)
- [Troubleshooting](#troubleshooting)

## Overview

Browser caching instructs visitors' browsers to store static resources locally for a specified period, reducing the need to download the same files on subsequent visits. The included Nginx configuration adds appropriate caching headers to static files such as:

- Images (JPEG, PNG, GIF, WebP, AVIF)
- Stylesheets (CSS)
- JavaScript files
- Fonts (WOFF, WOFF2, TTF, EOT, OTF)
- SVG files
- Other static assets

## Nginx Configuration for Browser Caching

The `nginx-includes/all/assets-expiry.conf.j2` file in this repository contains Nginx configuration to set appropriate caching headers for various file types. The configuration uses the `expires` directive along with `Cache-Control` headers to control how long browsers should cache content.

### How it Works

1. The configuration maps content types to specific expiration times
2. Different file types receive appropriate cache durations
3. HTML files are not cached to ensure fresh content
4. Admin areas and PHP files are explicitly set to not cache

## Implementation

1. Copy the `nginx-includes` directory to your Trellis project root (same level as `server.yml`)
2. The configuration in `nginx-includes/all/assets-expiry.conf.j2` will automatically be applied to **all sites** on your server
3. Provision your environment to apply the changes:

```bash
# For production
trellis provision --tags nginx-includes production 

# For staging  
trellis provision --tags nginx-includes staging

# For development
trellis provision --tags nginx-includes development
```

**Note**: Since the file is in the `all/` directory, it will be automatically included for every site configured in Trellis. You don't need to modify your `wordpress_sites.yml` configuration.

## File Types and Cache Duration

The configuration sets the following cache durations:

| File Type | Cache Duration |
|-----------|---------------|
| Images (JPEG, PNG, GIF, WebP, AVIF) | 30 days |
| CSS files | 7 days |
| JavaScript files | 7 days |
| Fonts (WOFF, WOFF2, TTF, etc.) | 30 days |
| SVG files | 30 days |
| HTML files | No cache (always fresh) |
| PHP files | No cache |
| Admin areas | No cache |
| Other static files | 1 day |

These durations provide a good balance between performance and freshness. You can adjust them in the `assets-expiry.conf.j2` file to match your specific needs.

## Testing Cache Implementation

After implementation, you can verify the caching headers are working correctly:

### Using Browser Dev Tools

1. Open your website in Chrome or Firefox
2. Open Developer Tools (F12)
3. Navigate to the Network tab
4. Reload the page
5. Select any static resource (image, CSS, or JS file)
6. Check the Response Headers section for:
   - `Cache-Control` headers
   - `Expires` headers

### Using curl

```bash
curl -I https://example.com/wp-content/uploads/image.jpg
```

Look for headers like:
```
Cache-Control: public, max-age=2592000
Expires: Wed, 17 Jun 2025 12:00:00 GMT
```

## Troubleshooting

### Resources Not Caching

1. Verify the Nginx configuration was properly included
2. Check file permissions on the configuration file
3. Test with `curl -I` to see the actual headers being sent
4. Review Nginx error logs: `/var/log/nginx/error.log`

### Too Aggressive Caching

If you're developing or frequently updating assets:

1. Reduce cache durations in the configuration
2. Use versioned file names or query strings (e.g., `style.css?v=1.2`)
3. Use a cache-busting technique in your build process

### Cached Pages Not Updating

For WordPress pages that should always be fresh:

1. Verify HTML pages are not being cached (they shouldn't be with this configuration)
2. Check for additional caching layers (WordPress plugins, CDN, etc.)
3. Clear browser cache during testing

## Advanced Configuration

You can modify the cache durations or add more specific rules by editing the `nginx-includes/assets-expiry.conf.j2` file. For example, to change the cache duration for images:

```nginx
# Change image caching from 30 days to 14 days
~image/                                 14d;
```

## Performance Benefits

Implementing proper browser caching provides several benefits:

- Reduced bandwidth usage (up to 70% on repeat visits)
- Faster page load times for returning visitors
- Reduced server load and resource consumption
- Improved Google PageSpeed scores
- Better user experience and engagement

For optimal performance, consider combining this caching configuration with image optimization (see the image-optimization directory) and a content delivery network (CDN).