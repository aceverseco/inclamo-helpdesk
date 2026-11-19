// Scenarios of behavior contract `app-store-erasure`, grouped by requirement.
// Each test is named after its scenario; scripts/check-e2e-coverage.mjs relies
// on that.
//
// The store app is the stand-in of e2e/stand-in-app: it signs the calls of
// docs/app-provisioning.md, docs/app-storefront-chat.md and
// docs/app-store-erasure.md with the stack's secret, and serves a storefront
// page that loads the chat widget with the values the helpdesk answered. The
// stores are invented `myshopify.com` domains of this run and the people are
// created by the calls themselves, so no account or user of the other files is
// touched.
//
// The stack waits half a minute, not a week, before a scheduled erasure comes
// due, a minute and a half, not 14 days, before a shopper's data is deleted
// automatically, and looks for due erasures every few seconds, not once a day
// (dev/docker-compose.e2e.yaml); the tests wait for that time to pass. What
// needs the installation's clock moved by days (a reminder, a request a month
// old), a look into a table no page shows, or a restore from a backup cannot
// be done to the installation the tests drive: those scenarios are named,
// with where they are covered, in the coverage checker.
import { test, expect } from '@playwright/test';
import { storeApp, storefrontUrl, unprovisionedUrl, signInWith, setPassword, personApi } from '../lib/app.mjs';
import { eventually, signIn, manageTab } from '../lib/helpdesk.mjs';
import { storeBrowser, pngBytes } from '../lib/website.mjs';

test.use(storeBrowser);

const run = (process.env.E2E_RUN || 'local').toLowerCase().replace(/[^a-z0-9]/g, '');
const store = name => `e2e-${run}-erase-${name}.myshopify.com`;
const person = name => ({ email: `e2e-${run}-erase-${name}@example.test`, name: `E2E Erase ${name}` });
const password = name => `Own-${name}-Passw0rd!`;
const helpdesk = (process.env.HELPDESK_URL || 'http://localhost:3000').replace(/\/$/, '');
const UNAUTHORIZED = { error: 'unauthorized' };
const NO_ACCOUNT = { error: 'no_account' };
const BROWSER = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
// The stack's own waiting time and the interval of its daily run, with room.
const PAST_THE_DATE = 15_000;
const ERASED_WITHIN = 150_000;

// What the tests learn on the way and later ones use.
const made = {};

// A new store whose administrator has set a password.
async function newStore(name, personName = name) {
  const admin = person(personName);
  const answer = await storeApp.provision(store(name), { shop: { name: `Erase ${name} ${run}` }, admin });
  expect(answer.status).toBe(201);
  if (answer.body.password_setup_url) expect(await setPassword(answer.body.password_setup_url, password(personName))).toBe(200);
  const api = await personApi(admin.email, password(personName));
  return { name, personName, domain: store(name), admin, accountId: answer.body.account_id, api, account: api.within(answer.body.account_id) };
}

const contactCount = async (api, accountId) => (await api.get(`/api/v1/accounts/${accountId}/contacts`)).body?.meta?.count;

// An outgoing message with a photo, sent as the dashboard sends it; answers the message.
async function messageWithPhoto(shop, conversationId) {
  const session = await signInWith(shop.admin.email, password(shop.adminName || shop.name));
  const form = new FormData();
  form.append('content', `A photo for ${run}`);
  form.append('message_type', 'outgoing');
  form.append('attachments[]', new Blob([pngBytes('box-front')], { type: 'image/png' }), 'box-front.png');
  const response = await fetch(`${helpdesk}/api/v1/accounts/${shop.accountId}/conversations/${conversationId}/messages`, {
    method: 'POST',
    headers: session.headers,
    body: form,
  });
  expect(response.status).toBe(200);
  return response.json();
}

// What the helpdesk answers for a stored file: a redirect to it while it is
// there, 404 once it is gone.
const fileStatus = async url => (await fetch(url, { redirect: 'manual' })).status;

// What Chatwoot answers a page that asks for the widget frame with a token.
const widgetFrame = async token =>
  (await fetch(`${helpdesk}/widget?website_token=${encodeURIComponent(token)}`, { headers: { 'User-Agent': BROWSER } })).status;

// Waits until the date the helpdesk gave has passed, and the daily run with it.
async function pastTheDate(eraseAfter) {
  const wait = Date.parse(eraseAfter) - Date.now() + PAST_THE_DATE;
  if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait));
}

test.describe.configure({ mode: 'serial' });

