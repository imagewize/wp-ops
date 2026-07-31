#!/usr/bin/env node

/**
 * Screenshot a URL with Playwright
 *
 * Navigates to a URL and screenshots either the first element matching a
 * selector (tries each --selector in order, falls back to full page) or the
 * whole page. Generic capture primitive — no WordPress/site-specific paths.
 *
 * Usage:
 *   node screenshot-url.js <url> --out=<path> [options]
 *
 * Options:
 *   --out=<path>        Output PNG path (required)
 *   --width=1400         Viewport width (default: 1400)
 *   --height=900          Viewport height (default: 900)
 *   --wait=3000           Milliseconds to wait after load, for JS-rendered content (default: 3000)
 *   --selector=<a,b,c>   Comma-separated CSS selectors, tried in order; first match is screenshotted
 *   --full-page          Skip selector matching and screenshot the entire page
 *
 * Examples:
 *   node screenshot-url.js http://example.test/my-page/ --out=pattern.png
 *   node screenshot-url.js http://example.test/my-page/ --out=pattern.png --selector=".entry-content > *:first-child"
 *   node screenshot-url.js http://example.test/ --out=full.png --full-page --width=1920 --height=1080
 */

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const DEFAULT_SELECTORS = [
  '.entry-content > *:first-child',
  'article .entry-content > div',
  'main > *:first-child',
  '.wp-site-blocks > *:first-child'
];

const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  blue: '\x1b[34m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function parseArgs(argv) {
  const url = argv[0];
  if (!url || url.startsWith('--')) {
    log('Error: URL is required', 'red');
    log('Usage: node screenshot-url.js <url> --out=<path> [options]', 'yellow');
    process.exit(1);
  }

  const flag = (name) => argv.find((a) => a.startsWith(`--${name}=`))?.split('=').slice(1).join('=');

  const out = flag('out');
  if (!out) {
    log('Error: --out=<path> is required', 'red');
    process.exit(1);
  }

  return {
    url,
    out,
    width: parseInt(flag('width') || '1400', 10),
    height: parseInt(flag('height') || '900', 10),
    wait: parseInt(flag('wait') || '3000', 10),
    selectors: flag('selector') ? flag('selector').split(',') : DEFAULT_SELECTORS,
    fullPage: argv.includes('--full-page')
  };
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  log(`\nScreenshot: ${opts.url}`, 'blue');
  log(`Viewport: ${opts.width}x${opts.height}  |  wait: ${opts.wait}ms  |  full-page: ${opts.fullPage}`, 'cyan');

  const outDir = path.dirname(opts.out);
  if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
  }

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: opts.width, height: opts.height } });
  const page = await context.newPage();

  try {
    await page.goto(opts.url, { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(opts.wait);

    let captured = false;

    if (!opts.fullPage) {
      for (const selector of opts.selectors) {
        const element = await page.$(selector);
        if (element) {
          await element.screenshot({ path: opts.out, type: 'png' });
          log(`Matched selector: ${selector}`, 'cyan');
          captured = true;
          break;
        }
      }
      if (!captured) {
        log('No selector matched, falling back to full page', 'yellow');
      }
    }

    if (!captured) {
      await page.screenshot({ path: opts.out, fullPage: true });
    }

    const { size } = fs.statSync(opts.out);
    log(`Saved: ${opts.out} (${Math.round(size / 1024)}KB)`, 'green');
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  log(`\nFatal error: ${error.message}`, 'red');
  console.error(error);
  process.exit(1);
});
