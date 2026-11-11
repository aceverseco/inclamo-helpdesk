// The AI agent's side of the end-to-end tests: the stand-in for the AI service
// (e2e/stand-in-agent/server.mjs), the shopper in the widget, and the inboxes
// the tests use. With E2E_AI_CODE set the tests connect with a code the AI
// service issued instead, and skip what only the stand-in can show
// (docs/ai-connector.md §8).
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const photos = {
  front: join(here, '..', 'fixtures', 'photos', 'box-front.png'),
  side: join(here, '..', 'fixtures', 'photos', 'box-side.png'),
};
export const photoBytes = name => readFileSync(photos[name]);

// Codes from the AI service: one that connects, and optionally one it refuses.
export const aiService = {
  code: process.env.E2E_AI_CODE || null,
  refusedCode: process.env.E2E_AI_REFUSED_CODE || null,
};
export const againstAiService = !!aiService.code;

const agentUrl = () => process.env.E2E_AGENT_URL || 'http://stand-in-agent:8090';
async function control(method, path, body) {
  const response = await fetch(`${agentUrl()}/__e2e/${path}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok && response.status !== 404) throw new Error(`the stand-in agent answered ${response.status} to ${path}`);
  return response.status === 204 ? null : response.json();
}

export const standIn = {
  raw: async conversationId => (await control('GET', `raw?conversation_id=${conversationId}`)).deliveries,
  code: async (refuse = null) => (await control('POST', 'codes', { refuse })).code,
  log: async () => (await control('GET', 'log')).log,
  clear: () => control('DELETE', 'log'),
  failWith: status => control('POST', 'fail', { status }),
  connection: () => control('GET', 'connection'),
  orderTool: (conversationId, tool, payload, proposalId) => control('POST', 'order-tool', { conversation_id: Number(conversationId), tool, payload, proposal_id: proposalId }),
  // What the agent reads of a conversation, through the helpdesk's endpoint.
  read: (conversationId, limit) => control('POST', 'read', { conversation_id: conversationId, limit }),
  // A reply with the credentials the stand-in holds, even after a disconnection:
  // through Chatwoot's message call, or the protected reply with `protected`.
  reply: (conversationId, { content, protected: isProtected = false } = {}) =>
    control('POST', 'reply', { conversation_id: conversationId, content, protected: isProtected }),
  // How long a "slow" turn holds its reply at most, and releasing it now.
  slow: ms => control('POST', 'slow', { ms }),
  release: () => control('POST', 'release', {}),
  deliveries: async (conversationId, filter = () => true) =>
    (await standIn.log()).filter(entry => entry.kind === 'delivery' && entry.conversation_id === conversationId && filter(entry)),
};

// The website inbox the agent answers in, with the given users as members.
export async function websiteInbox(api, memberIds = []) {
  const name = 'E2E Website';
  const existing = ((await api.get('/inboxes')).body.payload || []).find(inbox => inbox.name === name);
  const inbox =
    existing || (await api.post('/inboxes', { name, channel: { type: 'web_widget', website_url: 'https://shop.example.test', widget_color: '#1f93ff' } })).body;
  if (memberIds.length) await api.post('/inbox_members', { inbox_id: inbox.id, user_ids: memberIds });
  return inbox;
}

// An email inbox that already has a bot of its own.
export async function emailInboxWithBot(api) {
  const name = 'E2E Email';
  let inbox = ((await api.get('/inboxes')).body.payload || []).find(entry => entry.name === name);
  if (!inbox) inbox = (await api.post('/inboxes', { name, channel: { type: 'email', email: `support-${Date.now()}@shop.example.test` } })).body;
  let bot = ((await api.get('/agent_bots')).body || []).find(entry => entry.name === 'E2E Other bot');
  if (!bot) bot = (await api.post('/agent_bots', { name: 'E2E Other bot', outgoing_url: '' })).body;
  await api.post(`/inboxes/${inbox.id}/set_agent_bot`, { agent_bot: bot.id });
  return { inbox, bot };
}

// The conversation whose messages hold `text`, once the helpdesk has it.
export async function conversationWith(api, text, { timeout = 30_000 } = {}) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const found = ((await api.get(`/conversations/search?q=${encodeURIComponent(text)}`)).body?.payload || [])[0];
    if (found) return found;
    if (Date.now() > deadline) throw new Error(`no conversation holds "${text}" after ${timeout} ms`);
    await new Promise(resolve => setTimeout(resolve, 1_000));
  }
}

// The conversation's messages as the team's API gives them.
export const messagesOf = async (api, conversationId) => (await api.get(`/conversations/${conversationId}/messages`)).body.payload || [];
export const fromAgent = message => message.sender?.type === 'agent_bot' || message.sender_type === 'AgentBot';

// A shopper on the store's site: the widget of `inbox` in a browser context of its own.
export async function shopperOn(browser, inbox) {
  const context = await browser.newContext({ baseURL: process.env.HELPDESK_URL, viewport: { width: 420, height: 760 } });
  const page = await context.newPage();
  await page.goto(`/widget?website_token=${inbox.website_token}`);
  const input = page.locator('#chat-input');
  const start = page.getByRole('button', { name: /start conversation/i });
  await Promise.race([input.waitFor({ timeout: 45_000 }), start.waitFor({ timeout: 45_000 })]);
  if (await start.isVisible()) await start.click();
  await input.waitFor({ timeout: 30_000 });
  const own = page.locator('.user-message-wrap, .chat-bubble.user');
  return {
    page,
    async write(text) {
      await input.fill(text);
      await input.press('Enter');
      await page.getByText(text, { exact: true }).first().waitFor({ timeout: 20_000 });
    },
    // One file per message, as the widget sends them.
    async send(file) {
      const before = await page.locator('img').count();
      await page.locator('input[type="file"]').first().setInputFiles(file);
      await page.waitForFunction(count => document.querySelectorAll('img').length > count, before, { timeout: 30_000 });
    },
    agentBubble: text => page.locator('.agent-message-wrap .chat-bubble.agent').filter({ hasText: text }),
    own,
    close: () => context.close(),
  };
}

// Keeps the whole deliveries of a conversation in the run's output, as samples
// for docs/ai-connector.md (task 3.6). The output is not published by CI.
export async function keepPayloads(name, conversationId) {
  if (againstAiService) return;
  const dir = join(process.env.E2E_OUTPUT || './output', 'ai-payloads');
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${name}.json`), JSON.stringify(await standIn.raw(conversationId), null, 2));
}
