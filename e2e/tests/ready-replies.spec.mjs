// Scenarios of behavior contract `ready-replies`. The scenarios about sending
// a reply on a tied order and about repeated installation are covered by
// backend specs (see scripts/check-e2e-coverage.mjs): the first needs nothing
// the reply-order-variables tests do not already show in a browser, the
// others need the installer to run again.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users } from '../lib/helpdesk.mjs';

const account = process.env.E2E_ACCOUNT_ID || '1';
const SHORT_CODES = ['delivery-status', 'cancel-confirm', 'damage-photos', 'missing-part', 'return-start'];

test.describe('Ready saved replies exist for the support categories', () => {
  test("Ready replies are listed with the store's own", async ({ page, playwright }) => {
    const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
    const admin = await apiAs(request, users.admin);
    const replies = (await admin.get('/canned_responses')).body;

    for (const code of SHORT_CODES) expect(replies.map(reply => reply.short_code)).toContain(code);
    expect(replies.find(reply => reply.short_code === 'delivery-status').content).toContain('{{order.number}}');
    expect(replies.find(reply => reply.short_code === 'delivery-status').content).toContain('{{order.tracking_link}}');

    await signIn(page, users.admin);
    await page.goto(`/app/accounts/${account}/settings/canned-response/list`);
    for (const code of SHORT_CODES) await expect(page.getByText(code, { exact: true }).first()).toBeVisible({ timeout: 60_000 });
  });
});
