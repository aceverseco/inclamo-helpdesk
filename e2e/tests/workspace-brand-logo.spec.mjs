// The supplied combined Inclamo logo in the staff workspace, on the login page
// and in SuperAdmin, and the merchant's own branding of the customer widget.
import { test, expect } from '@playwright/test';
import { signIn, apiAs, users } from '../lib/helpdesk.mjs';
import { websiteInbox, published, baseline, visitor, pngBytes, asUpload, helpdeskUrl, storeBrowser } from '../lib/website.mjs';

test.use(storeBrowser);

const account = process.env.E2E_ACCOUNT_ID || '1';
const combined = '/brand-assets/inclamo-logo-combined.jpg';
const symbol = '/brand-assets/inclamo-mark.svg';
let admin;

test.beforeAll(async ({ playwright }) => {
  const request = await playwright.request.newContext({ baseURL: helpdeskUrl() });
  admin = await apiAs(request, users.admin, account);
});

// The image as shown: loaded, its proportions kept, at the given size.
async function shownWhole(image, size) {
  await expect(image).toBeVisible();
  await expect(image).toHaveJSProperty('complete', true);
  // The sidebar widens with a transition after it is expanded or the window
  // changes: the size is the one the image settles at.
  if (size) {
    await expect
      .poll(() => image.evaluate(node => { const box = node.getBoundingClientRect(); return [Math.round(box.width), Math.round(box.height)]; }))
      .toEqual([size, size]);
  }
  const shape = await image.evaluate(node => {
    const box = node.getBoundingClientRect();
    return { naturalWidth: node.naturalWidth, naturalHeight: node.naturalHeight, width: box.width, height: box.height, fit: getComputedStyle(node).objectFit };
  });
  expect(shape.naturalWidth).toBeGreaterThan(0);
  const src = await image.getAttribute('src');
  if (src.endsWith('.svg')) {
    // A vector image keeps its proportions inside any box unless it says otherwise.
    const svg = await (await image.page().request.get(src)).text();
    expect(svg).not.toMatch(/preserveAspectRatio="none"/);
  } else {
    // Not stretched or cropped: the box has the image's proportions, or the image is fitted inside it.
    const sameShape = Math.abs(shape.width / shape.height - shape.naturalWidth / shape.naturalHeight) < 0.02;
    expect(sameShape || ['contain', 'scale-down'].includes(shape.fit)).toBe(true);
    expect(shape.fit).not.toBe('cover');
  }
}

// The dashboard with the sidebar expanded; a collapsed sidebar is the user's
// saved preference and stays so across visits.
async function dashboard(page) {
  await page.goto(`/app/accounts/${account}/dashboard`);
  const logo = page.locator('.inclamo-brand-mark img').first();
  await logo.waitFor({ timeout: 45_000 });
  if ((await logo.getAttribute('src')) === symbol) {
    await page.locator('.inclamo-sidebar .cursor-col-resize').dblclick();
    await expect(logo).toHaveAttribute('src', combined);
  }
}

test('Administrator opens the workspace', async ({ page }) => {
  await signIn(page, users.admin);
  await dashboard(page);
  const mark = page.locator('.inclamo-brand-mark').first();
  const logo = mark.locator('img');
  await expect(logo).toHaveCount(1);
  await expect(logo).toHaveAttribute('src', combined);
  await expect(logo).toHaveAttribute('alt', 'Inclamo');
  await shownWhole(logo, 64);
  // Upper left, with no typed wordmark beside it.
  const box = await logo.boundingBox();
  expect(box.x).toBeLessThan(120);
  expect(box.y).toBeLessThan(120);
  expect((await mark.innerText()).trim()).toBe('');
  // A local product asset.
  const asset = await page.request.get(combined);
  expect(asset.status()).toBe(200);
  expect(asset.headers()['content-type']).toContain('image/jpeg');
});

test('Compact or short workspace', async ({ page }) => {
  await signIn(page, users.admin);
  for (const mode of ['light', 'dark']) {
    await page.setViewportSize({ width: 1440, height: 900 });
    await dashboard(page);
    await page.evaluate(scheme => localStorage.setItem('color_scheme', scheme), mode);
    await dashboard(page);
    const logo = page.locator('.inclamo-brand-mark img').first();
    const handle = page.locator('.inclamo-sidebar .cursor-col-resize');

    // Collapsed: the legible symbol, and the profile still at hand.
    await handle.dblclick();
    await expect(logo).toHaveAttribute('src', symbol);
    await shownWhole(logo);
    await expect(page.getByTestId('inclamo-profile-trigger')).toBeInViewport();
    await handle.dblclick();
    await expect(logo).toHaveAttribute('src', combined);

    // A short screen: logo, navigation and profile reachable, nothing on top of the logo.
    await page.setViewportSize({ width: 1280, height: 600 });
    await shownWhole(logo, 64);
    await expect(page.getByTestId('inclamo-profile-trigger')).toBeInViewport();
    const customers = page.getByRole('link', { name: 'Customers', exact: true });
    await customers.scrollIntoViewIfNeeded();
    await expect(customers).toBeInViewport();
    const logoBox = await logo.boundingBox();
    const linkBox = await customers.boundingBox();
    expect(linkBox.y >= logoBox.y + logoBox.height || linkBox.x >= logoBox.x + logoBox.width).toBe(true);
    await page.getByTestId('inclamo-profile-trigger').click();
    await expect(page.getByRole('menu')).toBeVisible();
    await page.keyboard.press('Escape');
  }
  await page.evaluate(() => localStorage.setItem('color_scheme', 'light'));
});

