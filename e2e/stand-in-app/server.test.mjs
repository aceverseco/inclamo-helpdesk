// Tests of the stand-in app itself: it must sign as docs/app-provisioning.md
// says, its switches must send exactly what the helpdesk has to refuse, its
// storefront page must load the widget as docs/app-storefront-chat.md §4 says,
// its agent calls must carry a fresh pairing token as
// docs/app-agent-connection.md §3.1 says, its erasure calls must send the
// bodies of docs/app-store-erasure.md, and it must check the helpdesk's key
// requests and answer them as docs/app-store-access.md says, or the end-to-end
// tests prove nothing.
//   node --test e2e/stand-in-app/server.test.mjs
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHmac } from 'node:crypto';
import { createStandInApp, sign, storefrontPage, STALE_SECONDS, KEY_REFUSALS } from './server.mjs';

const secret = 'secret-of-the-stand-in-app-test-0123456789abcdef';
const link = 'https://helpdesk.example.test/app/auth/password/edit?reset_password_token=one-time-token';
const entryUrl = 'https://helpdesk.example.test/inclamo/entry/one-time-entry-token';
const store = 'example-store.myshopify.com';
const WINDOW = 300;

let app;
let appUrl;
let helpdesk;
let helpdeskUrl;
let other;
let otherUrl;
let agent;
let agentUrl;
const received = [];
// What the fake AI service was asked for: one entry per pairing token.
const minted = [];
// What the fake helpdesk says of the store's storefront chat.
const chat = { token: 'wT3xFirstTokenOfTheInbox', gone: false };
const widgetBase = 'https://helpdesk.example.test';

const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(`http://127.0.0.1:${server.address().port}`)));

// The signature as the contract words it, written out again here so that a
// mistake in the stand-in's own routine is not checked against itself.
const expected = (key, request) =>
  `sha256=${createHmac('sha256', key).update([request.timestamp, request.requestId, request.method, request.path, request.raw].join('.')).digest('hex')}`;

// A helpdesk that checks what the contract's §2.3 checks, refuses a reused
// request id as the contract says, marks its answers, and records the rest.
function fakeHelpdesk() {
  const seen = new Map();
  return createServer((request, response) => {
    let raw = '';
    request.on('data', chunk => (raw += chunk));
    request.on('end', () => {
      const entry = {
        method: request.method,
        path: request.url,
        raw,
        timestamp: request.headers['x-inclamo-timestamp'],
        requestId: request.headers['x-inclamo-request-id'],
        signature: request.headers['x-inclamo-signature'],
      };
      received.push(entry);
      const answer = (status, body) => {
        response.writeHead(status, { 'Content-Type': 'application/json', 'X-Inclamo-Provisioning': '1' });
        response.end(JSON.stringify(body));
      };
      const digest = `${entry.method}.${entry.path}.${raw}`;
      const fresh = Math.abs(Date.now() / 1000 - Number(entry.timestamp)) <= WINDOW;
      if (entry.signature !== expected(secret, entry) || !fresh) return answer(401, { error: 'unauthorized' });
      if (seen.has(entry.requestId) && seen.get(entry.requestId) !== digest) return answer(409, { error: 'request_id_reused' });
      seen.set(entry.requestId, digest);
      if (entry.path.endsWith('/agent')) {
        if (entry.method === 'PUT') return answer(201, { contract: 1, state: 'connected', outcome: 'connected', inbox_ids: [3], phone_inbox_id: 12, connected_at: '2026-11-17T10:05:00Z' });
        if (entry.method === 'GET') return answer(200, { contract: 1, state: 'never_connected' });
        return answer(200, { contract: 1, state: 'disconnected', ai_service_told: true });
      }
      if (entry.path.endsWith('/shoppers/requests')) {
        return answer(200, { contract: 1, erasures: { waiting: 1, held: 0, overdue: 0 }, data_requests: { waiting: 0, overdue: 0 }, account_state: 'active' });
      }
      if (entry.path.endsWith('/shoppers/erasure')) return answer(200, { contract: 1, state: 'waiting', contacts: 1, conversations: 2, delete_after: '2026-12-02T10:00:00Z' });
      if (entry.path.endsWith('/shoppers/data-request')) return answer(200, { contract: 1, state: 'none', contacts: 0, conversations: 0 });
      if (entry.path.endsWith('/erasure')) return answer(200, { contract: 1, state: 'scheduled', erase_after: '2026-11-26T10:00:00Z' });
      if (entry.path.endsWith('/storefront-chat')) {
        const inbox = { contract: 1, inbox_id: 7, website_token: chat.token, widget_base_url: widgetBase, state: 'active' };
        if (entry.method === 'PUT') return answer(201, { ...inbox, outcome: 'created' });
        return chat.gone ? answer(404, { error: 'no_storefront_chat' }) : answer(200, inbox);
      }
      if (entry.path.endsWith('/entry')) return answer(200, { contract: 1, entry_url: entryUrl, expires_in: 60 });
      if (entry.method === 'PUT') return answer(201, { contract: 1, account_id: 7, outcome: 'created', password_setup_url: link });
      if (entry.method === 'GET') return answer(404, { error: 'no_account' });
      return answer(200, { contract: 1, state: 'suspended' });
    });
  });
}

