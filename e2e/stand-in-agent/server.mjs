// A stand-in for the AI service, for the end-to-end tests (design D10). It
// implements the helpdesk's side of docs/ai-connector.md by fixed rules, so
// every flow runs without the AI service:
//   - issues connection codes and answers the registration and removal calls;
//   - checks each delivery's signature, refuses a timestamp older than five
//     minutes, drops a delivery id it has seen, answers 200 at once and then
//     takes its turn through the helpdesk's API with the bot's token,
//     replying through the protected reply (§5.4) and ending the turn when it
//     is refused with 409 conversation_not_pending;
//   - a control API under /__e2e lets a test read what it received and make
//     it answer 503.
// Rules on the shopper's text: "person" or "human" hands over with a note and
// inclamo_handover; "urgent" raises the priority, adds inclamo_urgent and
// hands over; "resolve" replies and resolves; "intent" adds
// inclamo_intent_test; "slow" waits (6 s, or what /__e2e/slow set) before its
// reply, as a model would; a message with files gets a reply naming the files
// it received and the shopper's files in the conversation; anything else a
// reply.
//
// It never logs or answers a token or a secret. No dependencies: node >= 20.
import { createServer } from 'node:http';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const MAX_AGE_SECONDS = 300;

export function createStandIn({ publicUrl, fetchImpl = fetch, quiet = false } = {}) {
  const state = {
    codes: new Map(), // token -> { refuse, used }
    connections: new Map(), // id -> connection
    seen: new Set(),
    log: [],
    // Whole bodies of the last deliveries, for docs/ai-connector.md's samples.
    raw: [],
    failWith: null,
    slowMs: 6000,
    sequence: 0,
    queues: new Map(),
  };
  const say = (...args) => quiet || console.log('stand-in:', ...args);
  const record = entry => {
    state.log.push({ at: new Date().toISOString(), ...entry });
    if (state.log.length > 2000) state.log.shift();
  };
  const latest = () => [...state.connections.values()].at(-1);

  async function helpdesk(connection, method, path, body) {
    const url = `${connection.helpdesk_url}/api/v1/accounts/${connection.account_id}${path}`;
    const response = await fetchImpl(url, {
      method,
      headers: { 'Content-Type': 'application/json', api_access_token: connection.bot.access_token },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch (error) {
      data = null;
    }
    return { status: response.status, body: data };
  }

  async function act(connection, conversationId, action, call) {
    const result = await call();
    record({ kind: 'action', connection_id: connection.id, conversation_id: conversationId, action, status: result.status });
    if (result.status >= 300) say(`${action} on conversation ${conversationId} answered ${result.status}`);
    return result;
  }

  // The protected reply was refused: the team has the conversation, and the
  // turn ends without another call (docs/ai-connector.md §5.4).
  class TurnEnded extends Error {}

  // One turn for one shopper's message, by the rules above.
  async function turn(connection, event) {
    const id = event.conversation.id;
    const conv = `/conversations/${id}`;
    const text = String(event.content || '').toLowerCase();
    const files = (event.attachments || []).length;
    const reply = async content => {
      const result = await act(connection, id, 'reply', () => helpdesk(connection, 'POST', `/inclamo/ai/conversations/${id}/reply`, { content }));
      if (result.status === 409 && result.body?.error === 'conversation_not_pending') {
        record({ kind: 'turn_ended', conversation_id: id, reason: 'conversation_not_pending', status: result.body.status });
        throw new TurnEnded();
      }
      return result;
    };
    const note = content => act(connection, id, 'note', () => helpdesk(connection, 'POST', `${conv}/messages`, { content, private: true }));
    const label = names => act(connection, id, 'labels', () => helpdesk(connection, 'POST', `/inclamo/ai/conversations/${id}/labels`, { add: names }));
    const status = value => act(connection, id, `status_${value}`, () => helpdesk(connection, 'POST', `${conv}/toggle_status`, { status: value }));

    if (/\b(person|human)\b/.test(text)) {
      await note('The shopper asked for a person.');
      await label(['inclamo_handover']);
      await status('open');
    } else if (/\burgent\b/.test(text)) {
      await act(connection, id, 'priority', () => helpdesk(connection, 'POST', `${conv}/toggle_priority`, { priority: 'urgent' }));
      await label(['inclamo_urgent', 'inclamo_handover']);
      await note('Urgent request: handed to the team.');
      await status('open');
    } else if (/\bresolve\b/.test(text)) {
      await reply('Glad to help. Closing this conversation.');
      await label(['inclamo_resolved']);
      await status('resolved');
    } else if (/\bintent\b/.test(text)) {
      await label(['inclamo_intent_test']);
      await reply('Noted the type of your request.');
    } else if (/\bslow\b/.test(text)) {
      await new Promise(resolve => setTimeout(resolve, state.slowMs));
      await reply('A slow answer, composed before anyone took the conversation.');
    } else if (files > 0) {
      const history = await act(connection, id, 'history', () => helpdesk(connection, 'GET', `/inclamo/ai/conversations/${id}/messages`));
      const shopperFiles = history.body?.shopper_files ?? 0;
      record({ kind: 'files_named', conversation_id: id, in_message: files, in_conversation: shopperFiles });
      await reply(`I received ${files} file${files === 1 ? '' : 's'} in this message, ${shopperFiles} from you in this conversation.`);
    } else {
      await reply('Hello, I am the AI agent. How can I help?');
    }
  }

  // Turns of one conversation run one after another.
  function enqueue(connection, event) {
    const key = `${connection.id}:${event.conversation.id}`;
    const previous = state.queues.get(key) || Promise.resolve();
    const next = previous.then(() => turn(connection, event)).catch(error => {
      if (error instanceof TurnEnded) return;
      record({ kind: 'turn_failed', conversation_id: event.conversation.id, error: error.name });
      say(`a turn failed: ${error.name}`);
    });
    state.queues.set(key, next);
    return next;
  }

  // An incoming message is the shopper's: Chatwoot's payload of a contact
  // carries no `type` (app/models/contact.rb, webhook_data).
  const takesTurn = (connection, event) =>
    event.event === 'message_created' &&
    event.message_type === 'incoming' &&
    event.private === false &&
    event.conversation?.status === 'pending' &&
    connection.inbox_ids.includes(event.conversation?.inbox_id);

  // --- the AI service's endpoints -------------------------------------------

  function registration(request, body, response) {
    const token = bearer(request);
    const code = token && state.codes.get(token);
    if (!code) return send(response, 401, { error: 'unknown_code', message: 'This connection code is not known.' });
    if (code.refuse) return send(response, code.refuse.status || 410, { error: code.refuse.error || 'refused', message: code.refuse.message || 'Refused.' });
    if (code.used) return send(response, 409, { error: 'used', message: 'This connection code was used already.' });
    const data = parse(body);
    if (!data || data.contract !== 1 || !data.bot?.access_token || !data.bot?.secret) return send(response, 400, { error: 'invalid', message: 'The registration is not one of contract 1.' });
    code.used = true;
    state.sequence += 1;
    const id = `c${state.sequence}-${randomBytes(3).toString('hex')}`;
    const connection = {
      id,
      account_id: data.account.id,
      helpdesk_url: String(data.helpdesk_url || '').replace(/\/$/, ''),
      bot: { id: data.bot.id, access_token: data.bot.access_token, secret: data.bot.secret },
      inbox_ids: data.inbox_ids || [],
      phone_inbox_id: data.phone_inbox_id,
      removed: false,
    };
    state.connections.set(id, connection);
    record({ kind: 'registration', connection_id: id, account_id: connection.account_id, inbox_ids: connection.inbox_ids, phone_inbox_id: connection.phone_inbox_id, bot_id: connection.bot.id });
    say(`registered connection ${id} for account ${connection.account_id}`);
    return send(response, 201, { connection_id: id, webhook_url: `${publicUrl}/webhooks/${id}` });
  }

  function removal(request, id, response) {
    const connection = state.connections.get(id);
    if (!connection || bearer(request) !== connection.bot.access_token) return send(response, 401, { error: 'unauthorized', message: 'Unknown connection.' });
    connection.removed = true;
    record({ kind: 'removal', connection_id: id });
    say(`removed connection ${id}`);
    return send(response, 204);
  }

  function delivery(request, id, raw, response) {
    const connection = state.connections.get(id);
    const deliveryId = request.headers['x-chatwoot-delivery'];
    const event = parse(raw) || {};
    const entry = {
      kind: 'delivery',
      connection_id: id,
      delivery_id: deliveryId,
      event: event.event,
      message_type: event.message_type,
      sender_type: event.sender?.type ?? null,
      private: event.private,
      content: event.content,
      attachments: (event.attachments || []).map(file => ({ file_type: file.file_type, content_type: file.content_type, file_size: file.file_size, has_url: !!file.data_url })),
      conversation_id: event.conversation?.id ?? event.id,
      conversation_status: event.conversation?.status ?? event.status,
      changed: event.changed_attributes ? event.changed_attributes.flatMap(change => Object.keys(change)) : undefined,
    };
    if (!connection || connection.removed) return reply(404, 'unknown_connection');
    state.raw.push({ conversation_id: entry.conversation_id, event: event.event, body: event });
    if (state.raw.length > 300) state.raw.shift();
    const verdict = verify(connection.bot.secret, request.headers, raw);
    if (verdict !== 'valid') return reply(401, verdict);
    if (state.seen.has(deliveryId)) return reply(200, 'duplicate');
    state.seen.add(deliveryId);
    if (state.failWith) return reply(state.failWith, 'failing_on_purpose');
    reply(200, 'accepted');
    if (takesTurn(connection, event)) enqueue(connection, event);
    return undefined;

    function reply(status, outcome) {
      record({ ...entry, verified: outcome !== 'bad_signature' && outcome !== 'old_timestamp' && outcome !== 'unknown_connection', outcome, answered: status });
      return send(response, status, { outcome });
    }
  }

  // --- the tests' control API -------------------------------------------------

  async function control(request, path, body, response) {
    const data = parse(body) || {};
    if (request.method === 'POST' && path === '/__e2e/codes') {
      const token = randomBytes(24).toString('base64url');
      state.codes.set(token, { refuse: data.refuse || null, used: false });
      const code = `aic1.${Buffer.from(JSON.stringify({ service_url: publicUrl, token })).toString('base64url')}`;
      return send(response, 201, { code });
    }
    if (request.method === 'GET' && path === '/__e2e/log') return send(response, 200, { log: state.log });
    if (request.method === 'GET' && path === '/__e2e/raw') {
      const wanted = Number(new URL(request.url, 'http://stand-in').searchParams.get('conversation_id'));
      return send(response, 200, { deliveries: state.raw.filter(item => item.conversation_id === wanted) });
    }
    if (request.method === 'DELETE' && path === '/__e2e/log') {
      state.log = [];
      return send(response, 204);
    }
    if (request.method === 'POST' && path === '/__e2e/slow') {
      state.slowMs = Number.isInteger(data.ms) && data.ms >= 0 ? data.ms : 6000;
      return send(response, 200, { slow_ms: state.slowMs });
    }
    if (request.method === 'POST' && path === '/__e2e/fail') {
      state.failWith = data.status ? Number(data.status) : null;
      return send(response, 200, { fail_with: state.failWith });
    }
    if (request.method === 'GET' && path === '/__e2e/connection') {
      const connection = latest();
      if (!connection) return send(response, 404, {});
      return send(response, 200, { id: connection.id, account_id: connection.account_id, inbox_ids: connection.inbox_ids, phone_inbox_id: connection.phone_inbox_id, bot_id: connection.bot.id, removed: connection.removed });
    }
    // What the agent reads of a conversation, through the helpdesk's endpoint.
    if (request.method === 'POST' && path === '/__e2e/read') {
      const connection = latest();
      if (!connection) return send(response, 404, {});
      const result = await helpdesk(connection, 'GET', `/inclamo/ai/conversations/${data.conversation_id}/messages${data.limit ? `?limit=${data.limit}` : ''}`);
      return send(response, 200, result);
    }
    // Deterministic order-tool calls use the registered bot token internally.
    // Only the private test stack exposes this control API; secrets never leave it.
    if (request.method === 'POST' && path === '/__e2e/order-tool') {
      const connection = latest();
      if (!connection) return send(response, 404, {});
      if (!Number.isInteger(data.conversation_id) || !['context', 'propose', 'execute'].includes(data.tool)) return send(response, 400, { error: 'invalid_tool' });
      const root = `/inclamo/ai/conversations/${data.conversation_id}`;
      if (data.tool === 'execute' && !Number.isInteger(data.proposal_id)) return send(response, 400, { error: 'invalid_proposal' });
      const route = data.tool === 'context' ? `${root}/orders` : data.tool === 'propose' ? `${root}/proposals` : `${root}/proposals/${data.proposal_id}/execute`;
      return send(response, 200, await helpdesk(connection, data.tool === 'context' ? 'GET' : 'POST', route, data.payload));
    }
    // A reply with the latest connection's token, even after it was removed:
    // through Chatwoot's message call, or the protected reply with `protected`.
    if (request.method === 'POST' && path === '/__e2e/reply') {
      const connection = latest();
      if (!connection) return send(response, 404, {});
      const content = typeof data.content === 'string' ? data.content : 'A reply of the stand-in.';
      const route = data.protected ? `/inclamo/ai/conversations/${data.conversation_id}/reply` : `/conversations/${data.conversation_id}/messages`;
      const result = await helpdesk(connection, 'POST', route, { content });
      return send(response, 200, { status: result.status, body: result.body });
    }
    return send(response, 404, { error: 'not_found' });
  }

  const server = createServer((request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      const path = new URL(request.url, 'http://stand-in').pathname;
      Promise.resolve()
        .then(() => {
          if (path.startsWith('/__e2e/')) return control(request, path, raw, response);
          if (request.method === 'POST' && path === '/connections') return registration(request, raw, response);
          const removing = path.match(/^\/connections\/([^/]+)$/);
          if (request.method === 'DELETE' && removing) return removal(request, decodeURIComponent(removing[1]), response);
          const hook = path.match(/^\/webhooks\/([^/]+)$/);
          if (request.method === 'POST' && hook) return delivery(request, hook[1], raw, response);
          return send(response, 404, { error: 'not_found' });
        })
        .catch(error => {
          say(`a request failed: ${error.name}`);
          if (!response.headersSent) send(response, 500, { error: 'stand_in_failed' });
        });
    });
  });

  return { server, state, idle: () => Promise.all(state.queues.values()) };
}

