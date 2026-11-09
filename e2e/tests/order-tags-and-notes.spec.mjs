// Scenarios of openspec capability `order-tags-and-notes`. Each describe is a
// requirement, each test one of its scenarios.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, eventually, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let agent;
let store;
let maya;
let orders;
let conversation;

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
  await admin.takeRole(agent.userId);

  store = await openStore(runTag('marks'));
  maya = await store.customer('Maya', { tags: ['wholesale'], note: 'Pays by invoice' });
  orders = {};
  for (const name of ['shown', 'adding', 'removing', 'meanwhile', 'noting', 'record']) {
    const tags = name === 'meanwhile' ? ['gift'] : ['gift', 'priority'];
    orders[name] = await store.order(maya, { tags, note: 'Leave at the door' });
  }
  // The store's customer search lags behind what was just created, and the
  // panel keeps what it found for a minute.
  await eventually(() => store.shopify('seeded_customers', { query: `email:${maya.email}` }), found => found.customers.nodes.length === 1, { timeout: 120_000, every: 3_000 });
  conversation = await admin.conversation(inbox, { name: 'Marks Example', email: maya.email });
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  await admin.takeRole(agent.userId);
  const removed = await store.clean();
  // The seed of this run is gone: nothing of it was kept.
  expect(removed.kept).toEqual([]);
});

const open = async (page, user) => {
  await signIn(page, user);
  const section = await openOrders(page, account, conversation.id);
  await expect(section).toHaveAttribute('data-state', 'matched');
  return section;
};
const openOrder = async (page, user, order) => {
  const section = await open(page, user);
  return { section, card: await orderCard(section, order.number) };
};
const withRole = () => admin.giveRole(agent.userId);
// The store matches a tag to one it already has whatever its case.
const lower = tags => tags.map(tag => tag.toLowerCase()).sort();
const ownTags = tags => lower(tags).filter(tag => tag !== 'e2e' && !tag.startsWith('e2e-'));
const shownTags = async block => lower(await block.locator('[data-testid$="-tag"]').allTextContents());
const calls = async operation => (await proxy.log()).filter(entry => entry.operation === operation);
const addTag = async (block, subject, tag) => {
  await block.getByTestId(`inclamo-${subject}-tag-input`).fill(tag);
  await block.getByTestId(`inclamo-${subject}-tag-add`).click();
};
const editNote = async (block, subject, note) => {
  await block.getByTestId(`inclamo-${subject}-note-edit`).click();
  await block.getByTestId(`inclamo-${subject}-note-input`).fill(note);
  await block.getByTestId(`inclamo-${subject}-note-save`).click();
};
const privateNotes = async () =>
  ((await admin.get(`/conversations/${conversation.id}/messages`)).body.payload || [])
    .filter(message => message.private)
    .map(message => ({ content: message.content, senderId: message.sender?.id }));
const records = async () => admin.actions(conversation.id);

test.describe('The panel shows tags and notes', () => {
  test('Order with tags and a note', async ({ page }) => {
    const { card } = await openOrder(page, users.agent, orders.shown);
    const marks = card.getByTestId('inclamo-order-marks');

    expect(ownTags(await shownTags(marks))).toEqual(['gift', 'priority']);
    await expect(marks.getByTestId('inclamo-order-note')).toHaveText('Leave at the door');
  });

  test('Customer with tags and a note', async ({ page }) => {
    const section = await open(page, users.agent);
    const marks = section.getByTestId('inclamo-customer-marks');

    await expect(marks.getByTestId('inclamo-customer-tag').first()).toBeVisible();
    expect(ownTags(await shownTags(marks))).toEqual(['wholesale']);
    await expect(marks.getByTestId('inclamo-customer-note')).toHaveText('Pays by invoice');
  });
});

