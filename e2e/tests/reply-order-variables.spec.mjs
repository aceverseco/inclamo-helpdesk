// Scenarios of openspec capability `reply-order-variables`: order variables in
// typed replies, saved replies and macro messages. Each describe is a
// requirement, each test one of its scenarios.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, apiAs, proxy, bench, eventually, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
// Every order variable with the description the list shows next to it.
const VARIABLES = {
  number: 'Order number',
  date: 'Date the order was placed',
  total: 'Order total with its currency',
  payment_status: 'Payment status of the order',
  fulfillment_status: 'Shipping status of the order',
  tracking_number: 'Tracking number of the first shipment',
  tracking_link: 'Tracking link of the first shipment',
  status_link: 'Order status page for the customer',
  items: 'Items of the order, one per line',
};
// The helpdesk reuses what it read of an order for a minute. A test about a
// fresh read, or about a store that does not answer, waits that minute out.
const ORDER_CACHE = 65_000;
const TRACKING = { company: 'DHL Express', number: 'E2EV1', url: 'https://example.com/track/E2EV1' };
const LATE_TRACKING = { company: 'UPS', number: 'E2ELATE', url: 'https://example.com/track/E2ELATE' };

let admin;
let agent;
let inbox;
let store;
let maya;
let orders;
// Conversations tied before the tests start, with the moment of the last read of their order.
let late;
let quiet;
const savedReplies = [];
const macros = [];

test.describe.configure({ mode: 'serial' });

const conversationFor = (fields = {}) => admin.conversation(inbox, { name: 'Variables Example', email: maya.email, message: 'Hello, a question about my order', ...fields });
const tie = async (conversation, order) => {
  const answer = await admin.put(`/inclamo/shopify/conversations/${conversation.id}/order`, { order_id: order.id });
  expect(answer.status).toBe(200);
  return Date.now();
};
const savedReply = async (name, content) => {
  const shortCode = runTag(name).toLowerCase().replace(/[^a-z0-9]/g, '');
  const made = (await admin.post('/canned_responses', { short_code: shortCode, content })).body;
  savedReplies.push(made.id);
  return shortCode;
};
const macro = async (name, message) => {
  const made = (await admin.post('/macros', { name: `E2E ${runTag(name)}`, visibility: 'global', actions: [{ action_name: 'send_message', action_params: [message] }] })).body;
  const id = made.payload?.id || made.id;
  macros.push(id);
  return id;
};
// What the customer received in a conversation: the public outgoing messages.
const sent = async conversation =>
  ((await admin.get(`/conversations/${conversation.id}/messages`)).body.payload || []).filter(message => message.message_type === 1 && !message.private).map(message => message.content);
const runMacro = async (id, conversation) => {
  const before = (await sent(conversation)).length;
  expect((await agent.post(`/macros/${id}/execute`, { conversation_ids: [conversation.id] })).status).toBe(200);
  const messages = await eventually(() => sent(conversation), list => list.length > before, { timeout: 45_000 });
  return messages[messages.length - 1];
};

const editor = page => page.locator('.reply-box .ProseMirror').first();
const picker = page => page.locator('[data-popover-content]').last();
const openConversation = async (page, conversation) => {
  await page.goto(`/app/accounts/${account}/conversations/${conversation.id}`);
  await editor(page).waitFor({ state: 'visible', timeout: 45_000 });
};
// Opens the conversation and waits until its Orders section has read the
// store: from then on the editor knows the values of the tied order.
const panelRead = async (page, conversation) => {
  const section = await openOrders(page, account, conversation.id);
  await expect(section).toHaveAttribute('data-state', /^(matched|none|no_identifier|ambiguous)$/, { timeout: 45_000 });
};
const type = async (page, text) => {
  await editor(page).click();
  await page.keyboard.type(text, { delay: 40 });
};
// Picks an order variable the way an agent does: "{{" opens the list with its
// search field, the name narrows it to one, Enter puts it into the reply.
const pickVariable = async (page, name) => {
  await page.keyboard.type('{{', { delay: 40 });
  await expect(picker(page)).toBeVisible();
  await page.keyboard.type(`order.${name}`, { delay: 40 });
  await expect(picker(page).getByRole('option')).toHaveCount(1);
  await expect(picker(page)).toContainText(VARIABLES[name]);
  await page.keyboard.press('Enter');
  await expect(picker(page)).toBeHidden();
};
const send = page => page.locator('.reply-box').getByRole('button', { name: /^Send/ }).click();

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(600_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  inbox = await admin.inbox([admin.userId, agent.userId]);
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());

  store = await openStore(runTag('vars'));
  maya = await store.customer('Maya');
  orders = {
    shipped: await store.order(maya, { items: 2 }),
    late: await store.order(maya, { items: 1 }),
    quiet: await store.order(maya, { items: 1 }),
  };
  await store.ship(orders.shipped, [0, 1], TRACKING);

  late = { conversation: await conversationFor() };
  late.readAt = await tie(late.conversation, orders.late);
  quiet = { conversation: await conversationFor() };
  quiet.readAt = await tie(quiet.conversation, orders.quiet);
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  for (const id of savedReplies) await admin.delete(`/canned_responses/${id}`);
  for (const id of macros) await admin.delete(`/macros/${id}`);
  await admin.disconnect();
  await admin.connect(bench());
  await store.clean();
});

