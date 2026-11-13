// Scenarios of behavior contract `sla-urgency-widget`. Each describe is a
// requirement, each test one of its scenarios.
//
// The widget counts the team queues of the whole account, and other test
// files leave conversations in them. So a test reads the numbers before it
// adds its own conversations and expects them to move by what it added. The
// server keeps a member's answer for half a minute: after a change a test
// waits until the answer has moved, then looks at the widget.
//
// Every policy here covers inboxes of its own ("E2E SLA widget ..."). The
// first test needs an account with no policy at all, so the file starts by
// removing every policy (as sla-timers.spec.mjs does; it runs before this one).
import { test, expect } from '@playwright/test';
import { signIn, apiAs, eventually, users } from '../lib/helpdesk.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const PREFIX = 'Widget ';
const LEVELS = ['overdue', 'soon', 'other'];
let admin;
let agent;
const inboxes = {};

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(180_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  for (const name of ['calm', 'soon', 'fast', 'passing', 'none']) {
    inboxes[name] = await inbox(`E2E SLA widget ${name}`, [admin.userId, agent.userId]);
  }
  // The agent is not a member of this one.
  inboxes.hidden = await inbox('E2E SLA widget hidden', [admin.userId]);
  await removePolicies(() => true);
  await resetLayout(agent);
});

test.afterAll(async () => {
  await removePolicies(one => one.name.startsWith(PREFIX));
  await resetLayout(agent);
});

// An inbox of the API channel with the given users as its members.
async function inbox(name, memberIds) {
  const existing = ((await admin.get('/inboxes')).body.payload || []).find(entry => entry.name === name);
  const made = existing || (await admin.post('/inboxes', { name, channel: { type: 'api', webhook_url: '' } })).body;
  await admin.post('/inbox_members', { inbox_id: made.id, user_ids: memberIds });
  return made;
}

// Back to the account's default layout: the reset names the revision it replaces.
async function resetLayout(who) {
  const { revision } = (await who.get('/inclamo/workspace_layout')).body;
  return who.delete(`/inclamo/workspace_layout?revision=${encodeURIComponent(revision)}`);
}

async function removePolicies(which) {
  const { policies = [] } = (await admin.get('/inclamo/sla_policies')).body || {};
  for (const one of policies.filter(which)) await admin.delete(`/inclamo/sla_policies/${one.id}`);
}

async function policy({ name, ...fields }) {
  const made = await admin.post('/inclamo/sla_policies', { name: `${PREFIX}${name}`, business_hours_only: false, all_inboxes: false, ...fields });
  expect(made.status, JSON.stringify(made.body)).toBe(201);
  return made.body.policy;
}

// The policies of this file: calm (15 minutes, nothing pressing for the length
// of a test), soon (five minutes: soon from the start), fast (ten seconds:
// overdue at once), passing (40 seconds: soon, then overdue while a test looks).
async function policies() {
  await policy({ name: 'calm', first_response_seconds: 900, inbox_ids: [inboxes.calm.id] });
  await policy({ name: 'soon', first_response_seconds: 300, inbox_ids: [inboxes.soon.id] });
  await policy({ name: 'fast', first_response_seconds: 10, inbox_ids: [inboxes.fast.id, inboxes.hidden.id] });
  await policy({ name: 'passing', first_response_seconds: 40, inbox_ids: [inboxes.passing.id] });
}

const timerOf = async conversationId => (await admin.get(`/inclamo/conversations/${conversationId}/sla`)).body.timer;

// An open conversation of a category: labelled, its timer applied when a policy covers its inbox.
let serial = 0;
async function conversationIn(where, label, { timed = true } = {}) {
  serial += 1;
  const made = await admin.conversation(where, { name: `Widget ${serial} ${process.env.E2E_RUN || 'local'}-${Date.now()}`, message: 'Hello, where is my parcel?' });
  const labelled = await admin.post(`/conversations/${made.id}/labels`, { labels: [label] });
  expect(labelled.status, JSON.stringify(labelled.body)).toBe(200);
  if (timed) await eventually(() => timerOf(made.id), timer => timer !== null);
  return made;
}

