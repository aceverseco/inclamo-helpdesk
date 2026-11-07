// Scenarios of openspec capability `shopify-connection`. Each test is named
// after its scenario; scripts/check-e2e-coverage.mjs relies on that.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, apiAs, proxy, bench, limited, users } from '../lib/helpdesk.mjs';
import { accessToken, credentials } from '../lib/shopify.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
// A store that exists and on which the test app is not installed.
const otherShop = process.env.E2E_OTHER_SHOP_DOMAIN;
let admin;
let agent;
let conversation;
// Has the shape of an admin token and is none: put together here so that no
// token-like string sits in the repository.
const refusedToken = ['shpat', '0'.repeat(32)].join('_');

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  if (!otherShop) throw new Error('E2E_OTHER_SHOP_DOMAIN is not set');
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  const inbox = await admin.inbox([admin.userId, agent.userId]);
  conversation = await admin.conversation(inbox, { name: 'Connection Example' });
  await admin.takeRole(agent.userId);
});

test.beforeEach(async () => {
  await proxy.reset();
});

// Leaves the stand connected for whoever comes next.
test.afterAll(async () => {
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
});

const fillConnect = async (page, { domain, clientId, clientSecret, legacyToken }) => {
  const dialog = page.getByTestId('inclamo-connect-dialog');
  await dialog.getByTestId('inclamo-connect-domain').fill(domain);
  if (legacyToken !== undefined) {
    await dialog.getByTestId('inclamo-connect-kind-legacy_token').check();
    await dialog.getByTestId('inclamo-connect-access-token').fill(legacyToken);
  } else {
    await dialog.getByTestId('inclamo-connect-client-id').fill(clientId);
    await dialog.getByTestId('inclamo-connect-client-secret').fill(clientSecret);
  }
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  return dialog;
};

const openConnectDialog = async page => {
  await admin.disconnect();
  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation.id);
  await expect(section).toHaveAttribute('data-state', 'not_connected');
  await section.getByTestId('inclamo-connect-open').click();
  return section;
};

test('Valid client ID and secret', async ({ page }) => {
  const section = await openConnectDialog(page);
  await fillConnect(page, { domain: bench().shop_domain, clientId: bench().client_id, clientSecret: bench().client_secret });

  await expect(section).not.toHaveAttribute('data-state', 'not_connected');
  const saved = await admin.connection();
  expect(saved).toMatchObject({ connected: true, status: 'working', shop_domain: bench().shop_domain, auth_kind: 'client_credentials' });
  expect(saved.shop_name).toBeTruthy();
  expect(saved.actions.map(action => action.name)).toEqual(['cancel', 'refund', 'address', 'replacement', 'new_order', 'discount']);
  await expect(section.getByTestId('inclamo-manage')).toContainText(saved.shop_name);
});

test('Valid legacy token', async ({ page }) => {
  // No app with a permanent token can be created any more; a token of the
  // test app, entered as a token, takes the same path through the helpdesk.
  const token = await accessToken(credentials('SHOPIFY_BENCH'));
  const section = await openConnectDialog(page);
  await fillConnect(page, { domain: bench().shop_domain, legacyToken: token });

  await expect(section).not.toHaveAttribute('data-state', 'not_connected');
  expect(await admin.connection()).toMatchObject({ connected: true, status: 'working', auth_kind: 'legacy_token' });
});

test('Token renewal', async () => {
  await admin.disconnect();
  // The store says the first token lives one second.
  await proxy.rule({ match: { path: '/admin/oauth/access_token' }, effect: 'patch', value: { patch: 'expires_in', seconds: 1 }, times: 1 });
  expect((await admin.connect(bench())).status).toBe(201);
  await new Promise(resolve => setTimeout(resolve, 2500));
  await proxy.reset();

  // Something that needs the store: looking an order up by its number.
  const lookup = await admin.get(`/inclamo/shopify/conversations/${conversation.id}/lookup?number=999999`);

  expect(lookup.status).toBe(200);
  expect(lookup.body).toEqual({ found: false });
  const exchanges = (await proxy.log()).filter(entry => entry.path === '/admin/oauth/access_token');
  expect(exchanges.length).toBeGreaterThanOrEqual(1);
  expect((await admin.connection()).status).toBe('working');
});

test('App not installed on the store', async ({ page }) => {
  await openConnectDialog(page);
  const dialog = await fillConnect(page, { domain: otherShop, clientId: bench().client_id, clientSecret: bench().client_secret });

  await expect(dialog.getByTestId('inclamo-connect-error')).toContainText('must be installed on the store first');
  expect((await admin.connection()).connected).toBe(false);
});

