import { test, expect } from '@playwright/test';
import { signIn, openOrders, orderCard, apiAs, users } from '../lib/helpdesk.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const baseline = process.env.THEME_BASELINE === '1';
const accountPath = `/app/accounts/${account}`;
const editor = page => page.locator('.reply-box .ProseMirror').first();
let admin;
let agent;
let inbox;
let conversation;
let second;
const fixture = JSON.parse(process.env.THEME_DATA || '{}');
const resources = new Set();

async function workspace(page) {
  const section = await openOrders(page, account, conversation.id);
  await expect(section).toHaveAttribute('data-state', 'matched');
  await expect(editor(page)).toBeVisible();
  return section;
}

async function appearance(page, mode) {
  await page.evaluate(value => localStorage.setItem('color_scheme', value), mode);
  await page.reload();
  await expect(page.locator('body')).toHaveClass(mode === 'dark' ? /dark/ : /^(?!.*\bdark\b)/);
}

async function capture(page, name, info) {
  await page.evaluate(() => document.fonts.ready);
  await page.mouse.move(1400, 880);
  const screenshot = await page.screenshot({ animations: 'disabled' });
  await info.attach(`${baseline ? 'baseline' : 'theme'}-${name}`, { body: screenshot, contentType: 'image/png' });
  if (!baseline) await expect(page).toHaveScreenshot(`inclamo-${name}.png`, { animations: 'disabled' });
}

async function cancelDialog(page) {
  const card = await orderCard(page.getByTestId('inclamo-orders-section'), '#1001');
  const trigger = card.getByTestId('inclamo-action-cancel');
  await trigger.click();
  await expect(page.getByTestId('inclamo-action-dialog')).toBeVisible();
  return trigger;
}

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin, account);
  agent = await apiAs(request, users.agent, account);
  ({ inbox, conversation, second } = fixture);
});

test.beforeEach(async ({ page }, info) => {
  page.on('request', request => {
    if (['script', 'stylesheet', 'font'].includes(request.resourceType())) resources.add(request.url());
  });
  // Only screenshots need fixed relative timestamps; behavior tests use real time.
  if (/Brand across|Responsive operator|Leave the staff|Build and exercise|Authentication/.test(info.title)) {
    await page.clock.setFixedTime(new Date('2026-11-09T12:00:00Z'));
  }
  await page.addInitScript(() => {
    if (!localStorage.getItem('color_scheme')) localStorage.setItem('color_scheme', 'light');
  });
  await signIn(page, users.admin);
});

test('Build and exercise the product', async ({ page }, info) => {
   await workspace(page);
    for (const mode of ['light', 'dark']) {
      await appearance(page, mode);
      await workspace(page);
      await orderCard(page.getByTestId('inclamo-orders-section'), '#1001');
      if (!baseline) {
        await expect(page.locator('body')).toHaveClass(/inclamo-dashboard-theme/);
        expect(await editor(page).evaluate(node => getComputedStyle(node).fontFamily)).toMatch(/^Inter[, ]/);
        expect(await page.locator('body').evaluate(node => getComputedStyle(node).getPropertyValue('--slate-12').trim())).toBe(mode === 'light' ? '16 27 61' : '237 245 255');
      }
      await capture(page, `workspace-${mode}`, info);
      if (mode === 'light') await info.attach('workspace-resources.json', { body: JSON.stringify([...resources], null, 2), contentType: 'application/json' });
      await cancelDialog(page);
      if (!baseline) await expect(page.locator('dialog[open]')).toHaveCSS('border-radius', '14px');
      await capture(page, `dialog-${mode}`, info);
      await page.keyboard.press('Escape');
      await expect(page.locator('dialog[open]')).toHaveCount(0);
    }

    await expect(page.locator('.inclamo-brand-mark img')).toHaveAttribute('src', '/brand-assets/inclamo-mark.svg');
    expect(await page.locator('.inclamo-brand-mark img').evaluate(node => node.complete && node.naturalWidth > 0)).toBeTruthy();
});

