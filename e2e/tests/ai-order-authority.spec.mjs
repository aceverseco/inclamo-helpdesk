import { test, expect } from '@playwright/test';
import { writeFileSync } from 'node:fs';
import { signIn, openOrders, apiAs, proxy, bench, runTag, users } from '../lib/helpdesk.mjs';
import { standIn, websiteInbox } from '../lib/agent.mjs';
import { openStore } from '../lib/store.mjs';
const account = process.env.E2E_ACCOUNT_ID || '1';
let admin, agent, store, conversation, order, paidOrder, foreignOrder, refundOrder, sequence = 0;
const permissions = ['address', 'refund', 'cancel', 'edit_items'];
const propose = async (overrides = {}) => {
  const payload = { request_id: `${runTag('authority')}-${++sequence}`, action_name: 'address', order_id: order.id, address: { address1: '21 AI Review Street', city: 'Kyiv', country_code: 'UA', zip: '01030' }, ...overrides };
  if (payload.action_name !== 'address') delete payload.address;
  const result = await standIn.orderTool(conversation.id, 'propose', payload);
  expect(result.status, JSON.stringify(result.body)).toBe(201);
  return result.body;
};
const review = (proposal, action = 'approve', who = admin) => who.post(`/inclamo/conversations/${conversation.id}/ai_proposals/${proposal.id}/${action}`, { review_digest: proposal.review_digest });
const autonomous = proposal => standIn.orderTool(conversation.id, 'execute', undefined, proposal.id);
const policy = (action, mode, limits = {}) => admin.patch(`/inclamo/ai_policies/${action}`, { mode, limits });
const limits = maximum => ({ currency: store.currency, max_amount: maximum, allowed_states: ['UNFULFILLED'] });
const held = async () => (await store.shopify('shopper_order', { id: order.id })).order;

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(300_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin); agent = await apiAs(request, users.agent);
  await proxy.reset(); await admin.disconnect(); await admin.connect(bench());
  await admin.delete('/inclamo/ai/connection');
  const inbox = await websiteInbox(admin, [admin.userId, agent.userId]);
  const connection = await admin.post('/inclamo/ai/connection', { connection_code: await standIn.code(), inbox_ids: [inbox.id] });
  expect(connection.status).toBe(201);
  store = await openStore(runTag('authority'));
  const customer = await store.customer('Authority');
  const stranger = await store.customer('OtherAuthority');
  order = await store.draftOrder(customer); paidOrder = await store.order(customer); foreignOrder = await store.order(stranger);
  refundOrder = await store.order(customer, { quantity: 2 });
  conversation = await admin.conversation(inbox, { name: 'AI Authority Shopper', email: customer.email, message: 'Please help me update this order.' });
  await expect.poll(async () => (await standIn.orderTool(conversation.id, 'context')).status, { timeout: 60000 }).toBe(200);
});
test.beforeEach(async () => {
  await proxy.reset(); await admin.takeRole(agent.userId);
  for (const action of permissions) await policy(action, 'propose');
  await admin.post(`/conversations/${conversation.id}/assignments`, { assignee_id: 0 });
  await admin.post(`/conversations/${conversation.id}/toggle_status`, { status: 'pending' });
});
test.afterAll(async () => {
  await proxy.reset();
  if (admin) { for (const action of permissions) await policy(action, 'propose'); await admin.delete('/inclamo/ai/connection'); }
  if (store) expect((await store.clean()).kept).toEqual([]);
});

