// Scenarios of openspec capability `order-item-editing`: an agent changes the
// items of an order that has not fully shipped, sees the money difference as
// the store calculates it, and settles it. Each describe is a requirement,
// each test one of its scenarios. The orders are completed from drafts: the
// store lets the helpdesk's app edit those, not orders another app created.
// What the edit did is checked in the store through the Admin API.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, runTag, users, eventually } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const EDIT_SCOPES = ['write_order_edits', 'read_order_edits'];
const TRACKING = { company: 'DHL Express', number: 'E2EIE1', url: 'https://example.com/track/E2EIE1' };
let admin;
let agent;
let store;
let maya;
let conversation;
let mug;
let addition;
const orders = {};

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(900_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  const inbox = await admin.inbox([admin.userId, agent.userId]);
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  await admin.giveRole(agent.userId);

  store = await openStore(runTag('edit'));
  // A product of the run whose stock the store tracks, and a product of the
  // catalogue to add: one variant the store can sell.
  mug = await store.trackedProduct('E2E Tracked Mug', { units: 30 });
  maya = await store.customer('Maya');
  const two = { items: 0, lines: [{ variantId: mug.variantId, quantity: 2 }] };
  const plateAndMug = { items: 1, lines: [{ variantId: mug.variantId, quantity: 1 }] };
  const plate = { items: 1 };
  for (const [name, shape] of [
    ['reduced', two], ['removed', plateAndMug], ['restocked', two], ['added', plate], ['owes', plate], ['partly', plateAndMug],
    ['shipped', plate], ['untouched', two], ['dueBack', plateAndMug], ['recorded', two], ['refused', two], ['card', two],
  ]) {
    orders[name] = await store.draftOrder(maya, shape);
  }
  await store.ship(orders.partly, [0], TRACKING);
  await store.ship(orders.shipped, [0], TRACKING);
  const onOrders = new Set(Object.values(orders).flatMap(order => order.lineItems.nodes.map(line => line.title)));
  const catalog = (await store.shopify('new_order_catalog')).products.nodes;
  const product = catalog.find(
    entry => entry.variants.nodes.length === 1 && entry.variants.nodes[0].availableForSale && Number(entry.variants.nodes[0].price) >= 50 && !onOrders.has(entry.title)
  );
  if (!product) throw new Error('the store needs an active product with one variant that is not on the test orders');
  addition = { title: product.title, variant: product.variants.nodes[0].id, price: Number(product.variants.nodes[0].price) };

  conversation = await admin.conversation(inbox, { name: 'Edit Items Example', email: maya.email });
  // The customer is chosen as an agent would: the store's search may not show a new customer yet.
  const chosen = await admin.post(`/inclamo/shopify/conversations/${conversation.id}/customer`, { customer_id: maya.id });
  expect(chosen.status).toBe(200);
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await admin.recheck();
  await admin.takeRole(agent.userId);
  const removed = await store.clean();
  console.log(`removed from the store: ${JSON.stringify({ orders: removed.orders, drafts: removed.drafts, products: removed.products, customers: removed.customers })}`);
  // Nothing of the run is left in the store.
  expect(removed.kept).toEqual([]);
});

// The first amount in a sentence the panel shows, e.g. "UAH 80.00 is due back".
const amountIn = text => Number(String(text).match(/\d[\d,]*(?:\.\d+)?/)[0].replace(/,/g, ''));
const dialog = page => page.getByTestId('inclamo-action-dialog');
const lineOf = (page, line) => dialog(page).locator(`[data-line-id="${line.id}"]`);
const mugLine = order => order.lineItems.nodes.find(line => line.title === mug.title);
const otherLine = order => order.lineItems.nodes.find(line => line.title !== mug.title);
const calls = async operation => (await proxy.log()).filter(entry => entry.operation === operation);
const inStore = async order => (await store.shopify('edited_order', { id: order.id })).order;
const quantities = async order => Object.fromEntries((await inStore(order)).lineItems.nodes.map(line => [line.id, line.currentQuantity]));
const newestRecord = async () => (await admin.actions(conversation.id)).find(record => record.action === 'edit_items');

