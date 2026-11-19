// Scenarios of behavior contract `app-storefront-chat`, grouped by
// requirement. Each test is named after its scenario;
// scripts/check-e2e-coverage.mjs relies on that.
//
// The store app is the stand-in of e2e/stand-in-app: it signs the calls of
// docs/app-provisioning.md and docs/app-storefront-chat.md with the stack's
// secret, and serves a storefront page that loads the chat widget with the two
// values the helpdesk answered, as the app's theme embed would. The stores are
// invented `myshopify.com` domains of this run and the people are created by
// the calls themselves, so nothing here asks Shopify anything and no user or
// inbox of the other files is touched.
import { test, expect } from '@playwright/test';
import { storeApp, storefrontUrl, unprovisionedUrl, setPassword, personApi } from '../lib/app.mjs';
import { signIn, eventually } from '../lib/helpdesk.mjs';
import { storeBrowser, waitForWidget, published, widgetConfig, websiteInbox } from '../lib/website.mjs';

test.use(storeBrowser);

const run = (process.env.E2E_RUN || 'local').toLowerCase().replace(/[^a-z0-9]/g, '');
const store = name => `e2e-${run}-chat-${name}.myshopify.com`;
const person = name => ({ email: `e2e-${run}-chat-${name}@example.test`, name: `E2E ${name[0].toUpperCase()}${name.slice(1)}` });
const password = name => `Own-${name}-Passw0rd!`;
const helpdesk = (process.env.HELPDESK_URL || 'http://localhost:3000').replace(/\/$/, '');
const UNAUTHORIZED = { error: 'unauthorized' };
const NO_ACCOUNT = { error: 'no_account' };
const NO_CHAT = { error: 'no_storefront_chat' };
const BROWSER = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const ANSWER_KEYS = ['contract', 'inbox_id', 'state', 'website_token', 'widget_base_url'];

// What the tests learn on the way and later ones use.
const made = {};

// A new store whose administrator has set a password: the account, the person
// and their API inside the account.
async function newStore(name, shop = {}) {
  const admin = person(name);
  const shopName = `Store ${name} ${run}`;
  const answer = await storeApp.provision(store(name), { shop: { name: shopName, ...shop }, admin });
  expect(answer.status).toBe(201);
  expect(await setPassword(answer.body.password_setup_url, password(name))).toBe(200);
  const api = await personApi(admin.email, password(name));
  return { name, domain: store(name), shopName, admin, answer, accountId: answer.body.account_id, api, account: api.within(answer.body.account_id) };
}

const inboxesOf = async account => (await account.get('/inboxes')).body.payload || [];
const websiteInboxesOf = async account => (await inboxesOf(account)).filter(inbox => inbox.channel_type === 'Channel::WebWidget');
const conversationsOf = async (account, inboxId) =>
  (await account.get(`/conversations?inbox_id=${inboxId}&status=all&assignee_type=all`)).body?.data?.payload || [];
const incomingOf = async (account, conversationId) =>
  ((await account.get(`/conversations/${conversationId}/messages`)).body.payload || []).filter(message => message.message_type === 0).map(message => message.content);

// The administrator deletes an inbox in the dashboard's own way; Chatwoot
// removes it in the background, so the test waits until it is gone.
async function deleteInbox(shop, inboxId) {
  expect((await shop.account.delete(`/inboxes/${inboxId}`)).status).toBe(200);
  await eventually(() => inboxesOf(shop.account), inboxes => !inboxes.some(inbox => inbox.id === inboxId), { timeout: 60_000 });
}

// A new store whose team deleted the storefront inbox it was created with.
async function storeWithoutChat(name) {
  const shop = await newStore(name);
  const [inbox] = await websiteInboxesOf(shop.account);
  await deleteInbox(shop, inbox.id);
  await eventually(() => storeApp.storefrontChatStatus(shop.domain), answer => answer.status === 404);
  return shop;
}

