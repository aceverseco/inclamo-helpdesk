// Scenarios of behavior contract `app-agent-auto-connection`, grouped by
// requirement. Each test is named after its scenario;
// scripts/check-e2e-coverage.mjs relies on that.
//
// The store app is the stand-in of e2e/stand-in-app: it signs the calls of
// docs/app-provisioning.md, docs/app-storefront-chat.md and
// docs/app-agent-connection.md with the stack's secret, and takes a new
// pairing token from the stand-in agent (e2e/stand-in-agent) for every
// connection it asks for. The operator of this stack allowed two AI service
// addresses: the stand-in agent's, and the same with the path /second. The
// stores are invented `myshopify.com` domains of this run and the people are
// created by the calls themselves, so no account or user of the other files is
// touched, and the stand-in's connections of this file are never the ones the
// other files act with.
import { test, expect } from '@playwright/test';
import { storeApp, unprovisionedUrl, setPassword, personApi } from '../lib/app.mjs';
import { signIn, eventually } from '../lib/helpdesk.mjs';
import { standIn, shopperOn, conversationWith, messagesOf, fromAgent, callFixture } from '../lib/agent.mjs';

const run = (process.env.E2E_RUN || 'local').toLowerCase().replace(/[^a-z0-9]/g, '');
const store = name => `e2e-${run}-agent-${name}.myshopify.com`;
const person = name => ({ email: `e2e-${run}-agent-${name}@example.test`, name: `E2E Agent ${name}` });
const password = name => `Own-${name}-Passw0rd!`;
const AGENT = 'http://stand-in-agent:8090';
const SECOND = `${AGENT}/second`;
const UNLISTED = `${AGENT}/unlisted`;
const OUTGOING = 1;
const STATUS_KEYS = ['connected_at', 'connected_via', 'contract', 'inbox_ids', 'last_delivered_at', 'last_error', 'last_failed_at', 'last_reply_at', 'phone_inbox_id', 'state'];
const CONNECTED_KEYS = ['connected_at', 'contract', 'inbox_ids', 'outcome', 'phone_inbox_id', 'state'];

// What the tests learn on the way and later ones use.
const made = {};
const shoppers = [];

test.describe.configure({ mode: 'serial' });

test.beforeEach(() => standIn.failWith(null));

test.afterAll(async () => {
  await Promise.all(shoppers.map(shopper => shopper.close().catch(() => {})));
  await standIn.failWith(null);
});

// --- helpers of this file ---------------------------------------------------

// A new store whose administrator has set a password, with the storefront
// inbox the account was created with, as the app learns it.
async function newStore(name) {
  const admin = person(name);
  const answer = await storeApp.provision(store(name), { shop: { name: `Agent store ${name} ${run}` }, admin });
  expect(answer.status).toBe(201);
  expect(await setPassword(answer.body.password_setup_url, password(name))).toBe(200);
  const api = await personApi(admin.email, password(name));
  const chat = await storeApp.storefrontChat(store(name));
  expect(chat.status).toBe(200);
  return { name, domain: store(name), admin, accountId: answer.body.account_id, api, account: api.within(answer.body.account_id), chat: chat.body };
}

async function connected(shop, options = {}) {
  const answer = await storeApp.agent(shop.domain, options);
  expect(answer.status, JSON.stringify(answer.body)).toBe(201);
  return answer.body;
}

const inboxesOf = async shop => (await shop.account.get('/inboxes')).body.payload || [];
const botsOf = async shop => ((await shop.account.get('/agent_bots')).body || []).filter(bot => bot.account_id === shop.accountId);
const labelsOf = async shop => ((await shop.account.get('/labels')).body.payload || []).map(label => label.title).sort();
const botOfInbox = async (shop, inboxId) => (await shop.account.get(`/inboxes/${inboxId}/agent_bot`)).body?.agent_bot?.id ?? null;
const statusOf = async (shop, id) => (await shop.account.get(`/conversations/${id}`)).body.status;
const agentReplies = async (shop, id) => (await messagesOf(shop.account, id)).filter(message => fromAgent(message) && !message.private && message.message_type === OUTGOING);
const registrationsOf = async shop => (await standIn.log()).filter(entry => entry.kind === 'registration' && entry.account_id === shop.accountId);
const snapshot = async shop => ({ bots: await botsOf(shop), inboxes: (await inboxesOf(shop)).map(inbox => inbox.id), labels: await labelsOf(shop) });

