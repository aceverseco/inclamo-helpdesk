// Scenarios of behavior contract `agent-inbox-selection`, grouped by
// requirement. Each test is named after its scenario;
// scripts/check-e2e-coverage.mjs relies on that.
//
// An administrator changes the inboxes of a live AI agent connection on the
// "AI agent" page (docs/ai-connector.md §1.4). The accounts are those of
// invented stores the stand-in store app (e2e/stand-in-app) provisions in this
// run, connected either with a code (a pairing token of the stand-in agent
// pasted as a code, on the page's own address) or by the store app, so no
// account or connection of the other files is touched. The AI service is the
// stand-in agent of e2e/stand-in-agent: it keeps the list it was last told,
// takes no turn outside it, and is switched per account to refuse a change, to
// stay silent past the helpdesk's ten seconds, to answer 404 as a service
// without the call, or to accept only after a delay.
import { test, expect } from '@playwright/test';
import { storeApp, setPassword, personApi } from '../lib/app.mjs';
import { signIn, eventually, users } from '../lib/helpdesk.mjs';
import { standIn, shopperOn, conversationWith, messagesOf, fromAgent, callFixture } from '../lib/agent.mjs';

const run = (process.env.E2E_RUN || 'local').toLowerCase().replace(/[^a-z0-9]/g, '');
const store = name => `e2e-${run}-inboxes-${name}.myshopify.com`;
const person = name => ({ email: `e2e-${run}-inboxes-${name}@example.test`, name: `E2E Inboxes ${name}` });
const password = name => `Own-${name}-Passw0rd!`;
const OUTGOING = 1;

// What the tests learn on the way and later ones use.
const made = {};
const shoppers = [];
let withStoreApp = true;

test.describe.configure({ mode: 'serial' });

test.beforeAll(async () => {
  // The accounts of this file are made through the store app.
  withStoreApp = await storeApp.status(store('probe')).then(() => true, () => false);
});

test.beforeEach(async () => {
  test.skip(!withStoreApp, 'this stack has no store app, and the accounts of this file are made through it');
  await standIn.failWith(null);
  await standIn.inboxSwitch(null);
});

test.afterAll(async () => {
  await Promise.all(shoppers.map(shopper => shopper.close().catch(() => {})));
  await standIn.failWith(null).catch(() => {});
  await standIn.inboxSwitch(null).catch(() => {});
});

// --- helpers of this file ---------------------------------------------------

// A new store whose administrator has set a password, with the storefront
// inbox the account was created with, as the app learns it.
async function newStore(name) {
  const admin = person(name);
  const answer = await storeApp.provision(store(name), { shop: { name: `Inboxes store ${name} ${run}` }, admin });
  expect(answer.status, JSON.stringify(answer.body)).toBe(201);
  expect(await setPassword(answer.body.password_setup_url, password(name))).toBe(200);
  const api = await personApi(admin.email, password(name));
  const chat = await storeApp.storefrontChat(store(name));
  expect(chat.status).toBe(200);
  return { name, domain: store(name), admin, accountId: answer.body.account_id, api, account: api.within(answer.body.account_id), chat: chat.body };
}

// Connected on the page's own address with a code, as an administrator does.
async function connectedByCode(shop, inboxIds) {
  const answer = await shop.account.post('/inclamo/ai/connection', { connection_code: await standIn.pairingCode(), inbox_ids: inboxIds });
  expect(answer.status, JSON.stringify(answer.body)).toBe(201);
  return answer.body;
}

// Connected by the store app, in the storefront inbox.
async function connectedByApp(shop) {
  const answer = await storeApp.agent(shop.domain);
  expect(answer.status, JSON.stringify(answer.body)).toBe(201);
  return answer.body;
}

