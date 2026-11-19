// Tests of the stand-in app itself: it must sign as docs/app-provisioning.md
// says, and its switches must send exactly what the helpdesk has to refuse, or
// the end-to-end tests prove nothing.
//   node --test e2e/stand-in-app/server.test.mjs
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHmac } from 'node:crypto';
import { createStandInApp, sign, STALE_SECONDS } from './server.mjs';

const secret = 'secret-of-the-stand-in-app-test-0123456789abcdef';
const link = 'https://helpdesk.example.test/app/auth/password/edit?reset_password_token=one-time-token';
const store = 'example-store.myshopify.com';
const WINDOW = 300;

let app;
let appUrl;
let helpdesk;
let helpdeskUrl;
let other;
let otherUrl;
const received = [];

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
  app = createStandInApp({ helpdeskUrl, secret, quiet: true });
  appUrl = await listen(app.server);
});

after(() => {
  app.server.close();
  helpdesk.close();
  other.close();
});

beforeEach(() => {
  received.length = 0;
});

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
  assert.equal(sign(example, { timestamp: 1794000000, requestId, method: 'get', path }), 'sha256=b8c0445090549f105fbef920861ba8765304feb72969051bc5b898b30ba6a875');
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

test('refuses to sign without a secret, and a control call it does not know', async () => {
  const bare = createStandInApp({ helpdeskUrl, secret: '', quiet: true });
  assert.deepEqual(await bare.status({ domain: store }), { status: 503, body: { error: 'stand_in_has_no_secret' } });
  assert.equal(received.length, 0);
  assert.equal((await control('provision', {})).status, 400);
  assert.equal((await control('erase', { domain: store })).status, 404);
});