before(async () => {
  helpdesk = fakeHelpdesk();
  helpdeskUrl = await listen(helpdesk);
  // An installation without provisioning: every address is unknown to it.
  other = createServer((request, response) => {
    request.resume();
    request.on('end', () => {
      response.writeHead(404, { 'Content-Type': 'text/html' });
      response.end('<h1>Not found</h1>');
    });
  });
  otherUrl = await listen(other);
  // The AI service's side of a pairing token (the stand-in agent's /__e2e/tokens).
  agent = createServer((request, response) => {
    let raw = '';
    request.on('data', chunk => (raw += chunk));
    request.on('end', () => {
      minted.push({ path: request.url, refuse: JSON.parse(raw || '{}').refuse ?? null });
      response.writeHead(201, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ service_url: 'https://ai.example.test/channels/helpdesk', token: `pairing-token-${minted.length}` }));
    });
  });
  agentUrl = await listen(agent);
  app = createStandInApp({ helpdeskUrl, secret, agentUrl, quiet: true });
  appUrl = await listen(app.server);
});

after(() => {
  app.server.close();
  helpdesk.close();
  other.close();
  agent.close();
});

beforeEach(() => {
  received.length = 0;
  minted.length = 0;
  Object.assign(chat, { token: 'wT3xFirstTokenOfTheInbox', gone: false });
});

const page = async domain => {
  const response = await fetch(`${appUrl}/storefront/${domain}`);
  return { status: response.status, type: response.headers.get('content-type'), text: await response.text() };
};

const control = async (name, body, method = 'POST') => {
  const response = await fetch(`${appUrl}/__e2e/${name}`, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: response.status, body: response.status === 204 ? null : await response.json() };
};

test('reproduces both worked examples of the contract', () => {
  const example = 'test-secret-not-for-production-0123456789abcdef';
  const requestId = '6f1c2d0e-8a55-4c0a-9d5e-2b7f3c1a9e44';
  const path = '/inclamo/provisioning/stores/example-store.myshopify.com';
  const body =
    '{"contract":1,"shop":{"domain":"example-store.myshopify.com","name":"Example Store","locale":"en","timezone":"America/New_York"},"admin":{"email":"alex@example.com","name":"Alex Example","email_verified":true}}';
  assert.equal(sign(example, { timestamp: 1794000000, requestId, method: 'PUT', path, body }), 'sha256=305fc0be96cd96282165e88118f12f54bd26c9ae69d5b43c6c292a01efb139a0');
  assert.equal(sign(example, { timestamp: 1794000000, requestId: '2b8e4f7a-1c3d-4e5f-9a6b-7c8d9e0f1a2b', method: 'get', path }), 'sha256=ddaaebebc719bc983b8c2ca8de20603fb5f43e10504d4cad5aa668aa3411b901');
});

