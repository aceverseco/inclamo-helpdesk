// Scenarios of behavior contract `conversation-order-panel` about acting on
// orders. Each describe is a requirement, each test one of its scenarios.
import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, proxy, bench, runTag, users } from '../lib/helpdesk.mjs';
import { openStore } from '../lib/store.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let agent;
let inbox;
let store;
let maya;
let noah;
let orders;
let conversation;

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(900_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  inbox = await admin.inbox([admin.userId, agent.userId]);
  await proxy.reset();
  await admin.disconnect();
  await admin.connect(bench());
  await admin.takeRole(agent.userId);

  store = await openStore(runTag('act'));
  maya = await store.customer('Maya');
  noah = await store.customer('Noah');
  orders = {};
  for (const [name, items] of [['view', 3], ['cancel', 1], ['refund', 1], ['address', 1], ['shipped', 1], ['replace', 3], ['stock', 2], ['lostRefund', 1], ['running', 1]]) {
    orders[name] = await store.order(maya, { items });
  }
  // Two units of each of three items: the first two items ship, the third does not.
  orders.returns = await store.order(maya, { items: 3, quantity: 2 });
  await store.ship(orders.shipped, [0], { company: 'DHL Express', number: 'E2ED4', url: 'https://example.com/track/E2ED4' });
  await store.ship(orders.returns, [0, 1], { company: 'DHL Express', number: 'E2ED5', url: 'https://example.com/track/E2ED5' });
  conversation = await admin.conversation(inbox, { name: 'Actions Example', email: maya.email });
});

test.beforeEach(async () => {
  await proxy.reset();
});

test.afterAll(async () => {
  await proxy.reset();
  await admin.recheck();
  await admin.takeRole(agent.userId);
  await store.clean();
});

const open = async (page, user, number) => {
  await signIn(page, user);
  const section = await openOrders(page, account, conversation.id);
  await expect(section).toHaveAttribute('data-state', 'matched');
  return { section, card: await orderCard(section, number) };
};
const confirm = (page, label) => page.getByRole('button', { name: label }).click();
const act = (api, action, order, params, id = `e2e-${action}-${Date.now()}`) =>
  api.act(conversation.id, { action_name: action, action_id: id, order_id: order.id, params });
const refunded = async order => Number((await store.read(order)).totalRefundedSet.shopMoney.amount);
const lastRecord = async () => (await admin.actions(conversation.id))[0];
const calls = async operation => (await proxy.log()).filter(entry => entry.operation === operation);
// What the store lists for the app of the merchant guide.
const GUIDE_SCOPES = ['read_customers', 'read_orders', 'write_orders', 'write_draft_orders', 'read_draft_orders', 'read_products', 'read_locations', 'read_merchant_managed_fulfillment_orders'];

