// Scenarios of behavior contract `order-creation`: an agent builds a paid
// order for the customer of a conversation and hands them a payment link.
// Each describe is a requirement, each test one of its scenarios. What the
// helpdesk created is checked in the store through the Admin API.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, runTag, users, eventually } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
// What the store lists for the app of the merchant guide.
const GUIDE_SCOPES = ['read_customers', 'read_orders', 'write_orders', 'write_draft_orders', 'read_draft_orders', 'read_products', 'read_locations', 'read_merchant_managed_fulfillment_orders'];
let admin;
let agent;
let inbox;
let store;
let maya;
let petro;
let previous;
let products;
let conversation;
let phoneOnly;

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(600_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  inbox = await admin.inbox([admin.userId, agent.userId]);
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  await admin.giveRole(agent.userId);
  await admin.post('/inclamo/discount_grants', { user_id: agent.userId });

  store = await openStore(runTag('new'));
  // Two products the store can sell, each with one variant, priced so that a
  // discount of 10 % is a round sum the summary can be checked against.
  const catalog = (await store.shopify('new_order_catalog')).products.nodes;
  products = catalog
    .filter(product => product.variants.nodes.length === 1 && product.variants.nodes[0].availableForSale && Number(product.variants.nodes[0].price) >= 50)
    .slice(0, 2)
    .map(product => ({ title: product.title, variant: product.variants.nodes[0].id, price: Number(product.variants.nodes[0].price) }));
  if (products.length < 2) throw new Error('the store needs two active products with one variant that can be sold');

  maya = await store.customer('Maya');
  petro = await store.customer('Petro', { email: false });
  previous = await store.order(maya, { items: 2, quantity: 2 });
  conversation = await admin.conversation(inbox, { name: 'New Order Example', email: maya.email });
  phoneOnly = await admin.conversation(inbox, { name: 'Phone Example', phone: petro.phone });
  // The customer is chosen for each contact as an agent would: the store's
  // search may not show customers created a moment ago.
  for (const [chat, customer] of [[conversation, maya], [phoneOnly, petro]]) {
    const chosen = await admin.post(`/inclamo/shopify/conversations/${chat.id}/customer`, { customer_id: customer.id });
    expect(chosen.status).toBe(200);
  }
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await admin.recheck();
  await admin.takeRole(agent.userId);
  const removed = await store.clean();
  console.log(`removed from the store: ${JSON.stringify({ orders: removed.orders, drafts: removed.drafts, customers: removed.customers })}`);
  // Nothing of the run is left in the store.
  expect(removed.kept).toEqual([]);
  for (const customer of [maya, petro]) {
    expect((await store.shopify('seeded_drafts', { query: `customer_id:${customer.id.split('/').pop()}` })).draftOrders.nodes).toEqual([]);
  }
});

const money = amount => Number(String(amount).replace(/[^\d.,-]/g, '').replace(/,/g, ''));
const open = async (page, user, chat = conversation) => {
  await signIn(page, user);
  const section = await openOrders(page, account, chat.id);
  await expect(section).toHaveAttribute('data-state', 'matched');
  return section;
};
const dialog = page => page.getByTestId('inclamo-action-dialog');
const addProduct = async (page, product) => {
  await dialog(page).getByTestId('inclamo-product-query').fill(product.title);
  await dialog(page).locator(`[data-variant-id="${product.variant}"]`).click();
};
const setQuantity = (page, index, quantity) => dialog(page).getByTestId('inclamo-new-order-quantity').nth(index).fill(String(quantity));
const calculate = async page => {
  await dialog(page).getByTestId('inclamo-new-order-calculate').click();
  await expect(dialog(page).getByTestId('inclamo-new-order-summary')).toBeVisible();
  await expect(dialog(page).getByTestId('inclamo-new-order-stale')).toHaveCount(0);
};
const totalShown = async page => money(await dialog(page).getByTestId('inclamo-new-order-total').locator('span').last().innerText());
const confirm = page => page.getByRole('button', { name: 'Create order', exact: true }).click();
const calls = async operation => (await proxy.log()).filter(entry => entry.operation === operation);
const draftsOf = async customer =>
  (await store.shopify('new_order_drafts', { query: `customer_id:${customer.id.split('/').pop()} tag:inclamo-helpdesk` })).draftOrders.nodes;
// The store's search shows a new draft after a few seconds.
const draftById = async (customer, id) => (await eventually(() => draftsOf(customer), list => list.some(draft => draft.id === id))).find(draft => draft.id === id);
const newestRecord = async chat => (await admin.actions(chat.id)).find(record => record.action === 'new_order');
// Builds the order of two products, quantities 1 and 2, up to the summary.
const twoProducts = async page => {
  const section = await open(page, users.agent);
  await section.getByTestId('inclamo-new-order-open').click();
  await addProduct(page, products[0]);
  await addProduct(page, products[1]);
  await setQuantity(page, 1, 2);
  await calculate(page);
  return section;
};
const expected = products => products[0].price + products[1].price * 2;

