// Scenarios of behavior contract `team-queues`. Each describe is a
// requirement, each test one of its scenarios; scripts/check-e2e-coverage.mjs
// relies on the names. Scenarios that need a fresh account, an upgrade or an
// account without an AI agent are covered by backend specs (see that script).
//
// The queues are the account's, and other test files fill them too (urgent
// conversations, AI hand-overs). So a test never expects an absolute number:
// it looks for its own conversations by their contact names and compares a
// count with the list the same person gets.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, eventually, users, runTag } from '../lib/helpdesk.mjs';
import { standIn, aiService, againstAiService, websiteInbox, conversationWith, shopperOn } from '../lib/agent.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const tag = suffix => runTag(`-tq-${suffix}`);
const READY = ['urgent', 'ai_handover', 'overdue', 'delivery', 'cancellation', 'damage', 'missing_parts', 'return'];
const READY_NAMES = ['Urgent', 'Handed over by AI', 'Overdue', 'Delivery', 'Cancellation', 'Damage', 'Missing parts', 'Return'];
const UNAVAILABLE = 'This queue is not available. Showing all conversations.';

let admin;
let agent;
let shared;
let adminOnly;
const slaInboxes = {};
const policies = [];
const shoppers = [];

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(180_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  shared = await inbox('E2E Queues', [admin.userId, agent.userId]);
  adminOnly = await inbox('E2E Queues admin only', [admin.userId]);
  for (const name of ['first', 'resolution']) slaInboxes[name] = await inbox(`E2E Queues SLA ${name}`, [admin.userId, agent.userId]);
  await restoreAll();
});

test.afterAll(async () => {
  await restoreAll();
  for (const id of policies) await admin.delete(`/inclamo/sla_policies/${id}`);
  await Promise.all(shoppers.map(shopper => shopper.close().catch(() => {})));
});

// --- helpers of this file ---------------------------------------------------

async function inbox(name, memberIds) {
  const existing = ((await admin.get('/inboxes')).body.payload || []).find(entry => entry.name === name);
  const made = existing || (await admin.post('/inboxes', { name, channel: { type: 'api', webhook_url: '' } })).body;
  // Exactly these members: "admin only" must stay closed to the agent.
  await admin.patch('/inbox_members', { inbox_id: made.id, user_ids: memberIds });
  return made;
}

// Every queue of the account, hidden ones included, as an administrator reads them.
const allQueues = async () => (await admin.get('/inclamo/team_queues?all=1')).body.queues;
const queuesOf = async api => (await api.get('/inclamo/team_queues')).body.queues;
const queueOf = async (api, key) => (await queuesOf(api)).find(queue => queue.key === key);
const byKey = async key => (await allQueues()).find(queue => queue.key === key);

// The ready queues back as they shipped: shown, named, in the shipped order.
async function restoreAll() {
  for (const queue of await allQueues()) {
    if (!queue.ready) continue;
    await admin.post(`/inclamo/team_queues/${queue.id}/restore`);
    if (queue.hidden) await admin.patch(`/inclamo/team_queues/${queue.id}`, { hidden: false });
  }
  const ready = (await allQueues()).filter(queue => queue.ready);
  const others = (await allQueues()).filter(queue => !queue.ready);
  const ordered = [...READY.map(key => ready.find(queue => queue.key === key)), ...others].filter(Boolean);
  await admin.post('/inclamo/team_queues/reorder', { ids: ordered.map(queue => queue.id) });
}

// What the person's conversation list gets for a queue: Chatwoot's own filter call.
async function listed(api, key) {
  const queue = await queueOf(api, key);
  const answer = await api.post('/conversations/filter', { payload: queue.query.payload });
  return { ids: (answer.body.data?.payload || answer.body.payload || []).map(entry => entry.id), total: answer.body.data?.meta?.all_count ?? answer.body.meta?.all_count };
}
const inQueue = async (api, key, id) => (await listed(api, key)).ids.includes(id);
const enters = (api, key, id, timeout = 30_000) => eventually(() => inQueue(api, key, id), yes => yes, { timeout });
const leaves = (api, key, id, timeout = 30_000) => eventually(() => inQueue(api, key, id), yes => !yes, { timeout });

