import { defineConfig } from '@playwright/test';
import { join } from 'node:path';

// The tests drive a running helpdesk (HELPDESK_URL) connected to a development
// store. They change real data in that store, so they run one at a time.
export default defineConfig({
  testDir: './tests',
  // These files run against stacks of their own, with their own configs:
  // e2e/theme/run.sh (playwright.theme.config.mjs) and
  // e2e/workspace-support/run.sh (playwright.workspace-support.config.mjs).
  testIgnore: [
    'dashboard-theme.spec.mjs',
    'inclamo-product-design.spec.mjs',
    'inclamo-onboarding.spec.mjs',
    'workspace-widgets.spec.mjs',
    'in-product-support.spec.mjs',
  ],
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 20_000 },
  reporter: [['list'], ['json', { outputFile: join(process.env.E2E_OUTPUT || './output', 'results.json') }]],
  outputDir: process.env.E2E_OUTPUT || './output',
  use: {
    baseURL: process.env.HELPDESK_URL || 'http://localhost:3000',
    viewport: { width: 1440, height: 900 },
    // A trace or a page snapshot holds what was typed, the store's credentials
    // included: none is kept where others could download it.
    screenshot: process.env.CI ? 'off' : 'only-on-failure',
    trace: process.env.CI ? 'off' : 'retain-on-failure',
  },
});
