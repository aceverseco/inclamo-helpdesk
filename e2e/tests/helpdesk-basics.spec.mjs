// Acceptance of inherited CE behavior in the combined image, using a real
// browser widget. This does not establish delivery through external channels.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users, eventually, runTag } from '../lib/helpdesk.mjs';
import { shopperOn, conversationWith, messagesOf, photos } from '../lib/agent.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
let admin;
let agent;
let inbox;
let shopper;
let conversation;
const greeting = `Please help with my order ${runTag('basics')}`;

test.describe.configure({ mode: 'serial' });
test.beforeAll(async ({ playwright, browser }) => {
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  agent = await apiAs(request, users.agent);
  const made = await admin.post('/inboxes', {
    name: `Acceptance ${runTag('basics')}`,
    channel: { type: 'web_widget', website_url: 'https://shop.example.test', widget_color: '#1f93ff' },
  });
  expect(made.status).toBe(200);
  inbox = made.body;
  await admin.post('/inbox_members', { inbox_id: inbox.id, user_ids: [admin.userId, agent.userId] });
  shopper = await shopperOn(browser, inbox);
  await shopper.write(greeting);
  conversation = await conversationWith(admin, greeting);
});

test.afterAll(async () => {
  await shopper?.close();
  if (inbox) await admin.delete(`/inboxes/${inbox.id}`);
});

test('A shopper message and a human reply cross the widget and dashboard', async ({ page }, info) => {
  await signIn(page, users.agent);
  await page.goto(`/app/accounts/${account}/conversations/${conversation.id}`);
  await expect(page.getByText(greeting, { exact: true }).first()).toBeVisible();
  const reply = `I can help you change the delivery address ${runTag('reply')}`;
  await page.locator('.reply-box .ProseMirror').first().fill(reply);
  await page.locator('.reply-box').getByRole('button', { name: /^Send/ }).click();
  await expect(shopper.page.getByText(reply, { exact: true }).first()).toBeVisible();
  await page.screenshot({ path: info.outputPath('agent-conversation.png'), fullPage: true });
  await shopper.page.screenshot({ path: info.outputPath('shopper-conversation.png'), fullPage: true });
});

test('A private staff note notifies the mentioned colleague and is excluded from the shopper conversation', async () => {
  const note = `Internal verification note ${runTag('private')}`;
  const content = `${note} [@E2E Admin](mention://user/${admin.userId}/E2E%20Admin)`;
  const response = await agent.post(`/conversations/${conversation.id}/messages`, { content, private: true });
  expect(response.status).toBe(200);
  expect((await messagesOf(admin, conversation.id)).some(message => message.private && message.content === content)).toBe(true);
  await expect.poll(async () => ((await admin.get('/notifications')).body.data?.payload || [])
    .some(entry => entry.notification_type === 'conversation_mention' && entry.secondary_actor?.id === response.body.id)).toBe(true);
  // The embedding SDK normally restores this token on reload. This test
  // opens the widget directly, so supply the same shopper identity explicitly.
  const token = await shopper.page.evaluate(() => window.authToken);
  await shopper.page.goto(`/widget?website_token=${inbox.website_token}&cw_conversation=${encodeURIComponent(token)}`);
  await expect(shopper.page.locator('#chat-input')).toBeVisible();
  await expect(shopper.page.getByText(greeting, { exact: true }).first()).toBeVisible();
  await expect(shopper.page.getByText(note, { exact: false })).toHaveCount(0);
});

test('Resolving and snoozing a conversation preserve it and a shopper reply reopens it', async () => {
  const state = async () => (await admin.get(`/conversations/${conversation.id}`)).body.status;
  expect((await agent.post(`/conversations/${conversation.id}/toggle_status`, { status: 'resolved' })).status).toBe(200);
  expect(await state()).toBe('resolved');
  await shopper.write(`I still need help ${runTag('reopen')}`);
  await expect.poll(state).toBe('open');
  expect((await agent.post(`/conversations/${conversation.id}/toggle_status`, {
    status: 'snoozed', snoozed_until: new Date(Date.now() + 3_600_000).toISOString(),
  })).status).toBe(200);
  expect(await state()).toBe('snoozed');
  await shopper.write(`Please respond today ${runTag('unsnooze')}`);
  await expect.poll(state).toBe('open');
});