test('Default requires a person', async ({ page }, info) => {
  const before = (await held()).shippingAddress;
  const proposal = await propose();
  expect(proposal.state).toBe('proposed');
  expect((await autonomous(proposal)).body.error).toBe('approval_required');
  expect((await held()).shippingAddress).toEqual(before);
  await signIn(page, users.admin); await openOrders(page, account, conversation.id);
  await expect(page.getByTestId(`inclamo-ai-proposal-${proposal.id}`)).toContainText('21 AI Review Street');
  await page.screenshot({ path: info.outputPath('ai-default-proposal.png'), fullPage: true });
});
test('Refuse incomplete autonomous policy', async ({ page }, info) => {
  expect((await policy('refund', 'autonomous')).status).toBe(422);
  await signIn(page, users.admin); await page.goto(`/app/accounts/${account}/settings/ai-agent`);
  const editor = page.getByTestId('inclamo-ai-policy-refund');
  await editor.locator('select').selectOption('autonomous');
  await expect(editor.getByTestId('ai-max-amount')).toBeVisible();
  await editor.getByTestId('ai-max-amount').fill('50');
  await editor.getByRole('button', { name: 'Save operation' }).click();
  await expect(page.getByTestId('inclamo-ai-policy-error')).toContainText('fulfillment states');
  await page.screenshot({ path: info.outputPath('ai-policy-validation.png'), fullPage: true });
});
test("Another customer's order", async () => {
  const answer = await standIn.orderTool(conversation.id, 'propose', { request_id: `${runTag('other')}-${++sequence}`, action_name: 'address', order_id: foreignOrder.id, address: { address1: 'Forbidden', city: 'Kyiv', country_code: 'UA' } });
  expect(answer.body.error).toBe('not_customers_target');
});
test('Human takes over', async () => {
  await policy('address', 'autonomous', limits('10000'));
  const proposal = await propose();
  await review(proposal, 'verify_identity');
  await admin.post(`/conversations/${conversation.id}/toggle_status`, { status: 'open' });
  expect((await autonomous(proposal)).body.error).toBe('human_takeover');
});
test('Confirm with the right permission', async ({ page, browser }, info) => {
  const proposal = await propose();
  expect((await review(proposal, 'approve', agent)).status).toBe(403);
  await admin.patch(`/inclamo/order_roles/${agent.userId}`, { action_name: 'address', enabled: true });
  await signIn(page, users.agent); await openOrders(page, account, conversation.id);
  const card = page.getByTestId(`inclamo-ai-proposal-${proposal.id}`);
  await card.getByTestId('ai-approve').click();
  await expect(card).toContainText('Completed');
  await expect.poll(async () => (await held()).shippingAddress.address1).toBe('21 AI Review Street');
  await page.screenshot({ path: info.outputPath('ai-staff-approved.png'), fullPage: true });
  const customer = await browser.newContext();
  try { const view = await customer.newPage(); await view.goto((await held()).statusPageUrl); await expect(view.getByText('21 AI Review Street', { exact: false }).first()).toBeVisible(); await view.screenshot({ path: info.outputPath('ai-shopper-address.png'), fullPage: true }); }
  finally { await customer.close(); }
  const verified = await held();
  writeFileSync(info.outputPath('shopify-ai-verification.json'), JSON.stringify({ action: 'address', order_id: verified.id, shipping_address: verified.shippingAddress, shopper_view_verified: true }, null, 2));
});
test('Stale review or revoked permission', async () => {
  const proposal = await propose({ address: { address1: '22 Refreshed Street', city: 'Kyiv', country_code: 'UA' } });
  await admin.act(conversation.id, { action_id: `${runTag('intervening')}-${++sequence}`, action_name: 'address', order_id: order.id, address: { address1: 'Merchant intervened', city: 'Kyiv', country_code: 'UA' } });
  expect((await review(proposal)).body.error).toBe('review_changed');
  const refreshed = (await review(proposal, 'refresh')).body;
  expect(refreshed.review_digest).not.toBe(proposal.review_digest);
  expect((await review(refreshed, 'approve', agent)).status).toBe(403);
  expect((await review(refreshed)).body.state).toBe('accepted');
});
test('Reject or expire', async ({ page }) => {
  const proposal = await propose();
  await signIn(page, users.admin); await openOrders(page, account, conversation.id);
  await page.getByTestId(`inclamo-ai-proposal-${proposal.id}`).getByTestId('ai-reject').click();
  await expect(page.getByTestId(`inclamo-ai-proposal-${proposal.id}`)).toContainText('Rejected');
  expect((await review(proposal)).body.error).toBe('already_decided');
  // Expiry is clock-controlled in ai_authority_spec.rb; this live path verifies rejection.
});
test('Refund above the configured amount', async () => {
  await policy('refund', 'autonomous', limits('1'));
  const proposal = await propose({ action_name: 'refund', order_id: paidOrder.id, params: { mode: 'full', notify: false, restock: false } });
  await review(proposal, 'verify_identity');
  expect((await autonomous(proposal)).body.error).toBe('amount_limit');
  expect((await proxy.log()).filter(row => row.operation === 'refund_create')).toHaveLength(0);
});
test('Duplicate AI request and approval', async () => {
  await policy('address', 'autonomous', limits('10000'));
  const proposal = await propose({ address: { address1: '23 Autonomous Street', city: 'Kyiv', country_code: 'UA' } });
  await review(proposal, 'verify_identity');
  const results = await Promise.all([autonomous(proposal), autonomous(proposal)]);
  expect(results.some(result => result.body.state === 'accepted')).toBe(true);
  expect((await autonomous(proposal)).body.state).toBe('accepted');
  await expect.poll(async () => (await held()).shippingAddress.address1).toBe('23 Autonomous Street');
  expect((await proxy.log()).filter(row => row.operation === 'order_address_update')).toHaveLength(1);
});
test('Lost Shopify reply', async ({ page }, info) => {
  const proposal = await propose({ address: { address1: '24 Unknown Reply Street', city: 'Kyiv', country_code: 'UA' } });
  await proxy.rule({ match: { operation: 'order_address_update' }, effect: 'lose_answer', times: 1 });
  expect((await review(proposal)).body.state).toBe('unknown');
  expect((await review(proposal)).body.state).toBe('unknown');
  expect((await proxy.log()).filter(row => row.operation === 'order_address_update')).toHaveLength(1);
  await expect.poll(async () => (await held()).shippingAddress.address1).toBe('24 Unknown Reply Street');
  await signIn(page, users.admin); await openOrders(page, account, conversation.id);
  await expect(page.getByTestId(`inclamo-ai-proposal-${proposal.id}`)).toContainText('Outcome unknown');
  await page.screenshot({ path: info.outputPath('ai-unknown-outcome.png'), fullPage: true });
});

