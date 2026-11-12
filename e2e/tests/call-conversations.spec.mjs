// Scenarios of behavior contract `call-conversations`. Each test is named
// after its scenario; scripts/check-e2e-coverage.mjs relies on that.
//
// The AI service is the stand-in agent of e2e/stand-in-agent: it files the
// invented calls of e2e/fixtures/calls with the token of the connection's
// agent bot (docs/ai-connector-calls.md), and the tests read what the team's
// API and the dashboard show. Numbers are fictional (555-01xx) and every
// address is at example.com.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users, eventually, runTag } from '../lib/helpdesk.mjs';
import { standIn, againstAiService, websiteInbox, messagesOf, fromAgent, callFixture } from '../lib/agent.mjs';

test.skip(againstAiService, 'calls are filed by the stand-in agent, which holds the bot token');
test.describe.configure({ mode: 'serial' });

const account = process.env.E2E_ACCOUNT_ID || '1';
const INCOMING = 0;
const OUTGOING = 1;
const run = runTag('');
// Fictional numbers of this run: 555-01xx in an area code of its own.
const area = 200 + Math.floor(Math.random() * 700);
let serial = 0;
const number = () => {
  serial += 1;
  return `+1${area}55501${String(serial).padStart(2, '0')}`;
};
const callId = name => `e2e-${run}-${name}`.replace(/[^A-Za-z0-9_:.-]/g, '-');
const address = name => `call-${run}-${name}@example.com`.toLowerCase();

let admin;
let agent;
let website;
let phoneInboxId;

const aiConnection = async () => (await admin.get('/inclamo/ai/connection')).body;

async function ensureConnected() {
  const current = await aiConnection();
  if (!current.connected) {
    const answer = await admin.post('/inclamo/ai/connection', { connection_code: await standIn.code(), inbox_ids: [website.id] });
    if (answer.status !== 201) throw new Error(`could not connect the AI agent: HTTP ${answer.status} ${answer.body?.error}`);
  }
  phoneInboxId = (await aiConnection()).connection.phone_inbox_id;
}

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  website = await websiteInbox(admin, [admin.userId, agent.userId]);
  await ensureConnected();
});

// --- helpers of this file ---------------------------------------------------

// Files a fixture under a call id and a caller of this run.
const file = (fixture, name, overrides = {}) => standIn.call(callFixture(fixture, { call_id: callId(name), caller: { phone: number() }, ...overrides }));
const filed = async (fixture, name, overrides = {}) => {
  const answer = await file(fixture, name, overrides);
  expect(answer.status, JSON.stringify(answer.body)).toBe(201);
  return answer.body;
};
const conversation = async id => (await admin.get(`/conversations/${id}`)).body;
const labelsOf = async id => (await admin.get(`/conversations/${id}/labels`)).body.payload || [];
const contact = async id => (await admin.get(`/contacts/${id}`)).body.payload;
const phoneCalls = async () => (await admin.get(`/conversations?inbox_id=${phoneInboxId}&status=all&assignee_type=all`)).body.data.meta.all_count;
// Files what must be refused, and checks that the Phone inbox got nothing.
const refused = async (send, status, code) => {
  const before = await phoneCalls();
  const answer = await send();
  expect(answer.status).toBe(status);
  if (code) expect(answer.body).toMatchObject({ error: code, code });
  expect(await phoneCalls()).toBe(before);
  return answer;
};
// A filing with another token than the stand-in's, straight to the helpdesk.
const fileWithToken = async (token, call) => {
  const response = await fetch(`${process.env.HELPDESK_URL}/api/v1/accounts/${account}/inclamo/calls`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', api_access_token: token },
    body: JSON.stringify(call),
  });
  return { status: response.status, body: await response.json().catch(() => null) };
};
// Every message of a conversation, read the way the dashboard does: the
// latest page, then the pages before it.
const allMessagesOf = async id => {
  let messages = await messagesOf(admin, id);
  for (;;) {
    const earlier = (await admin.get(`/conversations/${id}/messages?before=${messages[0]?.id}`)).body.payload || [];
    if (!messages.length || !earlier.length) return messages;
    messages = [...earlier, ...messages];
  }
};
const turnsOf = async id => (await allMessagesOf(id)).filter(message => !message.private && [INCOMING, OUTGOING].includes(message.message_type));
const notesOf = async id => (await allMessagesOf(id)).filter(message => message.private);

