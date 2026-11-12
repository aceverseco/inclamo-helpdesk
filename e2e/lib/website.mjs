// The website widget's side of the end-to-end tests: a website inbox of the
// test account, its published widget settings, and a visitor on a store page
// that installs the widget with the usual snippet. The store page is served by
// the browser itself (a route on the helpdesk's own address), so the widget's
// requests go to the helpdesk under test and nowhere else.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const helpdeskUrl = () => process.env.HELPDESK_URL || 'http://localhost:3000';

// The store page is made up by the browser, so Chromium counts it as a public
// site loading the widget from a private address (the test network) and
// blocks that. A merchant's site and the helpdesk are both public in real use.
export const storeBrowser = {
  launchOptions: {
    args: ['--disable-features=LocalNetworkAccessChecks,BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessSendPreflights,PrivateNetworkAccessRespectPreflightResults'],
  },
};
export const pngBytes = name => readFileSync(join(here, '..', 'fixtures', 'photos', `${name}.png`));
export const asUpload = bytes => ({ data: Buffer.from(bytes).toString('base64') });

// A website inbox of the account, made once and found by name afterwards.
export async function websiteInbox(api, name, channel = {}) {
  const existing = ((await api.get('/inboxes')).body.payload || []).find(inbox => inbox.name === name);
  if (existing) return existing;
  const created = await api.post('/inboxes', {
    name,
    channel: { type: 'web_widget', website_url: 'https://shop.example.test', widget_color: '#1f93ff', welcome_title: 'Hi there', ...channel },
  });
  if (created.status !== 200) throw new Error(`could not create the website inbox ${name}: ${created.status} ${JSON.stringify(created.body)}`);
  return created.body;
}

export const widgetPath = inboxId => `/inclamo/website_widgets/${inboxId}`;
export const widgetConfig = async (api, inboxId) => {
  const answer = await api.get(widgetPath(inboxId));
  if (answer.status !== 200) throw new Error(`could not read the widget settings: ${answer.status}`);
  return answer.body;
};

// Publishes what `edit` makes of the saved settings, as the editor does.
// `extra` carries images and removals; the answer is returned as it came.
export async function publish(api, inboxId, edit = () => {}, extra = {}) {
  const saved = await widgetConfig(api, inboxId);
  const value = { settings: structuredClone(saved.settings), native: structuredClone(saved.native) };
  await edit(value);
  return api.patch(widgetPath(inboxId), { configuration: { revision: saved.revision, ...value, ...extra } });
}

// Publishes and fails the test when the helpdesk refuses.
export async function published(api, inboxId, edit, extra) {
  const answer = await publish(api, inboxId, edit, extra);
  if (answer.status !== 200) throw new Error(`the widget settings were refused: ${answer.status} ${JSON.stringify(answer.body)}`);
  return answer.body;
}

// The settings every test of a file starts from: the native defaults of the
// extension, the given starters and links, and nothing else.
export const baseline = (overrides = {}) => value => {
  Object.assign(value.settings, {
    position: 'right', type: 'standard', launcher_title: '', icon: 'chat', offset_x: 20, offset_y: 20,
    theme: 'light', language_mode: 'fixed', locale: 'en', visibility: { mode: 'all', rules: [] },
    starters: [], links: [], ...overrides,
  });
};

export const starter = (id, label, message, enabled = true) => ({ id, label, message, enabled });

// How many conversations the inbox has, and contacts the account has.
export async function counts(api, inboxId) {
  const conversations = await api.get(`/conversations?inbox_id=${inboxId}&status=all&assignee_type=all`);
  const contacts = await api.get('/contacts');
  return { conversations: conversations.body?.data?.meta?.all_count ?? null, contacts: contacts.body?.meta?.count ?? null };
}

export const messagesOf = async (api, conversationId) => (await api.get(`/conversations/${conversationId}/messages`)).body.payload || [];

const storePage = (token, explicit) => `<!doctype html>
<html lang="en">
  <head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Example store</title></head>
  <body style="font:16px system-ui;margin:32px">
    <h1>Example store</h1>
    <p>A page of the merchant's site with the widget installed.</p>
    <button id="e2e-open" onclick="window.$chatwoot.toggle('open')">Contact support</button>
    <script>window.chatwootSettings = ${JSON.stringify(explicit)};</script>
    <script src="${helpdeskUrl()}/packs/js/sdk.js"></script>
    <script>chatwootSDK.run({ baseUrl: ${JSON.stringify(helpdeskUrl())}, websiteToken: ${JSON.stringify(token)} });</script>
  </body>
</html>`;

