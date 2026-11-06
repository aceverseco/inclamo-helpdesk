// Scenarios of openspec capability `sla-timers`. Each describe is a
// requirement, each test one of its scenarios.
//
// Every policy here covers inboxes of its own ("E2E SLA ..."), except the one
// an administrator creates for all inboxes, which is deleted at once: other
// test files must not get timers, labels or notes from these policies. The
// test stack checks for missed targets every few seconds
// (INCLAMO_SLA_CHECK_SECONDS), so a target of ten seconds is missed quickly.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, eventually, users } from '../lib/helpdesk.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const LABEL = 'sla-missed';
let admin;
let agent;
const inboxes = {};

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  test.setTimeout(180_000);
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  for (const name of ['covered', 'none', 'older', 'deleted', 'rule', 'closed', 'missed', 'summary']) {
    inboxes[name] = await inbox(`E2E SLA ${name}`);
  }
  await removePolicies();
});

test.afterAll(async () => {
  await removePolicies();
});

// An inbox of the API channel with both test users as members.
async function inbox(name) {
  const existing = ((await admin.get('/inboxes')).body.payload || []).find(entry => entry.name === name);
  const made = existing || (await admin.post('/inboxes', { name, channel: { type: 'api', webhook_url: '' } })).body;
  await admin.post('/inbox_members', { inbox_id: made.id, user_ids: [admin.userId, agent.userId] });
  return made;
}

async function removePolicies() {
  const { policies = [] } = (await admin.get('/inclamo/sla_policies')).body || {};
  for (const policy of policies) await admin.delete(`/inclamo/sla_policies/${policy.id}`);
}

async function policy(fields) {
  const made = await admin.post('/inclamo/sla_policies', { business_hours_only: false, all_inboxes: false, ...fields });
  expect(made.status, JSON.stringify(made.body)).toBe(201);
  return made.body.policy;
}

// A conversation whose customer wrote first, as one arriving from a channel.
const conversationIn = (where, name) => admin.conversation(where, { name: `SLA ${name}`, message: 'Hello, where is my parcel?' });

const timerOf = async conversationId => (await agent.get(`/inclamo/conversations/${conversationId}/sla`)).body.timer;
const labelsOf = async conversationId => (await admin.get(`/conversations/${conversationId}/labels`)).body.payload || [];
const slaNotes = async conversationId => (await admin.notes(conversationId)).filter(note => note.startsWith('SLA "'));

// Waits until the conversation's timer is applied (Chatwoot's events are handled in the background).
const timerApplied = conversationId => eventually(() => timerOf(conversationId), timer => timer !== null);

// The header of the SLA section in the conversation sidebar.
const slaHeader = page => page.locator('button.drag-handle').filter({ has: page.locator('h5', { hasText: /^SLA$/ }) });
const ordersHeader = page => page.locator('button.drag-handle').filter({ has: page.locator('h5', { hasText: /^Orders$/ }) });

// Opens a conversation and makes sure the contact sidebar is open; returns once
// its sections are drawn (the Orders section is always there).
async function openConversation(page, conversationId) {
  await page.goto(`/app/accounts/${account}/conversations/${conversationId}`);
  const drawn = () => ordersHeader(page).first().waitFor({ state: 'attached', timeout: 8_000 }).then(() => true, () => false);
  if (!(await drawn())) {
    await page.locator('button[class*="!rounded-full"]').first().click();
    await ordersHeader(page).first().waitFor({ state: 'attached', timeout: 45_000 });
  }
}

// The SLA section of a conversation, expanded the way a person would.
async function openSla(page, conversationId) {
  await openConversation(page, conversationId);
  const section = page.getByTestId('inclamo-sla-section');
  await slaHeader(page).first().waitFor({ state: 'visible', timeout: 30_000 });
  if (!(await section.isVisible())) await slaHeader(page).first().click();
  await section.waitFor({ state: 'visible', timeout: 30_000 });
  return section;
}

// The conversation's sidebar has no SLA section, after its timer was read.
async function expectNoSla(page, conversationId) {
  await openConversation(page, conversationId);
  // The section appears only after the read; leave time for it.
  await page.waitForTimeout(3_000);
  await expect(slaHeader(page)).toHaveCount(0);
  await expect(page.getByTestId('inclamo-sla-section')).toHaveCount(0);
}

