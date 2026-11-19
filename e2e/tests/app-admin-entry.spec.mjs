// Scenarios of behavior contract `app-admin-entry`, grouped by requirement.
// Each test is named after its scenario; scripts/check-e2e-coverage.mjs
// relies on that.
//
// The store app is the stand-in of e2e/stand-in-app, which signs the entry
// call of docs/app-admin-entry.md with the stack's secret; the browser opens
// the one-time address the helpdesk answers, as the app would send it there.
// The stores are invented `myshopify.com` domains of this run, and their
// people are made by provisioning or invited by those people, so no user of
// the other files is touched.
//
// Three scenarios are not here, each named with its reason in the checker:
// the request limits (the stack runs without Rack::Attack) and the two about
// the record of attempts and the request log (no address shows them).
import { test, expect } from '@playwright/test';
import { createHmac } from 'node:crypto';
import { storeApp, storefrontUrl, unprovisionedUrl, setPassword, personApi, signInWith } from '../lib/app.mjs';

const run = (process.env.E2E_RUN || 'local').toLowerCase().replace(/[^a-z0-9]/g, '');
const store = name => `e2e-${run}-entry-${name}.myshopify.com`;
const person = name => ({ email: `e2e-${run}-entry-${name}@example.test`, name: `Entry ${name[0].toUpperCase()}${name.slice(1)}` });
const password = name => `Own-${name}-Passw0rd!`;
const helpdesk = (process.env.HELPDESK_URL || 'http://localhost:3000').replace(/\/$/, '');
const ENTRY_URL = new RegExp(`^${helpdesk.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/inclamo/entry/[A-Za-z0-9_-]{43}$`);
const NOT_A_USER = {
  error: 'not_a_user',
  message: "This email is not a user of this helpdesk account. Ask the account's administrator to invite you.",
};
const SESSION_HEADERS = ['access-token', 'token-type', 'client', 'expiry', 'uid'];

// The stores and people of the run, made once.
const made = {};

// A store with its account and an administrator who set a password.
async function storeWithAdministrator(storeName, personName) {
  const admin = person(personName);
  const answer = await storeApp.provision(store(storeName), { shop: { name: `Entry ${storeName} ${run}` }, admin });
  expect(answer.status).toBe(201);
  expect(await setPassword(answer.body.password_setup_url, password(personName))).toBe(200);
  return { domain: store(storeName), accountId: answer.body.account_id, admin, api: await personApi(admin.email, password(personName)) };
}

// The first store (an administrator, and an agent who administers the second
// store), and the second store.
async function stores() {
  if (made.first) return made;
  made.first = await storeWithAdministrator('first', 'olga');
  made.second = await storeWithAdministrator('second', 'boris');
  const added = await made.first.api.post(`/api/v1/accounts/${made.first.accountId}/agents`, { name: 'Entry Boris', email: person('boris').email, role: 'agent' });
  expect(added.status).toBe(200);
  return made;
}

// The app asks; the answer must give an address.
async function addressFor(domain, email) {
  const answer = await storeApp.entry(domain, { staff: { email } });
  expect([answer.status, answer.provisioning]).toEqual([200, '1']);
  expect(answer.body).toEqual({ contract: 1, entry_url: expect.stringMatching(ENTRY_URL), expires_in: 60 });
  return answer.body.entry_url;
}

// The dashboard's session in the browser, as its script reads it; null when none.
async function sessionOf(context) {
  const cookie = (await context.cookies(helpdesk)).find(entry => entry.name === 'cw_d_session_info');
  if (!cookie) return null;
  const all = JSON.parse(decodeURIComponent(cookie.value));
  return Object.fromEntries(SESSION_HEADERS.map(name => [name, all[name]]));
}

