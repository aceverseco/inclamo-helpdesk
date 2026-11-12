import { chromium, request, expect } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { api, signIn, resetLayouts } from './helpers.mjs';
const context = await request.newContext(); const browser = await chromium.launch();
const output = process.env.E2E_OUTPUT || '/out'; await mkdir(output, { recursive: true });
const result = { method: 'Same synthetic database, Chromium and warm conversation/dialog interactions from the theme harness; one warmup plus five samples. Readiness allows the existing 60-second commerce cache.', samples: {} };
const editor = page => page.locator('.reply-box .ProseMirror').first();
try {
  await resetLayouts(await api(context, 'theme-admin@example.test'));
  for (const [name, base] of [['before', 'http://baseline:3000'], ['after', 'http://client:3000']]) {
    const session = await api(context, 'theme-admin@example.test', base);
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } }); page.setDefaultTimeout(20_000);
    const panels = []; page.on('request', request => { if (/\/conversations\/\d+\/panel$/.test(request.url())) panels.push(request.url()); });
    await signIn(page, session); await page.goto(`${base}/app/accounts/1/conversations/1`);
    await expect(editor(page)).toBeVisible();
    if (!await page.locator('.reference-customer-pane').isVisible()) await page.getByTestId('inclamo-toggle-customer').click();
    await expect(page.locator('.reference-customer-pane')).toBeVisible();
    await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'matched');
    const timings = { conversation: [], dialog: [] };
    for (let iteration = 0; iteration < 6; iteration += 1) {
      await page.getByText('Alex Example', { exact: true }).first().click(); await expect(page).toHaveURL(/\/conversations\/2$/);
      await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'none');
      const start = performance.now();
      await page.getByText('Maya Example', { exact: true }).first().click(); await expect(page).toHaveURL(/\/conversations\/1$/);
      await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'matched'); await expect(editor(page)).toBeVisible();
      const opened = performance.now();
      const order = page.getByTestId('inclamo-order-#1001');
      const heading = order.getByRole('button', { name: /#1001 Placed/ });
      if (await heading.getAttribute('aria-expanded') !== 'true') await heading.click();
      if (!await order.locator('details').evaluate(node => node.open)) await order.locator('summary').click();
      await order.getByTestId('inclamo-action-cancel').click(); await expect(page.getByTestId('inclamo-action-dialog')).toBeVisible();
      const dialog = performance.now(); await page.keyboard.press('Escape');
      if (iteration) { timings.conversation.push(opened - start); timings.dialog.push(dialog - opened); }
    }
    const median = values => [...values].sort((a,b) => a-b)[Math.floor(values.length/2)];
    result.samples[name] = { timings, median: Object.fromEntries(Object.entries(timings).map(([key, values]) => [key, median(values)])), panel_requests: panels.length };
    console.log(JSON.stringify({ name, ...result.samples[name] }));
    await page.close();
  }
  const before = result.samples.before.median.conversation, after = result.samples.after.median.conversation;
  result.conversation_delta_ms = after - before;
  result.allowed_delta_ms = Math.max(50, before * .1);
  expect(result.conversation_delta_ms).toBeLessThanOrEqual(result.allowed_delta_ms);
  await writeFile(`${output}/performance.json`, JSON.stringify(result, null, 2)); console.log(JSON.stringify(result));
} finally { await browser.close(); await context.dispose(); }
