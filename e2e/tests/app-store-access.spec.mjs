// Scenarios of behavior contract `app-store-access`, grouped by requirement.
// Each test is named after its scenario; scripts/check-e2e-coverage.mjs
// relies on that.
//
// The store app is the stand-in of e2e/stand-in-app: it provisions the
// accounts and answers the helpdesk's signed requests for a store key, which
// the stack's helpdesk sends to it (INCLAMO_APP_URL). For the development
// store the key it hands out is a token of the test app, which the store
// accepts; the life and the scopes it claims for the key are what each
// scenario needs, and the helpdesk goes by those. Two accounts:
//   keys   an invented store, made while the app is silent; once it is
//          connected the Shopify proxy answers its few reads itself;
//   bench  the development store, with a customer and an order of this run.
// The tests run in order and share the two accounts.
//
// Two scenarios are not here, each named with its reason in the checker: an
// installation without the app's address, and the record of key requests.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, users, eventually, runTag } from '../lib/helpdesk.mjs';
import { storeApp, storeKeys, setPassword, personApi } from '../lib/app.mjs';
import { openStore } from '../lib/store.mjs';
import { accessToken, credentials, API_VERSION } from '../lib/shopify.mjs';

const run = (process.env.E2E_RUN || 'local').toLowerCase().replace(/[^a-z0-9]/g, '');
const operatorAccount = process.env.E2E_ACCOUNT_ID || '1';
const GRAPHQL = `/admin/api/${API_VERSION}/graphql.json`;
const TEN = ['read_customers', 'read_orders', 'read_products', 'write_orders', 'write_draft_orders', 'write_customers', 'write_order_edits', 'write_discounts', 'read_locations', 'read_merchant_managed_fulfillment_orders'];
const without = (...scopes) => TEN.filter(scope => !scopes.includes(scope));
const password = name => `Own-${name}-Passw0rd!`;
const person = name => ({ email: `e2e-${run}-${name}@example.test`, name: `E2E ${name[0].toUpperCase()}${name.slice(1)}` });
const keysStore = `e2e-${run}-keys.myshopify.com`;
// Has the shape of an admin token and is none: put together here so that no
// token-like string sits in the repository. No store is asked with it.
const inventedKey = ['shpat', 'stand', 'in', 'key', run].join('_');
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));

let benchDomain;
let benchToken;
let store;
let maya;
let mayaOrder;
let operator;
let operatorConversation;
// What the tests learn on the way and later ones use.
const keys = {};
const shop = {};

// A store's account with a new administrator, who sets a password through the
// answer's link and finishes Chatwoot's first-run form.
async function provisionWithAdministrator(domain, name) {
  const admin = person(name);
  const answer = await storeApp.provision(domain, { shop: { name: `Store ${name} ${run}` }, admin });
  expect(answer.status).toBe(201);
  expect(await setPassword(answer.body.password_setup_url, password(name))).toBe(200);
  const api = (await personApi(admin.email, password(name))).within(answer.body.account_id);
  expect((await api.patch('/onboarding', { onboarding_step: 'account_details' })).status).toBe(200);
  return { domain, accountId: answer.body.account_id, user: { email: admin.email, password: password(name) }, api };
}

// A conversation of `email` in an API inbox of the account.
async function conversationIn(target, email) {
  const inbox = (await target.api.post('/inboxes', { name: `Store chat ${run}`, channel: { type: 'api', webhook_url: '' } })).body;
  const made = (await target.api.post('/contacts', { inbox_id: inbox.id, name: 'Maya Example', email })).body.payload;
  const created = await target.api.post('/conversations', { source_id: made.contact_inbox.source_id, inbox_id: inbox.id, contact_id: made.contact.id });
  expect(created.status).toBe(200);
  return { inbox, id: created.body.id };
}

