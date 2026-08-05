#!/usr/bin/env node
/**
 * CF7 Rate Limit Smoke Test
 *
 * Verifies that Contact Form 7 submissions still work after deploying
 * Nginx rate limit changes. Uses Playwright to fill and submit the form,
 * then checks that all CF7 API requests return 200.
 *
 * Usage:
 *   node cf7-smoke-test.js <contact-page-url> [--name "Test"] [--email "test@example.com"]
 *
 * Examples:
 *   node cf7-smoke-test.js https://example.com/contact/
 *   node cf7-smoke-test.js https://yoursite.com/contact/ --name "QA Bot" --email "qa@yoursite.com"
 *
 * @desc     Playwright smoke test verifying CF7 submissions still work after an Nginx rate-limit deploy
 * @category monitoring
 * @platform wordpress
 * @runs     local
 * @requires node
 * @arg      contact-page-url  required  {https://example.com/contact/}  Contact page URL to test
 * @flag     --name     optional  {"QA Bot"}  Test submitter name
 * @flag     --email    optional  {qa@example.com}  Test submitter email
 * @flag     --subject  optional  {"Rate limit smoke test"}  Test subject
 * @flag     --message  optional  {"..."}  Test message body
 * @example  wp-ops cf7-smoke-test https://example.com/contact/ --name "QA Bot"
 */

const { chromium } = require('playwright');

const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));

if (!url) {
  console.error('Usage: node cf7-smoke-test.js <contact-page-url> [--name "Name"] [--email "email@example.com"]');
  process.exit(1);
}

function getArg(flag, fallback) {
  const idx = args.indexOf(flag);
  return idx !== -1 && args[idx + 1] ? args[idx + 1] : fallback;
}

const testName = getArg('--name', 'Smoke Test');
const testEmail = getArg('--email', 'smoke-test@example.com');
const testSubject = getArg('--subject', 'Rate limit smoke test');
const testMessage = getArg('--message', 'Automated smoke test after Nginx rate limit deploy.');

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();

  const cf7Requests = [];

  page.on('response', (response) => {
    const reqUrl = response.url();
    if (reqUrl.includes('contact-form-7')) {
      cf7Requests.push({
        method: response.request().method(),
        url: reqUrl.replace(/.*\/wp-json/, '/wp-json'),
        status: response.status(),
      });
    }
  });

  console.log(`\n  Navigating to ${url}`);
  await page.goto(url, { waitUntil: 'networkidle' });

  const form = page.getByRole('form', { name: 'Contact form' });
  const formExists = await form.count();

  if (!formExists) {
    console.error('  ✗ No Contact Form 7 form found on this page.');
    await browser.close();
    process.exit(1);
  }

  console.log('  Filling form fields...');
  await page.getByRole('textbox', { name: /your name/i }).fill(testName);
  await page.getByRole('textbox', { name: /your email/i }).fill(testEmail);

  const subjectField = page.getByRole('textbox', { name: /subject/i });
  if (await subjectField.count()) {
    await subjectField.fill(testSubject);
  }

  const messageField = page.getByRole('textbox', { name: /your message/i });
  if (await messageField.count()) {
    await messageField.fill(testMessage);
  }

  console.log('  Submitting form...');
  await page.getByRole('button', { name: /submit/i }).click();

  await page.waitForTimeout(3000);

  console.log('\n  CF7 API Requests:');
  console.log('  ' + '-'.repeat(70));

  let allPassed = true;

  for (const req of cf7Requests) {
    const icon = req.status === 200 ? '✓' : '✗';
    const line = `  ${icon} [${req.method}] ${req.url} → ${req.status}`;
    console.log(line);
    if (req.status !== 200) allPassed = false;
  }

  console.log('  ' + '-'.repeat(70));

  const successMsg = await form.locator('[role="alert"], .wpcf7-response-output').textContent().catch(() => '');

  if (successMsg && successMsg.toLowerCase().includes('sent')) {
    console.log('  ✓ Success message displayed on page');
  } else {
    console.log('  ✗ No success message found');
    allPassed = false;
  }

  if (cf7Requests.length === 0) {
    console.log('  ✗ No CF7 API requests captured — form may not be using AJAX');
    allPassed = false;
  }

  console.log(allPassed ? '\n  ✓ PASS — Form submission works correctly\n' : '\n  ✗ FAIL — Check output above\n');

  await browser.close();
  process.exit(allPassed ? 0 : 1);
})();
