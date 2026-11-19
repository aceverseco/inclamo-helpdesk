// Scenarios of behavior contract `app-provisioned-account`, grouped by
// requirement. Each test is named after its scenario;
// scripts/check-e2e-coverage.mjs relies on that.
//
// The store app is the stand-in of e2e/stand-in-app, which signs the three
// calls of docs/app-provisioning.md with the stack's secret. The stores are
// invented `myshopify.com` domains of this run: nothing here asks Shopify
// anything. The people are created by the calls themselves and get their
// passwords through the links the answers carry, so no user of the other
// files is touched.
//
// Three scenarios are not here, each named with its reason in the checker:
// the link's time passing, the request limits (the stack runs without
// Rack::Attack) and the record of attempts (no address shows it). The stand-in
// hands each answer's provisioning header to the test, so the mark that tells
// this installation's answers from an unknown address is checked here too.
import { test, expect } from '@playwright/test';
import { storeApp, unprovisionedUrl, signInWith, setPassword, personApi } from '../lib/app.mjs';

const run = (process.env.E2E_RUN || 'local').toLowerCase().replace(/[^a-z0-9]/g, '');
const store = name => `e2e-${run}-${name}.myshopify.com`;
const person = name => ({ email: `e2e-${run}-${name}@example.test`, name: `E2E ${name[0].toUpperCase()}${name.slice(1)}` });
const password = name => `Own-${name}-Passw0rd!`;
const helpdesk = (process.env.HELPDESK_URL || 'http://localhost:3000').replace(/\/$/, '');
const UNAUTHORIZED = { error: 'unauthorized' };
const NO_ACCOUNT = { error: 'no_account' };

// What the tests learn on the way and later ones use.
const made = {};

// A new store for a person the installation does not know, who then sets a
// password through the link of the answer.
async function storeWithAdministrator(storeName, personName, shop = {}) {
  const admin = person(personName);
  const answer = await storeApp.provision(store(storeName), { shop: { name: `Store ${storeName} ${run}`, ...shop }, admin });
  expect(answer.status).toBe(201);
  expect(await setPassword(answer.body.password_setup_url, password(personName))).toBe(200);
  return { answer, admin, accountId: answer.body.account_id, api: await personApi(admin.email, password(personName)) };
}

test.describe.configure({ mode: 'serial' });

test.describe("The app's request creates an account for a store", () => {
  test('A store without an account', async () => {
    const admin = person('alex');
    const name = `Maple & Oak ${run}`;
    const answer = await storeApp.provision(store('maple'), { shop: { name, locale: 'en', timezone: 'America/New_York' }, admin });

    expect(answer.status).toBe(201);
    expect(answer.body).toMatchObject({ contract: 1, helpdesk_url: helpdesk, state: 'active', outcome: 'created', admin_is_member: true });
    expect(answer.provisioning).toBe('1');
    expect(Number.isInteger(answer.body.account_id)).toBe(true);
    expect(Number.isNaN(Date.parse(answer.body.created_at))).toBe(false);

    // The staff member gets in (with the password of the answer's link) and
    // finds an account named after the store, theirs to administer.
    expect(await setPassword(answer.body.password_setup_url, password('alex'))).toBe(200);
    const alex = await personApi(admin.email, password('alex'));
    expect(await alex.accounts()).toEqual([expect.objectContaining({ id: answer.body.account_id, name, role: 'administrator' })]);
    expect(await alex.opens(answer.body.account_id)).toBe(200);
    made.maple = { accountId: answer.body.account_id, createdAt: answer.body.created_at, name, alex };
  });

  test('The email is not verified', async () => {
    const admin = person('unverified');
    for (const email_verified of [false, null, 'true']) {
      const answer = await storeApp.provision(store('unverified'), { admin: { ...admin, email_verified } });
      expect(answer.status).toBe(422);
      expect(answer.body.error).toBe('admin_email_unverified');
      expect(answer.body.message).toBeTruthy();
      expect(answer.body.account_id).toBeUndefined();
    }
    const status = await storeApp.status(store('unverified'));
    expect([status.status, status.body]).toEqual([404, NO_ACCOUNT]);
    // No user came of it: a later valid request for that person makes one,
    // which it tells by the password link it gives only to a person it created.
    const later = await storeApp.provision(store('verified-later'), { admin });
    expect(later.status).toBe(201);
    expect(later.body.password_setup_url).toBeTruthy();
  });

  test("The store's domain is not a Shopify domain", async () => {
    for (const domain of [`e2e-${run}.example.com`, `e2e-${run}.myshopify.com.example.com`]) {
      const answer = await storeApp.provision(domain, { admin: person('elsewhere') });
      expect(answer.status).toBe(422);
      expect(answer.body.error).toBe('shop_domain_invalid');
      expect(answer.body.message).toBeTruthy();
      expect((await storeApp.status(domain)).status).toBe(404);
    }
    // A body that names another store than the address does.
    const mixed = await storeApp.provision(store('address'), { shop: { domain: store('body') }, admin: person('elsewhere') });
    expect([mixed.status, mixed.body.error]).toEqual([422, 'shop_domain_invalid']);
    for (const name of ['address', 'body']) expect((await storeApp.status(store(name))).body).toEqual(NO_ACCOUNT);
    expect((await signInWith(person('elsewhere').email, password('elsewhere'))).status).toBe(401);
  });
});