const connectionOf = async target => (await target.api.get('/inclamo/shopify/connection')).body;
const recheck = target => target.api.post('/inclamo/shopify/connection/recheck');
const panelOf = async (target, conversationId) => (await target.api.get(`/inclamo/shopify/conversations/${conversationId}/panel`)).body;
// A number nobody has: the store is asked, whatever was read before.
const lookUp = (target, conversationId) =>
  target.api.get(`/inclamo/shopify/conversations/${conversationId}/lookup?number=${encodeURIComponent(`#9${Date.now().toString().slice(-8)}`)}`);
const keyRequests = async () => storeKeys.requests(benchDomain);
// The development store's key, with the life and scopes the app claims for it.
const grant = (extra = {}) => storeKeys.set(benchDomain, { access_token: benchToken, ...extra });

const ordersOf = async (page, target) => {
  await signIn(page, target.user);
  return openOrders(page, target.accountId, target.conversation.id);
};
// The "Store" menu at the foot of the Orders section, for whoever opens it.
const storeMenu = async section => {
  const menu = section.locator('details.reference-store-menu');
  if ((await menu.getAttribute('open')) === null) await menu.locator('summary').click();
  return menu;
};

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(600_000);
  benchDomain = bench().shop_domain;
  benchToken = await accessToken(credentials('SHOPIFY_BENCH'));
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  operator = await apiAs(request, users.admin);
  operatorConversation = await operator.conversation(await operator.inbox([operator.userId]), { name: 'Keys Example' });
  store = await openStore(runTag('keys'));
  maya = await store.customer('Maya');
  mayaOrder = await store.order(maya, { items: 1 });
  await store.known(maya, facts => facts.orders >= 1);
  await proxy.reset();
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  const connection = await operator.connection();
  if (!connection.connected) await operator.connect(bench());
  await store.clean();
});

test.describe('A provisioned account is connected to its store through the app', () => {
  test('A key for another store', async ({ page }) => {
    // The app is silent while it provisions the account: the helpdesk asks
    // for a key in the background and gives up after its ten seconds.
    await storeKeys.set(keysStore, { answer: 'silent' });
    Object.assign(keys, await provisionWithAdministrator(keysStore, 'keys'));
    keys.conversation = await conversationIn(keys, `maya.${run}@example.test`);
    await eventually(() => storeKeys.requests(keysStore), list => list.some(entry => entry.status === 'silent'), { timeout: 30_000 });
    await wait(12_000);
    expect(await connectionOf(keys)).toMatchObject({ connected: false, managed_by_app: true, through_app: true });

    // The app answers now, with a key to another store.
    await storeKeys.set(keysStore, { access_token: inventedKey, shop_domain: benchDomain });
    const section = await ordersOf(page, keys);
    await expect(section).toHaveAttribute('data-state', 'not_connected');
    await section.getByTestId('inclamo-connect-app').click();

    await expect(section.getByTestId('inclamo-connect-app-error')).toHaveText('The Inclamo app answered for another store.');
    expect((await connectionOf(keys)).connected).toBe(false);
  });

  test('A key without a read scope', async ({ page }) => {
    await storeKeys.set(keysStore, { access_token: inventedKey, scopes: without('read_orders') });
    const section = await ordersOf(page, keys);
    await section.getByTestId('inclamo-connect-app').click();

    await expect(section.getByTestId('inclamo-connect-app-error')).toHaveText('The Inclamo app does not have this permission at your store: read_orders.');
    expect((await connectionOf(keys)).connected).toBe(false);
  });

  test('The app has no key at that moment', async ({ page }) => {
    // When the account was made (above), the app was asked for a key and
    // did not answer; the account exists without a connection.
    const [first] = await storeKeys.requests(keysStore);
    expect(first).toMatchObject({ signed: true, status: 'silent', account_id: keys.accountId, path: `/helpdesk/stores/${keysStore}/store-key` });
    expect((await storeApp.status(keysStore)).body).toMatchObject({ account_id: keys.accountId, state: 'active' });
    const section = await ordersOf(page, keys);
    await expect(section).toHaveAttribute('data-state', 'not_connected');
    await expect(section).toContainText('Your store connects through the Inclamo app.');

    // The app answers now; the proxy answers the invented store's reads.
    await storeKeys.set(keysStore, { access_token: inventedKey, scopes: TEN });
    const answer = body => ({ effect: 'status', value: { status: 200, body } });
    await proxy.rule({ match: { operation: 'shop_identity' }, ...answer({ data: { shop: { name: `Keys Store ${run}`, myshopifyDomain: keysStore, currencyCode: 'EUR' } } }) });
    await proxy.rule({ match: { operation: 'customer_data_probe' }, ...answer({ data: { orders: { nodes: [] }, customers: { nodes: [] } } }) });
    await proxy.rule({ match: { operation: 'customers_search' }, ...answer({ data: { customers: { nodes: [] } } }) });
    await section.getByTestId('inclamo-connect-app').click();

    await expect(section).toHaveAttribute('data-state', 'none', { timeout: 30_000 });
    expect(await connectionOf(keys)).toMatchObject({ connected: true, status: 'working', auth_kind: 'app_key', shop_domain: keysStore, shop_name: `Keys Store ${run}` });
    await expect((await storeMenu(section)).getByTestId('inclamo-app-connection')).toContainText('Connected through the Inclamo app');
  });

  test('An account the app did not provision', async ({ page }) => {
    expect(await operator.connection()).toMatchObject({ managed_by_app: false, through_app: false });
    await operator.disconnect();
    try {
      await signIn(page, users.admin);
      const section = await openOrders(page, operatorAccount, operatorConversation.id);
      await expect(section).toHaveAttribute('data-state', 'not_connected');

      await expect(section.getByTestId('inclamo-connect-open')).toBeVisible();
      await expect(section.getByTestId('inclamo-connect-app')).toHaveCount(0);
      expect((await operator.post('/inclamo/shopify/connection', { via: 'app' })).body.error).toBe('not_through_app');
    } finally {
      await operator.connect(bench());
    }
  });

  test('A new account', async ({ page }) => {
    await grant();
    Object.assign(shop, await provisionWithAdministrator(benchDomain, 'bench'));

    const connection = await eventually(() => connectionOf(shop), found => found.connected === true, { timeout: 60_000 });
    expect(connection).toMatchObject({ status: 'working', auth_kind: 'app_key', shop_domain: benchDomain, managed_by_app: true });
    expect(connection.shop_name).toBeTruthy();
    expect(await keyRequests()).toEqual([expect.objectContaining({ signed: true, status: 200, account_id: shop.accountId, scopes: expect.arrayContaining(TEN) })]);

    // A conversation of a customer the store knows shows their orders.
    shop.conversation = await conversationIn(shop, maya.email);
    const section = await ordersOf(page, shop);
    await expect(section).toHaveAttribute('data-state', 'matched');
    await orderCard(section, mayaOrder.number);
    const details = (await storeMenu(section)).getByTestId('inclamo-app-connection');
    await expect(details).toContainText('Connected through the Inclamo app');
    await expect(details.getByTestId('inclamo-app-store')).toHaveText(`${connection.shop_name} · ${benchDomain}`);
  });
});