test('AI item edit is reviewed and verified by the shopper', async ({ page, browser }, info) => {
  const line = (await held()).lineItems.nodes[0];
  const proposal = await propose({ action_name: 'edit_items', params: { lines: [{ line_item_id: line.id, quantity: 3 }], notify: false, invoice: false } });
  await admin.patch(`/inclamo/order_roles/${agent.userId}`, { action_name: 'edit_items', enabled: true });
  await signIn(page, users.agent); await openOrders(page, account, conversation.id);
  const card = page.getByTestId(`inclamo-ai-proposal-${proposal.id}`);
  await expect(card).toContainText(line.title);
  await expect(card).not.toContainText('gid://');
  await card.getByText(line.title, { exact: false }).scrollIntoViewIfNeeded();
  await page.screenshot({ path: info.outputPath('ai-edit-review.png'), fullPage: true });
  await card.getByTestId('ai-approve').click();
  await expect(card).toContainText('Completed');
  await expect.poll(async () => (await held()).lineItems.nodes.find(item => item.id === line.id)?.currentQuantity).toBe(3);
  const verified = await held();
  expect(Number(verified.currentTotalPriceSet.shopMoney.amount)).toBe(Number(proposal.summary.effect.total_after.amount));
  expect((await proxy.log()).filter(row => row.operation === 'order_edit_commit')).toHaveLength(1);
  const customer = await browser.newContext();
  try {
    const view = await customer.newPage(); await view.goto(verified.statusPageUrl);
    await expect(view.getByText(line.title, { exact: false }).first()).toBeVisible();
    await expect.poll(async () => (await view.locator('body').innerText()).replace(/[,\s]/g, '')).toContain(Number(verified.currentTotalPriceSet.shopMoney.amount).toFixed(2));
    await view.screenshot({ path: info.outputPath('ai-shopper-edited.png'), fullPage: true });
  } finally { await customer.close(); }
  writeFileSync(info.outputPath('shopify-ai-edit-verification.json'), JSON.stringify({ action: 'edit_items', order_id: verified.id, items: verified.lineItems.nodes, total: verified.currentTotalPriceSet.shopMoney, shopper_view_verified: true }, null, 2));
});

