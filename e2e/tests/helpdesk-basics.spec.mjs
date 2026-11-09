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

test('A private staff note is excluded from the shopper conversation', async () => {
  const note = `Internal verification note ${runTag('private')}`;
  const response = await agent.post(`/conversations/${conversation.id}/messages`, { content: note, private: true });
  expect(response.status).toBe(200);
  expect((await messagesOf(admin, conversation.id)).some(message => message.private && message.content === note)).toBe(true);
  await shopper.page.reload();
  await expect(shopper.page.locator('#chat-input')).toBeVisible();
  await expect(shopper.page.getByText(greeting, { exact: true }).first()).toBeVisible();
  await expect(shopper.page.getByText(note, { exact: true })).toHaveCount(0);
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
