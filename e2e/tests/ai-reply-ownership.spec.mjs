// Scenarios of behavior contract `ai-reply-ownership`. Each test is named
// after its scenario; scripts/check-e2e-coverage.mjs relies on that. "Take-over
// and reply at the same moment" needs two database transactions at the same
// instant and is covered by a backend spec instead (see that script).
//
// The AI service is the stand-in agent of e2e/stand-in-agent: it replies
// through the protected reply (docs/ai-connector.md §5.4), ends its turn when
// that is refused, and on "slow" waits before its reply, the time a person
// needs to take the conversation. What only the stand-in can show (its log,
// replies with its token) is skipped against a real AI service.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users, eventually, runTag } from '../lib/helpdesk.mjs';
import { standIn, aiService, againstAiService, websiteInbox, conversationWith, messagesOf, fromAgent, shopperOn } from '../lib/agent.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const tag = suffix => runTag(`-own-${suffix}`);
const onlyWithStandIn = () => test.skip(againstAiService, 'shows what only the stand-in agent can show');
const OUTGOING = 1;
const SLOW_MS = 20_000;
const SLOW_ANSWER = 'A slow answer';

let admin;
let agent;
let website;
const shoppers = [];

test.describe.configure({ mode: 'serial' });

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  website = await websiteInbox(admin, [admin.userId, agent.userId]);
  if (!againstAiService) {
    await standIn.failWith(null);
    await standIn.slow(SLOW_MS);
  }
  await ensureConnected();
});

test.afterAll(async () => {
  await Promise.all(shoppers.map(shopper => shopper.close().catch(() => {})));
  if (!againstAiService) await standIn.slow(null);
});

// --- helpers of this file ---------------------------------------------------

async function ensureConnected() {
  if ((await admin.get('/inclamo/ai/connection')).body.connected) return;
  const code = againstAiService ? aiService.code : await standIn.code();
  const answer = await admin.post('/inclamo/ai/connection', { connection_code: code, inbox_ids: [website.id] });
  if (answer.status !== 201) throw new Error(`could not connect the AI agent: HTTP ${answer.status} ${answer.body?.error}`);
}

const statusOf = async id => (await admin.get(`/conversations/${id}`)).body.status;
const agentReplies = async id => (await messagesOf(admin, id)).filter(m => fromAgent(m) && !m.private && m.message_type === OUTGOING);
const waitForReplies = id => eventually(() => agentReplies(id), list => list.length > 0, { timeout: 45_000 });
const actionsOf = async id => (await standIn.log()).filter(entry => entry.kind === 'action' && entry.conversation_id === id);
const turnEnded = id =>
  eventually(async () => (await standIn.log()).filter(entry => entry.kind === 'turn_ended' && entry.conversation_id === id), list => list.length > 0, {
    timeout: SLOW_MS + 30_000,
  });

async function shopperStarts(browser, text) {
  const shopper = await shopperOn(browser, website);
  shoppers.push(shopper);
  await shopper.write(text);
  const found = await conversationWith(admin, text);
  return { shopper, id: found.id };
}

// --- The agent's protected reply is posted only while the conversation is the agent's

test('Agent replies in a Pending conversation', async ({ browser, page }) => {
  const { shopper, id } = await shopperStarts(browser, `Hello ${tag('pending')}`);

  const [reply] = await waitForReplies(id);

  await expect(shopper.agentBubble(reply.content).first()).toBeVisible({ timeout: 30_000 });
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/conversations/${id}`);
  await expect(page.locator(`#message${reply.id}`)).toBeVisible({ timeout: 45_000 });
  expect(await statusOf(id)).toBe('pending');
  if (!againstAiService) expect((await actionsOf(id)).filter(entry => entry.action === 'reply').map(entry => entry.status)).toEqual([201]);
});

test('A person took the conversation before the reply', async ({ browser, page }) => {
  onlyWithStandIn();
  await signIn(page, users.agent);
  const { shopper, id } = await shopperStarts(browser, `A slow question ${tag('taken')}`);

  await page.goto(`/app/accounts/${account}/conversations/${id}`);
  await page.getByRole('button', { name: 'Take over' }).click({ timeout: 45_000 });
  await eventually(() => statusOf(id), status => status === 'open', { timeout: 15_000 });

  const [ended] = await turnEnded(id);
  expect(ended).toMatchObject({ reason: 'conversation_not_pending', status: 'open' });
  expect((await actionsOf(id)).filter(entry => entry.action === 'reply').map(entry => entry.status)).toEqual([409]);
  expect(await agentReplies(id)).toEqual([]);
  await expect(shopper.agentBubble(SLOW_ANSWER)).toHaveCount(0);
  const conversation = (await admin.get(`/conversations/${id}`)).body;
  expect(conversation.meta.assignee?.id).toBe(agent.userId);
});