test.describe('Erasure requests come only from the app', () => {
  test('An unsigned request to erase a store', async () => {
    const oak = await newStore('oak');
    await oak.api.fill(oak.accountId, 3, `${run}-oak`);
    expect((await storeApp.removal(oak.domain)).body.state).toBe('suspended');
    made.oak = oak;

    for (const switches of [{ wrong_signature: true }, { stale: true }]) {
      const answer = await storeApp.erasure(oak.domain, switches);
      expect([answer.status, answer.body, answer.provisioning]).toEqual([401, UNAUTHORIZED, '1']);
    }
    // A request id the app used for another request is refused too.
    const first = await storeApp.status(oak.domain);
    const reused = await storeApp.erasure(oak.domain, { request_id: first.request_id });
    expect([reused.status, reused.body]).toEqual([409, { error: 'request_id_reused' }]);

    // The account is as it was: suspended, not scheduled (the first accepted
    // request below gets the full waiting time from its own moment).
    expect((await storeApp.status(oak.domain)).body).toMatchObject({ account_id: oak.accountId, state: 'suspended' });
    made.oak.refusedAt = Date.now();
  });

  test('A self-hosted installation', async () => {
    const elsewhere = { helpdesk_url: unprovisionedUrl() };
    expect((await fetch(`${unprovisionedUrl()}/api`)).status).toBe(200);

    for (const switches of [elsewhere, { ...elsewhere, wrong_signature: true }]) {
      const answers = [
        await storeApp.erasure(made.oak.domain, switches),
        await storeApp.shopperErasure(made.oak.domain, { shopper: { email: 'pat@example.com' }, ...switches }),
        await storeApp.dataRequest(made.oak.domain, { shopper: { email: 'pat@example.com' }, ...switches }),
        await storeApp.shopperRequests(made.oak.domain, switches),
      ];
      expect(answers.map(answer => answer.status)).toEqual([404, 404, 404, 404]);
      for (const answer of answers) {
        expect(answer.provisioning).toBeNull();
        expect(answer.body?.state).toBeUndefined();
      }
    }
    // Both helpdesks share one database: nothing was scheduled through the other one.
    expect((await storeApp.status(made.oak.domain)).body.state).toBe('suspended');
  });
});

test.describe("A store's erasure is scheduled, not immediate", () => {
  test('The first request', async () => {
    const answer = await storeApp.erasure(made.oak.domain);

    expect(answer.status).toBe(200);
    expect(answer.provisioning).toBe('1');
    expect(Object.keys(answer.body).sort()).toEqual(['contract', 'erase_after', 'state']);
    expect(answer.body).toMatchObject({ contract: 1, state: 'scheduled' });
    const eraseAfter = Date.parse(answer.body.erase_after);
    expect(eraseAfter).toBeGreaterThan(made.oak.refusedAt);
    expect(eraseAfter).toBeLessThanOrEqual(Date.now() + 7 * 24 * 3600 * 1000);
    // Still the same account, suspended and whole: "A reinstall inside the
    // waiting time" finds its three conversations when it is back.
    expect((await storeApp.status(made.oak.domain)).body).toMatchObject({ account_id: made.oak.accountId, state: 'suspended' });
    made.oak.eraseAfter = answer.body.erase_after;
  });

  test('The request is repeated', async () => {
    const answer = await storeApp.erasure(made.oak.domain);

    expect([answer.status, answer.body]).toEqual([200, { contract: 1, state: 'scheduled', erase_after: made.oak.eraseAfter }]);
  });

  test('A store without an account', async () => {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const answer = await storeApp.erasure(store('never'));
      expect([answer.status, answer.body, answer.provisioning]).toEqual([200, { contract: 1, state: 'none' }, '1']);
    }
    expect((await storeApp.status(store('never'))).body).toEqual(NO_ACCOUNT);
  });
});

test.describe('An active account is never erased by this channel', () => {
  test('The store has reinstalled before the request arrives', async () => {
    const elm = await newStore('elm');

    const answer = await storeApp.erasure(elm.domain);

    expect([answer.status, answer.body, answer.provisioning]).toEqual([409, { error: 'account_active' }, '1']);
    expect((await storeApp.status(elm.domain)).body).toMatchObject({ account_id: elm.accountId, state: 'active' });
    expect(await elm.api.opens(elm.accountId)).toBe(200);
  });

  test('A reinstall inside the waiting time', async () => {
    test.setTimeout(120_000);
    const { oak } = made;
    expect(Date.parse(oak.eraseAfter)).toBeGreaterThan(Date.now());

    const answer = await storeApp.provision(oak.domain, { admin: oak.admin });
    expect(answer.body).toMatchObject({ account_id: oak.accountId, outcome: 'restored', state: 'active' });

    await pastTheDate(oak.eraseAfter);
    expect((await storeApp.status(oak.domain)).body).toMatchObject({ account_id: oak.accountId, state: 'active' });
    expect(await oak.api.opens(oak.accountId)).toBe(200);
    expect(await oak.api.conversationCount(oak.accountId)).toBe(3);
    // The withdrawn erasure is not what a request now finds.
    expect((await storeApp.erasure(oak.domain)).body).toEqual({ error: 'account_active' });
  });
});