test.describe('Order actions need a role given by an administrator', () => {
  test('Agent without the role', async ({ page }) => {
    const { section, card } = await open(page, users.agent, orders.view.number);

    await expect(section.locator('[data-testid^="inclamo-order-#"]')).not.toHaveCount(0);
    await expect(card.getByTestId('inclamo-order-item')).toHaveCount(3);
    for (const action of ['cancel', 'refund', 'address', 'replacement']) {
      await expect(card.getByTestId(`inclamo-action-${action}`)).toBeDisabled();
      await expect(card.getByTestId(`inclamo-action-${action}`)).toHaveAttribute('title', /administrator has not allowed you to perform this action/);
    }
    await proxy.reset();
    const direct = await act(agent, 'refund', orders.view, { mode: 'amount', amount: '5' });
    expect(direct.status).toBe(403);
    expect(direct.body).toMatchObject({ outcome: 'refused', refusal: 'not_allowed' });
    expect(await proxy.log()).toEqual([]);
    expect(await refunded(orders.view)).toBe(0);
  });

  test('Administrator gives the role', async ({ page }) => {
    const { section } = await open(page, users.admin, orders.view.number);
    // The panel links to the page of the account settings that holds the switches.
    await section.getByTestId('inclamo-manage-roles').click();
    await expect(page).toHaveURL(/\/settings\/order-actions$/);
    await expect(page.getByRole('link', { name: 'Order actions' })).toBeVisible();
    for (const action of ['cancel', 'refund', 'address', 'replacement']) {
      await page.getByTestId(`inclamo-permission-${agent.userId}-${action}`).check();
      await expect.poll(async () => (await admin.get('/inclamo/order_roles')).body.members.find(member => member.user_id === agent.userId).permissions[action]).toBe(true);
    }
    await expect.poll(async () => (await admin.get('/inclamo/order_roles')).body.members.find(member => member.user_id === agent.userId).can_act).toBe(true);

    const forAgent = await open(page, users.agent, orders.view.number);
    for (const action of ['cancel', 'refund', 'address', 'replacement']) {
      await expect(forAgent.card.getByTestId(`inclamo-action-${action}`)).toBeEnabled();
    }
  });

  test('Role taken away during a confirmation', async ({ page }) => {
    const { card } = await open(page, users.agent, orders.view.number);
    await card.getByTestId('inclamo-action-refund').click();
    await page.getByTestId('inclamo-refund-mode-amount').check();
    await page.getByTestId('inclamo-refund-amount').fill('5');
    await page.getByTestId('inclamo-refund-calculate').click();
    await expect(page.getByTestId('inclamo-refund-preview')).toBeVisible();

    await admin.takeRole(agent.userId);
    await proxy.reset();
    await confirm(page, /^Refund .+/);

    await expect(page.getByTestId('inclamo-action-message')).toContainText('administrator has not allowed');
    expect(await calls('refund_create')).toEqual([]);
    expect(await refunded(orders.view)).toBe(0);
    expect(await lastRecord()).toMatchObject({ action: 'refund', outcome: 'refused', refusal: 'not_allowed' });
  });

  test('Agent tries to give the role', async () => {
    const attempt = await agent.giveRole(agent.userId);

    expect(attempt.status).toBe(403);
    expect((await admin.get('/inclamo/order_roles')).body.members.find(member => member.user_id === agent.userId).can_act).toBe(false);
  });
});

test.describe('Cancel an order', () => {
  test('Unfulfilled paid order', async ({ page }) => {
    const { section, card } = await open(page, users.admin, orders.cancel.number);
    await card.getByTestId('inclamo-action-cancel').click();
    await expect(page.getByTestId('inclamo-cancel-warning')).toContainText('cannot be undone');
    await page.getByTestId('inclamo-cancel-reason').selectOption('CUSTOMER');
    await expect(page.getByTestId('inclamo-cancel-refund')).toBeChecked();
    await confirm(page, 'Cancel the order');

    await expect(section.getByTestId(`inclamo-order-${orders.cancel.number}`).getByTestId('inclamo-order-statuses')).toHaveText('Cancelled', { timeout: 30_000 });
    const held = await store.read(orders.cancel);
    expect(held.cancelledAt).toBeTruthy();
    expect(Number(held.totalRefundedSet.shopMoney.amount)).toBe(orders.cancel.total);
    expect(await admin.notes(conversation.id)).toContain(`Cancelled order ${orders.cancel.number}. Reason: customer. Payment refunded. Items restocked.`);
  });

  test('Order the store will not cancel', async ({ page }) => {
    const { card } = await open(page, users.admin, orders.cancel.number);

    await expect(card.getByTestId('inclamo-action-cancel')).toBeDisabled();
    await expect(card.getByTestId('inclamo-action-cancel')).toHaveAttribute('title', 'The order is cancelled.');
    // And when the state changed meanwhile: the refusal is recorded, nothing else changes.
    const notes = (await admin.notes(conversation.id)).length;
    const late = await act(admin, 'cancel', orders.cancel, { reason: 'customer' });
    expect(late.body).toMatchObject({ outcome: 'refused', refusal: 'already_cancelled' });
    expect((await admin.notes(conversation.id)).length).toBe(notes);
  });
});