test.describe('The helpdesk asks for no more than it can use', () => {
  test('The app grants fewer scopes than asked', async ({ page }) => {
    await grant({ scopes: ['read_customers', 'read_orders', 'write_orders'] });
    expect((await recheck(shop)).status).toBe(200);

    const connection = await connectionOf(shop);
    expect(connection.scopes).toEqual(['read_customers', 'read_orders', 'write_orders']);
    // The actions of write_orders: cancel, refund, address change, and the order's tags and note.
    expect(connection.actions.filter(action => action.available).map(action => action.name)).toEqual(['cancel', 'refund', 'address', 'order_tags', 'order_note']);
    for (const action of connection.actions.filter(entry => !entry.available)) expect(action.missing_scopes.length).toBeGreaterThan(0);

    const menu = await storeMenu(await ordersOf(page, shop));
    for (const name of ['cancel', 'refund', 'address']) await expect(menu.getByTestId(`inclamo-app-action-${name}`)).toHaveAttribute('data-available', 'true');
    await expect(menu.getByTestId('inclamo-app-action-replacement')).toHaveAttribute('data-available', 'false');
    await expect(menu.getByTestId('inclamo-app-action-discount')).toContainText('the Inclamo app does not have this permission at your store (write_discounts)');
  });
});

test.describe('Granted scopes decide the actions as for any connection', () => {
  test('A direct request for an action the key does not allow', async () => {
    expect((await connectionOf(shop)).scopes).not.toContain('write_discounts');

    const answer = await shop.api.post(`/inclamo/shopify/conversations/${shop.conversation.id}/actions`, {
      action_name: 'discount', action_id: `e2e-discount-${run}`, params: { preset_id: 1 },
    });

    expect(answer.body).toMatchObject({ outcome: 'refused', refusal: 'missing_scope' });
    expect((await connectionOf(shop)).actions.find(action => action.name === 'discount').missing_scopes).toEqual(['write_discounts']);
    expect((await proxy.log()).filter(entry => /discount/.test(entry.operation || ''))).toEqual([]);
  });

  test('The store hides customer data from the app', async ({ page }) => {
    await grant();
    await proxy.rule({ match: { operation: 'customer_data_probe' }, effect: 'patch', value: { patch: 'customers_denied' }, times: 1 });
    try {
      expect((await recheck(shop)).status).toBe(200);
      expect((await connectionOf(shop)).customer_data).toBe('limited');

      // The panel works by the order's number only.
      const section = await ordersOf(page, shop);
      await expect(section).toHaveAttribute('data-state', 'limited');
      await section.getByTestId('inclamo-lookup-number').fill(mayaOrder.number);
      await section.getByTestId('inclamo-lookup-find').click();
      await expect(section.getByTestId(`inclamo-order-${mayaOrder.number}`)).toBeVisible({ timeout: 30_000 });
    } finally {
      await proxy.reset();
      await recheck(shop);
    }
    expect((await connectionOf(shop)).customer_data).toBe('full');
  });

  test("The app's permissions grow", async ({ page }) => {
    await grant({ scopes: without('write_order_edits') });
    await recheck(shop);
    expect((await connectionOf(shop)).actions.find(action => action.name === 'edit_items')).toMatchObject({ available: false, missing_scopes: ['write_order_edits'] });
    const before = (await keyRequests()).length;

    // The Inclamo app is given write_order_edits at the store.
    await grant();
    const section = await ordersOf(page, shop);
    const menu = await storeMenu(section);
    await expect(menu.getByTestId('inclamo-app-action-edit_items')).toHaveAttribute('data-available', 'false');
    await section.getByTestId('inclamo-manage-recheck').click();

    await expect(menu.getByTestId('inclamo-app-action-edit_items')).toHaveAttribute('data-available', 'true');
    expect((await keyRequests()).length).toBe(before + 1);
  });
});