test.describe('A due erasure destroys the account and everything in it', () => {
  test('The date passes', async () => {
    test.setTimeout(240_000);
    // Ash is administered by Arlo, who has no other account, and by Wren, who
    // also administers Willow.
    const ash = await newStore('ash', 'arlo');
    const willow = await newStore('willow', 'wren');
    expect((await storeApp.removal(ash.domain)).body.state).toBe('suspended');
    const restored = await storeApp.provision(ash.domain, { admin: willow.admin });
    expect(restored.body).toMatchObject({ account_id: ash.accountId, outcome: 'restored' });

    const chat = await storeApp.storefrontChat(ash.domain);
    expect(chat.status).toBe(200);
    await ash.api.fill(ash.accountId, 2, `${run}-ash`);
    const [conversation] = (await ash.account.get('/conversations?status=all&assignee_type=all')).body.data.payload;
    const message = await messageWithPhoto({ ...ash, adminName: 'arlo' }, conversation.id);
    const fileUrl = message.attachments[0].data_url;
    expect(await fileStatus(fileUrl)).toBe(302);
    expect(await contactCount(ash.api, ash.accountId)).toBe(2);
    made.ash = { ...ash, token: chat.body.website_token, fileUrl, willow };

    expect((await storeApp.removal(ash.domain)).body.state).toBe('suspended');
    const scheduled = await storeApp.erasure(ash.domain);
    expect(scheduled.body.state).toBe('scheduled');
    await pastTheDate(scheduled.body.erase_after);

    const erased = await eventually(() => storeApp.erasure(ash.domain), answer => answer.body?.state === 'erased', { timeout: ERASED_WITHIN, every: 3_000 });

    expect(erased.status).toBe(200);
    expect(Object.keys(erased.body).sort()).toEqual(['contract', 'erased_at', 'state']);
    expect(Date.parse(erased.body.erased_at)).toBeGreaterThanOrEqual(Date.parse(scheduled.body.erase_after));
    expect((await storeApp.status(ash.domain)).body).toEqual(NO_ACCOUNT);
    // The account is gone with its conversations, contacts and files: its
    // stored photo is no longer served, and nobody can open the account.
    expect(await fileStatus(fileUrl)).toBe(404);
    const wren = await personApi(person('wren').email, password('wren'));
    expect(await wren.opens(ash.accountId)).not.toBe(200);
    expect((await wren.get(`/api/v1/accounts/${ash.accountId}/contacts`)).status).not.toBe(200);
    made.ash.erasedAt = erased.body.erased_at;
    // Asking again answers the same, and the removal finds no account.
    expect((await storeApp.erasure(ash.domain)).body).toEqual({ contract: 1, state: 'erased', erased_at: made.ash.erasedAt });
    expect((await storeApp.removal(ash.domain)).body).toEqual({ contract: 1, state: 'none' });
  });

  test('The widget of an erased store', async ({ browser }) => {
    const { ash } = made;

    expect(await widgetFrame(ash.token)).toBe(404);
    const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
    const page = await context.newPage();
    await page.goto(storefrontUrl(ash.domain));
    // The storefront still carries the old token, and shows no chat.
    expect(await page.content()).toContain(ash.token);
    await page.waitForTimeout(6_000);
    expect(await page.evaluate(() => window.$chatwoot?.hasLoaded === true)).toBe(false);
    await expect(page.locator('#cw-bubble-holder .woot-widget-bubble:not(.woot--close)')).toHaveCount(0);
    await context.close();
  });
});

test.describe('The people of an erased account', () => {
  test('A user of one account', async () => {
    expect((await signInWith(person('arlo').email, password('arlo'))).status).toBe(401);

    // The email is free: a new store's request for it creates a new user, who
    // gets the password link and an account of their own.
    const birch = await storeApp.provision(store('birch'), { shop: { name: `Erase birch ${run}` }, admin: person('arlo') });
    expect(birch.status).toBe(201);
    expect(birch.body.password_setup_url).toBeTruthy();
    expect(await setPassword(birch.body.password_setup_url, password('arlo-again'))).toBe(200);
    const arlo = await personApi(person('arlo').email, password('arlo-again'));
    expect((await arlo.accounts()).map(account => account.id)).toEqual([birch.body.account_id]);
  });

  test('A user of two stores', async () => {
    const { ash } = made;
    const wren = await personApi(person('wren').email, password('wren'));

    expect(await wren.accounts()).toEqual([expect.objectContaining({ id: ash.willow.accountId, role: 'administrator' })]);
    expect(await wren.opens(ash.willow.accountId)).toBe(200);
    expect(await wren.opens(ash.accountId)).not.toBe(200);
  });
});

test.describe("What is kept after a store's erasure", () => {
  test('Installing again after erasure', async () => {
    const { ash } = made;
    const admin = person('iris');

    const answer = await storeApp.provision(ash.domain, { shop: { name: `Erase ash again ${run}` }, admin });

    expect(answer.status).toBe(201);
    expect(answer.body).toMatchObject({ outcome: 'created', state: 'active', admin_is_member: true });
    expect(answer.body.account_id).not.toBe(ash.accountId);
    expect(await setPassword(answer.body.password_setup_url, password('iris'))).toBe(200);
    const iris = await personApi(admin.email, password('iris'));
    expect(await iris.conversationCount(answer.body.account_id)).toBe(0);
    expect(await contactCount(iris, answer.body.account_id)).toBe(0);
    // A later request about the store answers by the new account's state.
    expect((await storeApp.erasure(ash.domain)).body).toEqual({ error: 'account_active' });
    // The new account has a storefront chat of its own, not the erased one's.
    const chat = await storeApp.storefrontChat(ash.domain);
    expect(chat.body.website_token).not.toBe(ash.token);
  });
});

// --- Requests about one shopper --------------------------------------------------
//
// Each shopper is a contact with an email and a phone and a few conversations
// in an API inbox of a store's account, made through the account's own API.
// A ticket is a conversation of the account's "Data requests" inbox; its card
// reads its request from the helpdesk.