test('Brand across staff screens', async ({ page }, info) => {
   await page.goto(`${accountPath}/settings/order-actions`);
    for (const mode of ['light', 'dark']) {
      await appearance(page, mode);
      for (const [path, testId] of [['order-actions', 'inclamo-roles-page'], ['preset-rules', 'inclamo-presets-page']]) {
        await page.goto(`${accountPath}/settings/${path}`);
        await expect(page.getByTestId(testId)).toBeVisible();
        if (!baseline) await expect(page.locator('body')).toHaveClass(/inclamo-dashboard-theme/);
        await capture(page, `${path}-${mode}`, info);
      }
    }
    await info.attach('settings-resources.json', { body: JSON.stringify([...resources], null, 2), contentType: 'application/json' });
    const amount = page.getByRole('spinbutton').first();
    await amount.fill('-1');
    const row = amount.locator('xpath=ancestor::*[starts-with(@data-testid,"inclamo-preset-")][1]');
    await row.getByRole('checkbox').check();
    await expect(row.getByRole('checkbox')).not.toBeChecked();
    await expect(row.locator('[data-testid$="-error"]')).toBeVisible();
    await page.goto(`${accountPath}/settings/order-actions`);
    await expect(page.getByTestId(`inclamo-role-${admin.userId}`).getByRole('checkbox')).toBeDisabled();

   await page.goto(`${accountPath}/contacts`);
    if (!baseline) await expect(page.locator('body')).toHaveClass(/inclamo-dashboard-theme/);
    await appearance(page, 'light');
    await capture(page, 'contacts', info);
    await page.getByRole('searchbox').fill('Maya');
    await page.getByRole('button', { name: 'View details' }).first().click();
    await expect(page.getByRole('textbox', { name: 'Enter the email address' }).first()).toBeVisible();
    await capture(page, 'contact-details', info);
    await page.goto(`${accountPath}/reports/overview`);
    await expect(page.getByRole('heading', { name: 'Open Conversations' }).first()).toBeVisible();
    await capture(page, 'reports', info);
    await page.goto(`${accountPath}/settings/inboxes`);
    await capture(page, 'inboxes', info);
    await page.getByRole('button', { name: /Add Inbox/i }).click();
    await expect(page.getByText('Website', { exact: true }).first()).toBeVisible();
    await page.goto(`${accountPath}/settings/automation/list`);
    await capture(page, 'automation', info);
    await page.getByRole('button', { name: /Add.*rule|Add.*automation|Create/i }).first().click();
    const automationDialog = page.getByRole('dialog', { name: 'Add Automation Rule' });
    await automationDialog.getByRole('textbox', { name: 'Rule Name', exact: true }).fill('Example automation');
    await expect(automationDialog.getByRole('button', { name: 'Add Condition', exact: true })).toBeVisible();
    await expect(automationDialog.getByRole('button', { name: 'Create', exact: true })).toBeEnabled();

    await capture(page, 'automation-dialog', info);
    await page.keyboard.press('Escape');

    await signIn(page, users.agent);
    await page.goto(`${accountPath}/settings/order-actions`);
    await expect(page.getByTestId('inclamo-roles-page')).not.toBeVisible();
});

test('Responsive operator workflow', async ({ page }, info) => {
   await admin.put(`/contacts/${conversation.contactId}`, { name: 'Maya Example with a deliberately long customer name for a narrow workspace' });
    for (const viewport of [{ width: 1024, height: 768 }, { width: 390, height: 844 }]) {
      await page.setViewportSize(viewport);
      await workspace(page);
      if (viewport.width === 390) {
        await capture(page, 'contact-390', info);
      }
      // Native narrow-screen workflow: close the contact drawer to write a reply.
      await page.getByRole('button', { name: 'Close', exact: true }).click();
      await expect(editor(page)).toBeVisible();
      await editor(page).fill('Long example message '.repeat(25));
      const send = page.locator('.reply-box').getByRole('button', { name: /^Send/ });
      await expect(send).toBeInViewport();
      await send.click({ trial: true });
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBeTruthy();
      await capture(page, `workspace-${viewport.width}`, info);
    }
    await page.setViewportSize({ width: 1024, height: 768 });
    await page.evaluate(() => document.documentElement.dir = 'rtl');
    await expect(editor(page)).toBeVisible();
    await capture(page, 'workspace-rtl', info);
    await admin.put(`/contacts/${conversation.contactId}`, { name: 'Maya Example' });
});

