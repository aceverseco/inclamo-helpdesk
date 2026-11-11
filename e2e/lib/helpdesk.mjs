// Signing in and finding the Orders section, shared by the end-to-end tests.
export const users = {
  admin: { email: process.env.STAND_ADMIN_EMAIL, password: process.env.STAND_ADMIN_PASSWORD },
  agent: { email: process.env.STAND_AGENT_EMAIL, password: process.env.STAND_AGENT_PASSWORD },
};

// One session per user for the whole run, shared by the browser and by API
// calls, and kept in a file so that every test file reuses it: Chatwoot limits
// how many sessions a user may have. The login page itself is not under test.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const baseUrl = () => process.env.HELPDESK_URL || 'http://localhost:3000';
const sessionsFile = () => join(process.env.E2E_OUTPUT || './output', '.sessions.json');
const readSessions = () => (existsSync(sessionsFile()) ? JSON.parse(readFileSync(sessionsFile(), 'utf8')) : {});

async function sessionOf(user) {
  if (!user.email || !user.password) throw new Error('the credentials of the test user are not set');
  const known = readSessions()[user.email];
  if (known) {
    const check = await fetch(`${baseUrl()}/api/v1/profile`, { headers: known.headers });
    if (check.ok) return known;
  }
  const response = await fetch(`${baseUrl()}/auth/sign_in`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: user.email, password: user.password }),
  });
  if (!response.ok) throw new Error(`could not sign in as ${user.email}: HTTP ${response.status}`);
  const headers = Object.fromEntries(['access-token', 'client', 'uid', 'expiry', 'token-type'].map(name => [name, response.headers.get(name)]));
  const session = { headers, userId: (await response.json()).data.id };
  mkdirSync(dirname(sessionsFile()), { recursive: true });
  writeFileSync(sessionsFile(), JSON.stringify({ ...readSessions(), [user.email]: session }));
  return session;
}

// Makes the page's browser context that of the signed-in user.
export async function signIn(page, user) {
  const { headers } = await sessionOf(user);
  await page.context().clearCookies();
  await page.context().addCookies([{ name: 'cw_d_session_info', value: encodeURIComponent(JSON.stringify(headers)), url: baseUrl() }]);
}

// Opens a conversation and returns the Orders section of its sidebar, opening
// the contact sidebar and expanding the section the way a person would.
export async function openOrders(page, accountId, conversationId) {
  await page.goto(`/app/accounts/${accountId}/conversations/${conversationId}`);
  const section = page.getByTestId('inclamo-orders-section');
  const header = page.locator('button.drag-handle', { hasText: 'Orders' });
  const appeared = async (locator, timeout) => locator.first().waitFor({ state: 'attached', timeout }).then(() => true, () => false);

  if (await appeared(section, 5_000)) return section;
  // The contact sidebar may be closed: Chatwoot's round button at the top
  // right of the conversation opens it.
  if (!(await appeared(header, 3_000))) await page.getByTestId('inclamo-toggle-customer').or(page.locator('button[class*="!rounded-full"]')).first().click();
  if (!(await appeared(section, 3_000))) await header.first().click();
  await section.waitFor({ state: 'attached', timeout: 45_000 });
  return section;
}

// The helpdesk's API as one signed-in user, for preparing and checking what
// the interface shows. `request` is Playwright's API context.
const apis = new Map();

export async function apiAs(request, user, accountId = process.env.E2E_ACCOUNT_ID || '1') {
  if (!apis.has(user.email)) apis.set(user.email, await newApi(request, user, accountId));
  return apis.get(user.email);
}

