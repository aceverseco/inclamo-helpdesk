import { test, expect } from '@playwright/test';
import { api, workspace, signIn, openSupport, createRequest, delivered, centralConversation, screenshot, randomUUID, signedSource, signedCall, hostedURL, centralURL } from '../workspace-support/helpers.mjs';
let author, admin, other, central, hosted;
const composer = page => page.locator('.reply-box .ProseMirror').first();
const fault = (request, value) => request.post('http://support-proxy:8081', { data: value });
const clearFault = request => request.delete('http://support-proxy:8081');
async function upload(request, session, name = 'synthetic.txt', buffer = Buffer.from('synthetic attachment'), mimeType = 'text/plain') {
  const response = await request.post(`${session.base}/api/v1/accounts/1/inclamo/support/uploads`, { headers: session.headers, multipart: { file: { name, mimeType, buffer } } });
  expect(response.status()).toBe(201);
  return response.json();
}
async function publicReply(centralSession, conversation, content, privateNote = false) {
  const result = await centralSession.call('post', `/conversations/${conversation.id}/messages`, { content, private: privateNote, message_type: 'outgoing' });
  expect(result.status).toBe(200); return result.body;
}
async function waitReply(session, reference, content) {
  let value;
  await expect.poll(async () => {
    value = (await session.call('get', `/inclamo/support/requests/${reference}`)).body;
    return value.messages?.some(message => message.body?.includes(content));
  }, { timeout: 90_000, intervals: [1000, 2000] }).toBe(true);
  return value;
}
let apiContext;
test.afterAll(async () => apiContext?.dispose());
test.beforeAll(async ({ playwright }) => {
  const request = apiContext = await playwright.request.newContext();
  author = await api(request); admin = await api(request, 'theme-admin@example.test'); other = await api(request, 'support-other@example.test');
  central = await api(request, 'support-admin@example.test', centralURL); hosted = await api(request, 'theme-agent@example.test', hostedURL);
});
test.afterEach(async ({ request }) => clearFault(request));

test('Self-hosted agent requests help', async ({ page }) => {
  await workspace(page, author); const support = await openSupport(page);
  await support.getByTestId('support-description').fill(`Self-hosted report ${randomUUID()}`);
  await support.getByTestId('support-submit').click();
  await expect(support.getByText('Delivered to Inclamo support', { exact: true })).toBeVisible({ timeout: 90_000 });
  expect((await author.call('get', '/inclamo/support/requests')).body.requests.length).toBeGreaterThan(0);
});

test('Support endpoint is unavailable', async ({ page, request }) => {
  await fault(request, { mode: 'unavailable', path: '/', persistent: true });
  await workspace(page, author); const support = await openSupport(page);
  await support.getByTestId('support-description').fill('Saved safely during a synthetic outage');
  await support.getByTestId('support-submit').click();
  await expect(support.getByText('The support service is unavailable.', { exact: false })).toBeVisible({ timeout: 30_000 });
  await expect(support).toContainText('Saved safely during a synthetic outage');
});

test('Submit a question without a screenshot', async () => {
  const request = await createRequest(author, { category: 'question' });
  const result = await delivered(author, request.reference);
  expect(result.author.name).toBe(author.user.name);
  expect(result.category).toBe('question');
  expect(result.submissions[0].files).toEqual([]);
});

test('Invalid description or attachment', async ({ page, request }) => {
  await workspace(page, author); const support = await openSupport(page);
  await expect(support.getByTestId('support-submit')).toBeDisabled();
  await support.getByTestId('support-description').fill('Preserve this valid text');
  await support.locator('input[type=file]').setInputFiles({ name: 'active.svg', mimeType: 'image/svg+xml', buffer: Buffer.from('<svg/>') });
  await expect(support).toContainText('Check the file type and size');
  await expect(support.getByTestId('support-description')).toHaveValue('Preserve this valid text');
  const response = await request.post(`${author.base}/api/v1/accounts/1/inclamo/support/uploads`, { headers: author.headers, multipart: { file: { name: 'safe.png', mimeType: 'image/png', buffer: Buffer.from('<svg><script>bad()</script></svg>') } } });
  expect(response.status()).toBe(422);
});