// A shopper writes in the website inbox whose token is given; answers the conversation id.
async function shopperWrites(browser, shop, websiteToken, text) {
  const shopper = await shopperOn(browser, { website_token: websiteToken });
  shoppers.push(shopper);
  await shopper.write(text);
  return (await conversationWith(shop.account, text)).id;
}

// What the stand-in agent received about a conversation of this store's
// account: conversation ids are counted per account, so only the deliveries to
// the account's own connections are looked at.
async function deliveriesTo(shop, id) {
  const own = new Set((await registrationsOf(shop)).map(entry => entry.connection_id));
  return (await standIn.log()).filter(entry => entry.kind === 'delivery' && own.has(entry.connection_id) && entry.conversation_id === id);
}

// The agent has no turn in the conversation: it stays with the team and gets no reply.
async function expectWithTheTeam(shop, id) {
  expect(await statusOf(shop, id)).toBe('open');
  await new Promise(resolve => setTimeout(resolve, 6_000));
  expect(await agentReplies(shop, id)).toEqual([]);
  expect(await deliveriesTo(shop, id)).toEqual([]);
}

async function emailInbox(shop) {
  const inbox = (await shop.account.post('/inboxes', { name: 'Support email', channel: { type: 'email', email: `support-${run}-${shop.name}@example.test` } })).body;
  expect(inbox.id, JSON.stringify(inbox)).toBeTruthy();
  return inbox;
}

// A shopper's new conversation in the email inbox, opened through the team's
// API. Whether a bot holds a conversation is decided when it is opened
// (pending for the inbox's bot, open for the team); the team's API takes no
// incoming message in an email inbox, so none is posted.
let mails = 0;
async function emailArrives(shop, inboxId) {
  mails += 1;
  const contact = (await shop.account.post('/contacts', { inbox_id: inboxId, name: 'Email shopper', email: `shopper-${run}-${shop.name}-${mails}@example.test` })).body.payload;
  const created = await shop.account.post('/conversations', { source_id: contact.contact_inbox.source_id, inbox_id: inboxId, contact_id: contact.contact.id });
  expect(created.status, JSON.stringify(created.body)).toBe(200);
  return created.body;
}

async function deleteInbox(shop, inboxId) {
  expect((await shop.account.delete(`/inboxes/${inboxId}`)).status).toBe(200);
  await eventually(() => inboxesOf(shop), inboxes => !inboxes.some(inbox => inbox.id === inboxId), { timeout: 60_000 });
}

// The administrator's "AI agent" page in the browser.
async function openAiPage(page, shop) {
  // A new account's administrator first meets Chatwoot's own first-run form;
  // it is finished here the way that form finishes it.
  expect((await shop.account.patch('/onboarding', { onboarding_step: 'account_details' })).status).toBe(200);
  await signIn(page, { email: shop.admin.email, password: password(shop.name) });
  await page.goto(`/app/accounts/${shop.accountId}/settings/ai-agent`);
  const view = page.getByTestId('inclamo-ai-page');
  await view.waitFor({ timeout: 45_000 });
  return view;
}

// The same person, signed in on the installation that has no provisioning.
async function onSelfHosted(shop) {
  const base = unprovisionedUrl();
  const signedIn = await fetch(`${base}/auth/sign_in`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: shop.admin.email, password: password(shop.name) }) });
  expect(signedIn.status).toBe(200);
  const headers = Object.fromEntries(['access-token', 'client', 'uid', 'expiry', 'token-type'].map(name => [name, signedIn.headers.get(name)]));
  return async (method, path, data) => {
    const response = await fetch(`${base}/api/v1/accounts/${shop.accountId}${path}`, { method, headers: { ...headers, 'Content-Type': 'application/json' }, body: data === undefined ? undefined : JSON.stringify(data) });
    return { status: response.status, body: await response.json().catch(() => null) };
  };
}

// --- The app connects the agent to a store's account -------------------------