test.describe('A store has one account', () => {
  test('The request is repeated', async () => {
    const answer = await storeApp.provision(store('maple'), { shop: { name: 'Another name' }, admin: person('alex') });

    expect(answer.status).toBe(200);
    expect(answer.body).toMatchObject({ account_id: made.maple.accountId, outcome: 'existed', state: 'active', created_at: made.maple.createdAt, admin_is_member: true });
    // Alex has signed in, so no new link either.
    expect(answer.body.password_setup_url).toBeUndefined();
    // One account for the store, under the name it had.
    expect(await made.maple.alex.accounts()).toEqual([expect.objectContaining({ id: made.maple.accountId, name: made.maple.name })]);
    // The store is the same store whatever the case of its letters.
    const upper = await storeApp.provision(store('maple').toUpperCase(), { shop: { domain: store('maple').toUpperCase() }, admin: person('alex') });
    expect([upper.status, upper.body.account_id, upper.body.outcome]).toEqual([200, made.maple.accountId, 'existed']);
  });

  test('Two requests at the same moment', async () => {
    const admin = person('twin');
    const answers = await Promise.all([1, 2].map(() => storeApp.provision(store('twins'), { shop: { name: `Twins ${run}` }, admin })));

    expect(answers.map(answer => answer.status).sort()).toEqual([200, 201]);
    expect(answers.map(answer => answer.body.outcome).sort()).toEqual(['created', 'existed']);
    expect(answers[0].body.account_id).toBe(answers[1].body.account_id);
    // The same person, who has not signed in yet: the later answer's link
    // replaced the first one.
    const link = outcome => answers.find(answer => answer.body.outcome === outcome).body.password_setup_url;
    expect(await setPassword(link('created'), password('twin'))).toBe(422);
    expect(await setPassword(link('existed'), password('twin'))).toBe(200);
    const twin = await personApi(admin.email, password('twin'));
    expect((await twin.accounts()).map(account => account.id)).toEqual([answers[0].body.account_id]);
  });

  test('Another person asks for a store that has an account', async () => {
    const answer = await storeApp.provision(store('maple'), { admin: person('sam') });

    expect(answer.status).toBe(200);
    expect(answer.body).toMatchObject({ account_id: made.maple.accountId, outcome: 'existed', admin_is_member: false });
    expect(answer.body.password_setup_url).toBeUndefined();
    expect(await made.maple.alex.members(made.maple.accountId)).toEqual([{ email: person('alex').email, role: 'administrator' }]);
  });
});

