import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';
const account = process.env.E2E_ACCOUNT_ID || '1';
let admin, store;
test.beforeAll(async ({ playwright }) => {
  admin = await apiAs(await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL }), users.admin);
});
test.afterAll(async () => { await proxy.reset(); if (store) expect((await store.clean()).kept).toEqual([]); });
test('Private draft with authorized editor preview', async ({ page, browser }, info) => {
  const slug = `protected-${runTag('preview')}`;
  const portal = await admin.post('/portals', { portal: { name: 'Protected preview test', slug, config: { default_locale: 'en', allowed_locales: ['en'] } } });
  expect(portal.status).toBe(200);
  const draft = await admin.post(`/portals/${slug}/articles`, { article: { title: 'Private preview article', status: 'draft', content: 'The unpublished return policy.', author_id: admin.userId, locale: 'en' } });
  expect(draft.status).toBe(200);
  const anonymous = await browser.newContext({ baseURL: process.env.HELPDESK_URL });
  try {
    const reader = await anonymous.newPage();
    const response = await reader.goto(`/hc/${slug}/articles/${draft.body.payload.slug}`);
    expect(response.status()).toBe(404);
    await expect(reader.getByText('The unpublished return policy.')).toHaveCount(0);
    await reader.screenshot({ path: info.outputPath('draft-anonymous-404.png'), fullPage: true });
    await signIn(page, users.admin);
    await page.goto(`/app/accounts/${account}/portals/${slug}/en/articles/draft/edit/${draft.body.payload.id}`);
    const popup = page.waitForEvent('popup');
    await page.getByRole('button', { name: 'Preview', exact: true }).click();
    const preview = await popup;
    await expect(preview.getByText('The unpublished return policy.', { exact: true })).toBeVisible();
    await preview.screenshot({ path: info.outputPath('draft-authorized-preview.png'), fullPage: true });
    await preview.close();
  } finally { await anonymous.close(); await admin.delete(`/portals/${slug}`); }
});
test('Fresh cancellation amount and preview recovery', async ({ page }, info) => {
  test.setTimeout(180_000);
  await proxy.reset(); await admin.disconnect(); await admin.connect(bench());
  store = await openStore(runTag('cancelpreview'));
  const customer = await store.customer('CancelPreview');
  const order = await store.order(customer);
  const inbox = await admin.inbox([admin.userId]);
  const conversation = await admin.conversation(inbox, { name: 'Cancellation review', email: customer.email });
  // Shopify's customer search index can lag behind creation. This scenario
  // checks cancellation preview, so select the known fixture customer first.
  const selected = await admin.post(`/inclamo/shopify/conversations/${conversation.id}/customer`, { customer_id: customer.id });
  expect(selected.status).toBe(200);
  await signIn(page, users.admin);
  const card = await orderCard(await openOrders(page, account, conversation.id), order.number);
  await page.route('**/actions/cancel_preview', route => route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }));
  await card.getByTestId('inclamo-action-cancel').click();
  await expect(page.getByTestId('inclamo-cancel-preview-error')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Cancel the order', exact: true })).toBeDisabled();
  await page.unroute('**/actions/cancel_preview');
  await page.getByRole('button', { name: 'Retry preview', exact: true }).click();
  await expect(page.getByTestId('inclamo-cancel-amount')).toContainText('Refund on cancellation:');
  await expect(page.getByTestId('inclamo-cancel-amount')).not.toContainText('[object Object]');
  await expect(page.getByRole('button', { name: 'Cancel the order', exact: true })).toBeEnabled();
  await page.screenshot({ path: info.outputPath('cancellation-fresh-refund.png'), fullPage: true });
  await page.getByTestId('inclamo-cancel-refund').uncheck();
  await expect(page.getByTestId('inclamo-cancel-amount')).toContainText('No money will be refunded.');
});
