// Administration of the website widget: the editor, who may use it, shared
// publication, validation, the native inbox settings, the side-effect-free
// preview and existing installations. The tests use website inboxes of their
// own in the test account; no store data is involved.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users } from '../lib/helpdesk.mjs';
import {
  websiteInbox, widgetConfig, widgetPath, publish, published, baseline, starter, counts, messagesOf,
  visitor, conversationCreated, openEditor, saveEditor, accountNamed, pngBytes, asUpload, helpdeskUrl, storeBrowser, toConversation,
} from '../lib/website.mjs';
import { conversationWith } from '../lib/agent.mjs';

test.use(storeBrowser);

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let second;
let agent;
let inbox;

const greeting = 'Welcome to the example store';
const intents = [starter('order', 'Where is my order?', 'Please help me track my order.'), starter('return', 'Start a return', 'I would like help with a return.')];

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: helpdeskUrl() });
  admin = await apiAs(request, users.admin, account);
  second = await apiAs(request, users.secondAdmin, account);
  agent = await apiAs(request, users.agent, account);
  inbox = await websiteInbox(admin, 'E2E Widget Settings');
});

// Every test starts from the same published settings.
test.beforeEach(async () => {
  await admin.patch(`/inboxes/${inbox.id}`, { channel: { pre_chat_form_enabled: false } });
  await published(admin, inbox.id, value => {
    baseline({ starters: intents })(value);
    value.native.welcome_title = greeting;
    value.native.widget_color = '#1f93ff';
  }, { remove_icon: true });
});

