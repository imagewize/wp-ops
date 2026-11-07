#!/usr/bin/env node

/**
 * Walk a WooCommerce store's buying path without placing an order
 *
 * Opens a fresh browser session, loads the shop, a category and a product,
 * adds the product to the cart, checks the cart page and its totals against
 * the WooCommerce Store API, and loads the checkout page. It stops there:
 * no order is placed, so it is safe on production. The cart session it
 * creates is abandoned.
 *
 * Each step reports pass, fail or skip with its timing. Cart and checkout
 * bypass the page cache, so those timings are an uncached speed number. A
 * skipped step never fails the run.
 *
 * Steps:
 *   1 shop page lists products          4 add to cart (product page, shop AJAX)
 *   2 category page loads               5 cart page shows the line, totals add up
 *   3 product page: price + button      6 checkout loads (block or shortcode),
 *                                         billing fields + payment methods render
 *
 * Exit codes (as store-audit):
 *   0  every step passed or was skipped
 *   1  bad usage, or the check could not run (no Playwright, browser failed)
 *   2  a step failed
 *
 * Variable products need an explicit --product that is a simple product.
 * Bot protection (Cloudflare, Wordfence) can block the run: allow-list the
 * user agent or run from a known IP. Run one site at a time by hand.
 *
 * Requires Playwright: `npm install && npx playwright install chromium` in
 * scripts/updates/, or run from a project that has Playwright installed.
 *
 * @desc     Walk shop > product > cart > checkout on a WooCommerce store without placing an order; per-step timings
 * @category monitoring
 * @platform any
 * @runs     local
 * @mutates  false
 * @requires node
 * @arg      url  required  {https://shop.example.com}  Store base URL (a subsite path like http://demo.test/shop-site is fine)
 * @flag     --product      optional  {/product/test-item/}  Simple product to add to the cart (default: first on the shop page)
 * @flag     --category     optional  {/product-category/test/}  Category page to load (default: discovered from the shop page)
 * @flag     --screenshots  optional  {shots}  Directory for a screenshot of each failed step
 * @flag     --json         optional  {}  Print the result as JSON only
 * @flag     --timeout      optional  {30}  Seconds per page load before the step fails
 * @example  wp-ops checkout-check https://shop.example.com
 * @example  wp-ops checkout-check http://demo.imagewize.test/winespring --screenshots=shots --json
 */

const fs = require('fs');
const path = require('path');

// Same lookup as update-snapshot: next to this script, the current project,
// then scripts/updates/ (where a wp-ops checkout installs Playwright).
let chromium;
try {
  ({ chromium } = require(require.resolve('playwright', {
    paths: [__dirname, process.cwd(), path.join(__dirname, '..', 'updates')],
  })));
} catch {
  console.error('Error: Playwright not found, neither next to this script nor in the current directory.');
  console.error('Either run from a project that has Playwright installed, or install it in scripts/updates/:');
  console.error(`  cd "${path.join(__dirname, '..', 'updates')}" && npm install && npx playwright install chromium`);
  process.exit(1);
}

const USAGE = 'Usage: checkout-check.js <store-url> [--product=/path/] [--category=/path/] [--screenshots=dir] [--json] [--timeout=30]';

function parseArgs(argv) {
  const opts = { json: false, timeout: 30 };
  for (const a of argv) {
    if (a === '--json') opts.json = true;
    else if (a === '-h' || a === '--help') { console.log(USAGE); process.exit(0); }
    else if (a.startsWith('--product=')) opts.product = a.slice(10);
    else if (a.startsWith('--category=')) opts.category = a.slice(11);
    else if (a.startsWith('--screenshots=')) opts.screenshots = a.slice(14);
    else if (a.startsWith('--timeout=')) opts.timeout = Number(a.slice(10));
    else if (a.startsWith('--')) { console.error(`checkout-check: unknown option ${a}\n${USAGE}`); process.exit(1); }
    else if (!opts.base) opts.base = a;
    else { console.error(USAGE); process.exit(1); }
  }
  if (!opts.base || !Number.isFinite(opts.timeout) || opts.timeout <= 0) { console.error(USAGE); process.exit(1); }
  try { new URL(opts.base); } catch { console.error(`checkout-check: not a URL: ${opts.base}`); process.exit(1); }
  opts.base = opts.base.replace(/\/+$/, '');
  return opts;
}

