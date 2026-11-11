import { expect } from '@playwright/test';
import { randomUUID, generateKeyPairSync, createHash, sign } from 'node:crypto';
export { randomUUID };
export const clientURL = process.env.HELPDESK_URL || 'http://client:3000';
export const centralURL = 'http://central:3000';
export const hostedURL = 'http://hosted:3000';
export const password = 'Synthetic-theme-only-123!';
const sessions = new Map();
export async function api(request, email = 'theme-agent@example.test', base = clientURL) {
  const key = `${base}:${email}`;
  if (!sessions.has(key)) {
    const response = await request.post(`${base}/auth/sign_in`, { data: { email, password } });
    expect(response.status()).toBe(200);
    const headers = Object.fromEntries(['access-token', 'client', 'uid', 'expiry', 'token-type'].map(name => [name, response.headers()[name]]));
    sessions.set(key, { headers, user: (await response.json()).data });
  }
  const session = sessions.get(key);
  return {
    ...session, base,
    async call(method, path, data, account = 1) {
      const url = path.startsWith('/api') ? `${base}${path}` : `${base}/api/v1/accounts/${account}${path}`;
      const response = await request[method](url, { headers: session.headers, data });
      const text = await response.text();
      let body; try { body = JSON.parse(text); } catch { body = text; }
      return { status: response.status(), body, response };
    },
  };
}
export async function signIn(page, session) {
  await page.context().addCookies([{ name: 'cw_d_session_info', value: encodeURIComponent(JSON.stringify(session.headers)), url: session.base }]);
}
export const product = () => ({ schema_version: 1, placements: {
  'conversation-sidebar': ['customer-profile', 'purchase-statistics', 'orders'].map(id => ({ id, collapsed: false })),
  'workspace-header': [{ id: 'notifications', collapsed: false }],
} });
export const empty = () => ({ schema_version: 1, placements: { 'conversation-sidebar': [], 'workspace-header': [] } });
export async function resetLayouts(admin) {
  const current = (await admin.call('get', '/inclamo/workspace_layout/administration')).body;
  const result = await admin.call('put', '/inclamo/workspace_layout/administer', { layout: product(), revision: current.revision, target: 'all', confirmed_count: current.members.length });
  expect(result.status).toBe(200);
}
export async function saveLayout(session, layout, account = 1) {
  const current = (await session.call('get', '/inclamo/workspace_layout', undefined, account)).body;
  return session.call('put', '/inclamo/workspace_layout', { revision: current.revision, layout }, account);
}
export async function workspace(page, session, conversation = 1) {
  await signIn(page, session);
  await page.goto(`${session.base}/app/accounts/1/conversations/${conversation}`);
  await expect(page.locator('.reply-box .ProseMirror').first()).toBeVisible();
  if (!(await page.locator('[data-widget-host="conversation-sidebar"]').count())) await page.getByTestId('inclamo-toggle-customer').click();
  await expect(page.locator('[data-widget-host="conversation-sidebar"]')).toBeVisible();
}
export async function openSupport(page) {
  if (page.viewportSize()?.width < 640 && await page.locator('.reference-customer-pane').isVisible()) {
    await page.locator('.customer-tabs-bar').getByRole('button', { name: 'Close', exact: true }).click();
  }
  await page.getByTestId('inclamo-support-open').click();
  await expect(page.getByTestId('inclamo-support')).toBeVisible();
  return page.getByTestId('inclamo-support');
}
export async function createRequest(session, overrides = {}) {
  const payload = { uuid: randomUUID(), category: 'question', body: `Synthetic request ${randomUUID()}`, files: [], context: { browser: 'Synthetic test', location: 'inbox' }, ...overrides };
  const result = await session.call('post', '/inclamo/support/requests', payload);
  expect(result.status).toBe(201);
  return { ...result.body, original: payload };
}
export async function delivered(session, reference) {
  let result;
  await expect.poll(async () => {
    result = await session.call('get', `/inclamo/support/requests/${reference}`);
    return result.body.delivery;
  }, { timeout: 90_000, intervals: [1000, 2000] }).toBe('delivered');
  return result.body;
}
export async function centralConversation(central, text) {
  let found;
  await expect.poll(async () => {
    const result = await central.call('get', '/conversations?status=all');
    for (const conversation of result.body.data.payload) {
      const messages = (await central.call('get', `/conversations/${conversation.id}/messages`)).body.payload;
      if (messages.some(message => message.content?.includes(text))) { found = { ...conversation, messages }; return true; }
    }
    return false;
  }, { timeout: 60_000, intervals: [1000, 2000] }).toBe(true);
  return found;
}
export async function screenshot(page, info, name) {
  await page.evaluate(() => document.fonts.ready);
  await info.attach(name, { body: await page.screenshot({ animations: 'disabled' }), contentType: 'image/png' });
}
export function signedSource() {
  const keys = generateKeyPairSync('ed25519');
  return { public_key: keys.publicKey.export({ type: 'spki', format: 'pem' }), private_key: keys.privateKey };
}
export async function signedCall(request, source, method, path, value) {
  const body = value ? JSON.stringify(value) : '';
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const canonical = [method.toUpperCase(), path, timestamp, createHash('sha256').update(body).digest('hex')].join('\n');
  return request[method](`${centralURL}${path}`, { data: method === 'get' ? undefined : body,
    headers: { 'Content-Type': 'application/json', 'X-Inclamo-Timestamp': timestamp, 'X-Inclamo-Source': source.reference || '',
      'X-Inclamo-Signature': sign(null, Buffer.from(canonical), source.private_key).toString('base64') } });
}