test('Assignment, labels and search retain the conversation', async () => {
  expect((await admin.post(`/conversations/${conversation.id}/assignments`, { assignee_id: agent.userId })).status).toBe(200);
  const label = `acceptance-${runTag('label').toLowerCase()}`;
  const made = await admin.post('/labels', { title: label, description: 'Acceptance test', color: '#1f93ff', show_on_sidebar: true });
  expect(made.status).toBe(200);
  try {
    expect((await agent.post(`/conversations/${conversation.id}/labels`, { labels: [label] })).status).toBe(200);
    expect((await agent.get(`/conversations/${conversation.id}/labels`)).body.payload).toContain(label);
    expect((await admin.get(`/conversations/${conversation.id}`)).body.meta.assignee.id).toBe(agent.userId);
    expect((await conversationWith(agent, greeting)).id).toBe(conversation.id);
  } finally {
    await admin.delete(`/labels/${made.body.id}`);
  }
});

test('A shopper attachment reaches the human agent', async ({ page }, info) => {
  await shopper.send(photos.front);
  const found = await eventually(() => messagesOf(admin, conversation.id), messages => messages.some(message => message.attachments?.length));
  const attachment = found.find(message => message.attachments?.length);
  expect(attachment.message_type).toBe(0);
  await signIn(page, users.agent);
  await page.goto(`/app/accounts/${account}/conversations/${conversation.id}`);
  await expect(page.locator(`#message${attachment.id}`)).toBeVisible();
  await page.screenshot({ path: info.outputPath('agent-attachment.png'), fullPage: true });
});


test('A published help article is readable by a shopper while a draft is private', async ({ browser }, info) => {
  const slug = `acceptance-${runTag('knowledge').toLowerCase()}`;
  const created = await admin.post('/portals', { portal: {
    name: 'Acceptance Help Center', slug, config: { default_locale: 'en', allowed_locales: ['en'] },
  } });
  expect(created.status).toBe(200);
  const context = await browser.newContext({ baseURL: process.env.HELPDESK_URL });
  try {
    const createArticle = (title, status, content) => admin.post(`/portals/${slug}/articles`, {
      article: { title, status, content, author_id: admin.userId, locale: 'en' },
    });
    const published = await createArticle('How to change your delivery address', 'published', 'Contact support before your parcel ships.');
    const draft = await createArticle('Internal unfinished policy', 'draft', 'This draft must stay private.');
    expect(published.status).toBe(200);
    expect(draft.status).toBe(200);
    const page = await context.newPage();
    const visible = await page.goto(`/hc/${slug}/articles/${published.body.payload.slug}`);
    expect(visible.status()).toBe(200);
    await expect(page.getByRole('heading', { name: 'How to change your delivery address', exact: true })).toBeVisible();
    await expect(page.getByText('Contact support before your parcel ships.', { exact: true })).toBeVisible();
    await page.screenshot({ path: info.outputPath('shopper-help-article.png'), fullPage: true });
    const hidden = await page.goto(`/hc/${slug}/articles/${draft.body.payload.slug}`);
    expect(hidden.status()).toBe(404);
    await expect(page.getByText('This draft must stay private.', { exact: true })).toHaveCount(0);
  } finally {
    await context.close();
    expect((await admin.delete(`/portals/${slug}`)).status).toBe(200);
  }
});

test('Conversation reports count the exchange and open in the administrator dashboard', async ({ page }, info) => {
  const until = Math.floor(Date.now() / 1000) + 60;
  const url = new URL(`/api/v2/accounts/${account}/reports/summary?type=account&since=${until - 86400}&until=${until}`, process.env.HELPDESK_URL).href;
  const report = await admin.get(url);
  expect(report.status).toBe(200);
  expect(Number(report.body.conversations_count)).toBeGreaterThan(0);
  expect(Number(report.body.incoming_messages_count)).toBeGreaterThan(0);
  expect(Number(report.body.outgoing_messages_count)).toBeGreaterThan(0);
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/reports/overview`);
  await expect(page.getByRole('heading', { name: /Overview/i }).first()).toBeVisible();
  await page.screenshot({ path: info.outputPath('administrator-reports.png'), fullPage: true });
});