class Skip extends Error {}

const SEL = {
  products: 'li.product, .wc-block-product, .wp-block-post.product, .wc-block-grid__product',
  productLink: 'li.product a[href*="/product/"], .wc-block-product a[href*="/product/"], .wp-block-post.product a[href*="/product/"], .wc-block-grid__product a[href*="/product/"]',
  price: '.price .amount, .wp-block-woocommerce-product-price, .woocommerce-Price-amount, .wc-block-components-product-price',
  addButton: 'button.single_add_to_cart_button, form.cart button[type="submit"], .wp-block-add-to-cart-form button[type="submit"]',
  variations: 'form.variations_form, table.variations, .wc-block-add-to-cart-with-options-variation-selector',
  ajaxButton: 'a.ajax_add_to_cart.product_type_simple, .wc-block-components-product-button button:not(.disabled)',
  miniCart: '.wc-block-mini-cart__badge, .cart-contents-count, .cart-count, .header-cart-count',
  cartRows: 'tr.cart_item, .wc-block-cart-items__row',
  checkoutBlock: '.wp-block-woocommerce-checkout, .wc-block-checkout',
  checkoutForm: 'form.woocommerce-checkout',
  billing: '#billing_first_name, #billing_email, #email, #billing-first_name, #billing_address_1, #billing-address_1',
  payment: 'ul.wc_payment_methods li, .wc-block-components-radio-control--highlight-checked, .wc-block-checkout__payment-method .wc-block-components-radio-control__option, #payment .payment_methods input',
};

