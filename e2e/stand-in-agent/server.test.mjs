// Tests of the stand-in agent itself: it must refuse what the AI service
// refuses (docs/ai-connector.md §2.1), or the end-to-end tests prove nothing.
//   node --test e2e/stand-in-agent/server.test.mjs
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createHmac, randomUUID } from 'node:crypto';
import { createStandIn, verify } from './server.mjs';

let agent;
let agentUrl;
let helpdesk;
let helpdeskUrl;
const calls = [];

const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve(`http://127.0.0.1:${server.address().port}`)));

before(async () => {
  // A helpdesk that records what the stand-in asks of it.
  helpdesk = createServer((request, response) => {
    let body = '';
    request.on('data', chunk => (body += chunk));
    request.on('end', () => {
      calls.push({ method: request.method, url: request.url, token: request.headers.api_access_token, body: body ? JSON.parse(body) : null });
      // The protected reply of a conversation the team took is refused.
      if (request.url.endsWith('/inclamo/ai/conversations/88/reply')) {
        response.writeHead(409, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify({ error: 'conversation_not_pending', status: 'open' }));
        return;
      }
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ shopper_files: 1 }));
    });
  });
  helpdeskUrl = await listen(helpdesk);
  const port = await new Promise(resolve => {
    const probe = createServer().listen(0, '127.0.0.1', () => {
      const { port: free } = probe.address();
      probe.close(() => resolve(free));
    });
  });
  agentUrl = `http://127.0.0.1:${port}`;
  agent = createStandIn({ publicUrl: agentUrl, quiet: true });
  await new Promise(resolve => agent.server.listen(port, '127.0.0.1', resolve));
});

after(() => {
  agent.server.close();
  helpdesk.close();
});

