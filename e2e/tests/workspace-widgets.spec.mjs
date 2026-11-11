import { test, expect } from '@playwright/test';
import { api, workspace, signIn, product, empty, saveLayout, resetLayouts, screenshot } from '../workspace-support/helpers.mjs';
let admin, agent;
const host = page => page.locator('[data-widget-host="conversation-sidebar"]');
const composer = page => page.locator('.reply-box .ProseMirror').first();
const configure = page => page.locator('.reference-customer-pane').getByTestId('configure-widgets').first();
const editor = page => page.getByTestId('widget-layout-editor');
let apiContext;
test.afterAll(async () => apiContext?.dispose());
test.beforeAll(async ({ playwright }) => {
  const request = apiContext = await playwright.request.newContext(); admin = await api(request, 'theme-admin@example.test'); agent = await api(request); });
test.beforeEach(async () => resetLayouts(admin));

test('Add and remove a card', async ({ page }) => {
  await workspace(page, agent);
  await composer(page).fill('Unsent customer draft');
  await configure(page).click();
  await editor(page).getByRole('button', { name: 'Remove', exact: true }).first().click();
  await page.getByRole('button', { name: 'Save layout', exact: true }).click();
  await expect(host(page).locator('[data-widget="customer-profile"]')).toHaveCount(0);
  await expect(composer(page)).toContainText('Unsent customer draft');
  await configure(page).click();
  await editor(page).getByRole('button', { name: 'Add', exact: true }).click();
  await page.getByRole('button', { name: 'Save layout', exact: true }).click();
  await expect(host(page).locator('[data-widget="customer-profile"]')).toBeVisible();
});

test('Unsupported placement', async () => {
  const invalid = empty(); invalid.placements['workspace-header'] = [{ id: 'orders', collapsed: false }];
  expect((await saveLayout(agent, invalid)).status).toBe(422);
  expect((await agent.call('get', '/inclamo/workspace_layout')).body.layout).toEqual(product());
});

test('A customer has commerce data', async ({ page }, info) => {
  const panels = []; page.on('request', request => { if (request.url().endsWith('/conversations/1/panel')) panels.push(request.url()); });
  await workspace(page, agent);
  await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'matched');
  await expect(host(page).locator('[data-widget="purchase-statistics"]')).toContainText('Lifetime value');
  await expect(page.getByTestId('inclamo-order-#1001')).toBeVisible();
  expect(panels.length).toBe(1);
  await screenshot(page, info, 'widget-defaults');
});

test('Missing or ambiguous commerce data', async ({ page }) => {
  await page.route('**/inclamo/shopify/conversations/1/panel', route => route.fulfill({ json: {
    state: 'ambiguous', viewer: { administrator: false }, connection: { connected: true }, candidates: [{ id: 'candidate', name: 'Synthetic Match', email: 'match@example.test', orders_count: 3 }], orders: [],
  } }));
  await workspace(page, agent);
  await expect(page.getByTestId('inclamo-orders-ambiguous')).toBeVisible();
  await expect(host(page).locator('[data-widget="purchase-statistics"]')).toContainText('Statistics are unavailable');
  await expect(page.getByTestId('inclamo-customer-summary')).toHaveCount(0);
});

test('Personalization survives reload', async ({ page }) => {
  const layout = product(); layout.placements['conversation-sidebar'] = [{ id: 'orders', collapsed: true }];
  expect((await saveLayout(agent, layout)).status).toBe(200);
  await workspace(page, agent); await page.reload();
  await expect(host(page).locator('[data-widget]')).toHaveCount(1);
  await expect(host(page).getByRole('button', { name: 'Orders' })).toHaveAttribute('aria-expanded', 'false');
});

test('Account switch and reset', async ({ page }) => {
  await saveLayout(agent, empty());
  await signIn(page, agent); await page.goto('/app/accounts/2/dashboard');
  await expect(page.locator('[data-widget="notifications"]')).toBeVisible();
  const current = (await agent.call('get', '/inclamo/workspace_layout')).body;
  expect((await agent.call('delete', '/inclamo/workspace_layout', { revision: current.revision })).status).toBe(200);
  await workspace(page, agent);
  await expect(host(page).locator('[data-widget]')).toHaveCount(3);
});

