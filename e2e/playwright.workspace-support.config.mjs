import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests',
  testMatch: ['workspace-widgets.spec.mjs', 'in-product-support.spec.mjs'],
  workers: 1, fullyParallel: false, retries: 0, timeout: 120_000,
  expect: { timeout: 20_000 },
  reporter: [['list'], ['json', { outputFile: `${process.env.E2E_OUTPUT || './workspace-support-output'}/results.json` }]],
  outputDir: `${process.env.E2E_OUTPUT || './workspace-support-output'}/test-results`,
  use: {
    actionTimeout: 20_000, navigationTimeout: 30_000,
    browserName: 'chromium', baseURL: process.env.HELPDESK_URL || 'http://client:3000',
    viewport: { width: 1440, height: 900 }, locale: 'en-US', timezoneId: 'UTC', reducedMotion: 'reduce',
    screenshot: 'only-on-failure', trace: 'retain-on-failure',
    launchOptions: { args: ['--unsafely-treat-insecure-origin-as-secure=http://client:3000,http://hosted:3000', '--enable-usermedia-screen-capturing', '--auto-select-desktop-capture-source=Entire screen'] },
  },
});