test('signs the three calls over their method, path and exact body', async () => {
  const created = await control('provision', { domain: store, shop: { name: 'Example Store' }, admin: { email: 'alex@example.test', name: 'Alex Example' } });
  const status = await control('status', { domain: store });
  const removal = await control('removal', { domain: store });

  assert.deepEqual([created.body.status, status.body.status, removal.body.status], [201, 404, 200]);
  assert.deepEqual(received.map(entry => [entry.method, entry.path]), [
    ['PUT', `/inclamo/provisioning/stores/${store}`],
    ['GET', `/inclamo/provisioning/stores/${store}`],
    ['POST', `/inclamo/provisioning/stores/${store}/removal`],
  ]);
  assert.deepEqual(JSON.parse(received[0].raw), {
    contract: 1,
    shop: { domain: store, name: 'Example Store', locale: 'en', timezone: 'Etc/UTC' },
    admin: { email: 'alex@example.test', name: 'Alex Example', email_verified: true },
  });
  assert.equal(received[1].raw, '');
  assert.equal(received[2].raw, '');
  // A new request id for every logical request, and the one it reports.
  assert.equal(new Set(received.map(entry => entry.requestId)).size, 3);
  assert.match(received[0].requestId, /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  assert.equal(created.body.request_id, received[0].requestId);
  // Each signed over its own request id too.
  assert.deepEqual(received.map(entry => entry.signature === expected(secret, entry)), [true, true, true]);
});

test('hands the answer to the test whole, the password link and the provisioning header included', async () => {
  const created = await control('provision', { domain: store });
  assert.deepEqual(created.body.body, { contract: 1, account_id: 7, outcome: 'created', password_setup_url: link });
  assert.equal(created.body.provisioning, '1');
});

test('leaves out a field given as null, adds the address for key requests, and sends a replaced body as it is', async () => {
  await control('provision', { domain: store, admin: { email_verified: null }, shop: { locale: null } });
  await control('provision', { domain: store, body: { contract: 2 } });
  await control('provision', { domain: store, store_access_url: 'https://app.example.test/store-access' });
  const first = JSON.parse(received[0].raw);
  assert.equal('email_verified' in first.admin, false);
  assert.equal('locale' in first.shop, false);
  assert.equal('store_access_url' in first, false);
  assert.equal(received[1].raw, '{"contract":2}');
  assert.equal(JSON.parse(received[2].raw).store_access_url, 'https://app.example.test/store-access');
  // All were signed over what was sent.
  assert.deepEqual(received.map(entry => entry.signature === expected(secret, entry)), [true, true, true]);
});

test('the wrong-signature switch signs with a secret the helpdesk does not have', async () => {
  const refused = await control('provision', { domain: store, wrong_signature: true });
  assert.equal(refused.body.status, 401);
  assert.deepEqual(refused.body.body, { error: 'unauthorized' });
  assert.match(received[0].signature, /^sha256=[0-9a-f]{64}$/);
  assert.notEqual(received[0].signature, expected(secret, received[0]));
});

test('the stale switch signs correctly with a time ten minutes in the past', async () => {
  const refused = await control('status', { domain: store, stale: true });
  assert.equal(refused.body.status, 401);
  const age = Date.now() / 1000 - Number(received[0].timestamp);
  assert.ok(age >= STALE_SECONDS - 1 && age < STALE_SECONDS + 5, `the time was ${age} s old`);
  assert.equal(received[0].signature, expected(secret, received[0]));
});

test('the request-id switch repeats an id, signed again each time', async () => {
  const first = await control('provision', { domain: store });
  const again = await control('provision', { domain: store, request_id: first.body.request_id });
  const elsewhere = await control('provision', { domain: 'other-store.myshopify.com', request_id: first.body.request_id });

  assert.deepEqual(received.map(entry => entry.requestId), Array(3).fill(first.body.request_id));
  assert.equal(received[1].raw, received[0].raw);
  assert.equal(again.body.status, 201);
  // The same id for another store is the helpdesk's to refuse, as reused.
  assert.deepEqual([elsewhere.body.status, elsewhere.body.body], [409, { error: 'request_id_reused' }]);
  assert.deepEqual(received.map(entry => entry.signature === expected(secret, entry)), [true, true, true]);
});

test('sends to another helpdesk when told, and reports an answer that is not JSON and has no provisioning header', async () => {
  const answer = await control('status', { domain: store, helpdesk_url: otherUrl });
  assert.equal(answer.body.status, 404);
  assert.equal(answer.body.body, null);
  assert.equal(answer.body.provisioning, null);
  assert.equal(received.length, 0);
});

test('its log holds no body, link, signature or secret', async () => {
  await control('log', null, 'DELETE');
  await control('provision', { domain: store });
  await control('status', { domain: store, wrong_signature: true });
  const { log } = (await control('log', null, 'GET')).body;

  assert.deepEqual(log.map(entry => [entry.method, entry.status, entry.outcome || entry.error]), [
    ['PUT', 201, 'created'],
    ['GET', 401, 'unauthorized'],
  ]);
  const text = JSON.stringify(log);
  for (const hidden of [secret, link, 'reset_password_token', 'sha256=', '@']) assert.equal(text.includes(hidden), false, `the log holds ${hidden}`);
});

test('signs the two storefront chat calls over their whole path and exact body', async () => {
  const chatStore = 'chat-calls.myshopify.com';
  const created = await control('storefront-chat', { domain: chatStore, storefront_url: 'https://example-store.com' });
  const bare = await control('storefront-chat', { domain: chatStore });
  const replaced = await control('storefront-chat', { domain: chatStore, body: { contract: 2 } });
  const status = await control('storefront-chat-status', { domain: chatStore });

  assert.deepEqual([created.body.status, bare.body.status, replaced.body.status, status.body.status], [201, 201, 201, 200]);
  assert.deepEqual(received.map(entry => [entry.method, entry.path]), [
    ['PUT', `/inclamo/provisioning/stores/${chatStore}/storefront-chat`],
    ['PUT', `/inclamo/provisioning/stores/${chatStore}/storefront-chat`],
    ['PUT', `/inclamo/provisioning/stores/${chatStore}/storefront-chat`],
    ['GET', `/inclamo/provisioning/stores/${chatStore}/storefront-chat`],
  ]);
  assert.deepEqual(received.map(entry => entry.raw), ['{"contract":1,"storefront_url":"https://example-store.com"}', '{"contract":1}', '{"contract":2}', '']);
  assert.deepEqual(received.map(entry => entry.signature === expected(secret, entry)), [true, true, true, true]);
  assert.equal(new Set(received.map(entry => entry.requestId)).size, 4);
  // The answer reaches the test whole.
  assert.deepEqual(created.body.body, { contract: 1, inbox_id: 7, website_token: chat.token, widget_base_url: widgetBase, state: 'active', outcome: 'created' });
  assert.deepEqual(status.body.body, { contract: 1, inbox_id: 7, website_token: chat.token, widget_base_url: widgetBase, state: 'active' });
});

test('the switches work on the storefront chat calls too', async () => {
  const refused = await control('storefront-chat', { domain: store, wrong_signature: true });
  const stale = await control('storefront-chat-status', { domain: store, stale: true });
  assert.deepEqual([refused.body.status, stale.body.status], [401, 401]);
  assert.notEqual(received[0].signature, expected(secret, received[0]));
  assert.equal(received[1].signature, expected(secret, received[1]));
});

test('the storefront page has no chat before the helpdesk answered with values', async () => {
  const untouched = 'no-chat-yet.myshopify.com';
  const before = await page(untouched);
  assert.equal(before.status, 200);
  assert.match(before.type, /^text\/html/);
  assert.equal(before.text.includes('<script'), false);
  assert.equal(before.text.includes('sdk.js'), false);

  // An answer without values gives the page nothing to load.
  await control('storefront-chat', { domain: untouched, wrong_signature: true });
  chat.gone = true;
  await control('storefront-chat-status', { domain: untouched });
  assert.equal((await page(untouched)).text.includes('<script'), false);
});

test('the storefront page loads the widget with the answered values, as the contract\'s snippet does', async () => {
  const shown = 'Chat-Shown.myshopify.com';
  await control('storefront-chat', { domain: shown });
  const { text } = await page(shown.toLowerCase());

  assert.ok(text.includes(`var BASE_URL = "${widgetBase}";`));
  assert.ok(text.includes('g.src = BASE_URL + "/packs/js/sdk.js";'));
  assert.ok(text.includes(`window.chatwootSDK.run({ websiteToken: "${chat.token}", baseUrl: BASE_URL });`));
  // No presentation option: the team's saved settings must not be overridden.
  for (const option of ['chatwootSettings', 'position', 'launcherTitle', 'darkMode', 'locale']) assert.equal(text.includes(option), false, `the page sets ${option}`);
  // Nothing but the two public values came from the helpdesk's answer.
  assert.equal(text.includes(secret), false);
  assert.equal((text.match(/<script/g) || []).length, 1);
  // The same store whatever the case of its letters.
  assert.equal((await page(shown)).text, text);
});

test('the storefront page takes the values of a later answer, and keeps them when told there is no chat', async () => {
  const changing = 'chat-changing.myshopify.com';
  await control('storefront-chat-status', { domain: changing });
  assert.ok((await page(changing)).text.includes(`websiteToken: "${chat.token}"`));

  // The team deleted the inbox: the storefront still carries the old token.
  const old = chat.token;
  chat.gone = true;
  assert.equal((await control('storefront-chat-status', { domain: changing })).body.status, 404);
  assert.ok((await page(changing)).text.includes(`websiteToken: "${old}"`));

  // The app asks again and is given a new token.
  chat.token = 'wT3xSecondTokenAfterDeletion';
  await control('storefront-chat', { domain: changing });
  const { text } = await page(changing);
  assert.ok(text.includes('websiteToken: "wT3xSecondTokenAfterDeletion"'));
  assert.equal(text.includes(old), false);
  // Another store's page is its own.
  assert.equal((await page('chat-elsewhere.myshopify.com')).text.includes('sdk.js'), false);
});

test('a value cannot end the page\'s script, and a path that is no store has no page', async () => {
  const text = storefrontPage('<b>.myshopify.com', { website_token: '</script><script>alert(1)</script>', widget_base_url: 'https://helpdesk.example.test' });
  assert.equal((text.match(/<script/g) || []).length, 1);
  assert.equal((text.match(/<\/script>/g) || []).length, 1);
  assert.equal(text.includes('<b>'), false);
  assert.equal((await page('%3Cb%3E')).status, 404);
  assert.equal((await fetch(`${appUrl}/storefront/${store}`, { method: 'POST' })).status, 405);
});

test('its log holds no token of a storefront chat', async () => {
  await control('log', null, 'DELETE');
  await control('storefront-chat', { domain: store });
  await control('storefront-chat-status', { domain: store });
  const { log } = (await control('log', null, 'GET')).body;

  assert.deepEqual(log.map(entry => [entry.method, entry.status, entry.outcome || entry.error]), [
    ['PUT', 201, 'created'],
    ['GET', 200, undefined],
  ]);
  assert.equal(JSON.stringify(log).includes(chat.token), false);
});

test('refuses to sign without a secret, and a control call it does not know', async () => {
  const bare = createStandInApp({ helpdeskUrl, secret: '', quiet: true });
  assert.deepEqual(await bare.status({ domain: store }), { status: 503, body: { error: 'stand_in_has_no_secret' } });
  assert.equal(received.length, 0);
  assert.equal((await control('provision', {})).status, 400);
  assert.equal((await control('erase', { domain: store })).status, 404);
});

test('signs the three agent calls, with a new pairing token for every connection it asks for', async () => {
  const agentStore = 'agent-calls.myshopify.com';
  const first = await control('agent', { domain: agentStore });
  const second = await control('agent', { domain: agentStore, extra: { inbox_ids: [5] } });
  const refused = await control('agent', { domain: agentStore, refuse: { status: 410, error: 'invalid_token' } });
  const given = await control('agent', { domain: agentStore, service_url: 'https://other-ai.example.test', token: 'given-token' });
  const replaced = await control('agent', { domain: agentStore, body: { contract: 2 } });
  const status = await control('agent-status', { domain: agentStore });
  const disconnected = await control('agent-disconnect', { domain: agentStore });

  assert.deepEqual([first, second, refused, given, replaced, status, disconnected].map(answer => answer.body.status), [201, 201, 201, 201, 201, 200, 200]);
  const path = `/inclamo/provisioning/stores/${agentStore}/agent`;
  assert.deepEqual(received.map(entry => [entry.method, entry.path]), [...Array(5).fill(['PUT', path]), ['GET', path], ['DELETE', path]]);
  assert.deepEqual(received.map(entry => entry.raw), [
    '{"contract":1,"service_url":"https://ai.example.test/channels/helpdesk","token":"pairing-token-1"}',
    '{"contract":1,"service_url":"https://ai.example.test/channels/helpdesk","token":"pairing-token-2","inbox_ids":[5]}',
    '{"contract":1,"service_url":"https://ai.example.test/channels/helpdesk","token":"pairing-token-3"}',
    '{"contract":1,"service_url":"https://other-ai.example.test","token":"given-token"}',
    '{"contract":2}',
    '',
    '',
  ]);
  // One token for each connection it made itself, asked of the AI service just before.
  assert.deepEqual(minted, [
    { path: '/__e2e/tokens', refuse: null },
    { path: '/__e2e/tokens', refuse: null },
    { path: '/__e2e/tokens', refuse: { status: 410, error: 'invalid_token' } },
  ]);
  assert.deepEqual(received.map(entry => entry.signature === expected(secret, entry)), Array(7).fill(true));
  assert.equal(new Set(received.map(entry => entry.requestId)).size, 7);
  assert.deepEqual(first.body.body, { contract: 1, state: 'connected', outcome: 'connected', inbox_ids: [3], phone_inbox_id: 12, connected_at: '2026-11-17T10:05:00Z' });
});

test('the switches work on the agent calls too, and its log holds no pairing token', async () => {
  await control('log', null, 'DELETE');
  const refused = await control('agent', { domain: store, wrong_signature: true });
  const stale = await control('agent-disconnect', { domain: store, stale: true });
  const { log } = (await control('log', null, 'GET')).body;

  assert.deepEqual([refused.body.status, stale.body.status], [401, 401]);
  assert.deepEqual(log.map(entry => [entry.method, entry.status]), [['PUT', 401], ['DELETE', 401]]);
  assert.equal(JSON.stringify(log).includes('pairing-token'), false);
});

test('signs the entry call over its method, whole path and exact body, and hands the address to the test only', async () => {
  await control('log', null, 'DELETE');
  const given = await control('entry', { domain: store, staff: { email: 'alex@example.test' } });

  assert.deepEqual([given.body.status, given.body.body], [200, { contract: 1, entry_url: entryUrl, expires_in: 60 }]);
  assert.deepEqual([received[0].method, received[0].path], ['POST', `/inclamo/provisioning/stores/${store}/entry`]);
  assert.deepEqual(JSON.parse(received[0].raw), { contract: 1, staff: { email: 'alex@example.test', email_verified: true } });
  assert.equal(received[0].signature, expected(secret, received[0]));
  const log = JSON.stringify((await control('log', null, 'GET')).body.log);
  for (const hidden of [entryUrl, 'one-time-entry-token', 'alex@example.test', 'sha256=']) assert.equal(log.includes(hidden), false, `the log holds ${hidden}`);
});

test('the entry call leaves out a field given as null, sends a replaced body as it is, and can send an earlier request unchanged', async () => {
  await control('entry', { domain: store, staff: { email: 'alex@example.test', email_verified: null } });
  await control('entry', { domain: store, body: { contract: 1, staff: { email: 'alex@example.test', email_verified: 'true' } } });
  assert.deepEqual(JSON.parse(received[0].raw), { contract: 1, staff: { email: 'alex@example.test' } });
  assert.equal(received[1].raw, '{"contract":1,"staff":{"email":"alex@example.test","email_verified":"true"}}');

  const timestamp = Math.floor(Date.now() / 1000) - 7;
  const first = await control('entry', { domain: store, staff: { email: 'alex@example.test' }, timestamp });
  await control('entry', { domain: store, staff: { email: 'alex@example.test' }, timestamp, request_id: first.body.request_id });
  const [sent, again] = received.slice(2);
  assert.deepEqual(again, sent);
  assert.equal(Number(sent.timestamp), timestamp);

  const wrong = await control('entry', { domain: store, wrong_signature: true });
  const elsewhere = await control('entry', { domain: store, helpdesk_url: otherUrl });
  assert.deepEqual([wrong.body.status, elsewhere.body.status, elsewhere.body.provisioning], [401, 404, null]);
});

// The helpdesk's side of docs/app-store-access.md §2: a signed request for a
// key, with the contract's ten scopes unless others are given.
const TEN = ['read_customers', 'read_orders', 'read_products', 'write_orders', 'write_draft_orders', 'write_customers', 'write_order_edits', 'write_discounts', 'read_locations', 'read_merchant_managed_fulfillment_orders'];
const askKey = async (domain, { prefix = '/helpdesk', accountId = 42, scopes = TEN, key = secret, requestId = crypto.randomUUID(), timestamp = Math.floor(Date.now() / 1000), base = appUrl } = {}) => {
  const path = `${prefix}/stores/${domain}/store-key`;
  const raw = JSON.stringify({ contract: 1, account_id: accountId, scopes });
  const response = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Inclamo-Timestamp': String(timestamp), 'X-Inclamo-Request-Id': requestId, 'X-Inclamo-Signature': sign(key, { timestamp, requestId, method: 'POST', path, body: raw }) },
    body: raw,
  });
  const text = await response.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }
  return { status: response.status, body, retryAfter: response.headers.get('retry-after'), cache: response.headers.get('cache-control') };
};
const keyStore = 'key-store.myshopify.com';
const keyToken = ['shpat', 'stand', 'in', 'key', '0123456789'].join('_');