const conversationIn = (where, name) => admin.conversation(where, { name, message: 'Hello, I have a question about my order.' });
const urgent = id => admin.post(`/conversations/${id}/toggle_priority`, { priority: 'urgent' });
const label = (id, labels) => admin.post(`/conversations/${id}/labels`, { labels });
const labelsOf = async id => (await admin.get(`/conversations/${id}/labels`)).body.payload || [];
const resolve = id => admin.post(`/conversations/${id}/toggle_status`, { status: 'resolved' });
const reply = (api, id) => api.post(`/conversations/${id}/messages`, { content: 'Thank you, we are looking into it.', message_type: 'outgoing' });

const nav = page => page.locator('.team-queue-nav');
const row = (page, key) => page.getByTestId(`inclamo-team-queue-${key}`);
const names = async page => (await nav(page).locator('.nav-row > span:not(.nav-count)').allTextContents()).map(text => text.trim());
const countShown = async (page, key) => (await row(page, key).locator('.nav-count').textContent()).trim();
const list = page => page.locator('.conversations-list-wrap');

async function workspace(page, user) {
  await signIn(page, user);
  await page.goto(`/app/accounts/${account}/dashboard`);
  await nav(page).waitFor({ timeout: 60_000 });
}

async function openQueue(page, key) {
  await row(page, key).click();
  await expect(page).toHaveURL(/\/custom_view\/q-\d+$/);
  await expect(row(page, key)).toHaveAttribute('aria-current', 'page');
}

async function policy(fields) {
  const made = await admin.post('/inclamo/sla_policies', { business_hours_only: false, all_inboxes: false, ...fields });
  expect(made.status, JSON.stringify(made.body)).toBe(201);
  policies.push(made.body.policy.id);
  return made.body.policy;
}

// --- Team queues are shared by the whole account ----------------------------

test.describe('Team queues are shared by the whole account', () => {
  test('Two staff members see the same queues', async ({ browser }) => {
    const seen = {};
    for (const [who, user] of [['admin', users.admin], ['agent', users.agent]]) {
      const context = await browser.newContext();
      const page = await context.newPage();
      await workspace(page, user);
      seen[who] = await names(page);
      await context.close();
    }

    expect(seen.admin).toEqual(READY_NAMES);
    expect(seen.agent).toEqual(seen.admin);
    expect((await queuesOf(agent)).map(queue => queue.id)).toEqual((await queuesOf(admin)).map(queue => queue.id));
  });

  test('A new staff member gets the queues without setup', async ({ page }) => {
    // The second administrator never opened the queues or their settings.
    await workspace(page, users.secondAdmin);

    expect(await names(page)).toEqual(READY_NAMES);
  });

  test('Native queues are unchanged', async ({ page }) => {
    const mine = await conversationIn(shared, `Mine ${tag('mine')}`);
    const nobody = await conversationIn(shared, `Nobody ${tag('nobody')}`);
    await admin.post(`/conversations/${mine.id}/assignments`, { assignee_id: agent.userId });

    await workspace(page, users.agent);
    await page.getByTestId('inclamo-queue-me').click();

    await expect(list(page)).toContainText(`Mine ${tag('mine')}`, { timeout: 30_000 });
    await expect(list(page)).not.toContainText(`Nobody ${tag('nobody')}`);
    await resolve(mine.id);
    await resolve(nobody.id);
  });
});

// --- A queue lists the open conversations that match it ---------------------

