// Match native feature settings to the baseline; restore the fixture afterward.
import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { base, login, api, publish, configPath, expect } from './helpers.mjs';
const headers = await login();
const original = await api(headers, configPath);
try {
  await publish(headers, value => {
    value.native.portal_id = null;
    Object.assign(value.settings, {
      links: [], theme: 'light', language_mode: 'fixed', locale: 'en',
      visibility: { mode: 'all', rules: [] },
    });
  });
  execFileSync(process.execPath, ['e2e/website-widget/baseline.mjs'], {
    stdio: 'inherit', env: { ...process.env, WIDGET_BASE: base, WIDGET_EVIDENCE: 'customized' },
  });
  const read = async name => JSON.parse(await readFile(`build/evidence/website-widget/${name}.json`, 'utf8'));
  const baseline = await read('baseline');
  const customized = await read('customized');
  const result = {
    baselineGzipBytes: baseline.gzipTotal,
    customizedGzipBytes: customized.gzipTotal,
    addedGzipBytes: customized.gzipTotal - baseline.gzipTotal,
    budgetBytes: 20 * 1024,
    baselineConnections: baseline.connections.length,
    customizedConnections: customized.connections.length,
    baselineIdleRequests: baseline.requests.filter(r => r.at > baseline.idleStart).map(r => r.path),
    customizedIdleRequests: customized.requests.filter(r => r.at > customized.idleStart).map(r => r.path),
    visitorAssets: customized.assets.map(a => a.url),
  };
  expect(result.addedGzipBytes).toBeLessThanOrEqual(result.budgetBytes);
  expect(result.customizedConnections).toBe(1);
  expect(result.customizedIdleRequests).toEqual(result.baselineIdleRequests);
  expect(result.visitorAssets.some(a => /dashboard|inclamo-widget-preview|builder/i.test(a))).toBe(false);
  await writeFile('build/evidence/website-widget/performance.json', JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result));
} finally {
  await publish(headers, value => {
    value.native = original.native;
    value.settings = original.settings;
  });
}
