// A stand-in for the store app, for the end-to-end tests. It plays the app's
// side of docs/app-provisioning.md: it signs the three calls with the secret
// it shares with the helpdesk and sends them, so every scenario runs without
// the store app.
//
// A test drives it through a control API; each call answers what the helpdesk
// answered, as { status, body, retry_after, request_id }:
//
//   POST   /__e2e/provision   { domain, shop?, admin?, body?, ...switches }
//                             PUT stores/{domain}: the store has an account.
//                             `shop` and `admin` are laid over a valid body;
//                             a field given as null is left out of it.
//                             `body` replaces the whole body.
//   POST   /__e2e/status      { domain, ...switches }   GET stores/{domain}
//   POST   /__e2e/removal     { domain, ...switches }   POST stores/{domain}/removal
//   GET    /__e2e/log         what was sent since the last DELETE /__e2e/log
//   DELETE /__e2e/log
//
// Switches, for what the store app must never send and the helpdesk must refuse:
//   wrong_signature: true   signs with another secret
//   stale: true             signs with a time ten minutes in the past
//   request_id: "<uuid>"    repeats an earlier request id instead of a new one
// and one for an installation that has no provisioning:
//   helpdesk_url: "<url>"   sends to this helpdesk instead of the stack's own
//
// It never logs or answers the secret or a signature, and its log holds no
// body: a password link passes through to the test that asked and is kept
// nowhere. No dependencies: node >= 20.
import { createServer } from 'node:http';
import { createHmac, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const STALE_SECONDS = 600;
const OTHER_SECRET = 'another-secret-the-helpdesk-was-never-given-0123456789';

// sha256=<hex HMAC-SHA256(secret, "<timestamp>.<METHOD>.<path>.<raw body>")>
export function sign(secret, { timestamp, method, path, body = '' }) {
  return `sha256=${createHmac('sha256', secret).update(`${timestamp}.${String(method).toUpperCase()}.${path}.${body}`).digest('hex')}`;
}

export const storePath = (domain, suffix = '') => `/inclamo/provisioning/stores/${domain}${suffix}`;

// A body the helpdesk accepts, with `shop` and `admin` laid over it.
export function provisionBody(domain, { shop = {}, admin = {} } = {}) {
  const without = fields => Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== null));
  return {
    contract: 1,
    shop: without({ domain, name: 'Stand-in Store', locale: 'en', timezone: 'Etc/UTC', ...shop }),
    admin: without({ email: 'staff@example.test', name: 'Stand-in Staff', email_verified: true, ...admin }),
  };
}

export function createStandInApp({ helpdeskUrl, secret, fetchImpl = fetch, quiet = false, now = () => Date.now() } = {}) {
  const state = { log: [] };
  const say = (...args) => quiet || console.log('stand-in app:', ...args);

  // Signs one call and sends it. The body is signed as the bytes that are sent.
  async function call(method, path, raw, switches = {}) {
    if (!secret) return { status: 503, body: { error: 'stand_in_has_no_secret' } };
    const base = String(switches.helpdesk_url || helpdeskUrl || '').replace(/\/$/, '');
    const requestId = switches.request_id || randomUUID();
    const timestamp = Math.floor(now() / 1000) - (switches.stale ? STALE_SECONDS : 0);
    const signature = sign(switches.wrong_signature ? OTHER_SECRET : secret, { timestamp, method, path, body: raw });
    const response = await fetchImpl(`${base}${path}`, {
      method,
      headers: {
        ...(raw ? { 'Content-Type': 'application/json' } : {}),
        'X-Inclamo-Timestamp': String(timestamp),
        'X-Inclamo-Request-Id': requestId,
        'X-Inclamo-Signature': signature,
      },
      body: raw || undefined,
      signal: AbortSignal.timeout(10_000),
    });
    const text = await response.text();
    const body = parse(text);
    state.log.push({
      at: new Date(now()).toISOString(),
      method,
      path,
      request_id: requestId,
      status: response.status,
      ...(body?.outcome ? { outcome: body.outcome } : {}),
      ...(body?.error ? { error: body.error } : {}),
    });
    if (state.log.length > 2000) state.log.shift();
    say(`${method} ${path} answered ${response.status}`);
    return { status: response.status, body, retry_after: response.headers.get('retry-after'), request_id: requestId };
  }

  const calls = {
    provision: ({ domain, shop, admin, body, ...switches }) =>
      call('PUT', storePath(domain), JSON.stringify(body === undefined ? provisionBody(domain, { shop, admin }) : body), switches),
    status: ({ domain, ...switches }) => call('GET', storePath(domain), '', switches),
    removal: ({ domain, ...switches }) => call('POST', storePath(domain, '/removal'), '', switches),
  };

  async function control(request, path, raw, response) {
    const name = path.slice('/__e2e/'.length);
    if (name === 'log' && request.method === 'GET') return send(response, 200, { log: state.log });
    if (name === 'log' && request.method === 'DELETE') {
      state.log = [];
      return send(response, 204);
    }
    if (request.method === 'POST' && calls[name]) {
      const asked = parse(raw);
      if (!asked?.domain) return send(response, 400, { error: 'domain_missing' });
      return send(response, 200, await calls[name](asked));
    }
    return send(response, 404, { error: 'not_found' });
  }

  const server = createServer((request, response) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8');
      const path = new URL(request.url, 'http://stand-in-app').pathname;
      Promise.resolve()
        .then(() => (path.startsWith('/__e2e/') ? control(request, path, raw, response) : send(response, 404, { error: 'not_found' })))
        .catch(error => {
          say(`a request failed: ${error.name}`);
          if (!response.headersSent) send(response, 502, { error: 'helpdesk_unreachable' });
        });
    });
  });

  return { server, state, ...calls };
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
  const port = Number(process.env.PORT || 8091);
  const helpdeskUrl = process.env.HELPDESK_URL || 'http://rails:3000';
  const secret = (process.env.INCLAMO_APP_PROVISIONING_SECRET || '').trim();
  if (!secret) console.log('stand-in app: no INCLAMO_APP_PROVISIONING_SECRET, every call will answer 503');
  createStandInApp({ helpdeskUrl, secret }).server.listen(port, () => console.log(`stand-in app: listening on ${port} for ${helpdeskUrl}`));
}