test.describe('Refund an order fully or partly', () => {
  test('Partial refund by amount', async ({ page }) => {
    const { section, card } = await open(page, users.admin, orders.refund.number);
    await card.getByTestId('inclamo-action-refund').click();
    await page.getByTestId('inclamo-refund-mode-amount').check();
    await page.getByTestId('inclamo-refund-amount').fill('20');
    await page.getByTestId('inclamo-refund-calculate').click();
    await expect(page.getByTestId('inclamo-refund-preview')).toContainText('20');
    await expect(page.getByTestId('inclamo-refund-preview')).toContainText('back to');
    await confirm(page, /^Refund .+/);

    await expect.poll(async () => (await store.read(orders.refund)).refunds.length, { timeout: 30_000 }).toBe(1);
    const after = await orderCard(section, orders.refund.number);
    await expect(after.getByTestId('inclamo-order-refunds')).toBeVisible({ timeout: 30_000 });
    const held = await store.read(orders.refund);
    expect(held.refunds).toHaveLength(1);
    expect(Number(held.totalRefundedSet.shopMoney.amount)).toBe(20);
    expect((await after.getByTestId('inclamo-order-refunds').innerText()).replace(/,/g, '')).toContain((orders.refund.total - 20).toFixed(2));
    expect((await admin.notes(conversation.id)).some(note => /^Refunded 20(\.0+)? \w+ on order /.test(note) && note.includes(orders.refund.number))).toBe(true);
  });

  // One unit of one item of the order that is kept for this, refunded with
  // restocking, up to the confirmation. Its first two items have shipped, the
  // third has not; every item keeps a unit to refund, so the list stays as it is.
  const startReturn = async (page, index) => {
    const { card } = await open(page, users.admin, orders.returns.number);
    await card.getByTestId('inclamo-action-refund').click();
    await page.getByTestId('inclamo-refund-mode-items').check();
    await page.getByTestId(`inclamo-refund-quantity-${index}`).fill('1');
    await page.getByTestId('inclamo-refund-restock').check();
    await page.getByTestId('inclamo-refund-calculate').click();
    await expect(page.getByTestId('inclamo-refund-preview')).toBeVisible();
  };
  const returnsMade = async () => (await store.read(orders.returns)).refunds.map(refund => refund.refundLineItems.nodes[0]);
  const refundAndRead = async page => {
    const before = (await returnsMade()).length;
    await confirm(page, /^Refund .+/);
    await expect.poll(async () => (await returnsMade()).length, { timeout: 30_000 }).toBe(before + 1);
    return (await returnsMade()).at(-1);
  };

  test('Shipped item put back in stock', async ({ page }) => {
    // The location the order was shipped from.
    const location = (await store.read(orders.returns)).fulfillments[0].location;
    await startReturn(page, 0);
    await expect(page.getByTestId('inclamo-refund-location')).toContainText(location.name);
    await expect(page.getByTestId('inclamo-refund-preview').locator('select')).toHaveCount(0);

    expect(await refundAndRead(page)).toMatchObject({ quantity: 1, restockType: 'RETURN', location: { id: location.id } });
  });

  test('Unshipped item put back in stock', async ({ page }) => {
    // The location that keeps what has not shipped.
    const kept = (await store.read(orders.returns)).fulfillmentOrders.nodes[0].assignedLocation;
    await startReturn(page, 2);
    await expect(page.getByTestId('inclamo-refund-location')).toContainText(kept.name);

    expect(await refundAndRead(page)).toMatchObject({ quantity: 1, restockType: 'CANCEL', location: { id: kept.location.id } });
  });

  test('Item the store names no location for', async ({ page }) => {
    await proxy.rule({ match: { operation: 'refund_assigned_locations' }, effect: 'patch', value: { patch: 'no_fulfillment_orders' } });
    await startReturn(page, 2);
    await expect(page.getByTestId('inclamo-refund-unplaced')).toBeVisible();
    await expect(page.getByTestId('inclamo-refund-location')).toHaveCount(0);

    expect(await refundAndRead(page)).toMatchObject({ quantity: 1, restockType: 'NO_RESTOCK' });
  });

  test('Locations scope missing', async ({ page }) => {
    await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes: GUIDE_SCOPES.filter(scope => scope !== 'read_locations') } });
    await admin.recheck();
    await startReturn(page, 1);

    await expect(page.getByTestId('inclamo-refund-left-out')).toContainText('read_locations');
    await expect(page.getByTestId('inclamo-refund-location')).toHaveCount(0);

    expect(await refundAndRead(page)).toMatchObject({ quantity: 1, restockType: 'NO_RESTOCK' });
    expect([...(await calls('refund_assigned_locations')), ...(await calls('refund_return_locations'))]).toEqual([]);

    await proxy.reset();
    await admin.recheck();
  });

  test('Amount above the refundable', async ({ page }) => {
    const { card } = await open(page, users.admin, orders.view.number);
    await card.getByTestId('inclamo-action-refund').click();
    await proxy.reset();
    await page.getByTestId('inclamo-refund-mode-amount').check();
    await page.getByTestId('inclamo-refund-amount').fill(String(orders.view.total + 6));

    await expect(page.getByTestId('inclamo-refund-above')).toBeVisible();
    await expect(page.getByTestId('inclamo-refund-calculate')).toBeDisabled();
    // Without a calculation the confirm button reads just "Refund", like the card's button; the dialog's is the later one.
    await expect(page.getByRole('button', { name: 'Refund', exact: true }).last()).toBeDisabled();
    expect(await proxy.log()).toEqual([]);
    expect(await refunded(orders.view)).toBe(0);
  });

  test('Repeat after a lost answer', async ({ page }) => {
    test.setTimeout(150_000);
    const id = `e2e-lost-refund-${Date.now()}`;
    // The store makes the refund, and its answer never arrives.
    await proxy.rule({ match: { operation: 'refund_create' }, effect: 'lose_answer', times: 1 });
    const first = await act(admin, 'refund', orders.lostRefund, { mode: 'amount', amount: '20' }, id);
    expect(first.body.outcome).toBe('unknown');

    expect((await admin.actions(conversation.id)).find(record => record.action_id === id).outcome).toBe('unknown');

    // The same confirmation, sent again.
    const second = await act(admin, 'refund', orders.lostRefund, { mode: 'amount', amount: '20' }, id);
    expect(second.body).toMatchObject({ outcome: 'accepted', action_id: id });
    const held = await store.read(orders.lostRefund);
    expect(held.refunds).toHaveLength(1);
    expect(Number(held.totalRefundedSet.shopMoney.amount)).toBe(20);
    const again = await open(page, users.admin, orders.lostRefund.number);
    await expect(again.card.getByTestId('inclamo-order-unknown')).toHaveCount(0);
    expect((await again.card.getByTestId('inclamo-order-refunds').innerText()).replace(/,/g, '')).toContain((orders.lostRefund.total - 20).toFixed(2));
  });
});