test('Change the default', async () => {
  await saveLayout(agent, empty());
  const revision = (await admin.call('get', '/inclamo/workspace_layout/administration')).body.revision;
  const layout = product(); layout.placements['workspace-header'] = [];
  expect((await admin.call('put', '/inclamo/workspace_layout/administer', { target: 'default', layout, revision })).status).toBe(200);
  expect((await agent.call('get', '/inclamo/workspace_layout')).body.layout).toEqual(empty());
  expect((await admin.call('get', '/inclamo/workspace_layout')).body.layout).toEqual(layout);
});

test('Apply to all members', async ({ page, browser }) => {
  await workspace(page, agent); await configure(page).click();
  await editor(page).getByRole('button', { name: 'Remove', exact: true }).first().click();
  const current = (await admin.call('get', '/inclamo/workspace_layout/administration')).body;
  expect(current.members.length).toBe(3);
  const context = await browser.newContext(); const administration = await context.newPage();
  try {
    await signIn(administration, admin); await administration.goto(`${admin.base}/app/accounts/1/settings/workspace-widgets`);
    await expect(editor(administration)).toBeVisible();
    const remove = editor(administration).getByRole('button', { name: 'Remove', exact: true });
    while (await remove.count()) await remove.first().click();
    await administration.getByRole('combobox').last().selectOption('all');
    await administration.getByRole('button', { name: 'Apply layout', exact: true }).click();
    await expect(administration.locator('dialog[open]')).toContainText('all 3 members');
    await administration.locator('dialog[open]').getByRole('button', { name: 'Apply layout', exact: true }).click();
    await expect(administration.getByText('Layout applied.', { exact: true })).toBeVisible();
  } finally { await context.close(); }
  await expect(page.getByRole('button', { name: 'Save layout', exact: true })).toBeDisabled({ timeout: 25_000 });
  await expect(page.getByText('This layout has changed.', { exact: false })).toBeVisible();
  await page.getByRole('button', { name: 'Reload current layout', exact: true }).click();
  await editor(page).getByRole('button', { name: 'Add', exact: true }).first().click();
  await page.getByRole('button', { name: 'Save layout', exact: true }).click();
  await expect(host(page).locator('[data-widget]')).toHaveCount(1);
});

test('Unauthorized or conflicting edit', async () => {
  const before = (await agent.call('get', '/inclamo/workspace_layout')).body;
  expect((await agent.call('get', '/inclamo/workspace_layout/administration')).status).toBe(403);
  expect((await saveLayout(agent, empty())).status).toBe(200);
  expect((await agent.call('put', '/inclamo/workspace_layout', { layout: product(), revision: before.revision })).status).toBe(409);
});

