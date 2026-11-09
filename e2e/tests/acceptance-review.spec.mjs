import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let agent;
let store;
let conversation;
let addressOrder;
let cancelOrder;

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(300_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  await proxy.reset();
  await admin.disconnect();
  expect((await admin.connect(bench())).status).toBe(201);
  await admin.takeRole(agent.userId);
  const inbox = await admin.inbox([admin.userId, agent.userId]);
  store = await openStore(runTag('review'));
  const customer = await store.customer('Review');
  addressOrder = await store.draftOrder(customer, { items: 2 });
  cancelOrder = await store.draftOrder(customer);
  conversation = await admin.conversation(inbox, { name: 'Acceptance Shopper', email: customer.email, message: 'Please help me change my order.' });
});

test.afterAll(async () => {
  await proxy.reset();
  if (admin) await admin.recheck();
  if (store) await store.clean();
});

test('Setup and administrator settings are reviewable in the combined image', async ({ page }, info) => {
  await admin.disconnect();
  await signIn(page, users.admin);
  let section = await openOrders(page, account, conversation.id);
  await expect(section).toHaveAttribute('data-state', 'not_connected');
  await section.getByTestId('inclamo-connect-open').click();
  await expect(page.getByTestId('inclamo-connect-dialog')).toBeVisible();
  // Empty fields only: no credentials in the screenshot.
  await page.screenshot({ path: info.outputPath('01-connect-store.png'), fullPage: true });
  expect((await admin.connect(bench())).status).toBe(201);

  for (const [route, view] of [
    ['order-actions', 'inclamo-roles-page'], ['preset-rules', 'inclamo-presets-page'],
    ['discount-codes', 'inclamo-discounts-page'], ['sla-policies', 'inclamo-sla-page'], ['ai-agent', 'inclamo-ai-page'],
  ]) {
    await page.goto(`/app/accounts/${account}/settings/${route}`);
    await expect(page.getByTestId(view)).toBeVisible();
    await page.screenshot({ path: info.outputPath(`settings-${route}.png`), fullPage: true });
    if (route === 'order-actions') {
      await page.route('**/inclamo/order_roles', route => route.request().method() === 'POST'
        ? route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }) : route.continue());
      const checkbox = page.getByTestId(`inclamo-role-${agent.userId}`).locator('input');
      await checkbox.click();
      await expect(page.getByTestId('inclamo-role-error')).toContainText('could not be confirmed');
      await expect(checkbox).not.toBeChecked();
      await page.screenshot({ path: info.outputPath('settings-role-error.png'), fullPage: true });
      await page.unroute('**/inclamo/order_roles');
    }
  }
  section = await openOrders(page, account, conversation.id);
  await orderCard(section, addressOrder.number);
  await page.screenshot({ path: info.outputPath('02-order-desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.screenshot({ path: info.outputPath('03-order-laptop.png'), fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test('An address change is visible in Shopify and in the shopper order view', async ({ page, browser }, info) => {
  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation.id);
  const card = await orderCard(section, addressOrder.number);
  await card.getByTestId('inclamo-action-address').click();
  await page.getByTestId('inclamo-address-address1').fill('2 Example Avenue');
  await page.getByTestId('inclamo-address-zip').fill('01030');
  await page.screenshot({ path: info.outputPath('04-address-confirmation.png'), fullPage: true });
  await page.getByRole('button', { name: 'Save address', exact: true }).click();
  const held = async () => (await store.shopify('shopper_order', { id: addressOrder.id })).order;
  await expect.poll(async () => (await held()).shippingAddress).toMatchObject({ address1: '2 Example Avenue', zip: '01030' });
  const order = await held();
  const context = await browser.newContext();
  try {
    const shopper = await context.newPage();
    await shopper.goto(order.statusPageUrl, { waitUntil: 'domcontentloaded' });
    await shopper.screenshot({ path: info.outputPath('05-shopper-address.png'), fullPage: true });
    await expect(shopper.getByText('2 Example Avenue', { exact: false }).first()).toBeVisible();
  } finally {
    await context.close();
  }
});

test('A cancellation is visible in Shopify and in the shopper order view', async ({ page, browser }, info) => {
  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation.id);
  const card = await orderCard(section, cancelOrder.number);
  await card.getByTestId('inclamo-action-cancel').click();
  await expect(page.getByTestId('inclamo-cancel-warning')).toContainText('cannot be undone');
  await page.getByTestId('inclamo-cancel-reason').selectOption('CUSTOMER');
  await page.screenshot({ path: info.outputPath('06-cancel-confirmation.png'), fullPage: true });
  await page.getByRole('button', { name: 'Cancel the order', exact: true }).click();
  const held = async () => (await store.shopify('shopper_order', { id: cancelOrder.id })).order;
  await expect.poll(async () => (await held()).cancelledAt, { timeout: 45_000 }).toBeTruthy();
  const order = await held();
  const context = await browser.newContext();
  try {
    const shopper = await context.newPage();
    await shopper.goto(order.statusPageUrl, { waitUntil: 'domcontentloaded' });
    await shopper.screenshot({ path: info.outputPath('07-shopper-cancelled.png'), fullPage: true });
    await expect(shopper.getByText(/order.*cancel(l)?ed|cancel(l)?ed.*order/i).first()).toBeVisible();
  } finally {
    await context.close();
  }
});

test('A payment link opens the ordered items and amount for the shopper', async ({ browser }, info) => {
  const prefill = await admin.get(`/inclamo/shopify/conversations/${conversation.id}/actions/new_order_prefill?order_id=${encodeURIComponent(addressOrder.id)}`);
  expect(prefill.status).toBe(200);
  expect(prefill.body.lines.length).toBeGreaterThan(0);
  const lines = prefill.body.lines.map(line => ({ variant_id: line.variant.id, quantity: line.quantity }));
  const made = await admin.act(conversation.id, { action_name: 'new_order', action_id: `acceptance-invoice-${Date.now()}`, params: { lines, delivery: 'reply' } });
  expect(made.status).toBe(200);
  expect(made.body.outcome).toBe('accepted');
  const context = await browser.newContext();
  try {
    const shopper = await context.newPage();
    await shopper.goto(made.body.result.invoice_url, { waitUntil: 'domcontentloaded' });
    await shopper.screenshot({ path: info.outputPath('08-shopper-payment-link.png'), fullPage: true });
    for (const line of prefill.body.lines) {
      await expect(shopper.getByText(line.product.title, { exact: false }).first()).toBeVisible();
    }
    await expect.poll(async () => (await shopper.locator('body').innerText()).replace(/[,\s]/g, ''))
      .toContain(Number(made.body.result.total.amount).toFixed(2));
  } finally {
    await context.close();
  }
});