// A shopper on the store's storefront page. `context` continues an earlier
// visit: the widget knows a returning shopper by a cookie of the store's page.
async function shopperOn(browser, domain, { context, expectWidget = true } = {}) {
  const own = context || (await browser.newContext({ viewport: { width: 1280, height: 900 } }));
  const page = own.pages()[0] || (await own.newPage());
  await page.goto(storefrontUrl(domain));
  if (expectWidget) await waitForWidget(page);
  return {
    context: own,
    page,
    widget: page.frameLocator('#chatwoot_live_chat_widget'),
    launcher: page.locator('#cw-bubble-holder .woot-widget-bubble:not(.woot--close)'),
    holder: page.locator('#cw-widget-holder'),
    close: () => own.close(),
  };
}

// The page asked for the widget and was given none: no launcher appears.
async function expectNoChat(shopper) {
  await shopper.page.waitForTimeout(6_000);
  expect(await shopper.page.evaluate(() => window.$chatwoot?.hasLoaded === true)).toBe(false);
  await expect(shopper.launcher).toHaveCount(0);
}

// The shopper opens the chat and sends their first message.
async function writeFirstMessage(shopper, text) {
  await shopper.launcher.click();
  await expect(shopper.holder).toBeVisible();
  await shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true }).click();
  await shopper.widget.locator('#chat-input').fill(text);
  await shopper.widget.locator('#chat-input').press('Enter');
  await expect(shopper.widget.getByText(text, { exact: true })).toBeVisible();
}

// What Chatwoot answers a page that asks for the widget frame with a token.
const widgetFrame = async token =>
  (await fetch(`${helpdesk}/widget?website_token=${encodeURIComponent(token)}`, { headers: { 'User-Agent': BROWSER } })).status;

test.describe.configure({ mode: 'serial' });

test.describe('A new account has its storefront inbox', () => {
  test('The account is created', async () => {
    const shop = await newStore('maple', { name: `Maple & Oak ${run}` });
    shop.shopName = `Maple & Oak ${run}`;

    // The call that created the account says nothing of the inbox.
    expect(Object.keys(shop.answer.body).sort()).toEqual(['account_id', 'contract', 'created_at', 'helpdesk_url', 'outcome', 'password_setup_url', 'state']);

    // The account has one inbox: a website inbox named after the store, at the
    // store's own Shopify address, with the administrator as its member.
    const inboxes = await inboxesOf(shop.account);
    expect(inboxes).toHaveLength(1);
    expect(inboxes[0]).toMatchObject({ channel_type: 'Channel::WebWidget', name: shop.shopName, website_url: `https://${shop.domain}` });
    const members = (await shop.account.get(`/inbox_members/${inboxes[0].id}`)).body.payload || [];
    expect(members.map(member => member.email)).toEqual([shop.admin.email]);

    // The app asks for the chat and learns the token of that inbox.
    const answer = await storeApp.storefrontChat(shop.domain);
    expect(answer.status).toBe(200);
    expect(answer.body).toEqual({
      contract: 1, inbox_id: inboxes[0].id, website_token: inboxes[0].website_token, widget_base_url: helpdesk, state: 'active', outcome: 'existed',
    });
    made.maple = { ...shop, inboxId: inboxes[0].id, token: inboxes[0].website_token };
  });

  test('A restored account whose inbox was deleted', async () => {
    const shop = await storeWithoutChat('restored');
    expect((await storeApp.removal(shop.domain)).body.state).toBe('suspended');

    const answer = await storeApp.provision(shop.domain, { admin: shop.admin });

    expect([answer.status, answer.body.outcome, answer.body.state]).toEqual([200, 'restored', 'active']);
    expect(await shop.api.opens(shop.accountId)).toBe(200);
    // No storefront inbox until the app asks for one.
    const status = await storeApp.storefrontChatStatus(shop.domain);
    expect([status.status, status.body]).toEqual([404, NO_CHAT]);
    expect(await inboxesOf(shop.account)).toEqual([]);
    made.restored = shop;
  });
});

