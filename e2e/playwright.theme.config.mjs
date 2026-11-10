import { defineConfig } from '@playwright/test';

// Only this fixture-backed suite may retain screenshots in CI.
export default defineConfig({
  testDir: './tests',
  testMatch: process.env.THEME_ONBOARDING === '1' ? 'inclamo-onboarding.spec.mjs' : process.env.THEME_LEGACY === '1' ? 'dashboard-theme.spec.mjs' : 'inclamo-product-design.spec.mjs',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 15_000, toHaveScreenshot: { maxDiffPixelRatio: 0.002 } },
  reporter: [['list'], ['json', { outputFile: `${process.env.E2E_OUTPUT || './theme-output'}/results.json` }]],
  outputDir: process.env.E2E_OUTPUT || './theme-output',
  snapshotPathTemplate: '{testDir}/../theme/snapshots/{arg}{ext}',
  use: {
    browserName: 'chromium',
    baseURL: process.env.HELPDESK_URL || 'http://rails:3000',
    viewport: { width: 1440, height: 900 },
    locale: 'en-US',
    timezoneId: 'UTC',
    reducedMotion: 'reduce',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
});
