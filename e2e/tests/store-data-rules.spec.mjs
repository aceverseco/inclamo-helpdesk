// Scenarios of behavior contract `store-data-rules`: what the store knows
// about the customer as conditions of Chatwoot's automation rules, and the
// preset rules. Each describe is a requirement, each test one of its scenarios.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, proxy, bench, eventually, runTag, users, withWorkspaceTools } from '../lib/helpdesk.mjs';
import { API_VERSION } from '../lib/shopify.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const FACTS = [
  'shopify_is_customer',
  'shopify_customer_orders',
  'shopify_customer_spent',
  'shopify_customer_tags',
  'shopify_last_order_payment_status',
  'shopify_last_order_fulfillment_status',
  'shopify_last_order_total',
  'shopify_last_order_tags',
];
// The helpdesk reuses what it read of a customer for a minute. A test about a
// store that does not answer waits that minute out.
const CUSTOMER_CACHE = 65_000;
const SPENT_RULE = 'E2E big spenders first';
// A rule without a store condition: its label on a conversation says that the
// rules of that conversation have run.
const RAN = 'e2e-rules-ran';
const LABELS = ['wholesale', 'awaiting-shipment', 'pre-sale', RAN];

let admin;
let agent;
let inbox;
let store;
// big spent more than `threshold` and waits for a shipment, small spent less
// and got theirs, tagged carries the tag "wholesale", nobody is unknown to the store.
let big;
let small;
let tagged;
let nobody;
let threshold;
let team;
const lastRead = {};
const madeLabels = [];

test.describe.configure({ mode: 'serial' });

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const fact = (key, operator, value, join = null) => ({
  attribute_key: key,
  filter_operator: operator,
  values: [value],
  query_operator: join,
  custom_attribute_type: 'conversation_attribute',
});
const allRules = async () => (await admin.get('/automation_rules')).body.payload || [];
const ruleNamed = async name => (await allRules()).find(rule => rule.name === name);
const clearRules = async () => {
  for (const rule of await allRules()) await admin.delete(`/automation_rules/${rule.id}`);
};
const rule = async (name, conditions, actions) => {
  const made = await admin.post('/automation_rules', { name, description: 'Made by the end-to-end tests', event_name: 'conversation_created', conditions, actions });
  expect(made.status).toBe(200);
  return made.body;
};
const spentRule = async () =>
  (await ruleNamed(SPENT_RULE)) ||
  rule(SPENT_RULE, [fact('shopify_customer_spent', 'is_greater_than', String(threshold))], [
    { action_name: 'change_priority', action_params: ['high'] },
    { action_name: 'assign_team', action_params: [team.id] },
  ]);
const controlRule = async () =>
  (await ruleNamed('E2E rules ran')) ||
  rule('E2E rules ran', [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: null }], [{ action_name: 'add_label', action_params: [RAN] }]);

const writesIn = async (person, fields = {}) => {
  const conversation = await admin.conversation(inbox, { name: 'Rules Example', email: person.email, message: 'Hello, I have a question', ...fields });
  lastRead[person.email] = Date.now();
  return conversation;
};
const read = async conversation => {
  const body = (await admin.get(`/conversations/${conversation.id}`)).body;
  return { priority: body.priority || null, team: body.meta?.team?.id || null, labels: body.labels || [], attributes: body.custom_attributes || {} };
};
// The conversation once its rules have run; needs the control rule.
const afterRules = async conversation => {
  await eventually(() => read(conversation), state => state.labels.includes(RAN), { timeout: 60_000 });
  // The other rules of the same event run in the same job, a moment apart.
  await sleep(3_000);
  return read(conversation);
};
const sent = async conversation =>
  ((await admin.get(`/conversations/${conversation.id}/messages`)).body.payload || []).filter(message => message.message_type === 1 && !message.private).map(message => message.content);
const storeFacts = attributes => Object.keys(attributes).filter(key => FACTS.includes(key));

