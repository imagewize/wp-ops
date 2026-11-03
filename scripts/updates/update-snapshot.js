#!/usr/bin/env node

/**
 * Screenshot a fixed set of pages before and after a WordPress update
 *
 * Captures the same page list at the same viewports every run, so two runs
 * (before an update, after it, then on production) can be diffed with
 * `wp-ops update-compare`. Built for update rounds, where a false diff costs
 * more than a slow capture:
 *
 *   - Scrolls through each page before capturing and waits for every image to
 *     decode (capped at 5s). A plain full-page capture leaves below-the-fold
 *     images unpainted at random, which shows up as a 1-3% "change" that
 *     isn't one.
 *   - Hard per-page timeout, so one hanging page can't stall the run.
 *   - Hides dynamic elements (--mask) with visibility:hidden, which keeps the
 *     layout identical. The Contact Form 7 CAPTCHA is masked by default.
 *   - Never resizes. Tall pages stay full resolution, so a diff is exact.
 *
 * Writes <out>/<name>-<viewport>.png plus <out>/manifest.json (URL, HTTP
 * status, size, errors per capture). Exits 1 if any capture failed or any
 * page returned HTTP 400 or higher.
 *
 * Usage:
 *   node update-snapshot.js <base-url> --out=<dir> [options]
 *
 * Options:
 *   --out=<dir>          Output directory (required)
 *   --pages=/,/contact/  Comma-separated paths (default: /)
 *   --pages-file=<file>  One path per line, optionally "name|/path/"; # comments allowed
 *   --viewports=desktop,mobile  Any of desktop (1920x1080), tablet (768x1024), mobile (390x844)
 *   --mask=<a,b>         Extra CSS selectors to hide before capture
 *   --no-default-mask    Don't hide the CF7 CAPTCHA
 *   --timeout=60         Seconds per capture before giving up (default: 60)
 *
 * Requires Playwright: `npm install && npx playwright install chromium` in
 * this directory (scripts/updates/).
 *
 * @desc     Screenshot a fixed page list for before/after update comparison
 * @category monitoring
 * @platform any
 * @runs     local
 * @requires node
 * @arg      base-url      required  {http://example.test}  Site base URL, no trailing slash
 * @flag     --out         required  {snapshots/before}  Output directory
 * @flag     --pages       optional  {/,/contact/}  Comma-separated paths to capture
 * @flag     --pages-file  optional  {pages.txt}  File with one path per line ("name|/path/" allowed)
 * @flag     --viewports   optional  {desktop,mobile}  Viewports: desktop, tablet, mobile
 * @flag     --mask        optional  {.cookie-button}  Extra CSS selectors to hide before capture
 * @flag     --no-default-mask optional  {}  Don't hide the Contact Form 7 CAPTCHA
 * @flag     --timeout     optional  {60}  Seconds per capture before giving up
 * @example  wp-ops update-snapshot http://example.test --out=snapshots/before --pages-file=pages.txt
 */

const fs = require('fs');
const path = require('path');

// Look for Playwright next to this script first (a wp-ops checkout after
// `npm install` here), then in the current project (a site that already has
// Playwright tests). A Homebrew install runs this script from wp-ops' asset
// cache, where nothing is installed until you do it.
let chromium;
try {
  ({ chromium } = require(require.resolve('playwright', { paths: [__dirname, process.cwd()] })));
} catch {
  console.error('Error: Playwright not found, neither next to this script nor in the current directory.');
  console.error('Either run from a project that has Playwright installed, or install it here:');
  console.error(`  cd "${__dirname}" && npm install && npx playwright install chromium`);
  process.exit(1);
}

const VIEWPORTS = {
  desktop: { width: 1920, height: 1080 },
  tablet: { width: 768, height: 1024 },
  mobile: { width: 390, height: 844 },
};
const DEFAULT_MASK = ['img.wpcf7-captcha', '.wpcf7-captchac'];

