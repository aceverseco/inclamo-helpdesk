import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';
const account = process.env.E2E_ACCOUNT_ID || '1';
let admin, agent, store, conversation, order, cancelOrder;
const grant = (action, enabled) => admin.patch(`/inclamo/order_roles/${agent.userId}`, { action_name: action, enabled });
test.beforeAll(async ({ playwright }) => {
  test.setTimeout(420_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin); agent = await apiAs(request, users.agent);
  await proxy.reset(); await admin.disconnect(); await admin.connect(bench());
  await admin.takeRole(agent.userId); await admin.delete(`/inclamo/discount_grants/${agent.userId}`);
  const inbox = await admin.inbox([admin.userId, agent.userId]);
  store = await openStore(runTag('rights'));
  const customer = await store.customer('Rights');
  order = await store.draftOrder(customer);
  cancelOrder = await store.draftOrder(customer);
  // The store's customer search, which the panel uses to find the customer, shows one it has just made only after a moment.
  await store.known(customer, facts => facts.orders >= 2, { timeout: 180_000 });
  conversation = await admin.conversation(inbox, { name: 'Rights Shopper', email: customer.email, message: 'Please update my delivery address.' });
});
test.afterAll(async () => { await proxy.reset(); if (store) expect((await store.clean()).kept).toEqual([]); });

test('Address-only staff member', async ({ page, browser }, info) => {
  expect((await grant('address', true)).status).toBe(200);
  await signIn(page, users.agent);
  const section = await openOrders(page, account, conversation.id);
  const card = await orderCard(section, order.number);
  await expect(card.getByTestId('inclamo-action-refund')).toBeDisabled();
  await expect(card.getByTestId('inclamo-action-cancel')).toBeDisabled();
  await card.getByTestId('inclamo-action-address').click();
  await page.getByTestId('inclamo-address-address1').fill('19 Permission Avenue');
  await page.getByRole('button', { name: 'Save address', exact: true }).click();
  const held = async () => (await store.shopify('shopper_order', { id: order.id })).order;
  await expect.poll(async () => (await held()).shippingAddress.address1).toBe('19 Permission Avenue');
  await page.screenshot({ path: info.outputPath('staff-address-only.png'), fullPage: true });
  const customer = await browser.newContext();
  try { const view = await customer.newPage(); await view.goto((await held()).statusPageUrl); await expect(view.getByText('19 Permission Avenue', { exact: false }).first()).toBeVisible(); await view.screenshot({ path: info.outputPath('staff-shopper-address.png'), fullPage: true }); }
  finally { await customer.close(); }
});
test('Another account and non-admin cannot grant', async () => {
  expect((await agent.patch(`/inclamo/order_roles/${agent.userId}`, { action_name: 'refund', enabled: true })).status).toBe(403);
  expect((await admin.patch('/inclamo/order_roles/99999999', { action_name: 'refund', enabled: true })).status).toBe(404);
});
test('Preserve existing grants', async () => {
  expect((await admin.giveRole(agent.userId)).status).toBe(200);
  const member = (await admin.get('/inclamo/order_roles')).body.members.find(row => row.user_id === agent.userId);
  expect(Object.values(member.permissions).filter(Boolean)).toHaveLength(10);
  expect(member.permissions.discount).toBe(false);
  await admin.takeRole(agent.userId); await grant('address', true);
});
test('Refund through a cancellation', async ({ browser }, info) => {
  await grant('cancel', true);
  const params = { reason: 'CUSTOMER', refund: true, restock: true, notify: false };
  const denied = await agent.act(conversation.id, { action_name: 'cancel', action_id: runTag('rights-cancel-deny'), order_id: cancelOrder.id, params });
  expect(denied.status).toBe(403);
  expect((await store.shopify('shopper_order', { id: cancelOrder.id })).order.cancelledAt).toBeNull();
  const accepted = await agent.act(conversation.id, { action_name: 'cancel', action_id: runTag('rights-cancel-allow'), order_id: cancelOrder.id, params: { ...params, refund: false } });
  expect(['accepted', 'running']).toContain(accepted.body.outcome);
  const held = async () => (await store.shopify('shopper_order', { id: cancelOrder.id })).order;
  await expect.poll(async () => (await held()).cancelledAt, { timeout: 45000 }).toBeTruthy();
  const customer = await browser.newContext();
  try { const view = await customer.newPage(); await view.goto((await held()).statusPageUrl); await expect(view.getByText(/order.*cancel(l)?ed|cancel(l)?ed.*order/i).first()).toBeVisible(); await view.screenshot({ path: info.outputPath('staff-shopper-cancelled.png'), fullPage: true }); }
  finally { await customer.close(); }
});
test('Permission revoked during a dialog', async ({ page }, info) => {
  await grant('address', true);
  const originalAddress = (await store.shopify('shopper_order', { id: order.id })).order.shippingAddress.address1;
  await signIn(page, users.agent);
  const card = await orderCard(await openOrders(page, account, conversation.id), order.number);
  await card.getByTestId('inclamo-action-address').click();
  await page.getByTestId('inclamo-address-address1').fill('This must not be saved');
  await grant('address', false);
  await page.getByRole('button', { name: 'Save address', exact: true }).click();
  await expect(page.getByTestId('inclamo-action-dialog')).toContainText(/not allowed|permission/i);
  expect((await store.shopify('shopper_order', { id: order.id })).order.shippingAddress.address1).toBe(originalAddress);
  await page.screenshot({ path: info.outputPath('revoked-address-dialog.png'), fullPage: true });
});
test('Concurrent grant edits', async () => {
  const updates = await Promise.all([grant('address', true), grant('refund', true)]);
  expect(updates.map(row => row.status)).toEqual([200, 200]);
  const member = (await admin.get('/inclamo/order_roles')).body.members.find(row => row.user_id === agent.userId);
  expect(member.permissions).toMatchObject({ address: true, refund: true, discount: false });
});
test('Failed permission save', async ({ page }, info) => {
  await grant('refund', false);
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/settings/order-actions`);
  await page.route('**/inclamo/order_roles/**', route => route.request().method() === 'PATCH' ? route.fulfill({ status: 503, contentType: 'application/json', body: '{}' }) : route.continue());
  const box = page.getByTestId(`inclamo-permission-${agent.userId}-refund`);
  await box.check();
  await expect(page.getByTestId('inclamo-role-error')).toBeVisible();
  await expect(box).not.toBeChecked();
  await page.screenshot({ path: info.outputPath('permission-save-failure.png'), fullPage: true });
});