test('Existing appearance and keyboard preferences', async ({ page }, info) => {
   await workspace(page);
    await appearance(page, 'dark');
    await page.goto(`${accountPath}/settings/order-actions`);
    await expect(page.locator('body')).toHaveClass(/dark/);
    await page.reload();
    await expect(page.locator('body')).toHaveClass(/dark/);
    await page.evaluate(() => localStorage.setItem('color_scheme', 'auto'));
    await page.emulateMedia({ colorScheme: 'light' });
    await page.reload();
    await expect(page.locator('body')).not.toHaveClass(/\bdark\b/);
    await page.emulateMedia({ colorScheme: 'dark' });
    await expect(page.locator('body')).toHaveClass(/dark/);
    expect(await page.evaluate(() => localStorage.getItem('color_scheme'))).toBe('auto');
   await workspace(page);
    const pairs = [];
    for (const mode of ['light', 'dark']) {
      await appearance(page, mode);
      await workspace(page);
      await cancelDialog(page);
      const values = await page.evaluate(() => {
        const style = getComputedStyle(document.body);
        return Object.fromEntries(['--slate-10', '--slate-11', '--slate-12', '--solid-1', '--solid-3', '--inclamo-focus', '--inclamo-brand', '--inclamo-brand-text', '--inclamo-control-border', '--inclamo-action-text'].map(name => [name, style.getPropertyValue(name).trim()]));
      });
      if (!baseline) {
        const luminance = value => value.split(/\s+/).map(Number).map(channel => channel / 255).map(channel => channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4).reduce((sum, channel, i) => sum + channel * [0.2126, 0.7152, 0.0722][i], 0);
        const contrast = (first, second) => (Math.max(luminance(first), luminance(second)) + 0.05) / (Math.min(luminance(first), luminance(second)) + 0.05);
        for (const foreground of ['--slate-10', '--slate-11', '--slate-12', '--inclamo-focus', '--inclamo-brand-text']) {
          for (const background of ['--solid-1', '--solid-3']) {
            const ratio = contrast(values[foreground], values[background]);
            pairs.push({ mode, foreground, background, ratio });
            expect(ratio).toBeGreaterThanOrEqual(foreground === '--inclamo-focus' ? 3 : 4.5);
          }
        }
        expect(contrast(values['--inclamo-action-text'], values['--inclamo-brand'])).toBeGreaterThanOrEqual(4.5);
        for (const background of ['--solid-1', '--solid-3']) {
          const ratio = contrast(values['--inclamo-control-border'], values[background]);
          pairs.push({ mode, foreground: '--inclamo-control-border', background, ratio });
          expect(ratio).toBeGreaterThanOrEqual(3);
        }
        const field = page.getByTestId('inclamo-cancel-reason');
        expect(await field.evaluate(node => getComputedStyle(node).getPropertyValue('--border-weak').trim())).toBe(values['--inclamo-control-border']);
        await field.hover();
        expect(await field.evaluate(node => getComputedStyle(node).getPropertyValue('--slate-6').trim())).toBe(values['--inclamo-control-border']);
      }
      await page.keyboard.press('Escape');
    }
    try {
      await page.goto(`${accountPath}/profile/settings`);
      // Native profile initialization also saves UI settings; let that finish first.
      await page.waitForLoadState('networkidle');
      const saved = page.waitForResponse(response => response.url().endsWith('/api/v1/profile') && response.request().method() === 'PUT' && response.request().postDataJSON()?.profile?.ui_settings?.font_size === '20px');
      await page.locator('select[name="fontSize"]').selectOption('20px');
      expect((await saved).ok()).toBeTruthy();
      await expect(page.locator('html')).toHaveCSS('font-size', '20px');
      await page.reload();
      await expect(page.locator('select[name="fontSize"]')).toHaveValue('20px');
      await expect(page.locator('html')).toHaveCSS('font-size', '20px');
      await workspace(page);
      await cancelDialog(page);
      if (!baseline) await expect(page.locator('dialog[open]')).toHaveCSS('border-radius', '17.5px');
      await page.keyboard.press('Escape');
    } finally {
      await page.goto(`${accountPath}/profile/settings`);
      await page.waitForLoadState('networkidle');
      const restored = page.waitForResponse(response => response.url().endsWith('/api/v1/profile') && response.request().method() === 'PUT' && response.request().postDataJSON()?.profile?.ui_settings?.font_size === '16px');
      await page.locator('select[name="fontSize"]').selectOption('16px');
      expect((await restored).ok()).toBeTruthy();
      await expect(page.locator('html')).toHaveCSS('font-size', '16px');
    }
    await info.attach('contrast.json', { body: JSON.stringify(pairs, null, 2), contentType: 'application/json' });
   await workspace(page);
    const trigger = await cancelDialog(page);
    for (let i = 0; i < 12; i += 1) {
      await page.keyboard.press('Tab');
      // Chromium can visit browser chrome at the end of the native modal's tab order.
      // No underlying application control may receive focus.
      expect(await page.evaluate(() => document.activeElement === document.body || !!document.activeElement.closest('dialog[open]'))).toBeTruthy();
    }
    await page.getByTestId('inclamo-cancel-reason').focus();
    await page.keyboard.press('Tab');
    if (!baseline) expect(await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle)).not.toBe('none');
    await page.keyboard.press('Escape');
    await expect(trigger).toBeFocused();
});