// Past a shopper's date: the stack's daily run comes every few seconds.
const SHOPPER_PAST_THE_DATE = 15_000;
const DELETED_WITHIN = 90_000;

let shopperSerial = 0;
async function shopperIn(shop, name, conversations = 2) {
  const { account } = shop;
  if (!shop.chatInbox) shop.chatInbox = (await account.post('/inboxes', { name: 'Store chat', channel: { type: 'api', webhook_url: '' } })).body;
  shopperSerial += 1;
  const email = `${name}-${run}@shoppers.example.test`;
  const phone = `+1555${String(Date.now()).slice(-5)}${String(shopperSerial).padStart(2, '0')}`;
  const made = await account.post('/contacts', { inbox_id: shop.chatInbox.id, name: `Shopper ${name}`, email, phone_number: phone });
  expect(made.status, JSON.stringify(made.body)).toBe(200);
  const { contact, contact_inbox: contactInbox } = made.body.payload;
  const conversationIds = [];
  for (let index = 1; index <= conversations; index += 1) {
    const created = await account.post('/conversations', {
      source_id: contactInbox.source_id,
      inbox_id: shop.chatInbox.id,
      contact_id: contact.id,
      message: { content: `Question ${index} from ${name}`, message_type: 'incoming' },
    });
    expect(created.status).toBe(200);
    conversationIds.push(created.body.id);
  }
  return { name, email, phone, contactId: contact.id, sourceId: contactInbox.source_id, conversationIds };
}

const dataRequestsInbox = async shop => ((await shop.account.get('/inboxes')).body.payload || []).find(inbox => inbox.name === 'Data requests');
async function tickets(shop) {
  const inbox = await dataRequestsInbox(shop);
  if (!inbox) return [];
  return (await shop.account.get(`/conversations?inbox_id=${inbox.id}&status=all&assignee_type=all`)).body.data.payload;
}
// The ticket the store's latest request made.
const newestTicket = async shop => (await tickets(shop)).sort((one, other) => other.id - one.id)[0];
const requestIdOf = ticket => ticket.custom_attributes.inclamo_shopper_request_id;
const card = (shop, ticket) => shop.account.get(`/inclamo/shopper_requests/${requestIdOf(ticket)}`);
const act = (shop, ticket, action, body = {}) => shop.account.post(`/inclamo/shopper_requests/${requestIdOf(ticket)}/${action}`, body);
const messagesOfTicket = async (shop, ticket) => (await shop.account.get(`/conversations/${ticket.id}/messages`)).body.payload || [];
const contactExists = async (shop, id) => (await shop.account.get(`/contacts/${id}`)).status === 200;
const conversationExists = async (shop, id) => (await shop.account.get(`/conversations/${id}`)).status === 200;
const goneWithin = async (shop, contactId, conversationIds) =>
  eventually(
    async () => [await contactExists(shop, contactId), ...(await Promise.all(conversationIds.map(id => conversationExists(shop, id))))],
    found => found.every(exists => !exists),
    { timeout: DELETED_WITHIN, every: 3_000 }
  );
// None of the administrator's notifications is about a ticket: a ticket's
// notes, made by the helpdesk or a colleague, notify nobody.
async function noTicketNotifications(shop) {
  const inbox = await dataRequestsInbox(shop);
  const notifications = (await shop.api.get(`/api/v1/accounts/${shop.accountId}/notifications`)).body?.data?.payload || [];
  expect(notifications.filter(notification => notification.primary_actor?.inbox_id === inbox.id)).toEqual([]);
}
async function pastShopperDate(deleteAfter) {
  const wait = Date.parse(deleteAfter) - Date.now() + SHOPPER_PAST_THE_DATE;
  if (wait > 0) await new Promise(resolve => setTimeout(resolve, wait));
}

// The "Data request" section of the ticket's sidebar, opened by the store's
// administrator the way a person would.
const cardHeader = page => page.locator('button.drag-handle').filter({ has: page.locator('h5', { hasText: /^Data request$/ }) });
async function openTicket(page, shop, ticket) {
  // A new account's administrator first meets Chatwoot's own first-run form;
  // it is finished here the way that form finishes it.
  if (!shop.onboarded) {
    expect((await shop.account.patch('/onboarding', { onboarding_step: 'account_details' })).status).toBe(200);
    shop.onboarded = true;
  }
  await signIn(page, { email: shop.admin.email, password: password(shop.personName) });
  await page.goto(`/app/accounts/${shop.accountId}/conversations/${ticket.id}`);
  await manageTab(page);
  await cardHeader(page).first().waitFor({ state: 'visible', timeout: 30_000 });
  const section = page.getByTestId('inclamo-shopper-request');
  if (!(await section.isVisible())) await cardHeader(page).first().click();
  await section.waitFor({ state: 'visible', timeout: 30_000 });
  await expect(section.getByTestId('inclamo-shopper-request-kind')).toBeVisible({ timeout: 30_000 });
  return section;
}

