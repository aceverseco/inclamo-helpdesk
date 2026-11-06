// Scenarios of openspec capability `macro-order-actions`: order steps in
// macros. Each describe is a requirement, each test one of its scenarios.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, proxy, bench, runTag, users, eventually } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const MESSAGE = 'We are sorry: your order is taken care of.';
let admin;
let agent;
let inbox;
let store;
let maya;
let orders;
let macros;
const made = [];

test.describe.configure({ mode: 'serial' });

// A macro made through the API, public, removed after the run.
const macro = async (name, ...steps) => {
  const actions = steps.map(step => ({ action_name: step, action_params: step === 'send_message' ? [MESSAGE] : [] }));
  const created = await admin.post('/macros', { name: `${name} ${runTag('')}`, visibility: 'global', actions });
  expect(created.status, JSON.stringify(created.body)).toBe(200);
  made.push(created.body.payload.id);
  return created.body.payload;
};

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(900_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  inbox = await admin.inbox([admin.userId, agent.userId]);
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  await admin.giveRole(agent.userId);

  store = await openStore(runTag('mac'));
  maya = await store.customer('Maya');
  orders = {};
  for (const [name, options] of [['refund', { items: 1 }], ['declined', { items: 1 }], ['shipping', { items: 1, shipping: 40 }], ['cancel', { items: 1 }], ['replace', { items: 2 }], ['noRole', { items: 1 }]]) {
    orders[name] = await store.order(maya, options);
  }
  macros = {
    refund: await macro('E2E refund and close', 'inclamo_refund_full', 'send_message', 'resolve_conversation'),
    shipping: await macro('E2E shipping refund', 'inclamo_refund_shipping', 'send_message'),
    cancel: await macro('E2E cancel', 'inclamo_cancel_order', 'send_message'),
    replace: await macro('E2E replacement', 'inclamo_replacement', 'send_message'),
  };
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await admin.giveRole(agent.userId);
  for (const id of made) await admin.delete(`/macros/${id}`);
  const removed = await store.clean();
  // Every order of the run is gone again, the replacements the macros made included.
  expect(removed.kept).toEqual([]);
  await expect.poll(() => store.tagged(`e2e-${store.run}`), { timeout: 60_000, intervals: [5_000] }).toEqual([]);
});

// A conversation of its own for each scenario, tied to `order` unless none is given.
const conversationFor = async (label, order) => {
  const conversation = await admin.conversation(inbox, { name: `Macro ${label}`, email: maya.email });
  if (order) {
    const tied = await admin.put(`/inclamo/shopify/conversations/${conversation.id}/order`, { order_id: order.id });
    expect(tied.status, JSON.stringify(tied.body)).toBe(200);
  }
  return conversation;
};

const messages = async conversation => (await admin.get(`/conversations/${conversation.id}/messages`)).body.payload || [];
const sent = async conversation => (await messages(conversation)).filter(message => !message.private && message.message_type === 1).map(message => message.content);
const notes = async conversation => (await messages(conversation)).filter(message => message.private);
const status = async conversation => (await admin.get(`/conversations/${conversation.id}`)).body.status;
const held = order => store.read(order);
const refunded = async order => Number((await held(order)).totalRefundedSet.shopMoney.amount);