test.describe('Order variables exist under readable names', () => {
  test('Variable list offers the order variables', async ({ page }) => {
    const conversation = await conversationFor();
    await signIn(page, users.agent);
    await openConversation(page, conversation);

    await type(page, '{{order.');

    for (const [name, description] of Object.entries(VARIABLES)) await expect(picker(page)).toContainText(`order.${name}${description}`);
    // Next to Chatwoot's own variables: the same list, searched for another word.
    for (let index = 0; index < 'order.'.length; index += 1) await page.keyboard.press('Backspace');
    await page.keyboard.type('contact.', { delay: 40 });
    await expect(picker(page)).toContainText('contact.nameContact name');
  });

  test('Account without a connection', async ({ page }) => {
    const conversation = await conversationFor();
    await admin.disconnect();
    try {
      await signIn(page, users.agent);
      await openConversation(page, conversation);

      await type(page, '{{');

      await expect(picker(page)).toContainText('contact.nameContact name');
      await expect(picker(page)).not.toContainText('order.');
      await page.keyboard.type('order.', { delay: 40 });
      await expect(page.getByText('Order number')).toHaveCount(0);
    } finally {
      await admin.connect(bench());
    }
  });

  test('Saved reply with number and tracking link', async ({ page }) => {
    const shortCode = await savedReply('shipped', 'Your order {{order.number}} is on its way: {{order.tracking_link}}');
    const conversation = await conversationFor();
    await tie(conversation, orders.shipped);
    await signIn(page, users.agent);
    await panelRead(page, conversation);

    // The list of saved replies already shows the reply with the order's values.
    await type(page, `/${shortCode}`);
    await expect(page.getByRole('option', { name: `/${shortCode}` })).toContainText(`Your order ${orders.shipped.number} is on its way: ${TRACKING.url}`);
    await page.keyboard.press('Enter');
    // The agent sees the values before sending.
    await expect(editor(page)).toContainText(`Your order ${orders.shipped.number} is on its way: ${TRACKING.url}`);
    await send(page);

    const messages = await eventually(() => sent(conversation), list => list.length > 0);
    expect(messages[0]).toContain(`Your order ${orders.shipped.number} is on its way:`);
    expect(messages[0]).toContain(TRACKING.url);
    expect(messages[0]).not.toContain('{{');
  });

  test('Items and total', async ({ page }) => {
    const conversation = await conversationFor();
    await tie(conversation, orders.shipped);
    await signIn(page, users.agent);
    await panelRead(page, conversation);

    await type(page, 'Total: ');
    await pickVariable(page, 'total');
    await page.keyboard.type(' You ordered: ', { delay: 40 });
    await pickVariable(page, 'items');
    // The agent sees the values before sending.
    await expect(editor(page)).toContainText(`${orders.shipped.lineItems.nodes[0].quantity} × ${orders.shipped.lineItems.nodes[0].title}`);
    await send(page);

    const [message] = await eventually(() => sent(conversation), list => list.length > 0);
    const stored = await store.read(orders.shipped);
    expect(stored.lineItems.nodes).toHaveLength(2);
    for (const item of stored.lineItems.nodes) expect(message).toContain(`${item.quantity} × ${item.title}`);
    const total = orders.shipped.total.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    expect(message).toContain(`Total: ${total} ${store.currency}`);
    expect(message).not.toContain('{{');
  });

  test('Macro message', async () => {
    const id = await macro('status', 'Order {{order.number}} is {{order.fulfillment_status}}. Placed on {{order.date}}, paid: {{order.payment_status}}. Follow it here: {{order.status_link}}');
    const conversation = await conversationFor();
    await tie(conversation, orders.shipped);

    const message = await runMacro(id, conversation);

    // The fulfilment status in the panel's words: a shipped order is "Shipped", not "FULFILLED".
    expect(message).toContain(`Order ${orders.shipped.number} is Shipped.`);
    expect(message).toMatch(/Placed on [A-Z][a-z]+ \d{1,2}, \d{4}, paid: Paid\./);
    expect(message).toMatch(/Follow it here: https:\/\/\S+/);
    expect(message).not.toContain('{{');
  });
});