test('An administrator assigns a layout to a restricted agent', async ({ page }) => {
  const current = (await admin.call('get', '/inclamo/workspace_layout/administration')).body;
  expect((await admin.call('put', '/inclamo/workspace_layout/administer', { target: 'member', user_id: agent.user.id, layout: product(), revision: current.revision })).status).toBe(200);
  await workspace(page, agent);
  await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'matched');
  const order = page.getByTestId('inclamo-order-#1001');
  await order.getByRole('button', { name: /#1001 Placed/ }).click();
  await order.locator('summary').click();
  await expect(order.getByTestId('inclamo-action-cancel')).toBeDisabled();
  expect((await agent.call('post', '/inclamo/order_roles', { user_id: agent.user.id })).status).toBe(403);
});

test('Notification scope', async ({ page }) => {
  await workspace(page, agent);
  const count = (await agent.call('get', '/notifications/unread_count')).body;
  const icon = page.locator('[data-widget="notifications"] a');
  await expect(icon).toHaveAttribute('href', /\/app\/accounts\/1\/inbox/);
  await expect(icon).toHaveAttribute('aria-label', new RegExp(String(count ?? 0)));
});

test('New notification arrives', async ({ page }) => {
  await admin.call('post', '/notifications/read_all', { primary_actor_type: 'Conversation', primary_actor_id: 2 });
  await signIn(page, admin); await page.goto('/app/accounts/1/settings/workspace-widgets');
  const writes = []; page.on('request', request => { if (/notifications/.test(request.url()) && request.method() !== 'GET') writes.push(request.url()); });
  const before = (await admin.call('get', '/notifications/unread_count')).body;
  expect((await admin.call('post', '/conversations/2/messages', { content: 'Synthetic new notification', message_type: 'incoming', private: false })).status).toBe(200);
  await expect.poll(async () => (await admin.call('get', '/notifications/unread_count')).body).toBeGreaterThan(before);
  const after = (await admin.call('get', '/notifications/unread_count')).body;
  await expect(page.locator('[data-widget="notifications"] a')).toHaveAttribute('aria-label', new RegExp(String(after)));
  expect(writes).toEqual([]);
});

test('Header space is limited', async ({ page }, info) => {
  await page.setViewportSize({ width: 768, height: 900 }); await workspace(page, agent);
  await expect(page.locator('[data-widget="notifications"] a')).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await screenshot(page, info, 'header-narrow');
});

test('Agent hides all customer cards', async ({ page }, info) => {
  await saveLayout(agent, empty()); await workspace(page, agent);
  await composer(page).fill('Customer draft survives widget changes');
  await expect(host(page).getByText('No widgets here.', { exact: false })).toBeVisible();
  await page.getByRole('tab', { name: 'Manage', exact: true }).click();
  await expect(page.getByTestId('inclamo-orders-section')).toBeVisible();
  await expect(page.locator('.reference-customer-manage')).toContainText('Maya Example');
  await expect(composer(page)).toContainText('Customer draft survives widget changes');
  await screenshot(page, info, 'all-hidden-manage');
});

test('Agent changes conversations during loading', async ({ page }) => {
  await page.route('**/inclamo/shopify/conversations/1/panel', async route => {
    await new Promise(resolve => setTimeout(resolve, 1800));
    await route.fulfill({ json: { state: 'none', viewer: {}, connection: {}, orders: [], marked_order: null } });
  });
  await page.route('**/inclamo/shopify/conversations/2/panel', route => route.fulfill({ json: { state: 'limited', viewer: {}, connection: {}, orders: [], marked_order: null } }));
  await workspace(page, agent);
  await page.getByText('Alex Example', { exact: true }).first().click();
  await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'limited');
  await page.waitForTimeout(2000);
  await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'limited');
});

test('One card fails', async ({ page }) => {
  await page.route('**/inclamo/shopify/conversations/1/panel', async route => {
    const response = await route.fetch(); const body = await response.json(); body.orders[0].total = null;
    await route.fulfill({ json: body });
  });
  await workspace(page, agent);
  await expect(host(page).locator('[data-widget="orders"]')).toContainText('This widget could not load');
  await expect(host(page).locator('[data-widget="purchase-statistics"]')).toContainText('Lifetime value');
  await expect(composer(page)).toBeVisible();
});

test('A later release adds a widget', async ({ page }) => {
  const legacy = empty(); legacy.placements['conversation-sidebar'] = [{ id: 'orders', collapsed: false }];
  await saveLayout(agent, legacy); await workspace(page, agent);
  await expect(host(page).locator('[data-widget]')).toHaveCount(1);
  await expect(page.locator('[data-widget="notifications"]')).toHaveCount(0);
  await configure(page).click();
  await expect(editor(page)).toContainText('Purchase statistics');
});

test('A widget becomes unavailable', async ({ page }) => {
  await page.route('**/inclamo/workspace_layout', async route => {
    if (route.request().method() !== 'GET') return route.continue();
    const response = await route.fetch(); const body = await response.json();
    body.layout.placements['workspace-header'].push({ id: 'retired-widget', collapsed: false });
    body.unavailable = ['retired-widget']; await route.fulfill({ json: body });
  });
  await workspace(page, agent); await configure(page).click();
  await expect(editor(page)).toContainText('Unavailable widget: retired-widget');
  await expect(page.locator('[data-widget="notifications"]')).toBeVisible();
});

test('Configure without a pointer', async ({ page }) => {
  await workspace(page, agent);
  await configure(page).focus(); await page.keyboard.press('Enter');
  const down = editor(page).getByRole('button', { name: 'Move down', exact: true }).first();
  await down.focus(); await page.keyboard.press('Enter');
  await page.getByRole('button', { name: 'Save layout', exact: true }).focus(); await page.keyboard.press('Enter');
  await expect(host(page).locator('[data-widget]').first()).toHaveAttribute('data-widget', 'purchase-statistics');
  await expect(configure(page)).toBeFocused();
});

test('Narrow conversation view', async ({ page }, info) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await workspace(page, agent);
  await configure(page).click();
  await expect(editor(page)).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  await screenshot(page, info, 'widget-mobile-configure');
});