test.describe('The key is renewed without anyone noticing', () => {
  test("An agent works across the key's end", async ({ page }) => {
    test.setTimeout(180_000);
    await signIn(page, shop.user);
    // The key the helpdesk holds has a little over two minutes; the next one lives an hour.
    await grant({ expires_in: 130 });
    await recheck(shop);
    await grant();
    const before = (await keyRequests()).length;

    // The agent opens the order within the pause that follows the app's last answer.
    const section = await openOrders(page, shop.accountId, shop.conversation.id);
    const card = await orderCard(section, mayaOrder.number);
    expect((await keyRequests()).length).toBe(before);

    // Later: the key is due, and the pause after the last request has passed.
    await wait(32_000);
    await card.getByTestId('inclamo-action-refund').click();
    await page.getByTestId('inclamo-refund-mode-amount').check();
    await page.getByTestId('inclamo-refund-amount').fill('5');
    await page.getByTestId('inclamo-refund-calculate').click();
    await expect(page.getByTestId('inclamo-refund-preview')).toContainText('5');
    await page.getByRole('button', { name: /^Refund .+/ }).click();

    await expect.poll(async () => Number((await store.read(mayaOrder)).totalRefundedSet.shopMoney.amount), { timeout: 30_000 }).toBe(5);
    const requests = await keyRequests();
    expect(requests.length).toBe(before + 1);
    expect(requests.at(-1)).toMatchObject({ signed: true, status: 200 });
    expect((await connectionOf(shop)).status).toBe('working');
  });

  test('Many agents at the moment of renewal', async () => {
    test.setTimeout(120_000);
    await grant({ expires_in: 130 });
    await recheck(shop);
    await grant();
    // Past the pause after the last request: the next read renews the key.
    await wait(32_000);
    await storeKeys.clear();

    const panels = await Promise.all(Array.from({ length: 10 }, () => panelOf(shop, shop.conversation.id)));

    expect(panels.map(panel => panel.state)).toEqual(Array(10).fill('matched'));
    expect(await keyRequests()).toHaveLength(1);
  });

  test('The store refuses a key that should still work', async () => {
    await grant();
    const before = (await keyRequests()).length;
    await proxy.rule({ match: { path: GRAPHQL }, effect: 'status', value: { status: 401, body: { errors: '[API] Invalid API key or access token' } }, times: 1 });

    const found = await lookUp(shop, shop.conversation.id);

    expect(found.status).toBe(200);
    expect(found.body).toEqual({ found: false });
    expect((await keyRequests()).length).toBe(before + 1);
    expect((await connectionOf(shop)).status).toBe('working');
  });

  test('The store refuses the new key too', async ({ page }) => {
    await proxy.rule({ match: { path: GRAPHQL }, effect: 'status', value: { status: 401, body: { errors: '[API] Invalid API key or access token' } }, times: 2 });
    try {
      expect((await lookUp(shop, shop.conversation.id)).status).toBe(502);
      expect((await connectionOf(shop)).status).toBe('broken');

      const section = await ordersOf(page, shop);
      await expect(section).toHaveAttribute('data-state', 'broken');
      await expect(section.getByTestId('inclamo-orders-broken-text')).toHaveText('The store connection needs attention: Shopify no longer accepts it.');
    } finally {
      await proxy.reset();
      await recheck(shop);
    }
    expect((await connectionOf(shop)).status).toBe('working');
  });
});

