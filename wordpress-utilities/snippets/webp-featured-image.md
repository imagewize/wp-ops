# WebP Featured Image Conversion

Shell commands to convert images to WebP format optimized for WordPress featured images and Facebook Open Graph sharing.

## Quick Command

```bash
cwebp -q 82 -resize 800 419 image.jpg -o image.webp
```

This produces an 800×419 px WebP image that:
- Hits the **1.91:1 ratio** required by Facebook Open Graph (1200×630 standard)
- Is **above Facebook's minimum** of 600×315
- Fits comfortably in WordPress content columns (typically 645px wide)
- Loads fast with small file size

## Why These Dimensions?

- **Facebook Open Graph**: Recommended ratio is 1.91:1. The command's `-resize 800 419` maintains this exact ratio.
- **WordPress content width**: Most themes use ~600-700px content columns. 800px wide gives some headroom without wasting pixels.
- **File size**: At quality 82, images typically compress to 30-60% of the original JPEG size.

## Installation

### macOS (Homebrew)

```bash
brew install webp
```

### Ubuntu/Debian

```bash
sudo apt-get install webp
```

## Usage Examples

### Convert a single image

```bash
cwebp -q 82 -resize 800 419 featured.jpg -o featured.webp
```

### Convert with metadata preserved

```bash
cwebp -metadata all -q 82 -resize 800 419 featured.jpg -o featured.webp
```

### Batch convert all JPGs in a directory

Crop to exact 800×419 (center crop via ImageMagick, then convert to WebP):

```bash
find . -type f -name "*.jpg" | while read img; do
  convert "$img" -resize 800x419^ -gravity center -extent 800x419 miff:- \
    | cwebp -q 82 -- - -o "${img%.jpg}.webp"
done
```

### Batch convert with existing WebP check (skip if already converted)

```bash
find . -type f -name "*.jpg" | while read img; do
  out="${img%.jpg}.webp"
  if [ ! -f "$out" ]; then
    convert "$img" -resize 800x419^ -gravity center -extent 800x419 miff:- \
      | cwebp -q 82 -- - -o "$out"
  fi
done
```

## Quality Settings

- `-q 82`: Good balance of quality and file size (default recommended by Google)
- Lower values (60-75): Smaller files, noticeable quality loss at lower end
- Higher values (85-95): Better quality, larger files
- For images with text: Use `-q 90-95` to preserve sharpness

## Nginx Integration

Once converted, use the Nginx configuration from `nginx/image-optimization/` to automatically serve `.webp` versions when browsers support it. The Nginx config expects files named like `image.jpg.webp`.

To match this naming convention:

```bash
cwebp -q 82 -resize 800 419 image.jpg -o image.jpg.webp
```

Then place both files in your uploads directory. Nginx will serve `.webp` to supporting browsers, falling back to `.jpg` otherwise.

## Complete Workflow Example

```bash
# Navigate to your uploads directory
cd wp-content/uploads/2024/05

# Convert all JPGs to WebP at 800x419 (center crop)
find . -type f -name "*.jpg" | while read img; do
  convert "$img" -resize 800x419^ -gravity center -extent 800x419 miff:- \
    | cwebp -q 82 -- - -o "${img%.jpg}.webp"
done

# Verify file sizes
ls -lh *.webp
```

## Tips

- **Exact crop vs. aspect ratio**: `cwebp -resize 800 419` distorts non-1.91:1 sources. Use the ImageMagick pipe (`-resize 800x419^ -gravity center -extent 800x419`) for center-crop to exact dimensions.
- **Lossless option**: Use `-lossless` instead of `-q` for images that need perfect quality (logos, icons).
- **Check quality**: Compare before/after with `cwebp -q 82 input.jpg -o /dev/null` to see predicted file size and PSNR.
