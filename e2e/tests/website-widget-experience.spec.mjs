// What a visitor of the merchant's site gets from the configured website
// widget: launcher, suggested intents, the native conversation rules, help
// links, page visibility, language, small screens and native transport. The
// tests use a website inbox of their own and a Help Center of the test account.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users } from '../lib/helpdesk.mjs';
import {
  websiteInbox, widgetConfig, publish, published, baseline, starter, counts, messagesOf, visitor,
  conversationCreated, countCreates, openEditor, pngBytes, asUpload, helpdeskUrl, storeBrowser, toHome, toConversation, navigateWithin,
} from '../lib/website.mjs';

test.use(storeBrowser);

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let inbox;
let plain;
let portal;
let article;
let draftArticle;

const order = starter('order', 'Where is my order?', 'Please help me track my order.');
const returns = starter('return', 'Start a return', 'I would like help with a return.');
const hidden = starter('hidden', 'Hidden starter', 'This one is switched off.', false);
const back = shopper => shopper.widget.locator('header button').first().click();
const preChat = {
  pre_chat_form_enabled: true,
  pre_chat_form_options: {
    pre_chat_message: 'Tell us how to reach you.',
    pre_chat_fields: [{ name: 'emailAddress', type: 'email', label: 'Email address', placeholder: 'you@example.test', enabled: true, required: true }],
  },
};

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: helpdeskUrl() });
  admin = await apiAs(request, users.admin, account);
  inbox = await websiteInbox(admin, 'E2E Widget Experience');
  plain = await websiteInbox(admin, 'E2E Widget Plain');
  await admin.post('/inbox_members', { inbox_id: inbox.id, user_ids: [admin.userId] });

  // A Help Center with one published and one draft article.
  const slug = 'e2e-widget-help';
  portal = ((await admin.get('/portals')).body.payload || []).find(entry => entry.slug === slug);
  if (!portal) portal = (await admin.post('/portals', { portal: { name: 'E2E Widget Help', slug, config: { allowed_locales: ['en'], default_locale: 'en' } } })).body;
  const articles = (await admin.get(`/portals/${slug}/articles?locale=en`)).body.payload || [];
  const write = async (title, status) =>
    articles.find(entry => entry.title === title) ||
    (await admin.post(`/portals/${slug}/articles`, { article: { title, content: `${title}: you can request a return within 30 days.`, description: title, status, locale: 'en', author_id: admin.userId } })).body.payload;
  article = await write('Returns and exchanges', 'published');
  draftArticle = await write('Unfinished policy', 'draft');
  expect(article.id).toBeTruthy();
});

// Every test starts from the same published settings and native options.
test.beforeEach(async () => {
  await admin.patch(`/inboxes/${inbox.id}`, { allow_messages_after_resolved: true, channel: { pre_chat_form_enabled: false } });
  await admin.post(`/inboxes/${inbox.id}/set_agent_bot`, { agent_bot: null });
  await published(admin, inbox.id, value => {
    baseline({
      starters: [order, returns, hidden],
      links: [
        { id: 'policy', label: 'Returns policy', kind: 'article', article_id: article.id, enabled: true },
        { id: 'site', label: 'Visit our website', kind: 'url', url: 'https://example.test/returns', enabled: true },
      ],
    })(value);
    value.native.portal_id = portal.id;
    value.native.welcome_title = "Let's find your answer";
  }, { remove_icon: true, remove_avatar: true });
});

test('Merchant publishes a custom launcher', async ({ browser }) => {
  const saved = await published(admin, inbox.id, value => { value.settings.icon = 'custom'; }, { icon_image: asUpload(pngBytes('box-front')), avatar_image: asUpload(pngBytes('box-side')) });
  expect(saved.icon_url).toBeTruthy();
  expect(saved.avatar_url).toBeTruthy();

  const shopper = await visitor(browser, inbox);
  const image = shopper.page.locator('.inclamo-launcher-image');
  await expect(image).toHaveJSProperty('complete', true);
  expect(await image.evaluate(node => node.naturalWidth)).toBeGreaterThan(0);
  expect(await image.getAttribute('src')).toContain(saved.icon_url.split('?')[0]);

  // It opens and closes the chat; the header keeps the merchant's own logo.
  await shopper.launcher.click();
  await expect(shopper.holder).toBeVisible();
  const header = shopper.widget.locator('header img').first();
  await expect(header).toHaveJSProperty('complete', true);
  expect(await header.getAttribute('src')).not.toContain(saved.icon_url.split('?')[0]);
  const created = conversationCreated(shopper.page);
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  const conversation = await (await created).json();
  await shopper.page.locator('#cw-bubble-holder .woot--close').click();
  await expect(shopper.holder).not.toBeVisible();
  await expect(image).toBeVisible();
  // The widget counts what arrives after the second the visitor last looked.
  await shopper.page.waitForTimeout(1_500);

  // A reply while it is closed marks the launcher unread, its image staying.
  await admin.post(`/conversations/${conversation.id}/messages`, { content: 'Your parcel is on its way.', message_type: 'outgoing' });
  // The native unread view then shows the reply above the launcher.
  await expect(shopper.launcher).toHaveClass(/unread-notification/);
  await expect(shopper.holder).toHaveClass(/has-unread-view/);
  await expect(shopper.widget.getByText('Your parcel is on its way.', { exact: true })).toBeVisible();
  await expect(image).toHaveCount(1);
  expect(await image.evaluate(node => node.naturalWidth)).toBeGreaterThan(0);
  await shopper.close();
});