test.describe('An app that does not answer is not a broken connection', () => {
  test("The app is down within the key's time", async ({ page }) => {
    await grant({ expires_in: 1800 });
    await recheck(shop);
    await storeKeys.set(benchDomain, { answer: 'silent' });
    const before = (await keyRequests()).length;

    const section = await ordersOf(page, shop);
    await expect(section).toHaveAttribute('data-state', 'matched');
    const card = await orderCard(section, mayaOrder.number);
    await card.getByTestId('inclamo-action-refund').click();
    await page.getByTestId('inclamo-refund-mode-amount').check();
    await page.getByTestId('inclamo-refund-amount').fill('1');
    await page.getByTestId('inclamo-refund-calculate').click();

    await expect(page.getByTestId('inclamo-refund-preview')).toContainText('1');
    expect((await keyRequests()).length).toBe(before);
  });

  test("The app is down after the key's time", async ({ page }) => {
    test.setTimeout(240_000);
    await grant({ expires_in: 125 });
    await recheck(shop);
    const renewedAt = (await connectionOf(shop)).renewed_at;
    await storeKeys.set(benchDomain, { answer: 'silent' });
    // The key is used up to a minute before its end.
    await wait(70_000);

    const section = await ordersOf(page, shop);
    await expect(section).toHaveAttribute('data-state', 'unavailable', { timeout: 45_000 });
    await expect(section.getByTestId('inclamo-orders-store-data-unavailable')).toHaveText("The store's data is temporarily unavailable. It comes back by itself.");
    await expect(section.locator('[data-testid^="inclamo-order-#"]')).toHaveCount(0);
    const connection = await connectionOf(shop);
    expect(connection).toMatchObject({ status: 'working', renewed_at: renewedAt });
  });

  test('The app comes back', async ({ page }) => {
    test.setTimeout(150_000);
    await grant();
    await signIn(page, shop.user);

    // An agent opens the conversation; nobody presses "check again".
    await expect(async () => {
      const section = await openOrders(page, shop.accountId, shop.conversation.id);
      await expect(section).toHaveAttribute('data-state', 'matched', { timeout: 15_000 });
    }).toPass({ timeout: 120_000, intervals: [5_000, 10_000] });
    await orderCard(page.getByTestId('inclamo-orders-section'), mayaOrder.number);
    expect((await keyRequests()).at(-1)).toMatchObject({ status: 200 });
  });
});

test.describe("The app's removal from the store breaks the connection and says why", () => {
  test('The store uninstalled the app', async ({ page }) => {
    await storeKeys.set(benchDomain, { answer: 'store_not_installed' });
    const section = await ordersOf(page, shop);
    await expect(section).toHaveAttribute('data-state', 'matched');

    // An administrator presses "check again": the helpdesk asks for a key.
    await (await storeMenu(section)).getByTestId('inclamo-manage-recheck').click();

    await expect(section).toHaveAttribute('data-state', 'broken');
    await expect(section.getByTestId('inclamo-orders-broken-text')).toHaveText('The Inclamo app was removed from the store.');
    await expect(section.getByTestId('inclamo-orders-broken-hint')).toHaveText('Install the Inclamo app again in Shopify, then check again.');
    await expect(section.getByTestId('inclamo-reconnect')).toHaveCount(0);
    await expect(section.locator('[data-testid^="inclamo-order-#"]')).toHaveCount(0);
    expect(await connectionOf(shop)).toMatchObject({ status: 'broken', broken_reason: 'app_removed' });
    const records = (await shop.api.get(`/inclamo/shopify/conversations/${shop.conversation.id}/actions`)).body.actions;
    expect(records).toContainEqual(expect.objectContaining({ action: 'refund', outcome: 'accepted', order_number: mayaOrder.number }));
  });

  test('The app is installed again', async ({ page }) => {
    await grant({ scopes: without('write_discounts') });
    const section = await ordersOf(page, shop);
    await expect(section).toHaveAttribute('data-state', 'broken');

    await section.getByTestId('inclamo-broken-recheck').click();

    await expect(section).toHaveAttribute('data-state', 'matched', { timeout: 30_000 });
    expect(await connectionOf(shop)).toMatchObject({ status: 'working', broken_reason: null, scopes: [...without('write_discounts')].sort() });
  });
});