test.describe('Change the shipping address', () => {
  test('Unfulfilled order', async ({ page }) => {
    const { section, card } = await open(page, users.admin, orders.address.number);
    await card.getByTestId('inclamo-action-address').click();
    await expect(page.getByTestId('inclamo-address-address1')).toHaveValue('1 Example Street');
    await page.getByTestId('inclamo-address-address1').fill('2 Example Avenue');
    await page.getByTestId('inclamo-address-zip').fill('01030');
    await confirm(page, 'Save address');

    await expect(section.getByTestId(`inclamo-order-${orders.address.number}`)).toBeVisible({ timeout: 30_000 });
    await expect.poll(async () => (await store.read(orders.address)).shippingAddress).toMatchObject({ address1: '2 Example Avenue', zip: '01030' });
    const after = await orderCard(section, orders.address.number);
    await expect(after.getByTestId('inclamo-order-address')).toContainText('2 Example Avenue');
    const notes = await admin.notes(conversation.id);
    expect(notes).toContain(`Changed the shipping address of order ${orders.address.number}.`);
    expect(notes.join(' ')).not.toContain('Example Avenue');
  });

  test('Order already shipped', async ({ page }) => {
    const { card } = await open(page, users.admin, orders.shipped.number);

    await expect(card.getByTestId('inclamo-action-address')).toBeDisabled();
    await expect(card.getByTestId('inclamo-action-address')).toHaveAttribute('title', 'Already shipped.');
  });
});