// The "Call" section of a conversation's sidebar, expanded the way a person would.
const callHeader = page => page.locator('button.drag-handle').filter({ has: page.locator('h5', { hasText: /^Call$/ }) });
async function openManage(page, user, conversationId) {
  await signIn(page, user);
  await page.goto(`/app/accounts/${account}/conversations/${conversationId}`);
  const pane = page.locator('.reference-customer-pane');
  const shown = await pane.waitFor({ state: 'visible', timeout: 15_000 }).then(() => true, () => false);
  if (!shown) await page.getByTestId('inclamo-toggle-customer').click();
  await pane.waitFor({ state: 'visible', timeout: 30_000 });
  await page.getByRole('tab', { name: 'Manage', exact: true }).click();
  await page.locator('.reference-customer-manage').waitFor({ state: 'visible', timeout: 30_000 });
}

// --- A finished call becomes one conversation in the Phone inbox --------------

test('A resolved inbound call', async ({ page }) => {
  const fixture = callFixture('resolved-inbound');
  const caller = number();
  const answer = await filed('resolved-inbound', 'resolved', { caller: { phone: caller, name: 'Anna Example' } });

  const record = await conversation(answer.conversation_id);
  expect(record.inbox_id).toBe(phoneInboxId);
  expect(record.meta.sender.id).toBe(answer.contact_id);
  expect(record.custom_attributes).toMatchObject({
    inclamo_call_entry: 'inbound', inclamo_call_line: fixture.line, inclamo_call_caller: caller, inclamo_call_duration: 192,
    inclamo_call_ended_at: fixture.ended_at, inclamo_call_outcome: 'resolved',
  });
  const messages = await messagesOf(admin, answer.conversation_id);
  const turns = messages.filter(message => !message.private && [INCOMING, OUTGOING].includes(message.message_type));
  expect(turns.map(message => message.content)).toEqual(fixture.turns.map(turn => turn.text));
  expect(turns.filter(message => message.message_type === INCOMING)).toHaveLength(4);
  expect(turns.filter(message => message.message_type === OUTGOING)).toHaveLength(4);
  expect(turns.filter(message => message.message_type === OUTGOING).every(fromAgent)).toBe(true);
  const notes = messages.filter(message => message.private);
  expect(notes).toHaveLength(1);
  expect(notes[0].content).toMatch(/^Resolved by the agent/);
  expect(messages.filter(message => message.message_type !== 2).at(-1).id).toBe(notes[0].id);

  // The team reads the call as a chat.
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/conversations/${answer.conversation_id}`);
  await expect(page.getByText('Order 1042 was shipped on Monday and arrives on Thursday.').first()).toBeVisible({ timeout: 45_000 });
  await expect(page.getByText('Good, can I still change the address?').first()).toBeVisible();
});

test('A call where the caller said nothing', async () => {
  const answer = await filed('no-conversation', 'silent');

  const messages = (await messagesOf(admin, answer.conversation_id)).filter(message => message.message_type !== 2);
  expect(messages).toHaveLength(1);
  expect(messages[0]).toMatchObject({ private: true });
  expect(messages[0].content).toMatch(/^No conversation/);
});

test("Turns keep the call's times", async () => {
  const fixture = callFixture('resolved-inbound');
  const answer = await filed('resolved-inbound', 'times');

  const turns = await turnsOf(answer.conversation_id);
  expect(turns.map(message => message.created_at)).toEqual(fixture.turns.map(turn => Date.parse(turn.at) / 1000));
});

// --- Only the connected AI agent may file a call -------------------------------

test("The connection's agent files a call", async () => {
  const answer = await file('resolved-inbound', 'own-token');

  expect(answer.status).toBe(201);
  expect((await conversation(answer.body.conversation_id)).inbox_id).toBe(phoneInboxId);
});

test("An administrator's token", async () => {
  const token = (await admin.get(`${process.env.HELPDESK_URL}/api/v1/profile`)).body.access_token;
  expect(token).toBeTruthy();

  await refused(() => fileWithToken(token, callFixture('resolved-inbound', { call_id: callId('admin-token') })), 401);
});

test('Another agent bot', async () => {
  const bot = (await admin.post('/agent_bots', { name: `E2E call bot ${run}`, outgoing_url: '' })).body;
  expect(bot.access_token).toBeTruthy();

  await refused(() => fileWithToken(bot.access_token, callFixture('resolved-inbound', { call_id: callId('other-bot') })), 401);
  await admin.delete(`/agent_bots/${bot.id}`);
});

// --- The call lands on the caller's contact -----------------------------------

test('The caller chatted before', async () => {
  const email = address('chatted');
  const chat = await admin.conversation(await admin.inbox([admin.userId, agent.userId]), { name: 'Anna Example', email, message: 'Where is my order?' });

  const answer = await filed('team-request', 'chatted', { caller: { phone: number(), email } });

  expect(answer).toMatchObject({ contact_id: chat.contactId, matched_by: 'email' });
  const conversations = (await admin.get(`/contacts/${chat.contactId}/conversations`)).body.payload.map(entry => entry.id);
  expect(conversations).toEqual(expect.arrayContaining([chat.id, answer.conversation_id]));
  expect(await contact(chat.contactId)).toMatchObject({ name: 'Anna Example', email, phone_number: null });
});

test('The number is known', async () => {
  const phone = number();
  const known = await admin.conversation(await admin.inbox(), { name: 'Maya Example', phone, message: 'Hello' });
  const before = await contact(known.contactId);

  const answer = await filed('resolved-inbound', 'known-number', { caller: { phone, name: 'Somebody else', email: address('known-other') } });

  expect(answer).toMatchObject({ contact_id: known.contactId, matched_by: 'phone' });
  const after = await contact(known.contactId);
  expect([after.name, after.email, after.phone_number]).toEqual([before.name, before.email, before.phone_number]);
});

test('No caller id', async () => {
  const answer = await filed('resolved-inbound', 'no-caller-id', { caller: {} });

  expect(answer.matched_by).toBe('anonymous');
  expect(await contact(answer.contact_id)).toMatchObject({ name: 'Unknown caller', email: null, phone_number: null });
  expect(await labelsOf(answer.conversation_id)).toContain('inclamo_no_caller_id');
});

test('A new caller', async () => {
  const phone = number();
  const answer = await filed('resolved-inbound', 'new-caller', { caller: { phone, name: 'Ben' } });

  expect(answer.matched_by).toBe('created');
  expect(await contact(answer.contact_id)).toMatchObject({ name: 'Ben', phone_number: phone });
  expect((await conversation(answer.conversation_id)).meta.sender.id).toBe(answer.contact_id);
});

// --- One call gives one conversation -------------------------------------------

test('The AI service files the same call again', async () => {
  const first = await filed('team-request', 'again');
  const before = (await messagesOf(admin, first.conversation_id)).map(message => [message.id, message.content]);

  const second = await file('team-request', 'again', { record: 'Another record', turns: [] });

  expect(second.status).toBe(200);
  expect(second.body).toMatchObject({ conversation_id: first.conversation_id, contact_id: first.contact_id, found: true });
  expect((await messagesOf(admin, first.conversation_id)).map(message => [message.id, message.content])).toEqual(before);
});

test('Two filings at once', async () => {
  const call = callFixture('team-request', { call_id: callId('at-once'), caller: { phone: number() } });
  const before = await phoneCalls();

  const answers = await Promise.all([standIn.call(call), standIn.call(call)]);

  expect(answers.map(answer => answer.status).sort()).toEqual([200, 201]);
  expect(answers[0].body.conversation_id).toBe(answers[1].body.conversation_id);
  expect(await phoneCalls()).toBe(before + 1);
});

// --- Status, priority and labels follow the call --------------------------------

test('A request for the team', async () => {
  const answer = await filed('team-request', 'team-request');

  expect((await conversation(answer.conversation_id)).status).toBe('open');
  expect((await labelsOf(answer.conversation_id)).sort()).toEqual(['inclamo_call', 'inclamo_escalation', 'inclamo_handover', 'inclamo_inbound']);
});

test('An urgent request', async () => {
  const answer = await filed('team-request', 'urgent', { priority: 'urgent' });

  expect(await conversation(answer.conversation_id)).toMatchObject({ status: 'open', priority: 'urgent' });
});

test('A resolved call', async () => {
  const answer = await filed('resolved-inbound', 'resolved-status');

  expect((await conversation(answer.conversation_id)).status).toBe('resolved');
  expect(await labelsOf(answer.conversation_id)).toContain('inclamo_resolved');
});

test("A label of someone else's", async () => {
  await refused(() => file('resolved-inbound', 'foreign-label', { labels: ['inclamo_call', 'vip'] }), 422, 'invalid_label');
});

// --- The call card shows the call -----------------------------------------------

test('The card of a call', async ({ page }) => {
  const phone = number();
  await admin.conversation(await admin.inbox(), { name: 'Card Example', phone, message: 'Hello' });
  const fixture = callFixture('team-request');
  const answer = await filed('team-request', 'card', { caller: { phone } });
  expect(answer.matched_by).toBe('phone');

  await openManage(page, users.admin, answer.conversation_id);
  const section = page.getByTestId('inclamo-call-section');
  await callHeader(page).first().waitFor({ state: 'visible', timeout: 30_000 });
  if (!(await section.isVisible())) await callHeader(page).first().click();
  await section.waitFor({ state: 'visible', timeout: 30_000 });

  await expect(section.getByTestId('inclamo-call-entry')).toHaveText("Call to the shop's number");
  await expect(section.getByTestId('inclamo-call-line')).toContainText(fixture.line);
  await expect(section.getByTestId('inclamo-call-caller')).toContainText(phone);
  await expect(section.getByTestId('inclamo-call-duration')).toContainText('3 min 12 s');
  await expect(section.getByTestId('inclamo-call-ended')).toContainText('2026');
  await expect(section.getByTestId('inclamo-call-outcome')).toContainText('Request for the team');
  await expect(section.getByTestId('inclamo-call-matched')).toContainText('Found by number');
  const link = section.getByTestId('inclamo-call-recording');
  await expect(link).toHaveAttribute('href', fixture.recording_url);
  await expect(link).toHaveAttribute('target', '_blank');
  // Kept in the run's output for review; not published by CI.
  await page.screenshot({ path: `${process.env.E2E_OUTPUT || './output'}/call-card.png` });
});

test('A chat has no card', async ({ page }) => {
  const chat = await admin.conversation(await admin.inbox([admin.userId, agent.userId]), { name: 'Chat Example', email: address('no-card'), message: 'Just a chat' });

  await openManage(page, users.admin, chat.id);
  // The sections of the tab are drawn; leave the call card time to appear if it would.
  await page.waitForTimeout(3_000);

  await expect(callHeader(page)).toHaveCount(0);
  await expect(page.getByTestId('inclamo-call-section')).toHaveCount(0);
});

// --- Filing a call reaches nobody outside and wakes no agent ----------------------

test("The agent's turns stay records", async () => {
  const email = address('records');
  const answer = await filed('team-request', 'records', { caller: { phone: number(), email, name: 'Record Example' } });
  expect((await contact(answer.contact_id)).email).toBe(email);

  // The Phone inbox has nowhere to send to: no webhook address, no agent bot.
  const inbox = (await admin.get(`/inboxes/${phoneInboxId}`)).body;
  expect(inbox.webhook_url || '').toBe('');
  expect((await admin.get(`/inboxes/${phoneInboxId}/agent_bot`)).body.agent_bot || null).toBeNull();
  // The outgoing turns were written as sent records; nothing fails or changes afterwards.
  await new Promise(resolve => setTimeout(resolve, 5_000));
  const turns = await turnsOf(answer.conversation_id);
  const outgoing = turns.filter(message => message.message_type === OUTGOING);
  expect(outgoing).toHaveLength(2);
  expect(outgoing.every(message => message.status === 'sent' && !message.content_attributes?.external_error)).toBe(true);
  expect(await standIn.deliveries(answer.conversation_id)).toEqual([]);
});

test('The agent bot stays quiet', async () => {
  await standIn.clear();
  const turns = Array.from({ length: 20 }, (_, index) => ({ role: index % 2 ? 'caller' : 'agent', text: `Turn ${index + 1} of a quiet call` }));

  const answer = await filed('team-request', 'quiet', { turns });

  // All twenty, once each and in the call's order, across the pages the dashboard reads.
  expect((await turnsOf(answer.conversation_id)).map(message => message.content)).toEqual(turns.map(turn => turn.text));
  // Events are delivered in the background; none comes for this conversation.
  await new Promise(resolve => setTimeout(resolve, 8_000));
  expect(await standIn.deliveries(answer.conversation_id)).toEqual([]);
  expect((await standIn.log()).filter(entry => entry.kind === 'delivery' && entry.event === 'message_created' && /quiet call/.test(entry.content || ''))).toEqual([]);
});

test('No notification for each turn', async ({ page }) => {
  // Chatwoot assigns the oldest open conversations first and at most five to
  // an agent in five minutes: the calls of the tests before this one are
  // closed, so this call is the one the Phone inbox has to assign.
  for (;;) {
    const open = (await admin.get(`/conversations?inbox_id=${phoneInboxId}&status=open&assignee_type=all`)).body.data.payload;
    if (!open.length) break;
    for (const entry of open) await admin.post(`/conversations/${entry.id}/toggle_status`, { status: 'resolved' });
  }
  // The Phone inbox assigns by itself to the agents of the inbox who are online.
  await admin.post('/inbox_members', { inbox_id: phoneInboxId, user_ids: [agent.userId] });
  await admin.patch(`/inboxes/${phoneInboxId}`, { enable_auto_assignment: true });
  await signIn(page, users.agent);
  await page.goto(`/app/accounts/${account}/dashboard`);
  await eventually(
    async () => (await admin.get('/agents')).body.find(entry => entry.id === agent.userId)?.availability_status,
    status => status === 'online',
    { timeout: 45_000 }
  );
  const turns = Array.from({ length: 40 }, (_, index) => ({ role: index % 2 ? 'caller' : 'agent', text: `Turn ${index + 1} of a long call` }));

  const answer = await filed('team-request', 'forty', { turns });

  const assigned = await eventually(() => conversation(answer.conversation_id), record => record.meta.assignee?.id === agent.userId, { timeout: 45_000 });
  expect(assigned.status).toBe('open');
  const about = notifications => notifications.filter(entry => entry.primary_actor?.id === answer.conversation_id || entry.primary_actor_id === answer.conversation_id);
  const mine = await eventually(
    async () => about((await agent.get('/notifications')).body.data.payload),
    list => list.some(entry => entry.notification_type === 'conversation_assignment'),
    { timeout: 45_000 }
  );
  await new Promise(resolve => setTimeout(resolve, 5_000));
  const later = about((await agent.get('/notifications')).body.data.payload);
  expect(mine.some(entry => entry.notification_type === 'conversation_assignment')).toBe(true);
  expect(later.filter(entry => /new_message/.test(entry.notification_type))).toEqual([]);
  expect(later.filter(entry => entry.secondary_actor?.message_type !== undefined && !entry.secondary_actor?.private)).toEqual([]);
});

// --- No payment card number is stored ---------------------------------------------

test('A card number in a turn', async () => {
  const answer = await filed('team-request', 'card-number', { turns: [{ role: 'caller', text: 'my card is 4111 1111 1111 1111' }] });

  expect((await turnsOf(answer.conversation_id)).map(message => message.content)).toEqual(['my card is [card number removed]']);
});

test('An order number stays', async () => {
  const answer = await filed('team-request', 'order-number', { turns: [{ role: 'caller', text: 'order 1001234567890' }] });

  expect((await turnsOf(answer.conversation_id)).map(message => message.content)).toEqual(['order 1001234567890']);
});

// --- A filing too large is refused whole ---------------------------------------------

test('A very long call', async () => {
  const turns = Array.from({ length: 600 }, (_, index) => ({ role: index % 2 ? 'caller' : 'agent', text: `Turn ${index + 1}` }));

  await refused(() => file('team-request', 'too-long', { turns }), 422, 'too_large');
});

// --- The answer of a filing tells the AI service what was done -------------------------

test('The answer of a new call', async () => {
  const phone = number();
  const known = await admin.conversation(await admin.inbox(), { name: 'Answer Example', phone, message: 'Hello' });

  const answer = await file('resolved-inbound', 'answer', { caller: { phone } });

  expect(answer.status).toBe(201);
  expect(answer.body).toMatchObject({ contact_id: known.contactId, found: false, matched_by: 'phone', labels_added: [] });
  expect((await conversation(answer.body.conversation_id)).id).toBe(answer.body.conversation_id);
  expect((await notesOf(answer.body.conversation_id))).toHaveLength(1);
});

test('A filing without a call id', async () => {
  await refused(() => standIn.call({ ...callFixture('resolved-inbound'), call_id: undefined }), 422, 'invalid_call');
});

// --- Last: the disconnection removes the bot the other tests file with ------------------

test('The AI agent was disconnected', async () => {
  const before = await phoneCalls();
  expect((await admin.delete('/inclamo/ai/connection')).status).toBeLessThan(300);

  const answer = await file('resolved-inbound', 'after-disconnect');

  expect(answer.status).toBe(401);
  expect(await phoneCalls()).toBe(before);
  // Connected again for the files that run after this one.
  await ensureConnected();
});
