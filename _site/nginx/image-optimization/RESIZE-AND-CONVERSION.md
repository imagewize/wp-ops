# Image Resizing and Conversion Guide

This guide covers how to resize, crop, and convert images using ImageMagick and WebP tools. These techniques are useful for preparing images for web use, creating thumbnails, avatars, and optimizing file sizes.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Resizing and Cropping with ImageMagick](#resizing-and-cropping-with-imagemagick)
- [Converting to WebP](#converting-to-webp)
- [Converting to AVIF](#converting-to-avif)
- [Complete Workflow Examples](#complete-workflow-examples)
- [Tips and Best Practices](#tips-and-best-practices)

## Prerequisites

### Installing ImageMagick

```bash
# macOS (using Homebrew)
brew install imagemagick

# Ubuntu/Debian
sudo apt-get install imagemagick

# Verify installation
magick -version
```

### Installing WebP Tools

```bash
# macOS (using Homebrew)
brew install webp

# Ubuntu/Debian
sudo apt-get install webp
```

### Installing AVIF Tools

```bash
# macOS (using Homebrew)
brew install cavif

# Ubuntu/Debian
# From source
cargo install cavif
```

## Resizing and Cropping with ImageMagick

### Basic Resize and Crop

The `magick` command (ImageMagick v7+) allows you to resize and crop images in a single operation:

```bash
magick input.jpg \
  -resize 500x500^ \
  -gravity center \
  -crop 400x400+0+0 \
  -quality 90 \
  output.jpg
```

**Parameters explained:**
- `-resize 500x500^`: Resize to minimum 500x500 pixels (the `^` ensures the image fills the dimensions)
- `-gravity center`: Set the anchor point to center for cropping
- `-crop 400x400+0+0`: Crop to exactly 400x400 pixels from the center
- `-quality 90`: Set JPEG quality (0-100, higher is better quality but larger file size)

### Custom Crop Offset

To crop with a vertical offset (e.g., move crop area up or down):

```bash
magick input.jpg \
  -resize 500x500^ \
  -gravity center \
  -crop 400x400+0-100 \
  -quality 90 \
  output.jpg
```

The `+0-100` means:
- `+0`: No horizontal offset
- `-100`: Move crop area 100 pixels up (use `+100` to move down)

### Common Resize Operations

```bash
# Create a square thumbnail (300x300)
magick input.jpg -resize 300x300^ -gravity center -crop 300x300+0+0 thumbnail.jpg

# Create avatar (200x200, high quality)
magick input.jpg -resize 250x250^ -gravity center -crop 200x200+0+0 -quality 95 avatar.jpg

# Resize while maintaining aspect ratio (max width 800px)
magick input.jpg -resize 800x output.jpg

# Resize with maximum dimensions (will fit within 1200x800)
magick input.jpg -resize 1200x800 output.jpg

# Resize screenshot with dimensions 1200 x 900 for theme
magick "~/Desktop/screenshot-taken.png" \
  -resize "1200x900^" \
  -gravity center \
  -extent 1200x900 \
  "~/Desktop/screenshot.png"
```



### Note on ImageMagick Versions

If you're using ImageMagick v6, use `convert` instead of `magick`:

```bash
convert input.jpg -resize 500x500^ -gravity center -crop 400x400+0+0 output.jpg
```

However, it's recommended to use ImageMagick v7+ with the `magick` command.

## Converting to WebP

After resizing your image, convert it to WebP format for better compression:

```bash
cwebp -q 85 output.jpg -o output.webp
```

**Parameters:**
- `-q 85`: Quality setting (0-100, recommended: 70-85)
- `-o output.webp`: Output filename

### Expected Output

```
Saving file 'output.webp'
File:      output.jpg
Dimension: 400 x 400
Output:    27150 bytes Y-U-V-All-PSNR 42.44 45.81 45.19   43.24 dB
           (1.36 bpp)
```

### Check File Size

```bash
# macOS
stat -f%z output.webp 2>/dev/null | awk '{printf "%.1fKB\n", $1/1024}'

# Linux
stat -c%s output.webp 2>/dev/null | awk '{printf "%.1fKB\n", $1/1024}'
```

## Converting to AVIF

For even better compression, convert to AVIF format:

```bash
cavif --quality 80 output.jpg -o output.avif
```

AVIF typically produces files 40-50% smaller than WebP at similar quality.

## Complete Workflow Examples

### Example 1: Create Optimized Avatar

```bash
# Step 1: Resize and crop to 200x200
magick profile-photo.jpg \
  -resize 250x250^ \
  -gravity center \
  -crop 200x200+0+0 \
  -quality 90 \
  avatar.jpg

# Step 2: Convert to WebP
cwebp -q 85 avatar.jpg -o avatar.webp

# Step 3: Convert to AVIF
cavif --quality 80 avatar.jpg -o avatar.avif

# Step 4: Check file sizes
echo "Original: $(stat -f%z avatar.jpg 2>/dev/null | awk '{printf "%.1fKB", $1/1024}')"
echo "WebP: $(stat -f%z avatar.webp 2>/dev/null | awk '{printf "%.1fKB", $1/1024}')"
echo "AVIF: $(stat -f%z avatar.avif 2>/dev/null | awk '{printf "%.1fKB", $1/1024}')"
```

### Example 2: Batch Process Multiple Images

```bash
#!/bin/bash

# Process all JPG files in current directory
for img in *.jpg; do
  # Skip if output already exists
  [ -f "optimized_${img}" ] && continue

  # Resize and crop
  magick "$img" \
    -resize 800x600^ \
    -gravity center \
    -crop 800x600+0+0 \
    -quality 85 \
    "optimized_${img}"

  # Convert to WebP
  cwebp -q 80 "optimized_${img}" -o "optimized_${img}.webp"

  # Convert to AVIF
  cavif --quality 75 "optimized_${img}" -o "optimized_${img}.avif"

  echo "Processed: $img"
done
```

### Example 3: Single Command Workflow (Using Pipe)

```bash
# Convert, resize, and output to WebP in one operation
magick input.jpg \
  -resize 400x400^ \
  -gravity center \
  -crop 400x400+0+0 \
  -quality 90 \
  - | cwebp -q 85 - -o output.webp
```

## Tips and Best Practices

### Quality Settings

- **JPEG**: 85-95 for photos, 90-100 for images with text
- **WebP**: 75-85 for photos, 85-95 for images with text
- **AVIF**: 70-80 for photos, 80-90 for images with text

### Choosing the Right Format

- **Original JPEG/PNG**: Keep as fallback for older browsers
- **WebP**: Good compression, wide browser support (95%+)
- **AVIF**: Best compression, growing browser support (90%+)

### File Size Comparison

For a typical 400x400 photo:
- JPEG (quality 90): ~50-80KB
- WebP (quality 85): ~25-50KB (30-40% smaller)
- AVIF (quality 80): ~15-35KB (50-60% smaller)

### Automation Tips

1. Always keep the original files
2. Create a temporary file for intermediate steps
3. Use descriptive output filenames
4. Check output quality before deleting originals
5. Consider creating multiple sizes for responsive images

### Responsive Image Sizes

For responsive web design, create multiple sizes:

```bash
# Large (1200px)
magick input.jpg -resize 1200x output-large.jpg

# Medium (800px)
magick input.jpg -resize 800x output-medium.jpg

# Small (400px)
magick input.jpg -resize 400x output-small.jpg

# Then convert each to WebP and AVIF
for size in large medium small; do
  cwebp -q 80 output-${size}.jpg -o output-${size}.webp
  cavif --quality 75 output-${size}.jpg -o output-${size}.avif
done
```

## Cleaning Up Temporary Files

```bash
# Remove all temporary files after conversion
rm -f temp-*.jpg temp-*.png

# Keep only WebP and AVIF versions
find . -name "*.jpg" -o -name "*.png" | while read img; do
  if [ -f "${img}.webp" ] && [ -f "${img}.avif" ]; then
    echo "Removing original: $img (WebP and AVIF versions exist)"
    # rm "$img"  # Uncomment to actually delete
  fi
done
```