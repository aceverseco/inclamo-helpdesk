// A stand-in for the store app, for the end-to-end tests. It plays the app's
// side of docs/app-provisioning.md, docs/app-storefront-chat.md and
// docs/app-agent-connection.md: it signs
// the calls with the secret it shares with the helpdesk and sends them, and it
// serves a storefront page that shows the chat widget as the app's theme embed
// would, so every scenario runs without the store app.
//
// A test drives it through a control API; each call answers what the helpdesk
// answered, as { status, body, retry_after, provisioning, request_id }, where
// `provisioning` is the answer's X-Inclamo-Provisioning header (null without):
//
//   POST   /__e2e/provision   { domain, shop?, admin?, store_access_url?, body?, ...switches }
//                             PUT stores/{domain}: the store has an account.
//                             `shop` and `admin` are laid over a valid body;
//                             a field given as null is left out of it.
//                             `store_access_url` is added to it.
//                             `body` replaces the whole body.
//   POST   /__e2e/status      { domain, ...switches }   GET stores/{domain}
//   POST   /__e2e/removal     { domain, ...switches }   POST stores/{domain}/removal
//   POST   /__e2e/storefront-chat         { domain, storefront_url?, body?, ...switches }
//                             PUT stores/{domain}/storefront-chat: the store
//                             has its storefront inbox. `body` replaces the body.
//   POST   /__e2e/storefront-chat-status  { domain, ...switches }
//                             GET stores/{domain}/storefront-chat
//   POST   /__e2e/agent       { domain, service_url?, token?, refuse?, extra?, body?, ...switches }
//                             PUT stores/{domain}/agent: the store's account is
//                             connected to the AI agent. Without `token` the
//                             app takes a new pairing token from the stand-in
//                             agent (`refuse` is passed to it, to make the AI
//                             service refuse or answer late) and sends the
//                             address the agent gave unless `service_url` names
//                             another. `extra` is laid over the body; `body`
//                             replaces it. Waits 15 s for the answer.
//   POST   /__e2e/agent-status      { domain, ...switches }   GET stores/{domain}/agent
//   POST   /__e2e/agent-disconnect  { domain, ...switches }   DELETE stores/{domain}/agent
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
// The storefront page, for a browser:
//
//   GET    /storefront/{domain}   a page of the store's site. It loads the
//                             widget exactly as docs/app-storefront-chat.md §4
//                             has the app embed do, with the two values the
//                             helpdesk last answered for that store, and sets
//                             no presentation option. Before any answer it is
//                             a page without a chat. The values are replaced
//                             only by a later answer that carries values: an
//                             answer that there is no chat leaves the page as a
//                             storefront whose embed was not updated yet.
//
// It never logs or answers the secret or a signature, and its log holds no
// body: a password link passes through to the test that asked and is kept
// nowhere, and so does a pairing token, which the helpdesk is sent once. The two widget values it keeps are public ones. No dependencies:
// node >= 20.
import { createServer } from 'node:http';
import { createHmac, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const STALE_SECONDS = 600;
const OTHER_SECRET = 'another-secret-the-helpdesk-was-never-given-0123456789';

// sha256=<hex HMAC-SHA256(secret, "<timestamp>.<request id>.<METHOD>.<path>.<raw body>")>
export function sign(secret, { timestamp, requestId, method, path, body = '' }) {
  return `sha256=${createHmac('sha256', secret).update(`${timestamp}.${requestId}.${String(method).toUpperCase()}.${path}.${body}`).digest('hex')}`;
}

export const storePath = (domain, suffix = '') => `/inclamo/provisioning/stores/${domain}${suffix}`;

// A body the helpdesk accepts, with `shop` and `admin` laid over it.
export function provisionBody(domain, { shop = {}, admin = {}, store_access_url } = {}) {
  const without = fields => Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== null));
  return {
    contract: 1,
    shop: without({ domain, name: 'Stand-in Store', locale: 'en', timezone: 'Etc/UTC', ...shop }),
    admin: without({ email: 'staff@example.test', name: 'Stand-in Staff', email_verified: true, ...admin }),
    ...(store_access_url === undefined ? {} : { store_access_url }),
  };
}

// The storefront page: the snippet of docs/app-storefront-chat.md §4 with the
// two answered values, or no script at all while the app holds none.
export function storefrontPage(domain, values) {
  const embed = values
    ? `<script>
      (function (d, t) {
        var BASE_URL = ${inline(values.widget_base_url)};
        var g = d.createElement(t), s = d.getElementsByTagName(t)[0];
        g.src = BASE_URL + "/packs/js/sdk.js";
        g.async = true;
        s.parentNode.insertBefore(g, s);
        g.onload = function () {
          window.chatwootSDK.run({ websiteToken: ${inline(values.website_token)}, baseUrl: BASE_URL });
        };
      })(document, "script");
    </script>`
    : '<!-- no storefront chat -->';
  return `<!doctype html>
<html lang="en">
  <head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${html(domain)}</title></head>
  <body style="font:16px system-ui;margin:32px">
    <h1>${html(domain)}</h1>
    <p>A page of the store's site, with the store app's chat embed.</p>
    ${embed}
  </body>
</html>`;
}