test('A person replied before the agent', async ({ browser }) => {
  onlyWithStandIn();
  const { shopper, id } = await shopperStarts(browser, `A slow question ${tag('replied')}`);
  const words = `A person here ${tag('replied')}`;

  await agent.post(`/conversations/${id}/messages`, { content: words });

  const [ended] = await turnEnded(id);
  expect(ended.reason).toBe('conversation_not_pending');
  expect(await agentReplies(id)).toEqual([]);
  await expect(shopper.agentBubble(words).first()).toBeVisible({ timeout: 30_000 });
  await expect(shopper.agentBubble(SLOW_ANSWER)).toHaveCount(0);
});

test('Empty reply', async ({ browser }) => {
  onlyWithStandIn();
  const { id } = await shopperStarts(browser, `Hello ${tag('empty')}`);
  await waitForReplies(id);
  const before = (await messagesOf(admin, id)).length;

  const answer = await standIn.reply(id, { protected: true, content: '   ' });

  expect(answer.status).toBe(422);
  expect(answer.body.error).toBe('empty_reply');
  expect((await messagesOf(admin, id)).length).toBe(before);
});

// --- A person's take-over is effective at once ----------------------------------

test('Status right after the take-over', async ({ browser }) => {
  const assigned = await shopperStarts(browser, `Hello ${tag('assign')}`);
  const replied = await shopperStarts(browser, `Hello ${tag('reply')}`);
  await waitForReplies(assigned.id);
  await waitForReplies(replied.id);

  expect((await agent.post(`/conversations/${assigned.id}/assignments`, { assignee_id: agent.userId })).status).toBe(200);
  expect(await statusOf(assigned.id)).toBe('open');
  expect((await agent.post(`/conversations/${replied.id}/messages`, { content: `A person here ${tag('reply')}` })).status).toBe(200);
  expect(await statusOf(replied.id)).toBe('open');

  if (!againstAiService) {
    for (const id of [assigned.id, replied.id]) {
      const changes = await eventually(
        () => standIn.deliveries(id, entry => entry.event === 'conversation_status_changed' && entry.conversation_status === 'open'),
        list => list.length > 0
      );
      expect(changes[0].verified).toBe(true);
    }
  }
});

test('Private note', async ({ browser }) => {
  const { id } = await shopperStarts(browser, `Hello ${tag('note')}`);
  await waitForReplies(id);

  await agent.post(`/conversations/${id}/messages`, { content: `Only for the team ${tag('note')}`, private: true });

  expect(await statusOf(id)).toBe('pending');
  if (!againstAiService) {
    const answer = await standIn.reply(id, { protected: true, content: `After the note ${tag('note')}` });
    expect(answer.status).toBe(201);
    expect(await statusOf(id)).toBe('pending');
  }
});

// --- The contract states the protected reply and its refusal --------------------

test('An AI service written against the document', async ({ browser }) => {
  onlyWithStandIn();
  const { id } = await shopperStarts(browser, `A slow question ${tag('document')}`);

  await agent.post(`/conversations/${id}/assignments`, { assignee_id: agent.userId });
  await turnEnded(id);
  // Give a retry or a hand-over the time it would take.
  await new Promise(resolve => setTimeout(resolve, 5_000));

  expect((await actionsOf(id)).map(entry => [entry.action, entry.status])).toEqual([['reply', 409]]);
  expect(await statusOf(id)).toBe('open');
});

// Last: it disconnects the account. Other files connect again when they need it.
test('Another token', async ({ browser }) => {
  const { id } = await shopperStarts(browser, `Hello ${tag('token')}`);
  await waitForReplies(id);
  const before = (await messagesOf(admin, id)).length;

  const byPerson = await admin.post(`/inclamo/ai/conversations/${id}/reply`, { content: 'From a person' });
  expect(byPerson.status).toBe(401);

  if (!againstAiService) {
    expect((await admin.delete('/inclamo/ai/connection')).status).toBeLessThan(300);
    const afterDisconnect = await standIn.reply(id, { protected: true, content: 'After the disconnection' });
    expect(afterDisconnect.status).toBe(401);
  }
  expect((await messagesOf(admin, id)).length).toBe(before);
});
