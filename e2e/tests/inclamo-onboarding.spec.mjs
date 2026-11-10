import { test, expect } from '@playwright/test';

// Run only with the disposable stack's onboarding flag, before normal staff checks.
test('Installation onboarding uses the staff identity', async ({ page }, info) => {
  await page.goto('/installation/onboarding');
  await expect(page.getByRole('heading', { name: 'Welcome to Inclamo' })).toBeVisible();
  await expect(page.locator('body')).toHaveClass(/inclamo-administration/);
  for (const name of ['name', 'company', 'email', 'password']) {
    await expect(page.locator(`#user_${name}`)).toBeVisible();
    await expect(page.locator(`#user_${name}`)).toHaveAttribute('required', 'required');
  }
  await expect(page.locator('img:visible')).toHaveAttribute('alt', 'Inclamo');
  await page.locator('button[type="submit"]').click();
  await expect(page).toHaveURL(/installation\/onboarding/);
  expect(await page.locator('#user_name').evaluate(node => node.validity.valueMissing)).toBeTruthy();
  await page.keyboard.press('Escape');
  await page.locator('h1, h2').first().click();
  await page.evaluate(() => document.fonts.ready);
  const screenshot = await page.screenshot({ animations: 'disabled' });
  await info.attach('inclamo-onboarding', { body: screenshot, contentType: 'image/png' });
  await expect(page).toHaveScreenshot('inclamo-onboarding.png');
});