test.describe('A request to erase one shopper becomes a ticket', () => {
  test('A shopper with two conversations', async () => {
    const maple = await newStore('maple');
    const pat = await shopperIn(maple, 'pat', 2);

    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: pat.email, phone: pat.phone }, order_ids: ['299938'] });

    expect([answer.status, answer.provisioning]).toEqual([200, '1']);
    expect(Object.keys(answer.body).sort()).toEqual(['contacts', 'contract', 'conversations', 'delete_after', 'state']);
    expect(answer.body).toMatchObject({ contract: 1, state: 'waiting', contacts: 1, conversations: 2 });
    expect(Date.parse(answer.body.delete_after)).toBeGreaterThan(Date.now());
    const all = await tickets(maple);
    expect(all).toHaveLength(1);
    const [ticket] = all;
    expect(ticket).toMatchObject({ status: 'open', labels: ['inclamo_erasure_request'] });
    const note = (await messagesOfTicket(maple, ticket)).find(message => message.private);
    expect(note.content).toContain('1 contact and 2 conversations');
    expect(note.content).toContain(answer.body.delete_after.slice(0, 10));
    expect(note.content).not.toContain(pat.email);
    expect((await card(maple, ticket)).body).toMatchObject({
      kind: 'shopper_erasure', state: 'waiting', email: pat.email, phone: pat.phone, delete_after: answer.body.delete_after,
      contacts: [{ id: pat.contactId, conversations: 2 }],
    });
    // The request itself deleted nothing.
    expect(await contactExists(maple, pat.contactId)).toBe(true);
    for (const id of pat.conversationIds) expect(await conversationExists(maple, id)).toBe(true);
    made.maple = { ...maple, pat, ticket, deleteAfter: answer.body.delete_after };
  });

  test('The request is repeated', async () => {
    const { maple } = made;

    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: maple.pat.email, phone: maple.pat.phone }, order_ids: ['299938'] });

    expect([answer.status, answer.body]).toEqual([200, { contract: 1, state: 'waiting', contacts: 1, conversations: 2, delete_after: maple.deleteAfter }]);
    expect(await tickets(maple)).toHaveLength(1);
  });

  test("The same email in another store's account", async () => {
    const { maple } = made;
    const rowan = await newStore('rowan');
    rowan.chatInbox = (await rowan.account.post('/inboxes', { name: 'Store chat', channel: { type: 'api', webhook_url: '' } })).body;
    const theirs = (await rowan.account.post('/contacts', { inbox_id: rowan.chatInbox.id, name: 'Shopper pat elsewhere', email: maple.pat.email })).body.payload.contact;

    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: maple.pat.email, phone: maple.pat.phone }, order_ids: ['299938'] });

    expect(answer.body).toMatchObject({ state: 'waiting', contacts: 1, conversations: 2 });
    expect(await dataRequestsInbox(rowan)).toBeUndefined();
    expect((await rowan.account.get(`/contacts/${theirs.id}`)).body.payload).toMatchObject({ id: theirs.id, email: maple.pat.email, name: 'Shopper pat elsewhere' });
    made.rowan = { ...rowan, theirs };
  });

  test('A shopper the helpdesk does not know', async () => {
    const { maple } = made;
    const before = await maple.api.conversationCount(maple.accountId);

    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: `nobody-${run}@shoppers.example.test`, phone: '+15550000000' } });

    expect([answer.status, answer.body]).toEqual([200, { contract: 1, state: 'none', contacts: 0 }]);
    expect(await tickets(maple)).toHaveLength(1);
    expect(await maple.api.conversationCount(maple.accountId)).toBe(before);
  });

  test('Neither email nor phone', async () => {
    const { maple } = made;

    for (const shopper of [{}, { email: '', phone: '  ' }]) {
      const answer = await storeApp.shopperErasure(maple.domain, { shopper });
      expect([answer.status, answer.body?.error, answer.provisioning]).toEqual([422, 'shopper_missing', '1']);
    }
    expect(await tickets(maple)).toHaveLength(1);
  });
});

