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
// due, and looks for due erasures every few seconds, not once a day
// (dev/docker-compose.e2e.yaml); the tests wait for that time to pass. The
// requirements about one shopper are not built in this revision, and the
// restore from a backup cannot be done to the installation the tests drive:
// those scenarios are named, with the reason, in the coverage checker.
import { test, expect } from '@playwright/test';
import { storeApp, storefrontUrl, unprovisionedUrl, signInWith, setPassword, personApi } from '../lib/app.mjs';
import { eventually } from '../lib/helpdesk.mjs';
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
  return { name, domain: store(name), admin, accountId: answer.body.account_id, api, account: api.within(answer.body.account_id) };
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
