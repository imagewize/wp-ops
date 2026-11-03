# Update snapshots

Before/after screenshots for WordPress updates. Capture a fixed list of pages
before you update, again after, then diff the two runs into a compare page you
can look at in a minute or send to a client.

Two commands:

| Command | What it does |
|---|---|
| `wp-ops update-snapshot` | Screenshot a page list at desktop and 390px mobile, into one directory per run |
| `wp-ops update-compare` | Diff two runs, write a self-contained compare folder (`index.html` + images), exit 1 if anything changed more than the threshold |

Both run on your machine, against any URL: a local `.test` copy, staging or
production. Neither one changes the site.

## Setup

```bash
cd scripts/updates          # in your wp-ops checkout
npm install
npx playwright install chromium
```

Playwright is looked up next to the script first, then in the directory you run
from, so inside a site project that already has Playwright tests no install is
needed. With a Homebrew install, the script runs from wp-ops' asset cache; if
Playwright isn't found, the error prints the exact folder to run `npm install` in.

`update-compare` needs ImageMagick 7 (`magick`), e.g. `brew install imagemagick`.

## An update round

```bash
# pages.txt: one path per line; "name|/path/" sets the file name; # starts a comment
cat > pages.txt <<'EOF'
home|/
/shop/
/contact/
post|/a-recent-post/
EOF

# 1. Before: on the local copy, after pulling the database AND uploads
wp-ops update-snapshot http://example.test --out=snapshots/before --pages-file=pages.txt

# 2. Apply the updates locally (composer update / wp plugin update ...)

# 3. After, same pages, then compare
wp-ops update-snapshot http://example.test --out=snapshots/after --pages-file=pages.txt
wp-ops update-compare snapshots/before snapshots/after --out=snapshots/compare-local
open snapshots/compare-local/index.html

# 4. Deploy, then check production against the tested local result
wp-ops update-snapshot https://example.com --out=snapshots/prod --pages-file=pages.txt
wp-ops update-compare snapshots/after snapshots/prod --out=snapshots/compare-prod
```

Step 4 compares production against **local after**, not against before: the
question there is "is live the same as what I tested?". On a matching stack the
expected result is 0.000% on every shot.

## Options

`update-snapshot <base-url> --out=<dir>`

| Flag | Default | |
|---|---|---|
| `--pages=/,/contact/` | `/` | Comma-separated paths |
| `--pages-file=<file>` | | One path per line, `name\|/path/` allowed, `#` comments |
| `--viewports=desktop,mobile` | `desktop,mobile` | Also `tablet`. Desktop 1920×1080, tablet 768×1024, mobile 390×844 |
| `--mask=<selectors>` | | Extra CSS selectors to hide (`visibility:hidden`, layout unchanged) |
| `--no-default-mask` | | Don't hide the Contact Form 7 CAPTCHA |
| `--timeout=60` | `60` | Seconds per capture before it is skipped and marked failed |

Writes `<name>-<viewport>.png` per shot and `manifest.json` (URL, HTTP status,
page size, error per shot). Exits 1 if a capture failed or a page returned 400+.

`update-compare <before-dir> <after-dir>`

| Flag | Default | |
|---|---|---|
| `--out=<dir>` | `<after-dir>-compare` | Compare folder: `index.html`, `before/`, `after/`, `diff/` |
| `--fuzz=15` | `15` | Per-pixel color tolerance in %, so antialiasing doesn't count |
| `--threshold=0.5` | `0.5` | % of changed pixels that flags a shot |
| `--title=<text>` | `Update compare` | Heading of the compare page |

Flagged shots are listed first. The diff column shows changed pixels in red over a
faded copy of the after shot.

## Why it captures the way it does

These came out of the first real update round (imagewize.com, Nov 2026):

- **Scroll, then wait for decode.** A plain full-page capture leaves
  below-the-fold images unpainted, and which ones differs from run to run. That
  showed up as 1–3% "changes" on three of six pages when nothing had changed.
  The script scrolls through the page and waits for every image to decode (up to
  5 seconds) before capturing. With that, two runs of the same page are
  pixel-identical.
- **Hard timeouts.** One page that never settles must not stall the whole run.
  Each capture is killed after `--timeout`. Pages that never go network-idle
  (analytics beacons, long polling) fall back to the `load` event.
- **No resizing.** Tall pages stay full resolution, so a diff is exact. View
  them in the compare page, not in tools that downscale.
- **Mask what changes on every load.** CAPTCHAs, rotating testimonials,
  "latest posts" lists, countdown timers. The CF7 CAPTCHA is masked by default.
- **Pull uploads before the before-run.** A missing image in local uploads shows
  up as a change once it arrives.

## Reading a result

- **0.000% on every shot**: nothing visible changed.
- **A block of red**: something on the page changed. Open the before and after
  columns.
- **Size changed and most of the page is red**: the page got taller or shorter, so
  everything below that point moved down or up. Look for the first red area from
  the top. That is where the change is.
- **Small scattered red**: animation, a carousel or a lazy element that the mask
  doesn't cover. Add a `--mask` selector and capture again.

A screenshot only proves the page *looks* the same. It doesn't prove the checkout
or a contact form still works, so test those separately.