test('Customer widget has its own branding', async ({ browser }) => {
  const inbox = await websiteInbox(admin, 'E2E Widget Brand');
  const saved = await published(admin, inbox.id, value => {
    baseline({ icon: 'custom' })(value);
    value.native.widget_color = '#e11d48';
  }, { icon_image: asUpload(pngBytes('box-front')), avatar_image: asUpload(pngBytes('box-side')) });

  const shopper = await visitor(browser, inbox);
  await expect(shopper.launcher).toHaveCSS('background-color', 'rgb(225, 29, 72)');
  expect(await shopper.page.locator('.inclamo-launcher-image').getAttribute('src')).toContain(saved.icon_url.split('?')[0]);
  await shopper.open();
  const header = shopper.widget.locator('header img').first();
  await expect(header).toHaveJSProperty('complete', true);
  expect(await header.getAttribute('src')).toBe(saved.avatar_url);
  // Nothing of the staff logo reaches the visitor.
  expect(await shopper.page.content()).not.toContain('inclamo-logo-combined');
  expect(await shopper.widget.locator('html').evaluate(node => node.outerHTML.includes('inclamo-logo-combined') || node.outerHTML.includes('inclamo-mark.svg'))).toBe(false);
  await shopper.close();
});

test('User opens the login page', async ({ browser }) => {
  for (const [viewport, colorScheme] of [[{ width: 1440, height: 900 }, 'light'], [{ width: 390, height: 844 }, 'dark']]) {
    const context = await browser.newContext({ baseURL: helpdeskUrl(), viewport, colorScheme });
    const page = await context.newPage();
    await page.goto('/app/login');
    const logos = page.locator(`img[src="${combined}"]`);
    await expect(logos).toHaveCount(1);
    await shownWhole(logos.first(), 96);
    const email = page.locator('input[name="email_address"], input[type="email"]');
    const password = page.locator('input[type="password"]');
    const submit = page.locator('button[type="submit"]');
    for (const control of [email, password, submit]) {
      await control.scrollIntoViewIfNeeded();
      await expect(control).toBeInViewport();
    }
    // Native sign-in still works.
    if (viewport.width > 1000) {
      await email.fill(users.secondAdmin.email);
      await password.fill(users.secondAdmin.password);
      await submit.click();
      await expect(page).toHaveURL(/\/app\/accounts\/\d+/);
    }
    await context.close();
  }
});

test('SuperAdmin signs in and opens the console', async ({ browser }) => {
  const context = await browser.newContext({ baseURL: helpdeskUrl(), viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  await page.goto('/super_admin/sign_in');
  const formLogo = page.locator(`img[src="${combined}"]`);
  await expect(formLogo).toHaveCount(1);
  await shownWhole(formLogo, 96);
  await page.locator('input[name="email_address"], input[type="email"]').first().fill(users.superAdmin.email);
  await page.locator('input[type="password"]').first().fill(users.superAdmin.password);
  await page.locator('button[type="submit"]').click();
  await expect(page).toHaveURL(/\/super_admin(?!\/sign_in)/);

  // The console navigation: the logo, the release link, no typed wordmark.
  const navLogo = page.locator(`img[src="${combined}"]`).filter({ visible: true }).first();
  await shownWhole(navLogo, 56);
  await expect(navLogo).toHaveAttribute('alt', 'Inclamo');
  await expect(page.locator('a[href*="github.com/chatwoot/chatwoot/releases/tag/v"]').first()).toBeVisible();
  const brandRow = navLogo.locator('xpath=ancestor::div[contains(@class,"h-14")][1]');
  await expect(brandRow.getByRole('link', { name: 'Inclamo', exact: true })).toHaveCount(1);
  expect(await brandRow.evaluate(node => node.innerText.split(/\s+/).filter(word => word === 'Inclamo').length)).toBe(0);

  // Dark theme and a narrow screen keep it.
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.reload();
  await shownWhole(page.locator(`img[src="${combined}"]`).filter({ visible: true }).first(), 56);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.reload();
  // The narrow console shows it in its own header.
  await shownWhole(page.locator(`img[src="${combined}"]`).filter({ visible: true }).first(), 56);
  await context.close();
});