test.describe("The app's request finds or makes the storefront inbox", () => {
  test('An account without a storefront inbox', async () => {
    const shop = made.restored;

    const answer = await storeApp.storefrontChat(shop.domain, { storefront_url: `https://restored-${run}.example/collections/all?sort=price` });

    expect(answer.status).toBe(201);
    expect(answer.body).toMatchObject({ contract: 1, widget_base_url: helpdesk, state: 'active', outcome: 'created' });
    expect(answer.body.website_token).toBeTruthy();
    const inboxes = await inboxesOf(shop.account);
    expect(inboxes).toHaveLength(1);
    // Named after the account, with the origin of the named address.
    expect(inboxes[0]).toMatchObject({
      id: answer.body.inbox_id, channel_type: 'Channel::WebWidget', name: shop.shopName,
      website_token: answer.body.website_token, website_url: `https://restored-${run}.example`,
    });
    made.restored.inboxId = answer.body.inbox_id;
  });

  test('No storefront address is given', async () => {
    const shop = made.restored;
    await deleteInbox(shop, shop.inboxId);

    const answer = await storeApp.storefrontChat(shop.domain);

    expect([answer.status, answer.body.outcome]).toEqual([201, 'created']);
    const inboxes = await inboxesOf(shop.account);
    expect(inboxes).toHaveLength(1);
    expect(inboxes[0]).toMatchObject({ id: answer.body.inbox_id, website_url: `https://${shop.domain}` });
  });

  test('A shopper writes through the answered values', async ({ browser }) => {
    const shop = made.maple;
    const text = `Do you ship to Canada? ${run}`;
    expect(await conversationsOf(shop.account, shop.inboxId)).toEqual([]);

    // The stand-in's storefront page carries the two values of the answer and
    // nothing else of the helpdesk.
    const shopper = await shopperOn(browser, shop.domain);
    const source = await shopper.page.content();
    expect(source).toContain(shop.token);
    expect(source).toContain(`var BASE_URL = "${helpdesk}";`);
    expect(source).not.toContain('chatwootSettings');
    expect(await shopper.page.evaluate(() => window.$chatwoot.position)).toBe('right');
    await writeFirstMessage(shopper, text);

    const conversations = await eventually(() => conversationsOf(shop.account, shop.inboxId), list => list.length === 1);
    expect(conversations[0].inbox_id).toBe(shop.inboxId);
    expect(await incomingOf(shop.account, conversations[0].id)).toEqual([text]);
    Object.assign(made.maple, { shopper, text, conversationId: conversations[0].id });
  });

  test('The storefront address does not read', async () => {
    const shop = await storeWithoutChat('unread');

    for (const address of [`http://unread-${run}.example`, `unread-${run}.example`, `//unread-${run}.example`, '/collections/all', '']) {
      const answer = await storeApp.storefrontChat(shop.domain, { storefront_url: address });
      expect(answer.status).toBe(422);
      expect(answer.body.error).toBe('storefront_url_invalid');
      expect(answer.body.message).toBeTruthy();
      expect(answer.body.website_token).toBeUndefined();
    }
    expect((await storeApp.storefrontChatStatus(shop.domain)).body).toEqual(NO_CHAT);
    expect(await inboxesOf(shop.account)).toEqual([]);
    made.unread = shop;
  });
});