const html = text => String(text).replace(/[&<>"']/g, character => `&#${character.charCodeAt(0)};`);
// A value inside an inline script: JSON, with nothing that could end the script.
const inline = value => JSON.stringify(String(value)).replace(/</g, '\\u003c');

// The body of "the store has its storefront inbox"; without an address the
// field is left out.
export const chatBody = storefrontUrl => ({ contract: 1, ...(storefrontUrl === undefined ? {} : { storefront_url: storefrontUrl }) });

// The body of "the store's account is connected to the agent": the pairing
// token's two fields, and `extra` laid over them (fields the contract does not
// have, such as inboxes, which the helpdesk must ignore).
export const agentBody = ({ service_url: serviceUrl, token }, extra = {}) => ({ contract: 1, service_url: serviceUrl, token, ...extra });

export function createStandInApp({ helpdeskUrl, secret, agentUrl, fetchImpl = fetch, quiet = false, now = () => Date.now() } = {}) {
  // `chats` is what the app would keep where its theme extension reads it:
  // per store, the two widget values of the helpdesk's last answer.
  const state = { log: [], chats: new Map() };
  const say = (...args) => quiet || console.log('stand-in app:', ...args);

  // Signs one call and sends it. The body is signed as the bytes that are sent.
  async function call(method, path, raw, switches = {}, waitMs = 10_000) {
    if (!secret) return { status: 503, body: { error: 'stand_in_has_no_secret' } };
    const base = String(switches.helpdesk_url || helpdeskUrl || '').replace(/\/$/, '');
    const requestId = switches.request_id || randomUUID();
    const timestamp = Math.floor(now() / 1000) - (switches.stale ? STALE_SECONDS : 0);
    const signature = sign(switches.wrong_signature ? OTHER_SECRET : secret, { timestamp, requestId, method, path, body: raw });
    const response = await fetchImpl(`${base}${path}`, {
      method,
      headers: {
        ...(raw ? { 'Content-Type': 'application/json' } : {}),
        'X-Inclamo-Timestamp': String(timestamp),
        'X-Inclamo-Request-Id': requestId,
        'X-Inclamo-Signature': signature,
      },
      body: raw || undefined,
      signal: AbortSignal.timeout(waitMs),
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
    return {
      status: response.status,
      body,
      retry_after: response.headers.get('retry-after'),
      provisioning: response.headers.get('x-inclamo-provisioning'),
      request_id: requestId,
    };
  }

  const calls = {
    provision: ({ domain, shop, admin, store_access_url, body, ...switches }) =>
      call('PUT', storePath(domain), JSON.stringify(body === undefined ? provisionBody(domain, { shop, admin, store_access_url }) : body), switches),
    status: ({ domain, ...switches }) => call('GET', storePath(domain), '', switches),
    removal: ({ domain, ...switches }) => call('POST', storePath(domain, '/removal'), '', switches),
    'storefront-chat': async ({ domain, storefront_url: storefrontUrl, body, ...switches }) =>
      remember(domain, await call('PUT', storePath(domain, '/storefront-chat'), JSON.stringify(body === undefined ? chatBody(storefrontUrl) : body), switches)),
    'storefront-chat-status': async ({ domain, ...switches }) => remember(domain, await call('GET', storePath(domain, '/storefront-chat'), '', switches)),
    agent: async ({ domain, service_url: serviceUrl, token, refuse, extra, body, ...switches }) => {
      let raw = body === undefined ? null : JSON.stringify(body);
      if (raw === null) {
        const pairing = token === undefined ? await mint(refuse) : { token };
        raw = JSON.stringify(agentBody({ service_url: serviceUrl ?? pairing.service_url, token: pairing.token }, extra));
      }
      return call('PUT', storePath(domain, '/agent'), raw, switches, 15_000);
    },
    'agent-status': ({ domain, ...switches }) => call('GET', storePath(domain, '/agent'), '', switches),
    'agent-disconnect': ({ domain, ...switches }) => call('DELETE', storePath(domain, '/agent'), '', switches),
  };

  // A one-time pairing token for the store, made immediately before the
  // request, as the app makes one with the AI service (docs/app-agent-connection.md §3.1).
  async function mint(refuse = null) {
    if (!agentUrl) throw new Error('the stand-in app has no AI service to take a pairing token from');
    const response = await fetchImpl(`${String(agentUrl).replace(/\/$/, '')}/__e2e/tokens`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refuse }),
      signal: AbortSignal.timeout(10_000),
    });
    if (response.status !== 201) throw new Error(`the stand-in agent answered ${response.status} to a pairing token`);
    return response.json();
  }

  // Keeps the two values of an answer that carries them, as the app does
  // after the `PUT`. The store is the same store whatever the case of its letters.
  function remember(domain, answer) {
    const { website_token: websiteToken, widget_base_url: widgetBaseUrl } = answer.body || {};
    if (answer.status < 300 && websiteToken && widgetBaseUrl) state.chats.set(String(domain).toLowerCase(), { website_token: websiteToken, widget_base_url: widgetBaseUrl });
    return answer;
  }

  function storefront(request, path, response) {
    if (request.method !== 'GET') return send(response, 405, { error: 'method_not_allowed' });
    const domain = decodeURIComponent(path.slice('/storefront/'.length)).toLowerCase();
    if (!/^[a-z0-9][a-z0-9.-]*$/.test(domain)) return send(response, 404, { error: 'not_found' });
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    return response.end(storefrontPage(domain, state.chats.get(domain)));
  }

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
        .then(() => {
          if (path.startsWith('/__e2e/')) return control(request, path, raw, response);
          if (path.startsWith('/storefront/')) return storefront(request, path, response);
          return send(response, 404, { error: 'not_found' });
        })
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
  const agentUrl = process.env.AGENT_URL || 'http://stand-in-agent:8090';
  if (!secret) console.log('stand-in app: no INCLAMO_APP_PROVISIONING_SECRET, every call will answer 503');
  createStandInApp({ helpdeskUrl, secret, agentUrl }).server.listen(port, () => console.log(`stand-in app: listening on ${port} for ${helpdeskUrl}`));
}
