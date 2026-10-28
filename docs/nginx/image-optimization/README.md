# Image Optimization Guide

Serve WebP and AVIF versions of your images from a Trellis-managed WordPress site. The Nginx include does the serving; you (or a plugin) supply the converted files.

## Nginx Configuration for WebP and AVIF

The `nginx-includes/webp-avf.conf.j2` file in this repository contains Nginx configuration to automatically serve WebP or AVIF versions of images when the browser supports them. This configuration works by checking the `Accept` header from the browser and serving the appropriate image format.

### How it Works

When a browser requests an image:

1. Nginx checks if the browser accepts WebP or AVIF formats
2. If supported formats exist on the server (e.g., `image.jpg.webp` or `image.jpg.avif`), Nginx serves them instead of the original
3. If no optimized version exists, the original image is served

### Implementation

1. Copy the `nginx-includes` directory to your Trellis project
2. Update your Trellis WordPress site configuration to include the custom Nginx configuration:

```yaml
# group_vars/production/wordpress_sites.yml (or staging/development)
wordpress_sites:
  example.com:
    # ... existing configuration ...
    nginx_includes:
      - nginx-includes/webp-avf.conf.j2
```

3. Provision your environment to apply the changes:

```bash
# For production
trellis provision production

# For staging
trellis provision staging

# For development
trellis provision development
```

## Generating the converted files

The include looks for the **original filename plus the new extension**: `photo.jpg` is served as `photo.jpg.webp` or `photo.jpg.avif` when both exist next to it.

```bash
# One image
cwebp -q 80 photo.jpg -o photo.jpg.webp
cavif --quality 80 photo.jpg

# Everything under uploads/
find uploads/ -name "*.jpg" -exec cwebp -q 80 {} -o {}.webp \;
```

Install the tools with `brew install webp cavif` (macOS) or `apt-get install webp` (Ubuntu). Quality 75-85 suits photos; use 85-95 for images with text. Keep the originals: they are the fallback.

A plugin that writes `.jpg.webp` files on upload works with the include too, for example [WebP Express](https://wordpress.org/plugins/webp-express/), [EWWW Image Optimizer](https://wordpress.org/plugins/ewww-image-optimizer/) or [ShortPixel](https://wordpress.org/plugins/shortpixel-image-optimiser/).

## Verify

```bash
curl -H "Accept: image/webp" -I https://example.com/wp-content/uploads/photo.jpg
```

Expect a `Content-Type: image/webp` response. If you still get the JPG, check that `photo.jpg.webp` exists with exactly that name.
