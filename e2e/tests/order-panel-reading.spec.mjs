// Scenarios of behavior contract `conversation-order-panel` about what the
// panel shows. Each describe is a requirement, each test one of its scenarios.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, eventually, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let agent;
let inbox;
let store;
let maya;
let noah;
let orders;

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

  store = await openStore(runTag('read'));
  maya = await store.customer('Maya');
  noah = await store.customer('Noah');
  orders = {
    open: await store.order(maya, { items: 3 }),
    shipped: await store.order(maya, { items: 2 }),
    refunded: await store.order(maya, { items: 1, quantity: 2 }),
    changing: await store.order(maya, { items: 1 }),
    noahs: await store.order(noah, { items: 1 }),
  };
  await store.ship(orders.shipped, [0], { company: 'DHL Express', number: 'E2EA1', url: 'https://example.com/track/E2EA1' });
  await store.ship(orders.shipped, [1], { company: 'UPS', number: 'E2EB2', url: 'https://example.com/track/E2EB2' });
  await store.refund(orders.refunded, 20);
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  await store.clean();
});

const conversationFor = (fields = {}) => admin.conversation(inbox, { name: 'Panel Example', ...fields });

test.describe('The panel is a section of the conversation sidebar', () => {
  test('Connected account', async ({ page }) => {
    const conversation = await conversationFor({ email: maya.email, message: 'Hello, a question about my order' });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);

    await expect(section).toBeVisible();
    await expect(page.getByText('Hello, a question about my order').first()).toBeVisible();
    // It behaves like the other cards of the sidebar: one of several, collapsible.
    const cards = page.locator('[data-widget-host="conversation-sidebar"] .inclamo-widget-heading');
    expect(await cards.count()).toBeGreaterThan(2);
    const heading = cards.filter({ hasText: 'Orders' });
    await expect(heading).toHaveAttribute('aria-expanded', 'true');
    await heading.click();
    await expect(heading).toHaveAttribute('aria-expanded', 'false');
    await expect(section).toHaveCount(0);
    await heading.click();
    await expect(heading).toHaveAttribute('aria-expanded', 'true');
    await expect(page.getByTestId('inclamo-orders-section')).toBeVisible();
  });

  test('Not connected, agent', async ({ page }) => {
    const conversation = await conversationFor({ email: maya.email });
    await admin.disconnect();
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);

    await expect(section).toHaveAttribute('data-state', 'not_connected');
    await expect(section).toContainText('An administrator can connect one');
    await expect(section.getByTestId('inclamo-connect-open')).toHaveCount(0);
    await admin.connect(bench());
  });
});

