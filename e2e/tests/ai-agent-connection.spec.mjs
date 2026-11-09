// Scenarios of openspec capability `ai-agent-connection`. Each test is named
// after its scenario; scripts/check-e2e-coverage.mjs relies on that.
//
// The shopper writes in the widget, the team works in the dashboard, and the
// AI service is the stand-in agent of e2e/stand-in-agent (fixed rules on the
// shopper's text: "person", "urgent", "resolve", "intent", files, anything
// else). The tests check what the helpdesk shows and stores, never the
// agent's words, so the same file runs against the AI service given a code it
// issued (E2E_AI_CODE; docs/ai-connector.md §8). What only the stand-in can
// show (what it received, its 503s, reading with its token) is then skipped.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users, eventually, runTag } from '../lib/helpdesk.mjs';
import {
  standIn,
  aiService,
  againstAiService,
  websiteInbox,
  emailInboxWithBot,
  conversationWith,
  messagesOf,
  fromAgent,
  shopperOn,
  photos,
  keepPayloads,
} from '../lib/agent.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const settingsPath = `/app/accounts/${account}/settings/ai-agent`;
const tag = suffix => runTag(`-ai-${suffix}`);
const onlyWithStandIn = () => test.skip(againstAiService, 'shows what only the stand-in agent can show');
const ACTIVITY = 2;
const OUTGOING = 1;
const INCOMING = 0;

let admin;
let agent;
let website;
let otherInbox;
const shoppers = [];

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  website = await websiteInbox(admin, [admin.userId, agent.userId]);
  otherInbox = await admin.inbox([admin.userId, agent.userId]);
});

test.beforeEach(async () => {
  if (!againstAiService) await standIn.failWith(null);
});

test.afterAll(async () => {
  await Promise.all(shoppers.map(shopper => shopper.close().catch(() => {})));
  if (!againstAiService) await standIn.failWith(null);
});

// --- helpers of this file ---------------------------------------------------

const aiConnection = async () => (await admin.get('/inclamo/ai/connection')).body;
const conversation = async id => (await admin.get(`/conversations/${id}`)).body;
const labelsOf = async id => (await admin.get(`/conversations/${id}/labels`)).body.payload || [];
const accountLabels = async () => (await admin.get('/labels')).body.payload || [];
const bots = async () => (await admin.get('/agent_bots')).body || [];
const statusOf = async id => (await conversation(id)).status;

const openPage = async page => {
  await signIn(page, users.admin);
  await page.goto(settingsPath);
  const view = page.getByTestId('inclamo-ai-page');
  await view.waitFor({ timeout: 45_000 });
  return view;
};

const fillAndConnect = async (view, code, inboxIds) => {
  await view.getByTestId('inclamo-ai-code').fill(code);
  for (const id of inboxIds) await view.getByTestId(`inclamo-ai-inbox-${id}`).locator('input').check();
  await view.getByTestId('inclamo-ai-connect').click();
};

// Connected for the tests that need it, also when one is run alone.
async function ensureConnected() {
  if ((await aiConnection()).connected) return;
  const code = againstAiService ? aiService.code : await standIn.code();
  const answer = await admin.post('/inclamo/ai/connection', { connection_code: code, inbox_ids: [website.id] });
  if (answer.status !== 201) throw new Error(`could not connect the AI agent: HTTP ${answer.status} ${answer.body?.error}`);
}

// A shopper in the widget who has started a conversation with `text`.
async function shopperStarts(browser, text) {
  const shopper = await shopperOn(browser, website);
  shoppers.push(shopper);
  await shopper.write(text);
  const found = await conversationWith(admin, text);
  return { shopper, id: found.id, contactId: (await conversation(found.id)).meta.sender.id };
}

// The agent's public replies in the conversation, as the team's API gives them.
const agentReplies = async id => (await messagesOf(admin, id)).filter(m => fromAgent(m) && !m.private && m.message_type === OUTGOING);

const waitForReplies = (id, count = 1) => eventually(() => agentReplies(id), list => list.length >= count, { timeout: 45_000 });

const openConversation = async (page, user, id) => {
  await signIn(page, user);
  await page.goto(`/app/accounts/${account}/conversations/${id}`);
};

