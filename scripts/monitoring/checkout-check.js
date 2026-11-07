#!/usr/bin/env node

/**
 * Walk a WooCommerce store's buying path, by default without placing an order
 *
 * Opens a fresh browser session, loads the shop, a category and a product,
 * adds the product to the cart, checks the cart page and its totals against
 * the WooCommerce Store API, and loads the checkout page. By default it stops
 * there: no order is placed, so it is safe on production. The cart session it
 * creates is abandoned.
 *
 * With --place-order it goes on: fills the checkout with marked test data,
 * pays with an offline method (cash on delivery, bank transfer or cheque; no
 * card, ever), checks the order-received page, optionally the confirmation
 * email in Mailpit, and with --cleanup deletes the marked order again via
 * WP-CLI. It refuses to run on a host that does not look like local or
 * staging unless you pass --allow-production, which a site's update manifest
 * should only allow after the client has agreed in writing (cleanup does not
 * undo webhooks, ERP sync or emails that already fired).
 *
 * A store with no offline payment method can have one switched on just for
 * the run: --enable-payment=bacs (with --wp) enables the gateway, and puts it
 * back to its previous state when the run ends, fails or is interrupted. Real
 * shoppers can see the method while it is on, so prefer local for this.
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
 * @desc     Walk shop > product > cart > checkout on a WooCommerce store; read-only by default, --place-order for a test purchase on local/staging
 * @category monitoring
 * @platform any
 * @runs     local
 * @mutates  true
 * @requires node
 * @arg      url  required  {https://shop.example.com}  Store base URL (a subsite path like http://demo.test/shop-site is fine)
 * @flag     --product      optional  {/product/test-item/}  Simple product to add to the cart (default: first on the shop page)
 * @flag     --category     optional  {/product-category/test/}  Category page to load (default: discovered from the shop page)
 * @flag     --screenshots  optional  {shots}  Directory for a screenshot of each failed step
 * @flag     --place-order  optional  {}  Also place a test order with an offline payment method (local/staging hosts only)
 * @flag     --allow-production optional  {}  Allow --place-order on a host that does not look like local/staging (needs the client's written OK)
 * @flag     --payment      optional  {cod}  Payment method id for --place-order (default: cod, bacs or cheque, whichever the checkout offers)
 * @flag     --enable-payment optional  {bacs}  Turn this offline gateway on for the run and restore it afterwards (needs --wp; shoppers can see it meanwhile)
 * @flag     --email        optional  {wp-ops-checkout-check+1@example.test}  Billing email for the test order (must start with wp-ops-checkout-check)
 * @flag     --mailpit      optional  {http://imagewize.test:8025}  Mailpit or MailHog URL: check that the order confirmation email arrives (API auto-detected)
 * @flag     --mailhog      optional  {http://localhost:8025}  Same as --mailpit
 * @flag     --cleanup      optional  {}  Delete the marked test order afterwards (needs --place-order and --wp)
 * @flag     --wp           optional  {trellis vm shell --workdir /srv/www/site/current -- wp}  WP-CLI command prefix for --cleanup
 * @flag     --wp-dir       optional  {~/code/site/trellis}  Directory to run the --wp command from
 * @flag     --wp-user      optional  {1}  WordPress admin user id for wp wc commands (default: 1)
 * @flag     --json         optional  {}  Print the result as JSON only
 * @flag     --timeout      optional  {30}  Seconds per page load before the step fails
 * @example  wp-ops checkout-check https://shop.example.com
 * @example  wp-ops checkout-check http://demo.imagewize.test/winespring --screenshots=shots --json
 * @example  wp-ops checkout-check http://demo.imagewize.test/winespring --place-order --mailpit=http://imagewize.test:8025 --cleanup --wp-dir=~/code/imagewize.com/trellis --wp="trellis vm shell --workdir /srv/www/demo.imagewize.com/current -- wp"
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

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

const MARKER = 'wp-ops-checkout-check';
const USAGE = 'Usage: checkout-check.js <store-url> [--product=/path/] [--category=/path/] [--screenshots=dir] [--json] [--timeout=30]\n' +
  '       [--place-order [--allow-production] [--payment=cod] [--enable-payment=bacs] [--email=wp-ops-checkout-check+1@example.test] [--mailpit=URL|--mailhog=URL]\n' +
  '        [--cleanup --wp="<wp-cli prefix>" [--wp-dir=dir] [--wp-user=1]]]';

function parseArgs(argv) {
  const opts = { json: false, timeout: 30, wpUser: '1' };
  for (const a of argv) {
    if (a === '--json') opts.json = true;
    else if (a === '-h' || a === '--help') { console.log(USAGE); process.exit(0); }
    else if (a.startsWith('--product=')) opts.product = a.slice(10);
    else if (a.startsWith('--category=')) opts.category = a.slice(11);
    else if (a.startsWith('--screenshots=')) opts.screenshots = a.slice(14);
    else if (a.startsWith('--timeout=')) opts.timeout = Number(a.slice(10));
    else if (a === '--place-order') opts.placeOrder = true;
    else if (a === '--allow-production') opts.allowProduction = true;
    else if (a === '--cleanup') opts.cleanup = true;
    else if (a.startsWith('--payment=')) opts.payment = a.slice(10);
    else if (a.startsWith('--enable-payment=')) opts.enablePayment = a.slice(17);
    else if (a.startsWith('--email=')) opts.email = a.slice(8);
    else if (a.startsWith('--mailpit=')) opts.mailpit = a.slice(10).replace(/\/+$/, '');
    else if (a.startsWith('--mailhog=')) opts.mailpit = a.slice(10).replace(/\/+$/, '');
    else if (a.startsWith('--wp=')) opts.wp = a.slice(5);
    else if (a.startsWith('--wp-dir=')) opts.wpDir = a.slice(9).replace(/^~(?=\/|$)/, os.homedir());
    else if (a.startsWith('--wp-user=')) opts.wpUser = a.slice(10);
    else if (a.startsWith('--')) { console.error(`checkout-check: unknown option ${a}\n${USAGE}`); process.exit(1); }
    else if (!opts.base) opts.base = a;
    else { console.error(USAGE); process.exit(1); }
  }
  if (!opts.base || !Number.isFinite(opts.timeout) || opts.timeout <= 0) { console.error(USAGE); process.exit(1); }
  try { new URL(opts.base); } catch { console.error(`checkout-check: not a URL: ${opts.base}`); process.exit(1); }
  opts.base = opts.base.replace(/\/+$/, '');
  if ((opts.cleanup || opts.mailpit || opts.payment || opts.enablePayment || opts.email || opts.allowProduction) && !opts.placeOrder) {
    console.error('checkout-check: --cleanup, --mailpit, --payment, --enable-payment, --email and --allow-production only make sense with --place-order');
    process.exit(1);
  }
  if (opts.enablePayment && !opts.wp) { console.error('checkout-check: --enable-payment needs --wp="<wp-cli command prefix>"'); process.exit(1); }
  if (opts.enablePayment && !/^[a-z0-9_]+$/.test(opts.enablePayment)) { console.error('checkout-check: --enable-payment takes a gateway id such as bacs or cod'); process.exit(1); }
  if (opts.cleanup && !opts.wp) { console.error('checkout-check: --cleanup needs --wp="<wp-cli command prefix>"'); process.exit(1); }
  if (opts.placeOrder) {
    opts.email = opts.email || `${MARKER}+${Date.now()}@example.test`;
    if (!opts.email.startsWith(MARKER)) { console.error(`checkout-check: --email must start with "${MARKER}" so --cleanup can tell test orders from real ones`); process.exit(1); }
    if (!looksNonProduction(new URL(opts.base).hostname)) {
      if (!opts.allowProduction) {
        console.error(`checkout-check: refusing --place-order on ${new URL(opts.base).hostname}: it does not look like a local or staging host.`);
        console.error('Run it on staging. Production needs the client\'s written OK for every order hook and email, then --allow-production.');
        process.exit(1);
      }
      console.error('checkout-check: WARNING placing a test order on a production-looking host (--allow-production).');
    }
  }
  return opts;
}

// Local and staging hosts: .test/.local/.localhost, loopback and private IPs,
// or a staging-style label (staging, stage, dev, test, uat, acc).
function looksNonProduction(host) {
  if (/(^|\.)(test|local|localhost|internal)$/.test(host)) return true;
  if (/^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host)) return true;
  return host.split('.').some((l) => /^(staging|stage|dev|test|uat|acc|preview)(-.*)?$|(-|^)(staging|stage|uat)(-|$)/.test(l));
}

class Skip extends Error {}

// Plausible addresses per store country (the country field is left as the store sets it).
const ADDRESSES = {
  NL: { address: 'Damrak 1', city: 'Amsterdam', postcode: '1012 LG' },
  DE: { address: 'Unter den Linden 1', city: 'Berlin', postcode: '10117' },
  US: { address: '1600 Pennsylvania Ave NW', city: 'Washington', postcode: '20500', state: 'DC' },
  GB: { address: '10 Downing Street', city: 'London', postcode: 'SW1A 2AA' },
  AU: { address: '1 Macquarie St', city: 'Sydney', postcode: '2000', state: 'NSW' },
  default: { address: 'Main Street 1', city: 'Springfield', postcode: '1000' },
};

const SEL = {
  products: 'li.product, .wc-block-product, .wp-block-post.product, .wc-block-grid__product',
  productLink: 'li.product a[href*="/product/"], .wc-block-product a[href*="/product/"], .wp-block-post.product a[href*="/product/"], .wc-block-grid__product a[href*="/product/"]',
  price: '.price .amount, .wp-block-woocommerce-product-price, .woocommerce-Price-amount, .wc-block-components-product-price',
  addButton: 'button.single_add_to_cart_button, form.cart button[type="submit"], .wp-block-add-to-cart-form button[type="submit"], .wc-block-add-to-cart-with-options button[type="submit"]',
  variations: 'form.variations_form, table.variations, .wp-block-woocommerce-add-to-cart-with-options-variation-selector',
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

  // Click the visible label like a shopper (the block checkout only registers
  // real clicks). Themes that hide the input and its label fall back to a click
  // in the page, which classic checkouts accept.
  async function tick(locator) {
    const id = await locator.getAttribute('id');
    const label = id ? page.locator(`label[for="${id}"]`).first() : null;
    if (label && (await label.isVisible().catch(() => false))) await label.click();
    else if (await locator.isVisible().catch(() => false)) await locator.click();
    else await locator.evaluate((n) => n.click());
  }

  async function fillIf(selector, value) {
    const el = page.locator(selector).first();
    if ((await el.count()) && (await el.isVisible().catch(() => false))) await el.fill(value);
  }

  // Pick an option for every attribute of a classic variation form until the
  // add-to-cart button is usable. Returns the chosen options, e.g. "color=Red".
  async function chooseVariation() {
    const form = page.locator('form.variations_form').first();
    if (!(await form.count())) return chooseBlockVariation();
    const selects = form.locator('select[name^="attribute_"]');
    const n = await selects.count();
    const usable = 'button.single_add_to_cart_button:not(.disabled):not(.wc-variation-selection-needed):not(.wc-variation-is-unavailable)';
    for (let k = 0; k < 4; k++) {
      const picked = [];
      for (let i = 0; i < n; i++) {
        const sel = selects.nth(i);
        const opts = await sel.locator('option:not([value=""]):not([disabled])').evaluateAll((os) => os.map((o) => [o.value, o.textContent.trim()]));
        if (!opts.length) continue;
        const [val, label] = opts[Math.min(k, opts.length - 1)];
        await sel.selectOption(val);
        picked.push(`${(await sel.getAttribute('name')).replace('attribute_', '')}=${label}`);
      }
      await page.waitForTimeout(800);
      if (await page.locator(usable).count()) return picked.join(', ');
    }
    throw new Error('no variation combination made add to cart available (all combinations unavailable?)');
  }

  // WooCommerce's block variation selector: one group per attribute, with
  // radio "chips" (or a select) inside; the form has .is-invalid until valid.
  async function chooseBlockVariation() {
    const form = page.locator('form.wc-block-add-to-cart-with-options').first();
    const groups = form.locator('.wp-block-woocommerce-add-to-cart-with-options-variation-selector-attribute');
    const n = await groups.count();
    if (!n) throw new Skip('variable product with a variation selector this check does not know (pass a simple --product)');
    for (let k = 0; k < 4; k++) {
      const picked = [];
      for (let i = 0; i < n; i++) {
        const g = groups.nth(i);
        const name = (await g.locator('[class*="attribute-name"]').first().innerText().catch(() => `attribute ${i + 1}`)).trim();
        const chips = g.locator('.wc-block-product-filter-chips__item:not([disabled])');
        const cn = await chips.count();
        if (cn) {
          const chip = chips.nth(Math.min(k, cn - 1));
          picked.push(`${name}=${(await chip.innerText()).trim()}`);
          await chip.click();
        } else {
          const sel = g.locator('select').first();
          const vals = await sel.locator('option:not([value=""]):not([disabled])').evaluateAll((os) => os.map((o) => [o.value, o.textContent.trim()]));
          if (!vals.length) continue;
          const [val, label] = vals[Math.min(k, vals.length - 1)];
          await sel.selectOption(val);
          picked.push(`${name}=${label}`);
        }
      }
      await page.waitForTimeout(800);
      if (!(await form.evaluate((f) => f.classList.contains('is-invalid')))) return picked.join(', ');
    }
    throw new Error('no variation combination made the add-to-cart form valid');
  }

  // First link on the current page whose path is exactly /<word>/ with no query
  // (a plain match on "/cart" also hits remove-item and add-to-cart links).
  async function pageLink(word) {
    const hrefs = await page.locator(`a[href*="/${word}"]`).evaluateAll((as) => as.map((a) => a.href));
    return hrefs.find((h) => {
      try { const u = new URL(h); return !u.search && new RegExp(`/${word}/?$`).test(u.pathname); } catch { return false; }
    }) || null;
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
    // An order form or landing page instead of a shop: fine when the product is given.
    if (opts.product && !(last && /^HTTP /.test(last.message))) {
      throw new Skip('no product grid on the shop page (order form or landing page); using --product');
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
    if (await page.locator(SEL.variations).count()) state.variable = true;
    if (!(await page.locator(SEL.price).first().isVisible().catch(() => false))) throw new Error('no visible price');
    if (!(await page.locator(SEL.addButton).first().isVisible().catch(() => false))) throw new Error('add-to-cart button not visible');
    return 'price and add-to-cart visible';
  });

  // 4 add to cart
  await step(4, 'add to cart', async () => {
    if (!state.productUrl) throw new Skip('no product page to add from');
    if (page.url() !== state.productUrl) await go(state.productUrl);
    const before = (await storeCart()).items_count;
    const notes = [];
    if (state.variable) notes.push(`variation: ${await chooseVariation()}`);
    await Promise.all([
      page.waitForLoadState('load').catch(() => {}),
      page.locator(SEL.addButton).first().click(),
    ]);
    await page.waitForTimeout(1500);
    const after = await storeCart();
    if (after.items_count <= before) throw new Error(`cart did not change after clicking add to cart (${before} -> ${after.items_count})`);
    notes.push(`product page add OK (${after.items_count} in cart)`);
    if (state.variable) state.variableAdded = true;

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
    const nav = await go((await pageLink('cart')) || abs('/cart/'));
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
    const nav = await go((await pageLink('checkout')) || abs('/checkout/'));
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

  if (opts.placeOrder) {
    // 7 place the order
    await step(7, 'place order', async (r) => {
      if (!state.checkoutUrl || !state.cartTotals) throw new Skip('checkout step did not pass; nothing to place');
      if (!page.url().includes('checkout')) await go(state.checkoutUrl);
      await page.locator(SEL.billing).first().waitFor({ state: 'attached', timeout: toMs });

      // Address data that passes validation for the store's own country.
      const countryEl = page.locator('#billing-country, #billing_country, #shipping-country, #shipping_country').first();
      const cc = (await countryEl.count()) ? await countryEl.inputValue().catch(() => '') : '';
      const addr = ADDRESSES[cc] || ADDRESSES.default;
      const vals = { first_name: 'WP Ops', last_name: 'Checkout Check', address_1: addr.address, city: addr.city, postcode: addr.postcode, phone: '+31612345678' };
      await fillIf('#email, #billing_email', opts.email);
      for (const [k, v] of Object.entries(vals)) {
        for (const prefix of ['shipping-', 'billing-', 'shipping_', 'billing_']) {
          await fillIf(`#${prefix}${k}`, v);
        }
      }
      for (const sel of ['#shipping-state', '#billing-state', '#shipping_state', '#billing_state']) {
        const el = page.locator(sel).first();
        if (!(await el.isVisible().catch(() => false))) continue;
        const tag = await el.evaluate((n) => n.tagName);
        if (tag === 'SELECT') {
          const opt = addr.state && (await el.locator(`option[value="${addr.state}"]`).count())
            ? addr.state
            : await el.locator('option:not([value=""])').first().getAttribute('value');
          if (opt) await el.selectOption(opt);
        } else if (addr.state) await el.fill(addr.state);
      }
      // Shipping rates and totals refresh after the address is in.
      await page.waitForTimeout(2000);

      // Payment method: an offline one only, never a card.
      const ids = await page.locator('input[name="radio-control-wc-payment-method-options"], input[name="payment_method"]')
        .evaluateAll((els) => els.map((e) => e.value));
      const wanted = opts.payment ? [opts.payment] : ['cod', 'bacs', 'cheque'];
      const method = wanted.find((m) => ids.includes(m));
      if (!method) throw new Error(`no offline payment method to use (offered: ${ids.join(', ') || 'none'}; wanted: ${wanted.join(', ')})`);
      r.payment = method;
      await tick(page.locator(`input[value="${method}"][name="radio-control-wc-payment-method-options"], #payment_method_${method}`).first());
      if (!(await page.locator(`input[value="${method}"][name="radio-control-wc-payment-method-options"], #payment_method_${method}`).first().evaluate((n) => n.checked))) {
        throw new Error(`could not select the ${method} payment method`);
      }

      for (const sel of ['#terms', '.wc-block-checkout__terms input[type="checkbox"]']) {
        const box = page.locator(sel).first();
        if ((await box.count()) && !(await box.evaluate((n) => n.checked))) await tick(box);
      }

      // The block checkout re-prices after the method changes; click only once
      // the button is enabled and idle, and click again if no checkout request left.
      await page.waitForLoadState('networkidle').catch(() => {});
      await page.waitForFunction(() => {
        const b = document.querySelector('.wc-block-components-checkout-place-order-button, #place_order');
        return b && !b.disabled && b.getAttribute('aria-disabled') !== 'true' && !b.classList.contains('wc-block-components-button--loading');
      }, null, { timeout: toMs });
      let tSubmit = 0;
      const onReq = (rq) => { if (!tSubmit && rq.method() === 'POST' && /\/checkout(\?|$)|wc-ajax=checkout/.test(rq.url())) tSubmit = Date.now(); };
      page.on('request', onReq);
      const button = page.locator('.wc-block-components-checkout-place-order-button, #place_order').first();
      await button.click();
      for (let i = 0; i < 16 && !tSubmit; i++) await page.waitForTimeout(250);
      if (!tSubmit && !/order-received/.test(page.url())) {
        await button.click();
        for (let i = 0; i < 16 && !tSubmit; i++) await page.waitForTimeout(250);
      }
      page.off('request', onReq);
      try {
        await page.waitForURL(/order-received/, { timeout: toMs });
      } catch {
        const errs = await page.locator('.wc-block-components-validation-error, .woocommerce-error li, .wc-block-components-notice-banner.is-error').allInnerTexts().catch(() => []);
        throw new Error(`order not placed${errs.length ? ': ' + errs.map((e) => e.trim().replace(/\s+/g, ' ')).join(' | ') : ' (still on checkout after ' + opts.timeout + ' s)'}`);
      }
      r.navMs = tSubmit ? Date.now() - tSubmit : null;
      const m = page.url().match(/order-received\/(\d+)/);
      state.orderId = m ? m[1] : null;
      const num = await page.locator('.woocommerce-order-overview__order strong, .wc-block-order-confirmation-summary-list-item__value').first().innerText().catch(() => '');
      state.orderNumber = num.trim() || state.orderId;
      if (!state.orderNumber) throw new Error('order-received page shows no order number');
      r.orderId = state.orderId;
      return `order #${state.orderNumber} placed with ${method}${r.navMs ? ` (${r.navMs} ms from submit to confirmation)` : ''}`;
    });

    // 8 confirmation email
    await step(8, 'confirmation email', async () => {
      if (!state.orderId) throw new Skip('no order was placed');
      if (!opts.mailpit) throw new Skip('no --mailpit given; the order-received page was checked, the email was not');
      const deadline = Date.now() + 20000;
      let found;
      while (Date.now() < deadline && !found) {
        found = await findMail(opts.mailpit, opts.email);
        if (!found) await new Promise((ok) => setTimeout(ok, 1500));
      }
      if (!found) throw new Error(`no email to ${opts.email} within 20 s`);
      return `"${found}" arrived`;
    });

    // 9 cleanup
    await step(9, 'cleanup', async () => {
      if (!opts.cleanup) throw new Skip(state.orderId ? `not requested; order #${state.orderNumber} (id ${state.orderId}) left in place` : 'not requested');
      if (!state.orderId) throw new Skip('no order to delete');
      const wp = (cmd) => wpRun(opts, cmd);
      const raw = wp(`wc shop_order get ${state.orderId} --user=${opts.wpUser} --format=json`);
      const order = JSON.parse(raw.slice(raw.indexOf('{')));
      const email = (order.billing && order.billing.email) || '';
      if (!email.startsWith(MARKER)) throw new Error(`order ${state.orderId} billing email "${email}" does not carry the ${MARKER} marker; not deleting`);
      wp(`wc shop_order delete ${state.orderId} --force=true --user=${opts.wpUser}`);
      return `deleted order id ${state.orderId} (marker ${MARKER})`;
    });
  }

  await browser.close();
  return { results, consoleErrors };
}

// Subject of the first mail to <email> in Mailpit or MailHog, or null. Mailpit
// answers /api/v1/search; MailHog answers /api/v2/search.
async function findMail(root, email) {
  const get = async (url) => { try { const r = await fetch(url); return r.ok ? r.json() : null; } catch { return null; } };
  const mp = await get(`${root}/api/v1/search?query=${encodeURIComponent('to:' + email)}`);
  if (mp) return (mp.messages || [])[0] ? mp.messages[0].Subject : null;
  const mh = await get(`${root}/api/v2/search?kind=to&query=${encodeURIComponent(email)}`);
  if (mh) {
    const m = (mh.items || [])[0];
    return m ? ((m.Content.Headers.Subject || [''])[0] || '(no subject)') : null;
  }
  throw new Error(`no Mailpit or MailHog API at ${root}`);
}

function wpRun(opts, cmd) {
  const u = new URL(opts.base);
  return execSync(`${opts.wp} ${cmd} --url=${u.host}${u.pathname.replace(/\/?$/, '/')}`,
    { cwd: opts.wpDir || process.cwd(), encoding: 'utf8', timeout: 90000, stdio: ['ignore', 'pipe', 'pipe'] });
}

// Turn an offline gateway on for the run; returns a function that restores it.
function enableGateway(opts) {
  const id = opts.enablePayment;
  const was = /^(true|1|yes)$/i.test(wpRun(opts, `wc payment_gateway get ${id} --user=${opts.wpUser} --field=enabled`).trim().split('\n').pop());
  if (was) return () => {};
  wpRun(opts, `wc payment_gateway update ${id} --enabled=true --user=${opts.wpUser}`);
  let done = false;
  return () => {
    if (done) return;
    done = true;
    try { wpRun(opts, `wc payment_gateway update ${id} --enabled=false --user=${opts.wpUser}`); }
    catch (e) { console.error(`checkout-check: COULD NOT turn ${id} off again, do it by hand: ${e.message.split('\n')[0]}`); }
  };
}

function orderNote(out) {
  const placed = out.results.find((r) => r.id === 7 && r.status === 'pass');
  return placed ? `A test order was placed (${placed.note}).` : 'No order was placed.';
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
    console.log(`\n${failed ? `${failed} step(s) failed` : 'No step failed'}. ${orderNote(out)}`);
  }
  return failed ? 2 : 0;
}

(async () => {
  const opts = parseArgs(process.argv.slice(2));
  const started = new Date();
  let out;
  let restore = () => {};
  try {
    if (opts.enablePayment) {
      restore = enableGateway(opts);
      process.on('SIGINT', () => { restore(); process.exit(1); });
    }
    out = await run(opts);
  } catch (e) {
    restore();
    console.error(`checkout-check: could not run: ${e.message}`);
    process.exit(1);
  }
  restore();
  process.exit(report(opts, out, started));
})();