test('reproduces the worked example of the store key contract', () => {
  const raw = JSON.stringify({ contract: 1, account_id: 42, scopes: TEN });
  const signature = sign('test-secret-not-for-production-0123456789abcdef', {
    timestamp: 1794000000, requestId: '4e7c2a90-6d1b-4f38-a5c2-9b1e8d3f6a07', method: 'POST', path: '/helpdesk/stores/example-store.myshopify.com/store-key', body: raw,
  });
  assert.equal(signature, 'sha256=b72c74f4156702aae0f7fa409326c14f19840cea15544d3d757b27fcae70d0b3');
});

test('grants the key the test set, with the asked scopes, its life and no-store, and logs no key', async () => {
  await control('store-keys', null, 'DELETE');
  assert.equal((await control('store-key', { domain: keyStore, access_token: keyToken })).status, 204);
  const before = Date.now();
  const granted = await askKey(keyStore);
  const narrow = await control('store-key', { domain: keyStore, access_token: keyToken, scopes: ['read_customers', 'read_orders', 'write_orders'], expires_in: 150 });
  const short = await askKey(keyStore, { prefix: '' });

  assert.equal(narrow.status, 204);
  assert.equal(granted.status, 200);
  assert.equal(granted.cache, 'no-store');
  assert.deepEqual({ ...granted.body, expires_at: undefined }, { contract: 1, shop_domain: keyStore, access_token: keyToken, expires_at: undefined, scopes: TEN });
  const life = (Date.parse(granted.body.expires_at) - before) / 1000;
  assert.ok(life > 3590 && life <= 3601, `a key of an hour, not ${life} s`);
  assert.deepEqual(short.body.scopes, ['read_customers', 'read_orders', 'write_orders']);
  const shortLife = (Date.parse(short.body.expires_at) - Date.now()) / 1000;
  assert.ok(shortLife > 140 && shortLife <= 150, `a key of 150 s, not ${shortLife} s`);
  const { requests } = (await control('store-keys', null, 'GET')).body;
  assert.deepEqual(requests.map(entry => [entry.domain, entry.path, entry.account_id, entry.signed, entry.status]), [
    [keyStore, `/helpdesk/stores/${keyStore}/store-key`, 42, true, 200],
    [keyStore, `/stores/${keyStore}/store-key`, 42, true, 200],
  ]);
  assert.deepEqual(requests[0].scopes, TEN);
  assert.equal(JSON.stringify(requests).includes(keyToken), false);
  assert.equal(JSON.stringify(app.state.log).includes(keyToken), false);
});

