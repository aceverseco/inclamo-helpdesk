import { chromium, request, expect } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import { api, workspace, signIn, openSupport, saveLayout, resetLayouts, product, empty, randomUUID } from './helpers.mjs';
const output = process.env.E2E_OUTPUT || '/out'; await mkdir(output, { recursive: true });
const context = await request.newContext();
const agent = await api(context), admin = await api(context, 'theme-admin@example.test');
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } }); page.setDefaultTimeout(20_000);
const errors = []; page.on('pageerror', error => errors.push(error.message));
const editor = page => page.locator('.reply-box .ProseMirror').first();
const result = {};
const profile = (await admin.call('get', '/api/v1/profile')).body;
async function card(page) {
  const order = page.getByTestId('inclamo-order-#1001');
  const heading = order.getByRole('button', { name: /#1001 Placed/ });
  if (await heading.getAttribute('aria-expanded') !== 'true') await heading.click();
  if (!await order.locator('details').evaluate(node => node.open)) await order.locator('summary').click();
  return order;
}
try {
  await resetLayouts(admin); await saveLayout(agent, empty());
  await workspace(page, agent); await page.getByRole('tab', { name: 'Manage', exact: true }).click();
  const order = await card(page); await order.getByTestId('inclamo-order-mark').click();
  await expect(order.getByTestId('inclamo-order-unmark')).toBeVisible();
  await page.getByRole('tab', { name: 'Details', exact: true }).click();
  await expect(page.locator('[data-widget-host="conversation-sidebar"] [data-widget]')).toHaveCount(0);
  const tag = `Synthetic variable reply ${randomUUID()} `;
  await editor(page).click(); await page.keyboard.type(tag);
  await page.keyboard.type('{{order.number', { delay: 30 });
  const picker = page.locator('[data-popover-content]').last();
  await expect(picker.getByRole('option')).toHaveCount(1); await page.keyboard.press('Enter');
  await expect(editor(page)).toContainText('#1001');
  await page.locator('.reply-box').getByRole('button', { name: /^Send/ }).click();
  await expect.poll(async () => (await agent.call('get', '/conversations/1/messages')).body.payload.some(message => message.message_type === 1 && !message.private && message.content.includes(tag.trim()) && message.content.includes('#1001'))).toBe(true);
  await page.getByRole('tab', { name: 'Private Note', exact: true }).click();
  await editor(page).fill(`Synthetic native private note ${tag}`);
  await page.locator('.reply-box').getByRole('button', { name: /Add Note|Send/ }).click();
  await expect.poll(async () => (await agent.call('get', '/conversations/1/messages')).body.payload.some(message => message.private && message.content.includes(tag.trim()))).toBe(true);
  result.native_workflow = 'marked-order variable, public reply and private note passed with all Details widgets hidden';
  await agent.call('delete', '/inclamo/shopify/conversations/1/order');
  await saveLayout(agent, product()); await page.close();

  const appearance = await browser.newPage({ viewport: { width: 1440, height: 900 } }); appearance.setDefaultTimeout(20_000);
  await workspace(appearance, admin);
  for (const [mode, locale] of [['dark', 'en'], ['light', 'ar']]) {
    await admin.call('put', '/api/v1/profile', { profile: { ui_settings: { ...profile.ui_settings, locale, is_contact_sidebar_open: true } } });
    await appearance.evaluate(mode => localStorage.setItem('color_scheme', mode), mode);
    await appearance.reload(); await expect(editor(appearance)).toBeVisible();
    await expect(appearance.locator('#app[dir]')).toHaveAttribute('dir', locale === 'ar' ? 'rtl' : 'ltr');
    if (mode === 'dark') await expect(appearance.locator('body')).toHaveClass(/dark/);
    expect(await appearance.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await appearance.screenshot({ path: `${output}/widgets-${mode}-${locale}.png` });
    await appearance.locator('.reference-customer-pane').getByTestId('configure-widgets').first().click();
    await expect(appearance.getByTestId('widget-layout-editor')).toBeVisible();
    await appearance.screenshot({ path: `${output}/configure-${mode}-${locale}.png` });
    await appearance.keyboard.press('Escape');
    await openSupport(appearance);
    await appearance.screenshot({ path: `${output}/support-${mode}-${locale}.png` });
    await appearance.keyboard.press('Escape');
  }
  await appearance.close(); result.appearance = 'dark, RTL and dialog keyboard checks passed';
  expect(errors).toEqual([]); result.uncaught_errors = errors;
  console.log(JSON.stringify(result));
  await writeFile(`${output}/workflow-results.json`, JSON.stringify(result, null, 2));
} finally {
  await agent.call('delete', '/inclamo/shopify/conversations/1/order');
  await admin.call('put', '/api/v1/profile', { profile: { ui_settings: profile.ui_settings } });
  await saveLayout(agent, product());
  await browser.close(); await context.dispose();
}