test.describe('The customer is matched by email, then phone, never by guess', () => {
  test('One customer by email', async ({ page }) => {
    const conversation = await conversationFor({ email: maya.email.toUpperCase() });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);

    await expect(section).toHaveAttribute('data-state', 'matched');
    await expect(section.getByTestId('inclamo-customer-name')).toHaveText('Maya Example');
    await expect(section.getByTestId(`inclamo-order-${orders.open.number}`)).toBeVisible();
    await expect(section.getByTestId(`inclamo-order-${orders.noahs.number}`)).toHaveCount(0);
  });

  test('Two customers with the same phone', async ({ page }) => {
    // A store keeps phone numbers unique, so a second customer with the same
    // number is put into the store's answer by the proxy.
    const conversation = await conversationFor({ phone: noah.phone });
    await proxy.rule({ match: { operation: 'customers_search' }, effect: 'patch', value: { patch: 'second_customer' } });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);

    await expect(section).toHaveAttribute('data-state', 'ambiguous');
    await expect(section.getByTestId('inclamo-candidate')).toHaveCount(2);
    await expect(section.locator('[data-testid^="inclamo-order-#"]')).toHaveCount(0);

    await section.getByTestId('inclamo-candidate').filter({ hasText: 'Noah Example' }).getByTestId('inclamo-candidate-choose').click();
    await expect(section).toHaveAttribute('data-state', 'matched');
    await expect(section.getByTestId('inclamo-customer-name')).toHaveText('Noah Example');

    // The next conversation of this contact opens with that customer.
    const contact = (await admin.get(`/conversations/${conversation.id}`)).body.meta.sender;
    const sourceId = (await admin.get(`/contacts/${contact.id}`)).body.payload.contact_inboxes.find(entry => entry.inbox.id === inbox.id).source_id;
    const next = (await admin.post('/conversations', { source_id: sourceId, inbox_id: inbox.id, contact_id: contact.id })).body;
    const again = await openOrders(page, account, next.id);
    await expect(again).toHaveAttribute('data-state', 'matched');
    await expect(again.getByTestId('inclamo-customer-name')).toHaveText('Noah Example');
  });

  test('Unknown contact, order number given', async ({ page }) => {
    const conversation = await conversationFor({ email: `stranger.${Date.now()}@example.com` });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);
    await expect(section).toHaveAttribute('data-state', 'none');

    await section.getByTestId('inclamo-lookup-number').fill(orders.noahs.number);
    await section.getByTestId('inclamo-lookup-find').click();

    await expect(section.getByTestId(`inclamo-order-${orders.noahs.number}`)).toBeVisible();
    await section.getByTestId('inclamo-lookup-keep').click();
    await expect(section).toHaveAttribute('data-state', 'matched');
    await expect(section.getByTestId('inclamo-customer-name')).toHaveText('Noah Example');
  });

  test('Contact without email and phone', async ({ page }) => {
    const conversation = await conversationFor();
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);

    await expect(section).toHaveAttribute('data-state', 'no_identifier');
    await expect(section.getByTestId('inclamo-lookup')).toBeVisible();
    await expect(section.locator('[data-testid^="inclamo-order-#"]')).toHaveCount(0);
  });

  test('Store connected in the limited mode', async ({ page }) => {
    await admin.disconnect();
    // The store refuses customers' personal data to this app.
    await proxy.rule({ match: { operation: 'customer_data_probe' }, effect: 'patch', value: { patch: 'customers_denied' } });
    await admin.connect(bench());
    expect((await admin.connection()).customer_data).toBe('limited');
    const conversation = await conversationFor({ email: maya.email });
    await signIn(page, users.admin);
    const section = await openOrders(page, account, conversation.id);

    await expect(section).toHaveAttribute('data-state', 'limited');
    await expect(section.getByTestId('inclamo-lookup')).toBeVisible();
    await section.getByTestId('inclamo-lookup-number').fill(orders.shipped.number);
    await section.getByTestId('inclamo-lookup-find').click();

    const card = section.getByTestId(`inclamo-order-${orders.shipped.number}`);
    await expect(card.getByTestId('inclamo-order-item')).toHaveCount(2);
    await expect(card.getByTestId('inclamo-order-shipment')).toHaveCount(2);
    await expect(card.getByTestId('inclamo-order-statuses')).toContainText('Shipped');
    await expect(card.getByTestId('inclamo-order-address-hidden')).toContainText('does not share');
    await expect(card).not.toContainText('Maya Example');
    await expect(card.getByTestId('inclamo-action-address')).toBeDisabled();

    await proxy.reset();
    await admin.disconnect();
    await admin.connect(bench());
    expect((await admin.connection()).customer_data).toBe('full');
  });
});