const target = (section, name) => section.getByTestId(`inclamo-sla-${name}`);

test.describe('Administrators define SLA policies', () => {
  test('Administrator creates a policy', async ({ page }) => {
    await signIn(page, users.admin);
    // The page is reached from the Settings group of the sidebar.
    await page.goto(`/app/accounts/${account}/settings/order-actions`);
    await page.locator(`a[href$="/settings/sla-policies"]`).first().click();
    await expect(page).toHaveURL(/\/settings\/sla-policies$/);
    await page.getByTestId('inclamo-sla-page').waitFor();

    await page.getByTestId('inclamo-sla-add').click();
    await page.getByTestId('inclamo-sla-name').fill('Standard');
    await page.getByTestId('inclamo-sla-first-value').fill('2');
    await page.getByTestId('inclamo-sla-first-unit').selectOption('hours');
    await page.getByTestId('inclamo-sla-resolution-value').fill('2');
    await page.getByTestId('inclamo-sla-resolution-unit').selectOption('days');
    await page.getByTestId('inclamo-sla-save').click();

    const row = page.locator('[data-testid^="inclamo-sla-policy-"]').filter({ has: page.getByTestId('inclamo-sla-policy-name').filter({ hasText: /^Standard$/ }) });
    await expect(row).toContainText('First response 2 h · Resolution 2 d');
    await expect(row).toContainText('All inboxes');
    const saved = (await admin.get('/inclamo/sla_policies')).body.policies.find(entry => entry.name === 'Standard');
    expect(saved).toMatchObject({ first_response_seconds: 7_200, resolution_seconds: 172_800, all_inboxes: true });

    // It covers every inbox: no other test may meet it.
    await admin.delete(`/inclamo/sla_policies/${saved.id}`);
  });

  test('Policy without a target', async ({ page }) => {
    await signIn(page, users.admin);
    await page.goto(`/app/accounts/${account}/settings/sla-policies`);
    await page.getByTestId('inclamo-sla-page').waitFor();

    await page.getByTestId('inclamo-sla-add').click();
    await page.getByTestId('inclamo-sla-name').fill('No target');
    await page.getByTestId('inclamo-sla-save').click();

    await expect(page.getByTestId('inclamo-sla-form-error')).toContainText('A target is needed');
    await expect(page.getByTestId('inclamo-sla-form')).toBeVisible();
    expect((await admin.get('/inclamo/sla_policies')).body.policies.some(entry => entry.name === 'No target')).toBe(false);
  });

  test('Agent cannot manage policies', async ({ page }) => {
    await signIn(page, users.agent);
    await page.goto(`/app/accounts/${account}/settings/sla-policies`);

    await expect(page).not.toHaveURL(/\/settings\/sla-policies$/, { timeout: 20_000 });
    await expect(page.getByTestId('inclamo-sla-page')).toHaveCount(0);
    // The Settings group of the sidebar, opened if the agent has one, has no entry for the page.
    const settings = page.getByRole('button', { name: /^Settings$/ });
    if (await settings.count()) await settings.first().click();
    await expect(page.locator('a[href$="/settings/sla-policies"]')).toHaveCount(0);
    expect((await agent.get('/inclamo/sla_policies')).status).toBe(403);
  });
});