test.describe("The app connects the agent to a store's account", () => {
  test('A provisioned account is connected', async ({ browser }) => {
    const shop = await newStore('main');

    const answer = await storeApp.agent(shop.domain);

    expect(answer.status).toBe(201);
    expect(Object.keys(answer.body).sort()).toEqual(CONNECTED_KEYS);
    expect(answer.body).toMatchObject({ contract: 1, state: 'connected', outcome: 'connected', inbox_ids: [shop.chat.inbox_id] });
    const phone = (await inboxesOf(shop)).find(inbox => inbox.id === answer.body.phone_inbox_id);
    expect(phone).toMatchObject({ name: 'Phone', channel_type: 'Channel::Api' });
    // The AI service was registered with the storefront inbox, as the helpdesk chose it.
    expect((await registrationsOf(shop)).map(entry => [entry.inbox_ids, entry.phone_inbox_id, entry.via])).toEqual([[[shop.chat.inbox_id], phone.id, 'pairing']]);
    expect((await labelsOf(shop))).toEqual(expect.arrayContaining(['inclamo_handover', 'inclamo_call']));

    // A shopper on the store's site: the conversation is held for the agent, which answers.
    const id = await shopperWrites(browser, shop, shop.chat.website_token, `Hello from the storefront ${run}`);
    expect(await statusOf(shop, id)).toBe('pending');
    await eventually(() => agentReplies(shop, id), replies => replies.length >= 1, { timeout: 45_000 });
    made.main = { ...shop, phoneInboxId: phone.id, connectedAt: answer.body.connected_at, conversationId: id };
  });

  test('The AI service refuses', async () => {
    const shop = await newStore('refused');
    const before = await snapshot(shop);

    const answer = await storeApp.agent(shop.domain, { refuse: { status: 410, error: 'invalid_token', message: 'This pairing token has expired.' } });

    expect(answer.status).toBe(422);
    expect(answer.body).toEqual({ error: 'agent_refused', message: 'This pairing token has expired.', service_error: 'invalid_token' });
    expect(await snapshot(shop)).toEqual(before);
    expect((await inboxesOf(shop)).some(inbox => inbox.name === 'Phone')).toBe(false);
    expect((await storeApp.agentStatus(shop.domain)).body.state).toBe('never_connected');
  });

  test('The AI service does not answer', async () => {
    const shop = await newStore('silent');
    const before = await snapshot(shop);
    const started = Date.now();

    // The AI service answers only after twelve seconds; the helpdesk waits ten.
    const answer = await storeApp.agent(shop.domain, { refuse: { status: 503, error: 'late', message: 'Too late.', delay_ms: 12_000 } });

    expect(answer.status).toBe(502);
    expect(answer.body).toEqual({ error: 'agent_not_answered' });
    expect(Date.now() - started).toBeLessThan(15_000);
    expect(await snapshot(shop)).toEqual(before);
    expect((await inboxesOf(shop)).some(inbox => inbox.name === 'Phone')).toBe(false);
  });
});

// --- Only a provisioned, active account is connected this way -----------------

test.describe('Only a provisioned, active account is connected this way', () => {
  test('A store without an account', async () => {
    const domain = store('nobody');

    const answer = await storeApp.agent(domain);

    expect([answer.status, answer.body]).toEqual([404, { error: 'no_account' }]);
    expect([(await storeApp.agentStatus(domain)).status, (await storeApp.agentDisconnect(domain)).status]).toEqual([404, 404]);
    expect((await storeApp.status(domain)).status).toBe(404);
  });

  test('A suspended account', async () => {
    const shop = await newStore('suspended');
    expect((await storeApp.removal(shop.domain)).body.state).toBe('suspended');

    const answer = await storeApp.agent(shop.domain);

    expect([answer.status, answer.body]).toEqual([409, { error: 'account_suspended' }]);
    expect(await registrationsOf(shop)).toEqual([]);
    expect((await storeApp.agentStatus(shop.domain)).body).toMatchObject({ state: 'never_connected', inbox_ids: [] });
    // Restored, the account shows it had no agent bot.
    expect((await storeApp.provision(shop.domain, { admin: shop.admin })).body.outcome).toBe('restored');
    expect(await botsOf(shop)).toEqual([]);
  });

  test('A request with a wrong signature', async () => {
    const shop = await newStore('signature');

    const answer = await storeApp.agent(shop.domain, { wrong_signature: true });

    expect([answer.status, answer.body]).toEqual([401, { error: 'unauthorized' }]);
    expect(await registrationsOf(shop)).toEqual([]);
    expect(await botsOf(shop)).toEqual([]);
    expect((await storeApp.agentStatus(shop.domain)).body.state).toBe('never_connected');
  });
});