function parseArgs(argv) {
  const base = argv[0];
  if (!base || base.startsWith('--')) usage('base URL is required');
  const flag = (n) => argv.find((a) => a.startsWith(`--${n}=`))?.split('=').slice(1).join('=');
  const has = (n) => argv.includes(`--${n}`);
  const out = flag('out');
  if (!out) usage('--out=<dir> is required');

  let pages = [];
  if (flag('pages-file')) {
    pages = fs.readFileSync(flag('pages-file'), 'utf8').split('\n')
      .map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  } else {
    pages = (flag('pages') || '/').split(',').map((p) => p.trim()).filter(Boolean);
  }
  pages = pages.map((entry) => {
    const [n, p] = entry.includes('|') ? entry.split('|') : [null, entry];
    const p2 = p.startsWith('/') ? p : `/${p}`;
    return { name: n || slug(p2), path: p2 };
  });

  const viewports = (flag('viewports') || 'desktop,mobile').split(',').map((v) => v.trim());
  for (const v of viewports) if (!VIEWPORTS[v]) usage(`unknown viewport "${v}"`);

  const mask = [
    ...(has('no-default-mask') ? [] : DEFAULT_MASK),
    ...(flag('mask') ? flag('mask').split(',').map((s) => s.trim()).filter(Boolean) : []),
  ];
  return { base: base.replace(/\/+$/, ''), out, pages, viewports, mask, timeout: (+flag('timeout') || 60) * 1000 };
}

function usage(msg) {
  console.error(`Error: ${msg}`);
  console.error('Usage: wp-ops update-snapshot <base-url> --out=<dir> [--pages=/,/contact/ | --pages-file=<file>] [--viewports=desktop,mobile] [--mask=<sel>]');
  process.exit(1);
}

function slug(p) {
  const s = p.replace(/^\/+|\/+$/g, '').replace(/[^a-zA-Z0-9]+/g, '-').toLowerCase();
  return s || 'home';
}

function withTimeout(promise, ms, label) {
  let t;
  return Promise.race([
    promise,
    new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`timed out after ${ms / 1000}s (${label})`)), ms); }),
  ]).finally(() => clearTimeout(t));
}

async function capture(browser, url, vp, file, mask) {
  const context = await browser.newContext({ viewport: VIEWPORTS[vp] });
  const page = await context.newPage();
  try {
    let resp;
    try {
      resp = await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 });
    } catch {
      // Sites with long-polling or analytics beacons never go network-idle.
      resp = await page.goto(url, { waitUntil: 'load', timeout: 20000 });
    }
    const status = resp ? resp.status() : 0;

    // Scroll through the page so lazy and async-decoded images load and paint.
    await page.evaluate(async () => {
      const step = window.innerHeight * 0.8;
      for (let i = 0, y = 0; i < 60 && y < document.body.scrollHeight; i++, y += step) {
        window.scrollTo(0, y);
        await new Promise((r) => setTimeout(r, 120));
      }
      window.scrollTo(0, 0);
    });
    await page.evaluate(() => Promise.race([
      Promise.all([...document.images].map((i) => i.decode().catch(() => {}))),
      new Promise((r) => setTimeout(r, 5000)),
    ]));
    if (mask.length) {
      await page.addStyleTag({ content: `${mask.join(',')}{visibility:hidden !important}` });
    }
    await page.waitForTimeout(500);
    await page.screenshot({ path: file, fullPage: true, timeout: 20000 });
    const size = await page.evaluate(() => [document.documentElement.scrollWidth, document.documentElement.scrollHeight]);
    return { status, width: size[0], height: size[1] };
  } finally {
    await context.close().catch(() => {});
  }
}

(async () => {
  const opts = parseArgs(process.argv.slice(2));
  fs.mkdirSync(opts.out, { recursive: true });
  const browser = await chromium.launch();
  const results = [];
  let failed = 0;
  const started = Date.now();

  for (const p of opts.pages) {
    for (const vp of opts.viewports) {
      const url = opts.base + p.path;
      const fileName = `${p.name}-${vp}.png`;
      const file = path.join(opts.out, fileName);
      const t0 = Date.now();
      const row = { name: p.name, path: p.path, url, viewport: vp, file: fileName };
      try {
        Object.assign(row, await withTimeout(capture(browser, url, vp, file, opts.mask), opts.timeout, url));
        if (row.status >= 400) failed++;
        console.log(`${row.status >= 400 ? '✗' : '✓'} ${String(row.status).padEnd(3)} ${vp.padEnd(7)} ${p.path}  (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
      } catch (e) {
        row.error = e.message.split('\n')[0];
        failed++;
        console.log(`✗ ERR ${vp.padEnd(7)} ${p.path}  ${row.error}`);
      }
      results.push(row);
    }
  }
  await browser.close();

  fs.writeFileSync(path.join(opts.out, 'manifest.json'), JSON.stringify({
    base: opts.base,
    captured_at: new Date().toISOString(),
    seconds: Math.round((Date.now() - started) / 1000),
    mask: opts.mask,
    shots: results,
  }, null, 2));
  console.log(`\n${results.length - failed}/${results.length} captured in ${Math.round((Date.now() - started) / 1000)}s → ${opts.out}`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(`Error: ${e.message}`); process.exit(1); });