const cardOf = async (page, user, order) => {
  await signIn(page, user);
  const section = await openOrders(page, account, conversation.id);
  await expect(section).toHaveAttribute('data-state', 'matched');
  return orderCard(section, order.number);
};
const startEdit = async (page, order, user = users.agent) => {
  const card = await cardOf(page, user, order);
  await card.getByTestId('inclamo-action-edit_items').click();
  await expect(dialog(page).getByTestId('inclamo-edit-lines')).toBeVisible();
  return card;
};
const setQuantity = (page, line, quantity) => lineOf(page, line).getByTestId('inclamo-edit-quantity').fill(String(quantity));
const addProduct = async page => {
  await dialog(page).getByTestId('inclamo-product-query').fill(addition.title);
  await dialog(page).locator(`[data-variant-id="${addition.variant}"]`).click();
};
const calculate = async page => {
  await dialog(page).getByTestId('inclamo-edit-calculate').click();
  await expect(dialog(page).getByTestId('inclamo-edit-summary')).toBeVisible();
  await expect(dialog(page).getByTestId('inclamo-edit-stale')).toHaveCount(0);
};
const difference = page => dialog(page).getByTestId('inclamo-edit-difference');
const save = async page => {
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.getByTestId('inclamo-edit-lines')).toHaveCount(0);
};
const closeDialog = page => page.getByRole('dialog').getByRole('button', { name: 'Close', exact: true }).click();
// Saving an edit that leaves money due back opens the refund dialog: closed here, nothing refunded.
const closeRefund = async page => {
  await expect(page.getByTestId('inclamo-refund-due-back')).toBeVisible();
  await closeDialog(page);
};