test.describe("Data-request tickets and erasure tickets are the administrators'", () => {
  test('An agent of the team', async () => {
    const { maple } = made;
    // Kai has a password and a store of their own; Maple's administrator adds
    // Kai as an agent, with the inbox the shopper wrote to.
    const kaiStore = await newStore('kai-own', 'kai');
    const added = await maple.account.post('/agents', { email: kaiStore.admin.email, name: kaiStore.admin.name, role: 'agent' });
    expect(added.status, JSON.stringify(added.body)).toBe(200);
    expect((await maple.account.post('/inbox_members', { inbox_id: maple.chatInbox.id, user_ids: [added.body.id] })).status).toBe(200);
    const kai = (await personApi(kaiStore.admin.email, password('kai'))).within(maple.accountId);

    const listed = (await kai.get('/conversations?status=all&assignee_type=all')).body.data.payload.map(conversation => conversation.id);

    expect(listed).toEqual(expect.arrayContaining(maple.pat.conversationIds));
    expect(listed).not.toContain(maple.ticket.id);
    expect((await kai.get(`/conversations/${maple.ticket.id}`)).status).not.toBe(200);
    const read = await kai.get(`/inclamo/shopper_requests/${requestIdOf(maple.ticket)}`);
    expect(read.status).toBe(403);
    expect(JSON.stringify(read.body)).not.toContain(maple.pat.email);
    const refused = await kai.post(`/inclamo/shopper_requests/${requestIdOf(maple.ticket)}/delete`, {});
    expect([refused.status, refused.body?.error]).toEqual([403, 'forbidden']);
    expect(await contactExists(maple, maple.pat.contactId)).toBe(true);
  });

  test('An administrator opens the ticket', async ({ page }) => {
    const { maple } = made;
    const ann = await shopperIn(maple, 'ann', 1);
    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: ann.email, phone: ann.phone } });
    expect(answer.body.state).toBe('waiting');
    const ticket = await newestTicket(maple);

    const section = await openTicket(page, maple, ticket);

    await expect(section.getByTestId('inclamo-shopper-request-kind')).toHaveText("Shopify asked to erase one shopper's data");
    await expect(section.getByTestId('inclamo-shopper-request-email')).toContainText(ann.email);
    await expect(section.getByTestId('inclamo-shopper-request-phone')).toContainText(ann.phone);
    const link = section.getByTestId(`inclamo-shopper-request-contact-${ann.contactId}`);
    await expect(link).toContainText('Shopper ann');
    await expect(link).toHaveAttribute('href', new RegExp(`/app/accounts/${maple.accountId}/contacts/${ann.contactId}$`));
    await expect(section.getByTestId('inclamo-shopper-request-date')).toContainText('Deleted automatically on');
    await expect(section.getByTestId('inclamo-shopper-request-delete')).toHaveText('Delete');
    await expect(section.getByTestId('inclamo-shopper-request-hold')).toHaveText('Hold');
    await expect(section.getByTestId('inclamo-shopper-request-lift')).toHaveCount(0);
    // Kept in the run's output for review; not published by CI.
    await page.screenshot({ path: `${process.env.E2E_OUTPUT || './output'}/shopper-request-card.png` });
    await noTicketNotifications(maple);
  });
});

test.describe("An administrator deletes the shopper's data from the ticket", () => {
  test('Delete from the ticket', async ({ page }) => {
    const { maple } = made;
    const dot = await shopperIn(maple, 'dot', 2);
    const message = await messageWithPhoto({ ...maple, adminName: 'maple' }, dot.conversationIds[0]);
    const fileUrl = message.attachments[0].data_url;
    expect(await fileStatus(fileUrl)).toBe(302);
    expect((await storeApp.shopperErasure(maple.domain, { shopper: { email: dot.email, phone: dot.phone } })).body.state).toBe('waiting');
    const ticket = await newestTicket(maple);
    // A colleague writes the shopper's email into a note of the ticket ("Reading a done ticket").
    const note = await maple.account.post(`/conversations/${ticket.id}/messages`, { content: `Called ${dot.email.toUpperCase()} back`, private: true, message_type: 'outgoing' });
    expect(note.status).toBe(200);

    const section = await openTicket(page, maple, ticket);
    await section.getByTestId('inclamo-shopper-request-delete').click();
    const dialog = page.locator('dialog[open]');
    await expect(dialog.getByTestId('inclamo-shopper-request-delete-dialog')).toContainText('Contacts: 1. Conversations: 2.');
    await dialog.getByRole('button', { name: 'Delete', exact: true }).click();

    await expect(section.getByTestId('inclamo-shopper-request-done')).toContainText(`Done by ${maple.admin.name}`, { timeout: 30_000 });
    await goneWithin(maple, dot.contactId, dot.conversationIds);
    expect(await fileStatus(fileUrl)).toBe(404);
    const read = (await card(maple, ticket)).body;
    expect(read).toMatchObject({ state: 'done', done: { by: 'team', user: { name: maple.admin.name } } });
    expect(Date.parse(read.done.at)).toBeLessThanOrEqual(Date.now());
    const last = (await messagesOfTicket(maple, ticket)).filter(one => one.private).pop();
    expect(last.content).toMatch(new RegExp(`^Done: ${maple.admin.name} deleted the shopper's data on \\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2} UTC\\.$`));
    made.dot = { ...dot, ticket };
  });

  test('The shopper wrote again after the ticket was made', async () => {
    const { maple } = made;
    const eve = await shopperIn(maple, 'eve', 1);
    expect((await storeApp.shopperErasure(maple.domain, { shopper: { email: eve.email } })).body).toMatchObject({ state: 'waiting', conversations: 1 });
    const ticket = await newestTicket(maple);
    const again = await maple.account.post('/conversations', {
      source_id: eve.sourceId, inbox_id: maple.chatInbox.id, contact_id: eve.contactId, message: { content: 'Me again', message_type: 'incoming' },
    });
    expect(again.status).toBe(200);

    const deleted = await act(maple, ticket, 'delete');

    expect([deleted.status, deleted.body.state]).toEqual([200, 'done']);
    await goneWithin(maple, eve.contactId, [...eve.conversationIds, again.body.id]);
  });
});