// A second browser of another person, signed in as `user`.
async function browserOf(browser, user) {
  const context = await browser.newContext({ baseURL: helpdeskUrl(), viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  await signIn(page, user);
  return { context, page };
}

const heading = page => page.getByLabel('Welcome heading', { exact: true });

test('Administrator opens a configured website', async ({ page }) => {
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/dashboard`);
  await page.getByRole('button', { name: 'Workspace tools', exact: true }).click();
  await page.getByRole('menuitem', { name: 'Website widget', exact: true }).first().click();
  await expect(page).toHaveURL(/\/settings\/website-widget/);
  await page.locator('.widget-toolbar select').selectOption(String(inbox.id));
  await expect(page).toHaveURL(new RegExp(`[?&]inbox=${inbox.id}(&|$)`));

  const preview = page.frameLocator('iframe[title="Website widget preview"]');
  for (const tab of ['Appearance', 'Home screen', 'Behavior', 'Installation']) await expect(page.getByRole('tab', { name: tab, exact: true })).toBeVisible();
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await expect(heading(page)).toHaveValue(greeting);
  await expect(preview.getByText(greeting, { exact: true })).toBeVisible();

  // The address keeps the selection: a reload shows the same website.
  await page.reload();
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await expect(page.locator('.widget-toolbar select')).toHaveValue(String(inbox.id));
  await expect(heading(page)).toHaveValue(greeting);
  await expect(page.frameLocator('iframe[title="Website widget preview"]').getByRole('button', { name: /Where is my order\?/ })).toBeVisible();
});

test('No website inbox exists', async ({ page }) => {
  const empty = await accountNamed(admin, 'E2E Setup');
  expect(empty).toBeTruthy();
  const inboxes = (await admin.get(`${helpdeskUrl()}/api/v1/accounts/${empty}/inboxes`)).body.payload || [];
  expect(inboxes.filter(entry => entry.channel_type === 'Channel::WebWidget')).toEqual([]);

  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${empty}/settings/website-widget`);
  await expect(page.getByRole('heading', { name: 'Connect your first website', exact: true })).toBeVisible();
  // Nothing of the test account's websites shows here.
  await expect(page.getByRole('tab', { name: 'Appearance', exact: true })).toHaveCount(0);
  await expect(page.getByText('E2E Widget Settings')).toHaveCount(0);
  const create = page.getByRole('link', { name: /Add website channel/ });
  await expect(create).toHaveAttribute('href', `/app/accounts/${empty}/settings/inboxes/new/website`);
  await create.click();
  await expect(page).toHaveURL(new RegExp(`/app/accounts/${empty}/settings/inboxes/new/website`));
});

test('Unauthorized configuration request', async ({ page }) => {
  const before = await widgetConfig(admin, inbox.id);

  // An agent of the account may neither read nor change nor preview it.
  expect((await agent.get(widgetPath(inbox.id))).status).toBe(403);
  expect((await agent.get(`${widgetPath(inbox.id)}/preview`)).status).toBe(403);
  const byAgent = await agent.patch(widgetPath(inbox.id), {
    configuration: { revision: before.revision, settings: { ...before.settings, launcher_title: 'Changed by an agent' }, native: before.native, icon_image: asUpload(pngBytes('box-front')) },
  });
  expect(byAgent.status).toBe(403);
  expect(JSON.stringify(byAgent.body ?? '')).not.toContain(greeting);

  // An administrator of another account cannot reach this inbox through it.
  const other = await accountNamed(admin, 'E2E Setup');
  const foreign = `${helpdeskUrl()}/api/v1/accounts/${other}${widgetPath(inbox.id)}`;
  const read = await admin.get(foreign);
  expect(read.status).toBe(404);
  expect(JSON.stringify(read.body ?? '')).not.toContain(greeting);
  expect((await admin.get(`${foreign}/preview`)).status).toBe(404);
  expect((await admin.patch(foreign, { configuration: { revision: before.revision, settings: before.settings, native: { ...before.native, welcome_title: 'Changed from elsewhere' } } })).status).toBe(404);

  // Nothing changed, the launcher image included.
  const after = await widgetConfig(admin, inbox.id);
  expect(after.revision).toBe(before.revision);
  expect(after.icon_url).toBe(before.icon_url);
  expect(after.native.welcome_title).toBe(greeting);

  // The agent does not get the editor in the dashboard either.
  await signIn(page, users.agent);
  await page.goto(`/app/accounts/${account}/settings/website-widget?inbox=${inbox.id}`);
  await expect(page.getByRole('tab', { name: 'Appearance', exact: true })).toHaveCount(0);
  await expect(page.getByLabel('Welcome heading', { exact: true })).toHaveCount(0);
});

test('Public configuration is inspected', async ({ page, browser }) => {
  // An unsaved draft in an open editor never reaches visitors.
  await signIn(page, users.admin);
  await openEditor(page, account, inbox.id);
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await heading(page).fill('Unsaved draft heading');

  const secrets = (await admin.get(`/inboxes/${inbox.id}`)).body;
  const profile = (await admin.get(`${helpdeskUrl()}/api/v1/profile`)).body;
  const shopper = await visitor(browser, inbox);
  const channel = await shopper.widget.locator('body').evaluate(() => JSON.stringify(window.chatwootWebChannel));
  const extension = JSON.parse(channel).inclamoWidget;

  expect(Object.keys(extension).sort()).toEqual(
    ['icon', 'language_mode', 'launcher_title', 'links', 'locale', 'offset_x', 'offset_y', 'position', 'starters', 'theme', 'type', 'visibility'].sort()
  );
  expect(extension.starters.map(entry => entry.label)).toEqual(['Where is my order?', 'Start a return']);
  // No identity-validation secret, staff credentials, draft or administration data.
  expect(secrets.hmac_token).toBeTruthy();
  for (const hidden of [secrets.hmac_token, profile.access_token, users.admin.email, 'Unsaved draft heading', '"revision"', '"native"', '"portals"', '"articles"']) {
    expect(channel).not.toContain(hidden);
  }
  await shopper.close();
});

test('Another administrator sees the saved result', async ({ page, browser }) => {
  await signIn(page, users.admin);
  const preview = await openEditor(page, account, inbox.id);
  await page.getByRole('combobox', { name: /^Position/ }).selectOption('left');
  await page.getByRole('combobox', { name: /^Button style/ }).selectOption('expanded_bubble');
  await page.getByLabel('Button label', { exact: true }).fill('Talk to the shop');
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await heading(page).fill('Shared greeting');
  await expect(preview.getByText('Shared greeting', { exact: true })).toBeVisible();
  await saveEditor(page);

  // The other administrator, in a browser of their own, sees the same.
  const other = await browserOf(browser, users.secondAdmin);
  await openEditor(other.page, account, inbox.id);
  await expect(other.page.getByRole('combobox', { name: /^Position/ })).toHaveValue('left');
  await expect(other.page.getByLabel('Button label', { exact: true })).toHaveValue('Talk to the shop');
  await other.page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await expect(heading(other.page)).toHaveValue('Shared greeting');
  await other.context.close();

  // A page loaded now uses them, with the snippet it already had.
  const shopper = await visitor(browser, inbox);
  expect(await shopper.page.evaluate(() => ({ position: window.$chatwoot.position, type: window.$chatwoot.type, title: window.$chatwoot.launcherTitle }))).toEqual({
    position: 'left', type: 'expanded_bubble', title: 'Talk to the shop',
  });
  await shopper.open();
  await expect(shopper.widget.getByText('Shared greeting', { exact: true })).toBeVisible();
  await shopper.close();
});

test('Draft is abandoned', async ({ page, browser }) => {
  await signIn(page, users.admin);
  const preview = await openEditor(page, account, inbox.id);
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await heading(page).fill('Abandoned draft heading');
  await expect(preview.getByText('Abandoned draft heading', { exact: true })).toBeVisible();
  // Leaving asks first; the administrator leaves without saving.
  page.once('dialog', dialog => dialog.accept());
  await page.goto(`/app/accounts/${account}/dashboard`);

  expect((await widgetConfig(admin, inbox.id)).native.welcome_title).toBe(greeting);
  const other = await browserOf(browser, users.secondAdmin);
  await openEditor(other.page, account, inbox.id);
  await other.page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await expect(heading(other.page)).toHaveValue(greeting);
  await other.context.close();

  const shopper = await visitor(browser, inbox);
  await shopper.open();
  await expect(shopper.widget.getByText(greeting, { exact: true })).toBeVisible();
  await expect(shopper.widget.getByText('Abandoned draft heading', { exact: true })).toHaveCount(0);
  await shopper.close();
});

test('Invalid or active uploaded content', async ({ page, browser }) => {
  // A launcher image is published first.
  await published(admin, inbox.id, value => { value.settings.icon = 'custom'; }, { icon_image: asUpload(pngBytes('box-front')) });
  const before = await widgetConfig(admin, inbox.id);
  expect(before.icon_url).toBeTruthy();

  await signIn(page, users.admin);
  await openEditor(page, account, inbox.id);
  const upload = page.getByLabel('Upload chat icon', { exact: true });
  const alert = page.locator('p[role="alert"].widget-error');
  const svg = body => ({ name: 'icon.svg', mimeType: 'image/svg+xml', buffer: Buffer.from(body) });
  const attempts = [
    { name: 'broken.png', mimeType: 'image/png', buffer: Buffer.from('this is not an image at all') },
    svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><script>alert(1)</script><circle cx="12" cy="12" r="10"/></svg>'),
    svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="url(https://tracker.example.test/x)"/></svg>'),
  ];
  for (const file of attempts) {
    await upload.setInputFiles(file);
    await page.getByRole('button', { name: 'Save changes', exact: true }).click();
    await expect(alert).toBeVisible();
    await expect(alert).not.toHaveText('');
    expect((await widgetConfig(admin, inbox.id)).icon_url).toBe(before.icon_url);
    page.once('dialog', dialog => dialog.accept());
    await page.getByRole('button', { name: 'Reload saved settings' }).click();
    await page.getByRole('tab', { name: 'Appearance', exact: true }).waitFor();
  }

  // Over 1 MB is refused before anything is sent.
  await upload.setInputFiles({ name: 'large.png', mimeType: 'image/png', buffer: Buffer.concat([pngBytes('box-front'), Buffer.alloc(1_100_000)]) });
  await expect(alert).toContainText('1 MB');
  expect((await widgetConfig(admin, inbox.id)).icon_url).toBe(before.icon_url);
  // The same refusals hold for a direct request.
  for (const file of [...attempts, { buffer: Buffer.alloc(1_100_000, 1) }]) {
    const answer = await publish(admin, inbox.id, value => { value.settings.icon = 'custom'; }, { icon_image: asUpload(file.buffer) });
    expect(answer.status).toBe(422);
  }

  // The visitor still gets the previous launcher.
  const shopper = await visitor(browser, inbox);
  const image = shopper.page.locator('.inclamo-launcher-image');
  await expect(image).toHaveJSProperty('complete', true);
  expect(await image.evaluate(node => node.naturalWidth)).toBeGreaterThan(0);
  expect(await image.getAttribute('src')).toContain(before.icon_url.split('?')[0]);
  await shopper.close();
});

test('Conflicting administrator changes', async ({ page, browser }) => {
  await signIn(page, users.admin);
  await openEditor(page, account, inbox.id);
  const other = await browserOf(browser, users.secondAdmin);
  await openEditor(other.page, account, inbox.id);

  await other.page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await heading(other.page).fill('Published by the other administrator');
  await saveEditor(other.page);
  await other.context.close();

  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await heading(page).fill('Stale draft preserved');
  await page.getByRole('button', { name: 'Save changes', exact: true }).click();
  await expect(page.getByRole('alert')).toContainText('Another administrator');
  await expect(heading(page)).toHaveValue('Stale draft preserved');
  expect((await widgetConfig(admin, inbox.id)).native.welcome_title).toBe('Published by the other administrator');
});

test('Native inbox settings are edited', async ({ page }) => {
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/settings/inboxes/${inbox.id}`);
  const field = page.locator('label', { hasText: /^Welcome Heading$/ }).locator('xpath=following-sibling::div[1]//input');
  await field.fill('Changed on the inbox page');
  await page.getByRole('button', { name: 'Update', exact: true }).filter({ visible: true }).first().click();
  await expect.poll(async () => (await admin.get(`/inboxes/${inbox.id}`)).body.welcome_title).toBe('Changed on the inbox page');

  await openEditor(page, account, inbox.id);
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await expect(heading(page)).toHaveValue('Changed on the inbox page');
  // A save of another field keeps the native value instead of an older copy.
  await page.getByRole('tab', { name: 'Appearance', exact: true }).click();
  await page.getByRole('combobox', { name: /^Position/ }).selectOption('left');
  await saveEditor(page);
  expect((await admin.get(`/inboxes/${inbox.id}`)).body.welcome_title).toBe('Changed on the inbox page');
});

test('Administrator tries a starter in preview', async ({ page }) => {
  await signIn(page, users.admin);
  const before = await counts(admin, inbox.id);
  const preview = await openEditor(page, account, inbox.id);
  const traffic = [];
  page.on('request', request => {
    if (request.frame() !== page.mainFrame() && /\/api\/|\/cable|\/widget\?/.test(request.url())) traffic.push(new URL(request.url()).pathname);
  });

  await preview.getByRole('button', { name: /Where is my order\?/ }).click();
  await expect(preview.getByText('Please help me track my order.', { exact: true })).toBeVisible();

  expect(traffic).toEqual([]);
  expect((await page.context().cookies()).some(cookie => cookie.name.startsWith('cw_conversation'))).toBe(false);
  expect(await counts(admin, inbox.id)).toEqual(before);
});

test('Existing snippet supplies a position', async ({ page, browser }) => {
  expect((await widgetConfig(admin, inbox.id)).settings.position).toBe('right');
  const shopper = await visitor(browser, inbox, { explicit: { position: 'left' } });
  expect(await shopper.page.evaluate(() => window.$chatwoot.position)).toBe('left');
  await expect(shopper.launcher).toHaveClass(/woot-elements--left/);
  await shopper.close();

  // The editor says which settings of an installed snippet win, and how to drop them.
  await signIn(page, users.admin);
  await openEditor(page, account, inbox.id);
  await page.getByRole('tab', { name: 'Installation', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Already installed?' })).toBeVisible();
  const guidance = page.locator('p', { has: page.locator('code', { hasText: 'window.chatwootSettings' }) });
  await expect(guidance).toContainText(/priority/i);
  const snippet = await page.locator('pre').first().innerText();
  expect(snippet).toContain(inbox.website_token);
  expect(snippet).not.toContain('position');
});

test('Existing inbox has no extension settings', async ({ browser }) => {
  // An inbox the editor never saved, with the native pre-chat form on.
  const untouched = await websiteInbox(admin, 'E2E Widget Untouched', { widget_color: '#0f766e', welcome_title: 'Native greeting' });
  expect((await widgetConfig(admin, untouched.id)).settings.starters).toEqual([]);
  await admin.patch(`/inboxes/${untouched.id}`, {
    channel: {
      pre_chat_form_enabled: true,
      pre_chat_form_options: { pre_chat_message: 'Tell us how to reach you.', pre_chat_fields: [{ name: 'emailAddress', type: 'email', label: 'Email address', placeholder: 'you@example.test', enabled: true, required: true }] },
    },
  });

  // The site's own SDK options keep working.
  const shopper = await visitor(browser, untouched, { explicit: { type: 'expanded_bubble', launcherTitle: 'Ask the shop' } });
  expect(await shopper.page.evaluate(() => [window.$chatwoot.type, window.$chatwoot.launcherTitle])).toEqual(['expanded_bubble', 'Ask the shop']);
  await expect(shopper.launcher).toHaveCSS('background-color', 'rgb(15, 118, 110)');
  await shopper.open();
  await expect(shopper.widget.getByText('Native greeting', { exact: true })).toBeVisible();
  await expect(shopper.widget.locator('.inclamo-home-actions')).toHaveCount(0);

  // The native pre-chat form, then the native conversation history.
  await shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true }).click();
  await shopper.widget.getByLabel('Email address', { exact: false }).fill(`untouched-${Date.now()}@example.test`);
  await shopper.widget.locator('textarea').fill('A question from an untouched widget');
  const created = conversationCreated(shopper.page);
  await shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true }).click();
  const conversation = await (await created).json();
  await expect(shopper.widget.getByText('A question from an untouched widget', { exact: true })).toBeVisible();
  await shopper.reload();
  await shopper.open();
  await toConversation(shopper);
  await expect(shopper.widget.getByText('A question from an untouched widget', { exact: true })).toBeVisible();
  expect((await messagesOf(admin, conversation.id)).some(message => message.content === 'A question from an untouched widget')).toBe(true);
  await shopper.close();
  await admin.patch(`/inboxes/${untouched.id}`, { channel: { pre_chat_form_enabled: false } });
});

test('Optional presentation configuration is unusable', async ({ browser }) => {
  // The widget page arrives with extension settings it cannot use.
  const unusable = {
    position: 'middle', type: 'giant', theme: 'neon', icon: 'custom', icon_url: '/no/such/launcher.png', launcher_title: 42,
    offset_x: 'far', offset_y: -50, locale: 'zz', language_mode: 'sideways', visibility: { mode: 'sideways', rules: 'broken' },
    starters: 'broken', links: [{ id: 'x', enabled: true }],
  };
  const shopper = await visitor(browser, inbox, {
    beforeLoad: page =>
      page.route(/\/widget\?website_token=/, async route => {
        const response = await route.fetch();
        const body = (await response.text()).replace(/inclamoWidget: .*,\n/, `inclamoWidget: ${JSON.stringify(unusable)},\n`);
        await route.fulfill({ response, body });
      }),
  });
  const channel = await shopper.widget.locator('body').evaluate(() => window.chatwootWebChannel.inclamoWidget);
  expect(channel.position).toBe('middle');

  // The native defaults: a right-hand launcher with its own icon.
  expect(await shopper.page.evaluate(() => [window.$chatwoot.position, window.$chatwoot.type])).toEqual(['right', 'standard']);
  await expect(shopper.launcher).toHaveClass(/woot-elements--right/);
  await expect(shopper.launcher).toBeInViewport();
  await expect(shopper.page.locator('.inclamo-launcher-image')).toHaveCount(0);
  await expect(shopper.launcher.locator('svg')).toBeVisible();

  // The chat itself works: native home screen, a conversation and a message.
  await shopper.launcher.click();
  await expect(shopper.holder).toBeVisible();
  await expect(shopper.widget.locator('.inclamo-home-actions')).toHaveCount(0);
  const text = `The chat works without its extension ${Date.now()}`;
  await shopper.widget.getByRole('button', { name: 'Start Conversation', exact: true }).click();
  await shopper.widget.locator('#chat-input').fill(text);
  await shopper.widget.locator('#chat-input').press('Enter');
  await expect(shopper.widget.getByText(text, { exact: true })).toBeVisible();
  const conversation = await conversationWith(admin, text);
  expect((await messagesOf(admin, conversation.id)).some(message => message.content === text)).toBe(true);
  await shopper.close();
});
