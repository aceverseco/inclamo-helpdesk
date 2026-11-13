// Scenarios of behavior contract `sla-badge`. Each describe is a requirement,
// each test one of its scenarios.
//
// Every policy here covers inboxes of its own ("E2E SLA badge ..."), so other
// test files get no timers from them. The targets are short where a test has
// to see a deadline pass: the test stack checks for missed targets every few
// seconds (INCLAMO_SLA_CHECK_SECONDS). The exact thresholds of "soon" (a
// quarter of the target, five minutes at least) are covered by the unit tests
// of the badge rule; here a target is chosen that is plainly on one side.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, eventually, users, chooseQueue } from '../lib/helpdesk.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const PREFIX = 'Badge ';
let admin;
let agent;
const inboxes = {};

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(180_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  for (const name of ['calm', 'soon', 'fast', 'passing', 'resolution', 'older', 'closed']) {
    inboxes[name] = await inbox(`E2E SLA badge ${name}`, [admin.userId, agent.userId]);
  }
  // The agent is not a member of this one.
  inboxes.hidden = await inbox('E2E SLA badge hidden', [admin.userId]);
  await removePolicies();
  await policy({ name: 'calm', first_response_seconds: 900, resolution_seconds: 172_800, inbox_ids: [inboxes.calm.id, inboxes.hidden.id] });
  await policy({ name: 'soon', first_response_seconds: 240, resolution_seconds: 172_800, inbox_ids: [inboxes.soon.id] });
  await policy({ name: 'fast', first_response_seconds: 10, resolution_seconds: 172_800, inbox_ids: [inboxes.fast.id] });
  await policy({ name: 'passing', first_response_seconds: 40, resolution_seconds: 172_800, inbox_ids: [inboxes.passing.id] });
  await policy({ name: 'resolution', first_response_seconds: 7_200, resolution_seconds: 240, inbox_ids: [inboxes.resolution.id] });
});

test.afterAll(async () => {
  await removePolicies();
});

// An inbox of the API channel with the given users as its members.
async function inbox(name, memberIds) {
  const existing = ((await admin.get('/inboxes')).body.payload || []).find(entry => entry.name === name);
  const made = existing || (await admin.post('/inboxes', { name, channel: { type: 'api', webhook_url: '' } })).body;
  await admin.post('/inbox_members', { inbox_id: made.id, user_ids: memberIds });
  return made;
}

// Only this file's policies: other files keep theirs.
async function removePolicies() {
  const { policies = [] } = (await admin.get('/inclamo/sla_policies')).body || {};
  for (const one of policies.filter(entry => entry.name.startsWith(PREFIX))) await admin.delete(`/inclamo/sla_policies/${one.id}`);
}

async function policy({ name, ...fields }) {
  const made = await admin.post('/inclamo/sla_policies', { name: `${PREFIX}${name}`, business_hours_only: false, all_inboxes: false, ...fields });
  expect(made.status, JSON.stringify(made.body)).toBe(201);
  return made.body.policy;
}

const timerOf = async conversationId => (await admin.get(`/inclamo/conversations/${conversationId}/sla`)).body.timer;

// A conversation whose customer wrote first, with its timer applied (when a
// policy covers it). The contact's name is unique: the row is found by it.
let serial = 0;
async function conversationIn(where, { timed = true } = {}) {
  serial += 1;
  const name = `Badge ${where.name.split(' ').pop()} ${process.env.E2E_RUN || 'local'}-${Date.now()}-${serial}`;
  const made = await admin.conversation(where, { name, message: 'Hello, where is my parcel?' });
  if (timed) await eventually(() => timerOf(made.id), timer => timer !== null);
  return { ...made, name };
}

const replyAs = (who, conversation) =>
  who.post(`/conversations/${conversation.id}/messages`, { content: 'Hello, it ships tomorrow.', message_type: 'outgoing', private: false });
const replied = conversation => eventually(() => timerOf(conversation.id), timer => timer.first_response.took_seconds != null);
const missed = conversation => eventually(() => timerOf(conversation.id), timer => timer.first_response.state === 'missed', { timeout: 60_000 });