test.describe('Order tags and note can be changed', () => {
  test('Agent without the role', async ({ page }) => {
    await admin.takeRole(agent.userId);
    const { section, card } = await openOrder(page, users.agent, orders.shown);

    const marks = card.getByTestId('inclamo-order-marks');
    expect(ownTags(await shownTags(marks))).toEqual(['gift', 'priority']);
    await expect(marks.getByTestId('inclamo-order-note')).toHaveText('Leave at the door');
    for (const control of ['tag-input', 'tag-remove', 'note-edit']) {
      await expect(card.getByTestId(`inclamo-order-${control}`)).toHaveCount(0);
      await expect(section.getByTestId(`inclamo-customer-${control}`)).toHaveCount(0);
    }
    expect(ownTags(await shownTags(section.getByTestId('inclamo-customer-marks')))).toContain('wholesale');

    // The server refuses too, without asking the store.
    await proxy.reset();
    const direct = await agent.act(conversation.id, { action_name: 'order_tags', action_id: `e2e-otag-norole-${Date.now()}`, order_id: orders.shown.id, params: { operation: 'add', tag: 'sneaky' } });
    expect(direct.status).toBe(403);
    expect(direct.body).toMatchObject({ outcome: 'refused', refusal: 'not_allowed' });
    expect(await calls('tags_add')).toEqual([]);
    expect(ownTags((await store.read(orders.shown)).tags)).toEqual(['gift', 'priority']);
  });

  test('Agent adds an order tag', async ({ page }) => {
    await withRole();
    const { card } = await openOrder(page, users.agent, orders.adding);
    await proxy.reset();

    await addTag(card, 'order', 'address-confirmed');

    await expect(card.getByTestId('inclamo-order-tag').filter({ hasText: /^address-confirmed$/i })).toBeVisible();
    expect(ownTags((await store.read(orders.adding)).tags)).toEqual(['address-confirmed', 'gift', 'priority']);
    // No confirmation: the change went to the store on the click, once.
    await expect(page.getByTestId('inclamo-action-dialog')).toHaveCount(0);
    expect(await calls('tags_add')).toHaveLength(1);
  });

  test('Agent removes an order tag', async ({ page }) => {
    await withRole();
    const { card } = await openOrder(page, users.agent, orders.removing);
    await proxy.reset();

    await card.locator('li', { has: page.getByTestId('inclamo-order-tag').filter({ hasText: /^priority$/ }) }).getByTestId('inclamo-order-tag-remove').click();

    await expect(card.getByTestId('inclamo-order-tag').filter({ hasText: /^priority$/ })).toHaveCount(0);
    expect(ownTags((await store.read(orders.removing)).tags)).toEqual(['gift']);
    expect(await calls('tags_remove')).toHaveLength(1);
  });

  test('Tag added in the store meanwhile', async ({ page }) => {
    await withRole();
    const { card } = await openOrder(page, users.agent, orders.meanwhile);
    expect(ownTags(await shownTags(card.getByTestId('inclamo-order-marks')))).toEqual(['gift']);

    // Someone adds a tag in the store while the panel shows the order.
    await store.shopify('seed_tags_add', { id: orders.meanwhile.id, tags: ['fraud-check'] });
    await proxy.reset();
    await addTag(card, 'order', 'address-confirmed');

    await expect(card.getByTestId('inclamo-order-tag').filter({ hasText: /^address-confirmed$/i })).toBeVisible();
    expect(ownTags((await store.read(orders.meanwhile)).tags)).toEqual(['address-confirmed', 'fraud-check', 'gift']);
    // Only the one tag was sent; the order's list was never written whole.
    expect(await calls('tags_add')).toHaveLength(1);
    expect(await calls('order_note_update')).toEqual([]);
  });

  test('Agent edits the order note', async ({ page }) => {
    await withRole();
    const { card } = await openOrder(page, users.agent, orders.noting);

    await editNote(card, 'order', 'Customer asked for delivery after 6 pm');

    await expect(card.getByTestId('inclamo-order-note')).toHaveText('Customer asked for delivery after 6 pm');
    expect((await store.read(orders.noting)).note).toBe('Customer asked for delivery after 6 pm');
    const notes = await privateNotes();
    expect(notes.map(note => note.content)).toContain(`Changed the note of order ${orders.noting.number}.`);
    expect(notes.some(note => note.content.includes('6 pm'))).toBe(false);
  });
});