test('Launcher image is unavailable', async ({ browser }) => {
  await published(admin, inbox.id, value => { value.settings.icon = 'custom'; }, { icon_image: asUpload(pngBytes('box-front')) });
  const shopper = await visitor(browser, inbox, {
    beforeLoad: page => page.route(/\/(rails\/active_storage|inclamo\/widget-images)\//, route => route.abort()),
  });
  await expect(shopper.page.locator('.inclamo-launcher-image')).toHaveCount(0);
  await expect(shopper.launcher.locator('svg')).toBeVisible();
  await shopper.launcher.click();
  await expect(shopper.holder).toBeVisible();
  await expect(shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true })).toBeVisible();
  await shopper.close();
});

test('Visitor chooses an intent', async ({ browser }) => {
  const shopper = await visitor(browser, inbox);
  const seen = countCreates(shopper.page);
  await shopper.open();
  await expect(shopper.widget.getByRole('button', { name: /Hidden starter/ })).toHaveCount(0);
  const buttons = await shopper.widget.locator('.inclamo-home-actions button').allInnerTexts();
  expect(buttons.slice(0, 2).map(text => text.trim())).toEqual(['Where is my order?', 'Start a return']);

  // A quick double click is one request.
  const created = conversationCreated(shopper.page);
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).evaluate(button => {
    button.click();
    button.click();
  });
  const conversation = await (await created).json();
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();
  expect(seen.creates).toBe(1);

  // The operator gets it as the visitor's message, once.
  const received = (await messagesOf(admin, conversation.id)).filter(message => message.content === 'Please help me track my order.');
  expect(received).toHaveLength(1);
  expect(received[0].message_type).toBe(0);
  await shopper.close();
});

test('No intents are configured', async ({ browser }) => {
  await published(admin, plain.id, baseline());
  const shopper = await visitor(browser, plain);
  await shopper.open();
  await expect(shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true })).toBeVisible();
  await expect(shopper.widget.locator('.inclamo-home-actions')).toHaveCount(0);
  await shopper.close();
});

test('Pre-chat form is required', async ({ browser }) => {
  await admin.patch(`/inboxes/${inbox.id}`, { channel: preChat });
  const shopper = await visitor(browser, inbox);
  const seen = countCreates(shopper.page);
  await shopper.open();
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  const message = shopper.widget.locator('textarea');
  await expect(message).toHaveValue('Please help me track my order.');

  // Nothing is sent before the form is valid.
  await shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true }).click();
  await expect(shopper.widget.getByText(/required/i).first()).toBeVisible();
  expect(seen.creates).toBe(0);

  await shopper.widget.getByLabel('Email address', { exact: false }).fill(`prechat-${Date.now()}@example.test`);
  await message.fill('Where is order 1001, please?');
  const created = conversationCreated(shopper.page);
  await shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true }).click();
  const conversation = await (await created).json();
  await expect(shopper.widget.getByText('Where is order 1001, please?', { exact: true })).toBeVisible();
  expect(seen.creates).toBe(1);
  const incoming = (await messagesOf(admin, conversation.id)).filter(entry => entry.message_type === 0);
  expect(incoming.map(entry => entry.content)).toEqual(['Where is order 1001, please?']);
  await shopper.close();
});

test('Visitor cancels the form', async ({ browser }) => {
  await admin.patch(`/inboxes/${inbox.id}`, { channel: preChat });
  const before = await counts(admin, inbox.id);
  const shopper = await visitor(browser, inbox);
  const seen = countCreates(shopper.page);
  await shopper.open();
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  await expect(shopper.widget.locator('textarea')).toHaveValue('Please help me track my order.');
  await back(shopper);

  // Back on the home screen nothing was sent, and the starter is gone.
  await expect(shopper.widget.getByRole('button', { name: /Where is my order\?/ })).toBeVisible();
  expect(seen.creates).toBe(0);
  await shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true }).click();
  await expect(shopper.widget.locator('textarea')).toHaveValue('');
  expect(seen.creates).toBe(0);
  expect((await counts(admin, inbox.id)).conversations).toBe(before.conversations);
  await shopper.close();
});