async function asSession(session, path, { method = 'GET', body } = {}) {
  const response = await fetch(`${helpdesk}${path}`, {
    method,
    headers: { ...session, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  try {
    return { status: response.status, body: text ? JSON.parse(text) : null };
  } catch (error) {
    return { status: response.status, body: text };
  }
}

// Opens the address and waits for the dashboard of the account.
async function enter(page, url, accountId) {
  await page.goto(url);
  await expect(page).toHaveURL(new RegExp(`/app/accounts/${accountId}(/|$)`), { timeout: 45_000 });
  const session = await sessionOf(page.context());
  expect(session).not.toBeNull();
  return session;
}

// The login page, with nobody signed in.
async function expectLoginPage(page) {
  await expect(page).toHaveURL(/\/app\/login(\?|$)/, { timeout: 45_000 });
  await expect(page.locator('input[type="password"]')).toBeVisible({ timeout: 45_000 });
  expect(await sessionOf(page.context())).toBeNull();
}

// RFC 6238 with the authenticator's defaults: SHA-1, six digits, 30 seconds.
function totp(secret, step = Math.floor(Date.now() / 30_000)) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bits = [...secret.replace(/=+$/, '').toUpperCase()].map(character => alphabet.indexOf(character).toString(2).padStart(5, '0')).join('');
  const key = Buffer.from(bits.match(/.{8}/g).map(byte => parseInt(byte, 2)));
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(step));
  const digest = createHmac('sha1', key).update(counter).digest();
  const offset = digest[digest.length - 1] & 15;
  return String((digest.readUInt32BE(offset) & 0x7fffffff) % 1_000_000).padStart(6, '0');
}

const nextStep = async () => {
  const step = Math.floor(Date.now() / 30_000);
  while (Math.floor(Date.now() / 30_000) === step) await new Promise(resolve => setTimeout(resolve, 500));
};

test.describe.configure({ mode: 'serial' });

test.describe("The app's request gives a user a one-time way in", () => {
  test('An administrator opens the helpdesk from the app', async ({ page }) => {
    const { first } = await stores();
    const url = await addressFor(first.domain, first.admin.email);
    expect(url).not.toContain('@');
    expect(url).not.toContain('%40');

    const session = await enter(page, url, first.accountId);

    // Nothing asked for a password on the way: the browser went from the
    // address straight to the account.
    await expect(page.locator('input[type="password"]')).toHaveCount(0);
    const profile = await asSession(session, '/api/v1/profile');
    expect(profile.status).toBe(200);
    expect(profile.body).toMatchObject({ email: first.admin.email });
    expect(profile.body.accounts).toEqual([expect.objectContaining({ id: first.accountId, role: 'administrator' })]);
  });

  test('An agent opens the helpdesk from the app', async ({ page }) => {
    const { first } = await stores();
    const session = await enter(page, await addressFor(first.domain, person('boris').email), first.accountId);

    const profile = await asSession(session, '/api/v1/profile');
    expect(profile.body.email).toBe(person('boris').email);
    expect(profile.body.accounts).toEqual(expect.arrayContaining([expect.objectContaining({ id: first.accountId, role: 'agent' })]));
    // An agent's rights: an administrator's change is refused.
    const inbox = await asSession(session, `/api/v1/accounts/${first.accountId}/inboxes`, { method: 'POST', body: { name: 'Not an agent\'s to add', channel: { type: 'api', webhook_url: '' } } });
    expect(inbox.status).toBe(401);
  });

  test('The email is not verified', async () => {
    const { first } = await stores();
    for (const emailVerified of [false, null, 'true']) {
      const answer = await storeApp.entry(first.domain, { staff: { email: first.admin.email, email_verified: emailVerified } });
      expect([answer.status, answer.body.error]).toEqual([422, 'staff_email_unverified']);
      expect(answer.body.message).toBeTruthy();
      expect(answer.body.entry_url).toBeUndefined();
    }
  });
});

test.describe("Only users of the store's account get in", () => {
  test('A staff member who is not a helpdesk user', async () => {
    const { first } = await stores();
    const stranger = person('stranger');

    const answer = await storeApp.entry(first.domain, { staff: { email: stranger.email } });

    expect([answer.status, answer.body, answer.provisioning]).toEqual([403, NOT_A_USER, '1']);
    // No user came of it: a later provisioning request for that person makes
    // one, which it tells by the password link it gives only to a person it created.
    const later = await storeApp.provision(store('stranger-later'), { admin: stranger });
    expect(later.status).toBe(201);
    expect(later.body.password_setup_url).toBeTruthy();
  });

  test("A user of another store's account", async () => {
    const { first } = await stores();
    const other = await storeWithAdministrator('third', 'pavel');

    const answer = await storeApp.entry(first.domain, { staff: { email: other.admin.email } });

    expect([answer.status, answer.body]).toEqual([403, NOT_A_USER]);
    expect((await other.api.accounts()).map(account => account.id)).toEqual([other.accountId]);
  });

  test('A store without an account', async () => {
    const answer = await storeApp.entry(store('never'), { staff: { email: person('olga').email } });

    expect([answer.status, answer.body, answer.provisioning]).toEqual([404, { error: 'no_account' }, '1']);
  });
});

test.describe("The person lands in this store's account", () => {
  test('A user of two accounts', async ({ page }) => {
    const { first, second } = await stores();
    const boris = person('boris').email;

    // Boris works in the first store's account, then opens the second store's.
    await enter(page, await addressFor(first.domain, boris), first.accountId);
    await page.waitForTimeout(3_000);
    await enter(page, await addressFor(second.domain, boris), second.accountId);

    await expect(page).toHaveURL(new RegExp(`/app/accounts/${second.accountId}(/|$)`));
    const profile = await asSession(await sessionOf(page.context()), '/api/v1/profile');
    expect(profile.body.accounts.map(account => account.id).sort()).toEqual([first.accountId, second.accountId].sort());
  });
});

test.describe('The address works once and briefly', () => {
  test('The address is opened a second time', async ({ page, browser }) => {
    const { first } = await stores();
    const url = await addressFor(first.domain, first.admin.email);
    await enter(page, url, first.accountId);

    const elsewhere = await browser.newContext();
    try {
      const other = await elsewhere.newPage();
      await other.goto(url);
      await expectLoginPage(other);
    } finally {
      await elsewhere.close();
    }
  });

  test('The address is opened too late', async ({ page }) => {
    test.setTimeout(180_000);
    const { first } = await stores();
    const url = await addressFor(first.domain, first.admin.email);

    // Past the minute the address lives.
    await new Promise(resolve => setTimeout(resolve, 65_000));
    await page.goto(url);

    await expectLoginPage(page);
  });

  test('The address with another email', async ({ page, browser }) => {
    const { first } = await stores();
    const url = await addressFor(first.domain, first.admin.email);
    const token = url.split('/').pop();

    // The address names nobody, so no email can be put in its place. Its
    // token put in Chatwoot's own sign-in link, with another user's email or
    // with its own user's, signs nobody in.
    for (const email of [person('boris').email, first.admin.email]) {
      const elsewhere = await browser.newContext();
      try {
        const other = await elsewhere.newPage();
        await other.goto(`/app/login?email=${encodeURIComponent(email)}&sso_auth_token=${token}`);
        // The login page submits the link by itself and, refused, reloads itself bare.
        await other.waitForURL(address => address.pathname === '/app/login' && !address.search, { timeout: 45_000 });
        await expectLoginPage(other);
      } finally {
        await elsewhere.close();
      }
    }

    // The address itself still signs in only the user it was made for.
    const session = await enter(page, url, first.accountId);
    expect((await asSession(session, '/api/v1/profile')).body.email).toBe(first.admin.email);
  });
});

test.describe("The session is the helpdesk's own", () => {
  test('The session is listed', async ({ page }) => {
    const { first } = await stores();
    const session = await enter(page, await addressFor(first.domain, first.admin.email), first.accountId);
    const withPassword = await signInWith(first.admin.email, password('olga'));
    expect(withPassword.status).toBe(200);

    const listed = await asSession(session, '/api/v1/profile/sessions');

    expect(listed.status).toBe(200);
    const current = listed.body.filter(entry => entry.current);
    expect(current).toHaveLength(1);
    // Listed like the session the password started, with the same fields.
    const fromPassword = (await asSession(withPassword.headers, '/api/v1/profile/sessions')).body.find(entry => entry.current);
    expect(listed.body.map(entry => entry.id)).toContain(fromPassword.id);
    expect(Object.keys(current[0]).sort()).toEqual(Object.keys(fromPassword).sort());
    expect(current[0].id).not.toBe(fromPassword.id);
  });

  test('The session outlives the Shopify admin', async ({ page }) => {
    const { first } = await stores();
    await enter(page, await addressFor(first.domain, first.admin.email), first.accountId);

    // The person leaves for another site (the store app is gone), comes back
    // and reloads the helpdesk.
    await page.goto(storefrontUrl(first.domain));
    await page.goto(`/app/accounts/${first.accountId}/dashboard`);
    await page.reload();

    await expect(page).toHaveURL(new RegExp(`/app/accounts/${first.accountId}(/|$)`), { timeout: 45_000 });
    await page.waitForTimeout(3_000);
    await expect(page).not.toHaveURL(/\/app\/login/);
    expect((await asSession(await sessionOf(page.context()), '/api/v1/profile')).status).toBe(200);
  });
});

test.describe('A suspended account lets nobody in', () => {
  test('The app was removed and the request still comes', async () => {
    const removed = await storeWithAdministrator('removed', 'rita');
    expect((await storeApp.removal(removed.domain)).body.state).toBe('suspended');

    const answer = await storeApp.entry(removed.domain, { staff: { email: removed.admin.email } });

    expect([answer.status, answer.body]).toEqual([403, { error: 'account_suspended', message: 'This helpdesk account is suspended.' }]);
  });
});

test.describe('Two-factor users use their password and code', () => {
  test('A user with two-factor authentication', async () => {
    test.setTimeout(150_000);
    const careful = await storeWithAdministrator('careful', 'tara');
    const enabled = await careful.api.post('/api/v1/profile/mfa');
    expect(enabled.status).toBe(200);
    const { secret } = enabled.body;
    expect((await careful.api.post('/api/v1/profile/mfa/verify', { otp_code: totp(secret) })).status).toBe(200);

    const answer = await storeApp.entry(careful.domain, { staff: { email: careful.admin.email } });
    expect([answer.status, answer.body]).toEqual([
      403,
      { error: 'two_factor', message: "Two-factor authentication is on for this user. Sign in on the helpdesk's login page with your password and code." },
    ]);

    // The login page's own calls: the password, then the code (a code is
    // used once, so the next one is waited for).
    const first = await fetch(`${helpdesk}/auth/sign_in`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: careful.admin.email, password: password('tara') }),
    });
    expect(first.status).toBe(206);
    const { mfa_token: mfaToken } = await first.json();
    await nextStep();
    const second = await fetch(`${helpdesk}/auth/sign_in`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mfa_token: mfaToken, otp_code: totp(secret) }),
    });
    expect(second.status).toBe(200);
  });
});