test.describe('Duplicate an order as a free replacement', () => {
  const replacementsOf = async order => (await store.tagged('replacement')).filter(found => found.note && found.note.includes(order.number));

  test('Damaged item reshipped', async ({ page }) => {
    const { section, card } = await open(page, users.admin, orders.replace.number);
    await card.getByTestId('inclamo-action-replacement').click();
    await expect(page.getByTestId('inclamo-replacement-intro')).toContainText('charged nothing');
    const quantities = page.locator('[data-testid^="inclamo-replacement-quantity-"]');
    await expect(quantities).toHaveCount(3);
    await quantities.nth(1).fill('0');
    await quantities.nth(2).fill('0');
    await confirm(page, 'Create replacement order');

    // Kept from the read that found it: the store's search may miss a new
    // order again on the next read.
    let created;
    await expect
      .poll(async () => {
        const found = await replacementsOf(orders.replace);
        [created] = found;
        return found.length;
      }, { timeout: 45_000 })
      .toBe(1);
    const held = await store.read(created);
    expect(Number(held.totalPriceSet.shopMoney.amount)).toBe(0);
    expect(held.lineItems.nodes).toHaveLength(1);
    expect(held.tags).toContain('replacement');
    expect(held.note).toContain(orders.replace.number);
    await expect(section.getByTestId(`inclamo-order-${created.name}`)).toBeVisible({ timeout: 30_000 });
    expect(await admin.notes(conversation.id)).toContain(`Created replacement order ${created.name} for order ${orders.replace.number}, free of charge.`);
  });

  test('Item no longer in stock', async ({ page }) => {
    await proxy.rule({ match: { operation: 'replacement_draft_complete' }, effect: 'refuse', value: { mutation: 'draftOrderComplete', empty: { draftOrder: null }, message: 'Item is no longer available' }, times: 1 });
    const { card } = await open(page, users.admin, orders.stock.number);
    await card.getByTestId('inclamo-action-replacement').click();
    await confirm(page, 'Create replacement order');

    await expect(page.getByTestId('inclamo-action-message')).toContainText('Item is no longer available', { timeout: 30_000 });
    expect((await calls('replacement_draft_delete')).map(entry => entry.status)).toEqual([200]);
    expect(await lastRecord()).toMatchObject({ action: 'replacement', outcome: 'refused' });
    // No order was created, and the draft is gone from the store.
    await new Promise(resolve => setTimeout(resolve, 5_000));
    expect(await replacementsOf(orders.stock)).toEqual([]);
  });

  test('Repeat after a lost answer', async () => {
    test.setTimeout(150_000);
    const id = `e2e-lost-replacement-${Date.now()}`;
    await proxy.rule({ match: { operation: 'replacement_draft_complete' }, effect: 'lose_answer', times: 1 });
    const first = await act(admin, 'replacement', orders.stock, { items: [] }, id);
    expect(first.body.outcome).toBe('unknown');

    const second = await act(admin, 'replacement', orders.stock, { items: [] }, id);

    expect(second.body).toMatchObject({ outcome: 'accepted', action_id: id });
    expect(second.body.result.new_order_number).toMatch(/^#/);
    await expect.poll(async () => (await replacementsOf(orders.stock)).length, { timeout: 45_000 }).toBe(1);
    // Still one a while later; polled, because the store's search may miss a
    // new order on a single read.
    await new Promise(resolve => setTimeout(resolve, 5_000));
    await expect.poll(async () => (await replacementsOf(orders.stock)).length, { timeout: 30_000 }).toBe(1);
    expect((await calls('replacement_draft_create')).length).toBe(1);
  });

  // The store's answer is changed so that the app seems to lack one scope.
  const withoutScope = missing => async ({ page }) => {
    const kept = GUIDE_SCOPES.filter(scope => scope !== missing && !(missing === 'write_draft_orders' && scope === 'read_draft_orders'));
    await proxy.rule({ match: { operation: 'shop_info' }, effect: 'patch', value: { patch: 'scopes', scopes: kept } });
    await admin.recheck();
    const { section, card } = await open(page, users.admin, orders.view.number);

    await expect(section.locator('[data-testid^="inclamo-order-#"]')).not.toHaveCount(0);
    for (const action of ['cancel', 'refund', 'address']) await expect(card.getByTestId(`inclamo-action-${action}`)).toBeEnabled();
    await expect(card.getByTestId('inclamo-action-replacement')).toBeDisabled();
    await expect(card.getByTestId('inclamo-action-replacement')).toHaveAttribute('title', new RegExp(missing));

    await proxy.reset();
    await admin.recheck();
  };

  test('Draft orders scope missing', withoutScope('write_draft_orders'));

  test('Products scope missing', withoutScope('read_products'));
});

test.describe('Every action leaves a record', () => {
  test('Refused action', async ({ page }) => {
    const notes = (await admin.notes(conversation.id)).length;
    await proxy.rule({ match: { operation: 'refund_create' }, effect: 'refuse', value: { mutation: 'refundCreate', empty: { refund: null }, message: 'Refund amount exceeds the amount available' }, times: 1 });
    const { card } = await open(page, users.admin, orders.view.number);
    await card.getByTestId('inclamo-action-refund').click();
    await page.getByTestId('inclamo-refund-mode-amount').check();
    await page.getByTestId('inclamo-refund-amount').fill('5');
    await page.getByTestId('inclamo-refund-calculate').click();
    await expect(page.getByTestId('inclamo-refund-preview')).toBeVisible();
    await confirm(page, /^Refund .+/);

    await expect(page.getByTestId('inclamo-action-message')).toContainText('Refund amount exceeds the amount available');
    expect((await admin.notes(conversation.id)).length).toBe(notes);
    expect(await lastRecord()).toMatchObject({ action: 'refund', outcome: 'refused', store_message: 'Refund amount exceeds the amount available', order_number: orders.view.number });
    expect(await refunded(orders.view)).toBe(0);
  });
});

test.describe('Failures are shown, never silent', () => {
  test('Store does not answer', async ({ page }) => {
    test.setTimeout(150_000);
    // A contact the helpdesk has not asked the store about, so nothing can be reused.
    const fresh = await admin.conversation(inbox, { name: 'Silent Example', email: noah.email });
    await proxy.rule({ match: { path: '/admin/api/2026-10/graphql.json' }, effect: 'hang' });
    await signIn(page, users.admin);
    const section = await openOrders(page, account, fresh.id);

    await expect(section).toHaveAttribute('data-state', 'unavailable', { timeout: 60_000 });
    await expect(section.getByTestId('inclamo-orders-unavailable')).toContainText('did not answer');
    await expect(section.locator('[data-testid^="inclamo-order-#"]')).toHaveCount(0);

    await proxy.reset();
    await section.getByTestId('inclamo-orders-retry').click();
    await expect(section).toHaveAttribute('data-state', 'matched', { timeout: 30_000 });
  });

  test('Cancellation still running', async ({ page }) => {
    test.setTimeout(180_000);
    // The store accepts the cancellation and keeps saying it is not done.
    await proxy.rule({ match: { operation: 'order_cancel' }, effect: 'patch', value: { patch: 'job_pending' } });
    await proxy.rule({ match: { operation: 'job_status' }, effect: 'patch', value: { patch: 'job_pending' } });
    await proxy.rule({ match: { operation: 'order_details_limited' }, effect: 'patch', value: { patch: 'not_cancelled' } });
    await proxy.rule({ match: { operation: 'order_details' }, effect: 'patch', value: { patch: 'not_cancelled' } });
    await proxy.rule({ match: { operation: 'customer_orders' }, effect: 'patch', value: { patch: 'not_cancelled' } });
    const { card } = await open(page, users.admin, orders.running.number);
    await card.getByTestId('inclamo-action-cancel').click();
    await confirm(page, 'Cancel the order');

    await expect(page.getByTestId('inclamo-action-message')).toContainText('still working', { timeout: 45_000 });
    expect(await lastRecord()).toMatchObject({ action: 'cancel', outcome: 'running' });
    expect((await admin.panel(conversation.id)).open_actions.map(action => action.outcome)).toContain('running');

    // The store has finished; the panel checks again when it is next read.
    await proxy.reset();
    const later = await open(page, users.admin, orders.running.number);
    await expect(later.card.getByTestId('inclamo-order-statuses')).toHaveText('Cancelled', { timeout: 30_000 });
    expect((await admin.panel(conversation.id)).open_actions).toEqual([]);
    expect((await admin.notes(conversation.id)).some(note => note.startsWith(`Cancelled order ${orders.running.number}.`))).toBe(true);
  });
});