async function run(opts) {
  const results = [];
  const toMs = opts.timeout * 1000;
  const abs = (p) => (/^https?:\/\//.test(p) ? p : opts.base + (p.startsWith('/') ? p : '/' + p));
  const state = { shopUrl: null, productUrl: null, categoryUrl: null, cartUrl: null, checkoutUrl: null, cartTotals: null };

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    ignoreHTTPSErrors: true,
    userAgent: 'wp-ops-checkout-check (+https://github.com/imagewize/wp-ops)',
  });
  const page = await context.newPage();
  page.setDefaultTimeout(toMs);
  const consoleErrors = [];
  page.on('pageerror', (e) => consoleErrors.push(e.message));

  async function go(url) {
    const t0 = Date.now();
    const resp = await page.goto(url, { waitUntil: 'load', timeout: toMs });
    const status = resp ? resp.status() : 0;
    if (status >= 400) throw new Error(`HTTP ${status} for ${url}`);
    return { status, ms: Date.now() - t0 };
  }

  async function storeCart() {
    return page.evaluate(async (root) => {
      const r = await fetch(root + '/wp-json/wc/store/v1/cart', { credentials: 'same-origin', cache: 'no-store' });
      if (!r.ok) throw new Error('Store API cart returned HTTP ' + r.status);
      return r.json();
    }, opts.base);
  }

  async function step(id, name, fn) {
    const t0 = Date.now();
    const r = { id, name, status: 'pass', note: '', ms: 0 };
    try {
      r.note = (await fn(r)) || '';
    } catch (e) {
      if (e instanceof Skip) { r.status = 'skip'; r.note = e.message; }
      else {
        r.status = 'fail';
        r.note = e.message.split('\n')[0];
        if (opts.screenshots) {
          try {
            fs.mkdirSync(opts.screenshots, { recursive: true });
            r.screenshot = path.join(opts.screenshots, `step-${id}-${name.replace(/\W+/g, '-').toLowerCase()}.png`);
            await page.screenshot({ path: r.screenshot, fullPage: true });
          } catch { /* a failed screenshot must not hide the real failure */ }
        }
      }
    }
    r.ms = Date.now() - t0;
    results.push(r);
    return r;
  }

  // 1 shop
  await step(1, 'shop page', async () => {
    let last;
    for (const p of ['/shop/', '/']) {
      try { await go(abs(p)); } catch (e) { last = e; continue; }
      const n = await page.locator(SEL.products).count();
      if (n > 0) {
        state.shopUrl = page.url();
        // Discover a category and the first product from what the shop shows.
        state.categoryUrl = await page.locator('a[href*="/product-category/"]').first().getAttribute('href').catch(() => null);
        state.firstProduct = await page.locator(SEL.productLink).first().getAttribute('href').catch(() => null);
        return `${n} products listed`;
      }
      last = new Error(`no products listed at ${page.url()}`);
    }
    throw last;
  });

  // 2 category
  await step(2, 'category page', async () => {
    const target = opts.category ? abs(opts.category) : state.categoryUrl;
    if (!target) throw new Skip('no category link found on the shop page (pass --category)');
    await go(target);
    const n = await page.locator(SEL.products).count();
    if (n === 0) throw new Error('category page lists no products');
    return `${n} products listed`;
  });

  // 3 product
  await step(3, 'product page', async () => {
    const target = opts.product ? abs(opts.product) : state.firstProduct;
    if (!target) throw new Skip('no product found (shop step failed; pass --product)');
    await go(target);
    state.productUrl = page.url();
    if (await page.locator(SEL.variations).count()) {
      state.variable = true;
      throw new Skip('variable product: pass --product with a simple product to test add to cart');
    }
    if (!(await page.locator(SEL.price).first().isVisible().catch(() => false))) throw new Error('no visible price');
    if (!(await page.locator(SEL.addButton).first().isVisible().catch(() => false))) throw new Error('add-to-cart button not visible');
    return 'price and add-to-cart visible';
  });

  // 4 add to cart
  await step(4, 'add to cart', async () => {
    if (!state.productUrl || state.variable) throw new Skip('no simple product page to add from');
    if (page.url() !== state.productUrl) await go(state.productUrl);
    const before = (await storeCart()).items_count;
    const notes = [];
    await Promise.all([
      page.waitForLoadState('load').catch(() => {}),
      page.locator(SEL.addButton).first().click(),
    ]);
    await page.waitForTimeout(1500);
    const after = await storeCart();
    if (after.items_count <= before) throw new Error(`cart did not change after clicking add to cart (${before} -> ${after.items_count})`);
    notes.push(`product page add OK (${after.items_count} in cart)`);

    // Mini-cart count, if the theme has one.
    const badge = page.locator(SEL.miniCart).first();
    if (await badge.count()) {
      const txt = (await badge.innerText().catch(() => '')).trim();
      notes.push(/\d/.test(txt) ? `mini-cart shows "${txt}"` : 'mini-cart count empty');
      if (!/\d/.test(txt)) throw new Error(notes.join('; '));
    }

    // AJAX add from the shop grid, when a simple-product button exists.
    if (state.shopUrl) {
      await go(state.shopUrl);
      const btn = page.locator(SEL.ajaxButton).first();
      if (await btn.count()) {
        const prev = (await storeCart()).items_count;
        await btn.click();
        await page.waitForTimeout(2000);
        const now = (await storeCart()).items_count;
        if (now <= prev) throw new Error(`${notes.join('; ')}; AJAX add on the shop page did not change the cart`);
        notes.push('AJAX add OK');
      } else {
        notes.push('no AJAX button on the shop page');
      }
    }
    return notes.join('; ');
  });

  // 5 cart
  await step(5, 'cart page', async (r) => {
    const cart = await storeCart();
    if (cart.items_count === 0) throw new Skip('cart is empty (add to cart did not run)');
    const cartHref = await page.locator('a[href*="/cart"]').first().getAttribute('href').catch(() => null);
    const nav = await go(cartHref && /^https?:/.test(cartHref) ? cartHref : abs('/cart/'));
    state.cartUrl = page.url();
    r.navMs = nav.ms;
    const rows = await page.locator(SEL.cartRows).count();
    if (rows < cart.items.length) throw new Error(`cart page shows ${rows} line(s), Store API has ${cart.items.length}`);
    const t = cart.totals;
    const minor = (v) => Number(v);
    const linesSum = cart.items.reduce((s, i) => s + minor(i.totals.line_total), 0);
    if (Math.abs(linesSum - minor(t.total_items)) > 1) {
      throw new Error(`line totals (${linesSum}) do not add up to the items total (${t.total_items})`);
    }
    const expected = minor(t.total_items) + minor(t.total_fees) + minor(t.total_shipping || 0)
      - minor(t.total_discount) + minor(t.total_tax);
    if (Math.abs(expected - minor(t.total_price)) > 1) {
      throw new Error(`cart total ${t.total_price} does not match items+fees+shipping-discount+tax (${expected})`);
    }
    state.cartTotals = t;
    const unit = Math.pow(10, t.currency_minor_unit ?? 2);
    return `${rows} line(s), total ${(minor(t.total_price) / unit).toFixed(t.currency_minor_unit ?? 2)} ${t.currency_code} adds up (${nav.ms} ms uncached)`;
  });

  // 6 checkout
  await step(6, 'checkout page', async (r) => {
    if (!state.cartTotals) throw new Skip('no cart to check out');
    const cartHref = await page.locator('a[href*="/checkout"]').first().getAttribute('href').catch(() => null);
    const nav = await go(cartHref && /^https?:/.test(cartHref) ? cartHref : abs('/checkout/'));
    state.checkoutUrl = page.url();
    r.navMs = nav.ms;
    if (!/checkout/.test(new URL(page.url()).pathname)) throw new Error(`checkout redirected to ${page.url()}`);
    const isBlock = (await page.locator(SEL.checkoutBlock).count()) > 0;
    const isShortcode = (await page.locator(SEL.checkoutForm).count()) > 0;
    if (!isBlock && !isShortcode) throw new Error('no checkout form found (neither block nor shortcode)');
    r.checkoutType = isBlock ? 'block' : 'shortcode';
    // Block checkout renders client-side: wait for fields.
    await page.locator(SEL.billing).first().waitFor({ state: 'attached', timeout: toMs }).catch(() => {});
    if ((await page.locator(SEL.billing).count()) === 0) throw new Error(`${r.checkoutType} checkout renders no billing fields`);
    const payments = await page.locator(SEL.payment).count();
    const zero = Number(state.cartTotals.total_price) === 0;
    if (payments === 0 && !zero) throw new Error(`${r.checkoutType} checkout shows no payment methods`);
    return `${r.checkoutType} checkout, billing fields present, ${payments} payment method(s) (${nav.ms} ms uncached)`;
  });

  await browser.close();
  return { results, consoleErrors };
}

