import { writeFile } from 'node:fs/promises';
import { chromium, expect, base, login, api, staff, visitor, publish, configPath } from './helpers.mjs';
const headers = await login();
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const errors = [];
const result = { base, checks: [], errors };
const original = await api(headers, configPath);
try {
  await publish(headers, value => Object.assign(value.settings, { language_mode: 'browser', locale: 'en' }));
  const legacy = await visitor(browser, { locale: 'fr-FR', explicit: { useBrowserLanguage: false } });
  legacy.page.on('pageerror', error => errors.push(error.message));
  expect(await legacy.page.evaluate(() => window.$chatwoot.locale)).toBe('en');
  await legacy.page.locator('#custom-open').click();
  await expect(legacy.widget.getByRole('button', { name: 'Start Conversation', exact: true })).toBeVisible();
  await legacy.context.close();
  result.checks.push('explicit browser-language opt-out survives saved browser mode in a real installation');
  await publish(headers, value => { value.settings = original.settings; });

  const context = await staff(browser, headers, { viewport: { width: 1600, height: 1200 } });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(base + '/app/accounts/1/settings/website-widget?inbox=2');
  const preview = page.frameLocator('iframe[title="Website widget preview"]');
  await expect(preview.getByText("Let's find your answer", { exact: true })).toBeVisible();
  await page.waitForTimeout(600); // Let native transitions and avatar assets settle for evidence.
  await page.screenshot({ path: 'build/evidence/website-widget/editor-desktop.png' });
  await page.getByRole('button', { name: 'Mobile', exact: true }).click();
  await expect(preview.locator('.preview-app > div')).toHaveClass(/is-mobile/);
  await page.waitForTimeout(600);
  await page.screenshot({ path: 'build/evidence/website-widget/editor-mobile-preview.png' });
  await page.getByRole('tab', { name: 'Home screen', exact: true }).click();
  await expect(page.getByLabel('Welcome heading', { exact: true })).toBeVisible();
  await page.waitForTimeout(600);
  await page.screenshot({ path: 'build/evidence/website-widget/editor-home.png' });
  await context.close();

  const live = await visitor(browser);
  live.page.on('pageerror', error => errors.push(error.message));
  await expect(live.page.locator('.inclamo-launcher-image')).toHaveJSProperty('complete', true);
  await live.page.waitForTimeout(600);
  await live.page.screenshot({ path: 'build/evidence/website-widget/widget-launcher.png' });
  await live.page.locator('#custom-open').click();
  await expect(live.widget.getByRole('button', { name: 'Where is my order?', exact: false })).toBeVisible();
  await live.page.waitForTimeout(600);
  await live.page.screenshot({ path: 'build/evidence/website-widget/widget-desktop.png' });
  await live.page.setViewportSize({ width: 375, height: 812 });
  await live.page.waitForTimeout(600);
  await expect(live.widget.locator('.close-button')).toBeInViewport();
  await live.page.screenshot({ path: 'build/evidence/website-widget/widget-mobile.png' });
  await live.context.close();
  result.checks.push('final editor, native preview and installed desktop/mobile widget load with matching presentation');
  expect(errors).toEqual([]);
  console.log(JSON.stringify(result));
} finally {
  await publish(headers, value => { value.settings = original.settings; });
  await writeFile('build/evidence/website-widget/delivery.json', JSON.stringify(result, null, 2) + '\n');
  await browser.close();
}