test('Existing conversation or bot is present', async ({ browser }) => {
  // An existing conversation continues; it is not a second one.
  const shopper = await visitor(browser, inbox);
  const seen = countCreates(shopper.page);
  await shopper.open();
  const created = conversationCreated(shopper.page);
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  const conversation = await (await created).json();
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();
  await shopper.reload();
  await shopper.open();
  await toHome(shopper);
  await shopper.widget.getByRole('button', { name: /Start a return/ }).click();
  await expect(shopper.widget.getByText('I would like help with a return.', { exact: true })).toBeVisible();
  expect(seen.creates).toBe(1);
  expect((await messagesOf(admin, conversation.id)).map(message => message.content)).toEqual(expect.arrayContaining(['Please help me track my order.', 'I would like help with a return.']));

  // A resolved conversation that takes no more messages offers a new one instead.
  await admin.patch(`/inboxes/${inbox.id}`, { allow_messages_after_resolved: false });
  await admin.post(`/conversations/${conversation.id}/toggle_status`, { status: 'resolved' });
  await shopper.reload();
  await shopper.open();
  await toHome(shopper);
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  await expect(shopper.widget.getByRole('button', { name: 'Start a new conversation', exact: true })).toBeVisible();
  expect(seen.creates).toBe(1);
  await shopper.close();

  // With a bot on the inbox, a starter goes to the bot, which hands over to the team.
  let bot = ((await admin.get('/agent_bots')).body || []).find(entry => entry.name === 'E2E Widget bot');
  if (!bot) bot = (await admin.post('/agent_bots', { name: 'E2E Widget bot', outgoing_url: '' })).body;
  const details = (await admin.get(`/agent_bots/${bot.id}`)).body;
  const token = typeof details.access_token === 'string' ? details.access_token : details.access_token?.token;
  expect(token).toBeTruthy();
  try {
    await admin.post(`/inboxes/${inbox.id}/set_agent_bot`, { agent_bot: bot.id });
    const other = await visitor(browser, inbox);
    await other.open();
    const botCreated = conversationCreated(other.page);
    await other.widget.getByRole('button', { name: /Where is my order\?/ }).click();
    const routed = await (await botCreated).json();
    expect(routed.status).toBe('pending');
    const asBot = (path, data) => fetch(`${helpdeskUrl()}/api/v1/accounts/${account}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', api_access_token: token }, body: JSON.stringify(data) });
    expect((await asBot(`/conversations/${routed.id}/messages`, { content: 'The assistant will connect you to our team.', message_type: 'outgoing' })).ok).toBe(true);
    await expect(other.widget.getByText('The assistant will connect you to our team.', { exact: true })).toBeVisible();
    expect((await asBot(`/conversations/${routed.id}/toggle_status`, { status: 'open' })).ok).toBe(true);
    await admin.post(`/conversations/${routed.id}/messages`, { content: 'An operator is here to help.', message_type: 'outgoing' });
    await expect(other.widget.getByText('An operator is here to help.', { exact: true })).toBeVisible();
    expect((await admin.get(`/conversations/${routed.id}`)).body.status).toBe('open');
    await other.close();
  } finally {
    await admin.post(`/inboxes/${inbox.id}/set_agent_bot`, { agent_bot: null });
  }
});

test('Visitor reads a help article', async ({ browser }) => {
  const before = await counts(admin, inbox.id);
  const shopper = await visitor(browser, inbox);
  await shopper.open();
  await shopper.widget.getByRole('button', { name: /Returns policy/ }).click();
  await expect(shopper.widget.frameLocator('iframe').getByText(/request a return within 30 days/).first()).toBeVisible();
  await back(shopper);
  await expect(shopper.widget.getByRole('button', { name: /Where is my order\?/ })).toBeVisible();
  expect((await counts(admin, inbox.id)).conversations).toBe(before.conversations);
  await shopper.close();
});

test('Invalid link is configured', async ({ page }) => {
  const before = await widgetConfig(admin, inbox.id);
  await signIn(page, users.admin);
  await openEditor(page, account, inbox.id);
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  const alert = page.locator('p[role="alert"].widget-error');
  for (const [label, address] of [['Script link', 'javascript:alert(1)'], ['Plain web link', 'http://example.test/returns']]) {
    await page.getByRole('button', { name: 'Add link', exact: true }).click();
    await page.getByLabel('Link label', { exact: true }).last().fill(label);
    await page.getByLabel('HTTPS address', { exact: true }).last().fill(address);
    await page.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(alert).toContainText('HTTPS');
    // The input stays for correction; nothing was published.
    await expect(page.getByLabel('HTTPS address', { exact: true }).last()).toHaveValue(address);
    expect((await widgetConfig(admin, inbox.id)).revision).toBe(before.revision);
    page.once('dialog', dialog => dialog.accept());
    await page.getByRole('button', { name: 'Reload saved settings' }).click();
    await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
    await expect(page.getByLabel('Link label', { exact: true })).toHaveCount(2);
  }
  // An article that is not published in the connected Help Center is refused too.
  const answer = await publish(admin, inbox.id, value => {
    value.settings.links.push({ id: 'draft', label: 'Unfinished policy', kind: 'article', article_id: draftArticle.id, enabled: true });
  });
  expect(answer.status).toBe(422);
  expect(answer.body.error).toMatch(/published article/);
  const after = await widgetConfig(admin, inbox.id);
  expect(after.revision).toBe(before.revision);
  expect(after.settings.links.map(link => link.label)).toEqual(['Returns policy', 'Visit our website']);
});

test('Visitor navigates to an excluded page', async ({ browser }) => {
  await published(admin, inbox.id, value => { value.settings.visibility = { mode: 'exclude', rules: [{ path: '/checkout', match: 'prefix' }] }; });
  const shopper = await visitor(browser, inbox);
  await shopper.open();
  const created = conversationCreated(shopper.page);
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  const conversation = await (await created).json();
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();

  // To the checkout without a reload: the chat closes and the launcher hides.
  await navigateWithin(shopper.page, '/checkout/payment?step=2#card');
  await expect(shopper.holder).not.toBeVisible();
  await expect(shopper.page.locator('#cw-bubble-holder')).toHaveClass(/inclamo-page-hidden/);
  // A reply there does not pop the chat open.
  await admin.post(`/conversations/${conversation.id}/messages`, { content: 'Message while the page is excluded.', message_type: 'outgoing' });
  await expect(shopper.widget.getByText('Message while the page is excluded.', { exact: true })).toHaveCount(1);
  await shopper.page.waitForTimeout(2_000);
  await expect(shopper.holder).not.toBeVisible();
  await expect(shopper.page.locator('#cw-bubble-holder')).toHaveClass(/inclamo-page-hidden/);

  // Back on an included page the history is all there.
  await navigateWithin(shopper.page, '/e2e-store?from=checkout');
  await expect(shopper.page.locator('#cw-bubble-holder')).not.toHaveClass(/inclamo-page-hidden/);
  await shopper.launcher.click();
  await expect(shopper.holder).toBeVisible();
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();
  await expect(shopper.widget.getByText('Message while the page is excluded.', { exact: true })).toBeVisible();
  await shopper.close();
});

test('Browser language is unsupported', async ({ browser }) => {
  const merchant = starter('order', 'Wo ist meine Bestellung?', 'Bitte helfen Sie mir, meine Bestellung zu verfolgen.');
  await published(admin, inbox.id, value => { value.settings.language_mode = 'browser'; value.settings.starters = [merchant]; });
  const shopper = await visitor(browser, inbox, { locale: 'zz-ZZ' });
  expect(await shopper.page.evaluate(() => window.$chatwoot.locale)).toBe('en');
  await shopper.open();
  // Native text in the account's language, the merchant's words as written.
  await expect(shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true })).toBeVisible();
  await expect(shopper.widget.getByRole('button', { name: /Wo ist meine Bestellung\?/ })).toBeVisible();
  await shopper.widget.getByRole('button', { name: /Wo ist meine Bestellung\?/ }).click();
  await expect(shopper.widget.getByText('Bitte helfen Sie mir, meine Bestellung zu verfolgen.', { exact: true })).toBeVisible();
  await shopper.close();
});

test('Mobile viewport with large offsets', async ({ browser }) => {
  await published(admin, inbox.id, value => {
    Object.assign(value.settings, { offset_x: 160, offset_y: 160, position: 'left', type: 'expanded_bubble', launcher_title: 'A very long launcher label for a narrow screen', locale: 'ar' });
  });
  const shopper = await visitor(browser, inbox, { viewport: { width: 320, height: 640 } });
  const noSideways = async () => {
    expect(await shopper.page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  };
  await expect(shopper.launcher).toBeInViewport();
  await noSideways();
  await shopper.launcher.click();
  await expect(shopper.holder).toBeVisible();
  await expect(shopper.widget.locator('html')).toHaveAttribute('dir', 'rtl');
  expect(await shopper.widget.locator('html').evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);

  // Read, send and close.
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();
  await shopper.widget.locator('#chat-input').fill('Written on a 320 px screen');
  await shopper.widget.locator('#chat-input').press('Enter');
  await expect(shopper.widget.getByText('Written on a 320 px screen', { exact: true })).toBeVisible();
  expect(await shopper.widget.locator('html').evaluate(node => node.scrollWidth <= node.clientWidth)).toBe(true);
  const close = shopper.widget.locator('.close-button');
  await expect(close).toHaveAttribute('aria-label', /.+/);
  await expect(close).toBeInViewport();
  await close.click();
  await expect(shopper.holder).not.toBeVisible();
  await expect(shopper.launcher).toBeInViewport();
  await noSideways();
  await shopper.close();
});

// The requests and connections of an idle widget, after its UI rerendered.
async function idleTraffic(browser, target) {
  const sockets = [];
  const requests = [];
  const shopper = await visitor(browser, target, {
    beforeLoad: page => {
      page.on('websocket', socket => sockets.push(new URL(socket.url()).pathname));
      page.on('request', request => requests.push({ at: Date.now(), path: new URL(request.url()).pathname }));
    },
  });
  await shopper.open();
  await expect(shopper.holder).toBeVisible();
  await shopper.page.waitForTimeout(2_000);
  const idleSince = Date.now();
  // Rerender: close, resize, open again, then stay idle.
  await shopper.page.evaluate(() => window.$chatwoot.toggle('close'));
  await expect(shopper.holder).not.toBeVisible();
  await shopper.page.setViewportSize({ width: 900, height: 700 });
  await shopper.open();
  await expect(shopper.holder).toBeVisible();
  await shopper.page.waitForTimeout(12_000);
  const idle = requests.filter(request => request.at >= idleSince).map(request => request.path);
  await shopper.close();
  return { sockets, idle };
}

test('Customized widget is idle', async ({ browser }) => {
  await published(admin, plain.id, baseline());
  await published(admin, inbox.id, value => { value.settings.icon = 'custom'; value.settings.theme = 'dark'; }, { icon_image: asUpload(pngBytes('box-front')) });
  const native = await idleTraffic(browser, plain);
  const customized = await idleTraffic(browser, inbox);
  // One messaging connection, and no configuration asked for again while idle.
  expect(customized.sockets.filter(path => path === '/cable')).toHaveLength(1);
  expect(customized.sockets.length).toBe(native.sockets.length);
  const configuration = path => /\/widget$|\/website_widgets|\/widget\/config|\/inbox_settings/.test(path);
  expect(customized.idle.filter(configuration)).toEqual([]);
  expect(customized.idle.filter(path => path.startsWith('/api/')).sort()).toEqual(native.idle.filter(path => path.startsWith('/api/')).sort());
});

test('Visitor returns to the site', async ({ browser }) => {
  // An anonymous visitor finds the conversation again after a reload.
  const shopper = await visitor(browser, inbox);
  const seen = countCreates(shopper.page);
  await shopper.open();
  const created = conversationCreated(shopper.page);
  await shopper.widget.getByRole('button', { name: /Where is my order\?/ }).click();
  const conversation = await (await created).json();
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();
  await shopper.reload();
  await shopper.open();
  await toHome(shopper);
  await expect(shopper.widget.getByRole('button', { name: /Start a return/ })).toBeVisible();
  await expect(shopper.widget.getByText("Let's find your answer", { exact: true })).toBeVisible();
  await toConversation(shopper);
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();

  // Identified by the site, the visitor keeps the same conversation after a reload.
  const identifier = `e2e-visitor-${Date.now()}`;
  const email = `${identifier}@example.test`;
  await shopper.page.evaluate(([id, address]) => window.$chatwoot.setUser(id, { email: address, name: 'Returning Visitor' }), [identifier, email]);
  await expect.poll(async () => ((await admin.get(`/contacts/search?q=${encodeURIComponent(email)}`)).body.payload || [])[0]?.identifier).toBe(identifier);
  const contact = ((await admin.get(`/contacts/search?q=${encodeURIComponent(email)}`)).body.payload || [])[0];
  expect((await admin.get(`/conversations/${conversation.id}`)).body.meta.sender.id).toBe(contact.id);
  await shopper.reload();
  await shopper.open();
  await toConversation(shopper);
  await expect(shopper.widget.getByText('Please help me track my order.', { exact: true })).toBeVisible();
  expect(seen.creates).toBe(1);
  await shopper.close();
});