test.describe('An administrator can hold the deletion with a reason', () => {
  test('A hold with a reason', async ({ page }) => {
    test.setTimeout(300_000);
    const { maple } = made;
    // Tickets of later scenarios, made now so that their dates pass during
    // the wait below: one held at once, and one in an account that is then
    // suspended.
    const lee = await shopperIn(maple, 'lee', 1);
    expect((await storeApp.shopperErasure(maple.domain, { shopper: { email: lee.email } })).body.state).toBe('waiting');
    const leeTicket = await newestTicket(maple);
    expect((await act(maple, leeTicket, 'hold', { reason: 'checking a refund' })).body.state).toBe('held');
    made.lee = { ...lee, ticket: leeTicket };
    const fir = await newStore('fir');
    const sam = await shopperIn(fir, 'sam', 1);
    expect((await storeApp.shopperErasure(fir.domain, { shopper: { email: sam.email } })).body.state).toBe('waiting');
    expect((await storeApp.removal(fir.domain)).body.state).toBe('suspended');
    made.fir = { ...fir, sam };

    const hal = await shopperIn(maple, 'hal', 2);
    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: hal.email, phone: hal.phone } });
    const ticket = await newestTicket(maple);
    const section = await openTicket(page, maple, ticket);
    await section.getByTestId('inclamo-shopper-request-hold').click();
    const dialog = page.locator('dialog[open]');
    const confirm = dialog.getByRole('button', { name: 'Hold', exact: true });
    await expect(confirm).toBeDisabled();
    await dialog.getByTestId('inclamo-shopper-request-reason').fill('open payment dispute');
    await confirm.click();
    await expect(section.getByTestId('inclamo-shopper-request-held')).toContainText(`Held by ${maple.admin.name}`, { timeout: 30_000 });
    await expect(section.getByTestId('inclamo-shopper-request-held-reason')).toHaveText('Reason: open payment dispute');

    await pastShopperDate(answer.body.delete_after);

    expect(await contactExists(maple, hal.contactId)).toBe(true);
    for (const id of hal.conversationIds) expect(await conversationExists(maple, id)).toBe(true);
    const read = (await card(maple, ticket)).body;
    expect(read).toMatchObject({ state: 'held', email: hal.email, hold: { reason: 'open payment dispute', held_by: { name: maple.admin.name } } });
    expect(Date.parse(read.hold.held_at)).toBeLessThan(Date.parse(answer.body.delete_after));
    // The app's counts say two are held and none wait: every other ticket of
    // the store was deleted, by an administrator or after its date.
    const counts = await storeApp.shopperRequests(maple.domain);
    expect([counts.status, counts.body]).toEqual([
      200,
      { contract: 1, erasures: { waiting: 0, held: 2, overdue: 0 }, data_requests: { waiting: 0, overdue: 0 }, account_state: 'active' },
    ]);
    made.hal = { ...hal, ticket };
    await noTicketNotifications(maple);
  });

  test('A hold without a reason', async () => {
    const { maple } = made;
    const kit = await shopperIn(maple, 'kit', 1);
    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: kit.email } });
    const ticket = await newestTicket(maple);

    for (const reason of ['', '   ']) {
      const refused = await act(maple, ticket, 'hold', { reason });
      expect([refused.status, refused.body]).toEqual([422, { error: 'reason_missing' }]);
    }

    expect((await card(maple, ticket)).body).toMatchObject({ state: 'waiting', delete_after: answer.body.delete_after, hold: null });
  });

  test('The hold is lifted after the date', async () => {
    const { maple, lee } = made;
    // Its date passed while the hold stood.
    expect((await card(maple, lee.ticket)).body.state).toBe('held');
    expect(await contactExists(maple, lee.contactId)).toBe(true);

    const lifted = await act(maple, lee.ticket, 'lift');

    expect([lifted.status, lifted.body.state]).toEqual([200, 'waiting']);
    const done = await eventually(() => card(maple, lee.ticket), read => read.body?.state === 'done', { timeout: 60_000, every: 2_000 });
    expect(done.body.done).toMatchObject({ by: 'automatic', user: null });
    await goneWithin(maple, lee.contactId, lee.conversationIds);
  });
});

test.describe('Without a decision the helpdesk deletes after the waiting time', () => {
  test('Nobody touched the ticket', async () => {
    const { maple, rowan } = made;

    const done = await eventually(() => card(maple, maple.ticket), read => read.body?.state === 'done', { timeout: 60_000, every: 2_000 });

    expect(done.body).toMatchObject({ email: null, phone: null, done: { by: 'automatic', user: null } });
    await goneWithin(maple, maple.pat.contactId, maple.pat.conversationIds);
    const last = (await messagesOfTicket(maple, maple.ticket)).filter(one => one.private).pop();
    expect(last.content).toContain('nobody deleted or held, so the helpdesk deleted');
    expect((await storeApp.shopperErasure(maple.domain, { shopper: { email: maple.pat.email, phone: maple.pat.phone } })).body)
      .toMatchObject({ state: 'done', done_by: 'automatic' });
    // The same email in another store's account is as it was.
    expect(await contactExists(rowan, rowan.theirs.id)).toBe(true);
  });

  test('A suspended account', async () => {
    const { fir } = made;

    // Nobody can open the ticket of a suspended account; the app's repeated
    // request finds it done all the same.
    const answer = await eventually(() => storeApp.shopperErasure(fir.domain, { shopper: { email: fir.sam.email } }), one => one.body?.state === 'done', {
      timeout: 60_000, every: 3_000,
    });

    expect(answer.body).toMatchObject({ contract: 1, state: 'done', done_by: 'automatic' });
    // Installing the app again shows the shopper's contact and conversation are gone.
    expect((await storeApp.provision(fir.domain, { admin: fir.admin })).body).toMatchObject({ outcome: 'restored', account_id: fir.accountId });
    expect(await contactExists(fir, fir.sam.contactId)).toBe(false);
    expect(await conversationExists(fir, fir.sam.conversationIds[0])).toBe(false);
  });
});