test.describe('Customer tags and note need their own permission', () => {
  test('Agent adds a customer tag', async ({ page }) => {
    await withRole();
    const section = await open(page, users.agent);
    const marks = section.getByTestId('inclamo-customer-marks');

    await addTag(marks, 'customer', 'vip');

    await expect(marks.getByTestId('inclamo-customer-tag').filter({ hasText: /^vip$/i })).toBeVisible();
    expect(ownTags((await store.readCustomer(maya)).tags)).toEqual(['vip', 'wholesale']);
  });

  test('Agent edits the customer note', async ({ page }) => {
    await withRole();
    const section = await open(page, users.agent);
    const marks = section.getByTestId('inclamo-customer-marks');

    await editNote(marks, 'customer', 'Prefers phone calls');

    await expect(marks.getByTestId('inclamo-customer-note')).toHaveText('Prefers phone calls');
    expect((await store.readCustomer(maya)).note).toBe('Prefers phone calls');
  });

  test('Connection without the customer permission', async ({ page }) => {
    // The app reports its scopes without write_customers. No test app sees
    // customers' data while lacking write_customers, so the proxy takes the
    // scope out of the store's answer.
    const granted = (await admin.connection()).scopes;
    expect(granted).toContain('write_customers');
    await admin.disconnect();
    await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes: granted.filter(scope => scope !== 'write_customers') } });
    await admin.connect(bench());
    const held = await store.readCustomer(maya);

    const section = await open(page, users.admin);
    const marks = section.getByTestId('inclamo-customer-marks');
    await expect(marks.getByTestId('inclamo-customer-tag').first()).toBeVisible();
    expect(await shownTags(marks)).toEqual(lower(held.tags));
    await expect(marks.getByTestId('inclamo-customer-note')).toHaveText(held.note);
    for (const control of ['tag-input', 'tag-remove', 'note-edit']) await expect(marks.getByTestId(`inclamo-customer-${control}`)).toHaveCount(0);
    await expect(marks.getByTestId('inclamo-customer-marks-lacks')).toHaveText('Tags and the note cannot be changed here: the connected app lacks write_customers.');
    // The order's tags stay changeable: they need write_orders only.
    const card = await orderCard(section, orders.shown.number);
    await expect(card.getByTestId('inclamo-order-tag-input')).toBeVisible();

    await proxy.reset();
    const direct = await admin.act(conversation.id, { action_name: 'customer_tags', action_id: `e2e-ctag-noscope-${Date.now()}`, customer_id: maya.id, params: { operation: 'add', tag: 'gold' } });
    expect(direct.status).toBe(422);
    expect(direct.body).toMatchObject({ outcome: 'refused', refusal: 'missing_scope' });
    expect(await calls('tags_add')).toEqual([]);

    await admin.disconnect();
    await admin.connect(bench());
    expect((await admin.connection()).scopes).toContain('write_customers');
  });
});

test.describe('Every change leaves a record and failures are shown', () => {
  test('Record of a tag', async ({ page }) => {
    await withRole();
    const { card } = await openOrder(page, users.agent, orders.record);

    await addTag(card, 'order', 'address-confirmed');
    await expect(card.getByTestId('inclamo-order-tag').filter({ hasText: /^address-confirmed$/i })).toBeVisible();

    const wanted = `Added the tag "address-confirmed" to order ${orders.record.number}.`;
    const notes = await eventually(privateNotes, found => found.some(entry => entry.content === wanted), { timeout: 20_000 });
    expect(notes.find(entry => entry.content === wanted).senderId).toBe(agent.userId);
    expect((await records())[0]).toMatchObject({ action: 'order_tags', outcome: 'accepted', order_number: orders.record.number });
  });

  test('Store refuses the change', async ({ page }) => {
    await withRole();
    const { card } = await openOrder(page, users.agent, orders.shown);
    const before = await privateNotes();
    await proxy.rule({ match: { operation: 'tags_add' }, effect: 'refuse', value: { mutation: 'tagsAdd', empty: { node: null }, field: 'tags', message: 'Order tags is invalid' }, times: 1 });

    await addTag(card, 'order', 'address-confirmed');

    await expect(card.getByTestId('inclamo-order-marks-message')).toHaveText('Shopify refused: Order tags is invalid');
    expect(ownTags(await shownTags(card.getByTestId('inclamo-order-marks')))).toEqual(['gift', 'priority']);
    expect(ownTags((await store.read(orders.shown)).tags)).toEqual(['gift', 'priority']);
    expect(await calls('tags_add')).toHaveLength(1);
    expect((await records())[0]).toMatchObject({ action: 'order_tags', outcome: 'refused', refusal: 'store_refused', store_message: 'Order tags is invalid' });
    expect(await privateNotes()).toEqual(before);
  });
});