test.describe('A queue lists the open conversations that match it', () => {
  test('Urgent conversation appears', async ({ page }) => {
    const name = `Urgent ${tag('urgent')}`;
    const made = await conversationIn(shared, name);
    expect(await inQueue(agent, 'urgent', made.id)).toBe(false);

    await urgent(made.id);

    await enters(agent, 'urgent', made.id);
    await workspace(page, users.agent);
    await openQueue(page, 'urgent');
    await expect(list(page)).toContainText(name, { timeout: 30_000 });
    await resolve(made.id);
    await leaves(agent, 'urgent', made.id);
  });

  test('AI hand-over appears and leaves', async ({ browser, page }) => {
    const website = await websiteInbox(admin, [admin.userId, agent.userId]);
    if (!(await admin.get('/inclamo/ai/connection')).body.connected) {
      const code = againstAiService ? aiService.code : await standIn.code();
      const answer = await admin.post('/inclamo/ai/connection', { connection_code: code, inbox_ids: [website.id] });
      expect(answer.status, JSON.stringify(answer.body)).toBe(201);
    }
    if (!againstAiService) await standIn.failWith(null);
    const text = `I want to talk to a person ${tag('handover')}`;
    const shopper = await shopperOn(browser, website);
    shoppers.push(shopper);
    await shopper.write(text);
    const { id } = await conversationWith(admin, text);

    await enters(agent, 'ai_handover', id, 60_000);
    expect(await labelsOf(id)).toContain('inclamo_handover');
    await workspace(page, users.agent);
    await openQueue(page, 'ai_handover');
    // The list shows a conversation by its contact and its latest message (here
    // the agent's hand-over note), not by what the shopper first wrote.
    const shopperName = (await admin.get(`/conversations/${id}`)).body.meta.sender.name;
    await expect(list(page)).toContainText(shopperName, { timeout: 30_000 });

    await resolve(id);
    await leaves(agent, 'ai_handover', id);
  });

  test('Missed first response appears and leaves', async () => {
    test.setTimeout(240_000);
    await policy({ name: `Queues first ${tag('p1')}`, first_response_seconds: 10, inbox_ids: [slaInboxes.first.id] });
    const made = await conversationIn(slaInboxes.first, `Late first ${tag('first')}`);

    await enters(agent, 'overdue', made.id, 150_000);
    expect(await labelsOf(made.id)).toEqual(expect.arrayContaining(['sla-missed', 'sla-overdue']));

    await reply(agent, made.id);

    await leaves(agent, 'overdue', made.id, 60_000);
    // The record that it was missed stays; only the live mark goes.
    expect(await labelsOf(made.id)).toContain('sla-missed');
    expect(await labelsOf(made.id)).not.toContain('sla-overdue');
    await resolve(made.id);
  });

  test('Missed resolution stays until resolved', async () => {
    test.setTimeout(240_000);
    await policy({ name: `Queues resolution ${tag('p2')}`, resolution_seconds: 10, inbox_ids: [slaInboxes.resolution.id] });
    const made = await conversationIn(slaInboxes.resolution, `Late resolution ${tag('resolution')}`);
    await reply(agent, made.id);

    await enters(agent, 'overdue', made.id, 150_000);
    // Another answer changes nothing: the resolution is what is overdue.
    await reply(agent, made.id);
    await new Promise(wait => setTimeout(wait, 12_000));
    expect(await inQueue(agent, 'overdue', made.id)).toBe(true);

    await resolve(made.id);
    await leaves(agent, 'overdue', made.id, 60_000);
  });

  test('Category label puts a conversation in its queue', async ({ page }) => {
    const name = `Parcel ${tag('delivery')}`;
    const made = await conversationIn(shared, name);

    await label(made.id, ['delivery']);

    await enters(agent, 'delivery', made.id);
    expect(await inQueue(agent, 'return', made.id)).toBe(false);
    await workspace(page, users.agent);
    await openQueue(page, 'delivery');
    await expect(list(page)).toContainText(name, { timeout: 30_000 });
    await resolve(made.id);
  });

  test("The AI agent's category label counts too", async () => {
    // The agent may add only labels that start with inclamo_; who adds the
    // label makes no difference to the queue, so the team's API adds it here.
    const made = await conversationIn(shared, `Send back ${tag('ai-return')}`);

    await label(made.id, ['inclamo_intent_return']);

    await enters(agent, 'return', made.id);
    await resolve(made.id);
  });

  test('Snoozed conversation is not listed', async () => {
    const made = await conversationIn(shared, `Later ${tag('snoozed')}`);
    await urgent(made.id);
    await enters(agent, 'urgent', made.id);

    await admin.post(`/conversations/${made.id}/toggle_status`, { status: 'snoozed', snoozed_until: Math.floor(Date.now() / 1000) + 3_600 });
    await leaves(agent, 'urgent', made.id);

    await admin.post(`/conversations/${made.id}/toggle_status`, { status: 'open' });
    await enters(agent, 'urgent', made.id);
    await resolve(made.id);
  });
});