test.describe('A user with a pending invitation gets in', () => {
  test('An invited agent who never opened the invitation', async ({ page }) => {
    const { first } = await stores();
    const ivy = person('ivy');
    const invited = await first.api.post(`/api/v1/accounts/${first.accountId}/agents`, { name: ivy.name, email: ivy.email, role: 'agent' });
    expect(invited.status).toBe(200);
    expect(invited.body.confirmed).toBe(false);

    const session = await enter(page, await addressFor(first.domain, ivy.email), first.accountId);

    expect((await asSession(session, '/api/v1/profile')).body).toMatchObject({ email: ivy.email, confirmed: true });
  });
});

test.describe('A signed request is used once', () => {
  test('A captured request is sent again', async () => {
    const { first } = await stores();
    const timestamp = Math.floor(Date.now() / 1000);
    const answered = await storeApp.entry(first.domain, { staff: { email: first.admin.email }, timestamp });
    expect(answered.status).toBe(200);

    const again = await storeApp.entry(first.domain, { staff: { email: first.admin.email }, timestamp, request_id: answered.request_id });

    expect([again.status, again.body, again.provisioning]).toEqual([409, { error: 'request_id_reused' }, '1']);
  });

  test('A request signed with another secret', async () => {
    const { first } = await stores();

    const answer = await storeApp.entry(first.domain, { staff: { email: first.admin.email }, wrong_signature: true });

    expect([answer.status, answer.body, answer.provisioning]).toEqual([401, { error: 'unauthorized' }, '1']);
  });
});

test.describe('Entry exists only where provisioning is enabled', () => {
  test('A self-hosted installation', async () => {
    const { first } = await stores();

    const answer = await storeApp.entry(first.domain, { staff: { email: first.admin.email }, helpdesk_url: unprovisionedUrl() });
    expect([answer.status, answer.provisioning]).toEqual([404, null]);
    expect(answer.body?.entry_url).toBeUndefined();

    // An address the provisioned installation gave opens nothing there, and
    // its password login works as on any installation.
    const url = await addressFor(first.domain, first.admin.email);
    const opened = await fetch(url.replace(helpdesk, unprovisionedUrl()), { redirect: 'manual' });
    expect(opened.status).toBe(404);
    expect(opened.headers.get('set-cookie') || '').not.toContain('cw_d_session_info');
    const login = await fetch(`${unprovisionedUrl()}/auth/sign_in`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: first.admin.email, password: password('olga') }),
    });
    expect(login.status).toBe(200);
  });
});