test.describe('The first administrator is the person the app names', () => {
  test('A person new to the installation', async () => {
    const admin = person('nina');
    const answer = await storeApp.provision(store('nina'), { shop: { name: `Nina's ${run}` }, admin });
    expect(answer.status).toBe(201);

    // No password signs them in before they set one. (That no letter is sent
    // is shown by the request specs: this stack has no mailbox to look into.)
    for (const guess of ['', 'password', 'Password1!', admin.email, admin.name]) {
      expect((await signInWith(admin.email, guess)).status).toBe(401);
    }
    expect(await setPassword(answer.body.password_setup_url, password('nina'))).toBe(200);
    const nina = await personApi(admin.email, password('nina'));
    expect(await nina.profile()).toMatchObject({ email: admin.email, name: admin.name, confirmed: true });
    expect(await nina.accounts()).toEqual([expect.objectContaining({ id: answer.body.account_id, role: 'administrator' })]);
    made.nina = { accountId: answer.body.account_id, api: nina };
  });

  test('A person the installation already knows', async () => {
    const admin = person('nina');
    const answer = await storeApp.provision(store('nina-second'), { shop: { name: `Nina's second ${run}` }, admin: { ...admin, name: 'Another Name' } });

    expect([answer.status, answer.body.outcome]).toEqual([201, 'created']);
    // The same password as before, the same name, and both accounts.
    const nina = await personApi(admin.email, password('nina'));
    expect((await nina.profile()).name).toBe(admin.name);
    const accounts = await nina.accounts();
    expect(accounts.map(account => [account.id, account.role]).sort()).toEqual(
      [
        [made.nina.accountId, 'administrator'],
        [answer.body.account_id, 'administrator'],
      ].sort()
    );
    expect(await nina.opens(made.nina.accountId)).toBe(200);
    expect(await nina.opens(answer.body.account_id)).toBe(200);
  });

  test('The app gives no name', async () => {
    for (const [index, name] of [null, ''].entries()) {
      const admin = { email: person(`nameless-${index}`).email, name };
      const answer = await storeApp.provision(store(`nameless-${index}`), { shop: { name: `Nameless ${index} ${run}` }, admin });
      expect([answer.status, answer.body.outcome]).toEqual([201, 'created']);

      expect(await setPassword(answer.body.password_setup_url, password(`nameless-${index}`))).toBe(200);
      const nameless = await personApi(admin.email, password(`nameless-${index}`));
      expect(await nameless.profile()).toMatchObject({ email: admin.email, name: admin.email });
      expect(await nameless.accounts()).toEqual([expect.objectContaining({ id: answer.body.account_id, role: 'administrator' })]);
    }
  });
});

test.describe('A new administrator can set a password of their own', () => {
  test('The new administrator sets a password', async ({ page }) => {
    const admin = person('paula');
    const answer = await storeApp.provision(store('paula'), { shop: { name: `Paula's ${run}` }, admin });
    expect(answer.status).toBe(201);
    expect(answer.body.password_setup_url.startsWith(`${helpdesk}/app/auth/password/edit?reset_password_token=`)).toBe(true);

    await page.goto(answer.body.password_setup_url);
    await page.locator('input[name="password"]').fill(password('paula'));
    await page.locator('input[name="confirm_password"]').fill(password('paula'));
    await page.locator('button[type="submit"]').click();
    await page.waitForURL(url => !url.pathname.includes('/auth/password'), { timeout: 45_000 });

    // The login page, as somebody who has only their email and that password.
    await page.context().clearCookies();
    await page.goto('/app/login');
    await page.locator('input[name="email_address"], input[type="email"]').fill(admin.email);
    await page.locator('input[type="password"]').fill(password('paula'));
    await page.locator('button[type="submit"]').click();
    await expect(page).toHaveURL(new RegExp(`/app/accounts/${answer.body.account_id}(/|$)`), { timeout: 45_000 });
    made.paula = { link: answer.body.password_setup_url, accountId: answer.body.account_id };
  });

  test('The link is used twice', async () => {
    const admin = person('paula');
    expect(await setPassword(made.paula.link, password('second'))).toBe(422);

    expect((await signInWith(admin.email, password('second'))).status).toBe(401);
    expect((await signInWith(admin.email, password('paula'))).status).toBe(200);
  });

  test('A person the installation already knew gets no link', async () => {
    const admin = person('paula');
    const answer = await storeApp.provision(store('paula-second'), { shop: { name: `Paula's second ${run}` }, admin });

    expect([answer.status, answer.body.outcome]).toEqual([201, 'created']);
    expect('password_setup_url' in answer.body).toBe(false);
    expect((await signInWith(admin.email, password('paula'))).status).toBe(200);
  });

  test('The first answer was lost', async () => {
    const admin = person('lucas');
    const first = await storeApp.provision(store('lucas'), { shop: { name: `Lucas ${run}` }, admin });
    expect(first.status).toBe(201);

    // The app never saw that answer and asks again under a new request id.
    const again = await storeApp.provision(store('lucas'), { shop: { name: `Lucas ${run}` }, admin });
    expect(again.status).toBe(200);
    expect(again.body).toMatchObject({ account_id: first.body.account_id, outcome: 'existed', admin_is_member: true });
    expect(again.body.password_setup_url).toBeTruthy();
    expect(again.body.password_setup_url).not.toBe(first.body.password_setup_url);

    expect(await setPassword(first.body.password_setup_url, password('lucas'))).toBe(422);
    expect(await setPassword(again.body.password_setup_url, password('lucas'))).toBe(200);
    const lucas = await personApi(admin.email, password('lucas'));
    expect(await lucas.accounts()).toEqual([expect.objectContaining({ id: first.body.account_id, role: 'administrator' })]);

    // Once they have signed in, nobody gets a link for them any more.
    const later = await storeApp.provision(store('lucas'), { admin });
    expect([later.status, later.body.outcome, later.body.admin_is_member]).toEqual([200, 'existed', true]);
    expect(later.body.password_setup_url).toBeUndefined();
  });
});