// 'valid', 'bad_signature' or 'old_timestamp' (docs/ai-connector.md §2.1).
export function verify(secret, headers, raw, now = Date.now()) {
  const timestamp = headers['x-chatwoot-timestamp'];
  const signature = String(headers['x-chatwoot-signature'] || '');
  const expected = `sha256=${createHmac('sha256', secret).update(`${timestamp}.${raw}`).digest('hex')}`;
  const given = Buffer.from(signature);
  const wanted = Buffer.from(expected);
  if (!timestamp || given.length !== wanted.length || !timingSafeEqual(given, wanted)) return 'bad_signature';
  if (Math.abs(now / 1000 - Number(timestamp)) > MAX_AGE_SECONDS) return 'old_timestamp';
  return 'valid';
}

function bearer(request) {
  const [scheme, token] = String(request.headers.authorization || '').split(' ');
  return scheme === 'Bearer' && token ? token : null;
}

function parse(text) {
  try {
    return text ? JSON.parse(text) : null;
  } catch (error) {
    return null;
  }
}

function send(response, status, body) {
  response.writeHead(status, body === undefined ? {} : { 'Content-Type': 'application/json' });
  response.end(body === undefined ? undefined : JSON.stringify(body));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 8090);
  const publicUrl = (process.env.PUBLIC_URL || `http://localhost:${port}`).replace(/\/$/, '');
  createStandIn({ publicUrl }).server.listen(port, () => console.log(`stand-in: listening on ${port} as ${publicUrl}`));
}