// The rule editor of Chatwoot, driven the way an administrator does.
const exactly = text => new RegExp(`^\\s*${text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`);
const pick = async (page, trigger, text) => {
  await trigger.click();
  await page.locator('.n-dropdown-item:visible').filter({ hasText: exactly(text) }).first().click();
};
const buildRule = async (page, { name, attribute, operator, value, actions }) => {
  // The editor lists the custom attributes the dashboard has loaded by the
  // time it is opened; a person never clicks before that, a test would.
  const attributes = page.waitForResponse(response => response.url().includes('/custom_attribute_definitions') && response.ok());
  await page.goto(`/app/accounts/${account}/settings/automation/list`);
  await attributes;
  await page.getByRole('button', { name: 'Create Automation' }).first().click();
  await page.getByPlaceholder('Enter rule name').fill(name);
  await page.getByPlaceholder('Enter rule description').fill('Made in the rule editor by the end-to-end tests');
  await page.locator('select:has(option[value="conversation_created"])').selectOption('conversation_created');

  const condition = page.locator('section:has(> label:text-is("Conditions")) > ul > li').first();
  await pick(page, condition.locator('button:visible').nth(0), attribute);
  await pick(page, condition.locator('button:visible').nth(1), operator);
  await condition.locator('input:visible').fill(value);

  const lines = page.locator('section:has(> label:text-is("Actions")) > ul > li');
  for (const [index, [action, parameter]] of actions.entries()) {
    if (index > 0) await page.getByRole('button', { name: 'Add Action' }).click();
    const line = lines.nth(index);
    await pick(page, line.locator('button:visible').nth(0), action);
    await pick(page, line.locator('button:visible').nth(1), parameter);
    // A list of several values stays open until something else is clicked.
    await page.getByPlaceholder('Enter rule name').click();
  }
  await page.getByRole('button', { name: 'Create', exact: true }).click();
  return eventually(() => ruleNamed(name), Boolean, { timeout: 30_000 });
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
  await clearRules();

  const known = ((await admin.get('/labels')).body.payload || []).map(label => label.title);
  for (const title of LABELS.filter(label => !known.includes(label))) {
    madeLabels.push((await admin.post('/labels', { label: { title, color: '#1f93ff', show_on_sidebar: false } })).body.id);
  }
  team = (await admin.post('/teams', { team: { name: `senior-${runTag('rules')}`.toLowerCase(), description: 'Made by the end-to-end tests' } })).body;

  store = await openStore(runTag('rules'));
  big = await store.customer('Maya');
  small = await store.customer('Noah');
  tagged = await store.customer('Olga', { tags: ['wholesale'] });
  nobody = { email: `nobody.example.${store.run}@example.com`.toLowerCase() };
  big.order = await store.order(big, { items: 3 });
  small.order = await store.order(small, { items: 1 });
  await store.ship(small.order, [0], { company: 'DHL Express', number: 'E2ER1', url: 'https://example.com/track/E2ER1' });
  threshold = Math.round((big.order.total + small.order.total) / 2);

  // The helpdesk asks the store's search, which learns of new orders late.
  await store.known(big, facts => Math.abs(facts.spent - big.order.total) < 0.01 && facts.latest?.fulfillment === 'UNFULFILLED');
  await store.known(small, facts => Math.abs(facts.spent - small.order.total) < 0.01 && facts.latest?.fulfillment === 'FULFILLED');
  await store.known(tagged, facts => facts.tags.includes('wholesale'));
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await clearRules();
  for (const id of madeLabels) await admin.delete(`/labels/${id}`);
  for (const label of ((await admin.get('/labels')).body.payload || []).filter(one => one.title === 'vip')) await admin.delete(`/labels/${label.id}`);
  if (team?.id) await admin.delete(`/teams/${team.id}`);
  await admin.disconnect();
  await admin.connect(bench());
  const removed = await store.clean();
  expect(removed.kept).toEqual([]);
});

test.describe('Store facts are conditions in automation rules', () => {
  test('Rule on total spent', async ({ page }) => {
    await clearRules();
    await signIn(page, users.admin);

    const saved = await buildRule(page, {
      name: SPENT_RULE,
      attribute: "Customer's total spent",
      operator: 'Is greater than',
      value: String(threshold),
      actions: [
        ['Change Priority', 'High'],
        ['Assign a Team', team.name],
      ],
    });
    expect(saved.conditions[0]).toMatchObject({ attribute_key: 'shopify_customer_spent', filter_operator: 'is_greater_than', custom_attribute_type: 'conversation_attribute' });
    // The editor offers the other comparison of a number too.
    await expect(page.getByText(SPENT_RULE)).toBeVisible();

    const conversation = await writesIn(big);
    const state = await eventually(() => read(conversation), value => value.priority === 'high' && value.team === team.id, { timeout: 60_000 });

    expect(Number(state.attributes.shopify_customer_spent)).toBeCloseTo(big.order.total, 2);
    expect(state.attributes.shopify_is_customer).toBe('yes');
  });

  test('Customer below the amount', async () => {
    await spentRule();
    await controlRule();

    const conversation = await writesIn(small);
    const state = await afterRules(conversation);

    // The facts were there: the rule compared them and did not match.
    expect(Number(state.attributes.shopify_customer_spent)).toBeCloseTo(small.order.total, 2);
    expect(state.priority).toBeNull();
    expect(state.team).toBeNull();
  });

  test('Rule on a customer tag', async ({ page }) => {
    await clearRules();
    await signIn(page, users.admin);

    const saved = await buildRule(page, {
      name: 'E2E wholesale customers',
      attribute: "Customer's tags",
      operator: 'Contains',
      value: 'wholesale',
      actions: [['Add a Label', 'wholesale']],
    });
    expect(saved.conditions[0]).toMatchObject({ attribute_key: 'shopify_customer_tags', filter_operator: 'contains' });
    await controlRule();

    const conversation = await writesIn(tagged);
    const state = await eventually(() => read(conversation), value => value.labels.includes('wholesale'), { timeout: 60_000 });
    expect(state.attributes.shopify_customer_tags).toContain('wholesale');

    // A customer without the tag is left alone.
    expect((await afterRules(await writesIn(small))).labels).not.toContain('wholesale');
  });

  test('Rule on the latest order', async () => {
    await clearRules();
    await rule('E2E waiting for a shipment', [fact('shopify_last_order_fulfillment_status', 'equal_to', 'unfulfilled')], [{ action_name: 'add_label', action_params: ['awaiting-shipment'] }]);
    await controlRule();

    const conversation = await writesIn(big);
    const state = await eventually(() => read(conversation), value => value.labels.includes('awaiting-shipment'), { timeout: 60_000 });
    expect(state.attributes.shopify_last_order_fulfillment_status).toBe('unfulfilled');
    expect(Number(state.attributes.shopify_last_order_total)).toBeCloseTo(big.order.total, 2);

    // A customer whose latest order was shipped is left alone.
    const shipped = await afterRules(await writesIn(small));
    expect(shipped.attributes.shopify_last_order_fulfillment_status).toBe('fulfilled');
    expect(shipped.labels).not.toContain('awaiting-shipment');
  });
});