test('AI cancellation requires both rights and returns the reviewed amount', async ({ page, browser }, info) => {
  const proposal = await propose({ action_name: 'cancel', order_id: paidOrder.id, params: { reason: 'CUSTOMER', refund: true, restock: true, notify: false } });
  await admin.patch(`/inclamo/order_roles/${agent.userId}`, { action_name: 'cancel', enabled: true });
  expect((await review(proposal, 'approve', agent)).status).toBe(403);
  expect((await proxy.log()).filter(row => row.operation === 'order_cancel')).toHaveLength(0);
  await admin.patch(`/inclamo/order_roles/${agent.userId}`, { action_name: 'refund', enabled: true });
  await signIn(page, users.agent); await openOrders(page, account, conversation.id);
  const card = page.getByTestId(`inclamo-ai-proposal-${proposal.id}`);
  await expect.poll(async () => (await card.innerText()).replaceAll(',', '')).toContain(Number(proposal.summary.effect.amount).toFixed(2));
  await page.screenshot({ path: info.outputPath('ai-cancel-review.png'), fullPage: true });
  await card.getByTestId('ai-approve').click();
  await expect.poll(async () => (await store.read(paidOrder)).cancelledAt, { timeout: 45000 }).toBeTruthy();
  const verified = await store.read(paidOrder);
  expect(Number(verified.totalRefundedSet.shopMoney.amount)).toBe(Number(proposal.summary.effect.amount));
  expect((await proxy.log()).filter(row => row.operation === 'order_cancel')).toHaveLength(1);
  const publicOrder = (await store.shopify('shopper_order', { id: paidOrder.id })).order;
  const customer = await browser.newContext();
  try {
    const view = await customer.newPage(); await view.goto(publicOrder.statusPageUrl);
    await expect(view.getByText(/order.*cancel(l)?ed|cancel(l)?ed.*order/i).first()).toBeVisible();
    await view.screenshot({ path: info.outputPath('ai-shopper-cancelled.png'), fullPage: true });
  } finally { await customer.close(); }
  writeFileSync(info.outputPath('shopify-ai-cancel-verification.json'), JSON.stringify({ action: 'cancel', order_id: verified.id, cancelled_at: verified.cancelledAt, refunded: verified.totalRefundedSet.shopMoney, shopper_view_verified: true }, null, 2));
});

test('AI item refund names the product and verifies the refunded amount', async ({ page }, info) => {
  const line = refundOrder.lineItems.nodes[0];
  const proposal = await propose({ action_name: 'refund', order_id: refundOrder.id, params: { mode: 'items', items: [{ line_item_id: line.id, quantity: 1 }], restock: false, notify: false } });
  await admin.patch(`/inclamo/order_roles/${agent.userId}`, { action_name: 'refund', enabled: true });
  await signIn(page, users.agent); await openOrders(page, account, conversation.id);
  const card = page.getByTestId(`inclamo-ai-proposal-${proposal.id}`);
  await expect(card).toContainText(line.title);
  await expect(card).toContainText('Refund destination');
  await expect(card).not.toContainText('gid://');
  await card.getByText(line.title, { exact: false }).scrollIntoViewIfNeeded();
  await page.screenshot({ path: info.outputPath('ai-refund-review.png'), fullPage: true });
  await card.getByTestId('ai-approve').click();
  await expect(card).toContainText('Completed');
  await expect.poll(async () => Number((await store.read(refundOrder)).totalRefundedSet.shopMoney.amount)).toBe(Number(proposal.summary.effect.amount));
  expect((await proxy.log()).filter(row => row.operation === 'refund_create')).toHaveLength(1);
  const verified = await store.read(refundOrder);
  writeFileSync(info.outputPath('shopify-ai-refund-verification.json'), JSON.stringify({ action: 'refund', order_id: verified.id, product: line.title, quantity: 1, refunded: verified.totalRefundedSet.shopMoney, shopper_view_verified: false }, null, 2));
});