test.describe('The variables speak about the tied order', () => {
  test('Agent warned when no order is tied', async ({ page }) => {
    const shortCode = await savedReply('untied', 'About your order {{order.number}}: thank you for your patience.');
    const conversation = await conversationFor();
    await signIn(page, users.agent);
    await openConversation(page, conversation);

    await type(page, `/${shortCode}`);
    await expect(page.getByRole('option', { name: `/${shortCode}` })).toContainText('About your order {{order.number}}');
    await page.keyboard.press('Enter');
    await expect(editor(page)).toContainText('About your order {{order.number}}');
    await send(page);

    const title = page.locator('[data-test-id="modal-header-title"]', { hasText: 'Undefined variables' });
    await expect(title).toBeVisible();
    await expect(page.locator('[data-test-id="modal-header-content"]')).toContainText('undefined variables in your message: order.number.');
    // Nothing goes out while the agent is being asked, nor when they step back.
    expect(await sent(conversation)).toHaveLength(0);
    // Chatwoot's question has two answers, "Yes" (send anyway) and "No".
    await page.getByRole('button', { name: 'No', exact: true }).click();
    await expect(title).toBeHidden();
    expect(await sent(conversation)).toHaveLength(0);
  });

  test('Macro in a conversation without an order', async () => {
    const id = await macro('untied', 'About order {{order.number}}: we are looking into it.');
    const conversation = await conversationFor();

    const message = await runMacro(id, conversation);

    expect(message).toBe('About order : we are looking into it.');
    expect(message).not.toContain('{{');
    expect(message).not.toMatch(/#?\d{3,}/);
  });
});

test.describe('Values are those of the moment of sending', () => {
  test('Tracking added after the panel was last open', async ({ page }) => {
    test.setTimeout(240_000);
    const id = await macro('tracking', 'Tracking number: {{order.tracking_number}}');
    expect(await admin.attributes(late.conversation.id)).not.toHaveProperty('shopify_order_tracking_number');

    await store.ship(orders.late, [0], LATE_TRACKING);
    // Nobody opens the panel; the minute for which an earlier read is reused passes.
    await page.waitForTimeout(Math.max(0, late.readAt + ORDER_CACHE - Date.now()));
    expect(await admin.attributes(late.conversation.id)).not.toHaveProperty('shopify_order_tracking_number');

    expect(await runMacro(id, late.conversation)).toBe(`Tracking number: ${LATE_TRACKING.number}`);
  });

  test('Store unreachable', async ({ page }) => {
    test.setTimeout(240_000);
    const id = await macro('unreachable', 'Order {{order.number}}, total: {{order.total}}');
    await page.waitForTimeout(Math.max(0, quiet.readAt + ORDER_CACHE - Date.now()));
    await proxy.rule({ match: { operation: 'order_details' }, effect: 'hang' });

    const message = await runMacro(id, quiet.conversation);

    // Sent with the number the conversation last knew, and without a total.
    expect(message).toMatch(new RegExp(`^Order ${orders.quiet.number}, total:\\s*$`));
    expect((await proxy.log()).some(entry => entry.operation === 'order_details' && entry.effect === 'hang')).toBe(true);
  });
});