function report(opts, out, started) {
  const failed = out.results.filter((r) => r.status === 'fail').length;
  const data = {
    url: opts.base,
    date: started.toISOString(),
    ok: failed === 0,
    steps: out.results,
    js_errors: out.consoleErrors,
  };
  if (opts.json) {
    console.log(JSON.stringify(data, null, 2));
  } else {
    console.log(`checkout-check ${opts.base}  (${started.toISOString()})\n`);
    for (const r of out.results) {
      const tag = { pass: 'PASS', fail: 'FAIL', skip: 'SKIP' }[r.status];
      console.log(`${tag}  ${r.id}. ${r.name.padEnd(14)} ${String(r.ms).padStart(6)} ms  ${r.note}`);
      if (r.screenshot) console.log(`        screenshot: ${r.screenshot}`);
    }
    if (out.consoleErrors.length) console.log(`\nJS errors seen: ${out.consoleErrors.length} (first: ${out.consoleErrors[0]})`);
    console.log(`\n${failed ? `${failed} step(s) failed` : 'No step failed'}. No order was placed.`);
  }
  return failed ? 2 : 0;
}

(async () => {
  const opts = parseArgs(process.argv.slice(2));
  const started = new Date();
  let out;
  try {
    out = await run(opts);
  } catch (e) {
    console.error(`checkout-check: could not run: ${e.message}`);
    process.exit(1);
  }
  process.exit(report(opts, out, started));
})();