// The Macros section of the conversation's sidebar, opened the way a person would.
const openMacros = async (page, user, conversation) => {
  await signIn(page, user);
  await page.goto(`/app/accounts/${account}/conversations/${conversation.id}`);
  const header = page.locator('button.drag-handle', { hasText: 'Macros' });
  if (!(await header.first().waitFor({ state: 'visible', timeout: 5_000 }).then(() => true, () => false))) {
    await page.locator('button[class*="!rounded-full"]').first().click();
  }
  await header.first().waitFor({ state: 'visible', timeout: 30_000 });
  const row = name => page.locator('div.h-10', { hasText: name });
  // The section remembers whether it was open: open it only when the list does not show.
  const listed = await row(macros.refund.name).first().waitFor({ state: 'visible', timeout: 8_000 }).then(() => true, () => false);
  if (!listed) await header.first().click();
  await row(macros.refund.name).first().waitFor({ state: 'visible', timeout: 30_000 });
  return row;
};
// Runs a macro from the sidebar and returns the confirmation it opens.
const runFromSidebar = async (page, user, conversation, chosen) => {
  const row = await openMacros(page, user, conversation);
  await row(chosen.name).locator('button').nth(1).click();
  const confirmation = page.getByTestId('inclamo-macro-confirmation');
  await expect(confirmation).toBeVisible({ timeout: 15_000 });
  await expect(page.getByTestId('inclamo-macro-loading')).toHaveCount(0, { timeout: 30_000 });
  return confirmation;
};
// The buttons of the confirmation, which is the dialog open on top.
const dialogButton = (page, name) => page.locator('dialog[open]').last().getByRole('button', { name, exact: true });
const runButton = page => dialogButton(page, 'Run the macro');

test.describe('The macro editor offers order steps', () => {
  test('Administrator builds a refund macro', async ({ page }) => {
    const name = `E2E built ${runTag('')}`;
    await signIn(page, users.admin);
    await page.goto(`/app/accounts/${account}/settings/macros/new`);
    await page.getByPlaceholder('Enter a name for your macro').fill(name);
    // Each step starts as Chatwoot's first action; the dropdown changes it.
    const choose = async (index, label) => {
      const node = page.locator('.macros__node-action').nth(index);
      await node.locator('li.list-none button').first().click();
      await page.locator('li.n-dropdown-item', { hasText: label }).first().click();
      return node;
    };
    const refund = await choose(0, 'Refund the order in full');
    await expect(refund.getByTestId('macro-step-description')).toContainText('not put back in stock');
    await page.getByRole('button', { name: 'Add new action' }).click();
    const message = await choose(1, 'Send a Message');
    await message.locator('.ProseMirror').fill(MESSAGE);
    await page.getByRole('button', { name: 'Add new action' }).click();
    await choose(2, 'Resolve Conversation');
    await page.getByRole('button', { name: 'Save macro' }).click();

    const saved = await eventually(async () => ((await admin.get('/macros')).body.payload || []).find(item => item.name === name), Boolean);
    made.push(saved.id);
    expect(saved.actions.map(action => action.action_name)).toEqual(['inclamo_refund_full', 'send_message', 'resolve_conversation']);

    // Its preview in a conversation lists the three steps in that order.
    const conversation = await conversationFor('preview');
    const row = await openMacros(page, users.admin, conversation);
    await row(name).locator('button').first().click();
    await expect(page.locator('.macro-preview p.text-xs')).toHaveText(['Refund the order in full', 'Send a Message', 'Resolve Conversation']);
  });

  test('Rules have no order steps', async ({ page }) => {
    await signIn(page, users.admin);
    await page.goto(`/app/accounts/${account}/settings/automation/list`);
    await page.getByRole('button', { name: 'Create Automation' }).first().click();
    // The type of the rule's first action lists every action a rule can take.
    const action = page.locator('li.list-none').last();
    await action.locator('button').first().click();
    await expect(page.locator('li.n-dropdown-item').first()).toBeVisible();
    const offered = (await page.locator('li.n-dropdown-item').allInnerTexts()).join('\n');
    expect(offered).toContain('Send a Message');
    for (const label of ['Refund the order in full', 'Refund the shipping cost', 'Cancel the order', 'Send a free replacement']) expect(offered).not.toContain(label);

    // Nor can one be put there through the API.
    const rule = await admin.post('/automation_rules', {
      name: `E2E rule ${runTag('')}`, event_name: 'conversation_created',
      conditions: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: null }],
      actions: [{ action_name: 'inclamo_refund_full', action_params: [] }],
    });
    expect(rule.status).toBe(422);
  });
});