test.describe('Unshipped items of an order can be edited', () => {
  test('Quantity reduced', async ({ page }) => {
    const order = orders.reduced;
    await startEdit(page, order);
    await setQuantity(page, mugLine(order), 1);
    await calculate(page);
    await save(page);
    await closeRefund(page);

    expect(await newestRecord()).toMatchObject({ outcome: 'accepted', order_number: order.number });
    expect((await quantities(order))[mugLine(order).id]).toBe(1);
  });

  test('Item removed', async ({ page }) => {
    const order = orders.removed;
    await startEdit(page, order);
    await lineOf(page, mugLine(order)).getByTestId('inclamo-edit-take-off').click();
    await calculate(page);
    await save(page);
    await closeRefund(page);

    const now = await quantities(order);
    expect(now[mugLine(order).id]).toBe(0);
    expect(now[otherLine(order).id]).toBe(1);
  });

  test('Product added', async ({ page }) => {
    const order = orders.added;
    await startEdit(page, order);
    await addProduct(page);
    await calculate(page);
    await expect(dialog(page).getByTestId('inclamo-edit-summary-added')).toContainText(addition.title);
    await save(page);

    const lines = (await inStore(order)).lineItems.nodes;
    expect(lines.find(line => line.variant?.id === addition.variant)).toMatchObject({ currentQuantity: 1 });
    expect(lines.find(line => line.id === otherLine(order).id)).toMatchObject({ currentQuantity: 1 });
    // The invoice was not chosen and the customer was not notified.
    expect(await calls('order_invoice_send')).toEqual([]);
  });

  test('Partly shipped order', async ({ page }) => {
    const order = orders.partly;
    await startEdit(page, order);

    const shipped = lineOf(page, otherLine(order));
    await expect(shipped.getByTestId('inclamo-edit-locked')).toBeVisible();
    await expect(shipped.getByTestId('inclamo-edit-quantity')).toHaveCount(0);
    await expect(lineOf(page, mugLine(order)).getByTestId('inclamo-edit-quantity')).toBeEditable();
    await closeDialog(page);
  });

  test('Fully shipped order', async ({ page }) => {
    const card = await cardOf(page, users.agent, orders.shipped);

    await expect(card.getByTestId('inclamo-action-refund')).toBeVisible();
    await expect(card.getByTestId('inclamo-action-edit_items')).toHaveCount(0);
    await expect(card.getByTestId('inclamo-edit-unavailable')).toHaveCount(0);
  });

  test('Closed without saving', async ({ page }) => {
    const order = orders.untouched;
    const before = await quantities(order);
    await startEdit(page, order);
    await setQuantity(page, mugLine(order), 1);
    // The summary opens an edit at the store that is never committed.
    await calculate(page);
    await closeDialog(page);

    await expect(page.getByTestId('inclamo-edit-lines')).toHaveCount(0);
    expect((await calls('order_edit_begin')).length).toBeGreaterThan(0);
    expect(await calls('order_edit_commit')).toEqual([]);
    expect(await quantities(order)).toEqual(before);
    expect((await inStore(order)).currentTotalPriceSet.shopMoney.amount).toBe(order.totalPriceSet.shopMoney.amount);
  });

  test('Permission missing', async ({ page }) => {
    const kept = (await admin.connection()).scopes.filter(scope => !EDIT_SCOPES.includes(scope));
    await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes: kept } });
    await admin.recheck();
    const card = await cardOf(page, users.admin, orders.untouched);

    await expect(card.getByTestId('inclamo-action-edit_items')).toHaveCount(0);
    await expect(card.getByTestId('inclamo-edit-unavailable')).toContainText('write_order_edits');

    await proxy.reset();
    await admin.recheck();
  });

  test('Agent without the role', async ({ page }) => {
    await admin.takeRole(agent.userId);
    const card = await cardOf(page, users.agent, orders.untouched);

    await expect(card.getByTestId('inclamo-action-edit_items')).toHaveCount(0);
    await expect(card.getByTestId('inclamo-edit-unavailable')).toHaveCount(0);
    const direct = await agent.act(conversation.id, {
      action_name: 'edit_items',
      action_id: `e2e-edit-items-${Date.now()}`,
      order_id: orders.untouched.id,
      params: { lines: [{ line_item_id: mugLine(orders.untouched).id, quantity: 1 }], expected: { total_after: '0', balance: '0' } },
    });
    expect(direct.status).toBe(403);
    expect(direct.body).toMatchObject({ outcome: 'refused', refusal: 'not_allowed' });
    expect(await calls('order_edit_begin')).toEqual([]);

    await admin.giveRole(agent.userId);
  });

  test('Card after an edit', async ({ page }) => {
    const order = orders.card;
    const card = await startEdit(page, order);
    await setQuantity(page, mugLine(order), 1);
    await calculate(page);
    await save(page);
    await closeRefund(page);

    const read = await inStore(order);
    expect(read.lineItems.nodes.find(line => line.id === mugLine(order).id).currentQuantity).toBe(1);
    await expect(card.locator(`[data-testid="inclamo-order-item"][data-line-id="${mugLine(order).id}"]`)).toContainText('× 1');
    expect(amountIn(await card.getByTestId('inclamo-order-total').innerText())).toBeCloseTo(Number(read.currentTotalPriceSet.shopMoney.amount), 2);
    expect(Number(read.currentTotalPriceSet.shopMoney.amount)).toBeLessThan(Number(order.totalPriceSet.shopMoney.amount));
  });
});