// What the server answers this member for a queue.
const overviewOf = async who => (await who.get('/inclamo/team_queues/sla_overview')).body;
const queueOf = async (who, key) => (await overviewOf(who)).queues.find(one => one.key === key);
const numbers = queue => LEVELS.map(level => queue[level]);
// Waits (past the half minute an answer is kept) until the queue's numbers moved by `added`.
const moved = (who, key, before, added) =>
  eventually(
    () => queueOf(who, key),
    queue => LEVELS.every((level, at) => queue[level] === before[level] + added[at]),
    { timeout: 120_000, every: 3_000 }
  );

const widget = page => page.locator('[data-widget="sla-overview"]');
const entry = (page, key) => widget(page).locator(`[data-testid="inclamo-sla-overview-queue"][data-queue="${key}"]`);
const shownNumbers = async (page, key) => Promise.all(LEVELS.map(level => entry(page, key).locator(`[data-level="${level}"]`).textContent()));
const toggle = page => widget(page).getByTestId('inclamo-sla-overview-toggle');
// The workspace with the widget in its header; `open`: with the widget's queues shown.
async function workspace(page, user, { open = true } = {}) {
  await signIn(page, user);
  await page.goto(`/app/accounts/${account}/dashboard`);
  await toggle(page).waitFor({ timeout: 60_000 });
  if (!open) return;
  await toggle(page).click();
  await widget(page).getByTestId('inclamo-sla-overview-queues').locator('[data-testid="inclamo-sla-overview-queue"], [data-testid="inclamo-sla-overview-no-policies"]').first().waitFor({ timeout: 30_000 });
}

test.describe('The widget follows the workspace widget rules', () => {
  // First: the account has no policy yet.
  test('Account without SLA policies', async ({ page }) => {
    await eventually(() => overviewOf(admin), body => body.policies === false, { timeout: 60_000, every: 3_000 });

    await workspace(page, users.admin);

    await expect(widget(page).getByTestId('inclamo-sla-overview-no-policies')).toContainText('No SLA policy yet');
    await expect(widget(page).getByTestId('inclamo-sla-overview-queue')).toHaveCount(0);
    await widget(page).getByTestId('inclamo-sla-overview-set-up').click();
    await expect(page).toHaveURL(/\/settings\/sla-policies$/);
  });

  test('Agent removes the widget', async ({ page, browser }) => {
    test.setTimeout(180_000);
    await policies();
    await workspace(page, users.agent, { open: false });

    await page.locator('[data-widget-host="workspace-header"]').getByTestId('configure-widgets').click();
    const editor = page.getByTestId('widget-layout-editor');
    await editor.locator('li').filter({ hasText: 'SLA overview' }).getByRole('button', { name: 'Remove', exact: true }).click();
    await page.getByRole('button', { name: 'Save layout', exact: true }).click();

    await expect(widget(page)).toHaveCount(0);
    await page.reload();
    await page.locator('[data-widget-host="workspace-header"]').waitFor({ timeout: 60_000 });
    await expect(widget(page)).toHaveCount(0);
    // Other staff still see it.
    const other = await browser.newContext({ baseURL: process.env.HELPDESK_URL });
    const theirs = await other.newPage();
    await workspace(theirs, users.admin, { open: false });
    await expect(toggle(theirs)).toBeVisible();
    await other.close();

    // The agent restores the widget: the account's default has it.
    expect((await resetLayout(agent)).status).toBe(200);
    await page.reload();
    await expect(widget(page)).toBeVisible({ timeout: 60_000 });
  });
});