test.describe('An agent builds a new order for the matched customer', () => {
  test('Order with two products', async ({ page }) => {
    await twoProducts(page);

    const lines = dialog(page).getByTestId('inclamo-new-order-summary-line');
    await expect(lines).toHaveCount(2);
    await expect(lines.nth(0)).toContainText(products[0].title);
    await expect(lines.nth(1)).toContainText(products[1].title);
    await expect(lines.nth(1)).toContainText('× 2');
    expect(await totalShown(page)).toBeCloseTo(expected(products), 2);
    expect((await calls('new_order_calculate')).length).toBeGreaterThan(0);
    // The summary is the store's calculation: nothing exists in the store yet.
    expect(await calls('new_order_create')).toEqual([]);
    expect(await draftsOf(maya)).toEqual([]);
  });

  test('Discount and shipping charge', async ({ page }) => {
    await twoProducts(page);
    await dialog(page).getByTestId('inclamo-new-order-discount-type').selectOption('percentage');
    await dialog(page).getByTestId('inclamo-new-order-discount-value').fill('10');
    await dialog(page).getByTestId('inclamo-new-order-shipping').fill('5.00');
    await calculate(page);

    const subtotal = expected(products);
    const discount = Math.round(subtotal * 10) / 100;
    expect(money(await dialog(page).getByTestId('inclamo-new-order-summary-discount').locator('span').last().innerText())).toBeCloseTo(discount, 1);
    expect(money(await dialog(page).getByTestId('inclamo-new-order-summary-shipping').locator('span').last().innerText())).toBeCloseTo(5, 2);
    expect(await totalShown(page)).toBeCloseTo(subtotal - discount + 5, 1);
  });

  test('Starting from an existing order', async ({ page }) => {
    const section = await open(page, users.agent);
    const card = await orderCard(section, previous.number);
    await card.getByTestId('inclamo-action-order-again').click();

    const lines = dialog(page).getByTestId('inclamo-new-order-line');
    await expect(lines).toHaveCount(previous.lineItems.nodes.length);
    for (const [index, item] of previous.lineItems.nodes.entries()) {
      await expect(lines.nth(index)).toContainText(item.title || item.name);
      await expect(dialog(page).getByTestId('inclamo-new-order-quantity').nth(index)).toHaveValue(String(item.quantity));
    }
    await setQuantity(page, 0, 1);
    await calculate(page);
    const summary = dialog(page).getByTestId('inclamo-new-order-summary-line');
    await expect(summary.nth(0)).toContainText('× 1');
    await expect(summary.nth(1)).toContainText(`× ${previous.lineItems.nodes[1].quantity}`);
  });

  test('Agent without the role', async ({ page }) => {
    await admin.takeRole(agent.userId);
    const section = await open(page, users.agent);

    await expect(section.getByTestId('inclamo-orders-matched')).toBeVisible();
    await expect(section.getByTestId('inclamo-new-order-open')).toHaveCount(0);
    const direct = await agent.act(conversation.id, { action_name: 'new_order', action_id: `e2e-new-order-${Date.now()}`, params: { lines: [{ variant_id: products[0].variant, quantity: 1 }], delivery: 'reply' } });
    expect(direct.status).toBe(403);
    expect(direct.body).toMatchObject({ outcome: 'refused', refusal: 'not_allowed' });
    expect(await calls('new_order_create')).toEqual([]);

    await admin.giveRole(agent.userId);
  });

  test('Permission missing', async ({ page }) => {
    const kept = GUIDE_SCOPES.filter(scope => scope !== 'write_draft_orders' && scope !== 'read_draft_orders');
    await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes: kept } });
    await admin.recheck();
    const section = await open(page, users.admin);

    await expect(section.getByTestId('inclamo-new-order-open')).toHaveCount(0);
    await expect(section.getByTestId('inclamo-new-order-unavailable')).toContainText('write_draft_orders');

    await proxy.reset();
    await admin.recheck();
  });
});