test('Annotate and redact a capture', async ({ page }, info) => {
  await workspace(page, author); const support = await openSupport(page);
  const uploads = []; page.on('request', request => { if (/\/support\/uploads$/.test(request.url())) uploads.push(request.url()); });
  // A deterministic screenshot fixture lets us inspect the actual flattened
  // pixels; native capture itself is exercised separately by capture-probe.mjs.
  const png = await page.evaluate(() => {
    const canvas = document.createElement('canvas'); canvas.width = 400; canvas.height = 200;
    const context = canvas.getContext('2d'); context.fillStyle = '#fff'; context.fillRect(0, 0, 400, 200);
    context.fillStyle = '#f00'; context.fillRect(40, 40, 100, 60);
    return canvas.toDataURL('image/png').split(',')[1];
  });
  await support.getByTestId('support-description').evaluate((node, png) => {
    const bytes = Uint8Array.from(atob(png), character => character.charCodeAt(0));
    const clipboard = new DataTransfer(); clipboard.items.add(new File([bytes], 'pasted.png', { type: 'image/png' }));
    node.dispatchEvent(new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: clipboard }));
  }, png);
  await expect(support.locator('img')).toBeVisible(); expect(uploads).toEqual([]);
  await support.getByRole('button', { name: 'Remove', exact: true }).click();
  await support.locator('input[type=file]').setInputFiles({ name: 'screenshot.png', mimeType: 'image/png', buffer: Buffer.from(png, 'base64') });
  await support.getByRole('button', { name: 'Edit image', exact: true }).click();
  const editorCanvas = support.locator('canvas'); const initial = await editorCanvas.boundingBox();
  for (const tool of ['Crop', 'Rectangle']) {
    await support.getByRole('button', { name: tool, exact: true }).click();
    await page.mouse.move(initial.x + 2, initial.y + 2); await page.mouse.down();
    await page.mouse.move(initial.x + initial.width * .9, initial.y + initial.height * .9); await page.mouse.up();
    await support.getByRole('button', { name: 'Undo', exact: true }).click();
    expect(await editorCanvas.evaluate(canvas => [canvas.width, canvas.height])).toEqual([400, 200]);
  }
  await support.getByRole('button', { name: 'Cover sensitive area', exact: true }).click();
  const canvas = support.locator('canvas'); const bounds = await canvas.boundingBox();
  await page.mouse.move(bounds.x + bounds.width * .05, bounds.y + bounds.height * .1);
  await page.mouse.down(); await page.mouse.move(bounds.x + bounds.width * .5, bounds.y + bounds.height * .7); await page.mouse.up();
  await support.getByRole('button', { name: 'Arrow', exact: true }).click();
  await page.mouse.move(bounds.x + bounds.width * .65, bounds.y + bounds.height * .8);
  await page.mouse.down(); await page.mouse.move(bounds.x + bounds.width * .8, bounds.y + bounds.height * .4); await page.mouse.up();
  await screenshot(page, info, 'redaction-editor');
  await support.getByRole('button', { name: 'Use this image', exact: true }).click();
  expect(uploads).toEqual([]);
  const pixels = await support.locator('img').evaluate(async image => {
    await image.decode(); const canvas = document.createElement('canvas'); canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
    const context = canvas.getContext('2d'); context.drawImage(image, 0, 0); return [...context.getImageData(80, 60, 1, 1).data];
  });
  expect(pixels).toEqual([0, 0, 0, 255]);
  const body = `Redacted screenshot ${randomUUID()}`;
  await support.getByTestId('support-description').fill(body); await support.getByTestId('support-submit').click();
  await expect(support.getByText('Delivered to Inclamo support', { exact: true })).toBeVisible({ timeout: 90_000 });
  const conversation = await centralConversation(central, body);
  const attachments = conversation.messages.filter(message => message.message_type === 0).flatMap(message => message.attachments || []);
  expect(attachments).toHaveLength(1);
  const report = (await author.call('get', '/inclamo/support/requests')).body.requests.find(item => item.preview === body);
  const download = await author.call('get', `/inclamo/support/requests/${report.reference}/attachments/${attachments[0].id}`);
  expect(download.status).toBe(200);
  const finalPixels = await page.evaluate(async encoded => {
    const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${encoded}`)).blob());
    const canvas = document.createElement('canvas'); canvas.width = bitmap.width; canvas.height = bitmap.height;
    const context = canvas.getContext('2d'); context.drawImage(bitmap, 0, 0); const pixels = [...context.getImageData(80, 60, 1, 1).data]; bitmap.close(); return pixels;
  }, (await download.response.body()).toString('base64'));
  expect(finalPixels).toEqual([0, 0, 0, 255]);
});

test('Capture is denied or unavailable', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getDisplayMedia: () => Promise.reject(new DOMException('Cancelled', 'NotAllowedError')) } });
  });
  await workspace(page, author); const support = await openSupport(page);
  await support.getByTestId('support-description').fill('Text survives cancellation');
  const uploads = []; page.on('request', request => { if (/\/support\/uploads$/.test(request.url())) uploads.push(request.url()); });
  await support.getByRole('button', { name: 'Take screenshot', exact: true }).click();
  await expect(support).toContainText('Capture was cancelled or unavailable');
  await expect(support.getByTestId('support-description')).toHaveValue('Text survives cancellation');
  expect(uploads).toEqual([]);
});

test('Review a report while viewing a customer conversation', async ({ page }) => {
  await workspace(page, author); const support = await openSupport(page);
  await expect(support).toContainText('Information included with this request');
  await expect(support.getByRole('checkbox')).not.toBeChecked();
  await expect(support).toContainText('Customer messages, order details, cookies and credentials are not collected');
  await support.getByTestId('support-description').fill('Only approved context');
  await support.getByRole('checkbox').check();
  const outgoing = page.waitForRequest(request => request.method() === 'POST' && /\/support\/requests$/.test(request.url()));
  await support.getByTestId('support-submit').click(); const value = (await outgoing).postDataJSON();
  expect(value.context.conversation_reference).toBe('1');
  expect(JSON.stringify(value)).not.toContain('shipping_address'); expect(JSON.stringify(value)).not.toContain('transcript');
});

test('Sanitized location', async ({ page }) => {
  await signIn(page, author); await page.goto('/app/accounts/1/conversations/1?secret=do-not-send#private-fragment');
  const support = await openSupport(page); await support.getByTestId('support-description').fill('Safe route context');
  const outgoing = page.waitForRequest(request => request.method() === 'POST' && /\/support\/requests$/.test(request.url()));
  await support.getByTestId('support-submit').click(); const value = (await outgoing).postDataJSON();
  expect(value.context.location).toBe('conversation'); expect(JSON.stringify(value)).not.toMatch(/do-not-send|private-fragment/);
});

test('A request reaches support', async () => {
  const request = await createRequest(author); await delivered(author, request.reference);
  const conversation = await centralConversation(central, request.original.body);
  expect(conversation.custom_attributes).toMatchObject({ inclamo_support_origin: 'self_hosted', inclamo_support_category: 'question' });
  expect(conversation.messages.filter(message => message.message_type === 0)).toHaveLength(1);
  expect(conversation.inbox_id).toBe(1);
});

test('A self-hosted request claims hosted status', async () => {
  const request = await createRequest(author, { hosted: true, account_id: 999, author: { name: 'Forged' } }); await delivered(author, request.reference);
  const conversation = await centralConversation(central, request.original.body);
  expect(conversation.custom_attributes.inclamo_support_origin).toBe('self_hosted');
  expect(conversation.messages.some(message => message.content?.includes('Forged'))).toBe(false);
});

test('Same reporter in two installations', async () => {
  const first = await createRequest(author); const second = await createRequest(hosted);
  await delivered(author, first.reference); await delivered(hosted, second.reference);
  const a = await centralConversation(central, first.original.body); const b = await centralConversation(central, second.original.body);
  expect(author.user.email).toBe(hosted.user.email);
  expect(a.custom_attributes.inclamo_support_source).not.toBe(b.custom_attributes.inclamo_support_source);
  expect(b.custom_attributes.inclamo_support_origin).toBe('hosted');
  expect((await author.call('get', `/inclamo/support/requests/${second.reference}`)).status).toBe(404);
});

test("Administrator helps with an agent's issue", async () => {
  const request = await createRequest(author); await delivered(author, request.reference);
  const result = await admin.call('post', `/inclamo/support/requests/${request.reference}/replies`, { uuid: randomUUID(), body: 'Administrator supplies details', files: [] });
  expect(result.status).toBe(201); await delivered(admin, request.reference);
  const conversation = await centralConversation(central, 'Administrator supplies details');
  const message = conversation.messages.find(message => message.content?.includes('Administrator supplies details'));
  expect(message.content).toContain(admin.user.name); expect(message.content).toContain('(administrator)');
});

test('Another member guesses the reference', async ({ request }) => {
  const file = await upload(request, author); const report = await createRequest(author, { files: [file.reference] });
  await delivered(author, report.reference);
  const conversation = await centralConversation(central, report.original.body);
  const attachment = conversation.messages.flatMap(message => message.attachments || [])[0];
  expect((await author.call('get', `/inclamo/support/requests/${report.reference}/attachments/${attachment.id}`)).status).toBe(200);
  const separate = await createRequest(author); await delivered(author, separate.reference);
  expect((await author.call('get', `/inclamo/support/requests/${separate.reference}/attachments/${attachment.id}`)).status).toBe(404);
  expect((await other.call('get', `/inclamo/support/requests/${report.reference}`)).status).toBe(404);
  expect((await other.call('get', `/inclamo/support/requests/${report.reference}/uploads/${file.reference}`)).status).toBe(404);
  expect((await admin.call('get', `/inclamo/support/requests/${report.reference}`, undefined, 2)).status).toBe(404);
});

test('Membership is revoked', async () => {
  const report = await createRequest(other);
  expect(other.user.accounts.some(account => account.id === 2)).toBe(true);
  expect((await admin.call('delete', `/agents/${other.user.id}`)).status).toBe(200);
  try {
    expect([401, 403, 404]).toContain((await other.call('get', `/inclamo/support/requests/${report.reference}`)).status);
    expect([401, 403, 404]).toContain((await other.call('post', `/inclamo/support/requests/${report.reference}/replies`, { uuid: randomUUID(), body: 'Denied' })).status);
  } finally {
    const restored = await admin.call('post', '/agents', { email: other.user.email, name: other.user.name, role: 'agent' });
    expect([200, 201]).toContain(restored.status);
  }
});

test('Public reply and private note', async ({ request }) => {
  const report = await createRequest(author); await delivered(author, report.reference);
  const conversation = await centralConversation(central, report.original.body);
  const note = await request.post(`${centralURL}/api/v1/accounts/1/conversations/${conversation.id}/messages`, { headers: central.headers,
    multipart: { content: 'Synthetic private note must stay private', private: 'true', message_type: 'outgoing', 'attachments[]': { name: 'private.txt', mimeType: 'text/plain', buffer: Buffer.from('private attachment') } } });
  expect(note.status()).toBe(200); const privateFile = (await note.json()).attachments[0];
  await publicReply(central, conversation, 'Public support reply for privacy check');
  const thread = await waitReply(author, report.reference, 'Public support reply for privacy check');
  expect(JSON.stringify(thread)).not.toContain('Synthetic private note'); expect(JSON.stringify(thread)).not.toContain('private.txt');
  expect(thread.unread).toBe(true);
  expect((await author.call('get', `/inclamo/support/requests/${report.reference}/attachments/${privateFile.id}`)).status).toBe(404);
  expect((await author.call('post', `/inclamo/support/requests/${report.reference}/read`, { cursor: thread.last_reply_id })).status).toBe(204);
});

test('Resolve and follow up', async () => {
  const report = await createRequest(author); await delivered(author, report.reference);
  const conversation = await centralConversation(central, report.original.body);
  expect((await central.call('post', `/conversations/${conversation.id}/toggle_status`, { status: 'resolved' })).status).toBe(200);
  await author.call('post', `/inclamo/support/requests/${report.reference}/replies`, { uuid: randomUUID(), body: 'Follow-up after resolution', files: [] });
  await delivered(author, report.reference);
  const same = await centralConversation(central, 'Follow-up after resolution');
  expect(same.id).toBe(conversation.id); expect(same.status).toBe('open');
});

test('Notify an offline author', async ({ request }) => {
  const report = await createRequest(author); await delivered(author, report.reference);
  const enrollment = await author.call('post', `/inclamo/support/requests/${report.reference}/recipient`, { enabled: true });
  expect(enrollment.status).toBe(200);
  if (!enrollment.body.recipients[0].verified) {
    const mails = await (await request.get('http://mail:8025')).json();
    const code = mails.filter(mail => /verification code is/.test(mail.body)).at(-1).body.match(/\b\d{6}\b/)[0];
    expect((await author.call('post', `/inclamo/support/requests/${report.reference}/recipient/verify`, { code })).status).toBe(200);
  }
  const conversation = await centralConversation(central, report.original.body);
  await publicReply(central, conversation, 'The answer body must not appear in notification email');
  let emails;
  await expect.poll(async () => {
    emails = (await (await request.get('http://mail:8025')).json()).filter(mail => mail.body.includes(report.reference)); return emails.length;
  }, { timeout: 60_000 }).toBe(1);
  expect(emails[0].body).not.toContain('The answer body'); expect(emails[0].body).not.toContain('access-token');
  await waitReply(author, report.reference, 'The answer body');
  expect((await (await request.get('http://mail:8025')).json()).filter(mail => mail.body.includes(report.reference))).toHaveLength(1);
});

test('Email is unavailable', async () => {
  const report = await createRequest(author); await delivered(author, report.reference);
  expect((await author.call('post', `/inclamo/support/requests/${report.reference}/recipient`, { enabled: false })).status).toBe(200);
  const conversation = await centralConversation(central, report.original.body);
  await publicReply(central, conversation, 'Available without email');
  const thread = await waitReply(author, report.reference, 'Available without email');
  expect(thread.unread).toBe(true); expect(thread.notifications_enabled).toBe(false);
});

test('Acknowledgement is lost', async ({ request }) => {
  await fault(request, { mode: 'lost_ack', path: '/submissions' });
  const report = await createRequest(author);
  const conversation = await centralConversation(central, report.original.body);
  await author.call('post', `/inclamo/support/requests/${report.reference}/retry/${report.original.uuid}`);
  await delivered(author, report.reference);
  const after = await centralConversation(central, report.original.body);
  expect(after.id).toBe(conversation.id);
  expect(after.messages.filter(message => message.message_type === 0 && message.content?.includes(report.original.body))).toHaveLength(1);
});

test('Screenshot delivery fails after text delivery', async ({ page, request }) => {
  const report = await createRequest(author); await delivered(author, report.reference);
  const conversation = await centralConversation(central, report.original.body);
  const png = await page.evaluate(() => { const canvas = document.createElement('canvas'); canvas.width = 20; canvas.height = 20; canvas.getContext('2d').fillRect(0, 0, 20, 20); return canvas.toDataURL('image/png').split(',')[1]; });
  const file = await upload(request, author, 'screenshot.png', Buffer.from(png, 'base64'), 'image/png');
  await fault(request, { mode: 'unavailable', path: '/uploads', persistent: true });
  const uuid = randomUUID();
  expect((await author.call('post', `/inclamo/support/requests/${report.reference}/replies`, { uuid, body: 'Approved attachment follows the original text', files: [file.reference] })).status).toBe(201);
  await expect.poll(async () => (await author.call('get', `/inclamo/support/requests/${report.reference}`)).body.delivery).toBe('attachments_pending');
  await clearFault(request);
  await author.call('post', `/inclamo/support/requests/${report.reference}/retry/${uuid}`);
  await delivered(author, report.reference);
  const after = await centralConversation(central, 'Approved attachment follows');
  expect(after.id).toBe(conversation.id);
  expect(after.messages.filter(message => message.content?.includes('Approved attachment follows'))).toHaveLength(1);
});

test('Central support outage during a shift', async ({ page, request }) => {
  await workspace(page, author); await composer(page).fill('Unsent customer reply remains intact');
  await fault(request, { mode: 'unavailable', path: '/', persistent: true });
  const support = await openSupport(page); await support.getByTestId('support-description').fill('Synthetic outage report');
  await page.getByRole('button', { name: 'Close', exact: true }).last().click();
  await expect(composer(page)).toContainText('Unsent customer reply remains intact');
  expect((await author.call('post', '/conversations/1/messages', { content: 'Native customer workflow remains available', private: true, message_type: 'outgoing' })).status).toBe(200);
});

test('An installation credential is reused against another source', async ({ request }) => {
  const first = signedSource(), second = signedSource();
  for (const [index, source] of [first, second].entries()) {
    const response = await signedCall(request, source, 'post', '/inclamo/support/v1/register', { public_key: source.public_key, base_url: `https://synthetic-${index}.example.test` });
    expect(response.status()).toBe(200); source.reference = (await response.json()).source_id;
  }
  const response = await signedCall(request, { ...first, reference: second.reference }, 'get', '/inclamo/support/v1/events?cursor=0');
  expect(response.status()).toBe(401);
});

test('Submit from a narrow screen using keyboard controls', async ({ page }, info) => {
  await page.setViewportSize({ width: 390, height: 844 }); await workspace(page, author);
  const support = await openSupport(page); await support.getByTestId('support-description').fill('Keyboard and mobile submission');
  await support.locator('input[type=file]').setInputFiles({ name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('Synthetic mobile attachment') });
  await support.getByTestId('support-submit').focus();
  await screenshot(page, info, 'support-mobile');
  await page.keyboard.press('Enter');
  await expect(support.getByText('Delivered to Inclamo support', { exact: true })).toBeVisible({ timeout: 90_000 });
});