// --- The helpdesk chooses where the agent answers -----------------------------

test.describe('The helpdesk chooses where the agent answers', () => {
  test('The agent starts in the storefront chat', async ({ browser }) => {
    const shop = await newStore('email');
    const email = await emailInbox(shop);

    const answer = await connected(shop);

    expect(answer.inbox_ids).toEqual([shop.chat.inbox_id]);
    expect(await botOfInbox(shop, shop.chat.inbox_id)).toBeTruthy();
    expect(await botOfInbox(shop, email.id)).toBeNull();
    const mail = await emailArrives(shop, email.id);
    await expectWithTheTeam(shop, mail.id);
    const chatId = await shopperWrites(browser, shop, shop.chat.website_token, `A question in the chat ${run}`);
    expect(await statusOf(shop, chatId)).toBe('pending');
    await eventually(() => agentReplies(shop, chatId), replies => replies.length >= 1, { timeout: 45_000 });
  });

  test('The request names inboxes', async () => {
    const shop = await newStore('names');
    const email = await emailInbox(shop);

    const answer = await connected(shop, { extra: { inbox_ids: [email.id] } });

    expect(answer.inbox_ids).toEqual([shop.chat.inbox_id]);
    expect(await botOfInbox(shop, email.id)).toBeNull();
    expect((await registrationsOf(shop)).map(entry => entry.inbox_ids)).toEqual([[shop.chat.inbox_id]]);
  });

  test('The storefront inbox has another bot', async () => {
    const shop = await newStore('otherbot');
    const other = (await shop.account.post('/agent_bots', { name: `E2E other bot ${run}`, outgoing_url: '' })).body;
    expect((await shop.account.post(`/inboxes/${shop.chat.inbox_id}/set_agent_bot`, { agent_bot: other.id })).status).toBeLessThan(300);

    const answer = await connected(shop);

    expect(answer.inbox_ids).toEqual([]);
    expect(answer.phone_inbox_id).toBeTruthy();
    expect((await registrationsOf(shop)).map(entry => entry.inbox_ids)).toEqual([[]]);
    expect(await botOfInbox(shop, shop.chat.inbox_id)).toBe(other.id);
  });

  test('Connected for calls only', async ({ browser }) => {
    const shop = await newStore('calls');
    await deleteInbox(shop, shop.chat.inbox_id);
    const site = (await shop.account.post('/inboxes', { name: 'Team site', channel: { type: 'web_widget', website_url: 'https://team-site.example.test' } })).body;

    const answer = await connected(shop);

    expect(answer.inbox_ids).toEqual([]);
    expect(await botOfInbox(shop, site.id)).toBeNull();
    // The agent files a finished call with its own token; it lands in Phone.
    const call = await standIn.call(callFixture('resolved-inbound', { call_id: `e2e-${run}-agent-calls-only`, caller: { phone: '+12025550161' } }), shop.accountId);
    expect(call.status, JSON.stringify(call.body)).toBe(201);
    expect((await shop.account.get(`/conversations/${call.body.conversation_id}`)).body.inbox_id).toBe(answer.phone_inbox_id);
    const id = await shopperWrites(browser, shop, site.website_token, `Calls only, a chat message ${run}`);
    await expectWithTheTeam(shop, id);
    made.calls = shop;
  });
});

// --- Asking again changes nothing ---------------------------------------------

