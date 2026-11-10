import { test, expect } from '@playwright/test';
import { signIn, apiAs, bench, users } from '../lib/helpdesk.mjs';
let admin, account, path;
const url = route => new URL(route, process.env.HELPDESK_URL).href;
const setup = async () => (await admin.get(url(`${path}/inclamo/setup`))).body;
const review = async step => admin.patch(url(`${path}/inclamo/setup`), { step, digest: (await setup()).review_digests[step] });
test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: process.env.HELPDESK_URL });
  admin = await apiAs(request, users.admin);
  const profile = (await admin.get(url('/api/v1/profile'))).body;
  account = profile.accounts.find(entry => entry.name === 'E2E Setup').id;
  path = `/api/v1/accounts/${account}`;
});
test('Connect before a conversation exists', async ({ page }, info) => {
  expect((await setup()).order_actions).toEqual([]);
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/settings/setup`);
  await page.getByTestId('setup-connect').click();
  await expect(page.getByTestId('inclamo-connect-dialog')).toBeVisible();
  await page.screenshot({ path: info.outputPath('onboarding-connect-empty.png'), fullPage: true });
  expect((await admin.post(url(`${path}/inclamo/shopify/connection`), bench())).status).toBe(201);
  expect((await setup()).checks.store).toBe(true);
});
test('Missing channel prevents completion', async ({ page }, info) => {
  await review('staff'); await review('ai');
  const result = await admin.post(url(`${path}/inclamo/setup/complete`));
  expect(result.status).toBe(409);
  expect(result.body.checks.channels).toBe(false);
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/settings/setup?step=verify`);
  await expect(page.getByTestId('setup-finish')).toBeDisabled();
  await page.screenshot({ path: info.outputPath('onboarding-missing-channel.png'), fullPage: true });
});
test('Resume settings', async ({ page }, info) => {
  await signIn(page, users.admin);
  await page.goto(`/app/accounts/${account}/settings/setup?step=ai`);
  const row = page.getByTestId('inclamo-ai-policy-cancel');
  await row.locator('select').selectOption('forbidden');
  await expect(page.getByTestId('setup-review-ai')).toBeDisabled();
  await row.getByRole('button', { name: 'Save operation' }).click();
  await expect(page.getByTestId('setup-review-ai')).toBeEnabled();
  await page.getByTestId('setup-review-ai').click();
  await page.goto(`/app/accounts/${account}/settings/ai-agent`);
  await expect(page.getByTestId('inclamo-ai-policy-cancel').locator('select')).toHaveValue('forbidden');
  await page.goto(`/app/accounts/${account}/settings/setup?step=ai`);
  await expect(page.getByTestId('inclamo-ai-policy-cancel').locator('select')).toHaveValue('forbidden');
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.screenshot({ path: info.outputPath('onboarding-ai-laptop.png'), fullPage: true });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
test('Human-operated setup', async ({ page }, info) => {
  expect((await admin.post(url(`${path}/inboxes`), { name: 'Setup store chat', channel: { type: 'api', webhook_url: '' } })).status).toBe(200);
  await review('staff'); await review('ai');
  await signIn(page, users.admin); await page.goto(`/app/accounts/${account}/settings/setup?step=verify`);
  await expect(page.getByTestId('setup-verification')).toContainText('AI is not connected');
  await page.getByTestId('setup-finish').click();
  await expect(page.getByTestId('setup-complete')).toBeVisible();
  expect((await setup()).complete).toBe(true);
  await page.screenshot({ path: info.outputPath('onboarding-human-complete.png'), fullPage: true });
});
test('A working connection is not a completed order test', async ({ page }) => {
  await signIn(page, users.admin); await page.goto(`/app/accounts/${account}/settings/setup?step=verify`);
  await expect(page.getByTestId('setup-no-actions')).toContainText('No completed order actions');
  await expect(page.getByTestId('setup-verification')).toContainText('does not verify the customer page, email delivery or real AI behavior');
  await admin.delete(url(`${path}/inclamo/shopify/connection`));
  await page.reload();
  await expect(page.getByTestId('setup-finish')).toBeDisabled();
  await expect(page.getByTestId('setup-complete')).toHaveCount(0);
});