test.describe('A finished ticket holds no shopper data', () => {
  test('Reading a done ticket', async ({ page }) => {
    const { maple, dot } = made;

    const section = await openTicket(page, maple, dot.ticket);

    await expect(section.getByTestId('inclamo-shopper-request-done')).toContainText(`Done by ${maple.admin.name}`);
    await expect(section.getByTestId('inclamo-shopper-request-email')).toHaveCount(0);
    await expect(page.getByText('Called [removed] back')).toBeVisible({ timeout: 30_000 });
    const shown = (await page.locator('body').innerText()).toLowerCase();
    expect(shown).not.toContain(dot.email.toLowerCase());
    expect(shown).not.toContain(dot.phone);
    const stored = JSON.stringify([await messagesOfTicket(maple, dot.ticket), (await card(maple, dot.ticket)).body]).toLowerCase();
    expect(stored).not.toContain(dot.email.toLowerCase());
    expect(stored).not.toContain(dot.phone);
  });
});

test.describe("A request for one shopper's data becomes a ticket", () => {
  test('A known shopper', async () => {
    const { maple } = made;
    const jo = await shopperIn(maple, 'jo', 3);

    const answer = await storeApp.dataRequest(maple.domain, { shopper: { email: jo.email, phone: jo.phone }, order_ids: ['1001'] });

    expect([answer.status, answer.body]).toEqual([200, { contract: 1, state: 'waiting', contacts: 1, conversations: 3, account_state: 'active' }]);
    const raw = JSON.stringify(answer.body);
    for (const text of [jo.email, jo.phone, 'Shopper jo', 'Question', '/contacts/']) expect(raw).not.toContain(text);
    const ticket = await newestTicket(maple);
    expect(ticket.labels).toEqual(['inclamo_data_request']);
    expect((await card(maple, ticket)).body).toMatchObject({
      kind: 'shopper_data_request', state: 'waiting', email: jo.email, contacts: [{ id: jo.contactId, conversations: 3 }],
    });
    expect((await messagesOfTicket(maple, ticket)).find(message => message.private).content).toContain('1 contact and 3 conversations');
    for (const id of jo.conversationIds) expect(await conversationExists(maple, id)).toBe(true);
    made.jo = { ...jo, ticket };
  });

  test('An unknown shopper', async () => {
    const { maple } = made;
    const before = (await tickets(maple)).length;

    const answer = await storeApp.dataRequest(maple.domain, { shopper: { email: `nobody-${run}@shoppers.example.test` } });

    expect([answer.status, answer.body]).toEqual([200, { contract: 1, state: 'none', contacts: 0, conversations: 0 }]);
    expect(await tickets(maple)).toHaveLength(before);
  });

  test('The team has answered', async ({ page }) => {
    const { maple, jo } = made;
    let section = await openTicket(page, maple, jo.ticket);
    // The link leads to the contact the team answers from.
    await section.getByTestId(`inclamo-shopper-request-contact-${jo.contactId}`).click();
    await page.waitForURL(new RegExp(`/contacts/${jo.contactId}`), { timeout: 30_000 });

    section = await openTicket(page, maple, jo.ticket);
    await section.getByTestId('inclamo-shopper-request-answered').click();
    const dialog = page.locator('dialog[open]');
    await dialog.getByRole('button', { name: 'Mark answered', exact: true }).click();

    await expect(section.getByTestId('inclamo-shopper-request-done')).toContainText(`Done by ${maple.admin.name}`, { timeout: 30_000 });
    await expect(section.getByTestId('inclamo-shopper-request-email')).toHaveCount(0);
    expect((await section.innerText()).toLowerCase()).not.toContain(jo.email.toLowerCase());
    const closed = await eventually(() => maple.account.get(`/conversations/${jo.ticket.id}`), read => read.body?.status === 'resolved');
    expect(closed.body.status).toBe('resolved');
    expect((await card(maple, jo.ticket)).body).toMatchObject({ state: 'done', email: null, phone: null });
    // Nothing was deleted.
    expect(await contactExists(maple, jo.contactId)).toBe(true);
  });
});

test.describe('The app learns the state of requests without shopper data', () => {
  test('Asking about a held request', async () => {
    const { maple, hal } = made;

    const answer = await storeApp.shopperErasure(maple.domain, { shopper: { email: hal.email, phone: hal.phone } });

    expect(answer.status).toBe(200);
    expect(Object.keys(answer.body).sort()).toEqual(['contract', 'held_at', 'state']);
    expect(answer.body).toMatchObject({ contract: 1, state: 'held' });
    const raw = JSON.stringify(answer.body);
    for (const text of ['payment dispute', maple.admin.name, maple.admin.email, hal.email, hal.phone]) expect(raw).not.toContain(text);
  });
});