test.describe('An account has one storefront inbox', () => {
  test('The request is repeated', async () => {
    const shop = made.maple;

    for (const options of [{}, { storefront_url: `https://another-${run}.example` }]) {
      const answer = await storeApp.storefrontChat(shop.domain, options);
      expect(answer.status).toBe(200);
      expect(answer.body).toMatchObject({ inbox_id: shop.inboxId, website_token: shop.token, outcome: 'existed', state: 'active' });
    }
    // The store is the same store whatever the case of its letters.
    const upper = await storeApp.storefrontChat(shop.domain.toUpperCase());
    expect([upper.status, upper.body.inbox_id, upper.body.outcome]).toEqual([200, shop.inboxId, 'existed']);
    expect((await websiteInboxesOf(shop.account)).map(inbox => inbox.id)).toEqual([shop.inboxId]);
  });

  test('The team changed the inbox', async () => {
    const shop = made.maple;
    const changed = { name: `Chat with the workshop ${run}`, greeting_enabled: true, greeting_message: 'Hello from the workshop' };
    const patched = await shop.account.patch(`/inboxes/${shop.inboxId}`, { ...changed, channel: { website_url: `https://workshop-${run}.example` } });
    expect(patched.status).toBe(200);

    const answer = await storeApp.storefrontChat(shop.domain, { storefront_url: `https://another-${run}.example` });

    expect(answer.status).toBe(200);
    expect(answer.body).toMatchObject({ inbox_id: shop.inboxId, website_token: shop.token, outcome: 'existed' });
    const inbox = (await shop.account.get(`/inboxes/${shop.inboxId}`)).body;
    expect(inbox).toMatchObject({ ...changed, website_url: `https://workshop-${run}.example`, website_token: shop.token });
    made.maple.inboxName = changed.name;
  });

  test('The team has a website inbox of their own', async () => {
    const shop = await storeWithoutChat('own');
    const own = await websiteInbox(shop.account, `Our other site ${run}`, { website_url: `https://other-site-${run}.example` });
    expect((await storeApp.storefrontChatStatus(shop.domain)).body).toEqual(NO_CHAT);

    const answer = await storeApp.storefrontChat(shop.domain);

    expect([answer.status, answer.body.outcome]).toEqual([201, 'created']);
    expect(answer.body.inbox_id).not.toBe(own.id);
    expect(answer.body.website_token).not.toBe(own.website_token);
    // Theirs is as it was, and is in no answer.
    const inboxes = await websiteInboxesOf(shop.account);
    expect(inboxes.map(inbox => inbox.id).sort()).toEqual([own.id, answer.body.inbox_id].sort());
    expect(inboxes.find(inbox => inbox.id === own.id)).toMatchObject({ name: own.name, website_url: own.website_url, website_token: own.website_token });
    const again = [await storeApp.storefrontChat(shop.domain), await storeApp.storefrontChatStatus(shop.domain)];
    for (const one of again) expect(one.body).toMatchObject({ inbox_id: answer.body.inbox_id, website_token: answer.body.website_token });
    expect(JSON.stringify([answer.body, ...again.map(one => one.body)])).not.toContain(own.website_token);
  });

  test('Two requests at the same moment', async () => {
    const shop = await storeWithoutChat('twins');

    const answers = await Promise.all([1, 2].map(() => storeApp.storefrontChat(shop.domain)));

    expect(answers.map(answer => answer.status).sort()).toEqual([200, 201]);
    expect(answers.map(answer => answer.body.outcome).sort()).toEqual(['created', 'existed']);
    expect(answers[0].body.website_token).toBe(answers[1].body.website_token);
    expect((await websiteInboxesOf(shop.account)).map(inbox => inbox.website_token)).toEqual([answers[0].body.website_token]);
  });
});

test.describe('Only public values leave the helpdesk', () => {
  test('The answer is read', async () => {
    const shop = made.maple;
    const inbox = (await shop.account.get(`/inboxes/${shop.inboxId}`)).body;
    // The administrator can read the inbox's identity-verification key; the app cannot.
    expect(inbox.hmac_token).toBeTruthy();

    const asked = await storeApp.storefrontChat(shop.domain);
    const status = await storeApp.storefrontChatStatus(shop.domain);

    expect(Object.keys(asked.body).sort()).toEqual([...ANSWER_KEYS, 'outcome'].sort());
    expect(Object.keys(status.body).sort()).toEqual(ANSWER_KEYS);
    const text = JSON.stringify([asked.body, status.body]);
    for (const hidden of [inbox.hmac_token, shop.admin.email, shop.admin.name, shop.text, shop.inboxName, 'Hello from the workshop', 'workshop-']) {
      expect(text).not.toContain(hidden);
    }
  });
});