// The conversation's labels as the dashboard shows them: in the contact
// sidebar, section "Conversation Actions", opened the way a person would.
async function expectSidebarLabels(page, titles) {
  const appeared = (locator, timeout) => locator.waitFor({ state: 'visible', timeout }).then(() => true, () => false);
  await page.locator('[data-message-id]').first().waitFor({ timeout: 45_000 });
  const section = page.getByText('Conversation Actions', { exact: true }).first();
  // The contact sidebar may be closed: the round button at the top right opens it.
  if (!(await appeared(section, 5_000))) await page.locator('button[class*="!rounded-full"]').first().click();
  await section.waitFor({ timeout: 30_000 });
  const label = title => page.getByText(title, { exact: true }).first();
  if (!(await appeared(label(titles[0]), 5_000))) await section.click();
  for (const title of titles) await expect(label(title)).toBeVisible({ timeout: 30_000 });
}

// The conversation list of a team member, filtered by status the way the
// dashboard's own status filter keeps it (Chatwoot's UI settings).
async function listWithStatus(page, api, status) {
  await api.put('api/v1/profile', { profile: { ui_settings: { conversations_filter_by: { status, order_by: 'last_activity_at_desc' } } } });
  await page.goto(`/app/accounts/${account}/inbox/${website.id}`);
  // The agent's conversations have the bot as assignee: they are under "All".
  const all = page.locator('main li').filter({ hasText: /^\s*All\s*\d*\s*$/ }).first();
  await all.click({ timeout: 45_000 });
}

// --- The AI agent page is the door to the agent ------------------------------