test('answers a key for another store and a request in another account name as the test set', async () => {
  await control('store-key', { domain: keyStore, access_token: keyToken, shop_domain: 'another-store.myshopify.com' });
  assert.equal((await askKey(keyStore)).body.shop_domain, 'another-store.myshopify.com');
  await control('store-key', { domain: keyStore, access_token: keyToken, account_id: 42 });
  assert.equal((await askKey(keyStore, { accountId: 42 })).status, 200);
  assert.deepEqual(await askKey(keyStore, { accountId: 43 }).then(answer => [answer.status, answer.body.error]), [403, 'account_mismatch']);
});

test('answers every refusal of the contract, with Retry-After where the test gave one', async () => {
  const seen = {};
  for (const answer of Object.keys(KEY_REFUSALS)) {
    await control('store-key', { domain: keyStore, answer, retry_after: 45 });
    const asked = await askKey(keyStore);
    seen[answer] = [asked.status, asked.body.error, asked.retryAfter];
  }
  assert.deepEqual(seen, {
    store_not_installed: [404, 'store_not_installed', null],
    account_mismatch: [403, 'account_mismatch', null],
    store_unavailable: [503, 'store_unavailable', '45'],
    unauthorized: [401, 'unauthorized', null],
    unprocessable: [422, 'contract_unsupported', null],
    rate_limited: [429, 'rate_limited', '45'],
    server_error: [500, 'internal_error', null],
  });
  await control('store-key', { domain: keyStore, answer: 'unreadable' });
  assert.deepEqual(await askKey(keyStore).then(asked => [asked.status, typeof asked.body]), [200, 'string']);
  // A store the test set nothing for does not have the app.
  assert.deepEqual(await askKey('never-set.myshopify.com').then(asked => [asked.status, asked.body.error]), [404, 'store_not_installed']);
  assert.equal((await control('store-key', { domain: keyStore })).status, 400);
  assert.equal((await control('store-key', { domain: keyStore, answer: 'maybe' })).status, 400);
});

