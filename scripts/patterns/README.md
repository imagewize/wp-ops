# Pattern Screenshot Toolkit

Playwright/sharp toolkit for screenshotting WordPress block patterns (or any URL) and
converting them to WebP. Useful for generating pattern-library preview images,
documentation screenshots, or visual diffs during theme development.

## Setup

```bash
cd scripts/patterns
npm install
npx playwright install chromium
```

Also requires ImageMagick for `trim-screenshots.sh` / `center-screenshots.sh`:

```bash
brew install imagemagick   # macOS
sudo apt-get install imagemagick  # Ubuntu/Debian
```

## Scripts

### screenshot-patterns.sh

End-to-end pattern screenshot pipeline: creates a temporary WordPress page containing
the pattern, screenshots it, deletes the page, and converts every capture to WebP.

Configure via environment variables (see the script header for the full list):

```bash
PATTERN_NAMESPACE=mytheme \
SITE_URL=http://example.test \
WP_CLI_CMD="wp --path=web/wp" \
./screenshot-patterns.sh hero-dark testimonials-and-logos
```

`WP_CLI_CMD` is whatever actually invokes WP-CLI for the target site — adjust it to
match your setup:

```bash
# Local Bedrock site
WP_CLI_CMD="wp --path=web/wp"

# Trellis VM
WP_CLI_CMD="trellis vm shell --workdir /srv/www/example.com/current -- wp"

# Remote over SSH
WP_CLI_CMD="ssh web@example.com -- wp --path=/srv/www/example.com/current/web/wp"
```

Output PNGs and WebPs land in `OUTPUT_DIR` (default: `./screenshots` next to this
script).

### screenshot-url.js

Generic capture primitive behind `screenshot-patterns.sh` — screenshots any URL, not
just a WordPress pattern page. Useful standalone for one-off captures or other
automation.

```bash
node screenshot-url.js http://example.test/some-page/ --out=page.png
node screenshot-url.js http://example.test/ --out=full.png --full-page --width=1920 --height=1080

# Custom selector priority list (first match wins, falls back to full page)
node screenshot-url.js http://example.test/pattern/ --out=pattern.png \
  --selector=".my-pattern-wrapper,.entry-content > *:first-child"
```

### convert-to-webp.js

Standalone PNG → WebP converter (sharp-based), used by `screenshot-patterns.sh` but
usable on its own for any directory of screenshots.

```bash
node convert-to-webp.js pattern-hero-dark.png
node convert-to-webp.js --all --dir=./screenshots
node convert-to-webp.js --all --dir=./screenshots --output-dir=./webp --quality=90
```

### trim-screenshots.sh / center-screenshots.sh

Post-processing for a directory of `pattern-*.webp` files (ImageMagick). Both back up
originals to `<dir>/originals/` before modifying in place, and skip files that already
have a backup (safe to re-run).

```bash
# Trim whitespace, resize to 900px wide
./trim-screenshots.sh ./screenshots 900

# Trim + center on a fixed 900x600 canvas (white background)
./center-screenshots.sh ./screenshots 900 600
```

## Typical workflow

```bash
PATTERN_NAMESPACE=mytheme SITE_URL=http://example.test WP_CLI_CMD="wp --path=web/wp" \
  ./screenshot-patterns.sh hero-dark testimonials-and-logos

./center-screenshots.sh ./screenshots 900 600
```

## Requirements

- Node.js >= 18, `npm install` in this directory
- Playwright Chromium (`npx playwright install chromium`)
- A reachable WordPress site with the target pattern registered under `PATTERN_NAMESPACE`
- WP-CLI access via whatever `WP_CLI_CMD` you configure
- ImageMagick, for `trim-screenshots.sh` / `center-screenshots.sh` only

## Not included

Site-specific QA checks (e.g. verifying a custom carousel block's JS state) are too
coupled to a particular block/theme to generalize usefully — write those as one-off
Playwright scripts in the project itself, using `screenshot-url.js` or Playwright
directly as a starting point.