test.describe("The widget counts each queue's conversations by SLA urgency", () => {
  test('Mixed queue', async ({ page }) => {
    test.setTimeout(240_000);
    const before = await queueOf(agent, 'delivery');
    for (const where of [inboxes.fast, inboxes.fast, inboxes.calm, inboxes.calm, inboxes.soon]) await conversationIn(where, 'delivery');

    const after = await moved(agent, 'delivery', before, [2, 1, 2]);

    await workspace(page, users.agent);
    expect(await shownNumbers(page, 'delivery')).toEqual(numbers(after).map(String));
    await expect(entry(page, 'delivery')).toContainText('Delivery');
    // The header itself shows each overdue and each soon conversation once.
    const { totals } = await overviewOf(agent);
    await expect(toggle(page).locator('[data-total="overdue"]')).toHaveText(String(totals.overdue));
    await expect(toggle(page).locator('[data-total="soon"]')).toHaveText(String(totals.soon));
    // The three numbers add up to the count next to the queue in the navigation.
    const counted = (await agent.get('/inclamo/team_queues')).body.queues.find(one => one.key === 'delivery').count;
    expect(after.overdue + after.soon + after.other).toBe(counted);
  });

  test('Conversation without a timer', async ({ page }) => {
    test.setTimeout(180_000);
    const before = await queueOf(agent, 'cancellation');
    const untimed = await conversationIn(inboxes.none, 'cancellation', { timed: false });

    const after = await moved(agent, 'cancellation', before, [0, 0, 1]);

    expect(await timerOf(untimed.id)).toBeNull();
    await workspace(page, users.agent);
    expect(await shownNumbers(page, 'cancellation')).toEqual(numbers(after).map(String));
  });

  test('Hidden queue', async ({ page }) => {
    test.setTimeout(180_000);
    const queue = (await admin.get('/inclamo/team_queues?all=1')).body.queues.find(one => one.key === 'missing_parts');
    try {
      expect((await admin.patch(`/inclamo/team_queues/${queue.id}`, { hidden: true })).status).toBe(200);
      await eventually(() => overviewOf(agent), body => !body.queues.some(one => one.key === 'missing_parts'), { timeout: 60_000, every: 3_000 });

      await workspace(page, users.agent);

      await expect(entry(page, 'delivery')).toBeVisible();
      await expect(entry(page, 'missing_parts')).toHaveCount(0);
    } finally {
      await admin.patch(`/inclamo/team_queues/${queue.id}`, { hidden: false });
    }
  });
});

test.describe("The numbers are the staff member's own", () => {
  test('Agent limited to one inbox', async () => {
    test.setTimeout(240_000);
    const [forAgent, forAdmin] = [await queueOf(agent, 'return'), await queueOf(admin, 'return')];
    await conversationIn(inboxes.fast, 'return');
    await conversationIn(inboxes.fast, 'return');
    await conversationIn(inboxes.hidden, 'return');

    await moved(agent, 'return', forAgent, [2, 0, 0]);
    await moved(admin, 'return', forAdmin, [3, 0, 0]);
  });
});

test.describe('The levels are told apart without relying on colour', () => {
  test('Nothing overdue', async ({ page }) => {
    const calm = (await overviewOf(agent)).queues.find(one => one.overdue === 0);
    expect(calm, 'a queue with nothing overdue').toBeTruthy();

    await workspace(page, users.agent);
    const overdue = entry(page, calm.key).locator('[data-level="overdue"]');

    await expect(overdue).toHaveText('0');
    await expect(overdue).toHaveClass(/zero/);
    await expect(overdue).toHaveAttribute('title', '0 overdue');
    await expect(entry(page, calm.key)).toHaveAttribute('aria-label', new RegExp(`^${calm.name}: 0 overdue, \\d+ due soon, \\d+ others\\. Open the queue\\.$`));
  });
});

test.describe("A queue's entry opens the queue", () => {
  test('Agent clicks the overdue count of "Damage"', async ({ page }) => {
    const queue = (await agent.get('/inclamo/team_queues')).body.queues.find(one => one.key === 'damage');
    await workspace(page, users.agent);

    await entry(page, 'damage').locator('[data-level="overdue"]').click();

    await expect(page).toHaveURL(new RegExp(`/custom_view/q-${queue.id}$`));
  });
});

test.describe('The widget stays current', () => {
  test('Deadline passes', async ({ page }) => {
    test.setTimeout(360_000);
    await workspace(page, users.agent);
    const overdue = entry(page, 'damage').locator('[data-level="overdue"]');
    const before = Number(await overdue.textContent());

    await conversationIn(inboxes.passing, 'damage');

    // Without a reload: the deadline (40 seconds) passes, the answer is kept
    // half a minute and the widget asks once a minute.
    await expect.poll(async () => Number(await overdue.textContent()), { timeout: 240_000, intervals: [5_000] }).toBe(before + 1);
  });
});