test.describe('The panel shows the customer and their recent orders', () => {
  test('Order with two shipments', async ({ page }) => {
    const conversation = await conversationFor({ email: maya.email });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);

    // The number of orders and the total spent are the Purchase statistics card, next to the Orders card.
    await expect(page.locator('[data-widget-host="conversation-sidebar"]').getByTestId('inclamo-customer-summary')).toContainText(/orders/i);
    const card = await orderCard(section, orders.shipped.number);
    const shipments = card.getByTestId('inclamo-order-shipment');
    await expect(shipments).toHaveCount(2);
    // The store does not promise an order of shipments.
    await expect(shipments.filter({ hasText: 'DHL Express E2EA1' }).locator('a')).toHaveAttribute('href', 'https://example.com/track/E2EA1');
    await expect(shipments.filter({ hasText: 'UPS E2EB2' }).locator('a')).toHaveAttribute('href', 'https://example.com/track/E2EB2');
    await expect(card.getByTestId('inclamo-order-item')).toHaveCount(2);
    await expect(card.getByTestId('inclamo-order-address')).toContainText('1 Example Street');
    await expect(card.getByTestId('inclamo-order-admin-link')).toHaveAttribute('href', /admin\.shopify\.com\/store\/.+\/orders\/\d+/);
  });

  test('Partially refunded order', async ({ page }) => {
    const conversation = await conversationFor({ email: maya.email });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);

    const card = await orderCard(section, orders.refunded.number);
    await expect(card.getByTestId('inclamo-order-statuses')).toContainText('Partially refunded');
    const text = (await card.getByTestId('inclamo-order-refunds').innerText()).replace(/,/g, '').replace(/[^\d.\n]/g, ' ');
    expect(text).toContain('20.00');
    expect(text).toContain((orders.refunded.total - 20).toFixed(2));
  });
});

test.describe('Order data is read from the store when needed and is not kept', () => {
  test('Order changed in the store', async ({ page }) => {
    test.setTimeout(240_000);
    const conversation = await conversationFor({ email: maya.email });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);
    await expect(section.getByTestId(`inclamo-order-${orders.changing.number}`).getByTestId('inclamo-order-statuses')).toContainText('Not shipped');

    await store.ship(orders.changing, [0], { company: 'DHL Express', number: 'E2EC3', url: 'https://example.com/track/E2EC3' });
    // "Two minutes later": longer than an answer may be reused.
    await page.waitForTimeout(65_000);
    const reopened = await openOrders(page, account, conversation.id);

    await expect(reopened.getByTestId(`inclamo-order-${orders.changing.number}`).getByTestId('inclamo-order-statuses')).toContainText('Shipped');
    await expect(reopened.getByTestId(`inclamo-order-${orders.changing.number}`).getByTestId('inclamo-order-statuses')).not.toContainText('Not shipped');
  });
});

test.describe('One order can be tied to the conversation', () => {
  test('Agent marks an order', async ({ page }) => {
    const conversation = await conversationFor({ email: maya.email });
    await signIn(page, users.agent);
    const section = await openOrders(page, account, conversation.id);
    const card = await orderCard(section, orders.shipped.number);

    await card.getByTestId('inclamo-order-mark').click();

    await expect(section.getByTestId(`inclamo-order-${orders.shipped.number}`).getByTestId('inclamo-order-marked')).toBeVisible();
    const attributes = await admin.attributes(conversation.id);
    expect(attributes).toMatchObject({
      shopify_order_number: orders.shipped.number,
      shopify_order_payment_status: 'paid',
      shopify_order_fulfillment_status: 'fulfilled',
    });
    expect(['E2EA1', 'E2EB2']).toContain(attributes.shopify_order_tracking_number);
    expect(attributes.shopify_order_tracking_link).toBe(`https://example.com/track/${attributes.shopify_order_tracking_number}`);
    expect(attributes.shopify_order_admin_link).toMatch(/admin\.shopify\.com\/store\/.+\/orders\/\d+/);
    expect(JSON.stringify(attributes)).not.toContain('Example Street');
  });

  test('Order number in the first message', async () => {
    const conversation = await conversationFor({ email: maya.email, message: `Hi, where is my order ${orders.open.number}? It has been a week.` });

    const attributes = await eventually(() => admin.attributes(conversation.id), value => !!value.shopify_order_number, { timeout: 45_000 });

    expect(attributes.shopify_order_number).toBe(orders.open.number);
  });

  test('Order number of someone else', async () => {
    const conversation = await conversationFor({ email: maya.email, message: `Please check order ${orders.noahs.number} for me` });

    await new Promise(resolve => setTimeout(resolve, 15_000));

    expect(await admin.attributes(conversation.id)).not.toHaveProperty('shopify_order_number');
  });
});