// The list of one inbox, all of its open conversations; the row of a conversation in it.
async function openList(page, where) {
  await page.goto(`/app/accounts/${account}/inbox/${where.id}`);
  await chooseQueue(page, 'all');
}
const rowOf = (page, conversation) => page.locator('.reference-row-host').filter({ hasText: conversation.name });
const badgeOf = (page, conversation) => rowOf(page, conversation).getByTestId('inclamo-sla-badge');
async function shownRow(page, conversation) {
  await openList(page, inboxes[conversation.name.split(' ')[1]]);
  await rowOf(page, conversation).waitFor({ timeout: 45_000 });
  return badgeOf(page, conversation);
}
// The row has no badge, after the timers of the list were read.
async function expectNoBadge(page, conversation) {
  await page.waitForTimeout(3_000);
  await expect(rowOf(page, conversation)).toBeVisible();
  await expect(badgeOf(page, conversation)).toHaveCount(0);
}
const headerBadge = page => page.locator('.inclamo-conversation-heading').getByTestId('inclamo-sla-badge');

test.describe('A list row shows the SLA target that needs attention', () => {
  test('New conversation waiting for a first reply', async ({ page }) => {
    const conversation = await conversationIn(inboxes.calm);

    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);

    await expect(badge).toHaveAttribute('data-target', 'first_response');
    await expect(badge).toHaveText(/^First reply · 1[34] min$/);
    await expect(badge).toHaveAttribute('aria-label', /^SLA: First reply due in 1[34] min$/);
  });

  test('Replied in time, resolution far away', async ({ page }) => {
    const conversation = await conversationIn(inboxes.calm);
    await replyAs(agent, conversation);
    await replied(conversation);

    await signIn(page, users.agent);
    await shownRow(page, conversation);

    await expectNoBadge(page, conversation);
  });

  test('Resolution deadline approaching', async ({ page }) => {
    const conversation = await conversationIn(inboxes.resolution);
    await replyAs(agent, conversation);
    await replied(conversation);

    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);

    await expect(badge).toHaveAttribute('data-target', 'resolution');
    await expect(badge).toHaveAttribute('data-look', 'soon');
    await expect(badge).toHaveText(/^Resolution · (\d min|\d+ s)$/);
  });
});

test.describe('The badge tells calm, soon and overdue apart', () => {
  test('Calm', async ({ page }) => {
    const conversation = await conversationIn(inboxes.calm);

    await signIn(page, users.agent);

    await expect(await shownRow(page, conversation)).toHaveAttribute('data-look', 'calm');
  });

  test('Soon', async ({ page }) => {
    const conversation = await conversationIn(inboxes.soon);

    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);

    await expect(badge).toHaveAttribute('data-look', 'soon');
    await expect(badge).toHaveText(/^First reply · (\d min|\d+ s)$/);
  });

  test('Overdue', async ({ page }) => {
    const conversation = await conversationIn(inboxes.fast);
    await missed(conversation);

    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);

    await expect(badge).toHaveAttribute('data-look', 'overdue');
    await expect(badge).toHaveText(/^First reply · overdue (\d+ s|\d+ min)$/);
    await expect(badge).toHaveAttribute('aria-label', /^SLA: First reply overdue by /);
  });
});

test.describe('No badge when there is nothing to watch', () => {
  test('Conversation older than the policy', async ({ page }) => {
    const conversation = await conversationIn(inboxes.older, { timed: false });
    await page.waitForTimeout(2_000);
    await policy({ name: 'too late', first_response_seconds: 900, inbox_ids: [inboxes.older.id] });

    await signIn(page, users.agent);
    await shownRow(page, conversation);

    await expectNoBadge(page, conversation);
    expect(await timerOf(conversation.id)).toBeNull();
  });

  test('Late reply', async ({ page }) => {
    test.setTimeout(240_000);
    const conversation = await conversationIn(inboxes.fast);
    await missed(conversation);
    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);
    await expect(badge).toHaveAttribute('data-look', 'overdue');

    await replyAs(agent, conversation);
    await replied(conversation);

    // Without a reload: the row follows the reply within about a minute.
    await expect(badge).toHaveCount(0, { timeout: 100_000 });
    await expect(rowOf(page, conversation)).toBeVisible();
  });
});