test.describe('The facts are there before the rules run', () => {
  test('Rule message with the order number', async () => {
    await clearRules();
    await rule('E2E order received', [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: null }], [
      { action_name: 'send_message', action_params: ['We are checking order {{order.number}}'] },
    ]);

    // The conversation and its first message arrive together, as from the
    // website widget or by email.
    const conversation = await writesIn(big, { message: `Hi, where is my order ${big.order.number}? It has been a week.`, together: true });
    const messages = await eventually(() => sent(conversation), list => list.length > 0, { timeout: 60_000 });

    expect(messages).toEqual([`We are checking order ${big.order.number}`]);
    expect((await read(conversation)).attributes.shopify_order_number).toBe(big.order.number);
  });

  test('Contact who is not a customer', async () => {
    await clearRules();
    await rule('E2E before the first order', [fact('shopify_is_customer', 'equal_to', 'no')], [{ action_name: 'add_label', action_params: ['pre-sale'] }]);
    await controlRule();

    const conversation = await writesIn(nobody);
    const state = await eventually(() => read(conversation), value => value.labels.includes('pre-sale'), { timeout: 60_000 });
    expect(storeFacts(state.attributes)).toEqual(['shopify_is_customer']);
    expect(state.attributes.shopify_is_customer).toBe('no');

    // A customer of the store is left alone.
    expect((await afterRules(await writesIn(small))).labels).not.toContain('pre-sale');
  });

  test('Store silent', async ({ page }) => {
    test.setTimeout(240_000);
    await clearRules();
    await spentRule();
    await controlRule();
    // Nothing the helpdesk read of this customer earlier may answer for the store.
    await sleep(Math.max(0, CUSTOMER_CACHE - (Date.now() - (lastRead[big.email] || 0))));
    await proxy.rule({ match: { path: `/admin/api/${API_VERSION}/graphql.json` }, effect: 'hang' });

    const conversation = await writesIn(big);
    const state = await afterRules(conversation);

    expect(state.priority).toBeNull();
    expect(state.team).toBeNull();
    expect(storeFacts(state.attributes)).toEqual([]);

    // The agent answers it as any other conversation.
    await signIn(page, users.agent);
    await page.goto(`/app/accounts/${account}/conversations/${conversation.id}`);
    const editor = page.locator('.reply-box .ProseMirror').first();
    await editor.waitFor({ state: 'visible', timeout: 45_000 });
    await editor.click();
    await page.keyboard.type('Thank you, we are looking into it', { delay: 30 });
    await page.locator('.reply-box').getByRole('button', { name: /^Send/ }).click();
    await eventually(() => sent(conversation), list => list.includes('Thank you, we are looking into it'), { timeout: 30_000 });

    await proxy.reset();
    lastRead[big.email] = Date.now();
  });

  test('Store in the limited mode', async () => {
    await clearRules();
    await spentRule();
    await controlRule();
    await admin.disconnect();
    // The store refuses customers' personal data to this app.
    await proxy.rule({ match: { operation: 'customer_data_probe' }, effect: 'patch', value: { patch: 'customers_denied' } });
    await admin.connect(bench());
    expect((await admin.connection()).customer_data).toBe('limited');

    const conversation = await writesIn(big);
    const state = await afterRules(conversation);

    expect(storeFacts(state.attributes)).toEqual([]);
    expect(state.priority).toBeNull();
    expect(state.team).toBeNull();

    await proxy.reset();
    await admin.disconnect();
    await admin.connect(bench());
    expect((await admin.connection()).customer_data).toBe('full');
  });
});