test('stays silent past the helpdesk time limit when told to', async () => {
  const quietApp = createStandInApp({ helpdeskUrl, secret, quiet: true, silentMs: 300 });
  const quietUrl = await listen(quietApp.server);
  try {
    await fetch(`${quietUrl}/__e2e/store-key`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ domain: keyStore, answer: 'silent' }) });
    const started = Date.now();
    const asked = await askKey(keyStore, { base: quietUrl });
    assert.ok(Date.now() - started >= 280, 'answered only after the silence');
    assert.equal(asked.status, 504);
    assert.equal(quietApp.state.keyLog[0].status, 'silent');
  } finally {
    quietApp.server.close();
  }
});

test('refuses a key request with another secret, a stale time or a repeated request id', async () => {
  await control('store-key', { domain: keyStore, access_token: keyToken });
  const requestId = crypto.randomUUID();
  const wrong = await askKey(keyStore, { key: 'another-secret-0123456789abcdef-0123456789' });
  const stale = await askKey(keyStore, { timestamp: Math.floor(Date.now() / 1000) - STALE_SECONDS });
  const first = await askKey(keyStore, { requestId });
  const again = await askKey(keyStore, { requestId });
  assert.deepEqual([wrong, stale, first, again].map(asked => asked.status), [401, 401, 200, 401]);
  assert.deepEqual(wrong.body, { error: 'unauthorized' });
});

