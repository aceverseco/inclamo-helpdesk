import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let agent;
let store;
let conversation;
let addressOrder;
let cancelOrder;
let editOrder;

// Keep the independently observed result, without Shopify status-page tokens
// or payment URLs. These are synthetic acceptance customers and orders.
const keepOrder = (info, action, order) => writeFileSync(info.outputPath('shopify-verification.json'), JSON.stringify({
  action, actor: 'administrator', shopper_view_verified: true,
  order: { id: order.id, number: order.name, cancelled_at: order.cancelledAt,
    total: order.currentTotalPriceSet?.shopMoney, outstanding: order.totalOutstandingSet?.shopMoney,
    address: order.shippingAddress, items: order.lineItems?.nodes },
}, null, 2));

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
  editOrder = await store.draftOrder(customer, { quantity: 2 });
  conversation = await admin.conversation(inbox, { name: 'Acceptance Shopper', email: customer.email, message: 'Please help me change my order.' });
});

test.afterAll(async () => {
  await proxy.reset();
  if (admin) await admin.recheck();
  if (store) {
    const removed = await store.clean();
    console.log(`acceptance cleanup: ${JSON.stringify(removed)}`);
    expect(removed.kept).toEqual([]);
  }
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
      await page.route('**/inclamo/order_roles/**', route => ['POST', 'PATCH'].includes(route.request().method())
        ? route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }) : route.continue());
      const checkbox = page.getByTestId(`inclamo-permission-${agent.userId}-address`);
      await checkbox.click();
      await expect(page.getByTestId('inclamo-role-error')).toContainText('could not be confirmed');
      await expect(checkbox).not.toBeChecked();
      await page.screenshot({ path: info.outputPath('settings-role-error.png'), fullPage: true });
      await page.unroute('**/inclamo/order_roles/**');
    }
    if (route === 'discount-codes') {
      await page.route('**/inclamo/discount_grants', route => route.request().method() === 'POST'
        ? route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }) : route.continue());
      const checkbox = page.getByTestId(`inclamo-grant-${agent.userId}`).locator('input');
      await checkbox.click();
      await expect(page.getByTestId('inclamo-discounts-action-error')).toContainText('could not be confirmed');
      await expect(checkbox).not.toBeChecked();
      await page.screenshot({ path: info.outputPath('settings-discount-error.png'), fullPage: true });
      await page.unroute('**/inclamo/discount_grants');
    }
  }
  section = await openOrders(page, account, conversation.id);
  const card = await orderCard(section, addressOrder.number);
  await card.getByTestId('inclamo-action-address').scrollIntoViewIfNeeded();
  await page.screenshot({ path: info.outputPath('02-order-desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 1024, height: 768 });
  const composer = page.locator('.reply-box .ProseMirror').first();
  await expect.poll(async () => (await composer.boundingBox())?.width || 0).toBeGreaterThanOrEqual(320);
  await expect(card.getByTestId('inclamo-action-address')).toBeVisible();
  await page.screenshot({ path: info.outputPath('03-order-laptop.png'), fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  await expect(composer).toHaveCount(0);
  // The saved list filter is Mine; this synthetic conversation is unassigned.
  await page.locator('main li a').filter({ hasText: /^All\s*\d+$/ }).click();
  await expect(page.getByText('Acceptance Shopper', { exact: true }).first()).toBeVisible();
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
    await expect(shopper.getByText('2 Example Avenue', { exact: false }).first()).toBeVisible();
    await shopper.screenshot({ path: info.outputPath('05-shopper-address.png'), fullPage: true });
    keepOrder(info, 'address', order);
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
    await expect(shopper.getByText(/order.*cancel(l)?ed|cancel(l)?ed.*order/i).first()).toBeVisible();
    await shopper.screenshot({ path: info.outputPath('07-shopper-cancelled.png'), fullPage: true });
    keepOrder(info, 'cancel', order);
  } finally {
    await context.close();
  }
});

test('A payment link opens the ordered items and amount for the shopper', async ({ browser }, info) => {
  const prefill = await admin.get(`/inclamo/shopify/conversations/${conversation.id}/actions/new_order_prefill?order_id=${encodeURIComponent(addressOrder.id)}`);
  expect(prefill.status).toBe(200);
  expect(prefill.body.lines.length).toBeGreaterThan(0);
  const lines = prefill.body.lines.map(line => ({ variant_id: line.variant.id, quantity: line.quantity }));
  for (const shipping of [undefined, '5.00']) {
    const made = await admin.act(conversation.id, { action_name: 'new_order', action_id: `acceptance-invoice-${Date.now()}`, params: { lines, shipping, delivery: 'reply' } });
    expect(made.status).toBe(200);
    expect(made.body.outcome).toBe('accepted');
    const context = await browser.newContext();
    try {
      const shopper = await context.newPage();
      await shopper.goto(made.body.result.invoice_url, { waitUntil: 'domcontentloaded' });
      for (const line of prefill.body.lines) {
        await expect(shopper.getByText(line.product.title, { exact: false }).first()).toBeVisible();
      }
      // The checkout payment control can differ by payment method. Wait for
      // the shipping summary itself before checking its effect on the total.
      await shopper.screenshot({ path: info.outputPath(shipping ? 'checkout-paid-loaded.png' : 'checkout-free-loaded.png'), fullPage: true });
      const shippingLabel = shopper.getByText('Shipping', { exact: true }).last();
      const shippingSummary = () => shippingLabel.evaluate(label => {
        for (let row = label.parentElement; row; row = row.parentElement) {
          const text = row.innerText.replace(/[,\s]/g, '');
          if (/Free|\d+\.\d{2}/i.test(text)) return text;
        }
        return '';
      });
      await expect.poll(shippingSummary).toMatch(shipping ? /5\.00/ : /Free/i);
      const totalLabel = shopper.getByText('Total', { exact: true }).last();
      await expect(totalLabel).toBeVisible();
      // Read the amount beside Total. Looking anywhere in the page can match
      // a subtotal and miss an extra shipping charge added at checkout.
      const checkoutTotal = () => totalLabel.evaluate(label => {
        for (let row = label.parentElement; row; row = row.parentElement) {
          const values = row.innerText.replace(/[,\s]/g, '').match(/\d+\.\d{2}/g);
          if (values?.length) return values;
        }
        return [];
      });
      const expected = Number(made.body.result.total.amount).toFixed(2);
      await expect.poll(checkoutTotal).toEqual([expected]);
      const name = shipping ? '08b-shopper-payment-shipping.png' : '08-shopper-payment-link.png';
      await shopper.screenshot({ path: info.outputPath(name), fullPage: true });
      writeFileSync(info.outputPath(shipping ? 'payment-shipping.json' : 'payment-free.json'), JSON.stringify({
        actor: 'administrator', shipping: shipping || '0', draft_id: made.body.result.draft_id,
        total: made.body.result.total, checkout_total: expected, items: prefill.body.lines.map(line => ({ title: line.product.title, quantity: line.quantity })),
      }, null, 2));
    } finally {
      await context.close();
    }
  }
});

test('Edited items and total reach Shopify and the shopper order view', async ({ page, browser }, info) => {
  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation.id);
  const card = await orderCard(section, editOrder.number);
  const line = editOrder.lineItems.nodes[0];
  await card.getByTestId('inclamo-action-edit_items').click();
  const dialog = page.getByTestId('inclamo-action-dialog');
  await dialog.locator(`[data-line-id="${line.id}"]`).getByTestId('inclamo-edit-quantity').fill('3');
  await dialog.getByTestId('inclamo-edit-calculate').click();
  await expect(dialog.getByTestId('inclamo-edit-summary')).toBeVisible();
  await page.screenshot({ path: info.outputPath('09-edit-items-confirmation.png'), fullPage: true });
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.getByTestId('inclamo-edit-lines')).toHaveCount(0);
  const held = async () => (await store.shopify('shopper_order', { id: editOrder.id })).order;
  await expect.poll(async () => (await held()).lineItems.nodes.find(item => item.id === line.id)?.currentQuantity).toBe(3);
  const order = await held();
  expect(Number(order.currentTotalPriceSet.shopMoney.amount)).toBeGreaterThan(editOrder.total);
  const context = await browser.newContext();
  try {
    const shopper = await context.newPage();
    await shopper.goto(order.statusPageUrl, { waitUntil: 'domcontentloaded' });
    await expect(shopper.getByText(line.title, { exact: false }).first()).toBeVisible();
    await expect.poll(async () => (await shopper.locator('body').innerText()).replace(/[,\s]/g, ''))
      .toContain(Number(order.currentTotalPriceSet.shopMoney.amount).toFixed(2));
    await page.screenshot({ path: info.outputPath('10-agent-after-edit.png'), fullPage: true });
    await shopper.screenshot({ path: info.outputPath('11-shopper-edited-order.png'), fullPage: true });
    keepOrder(info, 'edit_items', order);
  } finally {
    await context.close();
  }
});