const aiConnection = async shop => (await shop.account.get('/inclamo/ai/connection')).body;
const saveInboxes = (shop, inboxIds) => shop.account.patch('/inclamo/ai/connection', { inbox_ids: inboxIds });
const sorted = ids => [...ids].sort((a, b) => a - b);
const inboxesOf = async shop => (await shop.account.get('/inboxes')).body.payload || [];
const botsOf = async shop => ((await shop.account.get('/agent_bots')).body || []).filter(bot => bot.account_id === shop.accountId);
const botOfInbox = async (shop, inboxId) => (await shop.account.get(`/inboxes/${inboxId}/agent_bot`)).body?.agent_bot?.id ?? null;
const conversationOf = async (shop, id) => (await shop.account.get(`/conversations/${id}`)).body;
const statusOf = async (shop, id) => (await conversationOf(shop, id)).status;
const agentReplies = async (shop, id) => (await messagesOf(shop.account, id)).filter(message => fromAgent(message) && !message.private && message.message_type === OUTGOING);
const registrationsOf = async shop => (await standIn.log()).filter(entry => entry.kind === 'registration' && entry.account_id === shop.accountId);
const changesOf = async shop => (await standIn.inboxChanges(shop.accountId)).map(entry => [sorted(entry.inbox_ids), entry.outcome]);

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