test.describe('The storefront inbox is an ordinary website inbox', () => {
  test('An administrator changes the launcher', async ({ browser }) => {
    const shop = made.maple;
    expect((await widgetConfig(shop.account, shop.inboxId)).settings.position).toBe('right');

    // Published as the website widget editor publishes it.
    await published(shop.account, shop.inboxId, value => {
      value.settings.position = 'left';
    });

    // A newly loaded widget with the same token, on a page nobody changed.
    const shopper = await shopperOn(browser, shop.domain);
    expect(await shopper.page.content()).toContain(shop.token);
    expect(await shopper.page.evaluate(() => window.$chatwoot.position)).toBe('left');
    await expect(shopper.launcher).toHaveClass(/woot-elements--left/);
    await shopper.close();
    // The app was not asked again and holds the same values.
    expect((await storeApp.storefrontChatStatus(shop.domain)).body.website_token).toBe(shop.token);
  });

  test('No agent is connected', async () => {
    const shop = made.maple;
    expect((await shop.account.get('/inclamo/ai/connection')).body.state).toBe('never_connected');
    expect((await shop.account.get(`/inboxes/${shop.inboxId}/agent_bot`)).body?.agent_bot?.id ?? null).toBeNull();

    // The shopper's conversation is open for the team; a bot would hold it as pending.
    const conversation = (await shop.account.get(`/conversations/${shop.conversationId}`)).body;
    expect(conversation.status).toBe('open');
    expect(conversation.meta?.assignee?.type ?? 'user').not.toBe('agent_bot');
    const senders = ((await shop.account.get(`/conversations/${shop.conversationId}/messages`)).body.payload || []).map(message => message.sender?.type);
    expect(senders).not.toContain('agent_bot');
  });

  test('An agent of the account sees the inbox', async ({ page }) => {
    const shop = made.maple;
    // The inbox is listed for its member, as any inbox of theirs.
    expect((await inboxesOf(shop.account)).map(inbox => [inbox.id, inbox.name])).toEqual([[shop.inboxId, shop.inboxName]]);

    // A new account's administrator first meets Chatwoot's own first-run form;
    // it is finished here the way that form finishes it.
    expect((await shop.account.patch('/onboarding', { onboarding_step: 'account_details' })).status).toBe(200);
    await signIn(page, { email: shop.admin.email, password: password(shop.name) });
    // The inbox is among the channels of the sidebar, and its conversation
    // list holds the shopper's conversation.
    await page.goto(`/app/accounts/${shop.accountId}/inbox/${shop.inboxId}`);
    await expect(page.getByRole('link', { name: shop.inboxName, exact: true })).toBeVisible({ timeout: 45_000 });
    await expect(page.getByRole('heading', { name: shop.inboxName, exact: true })).toBeVisible();
    const rows = page.locator('.reference-row-host');
    await expect(rows).toHaveCount(1);
    // And the conversation opens with what the shopper wrote.
    await rows.first().click();
    await expect(page).toHaveURL(new RegExp(`/conversations/${shop.conversationId}(\\D|$)`));
    await expect(page.locator('[data-message-id]').filter({ hasText: shop.text }).first()).toBeVisible({ timeout: 45_000 });
  });
});

test.describe('The app can ask about the storefront chat', () => {
  test('A store with its storefront inbox', async () => {
    const shop = made.maple;

    const answer = await storeApp.storefrontChatStatus(shop.domain);

    expect(answer.status).toBe(200);
    expect(answer.body).toEqual({ contract: 1, inbox_id: shop.inboxId, website_token: shop.token, widget_base_url: helpdesk, state: 'active' });
  });

  test('A store without one', async () => {
    const answer = await storeApp.storefrontChatStatus(made.unread.domain);

    expect([answer.status, answer.body]).toEqual([404, NO_CHAT]);
    // Asking made none.
    expect(await inboxesOf(made.unread.account)).toEqual([]);
  });
});

