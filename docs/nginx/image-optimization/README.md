# Image Optimization Guide

This guide covers how to optimize images for your Trellis-managed WordPress sites, including Nginx configuration for serving WebP and AVIF images, and methods to convert traditional image formats to these more efficient formats.

## Table of Contents
- [Nginx Configuration for WebP and AVIF](#nginx-configuration-for-webp-and-avif)
- [Image Resizing and Cropping](#image-resizing-and-cropping)
- [Converting Images to WebP](#converting-images-to-webp)
- [Converting Images to AVIF](#converting-images-to-avif)
- [Automating Image Conversion](#automating-image-conversion)
- [WordPress Plugins](#wordpress-plugins)

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

## Image Resizing and Cropping

Before converting images to WebP or AVIF, you may need to resize or crop them to the appropriate dimensions. ImageMagick is a powerful tool for this purpose.

### Installing ImageMagick

```bash
# macOS (using Homebrew)
brew install imagemagick

# Ubuntu/Debian
sudo apt-get install imagemagick
```

For detailed instructions on resizing, cropping, and preparing images for conversion, see the [Image Resizing and Conversion Guide](RESIZE-AND-CONVERSION.md).

### Quick Example

```bash
# Resize and crop to 400x400, then convert to WebP
magick input.jpg \
  -resize 500x500^ \
  -gravity center \
  -crop 400x400+0+0 \
  -quality 90 \
  output.jpg

cwebp -q 85 output.jpg -o output.webp
```

See [RESIZE-AND-CONVERSION.md](RESIZE-AND-CONVERSION.md) for more examples, including:
- Creating thumbnails and avatars
- Batch processing multiple images
- Responsive image workflows
- Custom crop offsets
- Quality settings recommendations

## Converting Images to WebP

### Using cwebp (Command Line)

The `cwebp` tool from Google allows you to convert images to WebP format from the command line.

#### Installation

```bash
# macOS (using Homebrew)
brew install webp

# Ubuntu/Debian
sudo apt-get install webp
```

#### Basic Usage

```bash
# Convert a single image
cwebp -q 80 image.jpg -o image.jpg.webp

# Convert with metadata preservation
cwebp -metadata all -q 80 image.jpg -o image.jpg.webp
```

#### Batch Conversion

```bash
# Convert all JPG files in current directory
find . -type f -name "*.jpg" -exec cwebp -q 80 {} -o {}.webp \;

# Convert all PNG files in current directory
find . -type f -name "*.png" -exec cwebp -q 80 {} -o {}.webp \;
```

### Quality Settings

- `-q 0` to `-q 100`: Lower values = smaller files but lower quality
- Recommended: 75-85 for photos, 85-95 for images with text
- See [RESIZE-AND-CONVERSION.md](RESIZE-AND-CONVERSION.md) for detailed quality comparisons

## Converting Images to AVIF

AVIF offers even better compression than WebP but requires more processing power to create.

### Using cavif (Command Line)

#### Installation

```bash
# macOS (using Homebrew)
brew install cavif

# From source
git clone https://github.com/kornelski/cavif-rs
cd cavif-rs
cargo install --path .
```

#### Basic Usage

```bash
# Convert a single image
cavif --quality 80 image.jpg -o image.jpg.avif

# Convert with specific settings
cavif --quality 80 --speed 5 image.jpg
```

#### Batch Conversion

```bash
# Convert all JPG files in current directory
find . -type f -name "*.jpg" -exec cavif --quality 80 {} \;
```

## Automating Image Conversion

For comprehensive automation examples including resizing and cropping, see [RESIZE-AND-CONVERSION.md](RESIZE-AND-CONVERSION.md#complete-workflow-examples).

### Using a Shell Script

Create a script called `convert-images.sh`:

```bash
#!/bin/bash

# Directory containing images to convert
IMAGE_DIR="path/to/images"
QUALITY=80

# Process JPEG images to WebP
find "$IMAGE_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) | while read img; do
  if [ ! -f "${img}.webp" ]; then
    echo "Converting $img to WebP"
    cwebp -q $QUALITY "$img" -o "${img}.webp"
  fi
  
  if [ ! -f "${img}.avif" ]; then
    echo "Converting $img to AVIF"
    cavif --quality $QUALITY "$img" -o "${img}.avif"
  fi
done

# Process PNG images
find "$IMAGE_DIR" -type f -iname "*.png" | while read img; do
  if [ ! -f "${img}.webp" ]; then
    echo "Converting $img to WebP"
    cwebp -q $QUALITY "$img" -o "${img}.webp"
  fi
  
  if [ ! -f "${img}.avif" ]; then
    echo "Converting $img to AVIF"
    cavif --quality $QUALITY "$img" -o "${img}.avif"
  fi
done

echo "Conversion complete!"
```

Make it executable:

```bash
chmod +x convert-images.sh
```

### Setting Up a Cron Job

To automatically run the conversion script periodically:

```bash
# Edit crontab
crontab -e

# Add this line to run daily at 2 AM
0 2 * * * /path/to/convert-images.sh >> /path/to/conversion.log 2>&1
```

## WordPress Plugins

Several WordPress plugins can automatically generate and serve WebP/AVIF images:

1. **[WebP Express](https://wordpress.org/plugins/webp-express/)**: Converts images and works with the Nginx configuration
2. **[EWWW Image Optimizer](https://wordpress.org/plugins/ewww-image-optimizer/)**: Comprehensive image optimization
3. **[Imagify](https://wordpress.org/plugins/imagify/)**: Easy WebP conversion
4. **[ShortPixel Image Optimizer](https://wordpress.org/plugins/shortpixel-image-optimiser/)**: Supports WebP and AVIF

### Plugin Integration

For the best results:

1. Install one of the above plugins
2. Configure it to generate WebP/AVIF versions on upload
3. Ensure the plugin saves the optimized versions with the correct file extension pattern (`.jpg.webp`, `.jpg.avif`, etc.)
4. The Nginx configuration will automatically serve the optimized versions

## Best Practices

1. Always keep the original images as fallbacks
2. Use appropriate quality settings (70-85) for a good balance of size and quality
3. Test optimized images on different devices and browsers
4. Consider using a CDN that supports content negotiation for WebP/AVIF
5. Implement responsive images in your WordPress theme for additional optimization

## Performance Impact

Using WebP and AVIF formats can significantly improve website performance:

- WebP: 25-35% smaller than JPEG at similar quality
- AVIF: 50%+ smaller than JPEG at similar quality
- Faster load times lead to better SEO and user experience
- Reduced bandwidth consumption for both server and visitors