const json = async response => (response.status === 204 ? null : response.json());
const post = async (path, body, headers = {}) => {
  const response = await fetch(`${agentUrl}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body) });
  return { status: response.status, body: await json(response) };
};

const secret = 'secret-of-the-test-bot';
const token = 'token-of-the-test-bot';

async function connect() {
  const { body } = await post('/__e2e/codes', {});
  const decoded = JSON.parse(Buffer.from(body.code.slice('aic1.'.length), 'base64url').toString());
  assert.equal(decoded.service_url, agentUrl);
  const registration = {
    contract: 1,
    helpdesk_url: helpdeskUrl,
    account: { id: 1, name: 'Shop' },
    bot: { id: 7, access_token: token, secret },
    phone_inbox_id: 12,
    inbox_ids: [3],
  };
  const answer = await post('/connections', registration, { Authorization: `Bearer ${decoded.token}` });
  assert.equal(answer.status, 201);
  return answer.body;
}

const event = (overrides = {}) => ({
  event: 'message_created',
  id: 901,
  content: 'Hello',
  message_type: 'incoming',
  private: false,
  // A contact as Chatwoot sends it: no `type`.
  sender: { id: 5, name: 'Shopper', contact_type: 'visitor' },
  account: { id: 1 },
  conversation: { id: 41, inbox_id: 3, status: 'pending' },
  ...overrides,
});

const signed = (raw, { timestamp = Math.floor(Date.now() / 1000), key = secret, delivery = randomUUID() } = {}) => ({
  'X-Chatwoot-Timestamp': String(timestamp),
  'X-Chatwoot-Signature': `sha256=${createHmac('sha256', key).update(`${timestamp}.${raw}`).digest('hex')}`,
  'X-Chatwoot-Delivery': delivery,
});

test('issues a code that registers once, and answers the webhook address', async () => {
  const { body: issued } = await post('/__e2e/codes', {});
  const { token: oneTime } = JSON.parse(Buffer.from(issued.code.slice(5), 'base64url').toString());
  const registration = { contract: 1, helpdesk_url: helpdeskUrl, account: { id: 2, name: 'Shop' }, bot: { id: 8, access_token: 't', secret: 's' }, inbox_ids: [1] };

  const first = await post('/connections', registration, { Authorization: `Bearer ${oneTime}` });
  const second = await post('/connections', registration, { Authorization: `Bearer ${oneTime}` });
  const unknown = await post('/connections', registration, { Authorization: 'Bearer nothing' });

  assert.equal(first.status, 201);
  assert.match(first.body.webhook_url, new RegExp(`^${agentUrl}/webhooks/`));
  assert.equal(second.status, 409);
  assert.equal(unknown.status, 401);
});

test('refuses a code it was told to refuse, in its own words', async () => {
  const { body } = await post('/__e2e/codes', { refuse: { status: 410, error: 'expired', message: 'This connection code has expired.' } });
  const { token: oneTime } = JSON.parse(Buffer.from(body.code.slice(5), 'base64url').toString());

  const answer = await post('/connections', { contract: 1 }, { Authorization: `Bearer ${oneTime}` });

  assert.equal(answer.status, 410);
  assert.deepEqual(answer.body, { error: 'expired', message: 'This connection code has expired.' });
});

test('refuses a delivery with a wrong signature', async () => {
  const { connection_id: id } = await connect();
  const raw = JSON.stringify(event());

  const wrongKey = await post(`/webhooks/${id}`, raw, signed(raw, { key: 'another-secret' }));
  const altered = await post(`/webhooks/${id}`, raw.replace('Hello', 'Hullo'), signed(raw));
  const missing = await post(`/webhooks/${id}`, raw, {});

  for (const answer of [wrongKey, altered, missing]) {
    assert.equal(answer.status, 401);
    assert.equal(answer.body.outcome, 'bad_signature');
  }
});

test('refuses a delivery whose timestamp is older than five minutes', async () => {
  const { connection_id: id } = await connect();
  const raw = JSON.stringify(event());

  const old = await post(`/webhooks/${id}`, raw, signed(raw, { timestamp: Math.floor(Date.now() / 1000) - 301 }));

  assert.equal(old.status, 401);
  assert.equal(old.body.outcome, 'old_timestamp');
  assert.equal(verify(secret, { 'x-chatwoot-timestamp': '100', 'x-chatwoot-signature': signed(raw, { timestamp: 100 })['X-Chatwoot-Signature'] }, raw, 100_000), 'valid');
});

test('takes a repeated delivery once, and replies once through the helpdesk with the bot token', async () => {
  const { connection_id: id } = await connect();
  calls.length = 0;
  const raw = JSON.stringify(event({ conversation: { id: 77, inbox_id: 3, status: 'pending' } }));
  const headers = signed(raw);

  const first = await post(`/webhooks/${id}`, raw, headers);
  const again = await post(`/webhooks/${id}`, raw, { ...headers, 'X-Chatwoot-Timestamp': headers['X-Chatwoot-Timestamp'] });
  await agent.idle();

  assert.equal(first.status, 200);
  assert.equal(first.body.outcome, 'accepted');
  assert.equal(again.status, 200);
  assert.equal(again.body.outcome, 'duplicate');
  const replies = calls.filter(call => call.url === '/api/v1/accounts/1/inclamo/ai/conversations/77/reply');
  assert.equal(replies.length, 1);
  assert.equal(replies[0].token, token);
  assert.equal(calls.filter(call => call.url.endsWith('/conversations/77/messages')).length, 0);
});

test('ends the turn when its protected reply is refused: no retry, no hand-over, no other call', async () => {
  const { connection_id: id } = await connect();
  calls.length = 0;
  const raw = JSON.stringify(event({ content: 'please resolve this', conversation: { id: 88, inbox_id: 3, status: 'pending' } }));

  assert.equal((await post(`/webhooks/${id}`, raw, signed(raw))).status, 200);
  await agent.idle();

  assert.deepEqual(calls.map(call => call.url), ['/api/v1/accounts/1/inclamo/ai/conversations/88/reply']);
  const log = (await (await fetch(`${agentUrl}/__e2e/log`)).json()).log;
  assert.ok(log.some(entry => entry.kind === 'turn_ended' && entry.conversation_id === 88 && entry.reason === 'conversation_not_pending'));
  assert.ok(!log.some(entry => entry.kind === 'turn_failed' && entry.conversation_id === 88));
});

test('takes no turn for its own replies, private notes, other inboxes or a conversation that is not pending', async () => {
  const { connection_id: id } = await connect();
  calls.length = 0;
  const others = [
    event({ message_type: 'outgoing', sender: { type: 'agent_bot' } }),
    event({ message_type: 'outgoing', sender: { type: 'user' }, private: true }),
    event({ conversation: { id: 41, inbox_id: 99, status: 'pending' } }),
    event({ conversation: { id: 41, inbox_id: 3, status: 'open' } }),
    { event: 'conversation_status_changed', id: 41, status: 'open', account: { id: 1 } },
  ];
  for (const body of others) {
    const raw = JSON.stringify(body);
    assert.equal((await post(`/webhooks/${id}`, raw, signed(raw))).status, 200);
  }
  await agent.idle();

  assert.equal(calls.length, 0);
});

test('answers 503 when told to, and takes deliveries again after', async () => {
  const { connection_id: id } = await connect();
  await post('/__e2e/fail', { status: 503 });
  const raw = JSON.stringify(event({ content: 'resolve' }));

  const failing = await post(`/webhooks/${id}`, raw, signed(raw));
  await post('/__e2e/fail', { status: null });
  const back = await post(`/webhooks/${id}`, raw, signed(raw));
  await agent.idle();

  assert.equal(failing.status, 503);
  assert.equal(back.status, 200);
});

test('files a finished call with the bot token, and logs its id and the answer only', async () => {
  await connect();
  calls.length = 0;
  const call = { call_id: 'c-test-1', entry: 'inbound', record: 'Resolved by the agent', turns: [{ role: 'caller', text: 'A caller turn' }] };

  const answer = await post('/__e2e/call', { call });

  assert.equal(answer.status, 200);
  assert.equal(answer.body.status, 200);
  assert.deepEqual(calls.map(entry => [entry.method, entry.url, entry.token]), [['POST', '/api/v1/accounts/1/inclamo/calls', token]]);
  assert.deepEqual(calls[0].body, call);
  const { log } = await (await fetch(`${agentUrl}/__e2e/log`)).json();
  const filed = log.filter(entry => entry.kind === 'call_filed').at(-1);
  assert.deepEqual([filed.call_id, filed.status], ['c-test-1', 200]);
  assert.ok(!JSON.stringify(filed).includes('A caller turn'));
});

test('keeps no token or secret in its log', async () => {
  const log = await (await fetch(`${agentUrl}/__e2e/log`)).text();

  assert.ok(!log.includes(token));
  assert.ok(!log.includes(secret));
});