test('signs the four erasure calls over their method, whole path and exact body', async () => {
  const shopper = { email: 'pat@example.com', phone: '+15556251199' };
  const whole = await control('erasure', { domain: store });
  const erase = await control('shopper-erasure', { domain: store, shopper, order_ids: ['299938', '280263'] });
  const copy = await control('data-request', { domain: store, shopper: { email: 'pat@example.com' } });
  const counts = await control('shopper-requests', { domain: store });

  assert.deepEqual([whole, erase, copy, counts].map(answer => answer.body.status), [200, 200, 200, 200]);
  assert.deepEqual(whole.body.body, { contract: 1, state: 'scheduled', erase_after: '2026-11-26T10:00:00Z' });
  assert.deepEqual(received.map(entry => [entry.method, entry.path]), [
    ['POST', `/inclamo/provisioning/stores/${store}/erasure`],
    ['POST', `/inclamo/provisioning/stores/${store}/shoppers/erasure`],
    ['POST', `/inclamo/provisioning/stores/${store}/shoppers/data-request`],
    ['GET', `/inclamo/provisioning/stores/${store}/shoppers/requests`],
  ]);
  assert.equal(received[0].raw, '{"contract":1}');
  assert.deepEqual(JSON.parse(received[1].raw), { contract: 1, shopper, order_ids: ['299938', '280263'] });
  assert.deepEqual(JSON.parse(received[2].raw), { contract: 1, shopper: { email: 'pat@example.com' } });
  assert.equal(received[3].raw, '');
  assert.deepEqual(received.map(entry => entry.signature === expected(secret, entry)), [true, true, true, true]);
  assert.equal(new Set(received.map(entry => entry.requestId)).size, 4);
});