test.describe('The customer gets a payment link', () => {
  test('Invoice sent by the store', async ({ page }) => {
    await twoProducts(page);
    await dialog(page).getByTestId('inclamo-new-order-delivery-email').check();
    await confirm(page);
    await expect(dialog(page)).toHaveCount(0);

    const record = await newestRecord(conversation);
    expect(record).toMatchObject({ outcome: 'accepted', result: { delivery: 'email', invoice_sent: true } });
    const draft = await draftById(maya, record.result.draft_id);
    expect(draft).toMatchObject({ status: 'INVOICE_SENT', order: null, customer: { id: maya.id } });
    expect(draft.invoiceSentAt).not.toBeNull();
    expect(draft.lineItems.nodes.map(line => [line.variant.id, line.quantity])).toEqual([[products[0].variant, 1], [products[1].variant, 2]]);
    expect((await calls('new_order_invoice_send')).length).toBe(1);
  });

  test('Link put into the reply', async ({ page }) => {
    await twoProducts(page);
    await dialog(page).getByTestId('inclamo-new-order-delivery-reply').check();
    await confirm(page);
    await expect(dialog(page)).toHaveCount(0);

    const record = await newestRecord(conversation);
    expect(record).toMatchObject({ outcome: 'accepted', result: { delivery: 'reply', invoice_sent: false } });
    await expect(page.locator('.ProseMirror[contenteditable="true"]').first()).toContainText(record.result.invoice_url);
    const draft = await draftById(maya, record.result.draft_id);
    expect(draft).toMatchObject({ status: 'OPEN', invoiceSentAt: null, invoiceUrl: record.result.invoice_url });
    expect(await calls('new_order_invoice_send')).toEqual([]);
  });

  test('Customer without an email', async ({ page }) => {
    const section = await open(page, users.agent, phoneOnly);
    await section.getByTestId('inclamo-new-order-open').click();
    await addProduct(page, products[0]);
    await calculate(page);

    await expect(dialog(page).getByTestId('inclamo-new-order-delivery-email')).toHaveCount(0);
    await expect(dialog(page).getByTestId('inclamo-new-order-delivery-reply')).toBeChecked();
    const direct = await agent.act(phoneOnly.id, { action_name: 'new_order', action_id: `e2e-new-order-${Date.now()}`, params: { lines: [{ variant_id: products[0].variant, quantity: 1 }], delivery: 'email' } });
    expect(direct.body).toMatchObject({ outcome: 'refused', refusal: 'no_email' });
    expect(await draftsOf(petro)).toEqual([]);
  });

  test('Store refuses', async ({ page }) => {
    // The drafts the earlier tests made; the store's search may still be catching up with them.
    const made = (await admin.actions(conversation.id)).filter(record => record.action === 'new_order' && record.outcome === 'accepted').map(record => record.result);
    await twoProducts(page);
    await proxy.rule({ match: { operation: 'new_order_create' }, effect: 'refuse', value: { mutation: 'draftOrderCreate', message: 'Product is no longer available.', empty: { draftOrder: null } } });
    await dialog(page).getByTestId('inclamo-new-order-delivery-email').check();
    await confirm(page);

    await expect(page.getByTestId('inclamo-action-message')).toContainText('Product is no longer available.');
    expect(await newestRecord(conversation)).toMatchObject({ outcome: 'refused', refusal: 'store_refused', result: {} });
    await page.getByRole('dialog').getByRole('button', { name: 'Close', exact: true }).click();
    // Long enough for the store's search to show a draft, had one been made.
    await new Promise(resolve => setTimeout(resolve, 6_000));
    expect((await draftsOf(maya)).map(draft => draft.id).sort()).toEqual(made.map(result => result.draft_id).sort());
    await page.reload();
    const again = await openOrders(page, account, conversation.id);
    await expect(again).toHaveAttribute('data-state', 'matched');
    const shown = await again.locator('[data-testid^="inclamo-awaiting-#"]').evaluateAll(blocks => blocks.map(block => block.dataset.testid.replace('inclamo-awaiting-', '')));
    expect(shown.sort()).toEqual(made.map(result => result.draft_name).sort());
  });
});

test.describe('Orders awaiting payment are visible and recorded', () => {
  test('Order awaiting payment in the panel', async ({ page }) => {
    const unpaid = (await draftsOf(maya)).filter(draft => draft.status !== 'COMPLETED');
    expect(unpaid.length).toBeGreaterThan(0);
    const section = await open(page, users.agent);

    for (const draft of unpaid.slice(0, 5)) {
      const block = section.getByTestId(`inclamo-awaiting-${draft.name}`);
      await expect(block).toBeVisible();
      expect(money(await block.getByTestId('inclamo-awaiting-total').innerText())).toBeCloseTo(Number(draft.totalPriceSet.shopMoney.amount), 2);
      await expect(block.getByTestId('inclamo-awaiting-link')).toHaveAttribute('href', draft.invoiceUrl);
    }
  });

  test('Record of the new order', async ({ page }) => {
    await twoProducts(page);
    await dialog(page).getByTestId('inclamo-new-order-delivery-email').check();
    await confirm(page);
    await expect(dialog(page)).toHaveCount(0);

    const record = await newestRecord(conversation);
    const total = record.result.total;
    const messages = (await admin.get(`/conversations/${conversation.id}/messages`)).body.payload;
    const note = messages.filter(message => message.private).find(message => message.content.startsWith(`Created order ${record.result.draft_name} `));
    expect(note.content).toBe(`Created order ${record.result.draft_name} for ${total.amount} ${total.currency}, awaiting payment. The store emailed its invoice to the customer.`);
    expect(note.sender).toMatchObject({ id: agent.userId });
    expect(note.content).not.toContain(maya.email);
  });
});

// Granular new-order authority must not also grant financial concessions.
test('New-order permission does not grant discounts', async () => {
  await admin.delete(`/inclamo/discount_grants/${agent.userId}`);
  const answer = await agent.post(`/inclamo/shopify/conversations/${conversation.id}/actions/new_order_preview`, {
    params: { lines: [{ variant_id: products[0].variant, quantity: 1 }], discount: { type: 'percentage', value: '10' } },
  });
  expect(answer.status).toBe(403);
  expect(answer.body.refusal || answer.body.error).toBe('not_allowed');
});