test.describe('Order steps act on the tied order after a confirmation', () => {
  test('Refund macro runs', async ({ page }) => {
    const conversation = await conversationFor('refund', orders.refund);
    const confirmation = await runFromSidebar(page, users.agent, conversation, macros.refund);
    await expect(page.getByTestId('inclamo-macro-order')).toContainText(orders.refund.number);
    await expect(confirmation.getByTestId('inclamo-macro-step-inclamo_refund_full')).toContainText(orders.refund.total.toFixed(2).replace(/\.00$/, ''));
    await runButton(page).click();

    await expect.poll(() => refunded(orders.refund), { timeout: 60_000 }).toBe(orders.refund.total);
    await expect.poll(() => sent(conversation), { timeout: 30_000 }).toEqual([MESSAGE]);
    await expect.poll(() => status(conversation), { timeout: 30_000 }).toBe('resolved');
    orders.refund.conversation = conversation;
  });

  test('Agent declines the confirmation', async ({ page }) => {
    const conversation = await conversationFor('declined', orders.declined);
    await runFromSidebar(page, users.agent, conversation, macros.refund);
    await dialogButton(page, "Don't run").click();
    await expect(page.getByTestId('inclamo-macro-confirmation')).toHaveCount(0);

    // Long enough for a macro that was sent to have run.
    await page.waitForTimeout(8_000);
    expect(await refunded(orders.declined)).toBe(0);
    expect(await sent(conversation)).toEqual([]);
    expect(await status(conversation)).toBe('open');
    expect((await admin.actions(conversation.id)).length).toBe(0);
  });

  test('Shipping refund step', async ({ page }) => {
    const conversation = await conversationFor('shipping', orders.shipping);
    const confirmation = await runFromSidebar(page, users.agent, conversation, macros.shipping);
    await expect(confirmation.getByTestId('inclamo-macro-step-inclamo_refund_shipping')).toContainText('40');
    await runButton(page).click();

    await expect.poll(async () => Number((await held(orders.shipping)).totalRefundedShippingSet.shopMoney.amount), { timeout: 60_000 }).toBe(40);
    const order = await held(orders.shipping);
    expect(Number(order.totalRefundedSet.shopMoney.amount)).toBe(40);
    expect(order.refunds.flatMap(refund => refund.refundLineItems.nodes)).toEqual([]);
    await expect.poll(() => sent(conversation), { timeout: 30_000 }).toEqual([MESSAGE]);
  });

  test('Cancel step', async ({ page }) => {
    const conversation = await conversationFor('cancel', orders.cancel);
    const confirmation = await runFromSidebar(page, users.agent, conversation, macros.cancel);
    await expect(confirmation.getByTestId('inclamo-macro-step-inclamo_cancel_order')).toContainText('Cancels the order and refunds');
    await runButton(page).click();

    await expect.poll(async () => Boolean((await held(orders.cancel)).cancelledAt), { timeout: 60_000 }).toBe(true);
    await expect.poll(() => refunded(orders.cancel), { timeout: 60_000 }).toBe(orders.cancel.total);
    await expect.poll(() => sent(conversation), { timeout: 30_000 }).toEqual([MESSAGE]);
  });

  test('Replacement step', async ({ page }) => {
    const conversation = await conversationFor('replace', orders.replace);
    const confirmation = await runFromSidebar(page, users.agent, conversation, macros.replace);
    await expect(confirmation.getByTestId('inclamo-macro-step-inclamo_replacement')).toContainText('same 2 items');
    await runButton(page).click();

    const replacement = await eventually(
      async () => (await store.tagged('replacement')).find(order => (order.note || '').endsWith(` ${orders.replace.number}`)),
      Boolean,
      { timeout: 90_000, every: 3_000 }
    );
    const created = await held(replacement);
    const original = await held(orders.replace);
    expect(Number(created.totalPriceSet.shopMoney.amount)).toBe(0);
    expect(created.customer.id).toBe(maya.id);
    expect(created.lineItems.nodes).toEqual(original.lineItems.nodes);
    expect(created.shippingAddress).toEqual(original.shippingAddress);
    await expect.poll(() => sent(conversation), { timeout: 30_000 }).toEqual([MESSAGE]);
  });
});