test.describe('A paused timer is shown as paused', () => {
  test('Night outside business hours', async ({ page }) => {
    // Closed every day: whatever the time of the run, the inbox is closed now.
    const closed = await admin.put(`/inboxes/${inboxes.closed.id}`, {
      working_hours_enabled: true,
      timezone: 'Europe/Berlin',
      working_hours: [0, 1, 2, 3, 4, 5, 6].map(day => ({ day_of_week: day, closed_all_day: true, open_all_day: false })),
    });
    expect(closed.status, JSON.stringify(closed.body)).toBe(200);
    await policy({ name: 'office hours', first_response_seconds: 7_200, business_hours_only: true, inbox_ids: [inboxes.closed.id] });
    const conversation = await conversationIn(inboxes.closed);

    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);

    await expect(badge).toHaveText('First reply · paused, 2 h');
    await expect(badge).toHaveAttribute('data-paused', 'true');
    // It does not count down.
    await page.waitForTimeout(5_000);
    await expect(badge).toHaveText('First reply · paused, 2 h');
  });
});

test.describe('The conversation header shows the same badge', () => {
  test('Agent opens an overdue conversation', async ({ page }) => {
    const conversation = await conversationIn(inboxes.fast);
    await missed(conversation);

    await signIn(page, users.agent);
    await page.goto(`/app/accounts/${account}/conversations/${conversation.id}`);
    const badge = headerBadge(page);

    await expect(badge).toHaveAttribute('data-look', 'overdue', { timeout: 45_000 });
    await expect(badge).toHaveText(/^First reply · overdue /);
    await badge.hover();
    const details = page.getByTestId('inclamo-sla-badge-details');
    await expect(details).toContainText('SLA "Badge fast"');
    await expect(page.getByTestId('inclamo-sla-badge-first_response')).toHaveText(/^First response: Missed by .+ · due .+/);
    await expect(page.getByTestId('inclamo-sla-badge-resolution')).toHaveText(/^Resolution: 1 d 23 h left · due .+/);
    // The same badge as on the conversation's row in the list beside it.
    await expect(badgeOf(page, conversation)).toHaveAttribute('data-look', 'overdue');
  });
});

test.describe('The badge stays current without reloading', () => {
  test('Deadline passes while the list is open', async ({ page }) => {
    test.setTimeout(240_000);
    const conversation = await conversationIn(inboxes.passing);

    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);
    await expect(badge).toHaveAttribute('data-look', 'soon');

    await expect(badge).toHaveAttribute('data-look', 'overdue', { timeout: 100_000 });
    await expect(badge).toHaveText(/^First reply · overdue /);
  });

  test('Colleague replies', async ({ page }) => {
    test.setTimeout(240_000);
    const conversation = await conversationIn(inboxes.calm);
    await signIn(page, users.agent);
    const badge = await shownRow(page, conversation);
    await expect(badge).toHaveAttribute('data-target', 'first_response');

    await replyAs(admin, conversation);
    await replied(conversation);

    await expect(badge).toHaveCount(0, { timeout: 100_000 });
    await expect(rowOf(page, conversation)).toBeVisible();
  });
});

test.describe('The badge shows only what the staff member may see', () => {
  test('Agent without access to an inbox', async () => {
    const open = await conversationIn(inboxes.calm);
    const closed = await conversationIn(inboxes.hidden);
    const path = `/inclamo/conversation_slas?ids=${open.id},${closed.id}`;

    const forAgent = await agent.get(path);
    const forAdmin = await admin.get(path);

    expect(forAgent.status).toBe(200);
    expect(Object.keys(forAgent.body.timers)).toEqual([String(open.id)]);
    expect(Object.keys(forAdmin.body.timers).sort()).toEqual([String(open.id), String(closed.id)].sort());
    expect(forAdmin.body.timers[String(closed.id)].policy_name).toBe('Badge calm');
  });

  test('SLA data unavailable', async ({ page }) => {
    const conversation = await conversationIn(inboxes.calm);
    await page.route('**/inclamo/conversation_slas*', route => route.abort());

    await signIn(page, users.agent);
    await shownRow(page, conversation);

    await expectNoBadge(page, conversation);
    // The list works as before: the conversation opens from its row.
    await rowOf(page, conversation).click();
    await expect(page).toHaveURL(new RegExp(`/conversations/${conversation.id}$`));
  });
});