// A visitor on the store's site, in a browser context of their own.
// `explicit` is what the site writes into window.chatwootSettings.
export async function visitor(browser, inbox, { explicit = {}, path = '/e2e-store', beforeLoad, ...options } = {}) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, ...options });
  const page = await context.newPage();
  await page.route(`${helpdeskUrl()}/e2e-store**`, route =>
    route.fulfill({ contentType: 'text/html', body: storePage(inbox.website_token, explicit) })
  );
  if (beforeLoad) await beforeLoad(page);
  await page.goto(helpdeskUrl() + path);
  await waitForWidget(page);
  return {
    context,
    page,
    widget: page.frameLocator('#chatwoot_live_chat_widget'),
    launcher: page.locator('#cw-bubble-holder .woot-widget-bubble:not(.woot--close)'),
    holder: page.locator('#cw-widget-holder'),
    open: () => page.locator('#e2e-open').click(),
    reload: async () => {
      await page.reload();
      await waitForWidget(page);
    },
    close: () => context.close(),
  };
}

export const waitForWidget = page => page.waitForFunction(() => window.$chatwoot?.hasLoaded === true, null, { timeout: 45_000 });

// Which screen the open widget settles on: its messages (with the input, or a
// resolved conversation's "Start a new conversation") or its home screen. A
// visitor with a conversation may come back to its messages first.
async function settledScreen(shopper) {
  const messages = shopper.widget.locator('#chat-input').or(shopper.widget.getByRole('button', { name: 'Start a new conversation', exact: true }));
  const home = shopper.widget.getByRole('button', { name: /^(Start Conversation|Continue conversation)/i });
  let last = null;
  let since = Date.now();
  const deadline = Date.now() + 30_000;
  for (;;) {
    const now = (await messages.first().isVisible()) ? 'messages' : (await home.first().isVisible()) ? 'home' : null;
    if (now !== last) {
      last = now;
      since = Date.now();
    } else if (now && Date.now() - since >= 800) {
      return now;
    }
    if (Date.now() > deadline) throw new Error('the widget showed neither its home screen nor a conversation');
    await shopper.page.waitForTimeout(200);
  }
}

export async function toHome(shopper) {
  if ((await settledScreen(shopper)) === 'messages') await shopper.widget.locator('header button').first().click();
  await shopper.widget.getByRole('button', { name: /^(Start Conversation|Continue conversation)/i }).first().waitFor();
}

// The visitor's conversation, from the home screen when it shows first.
export async function toConversation(shopper) {
  if ((await settledScreen(shopper)) === 'home') await shopper.widget.getByRole('button', { name: /^Continue conversation/i }).click();
  await shopper.widget.locator('#chat-input').or(shopper.widget.getByRole('button', { name: 'Start a new conversation', exact: true })).first().waitFor();
}

// A change of the page's address without a reload, as a single-page store makes it.
export const navigateWithin = (page, path) =>
  page.evaluate(target => {
    history.pushState({}, '', target);
    document.body.append(document.createElement('span'));
  }, path);

// The answer of the widget's request that creates a conversation.
export const conversationCreated = page =>
  page.waitForResponse(response => new URL(response.url()).pathname === '/api/v1/widget/conversations' && response.request().method() === 'POST');

// Counts the conversations the visitor's widget asks to create.
export function countCreates(page) {
  const seen = { creates: 0 };
  page.on('request', request => {
    if (new URL(request.url()).pathname === '/api/v1/widget/conversations' && request.method() === 'POST') seen.creates += 1;
  });
  return seen;
}

// The editor of the website widget, open on the given inbox.
export async function openEditor(page, accountId, inboxId) {
  await page.goto(`/app/accounts/${accountId}/settings/website-widget?inbox=${inboxId}`);
  await page.getByRole('tab', { name: 'Appearance', exact: true }).waitFor({ timeout: 45_000 });
  return page.frameLocator('iframe[title="Website widget preview"]');
}

export const saveEditor = async page => {
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await page.getByRole('status').filter({ hasText: 'Changes saved' }).waitFor();
};

// The id of another account of the signed-in user, by its name.
export async function accountNamed(api, name) {
  const profile = (await api.get(`${helpdeskUrl()}/api/v1/profile`)).body;
  return profile.accounts.find(entry => entry.name === name)?.id;
}