test('sends a replaced erasure body as it is, and the switches work on the erasure calls too', async () => {
  await control('erasure', { domain: store, body: { contract: 2 } });
  await control('shopper-erasure', { domain: store, body: { contract: 1, shopper: {} } });
  assert.equal(received[0].raw, '{"contract":2}');
  assert.equal(received[1].raw, '{"contract":1,"shopper":{}}');

  const wrong = await control('erasure', { domain: store, wrong_signature: true });
  const stale = await control('shopper-requests', { domain: store, stale: true });
  assert.deepEqual([wrong.body.status, stale.body.status], [401, 401]);
  const first = await control('erasure', { domain: store });
  const reused = await control('erasure', { domain: store, request_id: first.body.request_id, body: { contract: 1, again: true } });
  assert.deepEqual([reused.body.status, reused.body.body], [409, { error: 'request_id_reused' }]);
  const elsewhere = await control('erasure', { domain: store, helpdesk_url: otherUrl });
  assert.deepEqual([elsewhere.body.status, elsewhere.body.provisioning], [404, null]);
});

test('its log holds no shopper\'s email or phone', async () => {
  await control('shopper-erasure', { domain: store, shopper: { email: 'pat@example.com', phone: '+15556251199' } });
  await control('data-request', { domain: store, shopper: { email: 'pat@example.com', phone: '+15556251199' } });
  const log = JSON.stringify((await fetch(`${appUrl}/__e2e/log`).then(response => response.json())).log);
  assert.equal(log.includes('pat@example.com'), false);
  assert.equal(log.includes('5556251199'), false);
});