test.describe('Preset rules are switched on with one toggle', () => {
  const presetsPage = async page => {
    await page.goto(`/app/accounts/${account}/settings/preset-rules`);
    await expect(page.getByTestId('inclamo-presets-page')).toBeVisible({ timeout: 45_000 });
  };
  const vip = async () => (await admin.get('/inclamo/rule_presets')).body.presets.find(preset => preset.key === 'vip');

  test('Administrator switches on the VIP preset', async ({ page }) => {
    await clearRules();
    await signIn(page, users.admin);
    await presetsPage(page);
    for (const name of ['VIP customers first', 'Order not shipped yet', 'No orders yet']) await expect(page.getByTestId('inclamo-presets-page')).toContainText(name);

    await page.getByTestId('inclamo-preset-vip-value').fill(String(threshold));
    await page.getByTestId('inclamo-preset-vip-switch').check();
    await expect(page.getByTestId('inclamo-preset-vip-rule')).toContainText('VIP customers first');

    // It is an ordinary rule of Chatwoot's automation list, and opens in its editor.
    await page.getByTestId('inclamo-preset-vip-rule').getByRole('link').click();
    await expect(page).toHaveURL(/\/settings\/automation\/list$/);
    await expect(page.getByText('VIP customers first')).toBeVisible();
    await expect(page.getByRole('switch')).toHaveCount(1);
    await expect(page.getByRole('switch')).toHaveAttribute('aria-checked', 'true');
    await page.getByText('VIP customers first').hover();
    await page.locator('button:has(.i-woot-edit-pen)').first().click();
    const condition = page.locator('section:has(> label:text-is("Conditions")) > ul > li').first();
    await expect(condition).toContainText("Customer's total spent");
    await expect(condition).toContainText('Is greater than');
    await expect(condition.locator('input:visible')).toHaveValue(String(threshold));

    const conversation = await writesIn(big);
    const state = await eventually(() => read(conversation), value => value.priority === 'high' && value.labels.includes('vip'), { timeout: 60_000 });
    expect(Number(state.attributes.shopify_customer_spent)).toBeGreaterThan(threshold);
  });

  test('Preset switched off', async ({ page }) => {
    expect((await vip()).on).toBe(true);
    await signIn(page, users.admin);
    await presetsPage(page);

    await page.getByTestId('inclamo-preset-vip-switch').uncheck();
    await expect.poll(async () => (await vip()).on).toBe(false);

    // The rule is still in the automation list, shown as inactive.
    await page.getByTestId('inclamo-preset-vip-rule').getByRole('link').click();
    await expect(page.getByText('VIP customers first')).toBeVisible();
    await expect(page.getByRole('switch')).toHaveCount(1);
    await expect(page.getByRole('switch')).toHaveAttribute('aria-checked', 'false');

    await controlRule();
    const state = await afterRules(await writesIn(big));
    expect(Number(state.attributes.shopify_customer_spent)).toBeGreaterThan(threshold);
    expect(state.priority).toBeNull();
    expect(state.labels).not.toContain('vip');
  });

  test('Agent cannot manage presets', async ({ page }) => {
    // The administrator's settings menu has the entry and the page.
    await signIn(page, users.admin);
    await presetsPage(page);
    await withWorkspaceTools(page, menu => expect(menu.getByRole('menuitem', { name: 'Preset rules', exact: true })).toBeVisible());

    await signIn(page, users.agent);
    await page.goto(`/app/accounts/${account}/settings/preset-rules`);
    await expect(page).not.toHaveURL(/preset-rules/, { timeout: 45_000 });
    await expect(page.getByTestId('inclamo-presets-page')).toHaveCount(0);
    // On a settings page an agent may open, the Workspace tools menu has the agent's settings without the entry.
    await page.goto(`/app/accounts/${account}/settings/canned-response/list`);
    await withWorkspaceTools(page, async menu => {
      await expect(menu.getByRole('menuitem', { name: 'Canned Responses', exact: true })).toBeVisible({ timeout: 45_000 });
      await expect(menu.getByRole('menuitem', { name: 'Preset rules', exact: true })).toHaveCount(0);
    });

    expect((await agent.get('/inclamo/rule_presets')).status).toBe(403);
    expect((await agent.put('/inclamo/rule_presets/vip', { active: true, value: 1 })).status).toBe(403);
    expect((await vip()).on).toBe(false);
  });
});