test.describe('Asking again changes nothing', () => {
  test('The request is repeated', async () => {
    const shop = made.main;
    const bots = await botsOf(shop);
    expect(bots).toHaveLength(1);

    const answer = await storeApp.agent(shop.domain);

    expect(answer.status).toBe(200);
    expect(answer.body).toEqual({
      contract: 1, state: 'connected', outcome: 'existed', inbox_ids: [shop.chat.inbox_id], phone_inbox_id: shop.phoneInboxId, connected_at: shop.connectedAt,
    });
    expect(await registrationsOf(shop)).toHaveLength(1);
    expect((await botsOf(shop)).map(bot => bot.id)).toEqual(bots.map(bot => bot.id));
  });

  // The storefront inbox made while the agent is connected gets the agent when
  // it is made (capability agent-inbox-selection), not from the repeated request.
  test('A storefront inbox appears after the connection', async ({ browser }) => {
    const shop = made.calls;
    const bots = (await botsOf(shop)).map(bot => bot.id);
    const chat = await storeApp.storefrontChat(shop.domain);
    expect([chat.status, chat.body.outcome]).toEqual([201, 'created']);
    expect(await botOfInbox(shop, chat.body.inbox_id)).toBe(bots[0]);

    const answer = await storeApp.agent(shop.domain);

    expect([answer.status, answer.body.outcome, answer.body.inbox_ids]).toEqual([200, 'existed', [chat.body.inbox_id]]);
    expect((await botsOf(shop)).map(bot => bot.id)).toEqual(bots);
    expect(await registrationsOf(shop)).toHaveLength(1);
    const id = await shopperWrites(browser, shop, chat.body.website_token, `The new storefront chat ${run}`);
    expect(await statusOf(shop, id)).toBe('pending');
    await eventually(() => agentReplies(shop, id), replies => replies.length >= 1, { timeout: 45_000 });
  });

  test('Another address for a connected account', async () => {
    const shop = made.main;
    const bots = (await botsOf(shop)).map(bot => bot.id);

    const answer = await storeApp.agent(shop.domain, { service_url: SECOND });

    expect([answer.status, answer.body]).toEqual([409, { error: 'agent_connected' }]);
    expect((await botsOf(shop)).map(bot => bot.id)).toEqual(bots);
    expect((await storeApp.agentStatus(shop.domain)).body).toMatchObject({ state: 'connected', inbox_ids: [shop.chat.inbox_id] });
    expect((await standIn.log()).filter(entry => entry.kind === 'unknown_request' && entry.path.startsWith('/second'))).toEqual([]);
  });
});

// --- The agent's credentials go only to an allowed AI service -----------------

test.describe("The agent's credentials go only to an allowed AI service", () => {
  test('An address that is not listed', async () => {
    const shop = await newStore('unlisted');

    const answer = await storeApp.agent(shop.domain, { service_url: UNLISTED });

    expect(answer.status).toBe(422);
    expect(answer.body.error).toBe('service_url_not_allowed');
    expect((await standIn.log()).filter(entry => entry.kind === 'unknown_request' && entry.path.startsWith('/unlisted'))).toEqual([]);
    expect(await registrationsOf(shop)).toEqual([]);
    expect(await botsOf(shop)).toEqual([]);
  });
});

// --- The app can ask how the connection is doing ------------------------------

test.describe('The app can ask how the connection is doing', () => {
  test('A connected account', async () => {
    const shop = made.main;

    const answer = await storeApp.agentStatus(shop.domain);

    expect(answer.status).toBe(200);
    expect(Object.keys(answer.body).sort()).toEqual(STATUS_KEYS);
    expect(answer.body).toMatchObject({
      contract: 1, state: 'connected', connected_via: 'app', inbox_ids: [shop.chat.inbox_id], phone_inbox_id: shop.phoneInboxId,
      connected_at: shop.connectedAt, last_failed_at: null, last_error: null,
    });
    expect(Date.parse(answer.body.last_delivered_at)).toBeGreaterThan(0);
    expect(Date.parse(answer.body.last_reply_at)).toBeGreaterThan(0);
    // Nothing of the conversation, and no credential.
    expect(JSON.stringify(answer.body)).not.toContain('Hello from the storefront');
    expect(JSON.stringify(answer.body)).not.toMatch(/token|secret/i);
  });

  test('Deliveries are failing', async ({ browser }) => {
    const shop = await newStore('failing');
    await connected(shop);
    await standIn.failWith(503);
    try {
      await shopperWrites(browser, shop, shop.chat.website_token, `While the AI service fails ${run}`);

      const answer = await eventually(() => storeApp.agentStatus(shop.domain), status => status.body.state === 'failing', { timeout: 60_000 });

      expect(answer.body).toMatchObject({ state: 'failing', last_error: 'http_503', inbox_ids: [shop.chat.inbox_id] });
      expect(Date.parse(answer.body.last_failed_at)).toBeGreaterThan(0);
    } finally {
      await standIn.failWith(null);
    }
  });

  test('An account that was never connected', async () => {
    const shop = await newStore('never');

    const answer = await storeApp.agentStatus(shop.domain);

    expect(answer.status).toBe(200);
    expect(answer.body).toEqual({
      contract: 1, state: 'never_connected', connected_via: null, inbox_ids: [], phone_inbox_id: null,
      connected_at: null, last_reply_at: null, last_delivered_at: null, last_failed_at: null, last_error: null,
    });
  });
});

