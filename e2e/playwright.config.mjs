import { defineConfig } from '@playwright/test';

// The tests drive a running helpdesk (HELPDESK_URL) connected to a development
// store. They change real data in that store, so they run one at a time.
export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 20_000 },
  reporter: [['list']],
  outputDir: process.env.E2E_OUTPUT || './output',
  use: {
    baseURL: process.env.HELPDESK_URL || 'http://localhost:3000',
    viewport: { width: 1440, height: 900 },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
});