async function newApi(request, user, accountId) {
  const { headers, userId } = await sessionOf(user);
  const base = `/api/v1/accounts/${accountId}`;
  const call = async (method, path, data) => {
    const response = await request[method](path.startsWith('/') ? `${base}${path}` : path, { headers, data, failOnStatusCode: false });
    const text = await response.text();
    let body = null;
    try {
      body = text ? JSON.parse(text) : null;
    } catch (error) {
      body = text;
    }
    return { status: response.status(), body };
  };
  const api = {
    userId,
    accountId,
    get: path => call('get', path),
    post: (path, data) => call('post', path, data),
    put: (path, data) => call('put', path, data),
    patch: (path, data) => call('patch', path, data),
    delete: path => call('delete', path),

    connection: async () => (await api.get('/inclamo/shopify/connection')).body,
    connect: payload => api.post('/inclamo/shopify/connection', payload),
    disconnect: () => api.delete('/inclamo/shopify/connection'),
    recheck: () => api.post('/inclamo/shopify/connection/recheck'),
    giveRole: id => api.post('/inclamo/order_roles', { user_id: id }),
    takeRole: id => api.delete(`/inclamo/order_roles/${id}`),
    panel: async conversationId => (await api.get(`/inclamo/shopify/conversations/${conversationId}/panel`)).body,
    actions: async conversationId => (await api.get(`/inclamo/shopify/conversations/${conversationId}/actions`)).body.actions,
    act: (conversationId, payload) => api.post(`/inclamo/shopify/conversations/${conversationId}/actions`, payload),
    attributes: async conversationId => (await api.get(`/conversations/${conversationId}`)).body.custom_attributes || {},
    notes: async conversationId =>
      ((await api.get(`/conversations/${conversationId}/messages`)).body.payload || []).filter(message => message.private).map(message => message.content),

    // The inbox the tests put their conversations in, with the given users as members.
    async inbox(memberIds = []) {
      const existing = ((await api.get('/inboxes')).body.payload || []).find(inbox => inbox.name === 'E2E');
      const inbox = existing || (await api.post('/inboxes', { name: 'E2E', channel: { type: 'api', webhook_url: '' } })).body;
      if (memberIds.length) await api.post('/inbox_members', { inbox_id: inbox.id, user_ids: memberIds });
      return inbox;
    },

    // A contact with one conversation; `message` becomes the customer's first message.
    // A contact is unique by email and phone, so an existing one is reused.
    // `together` creates the conversation and its first message in one step,
    // the way the website widget and email do.
    async conversation(inbox, { name, email, phone, message, together = false } = {}) {
      const made = (await api.post('/contacts', { inbox_id: inbox.id, name: name || 'E2E Contact', email, phone_number: phone })).body.payload;
      let contactId = made?.contact?.id;
      let sourceId = made?.contact_inbox?.source_id;
      if (!contactId) {
        const wanted = (email || phone || '').toLowerCase();
        const found = ((await api.get(`/contacts/search?q=${encodeURIComponent(wanted)}`)).body.payload || []).find(
          contact => (contact.email || '').toLowerCase() === wanted || contact.phone_number === phone
        );
        if (!found) throw new Error(`could neither create nor find a contact for ${wanted}`);
        contactId = found.id;
        const inboxes = (await api.get(`/contacts/${contactId}`)).body.payload.contact_inboxes || [];
        sourceId = inboxes.find(entry => entry.inbox.id === inbox.id)?.source_id;
        if (!sourceId) sourceId = (await api.post(`/contacts/${contactId}/contact_inboxes`, { inbox_id: inbox.id })).body.source_id;
      }
      const first = message ? { content: message, message_type: 'incoming' } : null;
      const created = (await api.post('/conversations', { source_id: sourceId, inbox_id: inbox.id, contact_id: contactId, ...(first && together ? { message: first } : {}) })).body;
      if (first && !together) await api.post(`/conversations/${created.id}/messages`, first);
      return { id: created.id, contactId };
    },
  };
  return api;
}

// Control of the proxy between the helpdesk and Shopify (e2e/proxy/server.mjs).
const proxyUrl = () => process.env.E2E_PROXY_URL || 'http://shopify-proxy:8080';
export const proxy = {
  rule: async rule => {
    const response = await fetch(`${proxyUrl()}/__e2e/rules`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(rule) });
    if (!response.ok) throw new Error(`the proxy refused a rule: HTTP ${response.status}`);
  },
  reset: async () => {
    await fetch(`${proxyUrl()}/__e2e/rules`, { method: 'DELETE' });
    await fetch(`${proxyUrl()}/__e2e/log`, { method: 'DELETE' });
  },
  log: async () => (await (await fetch(`${proxyUrl()}/__e2e/log`)).json()).log,
};

export const bench = () => ({
  shop_domain: process.env.SHOPIFY_BENCH_DOMAIN,
  client_id: process.env.SHOPIFY_BENCH_CLIENT_ID,
  client_secret: process.env.SHOPIFY_BENCH_CLIENT_SECRET,
});

// The app with no distribution method chosen, to which the store refuses its
// orders and customers. Optional: without it a test makes the proxy refuse.
export const limited = () =>
  process.env.SHOPIFY_LIMITED_CLIENT_ID
    ? { shop_domain: process.env.SHOPIFY_LIMITED_DOMAIN, client_id: process.env.SHOPIFY_LIMITED_CLIENT_ID, client_secret: process.env.SHOPIFY_LIMITED_CLIENT_SECRET }
    : null;

// Waits until `read()` returns something `accept` likes; for things a
// background job does.
export async function eventually(read, accept, { timeout = 30_000, every = 1_000 } = {}) {
  const deadline = Date.now() + timeout;
  for (;;) {
    const value = await read();
    if (accept(value)) return value;
    if (Date.now() > deadline) throw new Error(`still not as expected after ${timeout} ms: ${JSON.stringify(value).slice(0, 300)}`);
    await new Promise(resolve => setTimeout(resolve, every));
  }
}

// The card of one order inside the Orders section, expanded.
export async function orderCard(section, number) {
  const card = section.getByTestId(`inclamo-order-${number}`);
  // The panel shows ten orders at a time, newest first: an older one is further down.
  for (let page = 0; page < 5; page += 1) {
    if (await card.waitFor({ state: 'visible', timeout: 6_000 }).then(() => true, () => false)) break;
    const more = section.getByTestId('inclamo-orders-more');
    if (!(await more.isVisible())) break;
    await more.click();
  }
  await card.waitFor({ state: 'visible', timeout: 30_000 });
  const heading = card.locator('button').first();
  const expanded = await heading.getAttribute('aria-expanded');
  if (expanded === 'false' || (expanded === null && !(await card.getByTestId('inclamo-action-cancel').isVisible()))) await heading.click();
  const actions = card.locator('details.reference-order-actions');
  if (await actions.count() && (await actions.getAttribute('open')) === null) await actions.locator('summary').click();
  await card.getByTestId('inclamo-action-cancel').waitFor({ state: 'visible' });
  return card;
}

// The run tag of this test run: every store record the tests create carries it.
export const runTag = suffix => `${process.env.E2E_RUN || 'local'}${suffix}`;