test.describe('A failed order step stops the macro', () => {
  test('No order tied', async ({ page }) => {
    const conversation = await conversationFor('no order');
    // In the dashboard the confirmation says so and offers only to close.
    await runFromSidebar(page, users.agent, conversation, macros.refund);
    await expect(page.getByTestId('inclamo-macro-no-order')).toContainText('No order is tied');
    await expect(runButton(page)).toHaveCount(0);
    await dialogButton(page, 'Close').click();

    // Run anyway, through the API, the server stops at the refund.
    await proxy.reset();
    const run = await agent.post(`/macros/${macros.refund.id}/execute`, { conversation_ids: [conversation.id] });
    expect(run.status).toBe(200);
    const note = await eventually(async () => (await notes(conversation)).find(item => item.content.includes('stopped at the step')), Boolean);
    expect(note.content).toContain('"Refund the order in full": no order is tied to this conversation');
    expect(await sent(conversation)).toEqual([]);
    expect(await status(conversation)).toBe('open');
    expect((await proxy.log()).filter(entry => entry.operation === 'refund_create')).toEqual([]);
  });

  test('Agent without the role', async ({ page }) => {
    await admin.takeRole(agent.userId);
    const conversation = await conversationFor('no role', orders.noRole);
    const confirmation = await runFromSidebar(page, users.agent, conversation, macros.refund);
    await expect(confirmation.getByTestId('inclamo-macro-step-inclamo_refund_full')).toContainText('administrator has not allowed you to act on orders');
    await runButton(page).click();

    const note = await eventually(async () => (await notes(conversation)).find(item => item.content.includes('stopped at the step')), Boolean);
    expect(note.content).toContain('you may not act on orders');
    expect(await refunded(orders.noRole)).toBe(0);
    expect(await sent(conversation)).toEqual([]);
    expect(await status(conversation)).toBe('open');
    await admin.giveRole(agent.userId);
  });

  test('Nothing left to refund', async () => {
    const conversation = orders.refund.conversation;
    expect(conversation, 'the scenario "Refund macro runs" refunds this order first').toBeTruthy();
    await admin.post(`/conversations/${conversation.id}/toggle_status`, { status: 'open' });
    const before = (await held(orders.refund)).refunds.length;

    const run = await agent.post(`/macros/${macros.refund.id}/execute`, { conversation_ids: [conversation.id] });
    expect(run.status).toBe(200);
    const note = await eventually(async () => (await notes(conversation)).find(item => item.content.includes('stopped at the step')), Boolean);
    expect(note.content).toContain('nothing left to refund');
    expect((await held(orders.refund)).refunds.length).toBe(before);
    expect(await sent(conversation)).toEqual([MESSAGE]);
  });
});

test.describe('Order steps leave the same record as manual actions', () => {
  test('Record of a macro refund', async () => {
    const conversation = orders.refund.conversation;
    expect(conversation, 'the scenario "Refund macro runs" refunds this order first').toBeTruthy();

    const note = (await notes(conversation)).find(item => item.content.startsWith('Refunded '));
    expect(note.content).toContain(orders.refund.number);
    expect(note.content).toMatch(new RegExp(`Refunded ${orders.refund.total}(\\.0+)? \\w+ on order`));
    expect(note.sender.id).toBe(agent.userId);
    const record = (await admin.actions(conversation.id)).find(item => item.outcome === 'accepted');
    expect(record).toMatchObject({ action: 'refund', order_number: orders.refund.number, macro_id: macros.refund.id });
  });
});