test('Administrator opens the page without a connection', async ({ page }) => {
  expect((await aiConnection()).state).toBe('never_connected');

  const view = await openPage(page);

  await expect(view).toHaveAttribute('data-state', 'never_connected');
  await expect(view.getByTestId('inclamo-ai-about')).toBeVisible();
  await expect(view.getByTestId('inclamo-ai-get')).toHaveAttribute('href', /^https:\/\//);
  await expect(view.getByTestId('inclamo-ai-code')).toBeVisible();
  await expect(view.getByTestId(`inclamo-ai-inbox-${website.id}`)).toBeVisible();
  await expect(view.getByTestId(`inclamo-ai-inbox-${otherInbox.id}`)).toBeVisible();
  await expect(page.locator('a[href$="/settings/ai-agent"]').first()).toBeVisible();
  expect(await bots()).toEqual([]);
});

test('Agents do not see the page', async ({ page }) => {
  await signIn(page, users.agent);
  await page.goto(`/app/accounts/${account}/settings/canned-response/list`);
  await expect(page.locator('a[href$="/settings/canned-response/list"]').first()).toBeVisible({ timeout: 45_000 });
  await expect(page.locator('a[href$="/settings/ai-agent"]')).toHaveCount(0);

  await page.goto(settingsPath);
  await expect(page).not.toHaveURL(/\/settings\/ai-agent/, { timeout: 30_000 });
  await expect(page.getByTestId('inclamo-ai-page')).toHaveCount(0);
  const answer = await agent.get('/inclamo/ai/connection');
  expect(answer.status).toBe(403);
  expect(answer.body.error).toBe('forbidden');
});

// --- An administrator connects the account with a code -----------------------

test('A code that does not read', async ({ page }) => {
  if (!againstAiService) await standIn.clear();
  const view = await openPage(page);

  await fillAndConnect(view, 'this is not a connection code', [website.id]);

  await expect(view.getByTestId('inclamo-ai-error')).toContainText('not a valid connection code');
  await expect(view).toHaveAttribute('data-state', 'never_connected');
  if (!againstAiService) expect((await standIn.log()).filter(entry => entry.kind === 'registration')).toEqual([]);
});

test('The AI service refuses the code', async ({ page }) => {
  const refusal = { status: 410, error: 'expired', message: 'This connection code has expired.' };
  const code = againstAiService ? aiService.refusedCode : await standIn.code(refusal);
  test.skip(!code, 'E2E_AI_REFUSED_CODE is not set');
  const before = { bots: await bots(), inboxes: (await admin.get('/inboxes')).body.payload.map(i => i.id), labels: (await accountLabels()).map(l => l.title) };
  const view = await openPage(page);

  await fillAndConnect(view, code, [website.id]);

  const error = view.getByTestId('inclamo-ai-error');
  if (againstAiService) await expect(error).not.toBeEmpty();
  else await expect(error).toHaveText(refusal.message);
  await expect(view).toHaveAttribute('data-state', 'never_connected');
  expect(await bots()).toEqual(before.bots);
  const inboxes = (await admin.get('/inboxes')).body.payload;
  expect(inboxes.map(i => i.id)).toEqual(before.inboxes);
  expect(inboxes.some(i => i.name === 'Phone')).toBe(false);
  expect((await accountLabels()).map(l => l.title)).toEqual(before.labels);
});

test('An inbox with another bot cannot be picked', async ({ page }) => {
  const { inbox: email } = await emailInboxWithBot(admin);
  const view = await openPage(page);

  const item = view.getByTestId(`inclamo-ai-inbox-${email.id}`);
  await expect(item).toHaveAttribute('data-selectable', 'false');
  await expect(item.getByTestId('inclamo-ai-other-bot')).toBeVisible();
  await expect(item.locator('input')).toBeDisabled();
  await expect(view.getByTestId(`inclamo-ai-inbox-${website.id}`)).toHaveAttribute('data-selectable', 'true');
});

test('Administrator connects a website inbox', async ({ page }) => {
  const code = againstAiService ? aiService.code : await standIn.code();
  const view = await openPage(page);

  await fillAndConnect(view, code, [website.id]);

  await expect(view).toHaveAttribute('data-state', 'connected');
  await expect(view.getByTestId('inclamo-ai-state')).toHaveAttribute('data-state', 'connected');
  await expect(view.getByTestId(`inclamo-ai-connected-${website.id}`)).toBeVisible();
  const saved = await aiConnection();
  expect(saved.connection.inbox_ids).toEqual([website.id]);
  const phone = (await admin.get('/inboxes')).body.payload.find(inbox => inbox.id === saved.connection.phone_inbox_id);
  expect(phone).toMatchObject({ name: 'Phone', channel_type: 'Channel::Api' });
  const labels = Object.fromEntries((await accountLabels()).map(label => [label.title, label]));
  expect(labels.inclamo_handover?.description).toBeTruthy();
  expect(labels.inclamo_urgent?.description).toBeTruthy();
  if (!againstAiService) {
    const registration = (await standIn.log()).filter(entry => entry.kind === 'registration').at(-1);
    expect(registration).toMatchObject({ inbox_ids: [website.id], phone_inbox_id: phone.id });
  }
});

// --- The agent answers first in a connected inbox ----------------------------

test('Shopper writes in the widget', async ({ browser, page }) => {
  await ensureConnected();
  const text = `Hello ${tag('hello')}`;

  const { shopper, id } = await shopperStarts(browser, text);

  if (!againstAiService) {
    const [delivery] = await eventually(() => standIn.deliveries(id, entry => entry.event === 'message_created' && entry.content === text), list => list.length > 0);
    expect(delivery).toMatchObject({ verified: true, outcome: 'accepted', message_type: 'incoming', private: false });
  }
  const [reply] = await waitForReplies(id);
  await expect(shopper.agentBubble(reply.content).first()).toBeVisible({ timeout: 30_000 });
  await openConversation(page, users.admin, id);
  await expect(page.locator(`#message${reply.id}`)).toBeVisible({ timeout: 45_000 });
  expect(await statusOf(id)).toBe('pending');
});

test("The team sees the agent's conversations under Pending", async ({ browser, page }) => {
  await ensureConnected();
  const text = `Hello ${tag('list')}`;
  const { id, contactId } = await shopperStarts(browser, text);
  const name = `Shopper ${tag('list')}`;
  expect((await admin.put(`/contacts/${contactId}`, { name })).status).toBe(200);
  await waitForReplies(id);
  expect(await statusOf(id)).toBe('pending');
  await signIn(page, users.agent);

  await listWithStatus(page, agent, 'pending');
  await expect(page.locator('.conversation', { hasText: name })).toBeVisible({ timeout: 45_000 });

  await listWithStatus(page, agent, 'open');
  await expect(page.locator('.conversation').first().or(page.getByText(/no .*conversations/i).first())).toBeVisible({ timeout: 45_000 });
  await expect(page.locator('.conversation', { hasText: name })).toHaveCount(0);
});

// --- The shopper's files reach the agent ---------------------------------------

test('One photo', async ({ browser, page }) => {
  await ensureConnected();
  const { shopper, id } = await shopperStarts(browser, `Hello ${tag('photo')}`);

  await shopper.send(photos.front);

  if (!againstAiService) {
    const [delivery] = await eventually(() => standIn.deliveries(id, entry => entry.event === 'message_created' && entry.attachments.length > 0), list => list.length > 0);
    expect(delivery.attachments).toEqual([expect.objectContaining({ file_type: 'image', content_type: 'image/png', has_url: true })]);
    expect(delivery.attachments[0].file_size).toBeGreaterThan(0);
  }
  const photo = await eventually(async () => (await messagesOf(admin, id)).find(m => m.message_type === INCOMING && (m.attachments || []).length), Boolean);
  await openConversation(page, users.admin, id);
  await expect(page.locator(`#message${photo.id} img`).first()).toBeVisible({ timeout: 45_000 });
  await keepPayloads('widget-message-with-one-image', id);
});

test('Two photos', async ({ browser }) => {
  await ensureConnected();
  const { shopper, id } = await shopperStarts(browser, `Hello ${tag('photos')}`);

  await shopper.send(photos.front);
  await shopper.send(photos.side);

  const withFiles = await eventually(async () => (await messagesOf(admin, id)).filter(m => m.message_type === INCOMING && (m.attachments || []).length), list => list.length >= 2);
  expect(withFiles.map(m => m.attachments.length)).toEqual([1, 1]);
  if (!againstAiService) {
    const deliveries = await eventually(() => standIn.deliveries(id, entry => entry.event === 'message_created' && entry.attachments.length > 0), list => list.length >= 2);
    expect(deliveries.map(entry => entry.attachments.map(file => file.file_type))).toEqual([['image'], ['image']]);
    const history = await standIn.read(id);
    expect(history.status).toBe(200);
    expect(history.body.shopper_files).toBe(2);
  }
});

test('Photo without text', async ({ browser, page }) => {
  await ensureConnected();
  const { shopper, id } = await shopperStarts(browser, `Hello ${tag('bare-photo')}`);
  await waitForReplies(id);

  await shopper.send(photos.side);

  if (!againstAiService) {
    const [delivery] = await eventually(() => standIn.deliveries(id, entry => entry.event === 'message_created' && entry.attachments.length > 0), list => list.length > 0);
    expect(delivery.content ?? '').toBe('');
    expect(delivery.attachments.map(file => file.file_type)).toEqual(['image']);
    const [named] = await eventually(async () => (await standIn.log()).filter(entry => entry.kind === 'files_named' && entry.conversation_id === id), list => list.length > 0);
    expect(named).toMatchObject({ in_message: 1, in_conversation: 1 });
  }
  const replies = await waitForReplies(id, 2);
  await expect(shopper.agentBubble(replies[1].content).first()).toBeVisible({ timeout: 30_000 });
  await openConversation(page, users.admin, id);
  await expect(page.locator(`#message${replies[1].id}`)).toBeVisible({ timeout: 45_000 });
  expect(await statusOf(id)).toBe('pending');
});

// --- The agent reads only connected conversations, without private notes ------

test('Agent reads a conversation with a private note', async ({ browser }) => {
  onlyWithStandIn();
  await ensureConnected();
  const text = `Hello ${tag('note')}`;
  const { id } = await shopperStarts(browser, text);
  const [reply] = await waitForReplies(id);
  const note = `Team only ${tag('note')}`;
  await admin.post(`/conversations/${id}/messages`, { content: note, private: true });

  const history = await standIn.read(id);

  expect(history.status).toBe(200);
  expect(history.body.messages.map(m => [m.role, m.text])).toEqual([
    ['shopper', text],
    ['agent', reply.content],
  ]);
  expect(JSON.stringify(history.body)).not.toContain(note);
});

test('Agent asks for a conversation of another inbox', async () => {
  onlyWithStandIn();
  await ensureConnected();
  const other = await admin.conversation(otherInbox, { name: 'Not for the agent', email: `${tag('other')}@example.test`, message: `Not for the agent ${tag('other')}` });

  const answer = await standIn.read(other.id);

  expect(answer.status).toBe(403);
  expect(answer.body.messages).toBeUndefined();
  expect(JSON.stringify(answer.body)).not.toContain('Not for the agent');
});

// --- The agent's labels are shown and keep the team's -------------------------

test('Agent adds a label for a request type', async ({ browser, page }) => {
  await ensureConnected();
  if (!(await accountLabels()).some(label => label.title === 'vip')) await admin.post('/labels', { title: 'vip', description: 'Team label' });
  const { shopper, id } = await shopperStarts(browser, `Hello ${tag('label')}`);
  await waitForReplies(id);
  await admin.post(`/conversations/${id}/labels`, { labels: ['vip'] });

  await shopper.write(`What intent is this ${tag('label')}`);

  await eventually(() => labelsOf(id), list => list.includes('inclamo_intent_test'), { timeout: 45_000 });
  expect((await labelsOf(id)).sort()).toEqual(['inclamo_intent_test', 'vip']);
  expect((await accountLabels()).map(label => label.title)).toContain('inclamo_intent_test');
  await openConversation(page, users.admin, id);
  await expectSidebarLabels(page, ['vip', 'inclamo_intent_test']);
});

// --- The conversation goes to the team when the agent hands over or a person steps in

test('Agent hands over with a note', async ({ browser, page }) => {
  await ensureConnected();
  const { id } = await shopperStarts(browser, `I want to talk to a person ${tag('handover')}`);

  await eventually(() => statusOf(id), status => status === 'open', { timeout: 45_000 });

  expect(await labelsOf(id)).toContain('inclamo_handover');
  const note = (await messagesOf(admin, id)).find(m => fromAgent(m) && m.private);
  expect(note).toBeTruthy();
  await openConversation(page, users.admin, id);
  await expect(page.locator(`#message${note.id}`)).toBeVisible({ timeout: 45_000 });
  await expectSidebarLabels(page, ['inclamo_handover']);
  await keepPayloads('events-after-bot-handoff', id);
});

test('Urgent request', async ({ browser, page }) => {
  await ensureConnected();
  const { id } = await shopperStarts(browser, `This is urgent ${tag('urgent')}`);

  await eventually(() => statusOf(id), status => status === 'open', { timeout: 45_000 });

  const stored = await conversation(id);
  expect(stored.priority).toBe('urgent');
  expect(await labelsOf(id)).toContain('inclamo_urgent');
  await openConversation(page, users.admin, id);
  await expectSidebarLabels(page, ['inclamo_urgent']);
});

// The dashboard of Chatwoot 4.19 keeps the reply box of a conversation the
// agent handles to private notes, with "Take over", which assigns the team
// member. So a public reply comes from the dashboard after "Take over", or from
// any other client of the API without it; both open the conversation.
test('Team member replies in a pending conversation', async ({ browser, page }) => {
  await ensureConnected();
  const byApi = await shopperStarts(browser, `Hello ${tag('reply-api')}`);
  const inDashboard = await shopperStarts(browser, `Hello ${tag('reply-ui')}`);
  await waitForReplies(byApi.id);
  await waitForReplies(inDashboard.id);
  expect(await statusOf(byApi.id)).toBe('pending');
  expect(await statusOf(inDashboard.id)).toBe('pending');

  await agent.post(`/conversations/${byApi.id}/messages`, { content: `A person here ${tag('reply-api')}` });
  await openConversation(page, users.agent, inDashboard.id);
  await page.getByRole('button', { name: 'Take over' }).click({ timeout: 45_000 });
  // Take over switches from the note editor to the public reply editor.
  // Wait for that transition before typing so the note draft is not replaced.
  const replyBox = page.locator('.reply-box');
  await expect(replyBox).not.toHaveClass(/is-private/);
  const editor = replyBox.locator('.ProseMirror').first();
  await expect(editor).toBeEditable();
  await editor.fill(`A person here ${tag('reply-ui')}`);
  await expect(editor).toContainText(`A person here ${tag('reply-ui')}`);
  await replyBox.getByRole('button', { name: /^Send/ }).click();

  for (const id of [byApi.id, inDashboard.id]) {
    await eventually(() => statusOf(id), status => status === 'open', { timeout: 45_000 });
    if (!againstAiService) {
      const changes = await eventually(() => standIn.deliveries(id, entry => entry.event === 'conversation_status_changed' && entry.conversation_status === 'open'), list => list.length > 0);
      expect(changes[0].verified).toBe(true);
    }
  }
  await eventually(async () => (await messagesOf(admin, inDashboard.id)).some(m => m.content === `A person here ${tag('reply-ui')}` && !m.private), Boolean);
});

test('Team member leaves a private note', async ({ browser }) => {
  await ensureConnected();
  const { id } = await shopperStarts(browser, `Hello ${tag('private')}`);
  await waitForReplies(id);
  const note = `Only for the team ${tag('private')}`;

  await agent.post(`/conversations/${id}/messages`, { content: note, private: true });

  if (!againstAiService) {
    const [delivered] = await eventually(() => standIn.deliveries(id, entry => entry.content === note), list => list.length > 0);
    expect(delivered).toMatchObject({ private: true, sender_type: 'user', verified: true });
  }
  // The handover listener runs in a job: give it the time a reply takes.
  await new Promise(resolve => setTimeout(resolve, 8_000));
  expect(await statusOf(id)).toBe('pending');
});

test('Shopper writes again after the agent resolved', async ({ browser }) => {
  await ensureConnected();
  const { shopper, id } = await shopperStarts(browser, `Please resolve this ${tag('again')}`);
  await eventually(() => statusOf(id), status => status === 'resolved', { timeout: 45_000 });
  const again = `One more question ${tag('again')}`;

  await shopper.write(again);

  await eventually(() => statusOf(id), status => status === 'pending', { timeout: 45_000 });
  if (!againstAiService) {
    const [delivered] = await eventually(() => standIn.deliveries(id, entry => entry.event === 'message_created' && entry.content === again), list => list.length > 0);
    expect(delivered.verified).toBe(true);
  }
});

// --- The team gets the conversation when the AI service cannot take it --------

test('The AI service is down', async ({ browser, page }) => {
  onlyWithStandIn();
  await ensureConnected();
  await standIn.failWith(503);

  const { id } = await shopperStarts(browser, `Hello ${tag('down')}`);

  await eventually(() => statusOf(id), status => status === 'open', { timeout: 60_000 });
  const activity = await eventually(async () => (await messagesOf(admin, id)).find(m => m.message_type === ACTIVITY), Boolean, { timeout: 30_000 });
  await openConversation(page, users.admin, id);
  await expect(page.locator(`#message${activity.id}`)).toBeVisible({ timeout: 45_000 });
  const view = await openPage(page);
  await expect(view.getByTestId('inclamo-ai-state')).toHaveAttribute('data-state', 'failing');
  await expect(view.getByTestId('inclamo-ai-last-error')).toHaveAttribute('data-kind', 'http_503');
  await expect(view.getByTestId('inclamo-ai-last-error')).toContainText(/\d/);
  expect(JSON.stringify(await aiConnection())).not.toContain(tag('down'));
  await keepPayloads('pending-opened-after-503', id);
});

test('The AI service is back', async ({ browser, page }) => {
  onlyWithStandIn();
  await ensureConnected();
  await standIn.failWith(null);

  const { id } = await shopperStarts(browser, `Hello ${tag('back')}`);

  await waitForReplies(id);
  await eventually(aiConnection, saved => saved.connection?.state === 'connected');
  const view = await openPage(page);
  await expect(view.getByTestId('inclamo-ai-state')).toHaveAttribute('data-state', 'connected');
});

// --- An administrator disconnects the account ---------------------------------

let handled;

test('Administrator disconnects', async ({ browser, page }) => {
  await ensureConnected();
  handled = await shopperStarts(browser, `Hello ${tag('handled')}`);
  await waitForReplies(handled.id);
  expect(await statusOf(handled.id)).toBe('pending');
  const view = await openPage(page);

  await view.getByTestId('inclamo-ai-disconnect').click();
  const dialog = page.getByRole('dialog').filter({ has: page.getByTestId('inclamo-ai-confirm') });
  await expect(dialog.getByTestId('inclamo-ai-confirm')).toBeVisible();
  await dialog.getByRole('button', { name: 'Disconnect' }).click();

  await expect(view).toHaveAttribute('data-state', 'disconnected', { timeout: 30_000 });
  expect(await statusOf(handled.id)).toBe('open');
  if (!againstAiService) await standIn.clear();
  const fresh = await shopperStarts(browser, `Hello ${tag('after')}`);
  expect(await statusOf(fresh.id)).toBe('open');
  await new Promise(resolve => setTimeout(resolve, 8_000));
  expect(await agentReplies(fresh.id)).toEqual([]);
  if (!againstAiService) {
    expect(await standIn.deliveries(fresh.id)).toEqual([]);
    expect((await standIn.reply(handled.id)).status).toBe(401);
    expect((await standIn.connection()).removed).toBe(true);
  }
});

test("Agent's credentials after disconnecting", async () => {
  onlyWithStandIn();
  expect(handled).toBeTruthy();
  const before = (await messagesOf(admin, handled.id)).length;

  const attempt = await standIn.reply(handled.id);

  expect(attempt.status).toBe(401);
  expect((await messagesOf(admin, handled.id)).length).toBe(before);
});