test('Work a real conversation', async ({ page }, info) => {
   await workspace(page);
    await page.evaluate(() => localStorage.setItem('color_scheme', 'auto'));
    await page.reload();
    await editor(page).fill('Unsent reply with details to preserve');
    await page.emulateMedia({ colorScheme: 'dark' });
    await expect(page.locator('body')).toHaveClass(/dark/);
    await expect(editor(page)).toHaveText('Unsent reply with details to preserve');
    await page.emulateMedia({ colorScheme: 'light' });
    await expect(page.locator('body')).not.toHaveClass(/\bdark\b/);
    await expect(editor(page)).toHaveText('Unsent reply with details to preserve');
   await workspace(page);
    const card = await orderCard(page.getByTestId('inclamo-orders-section'), '#1001');
    await card.getByTestId('inclamo-order-mark').click();
    await expect(card.getByTestId('inclamo-order-marked')).toBeVisible();
    await editor(page).fill('Your order is ');
    await editor(page).press('End');
    await page.keyboard.type('{{order.number', { delay: 50 });
    await expect(page.getByRole('option')).toHaveCount(1);
    await page.keyboard.press('Enter');
    await expect(editor(page)).toContainText('#1001');
    await editor(page).press('Control+Enter');
    await expect(editor(page)).toHaveText('');
    const messages = await admin.get(`/conversations/${conversation.id}/messages`);
    expect(messages.body.payload.some(message => !message.private && message.content?.includes('Your order is #1001'))).toBeTruthy();
    // Exercise the native attachment input without needing an external file.
    await page.locator('#conversationAttachment').setInputFiles({ name: 'example.txt', mimeType: 'text/plain', buffer: Buffer.from('Synthetic attachment') });
    await expect(page.locator('.reply-box')).toContainText('example.txt');
    await page.locator('.reply-box').getByText('Private Note', { exact: true }).click();
    await editor(page).fill('Internal example note');
    // Switching reply modes intentionally clears attachments in native Chatwoot.
    await page.locator('#conversationAttachment').setInputFiles({ name: 'example.txt', mimeType: 'text/plain', buffer: Buffer.from('Synthetic attachment') });
    await page.locator('.reply-box').getByRole('button', { name: /Add note|Send/i }).first().click();
    await expect(editor(page)).toHaveText('');
    await expect.poll(async () => {
      const afterNote = await admin.get(`/conversations/${conversation.id}/messages`);
      return afterNote.body.payload.some(message => message.private && message.content === 'Internal example note' && message.attachments?.length === 1);
    }).toBeTruthy();
    const resolve = page.getByRole('button', { name: 'Resolve', exact: true }).first();
    await resolve.click();
    await expect.poll(async () => (await admin.get(`/conversations/${conversation.id}`)).body.status).toBe('resolved');
    await admin.post(`/conversations/${conversation.id}/toggle_status`, { status: 'open' });
});

test('Customer and order actions', async ({ page }, info) => {
   await workspace(page);
    const received = [];
    await page.route('**/inclamo/shopify/conversations/*/actions', async route => {
      if (route.request().method() !== 'POST') return route.continue();
      received.push(route.request().postDataJSON());
      await new Promise(resolve => setTimeout(resolve, 350));
      await route.fulfill({ json: { outcome: 'refused', refusal: 'not_allowed' } });
    });
    await cancelDialog(page);
    const confirm = page.locator('dialog[open] button[type="submit"]');
    await confirm.click();
    await expect(confirm).toBeDisabled();
    await expect(page.getByTestId('inclamo-action-message')).toBeVisible();
    await expect(confirm).toBeEnabled();
    await confirm.click();
    await expect(page.getByTestId('inclamo-action-message')).toBeVisible();
    expect(received).toHaveLength(2);
    expect(received[0].action_id).toBeTruthy();
    expect(received[1].action_id).not.toBe(received[0].action_id);
    await page.keyboard.press('Escape');
    await signIn(page, users.agent);
    await workspace(page);
    const card = await orderCard(page.getByTestId('inclamo-orders-section'), '#1001');
    await expect(card.getByTestId('inclamo-action-cancel')).toBeDisabled();
    await expect(card.getByTestId('inclamo-action-cancel')).toHaveAttribute('title', /.+/);
});