test.describe('A deleted storefront inbox is reported, not silently replaced', () => {
  test('An administrator deletes the inbox', async ({ browser }) => {
    const shop = await newStore('gone');
    const first = await storeApp.storefrontChat(shop.domain);
    expect(first.status).toBe(200);
    const shopper = await shopperOn(browser, shop.domain);
    await writeFirstMessage(shopper, `Before the inbox was deleted ${run}`);
    await eventually(() => conversationsOf(shop.account, first.body.inbox_id), list => list.length === 1);

    await deleteInbox(shop, first.body.inbox_id);

    const status = await eventually(() => storeApp.storefrontChatStatus(shop.domain), answer => answer.status === 404);
    expect(status.body).toEqual(NO_CHAT);
    // The storefront still carries the old token: it is answered as unknown and shows no chat.
    expect(await widgetFrame(first.body.website_token)).toBe(404);
    const stale = await shopperOn(browser, shop.domain, { context: shopper.context, expectWidget: false });
    expect(await stale.page.content()).toContain(first.body.website_token);
    await expectNoChat(stale);
    // Nothing was made in its place.
    expect(await inboxesOf(shop.account)).toEqual([]);
    made.gone = { ...shop, oldToken: first.body.website_token, oldInboxId: first.body.inbox_id, shopper };
  });

  test('The app asks for the inbox again', async ({ browser }) => {
    const shop = made.gone;

    const answer = await storeApp.storefrontChat(shop.domain);

    expect([answer.status, answer.body.outcome, answer.body.state]).toEqual([201, 'created', 'active']);
    expect(answer.body.website_token).not.toBe(shop.oldToken);
    expect(answer.body.inbox_id).not.toBe(shop.oldInboxId);
    // A new inbox without the earlier conversations, which the storefront now loads.
    expect(await conversationsOf(shop.account, answer.body.inbox_id)).toEqual([]);
    const shopper = await shopperOn(browser, shop.domain, { context: shop.shopper.context });
    const source = await shopper.page.content();
    expect(source).toContain(answer.body.website_token);
    expect(source).not.toContain(shop.oldToken);
    await expect(shopper.launcher).toBeVisible();
    await shopper.close();
  });
});