test.describe('A policy applies to new conversations of its inboxes', () => {
  test('New conversation gets a timer', async ({ page }) => {
    await policy({ name: 'Covered', first_response_seconds: 7_200, resolution_seconds: 172_800, inbox_ids: [inboxes.covered.id] });
    const conversation = await conversationIn(inboxes.covered, 'covered');
    await timerApplied(conversation.id);

    await signIn(page, users.agent);
    const section = await openSla(page, conversation.id);

    await expect(section.getByTestId('inclamo-sla-policy')).toHaveText('Covered');
    await expect(target(section, 'first_response')).toHaveAttribute('data-state', 'running');
    await expect(target(section, 'first_response')).toContainText(/1 h 5\d min left|2 h left/);
    await expect(target(section, 'resolution')).toHaveAttribute('data-state', 'running');
    await expect(target(section, 'resolution')).toContainText(/1 d 23 h left|2 d left/);
  });

  test('Inbox without a policy', async ({ page }) => {
    const conversation = await conversationIn(inboxes.none, 'none');
    // Give the background a moment to apply a timer, were there one to apply.
    await page.waitForTimeout(3_000);
    expect(await timerOf(conversation.id)).toBeNull();

    await signIn(page, users.agent);
    await expectNoSla(page, conversation.id);
  });

  test('Conversation older than the policy', async ({ page }) => {
    const conversation = await conversationIn(inboxes.older, 'older');
    await page.waitForTimeout(2_000);
    await policy({ name: 'Too late', first_response_seconds: 7_200, inbox_ids: [inboxes.older.id] });

    await signIn(page, users.agent);
    await expectNoSla(page, conversation.id);
    expect(await timerOf(conversation.id)).toBeNull();
  });

  test('Policy deleted', async ({ page }) => {
    const doomed = await policy({ name: 'Doomed', first_response_seconds: 20, inbox_ids: [inboxes.deleted.id] });
    const conversation = await conversationIn(inboxes.deleted, 'deleted');
    await timerApplied(conversation.id);

    await admin.delete(`/inclamo/sla_policies/${doomed.id}`);

    await signIn(page, users.agent);
    const section = await openSla(page, conversation.id);
    await expect(target(section, 'first_response')).toHaveAttribute('data-state', 'stopped');
    await expect(section.locator('[data-state="running"]')).toHaveCount(0);

    // Well past the target and several checks later, nothing is marked.
    await page.waitForTimeout(30_000);
    expect(await labelsOf(conversation.id)).not.toContain(LABEL);
    expect(await slaNotes(conversation.id)).toEqual([]);
    expect((await timerOf(conversation.id)).first_response.state).toBe('stopped');
  });
});

test.describe('The two timers stop on the first human reply and on resolution', () => {
  test('Agent replies in time', async ({ page }) => {
    const conversation = await conversationIn(inboxes.covered, 'reply');
    await timerApplied(conversation.id);

    // The agent answers the customer, as the reply box does.
    await agent.post(`/conversations/${conversation.id}/messages`, { content: 'Hello, it ships tomorrow.', message_type: 'outgoing', private: false });
    await eventually(() => timerOf(conversation.id), timer => timer.first_response.state === 'met');

    await signIn(page, users.agent);
    const section = await openSla(page, conversation.id);
    await expect(target(section, 'first_response')).toHaveAttribute('data-state', 'met');
    await expect(target(section, 'first_response')).toContainText('Met in');
    await expect(target(section, 'resolution')).toHaveAttribute('data-state', 'running');
  });

  test('Automatic message does not count', async ({ page }) => {
    await policy({ name: 'Rule inbox', first_response_seconds: 7_200, inbox_ids: [inboxes.rule.id] });
    const rule = await admin.post('/automation_rules', {
      name: 'E2E SLA greeting',
      event_name: 'conversation_created',
      active: true,
      conditions: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inboxes.rule.id], query_operator: null }],
      actions: [{ action_name: 'send_message', action_params: ['Thanks for writing, we will answer soon.'] }],
    });
    expect(rule.status, JSON.stringify(rule.body)).toBe(200);
    try {
      const conversation = await conversationIn(inboxes.rule, 'rule');
      // The rule's message reaches the customer and no person has replied.
      await eventually(
        async () => ((await admin.get(`/conversations/${conversation.id}/messages`)).body.payload || []).map(message => message.content),
        contents => contents.includes('Thanks for writing, we will answer soon.')
      );
      await timerApplied(conversation.id);
      await page.waitForTimeout(3_000);
      expect((await timerOf(conversation.id)).first_response.state).toBe('running');

      await signIn(page, users.agent);
      const section = await openSla(page, conversation.id);
      await expect(target(section, 'first_response')).toHaveAttribute('data-state', 'running');
    } finally {
      await admin.delete(`/automation_rules/${rule.body.id}`);
    }
  });

  test('Resolved in time', async ({ page }) => {
    const conversation = await conversationIn(inboxes.covered, 'resolved');
    await timerApplied(conversation.id);

    await agent.post(`/conversations/${conversation.id}/toggle_status`, { status: 'resolved' });
    await eventually(() => timerOf(conversation.id), timer => timer.resolution.state === 'met');

    await signIn(page, users.agent);
    const section = await openSla(page, conversation.id);
    await expect(target(section, 'resolution')).toHaveAttribute('data-state', 'met');
    await expect(target(section, 'resolution')).toContainText('Met in');
  });
});