test('Authentication and administration', async ({ page }, info) => {
    await page.context().clearCookies();
    await page.goto('/app/login');
    await expect(page.locator('.inclamo-auth-root')).toBeVisible();
    await expect(page.locator('body')).toHaveClass(/inclamo-app-theme/);
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await capture(page, 'login', info);
    await page.getByRole('link', { name: /Forgot/i }).click();
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await capture(page, 'recovery', info);
    await page.goto('/app/login');
    await page.locator('input[type="email"]').fill(users.admin.email);
    await page.locator('input[type="password"]').fill(users.admin.password);
    await page.locator('button[type="submit"]').click();
    await expect(page).toHaveURL(new RegExp(`/app/accounts/${account}`));
    await page.goto('/super_admin/sign_in');
    await expect(page.locator('body')).toHaveClass(/inclamo-administration/);
    await capture(page, 'superadmin-login', info);
    await page.locator('input[type="email"]').fill(users.admin.email);
    await page.locator('input[type="password"]').fill(users.admin.password);
    await page.locator('button[type="submit"]').click();
    await expect(page).toHaveURL(/super_admin(?!\/sign_in)/);
    await capture(page, 'superadmin', info);

});

test('Leave the staff application', async ({ page }, info) => {
    for (const [name, path] of [['help-centre', '/hc/theme-example/en'], ['widget', '/widget?website_token=synthetic-theme-widget'], ['survey', `/survey/responses/${fixture.survey}`]]) {
      await page.goto(path);
      await expect(page.locator('body')).not.toContainText('The page you were looking for doesn');
      if (name === 'help-centre') await expect(page.getByText('Example Help Centre').first()).toBeVisible();
      if (name === 'widget') await expect(page.getByText('Example support').first()).toBeVisible();
      if (name === 'survey') await expect(page.locator('.ratings button')).toHaveCount(5);
      await expect(page.locator('body')).not.toHaveClass(/inclamo-(dashboard|app)-theme/);
      expect(await page.locator('body').evaluate(node => getComputedStyle(node).getPropertyValue('--inclamo-font-family'))).toBe('');
      await capture(page, name, info);
    }
});

test('Performance and isolation', async ({ page }, info) => {
    await workspace(page);
    const timings = { conversation: [], dialog: [] };
    for (let iteration = 0; iteration < 6; iteration += 1) {
      await page.getByText('Alex Example', { exact: true }).first().click();
      await expect(page).toHaveURL(new RegExp(`/conversations/${second.id}$`));
      await expect(editor(page)).toBeVisible();
      const readPanel = page.waitForResponse(response => response.url().includes(`/conversations/${conversation.id}/panel`) && response.status() === 200);
      const start = performance.now();
      await page.getByText('Maya Example', { exact: true }).first().click();
      await expect(page).toHaveURL(new RegExp(`/conversations/${conversation.id}$`));
      await readPanel;
      await expect(page.getByTestId('inclamo-orders-section')).toHaveAttribute('data-state', 'matched');
      const opened = performance.now();
      await cancelDialog(page);
      const dialog = performance.now();
      await page.keyboard.press('Escape');
      if (iteration) {
        timings.conversation.push(opened - start);
        timings.dialog.push(dialog - opened);
      }
    }
    await info.attach('performance.json', { body: JSON.stringify({ timings, resources: [...resources] }, null, 2), contentType: 'application/json' });
   const origin = new URL(process.env.HELPDESK_URL).origin;
    const externalAssets = [];
    await page.route('**/*', route => {
      const request = route.request();
      if (new URL(request.url()).origin === origin) return route.continue();
      if (['stylesheet', 'script', 'font'].includes(request.resourceType())) externalAssets.push(request.url());
      return route.abort();
    });
    await workspace(page);
    await cancelDialog(page);
    await expect(page.getByTestId('inclamo-cancel-reason')).toBeVisible();
    await page.keyboard.press('Escape');
    await page.goto(`${accountPath}/settings/preset-rules`);
    await expect(page.getByTestId('inclamo-presets-page')).toBeVisible();
    expect(externalAssets).toEqual([]);
    const fixtureRequests = await (await fetch('http://shopify-fixture:8080/requests')).json();
    expect(fixtureRequests.length).toBeGreaterThan(0);
    expect(fixtureRequests.every(request => request.supported)).toBeTruthy();
});