// --- The app can disconnect the agent -------------------------------------------

test.describe('The app can disconnect the agent', () => {
  test('The app disconnects', async ({ browser }) => {
    const shop = await newStore('disconnect');
    const answer = await connected(shop);
    const pending = [
      await shopperWrites(browser, shop, shop.chat.website_token, `First shopper waiting ${run}`),
      await shopperWrites(browser, shop, shop.chat.website_token, `Second shopper waiting ${run}`),
    ];
    for (const id of pending) expect(await statusOf(shop, id)).toBe('pending');
    const call = await standIn.call(callFixture('resolved-inbound', { call_id: `e2e-${run}-agent-before-disconnect`, caller: { phone: '+12025550162' } }), shop.accountId);
    expect(call.status).toBe(201);

    const done = await storeApp.agentDisconnect(shop.domain);

    expect([done.status, done.body]).toEqual([200, { contract: 1, state: 'disconnected', ai_service_told: true }]);
    for (const id of pending) expect(await statusOf(shop, id)).toBe('open');
    expect((await standIn.reply(pending[0], { accountId: shop.accountId })).status).toBe(401);
    expect((await standIn.connection(shop.accountId)).removed).toBe(true);
    expect((await inboxesOf(shop)).map(inbox => inbox.id)).toContain(answer.phone_inbox_id);
    expect((await shop.account.get(`/conversations/${call.body.conversation_id}`)).body.inbox_id).toBe(answer.phone_inbox_id);
    expect(await botsOf(shop)).toEqual([]);
    made.disconnected = { ...shop, pending };
  });

  test('Disconnecting twice', async () => {
    const shop = made.disconnected;
    const removals = async () => (await standIn.log()).filter(entry => entry.kind === 'removal').length;
    const before = await removals();

    const again = await storeApp.agentDisconnect(shop.domain);

    expect([again.status, again.body]).toEqual([200, { contract: 1, state: 'disconnected', ai_service_told: true }]);
    expect(await removals()).toBe(before);
    for (const id of shop.pending) expect(await statusOf(shop, id)).toBe('open');
    expect((await storeApp.agentStatus(shop.domain)).body.state).toBe('disconnected');
  });
});

// --- A suspended account has no agent --------------------------------------------

test.describe('A suspended account has no agent', () => {
  test('The app is removed from a connected store', async () => {
    const shop = await newStore('removed');
    await connected(shop);
    const connection = await standIn.connection(shop.accountId);
    expect(connection.removed).toBe(false);

    const removal = await storeApp.removal(shop.domain);

    expect([removal.status, removal.body]).toEqual([200, { contract: 1, state: 'suspended' }]);
    // The AI service was told, with the bot's former token, and that token is refused.
    expect((await standIn.connection(shop.accountId)).removed).toBe(true);
    expect((await standIn.log()).filter(entry => entry.kind === 'removal' && entry.connection_id === connection.id)).toHaveLength(1);
    expect((await standIn.reply(1, { accountId: shop.accountId })).status).toBe(401);
    expect((await storeApp.agentStatus(shop.domain)).body).toMatchObject({ state: 'disconnected', inbox_ids: [] });
    made.removed = shop;
  });

  test('The store installs the app again', async ({ browser }) => {
    const shop = made.removed;

    const restored = await storeApp.provision(shop.domain, { admin: shop.admin });

    expect([restored.status, restored.body.outcome]).toEqual([200, 'restored']);
    expect((await storeApp.agentStatus(shop.domain)).body).toMatchObject({ state: 'disconnected', connected_via: 'app', inbox_ids: [] });
    expect(await botsOf(shop)).toEqual([]);
    const id = await shopperWrites(browser, shop, shop.chat.website_token, `Back after the reinstall ${run}`);
    await expectWithTheTeam(shop, id);
  });
});