// --- A queue never widens what a staff member may see -----------------------

test.describe('A queue never widens what a staff member may see', () => {
  test('Agent outside an inbox', async ({ page }) => {
    const hidden = await conversationIn(adminOnly, `Closed inbox ${tag('closed')}`);
    await urgent(hidden.id);
    await enters(admin, 'urgent', hidden.id);

    expect(await inQueue(agent, 'urgent', hidden.id)).toBe(false);
    const forAdmin = await queueOf(admin, 'urgent');
    const forAgent = await queueOf(agent, 'urgent');
    expect(forAdmin.count).toBeGreaterThan(forAgent.count);
    expect(forAgent.count).toBe((await listed(agent, 'urgent')).total);

    await workspace(page, users.agent);
    await openQueue(page, 'urgent');
    await page.waitForTimeout(3_000);
    await expect(list(page)).not.toContainText(`Closed inbox ${tag('closed')}`);
    await resolve(hidden.id);
  });
});

// --- Each queue shows how many conversations it holds -----------------------

test.describe('Each queue shows how many conversations it holds', () => {
  let made;

  test('Count matches the list', async ({ page }) => {
    made = await conversationIn(shared, `Counted ${tag('count')}`);
    await label(made.id, ['damage']);
    await enters(agent, 'damage', made.id);

    await workspace(page, users.agent);
    const { total, ids } = await listed(agent, 'damage');

    expect(ids).toContain(made.id);
    expect(await countShown(page, 'damage')).toBe(String(total));
    expect((await queueOf(agent, 'damage')).count).toBe(total);
  });

  test('Count follows a change', async ({ page }) => {
    await workspace(page, users.agent);
    const before = Number(await countShown(page, 'damage'));

    await resolve(made.id);

    // No reload: the navigation refreshes on the list's own events.
    await expect.poll(async () => Number(await countShown(page, 'damage')), { timeout: 45_000 }).toBe(before - 1);
  });

  test('Count request fails', async ({ page }) => {
    const again = await conversationIn(shared, `Counted again ${tag('count-fail')}`);
    await label(again.id, ['damage']);
    await enters(agent, 'damage', again.id);
    await workspace(page, users.agent);
    const known = await countShown(page, 'damage');
    expect(known).not.toBe('—');

    await page.route('**/inclamo/team_queues*', route => route.abort());
    const failed = page.waitForEvent('requestfailed', request => request.url().includes('/inclamo/team_queues'));
    await page.evaluate(() => window.dispatchEvent(new Event('focus')));
    await failed;
    await page.waitForTimeout(2_000);

    expect(await countShown(page, 'damage')).toBe(known);
    await page.unroute('**/inclamo/team_queues*');
    await resolve(again.id);
  });
});

// --- Administrators manage team queues --------------------------------------