test.describe('A suspended account has no storefront chat', () => {
  test('The app was removed', async ({ browser }) => {
    const shop = made.maple;
    expect(await widgetFrame(shop.token)).toBe(200);
    made.maple.before = (await conversationsOf(shop.account, shop.inboxId)).length;
    expect(made.maple.before).toBe(1);

    expect((await storeApp.removal(shop.domain)).body.state).toBe('suspended');

    // The returning shopper's page asks for the widget with the same token and is refused.
    expect(await widgetFrame(shop.token)).toBe(401);
    const returning = await shopperOn(browser, shop.domain, { context: shop.shopper.context, expectWidget: false });
    expect(await returning.page.content()).toContain(shop.token);
    await expectNoChat(returning);
    // So is a message sent past the page, straight to the widget's own address.
    const direct = await fetch(`${helpdesk}/api/v1/widget/conversations?website_token=${shop.token}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ message: { content: 'Sent while suspended' } }),
    });
    expect(direct.status).toBe(401);
    // The app is told the widget would not be served; the inbox and its token are kept.
    const status = await storeApp.storefrontChatStatus(shop.domain);
    expect(status.body).toEqual({ contract: 1, inbox_id: shop.inboxId, website_token: shop.token, widget_base_url: helpdesk, state: 'suspended' });
  });

  test('A request for a suspended account', async () => {
    const shop = made.maple;

    const answer = await storeApp.storefrontChat(shop.domain, { storefront_url: `https://another-${run}.example` });

    expect([answer.status, answer.body]).toEqual([409, { error: 'account_suspended' }]);
    expect((await storeApp.storefrontChatStatus(shop.domain)).body).toMatchObject({ inbox_id: shop.inboxId, website_token: shop.token, state: 'suspended' });
  });

  test('The store returns', async ({ browser }) => {
    const shop = made.maple;
    const restored = await storeApp.provision(shop.domain, { admin: shop.admin });
    expect([restored.status, restored.body.outcome]).toEqual([200, 'restored']);

    // The same inbox and token; no conversation came of the suspended time.
    const answer = await storeApp.storefrontChat(shop.domain);
    expect(answer.body).toMatchObject({ inbox_id: shop.inboxId, website_token: shop.token, state: 'active', outcome: 'existed' });
    const conversations = await conversationsOf(shop.account, shop.inboxId);
    expect(conversations.map(conversation => conversation.id)).toEqual([shop.conversationId]);
    expect(await incomingOf(shop.account, shop.conversationId)).toEqual([shop.text]);

    // The widget opens again, and the shopper who wrote before finds their conversation.
    expect(await widgetFrame(shop.token)).toBe(200);
    const returning = await shopperOn(browser, shop.domain, { context: shop.shopper.context });
    await returning.launcher.click();
    await expect(returning.holder).toBeVisible();
    const earlier = returning.widget.getByText(shop.text, { exact: true });
    const resume = returning.widget.getByRole('button', { name: /^Continue conversation/i });
    await earlier.or(resume).first().waitFor({ timeout: 30_000 });
    if (!(await earlier.isVisible())) await resume.click();
    await expect(earlier).toBeVisible();
    await returning.close();
  });
});

test.describe("The storefront chat calls follow the provisioning channel's rules", () => {
  test('A request without a valid signature', async () => {
    const shop = made.unread;

    const refused = [
      await storeApp.storefrontChat(shop.domain, { wrong_signature: true }),
      await storeApp.storefrontChat(shop.domain, { stale: true }),
      await storeApp.storefrontChatStatus(shop.domain, { wrong_signature: true }),
      await storeApp.storefrontChatStatus(made.maple.domain, { wrong_signature: true }),
    ];

    for (const answer of refused) expect([answer.status, answer.body]).toEqual([401, UNAUTHORIZED]);
    // The account has no new inbox, and the store that has one told nothing of it.
    expect((await storeApp.storefrontChatStatus(shop.domain)).body).toEqual(NO_CHAT);
    expect(await inboxesOf(shop.account)).toEqual([]);
    // A request id is used once: the same id with another request is refused.
    const first = await storeApp.storefrontChatStatus(made.maple.domain);
    const reused = await storeApp.storefrontChat(shop.domain, { request_id: first.request_id });
    expect([reused.status, reused.body]).toEqual([401, UNAUTHORIZED]);
    expect(await inboxesOf(shop.account)).toEqual([]);
  });

  test('A store without an account', async () => {
    const asked = await storeApp.storefrontChat(store('nobody'), { storefront_url: `https://nobody-${run}.example` });
    const status = await storeApp.storefrontChatStatus(store('nobody'));

    expect([asked.status, asked.body]).toEqual([404, NO_ACCOUNT]);
    expect([status.status, status.body]).toEqual([404, NO_ACCOUNT]);
    // No account came of it.
    const account = await storeApp.status(store('nobody'));
    expect([account.status, account.body]).toEqual([404, NO_ACCOUNT]);
  });

  test('A self-hosted installation', async () => {
    const elsewhere = { helpdesk_url: unprovisionedUrl() };
    const shop = made.unread;
    // The other helpdesk is up and is this installation without the secret.
    expect((await fetch(`${unprovisionedUrl()}/api`)).status).toBe(200);

    for (const switches of [elsewhere, { ...elsewhere, wrong_signature: true }]) {
      const answers = [
        await storeApp.storefrontChat(shop.domain, switches),
        await storeApp.storefrontChatStatus(shop.domain, switches),
        await storeApp.storefrontChatStatus(made.maple.domain, switches),
      ];
      expect(answers.map(answer => answer.status)).toEqual([404, 404, 404]);
      for (const answer of answers) {
        expect(answer.body?.error).not.toBe('no_account');
        expect(answer.body?.error).not.toBe('no_storefront_chat');
        expect(answer.body?.website_token).toBeUndefined();
      }
    }

    // Nothing was created: both helpdesks share one database.
    expect((await storeApp.storefrontChatStatus(shop.domain)).body).toEqual(NO_CHAT);
    expect(await inboxesOf(shop.account)).toEqual([]);
  });
});
