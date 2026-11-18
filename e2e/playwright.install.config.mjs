import { defineConfig } from '@playwright/test';
import { join } from 'node:path';

// The install tests (e2e/install-run.sh): one file, in order, against an
// instance the tests install themselves. The web server's certificate comes
// from its internal authority in the install's test mode, so the browser does
// not check it; the test "Fresh install" checks it against that authority.
export default defineConfig({
  testDir: './tests',
  testMatch: 'instance-installation.spec.mjs',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 5 * 60_000,
  expect: { timeout: 30_000 },
  reporter: [['list'], ['json', { outputFile: join(process.env.E2E_OUTPUT || './output', 'results.json') }]],
  outputDir: join(process.env.E2E_OUTPUT || './output', 'playwright'),
  use: {
    ignoreHTTPSErrors: true,
    viewport: { width: 1440, height: 900 },
    // A trace or a page snapshot holds what was typed: none is kept.
    screenshot: 'off',
    trace: 'off',
  },
});