// The agent has the conversation: it is Pending, the AI service got the message and its reply is in.
async function expectWithTheAgent(shop, id, text) {
  expect(await statusOf(shop, id)).toBe('pending');
  await eventually(() => deliveriesTo(shop, id), list => list.some(entry => entry.event === 'message_created' && entry.content === text), { timeout: 45_000 });
  await eventually(() => agentReplies(shop, id), replies => replies.length >= 1, { timeout: 45_000 });
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

async function siteInbox(shop) {
  const inbox = (await shop.account.post('/inboxes', { name: 'Team site', channel: { type: 'web_widget', website_url: `https://${shop.name}-site.example.test` } })).body;
  expect(inbox.website_token, JSON.stringify(inbox)).toBeTruthy();
  return inbox;
}

// A shopper's new conversation in the email inbox, opened through the team's
// API: whether a bot holds a conversation is decided when it is opened.
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

// One of the users e2e/setup.rb prepares, made a member of the store's account
// with `role`; `leave()` takes them out of it again.
async function member(shop, user, role) {
  const added = await shop.account.post('/agents', { name: `E2E ${role}`, email: user.email, role });
  expect(added.status, JSON.stringify(added.body)).toBe(200);
  const api = (await personApi(user.email, user.password)).within(shop.accountId);
  return { api, leave: () => shop.account.delete(`/agents/${added.body.id}`) };
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
  await expect(view).toHaveAttribute('data-state', 'connected');
  return view;
}

const tick = (view, inboxId) => view.getByTestId(`inclamo-ai-inbox-${inboxId}`).locator('input').check();
const untick = (view, inboxId) => view.getByTestId(`inclamo-ai-inbox-${inboxId}`).locator('input').uncheck();
const changeDialog = page => page.getByRole('dialog').filter({ has: page.getByTestId('inclamo-ai-change-confirm') });

// --- An administrator changes the agent's inboxes on the AI agent page --------

test.describe("An administrator changes the agent's inboxes on the AI agent page", () => {
  test('An inbox is added to a connection made with a code', async ({ page }) => {
    const shop = await newStore('code');
    const email = await emailInbox(shop);
    const before = await connectedByCode(shop, [shop.chat.inbox_id]);
    const view = await openAiPage(page, shop);
    await expect(view.getByTestId('inclamo-ai-save')).toBeDisabled();

    await tick(view, email.id);
    await view.getByTestId('inclamo-ai-save').click();

    await expect(view.getByTestId(`inclamo-ai-connected-${email.id}`)).toBeVisible({ timeout: 30_000 });
    await expect(view.getByTestId(`inclamo-ai-connected-${shop.chat.inbox_id}`)).toBeVisible();
    await expect(view.getByTestId('inclamo-ai-state')).toHaveAttribute('data-state', 'connected');
    await expect(view.getByTestId('inclamo-ai-connected-by')).toHaveAttribute('data-via', 'page');
    const after = (await aiConnection(shop)).connection;
    expect(sorted(after.inbox_ids)).toEqual(sorted([shop.chat.inbox_id, email.id]));
    expect(after.connected_at).toBe(before.connection.connected_at);
    expect(after.phone_inbox_id).toBe(before.connection.phone_inbox_id);
    expect(await changesOf(shop)).toEqual([[sorted([shop.chat.inbox_id, email.id]), 'accepted']]);
    const bots = await botsOf(shop);
    expect(bots).toHaveLength(1);
    expect(await botOfInbox(shop, email.id)).toBe(bots[0].id);
    expect(await registrationsOf(shop)).toHaveLength(1);
    made.code = { ...shop, email };
  });

  test('An inbox is added to a connection made by the store app', async ({ page }) => {
    const shop = await newStore('app');
    await connectedByApp(shop);
    const email = await emailInbox(shop);
    const view = await openAiPage(page, shop);

    await tick(view, email.id);
    await view.getByTestId('inclamo-ai-save').click();

    await expect(view.getByTestId(`inclamo-ai-connected-${email.id}`)).toBeVisible({ timeout: 30_000 });
    await expect(view.getByTestId(`inclamo-ai-connected-${shop.chat.inbox_id}`)).toBeVisible();
    await expect(view.getByTestId('inclamo-ai-connected-by')).toHaveAttribute('data-via', 'app');
    await expect(view.getByTestId('inclamo-ai-connected-by')).toHaveText('The store app');
    expect((await aiConnection(shop)).connection.connected_via).toBe('app');
    made.app = { ...shop, email };
  });

  test('An agent of the team tries to change the inboxes', async () => {
    const shop = made.code;
    const agent = await member(shop, users.agent, 'agent');
    try {
      const answer = await agent.api.patch('/inclamo/ai/connection', { inbox_ids: [shop.chat.inbox_id] });

      expect([answer.status, answer.body.error]).toEqual([403, 'forbidden']);
      expect(sorted((await aiConnection(shop)).connection.inbox_ids)).toEqual(sorted([shop.chat.inbox_id, shop.email.id]));
      expect(await changesOf(shop)).toHaveLength(1);
    } finally {
      await agent.leave();
    }
  });

  test('The account is not connected', async () => {
    const shop = await newStore('never');

    const answer = await saveInboxes(shop, [shop.chat.inbox_id]);

    expect([answer.status, answer.body.error]).toEqual([404, 'not_connected']);
    expect(await botsOf(shop)).toEqual([]);
    expect((await inboxesOf(shop)).some(inbox => inbox.name === 'Phone')).toBe(false);
    expect(await changesOf(shop)).toEqual([]);
    expect((await aiConnection(shop)).state).toBe('never_connected');
  });
});

// --- The agent answers first in an added inbox from the moment it is added ---

test.describe('The agent answers first in an added inbox from the moment it is added', () => {
  test('A shopper writes after the inbox was added', async ({ browser }) => {
    const shop = await newStore('added');
    await connectedByCode(shop, [shop.chat.inbox_id]);
    const site = await siteInbox(shop);
    expect((await saveInboxes(shop, [shop.chat.inbox_id, site.id])).status).toBe(200);
    const text = `A question on the team site ${run}`;

    const id = await shopperWrites(browser, shop, site.website_token, text);

    await expectWithTheAgent(shop, id, text);
  });

  test('A conversation that was open before', async () => {
    const shop = await newStore('before');
    await connectedByCode(shop, [shop.chat.inbox_id]);
    const email = await emailInbox(shop);
    const mail = await emailArrives(shop, email.id);
    const adminId = (await shop.api.profile()).id;
    expect((await shop.account.post(`/conversations/${mail.id}/assignments`, { assignee_id: adminId })).status).toBe(200);
    expect(await conversationOf(shop, mail.id)).toMatchObject({ status: 'open', meta: { assignee: { id: adminId } } });

    expect((await saveInboxes(shop, [shop.chat.inbox_id, email.id])).status).toBe(200);

    expect(await conversationOf(shop, mail.id)).toMatchObject({ status: 'open', meta: { assignee: { id: adminId } } });
    expect(await deliveriesTo(shop, mail.id)).toEqual([]);
    expect((await emailArrives(shop, email.id)).status).toBe('pending');
  });
});

// --- Removing an inbox gives its conversations to the team ---------------------

test.describe('Removing an inbox gives its conversations to the team', () => {
  test('The agent holds two conversations in the removed inbox', async ({ browser }) => {
    const shop = await newStore('removed');
    const email = await emailInbox(shop);
    await connectedByCode(shop, [shop.chat.inbox_id, email.id]);
    const chats = [
      await shopperWrites(browser, shop, shop.chat.website_token, `First shopper in the chat ${run}`),
      await shopperWrites(browser, shop, shop.chat.website_token, `Second shopper in the chat ${run}`),
    ];
    const mail = await emailArrives(shop, email.id);
    for (const id of [...chats, mail.id]) expect(await statusOf(shop, id)).toBe('pending');

    const answer = await saveInboxes(shop, [email.id]);

    expect(answer.status, JSON.stringify(answer.body)).toBe(200);
    for (const id of chats) expect(await statusOf(shop, id)).toBe('open');
    expect(await conversationOf(shop, mail.id)).toMatchObject({ status: 'pending' });
    expect(await botOfInbox(shop, shop.chat.inbox_id)).toBeNull();
    const fresh = await shopperWrites(browser, shop, shop.chat.website_token, `A shopper after the removal ${run}`);
    await expectWithTheTeam(shop, fresh);
    made.removed = { ...shop, chats };
  });

  test('The agent asks for a conversation of a removed inbox', async () => {
    const shop = made.removed;

    const answer = await standIn.read(shop.chats[0], undefined, shop.accountId);

    expect(answer.status).toBe(403);
    expect(answer.body?.messages).toBeUndefined();
    expect(JSON.stringify(answer.body)).not.toContain('First shopper in the chat');
  });

  test('The page warns before removing', async ({ browser, page }) => {
    const shop = await newStore('warn');
    await connectedByApp(shop);
    for (const which of ['first', 'second']) {
      const id = await shopperWrites(browser, shop, shop.chat.website_token, `The ${which} shopper waiting ${run}`);
      await eventually(() => agentReplies(shop, id), replies => replies.length >= 1, { timeout: 45_000 });
    }
    const view = await openAiPage(page, shop);

    await untick(view, shop.chat.inbox_id);
    await view.getByTestId('inclamo-ai-save').click();

    const dialog = changeDialog(page);
    await expect(dialog.getByTestId('inclamo-ai-change-handover')).toHaveAttribute('data-count', '2');
    await expect(dialog.getByTestId('inclamo-ai-change-handover')).toContainText('2');
    await dialog.getByRole('button', { name: 'Keep as it is' }).click();
    await expect(dialog).toBeHidden();
    expect(await changesOf(shop)).toEqual([]);
    expect(await botOfInbox(shop, shop.chat.inbox_id)).toBeTruthy();
    await expect(view.getByTestId(`inclamo-ai-connected-${shop.chat.inbox_id}`)).toBeVisible();
  });
});

// --- The agent may be left with no chat inbox ----------------------------------

test.describe('The agent may be left with no chat inbox', () => {
  test('The only inbox is removed', async ({ browser, page }) => {
    const shop = await newStore('only');
    const connected = await connectedByApp(shop);
    const view = await openAiPage(page, shop);

    await untick(view, shop.chat.inbox_id);
    await view.getByTestId('inclamo-ai-save').click();
    const dialog = changeDialog(page);
    await expect(dialog.getByTestId('inclamo-ai-change-calls-only')).toBeVisible();
    await dialog.getByRole('button', { name: 'Save' }).click();

    await expect(view.getByTestId('inclamo-ai-calls-only')).toBeVisible({ timeout: 30_000 });
    await expect(view.getByTestId('inclamo-ai-state')).toHaveAttribute('data-state', 'connected');
    expect((await aiConnection(shop)).connection.inbox_ids).toEqual([]);
    expect(await changesOf(shop)).toEqual([[[], 'accepted']]);
    // A finished call is still filed in Phone, with the agent's own token.
    const call = await standIn.call(callFixture('resolved-inbound', { call_id: `e2e-${run}-inboxes-only`, caller: { phone: '+12025550171' } }), shop.accountId);
    expect(call.status, JSON.stringify(call.body)).toBe(201);
    expect((await conversationOf(shop, call.body.conversation_id)).inbox_id).toBe(connected.phone_inbox_id);
    const id = await shopperWrites(browser, shop, shop.chat.website_token, `A chat message with no agent ${run}`);
    await expectWithTheTeam(shop, id);
    made.only = shop;
  });
});

// --- Only an inbox the agent can take is added ------------------------------------

test.describe('Only an inbox the agent can take is added', () => {
  test('An inbox that has another bot', async () => {
    const shop = await newStore('otherbot');
    await connectedByCode(shop, [shop.chat.inbox_id]);
    const email = await emailInbox(shop);
    const other = (await shop.account.post('/agent_bots', { name: `E2E other bot ${run}`, outgoing_url: '' })).body;
    expect((await shop.account.post(`/inboxes/${email.id}/set_agent_bot`, { agent_bot: other.id })).status).toBeLessThan(300);
    const site = await siteInbox(shop);

    const answer = await saveInboxes(shop, [shop.chat.inbox_id, site.id, email.id]);

    expect([answer.status, answer.body.error]).toEqual([422, 'inbox_has_bot']);
    expect(await botOfInbox(shop, site.id)).toBeNull();
    expect(await botOfInbox(shop, email.id)).toBe(other.id);
    expect((await aiConnection(shop)).connection.inbox_ids).toEqual([shop.chat.inbox_id]);
    expect(await changesOf(shop)).toEqual([]);
    const listed = (await aiConnection(shop)).inboxes.find(inbox => inbox.id === email.id);
    expect(listed).toMatchObject({ selectable: false, other_bot: 'Agent Bot' });
  });

  test('The Phone inbox', async () => {
    const shop = made.app;
    const before = (await aiConnection(shop)).connection;

    const answer = await saveInboxes(shop, [shop.chat.inbox_id, before.phone_inbox_id]);

    expect([answer.status, answer.body.error]).toEqual([422, 'invalid_inbox']);
    expect(sorted((await aiConnection(shop)).connection.inbox_ids)).toEqual(sorted(before.inbox_ids));
    expect(await botOfInbox(shop, before.phone_inbox_id)).toBeNull();
  });

  test('A storefront inbox made again and ticked by hand', async ({ browser, page }) => {
    const shop = await newStore('byhand');
    await deleteInbox(shop, shop.chat.inbox_id);
    const again = await storeApp.storefrontChat(shop.domain);
    expect([again.status, again.body.outcome]).toEqual([201, 'created']);
    expect(await botOfInbox(shop, again.body.inbox_id)).toBeNull();
    const email = await emailInbox(shop);
    await connectedByCode(shop, [email.id]);
    const view = await openAiPage(page, shop);

    await tick(view, again.body.inbox_id);
    await view.getByTestId('inclamo-ai-save').click();

    await expect(view.getByTestId(`inclamo-ai-connected-${again.body.inbox_id}`)).toBeVisible({ timeout: 30_000 });
    const text = `The storefront chat made again ${run}`;
    const id = await shopperWrites(browser, shop, again.body.website_token, text);
    await expectWithTheAgent(shop, id, text);
  });
});

// --- A storefront inbox made again gets the agent by itself -----------------------

test.describe('A storefront inbox made again gets the agent by itself', () => {
  test('Made again while the agent is connected', async ({ browser }) => {
    const shop = await newStore('again');
    await connectedByApp(shop);
    await deleteInbox(shop, shop.chat.inbox_id);

    const again = await storeApp.storefrontChat(shop.domain);

    expect([again.status, again.body.outcome]).toEqual([201, 'created']);
    const bots = await botsOf(shop);
    expect(await botOfInbox(shop, again.body.inbox_id)).toBe(bots[0].id);
    expect(await changesOf(shop)).toEqual([[[again.body.inbox_id], 'accepted']]);
    expect((await storeApp.agentStatus(shop.domain)).body.inbox_ids).toEqual([again.body.inbox_id]);
    const text = `Back in the new storefront chat ${run}`;
    const id = await shopperWrites(browser, shop, again.body.website_token, text);
    await expectWithTheAgent(shop, id, text);
  });

  test('The AI service does not accept', async ({ browser, page }) => {
    const shop = await newStore('notaccepted');
    await connectedByApp(shop);
    await deleteInbox(shop, shop.chat.inbox_id);
    await standIn.inboxSwitch({ mode: 'refuse', status: 422, error: 'plan_limit', message: 'One inbox on this plan.', account_id: shop.accountId });

    const again = await storeApp.storefrontChat(shop.domain);

    expect([again.status, again.body.outcome]).toEqual([201, 'created']);
    expect(await botOfInbox(shop, again.body.inbox_id)).toBeNull();
    expect(await changesOf(shop)).toEqual([[[again.body.inbox_id], 'refused']]);
    const id = await shopperWrites(browser, shop, again.body.website_token, `The new chat stays with the team ${run}`);
    await expectWithTheTeam(shop, id);
    const view = await openAiPage(page, shop);
    await expect(view.getByTestId('inclamo-ai-change-error')).toHaveAttribute('data-error', 'storefront_not_added');
    await expect(view.getByTestId('inclamo-ai-change-error')).toContainText('could not be added');
  });

  test('Another new inbox', async () => {
    const shop = await newStore('another');
    await connectedByApp(shop);

    const email = await emailInbox(shop);

    expect(await botOfInbox(shop, email.id)).toBeNull();
    const mail = await emailArrives(shop, email.id);
    expect(mail.status).toBe('open');
    expect(await changesOf(shop)).toEqual([]);
    expect((await aiConnection(shop)).connection.inbox_ids).toEqual([shop.chat.inbox_id]);
    // Until an administrator ticks it.
    expect((await saveInboxes(shop, [shop.chat.inbox_id, email.id])).status).toBe(200);
    expect((await emailArrives(shop, email.id)).status).toBe('pending');
  });
});

// --- The AI service agrees to the new list before anything changes ---------------

test.describe('The AI service agrees to the new list before anything changes', () => {
  // The page tries to add the email inbox; the AI service does not accept it.
  async function tryToAdd(page, shop) {
    const view = await openAiPage(page, shop);
    await tick(view, shop.email.id);
    await view.getByTestId('inclamo-ai-save').click();
    return view;
  }

  async function expectUnchanged(view, shop) {
    await expect(view.getByTestId(`inclamo-ai-connected-${shop.email.id}`)).toHaveCount(0);
    await expect(view.getByTestId(`inclamo-ai-connected-${shop.chat.inbox_id}`)).toBeVisible();
    expect((await aiConnection(shop)).connection.inbox_ids).toEqual([shop.chat.inbox_id]);
    expect(await botOfInbox(shop, shop.email.id)).toBeNull();
    expect(await statusOf(shop, shop.waiting)).toBe('pending');
  }

  test('The AI service refuses', async ({ browser, page }) => {
    const shop = await newStore('refuses');
    await connectedByApp(shop);
    const waiting = await shopperWrites(browser, shop, shop.chat.website_token, `Waiting for the agent ${run}`);
    made.agrees = { ...shop, email: await emailInbox(shop), waiting };
    await standIn.inboxSwitch({ mode: 'refuse', status: 422, error: 'plan_limit', message: 'One inbox on this plan.', account_id: shop.accountId });

    const view = await tryToAdd(page, made.agrees);

    await expect(view.getByTestId('inclamo-ai-error')).toHaveText('One inbox on this plan.', { timeout: 30_000 });
    await expectUnchanged(view, made.agrees);
  });

  test('The AI service does not answer', async ({ page }) => {
    const shop = made.agrees;
    await standIn.inboxSwitch({ mode: 'silent', delay_ms: 15_000, account_id: shop.accountId });
    const started = Date.now();

    const view = await tryToAdd(page, shop);

    await expect(view.getByTestId('inclamo-ai-error')).toContainText('did not answer', { timeout: 30_000 });
    expect(Date.now() - started).toBeLessThan(25_000);
    await expectUnchanged(view, shop);
  });

  test('The AI service does not know the call', async ({ page }) => {
    const shop = made.agrees;
    await standIn.inboxSwitch({ mode: 'unknown', account_id: shop.accountId });

    const view = await tryToAdd(page, shop);

    await expect(view.getByTestId('inclamo-ai-error')).toContainText('This AI service cannot change inboxes', { timeout: 30_000 });
    await expect(view.getByTestId('inclamo-ai-error')).toContainText('Disconnect and connect again');
    await expectUnchanged(view, shop);
  });

  test('The same list is saved again', async () => {
    const shop = made.agrees;
    const asked = (await changesOf(shop)).length;

    const answer = await saveInboxes(shop, [shop.chat.inbox_id]);

    expect(answer.status).toBe(200);
    expect(answer.body.connection.inbox_ids).toEqual([shop.chat.inbox_id]);
    expect(await changesOf(shop)).toHaveLength(asked);
  });
});

// --- A change is never left half done ------------------------------------------------

test.describe('A change is never left half done', () => {
  test('Two administrators save at the same moment', async () => {
    const shop = await newStore('together');
    await connectedByApp(shop);
    const email = await emailInbox(shop);
    const site = await siteInbox(shop);
    const second = await member(shop, users.secondAdmin, 'administrator');
    try {
      // The AI service takes three seconds to accept, so the first change still holds the connection.
      await standIn.inboxSwitch({ mode: 'accept', delay_ms: 3_000, account_id: shop.accountId });

      const first = saveInboxes(shop, [shop.chat.inbox_id, email.id]);
      await new Promise(resolve => setTimeout(resolve, 1_000));
      const other = await second.api.patch('/inclamo/ai/connection', { inbox_ids: [shop.chat.inbox_id, site.id] });
      const applied = await first;

      expect(applied.status, JSON.stringify(applied.body)).toBe(200);
      expect([other.status, other.body.error]).toEqual([409, 'busy']);
      expect(sorted((await aiConnection(shop)).connection.inbox_ids)).toEqual(sorted([shop.chat.inbox_id, email.id]));
      expect(await botOfInbox(shop, site.id)).toBeNull();
      expect(await changesOf(shop)).toEqual([[sorted([shop.chat.inbox_id, email.id]), 'accepted']]);
    } finally {
      await second.leave();
    }
  });
});

// --- The store app sees the agent's inboxes as they are ---------------------------

test.describe("The store app sees the agent's inboxes as they are", () => {
  test('The app asks after a change on the page', async () => {
    const shop = made.app;

    const answer = await storeApp.agentStatus(shop.domain);

    expect(answer.status).toBe(200);
    expect(answer.body).toMatchObject({ state: 'connected', connected_via: 'app' });
    expect(sorted(answer.body.inbox_ids)).toEqual(sorted([shop.chat.inbox_id, shop.email.id]));
  });
});