test('Token the store refuses', async ({ page }) => {
  await openConnectDialog(page);
  const dialog = await fillConnect(page, { domain: bench().shop_domain, legacyToken: refusedToken });

  await expect(dialog.getByTestId('inclamo-connect-error')).toContainText('refused these credentials');
  expect((await admin.connection()).connected).toBe(false);
});

test('Domain that is not a Shopify store domain', async ({ page }) => {
  await openConnectDialog(page);
  await proxy.reset();
  const dialog = await fillConnect(page, { domain: 'shop.example.com', clientId: 'anything', clientSecret: 'anything' });

  await expect(dialog.getByTestId('inclamo-connect-error')).toContainText('your-store.myshopify.com');
  expect(await proxy.log()).toEqual([]);
  expect((await admin.connection()).connected).toBe(false);
});

test('An agent tries to connect', async ({ page }) => {
  await admin.disconnect();
  await signIn(page, users.agent);
  const section = await openOrders(page, account, conversation.id);

  await expect(section).toHaveAttribute('data-state', 'not_connected');
  await expect(section).toContainText('An administrator can connect one');
  await expect(section.getByTestId('inclamo-connect-open')).toHaveCount(0);
  expect((await agent.connect(bench())).status).toBe(403);
  expect((await admin.connection()).connected).toBe(false);
});

test('Token without read_orders', async ({ page }) => {
  await openConnectDialog(page);
  await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes: ['read_customers'] } });
  const dialog = await fillConnect(page, { domain: bench().shop_domain, clientId: bench().client_id, clientSecret: bench().client_secret });

  await expect(dialog.getByTestId('inclamo-connect-error')).toContainText('read_orders');
  expect((await admin.connection()).connected).toBe(false);
});

test('Store whose plan hides customer data', async ({ page }) => {
  const section = await openConnectDialog(page);
  await proxy.rule({ match: { operation: 'customer_data_probe' }, effect: 'patch', value: { patch: 'customers_denied' } });
  await fillConnect(page, { domain: bench().shop_domain, clientId: bench().client_id, clientSecret: bench().client_secret });

  await expect(section).toHaveAttribute('data-state', 'limited');
  await expect(section.getByTestId('inclamo-orders-limited')).toContainText('orders are found by order number only');
  await expect(section.getByTestId('inclamo-orders-limited')).toContainText('custom distribution');
  expect(await admin.connection()).toMatchObject({ connected: true, customer_data: 'limited' });
});

test('App with no distribution method', async ({ page }) => {
  await openConnectDialog(page);
  // The real thing when the third test app is configured: the store has
  // orders and refuses them to it. Otherwise the proxy answers as the store did.
  const app = limited() || bench();
  if (!limited()) await proxy.rule({ match: { operation: 'customer_data_probe' }, effect: 'patch', value: { patch: 'orders_denied' } });
  const dialog = await fillConnect(page, { domain: app.shop_domain, clientId: app.client_id, clientSecret: app.client_secret });

  await expect(dialog.getByTestId('inclamo-connect-error')).toContainText("refuses this app the store's orders");
  await expect(dialog.getByTestId('inclamo-connect-error')).toContainText('custom distribution');
  expect((await admin.connection()).connected).toBe(false);
});

test('Store starts refusing after it was connected', async ({ page }) => {
  await admin.disconnect();
  await admin.connect(bench());
  const inbox = await admin.inbox();
  const asked = await admin.conversation(inbox, { name: 'Refused Example', email: 'refused.example.e2e@example.com' });
  await proxy.rule({ match: { operation: 'customers_search' }, effect: 'patch', value: { patch: 'customers_denied' } });
  await signIn(page, users.admin);
  const section = await openOrders(page, account, asked.id);

  await expect(section).toHaveAttribute('data-state', 'refused');
  await expect(section.getByTestId('inclamo-orders-refused')).toContainText('Shopify refuses the connected app');
  await expect(section.getByTestId('inclamo-orders-refused')).toContainText('custom distribution');
  await expect(section.locator('[data-testid^="inclamo-order-#"]')).toHaveCount(0);
  await expect(section.getByTestId('inclamo-lookup')).toHaveCount(0);
  expect((await admin.connection()).status).toBe('working');

  // The merchant chose a distribution method: the store answers again.
  await proxy.reset();
  await section.getByTestId('inclamo-refused-recheck').click();
  await expect(section).toHaveAttribute('data-state', 'none');
});