test.describe('Business hours', () => {
  test('Conversation created outside business hours', async ({ page }) => {
    // Closed every day: whatever the time of the run, the inbox is closed now.
    const closed = await admin.put(`/inboxes/${inboxes.closed.id}`, {
      working_hours_enabled: true,
      timezone: 'Europe/Berlin',
      working_hours: [0, 1, 2, 3, 4, 5, 6].map(day => ({ day_of_week: day, closed_all_day: true, open_all_day: false })),
    });
    expect(closed.status, JSON.stringify(closed.body)).toBe(200);
    await policy({ name: 'Office hours', first_response_seconds: 7_200, resolution_seconds: 172_800, business_hours_only: true, inbox_ids: [inboxes.closed.id] });
    const conversation = await conversationIn(inboxes.closed, 'closed');
    await timerApplied(conversation.id);

    await signIn(page, users.agent);
    const section = await openSla(page, conversation.id);
    await expect(target(section, 'first_response')).toHaveAttribute('data-state', 'paused');
    await expect(target(section, 'first_response')).toContainText('Paused, 2 h left');
    await expect(target(section, 'resolution')).toHaveAttribute('data-state', 'paused');
    await expect(target(section, 'resolution')).toContainText('Paused, 2 d left');
  });
});

test.describe('A missed target is marked once', () => {
  test('First response missed', async ({ page }) => {
    await policy({ name: 'Ten seconds', first_response_seconds: 10, resolution_seconds: 172_800, inbox_ids: [inboxes.missed.id] });
    const conversation = await conversationIn(inboxes.missed, 'first response missed');
    await timerApplied(conversation.id);

    await eventually(() => labelsOf(conversation.id), labels => labels.includes(LABEL), { timeout: 60_000 });
    // Two more checks later the note is still there once.
    await page.waitForTimeout(12_000);
    expect(await slaNotes(conversation.id)).toEqual(['SLA "Ten seconds": the first-response target of 10 seconds was missed.']);

    await signIn(page, users.agent);
    const section = await openSla(page, conversation.id);
    await expect(target(section, 'first_response')).toHaveAttribute('data-state', 'missed');
    await expect(target(section, 'first_response')).toContainText('Missed by');
    await expect(target(section, 'resolution')).toHaveAttribute('data-state', 'running');
  });

  test('Resolution missed', async ({ page }) => {
    await removePolicies();
    await policy({ name: 'Quick close', resolution_seconds: 10, inbox_ids: [inboxes.missed.id] });
    const conversation = await conversationIn(inboxes.missed, 'resolution missed');
    await timerApplied(conversation.id);

    await eventually(() => slaNotes(conversation.id), notes => notes.length > 0, { timeout: 60_000 });
    expect(await slaNotes(conversation.id)).toEqual(['SLA "Quick close": the resolution target of 10 seconds was missed.']);
    expect(await labelsOf(conversation.id)).toContain(LABEL);

    await signIn(page, users.agent);
    const section = await openSla(page, conversation.id);
    await expect(target(section, 'resolution')).toHaveAttribute('data-state', 'missed');
    await expect(target(section, 'first_response')).toHaveCount(0);
  });
});

test.describe('Summary per policy', () => {
  test('Summary after one met and one missed', async ({ page }) => {
    const watched = await policy({ name: 'Summary', first_response_seconds: 10, inbox_ids: [inboxes.summary.id] });
    const answered = await conversationIn(inboxes.summary, 'answered');
    await agent.post(`/conversations/${answered.id}/messages`, { content: 'Hello, here is your answer.', message_type: 'outgoing', private: false });
    const unanswered = await conversationIn(inboxes.summary, 'unanswered');

    await eventually(() => timerOf(answered.id), timer => timer?.first_response.state === 'met');
    await eventually(() => labelsOf(unanswered.id), labels => labels.includes(LABEL), { timeout: 60_000 });

    await signIn(page, users.admin);
    await page.goto(`/app/accounts/${account}/settings/sla-policies`);
    const summary = page.getByTestId(`inclamo-sla-summary-${watched.id}`);
    await expect(summary).toContainText('2 conversations');
    await expect(summary).toContainText('first response: 50 % met');
  });
});