test.describe('The money difference is shown and settled', () => {
  test('Customer owes more', async ({ page }) => {
    const order = orders.owes;
    await startEdit(page, order);
    await addProduct(page);
    await calculate(page);

    await expect(difference(page)).toHaveAttribute('data-difference', 'owed');
    const owed = amountIn(await difference(page).innerText());
    expect(owed).toBeGreaterThan(0);
    await dialog(page).getByTestId('inclamo-edit-invoice').check();
    await save(page);

    const record = await newestRecord();
    expect(record).toMatchObject({ outcome: 'accepted', result: { difference: 'owed', invoice: 'sent' } });
    expect(Number(record.result.amount)).toBeCloseTo(owed, 2);
    expect((await calls('order_invoice_send')).length).toBe(1);
    expect(Number((await inStore(order)).totalOutstandingSet.shopMoney.amount)).toBeCloseTo(owed, 2);
    // The store records the invoice it emailed on the order, once.
    const sentEvents = read => read.events.nodes.filter(event => event.action === 'invoice_sent');
    expect(sentEvents(await eventually(() => inStore(order), read => sentEvents(read).length > 0))).toHaveLength(1);
  });

  test('Money due back', async ({ page }) => {
    const order = orders.dueBack;
    await startEdit(page, order);
    await lineOf(page, mugLine(order)).getByTestId('inclamo-edit-take-off').click();
    await calculate(page);

    await expect(difference(page)).toHaveAttribute('data-difference', 'due_back');
    const due = amountIn(await difference(page).innerText());
    expect(due).toBeGreaterThan(0);
    await save(page);

    // Saving refunds nothing; the refund dialog is offered with the amount.
    expect(amountIn(await page.getByTestId('inclamo-refund-due-back').innerText())).toBeCloseTo(due, 2);
    await expect(page.getByTestId('inclamo-refund-mode-amount')).toBeChecked();
    expect(Number(await page.getByTestId('inclamo-refund-amount').inputValue())).toBeCloseTo(due, 2);
    const read = await inStore(order);
    expect(Number(read.totalRefundedSet.shopMoney.amount)).toBe(0);
    expect(Number(read.totalOutstandingSet.shopMoney.amount)).toBeCloseTo(-due, 2);
    expect(await calls('refund_create')).toEqual([]);
    await closeDialog(page);
    await expect(page.getByTestId('inclamo-edited-refund')).toBeVisible();
  });

  test('Removed item back in stock', async ({ page }) => {
    const order = orders.restocked;
    const before = await store.available(mug.variantId, mug.location);
    await startEdit(page, order);
    await lineOf(page, mugLine(order)).getByTestId('inclamo-edit-take-off').click();
    await calculate(page);
    await save(page);
    await closeRefund(page);

    expect((await quantities(order))[mugLine(order).id]).toBe(0);
    await eventually(() => store.available(mug.variantId, mug.location), available => available === before + 2);
  });
});

test.describe('Every edit leaves a record and failures are shown', () => {
  test('Record of an edit', async ({ page }) => {
    const order = orders.recorded;
    await startEdit(page, order);
    await setQuantity(page, mugLine(order), 1);
    await calculate(page);
    await save(page);
    await closeRefund(page);

    const record = await newestRecord();
    expect(record).toMatchObject({ outcome: 'accepted', order_number: order.number, result: { difference: 'due_back' } });
    const messages = (await admin.get(`/conversations/${conversation.id}/messages`)).body.payload;
    const note = messages.filter(message => message.private).find(message => message.content.startsWith(`Edited the items of order ${order.number}:`));
    expect(note.content).toBe(
      `Edited the items of order ${order.number}: ${mug.title} from 2 to 1. ${record.result.amount} ${record.result.currency} is due back to the customer.`
    );
    expect(note.sender).toMatchObject({ id: agent.userId });
    expect(note.content).not.toContain(maya.email);
  });

  test('Store refuses the edit', async ({ page }) => {
    const order = orders.refused;
    const before = await quantities(order);
    await proxy.rule({
      match: { operation: 'order_edit_commit' },
      effect: 'refuse',
      value: { mutation: 'orderEditCommit', message: 'The order cannot be edited.', empty: { order: null, successMessages: null } },
    });
    await startEdit(page, order);
    await setQuantity(page, mugLine(order), 1);
    await calculate(page);
    await page.getByRole('button', { name: 'Save changes', exact: true }).click();

    await expect(page.getByTestId('inclamo-action-message')).toContainText('The order cannot be edited.');
    expect(await newestRecord()).toMatchObject({ outcome: 'refused', refusal: 'store_refused', store_message: 'The order cannot be edited.' });
    expect(await quantities(order)).toEqual(before);
    await closeDialog(page);
  });
});