// --- The "AI agent" page keeps working and names the app ---------------------------

test.describe('The "AI agent" page keeps working and names the app', () => {
  test('An installation without provisioning', async ({ browser }) => {
    const shop = await newStore('selfhosted');
    // The installation without the secret has none of the app's calls.
    const elsewhere = await storeApp.agent(shop.domain, { helpdesk_url: unprovisionedUrl() });
    expect([elsewhere.status, elsewhere.body]).toEqual([404, null]);
    const api = await onSelfHosted(shop);

    const answer = await api('POST', '/inclamo/ai/connection', { connection_code: await standIn.pairingCode(), inbox_ids: [shop.chat.inbox_id] });

    expect(answer.status, JSON.stringify(answer.body)).toBe(201);
    expect(answer.body.connection).toMatchObject({ state: 'connected', inbox_ids: [shop.chat.inbox_id], connected_via: 'page', connected_by: shop.admin.name });
    const id = await shopperWrites(browser, shop, shop.chat.website_token, `A self-hosted shopper ${run}`);
    expect(await statusOf(shop, id)).toBe('pending');
    await eventually(() => agentReplies(shop, id), replies => replies.length >= 1, { timeout: 45_000 });
  });

  test('A connection made by the app', async ({ page }) => {
    const shop = made.main;

    const view = await openAiPage(page, shop);

    await expect(view).toHaveAttribute('data-state', 'connected');
    await expect(view.getByTestId('inclamo-ai-state')).toHaveAttribute('data-state', 'connected');
    await expect(view.getByTestId(`inclamo-ai-connected-${shop.chat.inbox_id}`)).toBeVisible();
    await expect(view.getByTestId('inclamo-ai-connected-by')).toHaveAttribute('data-via', 'app');
    await expect(view.getByTestId('inclamo-ai-connected-by')).toHaveText('The store app');
    await expect(view.getByTestId('inclamo-ai-connected-by')).not.toContainText(shop.admin.name);
    await expect(view.getByTestId('inclamo-ai-last-reply')).not.toHaveText('No reply yet');
    await expect(view.getByTestId('inclamo-ai-last-error')).toHaveText('None');
  });

  test('The administrator disconnects a connection the app made', async ({ page }) => {
    const shop = made.main;
    const view = await openAiPage(page, shop);

    await view.getByTestId('inclamo-ai-disconnect').click();
    const dialog = page.getByRole('dialog').filter({ has: page.getByTestId('inclamo-ai-confirm') });
    await expect(dialog.getByTestId('inclamo-ai-confirm')).toBeVisible();
    await dialog.getByRole('button', { name: 'Disconnect' }).click();

    await expect(view).toHaveAttribute('data-state', 'disconnected', { timeout: 30_000 });
    expect((await storeApp.agentStatus(shop.domain)).body).toMatchObject({ state: 'disconnected', inbox_ids: [] });
    expect((await standIn.connection(shop.accountId)).removed).toBe(true);
  });

  test('The administrator moves the agent to other inboxes', async ({ browser }) => {
    const shop = await newStore('moved');
    await connected(shop);
    const email = await emailInbox(shop);
    expect((await shop.account.delete('/inclamo/ai/connection')).status).toBe(200);

    const answer = await shop.account.post('/inclamo/ai/connection', { connection_code: await standIn.pairingCode(), inbox_ids: [email.id] });

    expect(answer.status, JSON.stringify(answer.body)).toBe(201);
    const mail = await emailArrives(shop, email.id);
    expect(mail.status).toBe('pending');
    const chatId = await shopperWrites(browser, shop, shop.chat.website_token, `The chat after the move ${run}`);
    await expectWithTheTeam(shop, chatId);
    const status = await storeApp.agentStatus(shop.domain);
    expect(status.body).toMatchObject({ state: 'connected', connected_via: 'page', inbox_ids: [email.id] });
    // The app leaves the page's choice alone: asking again changes nothing.
    const again = await storeApp.agent(shop.domain);
    expect([again.status, again.body.outcome, again.body.inbox_ids]).toEqual([200, 'existed', [email.id]]);
  });
});