test.describe('Administrators manage team queues', () => {
  const settings = async page => {
    await signIn(page, users.admin);
    await page.goto(`/app/accounts/${account}/settings/team-queues`);
    await page.getByTestId('inclamo-team-queues-page').waitFor({ timeout: 60_000 });
  };
  const field = (page, what, key) => page.getByTestId(`inclamo-team-queue-${what}-${key}`);

  test.afterEach(restoreAll);

  test('Rename', async ({ page, browser }) => {
    const made = await conversationIn(shared, `Part ${tag('rename')}`);
    await label(made.id, ['missing-parts']);
    await settings(page);

    await field(page, 'name', 'missing_parts').fill('Parts requests');
    await field(page, 'name', 'missing_parts').blur();
    await eventually(() => byKey('missing_parts'), queue => queue.name === 'Parts requests');

    const context = await browser.newContext();
    const other = await context.newPage();
    await workspace(other, users.agent);
    expect(await names(other)).toContain('Parts requests');
    expect(await names(other)).not.toContain('Missing parts');
    expect(await inQueue(agent, 'missing_parts', made.id)).toBe(true);
    await context.close();
    await resolve(made.id);
  });

  test('Hide and show', async ({ page, browser }) => {
    await settings(page);

    await field(page, 'shown', 'cancellation').uncheck();
    await eventually(() => byKey('cancellation'), queue => queue.hidden === true);
    const context = await browser.newContext();
    const other = await context.newPage();
    await workspace(other, users.agent);
    expect(await names(other)).toEqual(READY_NAMES.filter(name => name !== 'Cancellation'));

    await field(page, 'shown', 'cancellation').check();
    await eventually(() => byKey('cancellation'), queue => queue.hidden === false);
    await other.reload();
    await nav(other).waitFor({ timeout: 60_000 });
    expect(await names(other)).toEqual(READY_NAMES);
    await context.close();
  });

  test('Reorder', async ({ page, browser }) => {
    await settings(page);

    // "Return" is last of the eight: seven steps up make it first.
    for (let step = 0; step < 7; step += 1) {
      const position = (await allQueues()).findIndex(queue => queue.key === 'return');
      await field(page, 'up', 'return').click();
      await eventually(allQueues, queues => queues.findIndex(queue => queue.key === 'return') === position - 1);
    }

    const context = await browser.newContext();
    const other = await context.newPage();
    await workspace(other, users.agent);
    expect((await names(other))[0]).toBe('Return');
    await context.close();
  });

  test('Restore', async ({ page }) => {
    const queue = await byKey('missing_parts');
    await admin.patch(`/inclamo/team_queues/${queue.id}`, { name: 'Parts requests' });
    await settings(page);
    await expect(field(page, 'name', 'missing_parts')).toHaveValue('Parts requests');

    await field(page, 'restore', 'missing_parts').click();

    await expect(field(page, 'name', 'missing_parts')).toHaveValue('Missing parts', { timeout: 30_000 });
    expect((await byKey('missing_parts')).name).toBe('Missing parts');
  });

  test('Agent cannot manage', async ({ page }) => {
    await signIn(page, users.agent);
    await page.goto(`/app/accounts/${account}/settings/team-queues`);
    await page.waitForTimeout(5_000);
    await expect(page.getByTestId('inclamo-team-queues-page')).toHaveCount(0);
    await expect(page.locator('a[href$="/settings/team-queues"]')).toHaveCount(0);

    const queue = await byKey('urgent');
    expect((await agent.patch(`/inclamo/team_queues/${queue.id}`, { name: 'Mine now' })).status).toBe(403);
    expect((await byKey('urgent')).name).toBe('Urgent');

    await page.goto(`/app/accounts/${account}/dashboard`);
    await nav(page).waitFor({ timeout: 60_000 });
    await openQueue(page, 'urgent');
    await expect(page.locator('#toggleConversationFilterButton')).toHaveCount(0);
  });
});

// --- Opening a queue that is not available ----------------------------------

test.describe('Opening a queue that is not available', () => {
  test.afterEach(restoreAll);

  test('Link to a hidden queue', async ({ page }) => {
    const queue = await byKey('cancellation');
    await admin.patch(`/inclamo/team_queues/${queue.id}`, { hidden: true });
    await signIn(page, users.agent);

    await page.goto(`/app/accounts/${account}/custom_view/q-${queue.id}`);

    await expect(page).toHaveURL(new RegExp(`/accounts/${account}/dashboard`), { timeout: 60_000 });
    await expect(page.getByText(UNAVAILABLE)).toBeVisible();
    await expect(row(page, 'cancellation')).toHaveCount(0);
  });
});