test.describe('The connection through the app belongs to the app', () => {
  test('An administrator tries to connect another store', async () => {
    const before = await connectionOf(shop);
    const another = { shop_domain: `e2e-${run}-another.myshopify.com`, client_id: bench().client_id, client_secret: bench().client_secret };

    const answer = await shop.api.post('/inclamo/shopify/connection', another);

    expect(answer.status).toBe(403);
    expect(answer.body.error).toBe('managed_by_app');
    expect((await shop.api.delete('/inclamo/shopify/connection')).status).toBe(403);
    expect(await connectionOf(shop)).toMatchObject({ auth_kind: 'app_key', shop_domain: benchDomain, status: 'working', scopes: before.scopes });
  });

  test('An agent presses nothing', async ({ page }) => {
    // A person with a password of their own (their own store's account gave
    // them one), whom the administrator adds to the account as an agent.
    const agent = person('agent');
    const own = await storeApp.provision(`e2e-${run}-agentstore.myshopify.com`, { admin: agent });
    expect(await setPassword(own.body.password_setup_url, password('agent'))).toBe(200);
    const added = await shop.api.post('/agents', { name: agent.name, email: agent.email, role: 'agent' });
    expect(added.status).toBe(200);
    expect((await shop.api.post('/inbox_members', { inbox_id: shop.conversation.inbox.id, user_ids: [added.body.id] })).status).toBe(200);
    const asAgent = { ...shop, user: { email: agent.email, password: password('agent') }, api: (await personApi(agent.email, password('agent'))).within(shop.accountId) };

    const seen = await connectionOf(asAgent);
    expect(seen).toMatchObject({ shop_domain: benchDomain, auth_kind: 'app_key', scopes: (await connectionOf(shop)).scopes });
    expect(seen.last_checked_at).toBeTruthy();
    expect((await recheck(asAgent)).status).toBe(403);

    const section = await ordersOf(page, asAgent);
    const menu = await storeMenu(section);
    await expect(menu.getByTestId('inclamo-app-store')).toContainText(benchDomain);
    await expect(menu.getByTestId('inclamo-app-checked')).toBeVisible();
    await expect(section.getByTestId('inclamo-manage-recheck')).toHaveCount(0);
  });
});

test.describe('The key is a secret', () => {
  test('Reading the connection', async ({ page }) => {
    const answer = await shop.api.get('/inclamo/shopify/connection');
    expect(JSON.stringify(answer.body)).not.toContain(benchToken);
    expect(Object.keys(answer.body)).not.toContain('access_token');
    expect(answer.body).toMatchObject({ shop_domain: benchDomain, auth_kind: 'app_key' });
    for (const field of ['shop_name', 'scopes', 'last_checked_at', 'renewed_at']) expect(answer.body[field]).toBeTruthy();

    const section = await ordersOf(page, shop);
    const menu = await storeMenu(section);
    await expect(menu.getByTestId('inclamo-app-store')).toContainText(benchDomain);
    await expect(menu.getByTestId('inclamo-app-checked')).toBeVisible();
    await expect(menu.getByTestId('inclamo-app-renewed')).toBeVisible();
    expect(await page.content()).not.toContain(benchToken);
  });

  test('The account is suspended', async () => {
    const records = (await shop.api.get(`/inclamo/shopify/conversations/${shop.conversation.id}/actions`)).body.actions;
    expect(records.length).toBeGreaterThan(0);

    expect((await storeApp.removal(benchDomain)).body).toEqual({ contract: 1, state: 'suspended' });

    // The app is installed again: its request restores the account, and the
    // helpdesk asks for a new key, the one it held being gone.
    await grant();
    await storeKeys.clear();
    expect((await storeApp.provision(benchDomain, { admin: person('bench') })).body.outcome).toBe('restored');
    await eventually(() => keyRequests(), list => list.some(entry => entry.status === 200), { timeout: 60_000 });
    await eventually(() => connectionOf(shop), found => found.status === 'working', { timeout: 30_000 });
    expect((await shop.api.get(`/inclamo/shopify/conversations/${shop.conversation.id}/actions`)).body.actions).toEqual(records);
  });
});