test.describe('Only the app can ask', () => {
  test('A request without a valid signature', async () => {
    const answer = await storeApp.provision(store('forged'), { admin: person('forger'), wrong_signature: true });
    expect([answer.status, answer.body, answer.provisioning]).toEqual([401, UNAUTHORIZED, '1']);

    for (const call of ['status', 'removal']) {
      const refused = await storeApp[call](store('maple'), { wrong_signature: true });
      expect([refused.status, refused.body]).toEqual([401, UNAUTHORIZED]);
    }
    // Requests with no signature at all, as anybody could send them.
    const bare = await fetch(`${helpdesk}/inclamo/provisioning/stores/${store('forged')}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    expect([bare.status, bare.headers.get('x-inclamo-provisioning')]).toEqual([401, '1']);

    expect((await storeApp.status(store('forged'))).body).toEqual(NO_ACCOUNT);
    expect((await storeApp.status(store('maple'))).body.state).toBe('active');
  });

  test('A stale request', async () => {
    const answer = await storeApp.provision(store('stale'), { admin: person('late'), stale: true });

    // The same answer as for a wrong signature: nothing says which check failed.
    expect([answer.status, answer.body]).toEqual([401, UNAUTHORIZED]);
    expect((await storeApp.status(store('stale'))).body).toEqual(NO_ACCOUNT);
  });

  test('The same request delivered twice', async () => {
    const request = { shop: { name: `Twice ${run}` }, admin: person('twice') };
    const first = await storeApp.provision(store('twice'), request);
    const second = await storeApp.provision(store('twice'), { ...request, request_id: first.request_id });

    expect(first.status).toBe(201);
    expect([second.status, second.body]).toEqual([first.status, first.body]);
    // Nothing was made a second time: the store has the one account, and a
    // new request finds it.
    const fresh = await storeApp.provision(store('twice'), request);
    expect([fresh.status, fresh.body.outcome, fresh.body.account_id]).toEqual([200, 'existed', first.body.account_id]);
    made.twice = { requestId: first.request_id };
  });

  test('A key reused for another store', async () => {
    const answer = await storeApp.provision(store('reused'), { shop: { name: `Twice ${run}` }, admin: person('twice'), request_id: made.twice.requestId });

    // Refused as a reused key, which the app can tell from a wrong secret.
    expect([answer.status, answer.body, answer.provisioning]).toEqual([409, { error: 'request_id_reused' }, '1']);
    expect((await storeApp.status(store('reused'))).body).toEqual(NO_ACCOUNT);
  });
});

test.describe('Removing the app suspends the account', () => {
  test('The app is removed', async () => {
    // Rita administers two stores; the first one has twelve conversations.
    const river = await storeWithAdministrator('river', 'rita');
    const second = await storeApp.provision(store('rita-second'), { shop: { name: `Rita's second ${run}` }, admin: river.admin });
    expect(second.status).toBe(201);
    await river.api.fill(river.accountId, 12, `${run}-river`);
    expect(await river.api.conversationCount(river.accountId)).toBe(12);
    made.river = { accountId: river.accountId, otherAccountId: second.body.account_id, rita: river.api };

    const answer = await storeApp.removal(store('river'));

    expect([answer.status, answer.body]).toEqual([200, { contract: 1, state: 'suspended' }]);
    expect((await storeApp.status(store('river'))).body).toMatchObject({ account_id: river.accountId, state: 'suspended' });
    expect(await river.api.opens(river.accountId)).toBe(401);
    // That its conversations, contacts and settings are still stored is what
    // "The store installs the app again" finds when the account is back.
  });

  test('The notice is repeated', async () => {
    const answer = await storeApp.removal(store('river'));

    expect([answer.status, answer.body]).toEqual([200, { contract: 1, state: 'suspended' }]);
    expect((await storeApp.status(store('river'))).body).toMatchObject({ account_id: made.river.accountId, state: 'suspended' });
    expect(await made.river.rita.opens(made.river.accountId)).toBe(401);
    // A notice for a store that never had an account is answered as done too.
    const unknown = await storeApp.removal(store('never'));
    expect([unknown.status, unknown.body]).toEqual([200, { contract: 1, state: 'none' }]);
  });

  test('A user of two accounts', async () => {
    const { rita, accountId, otherAccountId } = made.river;

    expect(await rita.opens(accountId)).toBe(401);
    expect(await rita.opens(otherAccountId)).toBe(200);
    // Signing in again works too, and shows the other account as theirs.
    const again = await personApi(person('rita').email, password('rita'));
    expect(await again.opens(otherAccountId)).toBe(200);
  });
});

test.describe('Installing again restores the same account', () => {
  test('The store installs the app again', async () => {
    const answer = await storeApp.provision(store('river'), { shop: { name: 'A name the store has now' }, admin: person('rita') });

    expect(answer.status).toBe(200);
    expect(answer.body).toMatchObject({ account_id: made.river.accountId, outcome: 'restored', state: 'active' });
    expect(answer.body.password_setup_url).toBeUndefined();
    expect((await storeApp.status(store('river'))).body.state).toBe('active');
    const { rita, accountId } = made.river;
    expect(await rita.opens(accountId)).toBe(200);
    expect(await rita.conversationCount(accountId)).toBe(12);
    // The inbox the conversations came through is there as it was.
    expect(((await rita.get(`/api/v1/accounts/${accountId}/inboxes`)).body.payload || []).map(inbox => inbox.name)).toContain('Store chat');
  });

  test('Another person installs again', async () => {
    const { rita, accountId } = made.river;
    expect((await storeApp.removal(store('river'))).body.state).toBe('suspended');
    const admin = person('nora');

    const answer = await storeApp.provision(store('river'), { admin });

    expect(answer.status).toBe(200);
    expect(answer.body).toMatchObject({ account_id: accountId, outcome: 'restored', state: 'active' });
    // Nora is new to the installation, so she gets the link, and gets in.
    expect(await setPassword(answer.body.password_setup_url, password('nora'))).toBe(200);
    const nora = await personApi(admin.email, password('nora'));
    expect(await nora.opens(accountId)).toBe(200);
    expect(await nora.conversationCount(accountId)).toBe(12);
    const byEmail = (a, b) => a.email.localeCompare(b.email);
    expect((await rita.members(accountId)).sort(byEmail)).toEqual(
      [
        { email: admin.email, role: 'administrator' },
        { email: person('rita').email, role: 'administrator' },
      ].sort(byEmail)
    );
  });
});

test.describe('The app can ask what a store has', () => {
  test('A store with an active account', async () => {
    const answer = await storeApp.status(store('maple'));

    expect(answer.status).toBe(200);
    // These fields and no other: nothing about users or conversations.
    expect(answer.body).toEqual({ contract: 1, account_id: made.maple.accountId, helpdesk_url: helpdesk, state: 'active', created_at: made.maple.createdAt });
  });

  test('A store without an account', async () => {
    const answer = await storeApp.status(store('never'));

    // Marked as this installation's answer, so it is not "no provisioning here".
    expect([answer.status, answer.body, answer.provisioning]).toEqual([404, NO_ACCOUNT, '1']);
  });
});

test.describe('Provisioning exists only where the operator enabled it', () => {
  test('A self-hosted installation', async () => {
    const elsewhere = { helpdesk_url: unprovisionedUrl() };
    // The other helpdesk is up and is this installation without the secret.
    expect((await fetch(`${unprovisionedUrl()}/api`)).status).toBe(200);

    // Correctly signed with the secret the first helpdesk accepts, and not.
    for (const switches of [elsewhere, { ...elsewhere, wrong_signature: true }]) {
      const answers = [
        await storeApp.provision(store('self-hosted'), { admin: person('owner'), ...switches }),
        await storeApp.status(store('maple'), switches),
        await storeApp.removal(store('maple'), switches),
      ];
      expect(answers.map(answer => answer.status)).toEqual([404, 404, 404]);
      for (const answer of answers) {
        expect(answer.body?.error).not.toBe('no_account');
        // No provisioning mark: a 404 without it means "no provisioning here".
        expect(answer.provisioning).toBeNull();
      }
    }

    // Nothing was created or changed: both helpdesks share one database.
    expect((await storeApp.status(store('self-hosted'))).body).toEqual(NO_ACCOUNT);
    expect((await storeApp.status(store('maple'))).body.state).toBe('active');
    // And signing up stays closed there, as the installation set it.
    const signup = await fetch(`${unprovisionedUrl()}/api/v1/accounts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ account_name: 'Walk-in', user_full_name: 'Walk In', email: person('walk-in').email, password: password('walk-in') }),
    });
    expect(signup.status).toBe(404);
  });
});