test('Reading the connection', async ({ page }) => {
  await admin.disconnect();
  await admin.connect(bench());
  const read = await admin.get('/inclamo/shopify/connection');

  expect(read.body).toMatchObject({ connected: true, shop_domain: bench().shop_domain });
  expect(read.body.scopes).toContain('read_orders');
  expect(read.body.last_checked_at).toBeTruthy();
  expect(JSON.stringify(read.body)).not.toContain(bench().client_secret);
  expect(Object.keys(read.body)).not.toEqual(expect.arrayContaining(['client_secret', 'access_token']));

  await signIn(page, users.admin);
  await openOrders(page, account, conversation.id);
  expect(await page.content()).not.toContain(bench().client_secret);
});

test('Second store', async () => {
  await admin.disconnect();
  await admin.connect(bench());
  await proxy.reset();

  const second = await admin.connect({ ...bench(), shop_domain: otherShop });

  expect(second.status).toBe(422);
  expect(second.body.error).toBe('already_connected');
  expect(second.body.message).toContain('Remove it before connecting another store');
  expect(await proxy.log()).toEqual([]);
  expect((await admin.connection()).shop_domain).toBe(bench().shop_domain);
});

test('Read-only token', async ({ page }) => {
  await admin.disconnect();
  await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes: ['read_customers', 'read_orders'] } });
  await admin.connect(bench());

  const saved = await admin.connection();
  expect(saved.actions.every(action => !action.available && action.reason === 'missing_scope')).toBe(true);
  expect(saved.actions.find(action => action.name === 'cancel').missing_scopes).toEqual(['write_orders']);
  const attempt = await admin.act(conversation.id, { action_name: 'cancel', action_id: `e2e-readonly-${Date.now()}`, order_id: 'gid://shopify/Order/1', params: { reason: 'customer' } });
  expect(attempt.status).toBe(422);
  expect(attempt.body).toMatchObject({ outcome: 'refused', refusal: 'missing_scope' });

  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation.id);
  await expect(section).not.toHaveAttribute('data-state', 'loading');
});

test('Scopes change at the store', async ({ page }) => {
  // Continues from a connection that holds the read scopes only.
  expect((await admin.connection()).actions.every(action => !action.available)).toBe(true);
  await proxy.reset();
  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation.id);

  await section.getByTestId('inclamo-manage-recheck').click();

  await expect.poll(async () => (await admin.connection()).actions.filter(action => action.available).map(action => action.name)).toEqual(['cancel', 'refund', 'address', 'replacement', 'new_order', 'discount']);
});

test('Token revoked at the store', async ({ page }) => {
  await admin.disconnect();
  await admin.connect(bench());
  // The app was uninstalled: the token is refused and no new one is given.
  await proxy.rule({ match: { path: '/admin/api/2026-10/graphql.json' }, effect: 'status', value: { status: 401, body: { errors: '[API] Invalid API key or access token' } } });
  await proxy.rule({ match: { path: '/admin/oauth/access_token' }, effect: 'status', value: { status: 400, contentType: 'text/html', body: '<title>400 - Oauth error app_not_installed</title>' } });
  const withEmail = await admin.conversation(await admin.inbox(), { name: 'Revoked Example', email: `revoked.${Date.now()}@example.com` });

  await signIn(page, users.agent);
  const section = await openOrders(page, account, withEmail.id);
  await expect(section).toHaveAttribute('data-state', 'broken');
  await expect(section).toContainText('needs attention');
  await expect(section.getByTestId('inclamo-order-#1001')).toHaveCount(0);
  await expect(section.getByTestId('inclamo-reconnect')).toHaveCount(0);

  await signIn(page, users.admin);
  const forAdmin = await openOrders(page, account, withEmail.id);
  await expect(forAdmin.getByTestId('inclamo-reconnect')).toBeVisible();
  expect((await admin.connection()).status).toBe('broken');
});

test('Removal', async ({ page }) => {
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  // An attempt on record before the removal: an agent without the role.
  const before = await agent.act(conversation.id, { action_name: 'cancel', action_id: `e2e-removal-${Date.now()}`, order_id: 'gid://shopify/Order/1', params: { reason: 'customer' } });
  expect(before.body.refusal).toBe('not_allowed');
  const recorded = (await admin.actions(conversation.id)).length;

  await signIn(page, users.admin);
  const section = await openOrders(page, account, conversation.id);
  await section.getByTestId('inclamo-manage-remove').click();
  await section.getByTestId('inclamo-manage-remove-confirm').click();

  await expect(section).toHaveAttribute('data-state', 'not_connected');
  expect(await admin.connection()).toMatchObject({ connected: false });
  expect((await admin.actions(conversation.id)).length).toBe(recorded);
});
