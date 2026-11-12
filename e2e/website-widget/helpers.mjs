import { execFileSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
mkdirSync('build/evidence/website-widget', { recursive: true });
import { chromium, expect } from '@playwright/test';
export { chromium, expect };
export const base = process.env.WIDGET_BASE || 'http://localhost:3197';
export const accountPath = '/api/v1/accounts/1';
export async function login(role = 'admin') {
  const r = await fetch(`${base}/auth/sign_in`, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`theme-${role}@example.test`,password:'Synthetic-theme-only-123!'})});
  if (!r.ok) throw new Error(`Synthetic login ${r.status}`);
  return Object.fromEntries(['access-token','client','uid','expiry','token-type'].map(k=>[k,r.headers.get(k)]));
}
export async function api(headers, path, method = 'GET', body) {
  const r = await fetch(`${base}${path}`, {method,headers:{...headers,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
  const raw = await r.text();
  const data = raw ? JSON.parse(raw) : null;
  if(!r.ok) throw new Error(`${method} ${path}: ${r.status}: ${JSON.stringify(data)}`);
  return data;
}
export async function staff(browser, headers, options={}) {
  const context = await browser.newContext({viewport:{width:1600,height:1000},...options});
  await context.grantPermissions(['local-network-access']);
  await context.addCookies([{name:'cw_d_session_info',value:encodeURIComponent(JSON.stringify(headers)),url:base}]);
  return context;
}
export async function visitor(browser, {explicit={},path='/widget-audit-host',...options}={}) {
  const context = await browser.newContext({viewport:{width:1280,height:900},...options});
  await context.grantPermissions(['local-network-access']);
  const page = await context.newPage();
  await page.route(`${base}/widget-audit-host**`,route=>route.fulfill({contentType:'text/html',body:`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="font:16px system-ui;margin:32px"><h1>Example Store</h1><p>Synthetic widget acceptance test</p><button id="custom-open" onclick="window.$chatwoot.toggle('open')">Contact support</button><script>window.chatwootSettings=${JSON.stringify(explicit)};</script><script src="${base}/packs/js/sdk.js"></script><script>chatwootSDK.run({baseUrl:${JSON.stringify(base)},websiteToken:'synthetic-theme-widget'});</script></body></html>`}));
  await page.goto(base+path);
  await page.waitForFunction(()=>window.$chatwoot?.hasLoaded);
  return {context,page,widget:page.frameLocator('#chatwoot_live_chat_widget')};
}
export const configPath = `${accountPath}/inclamo/website_widgets/2`;
export async function publish(headers, edit) {
  const config=await api(headers,configPath);
  const value={revision:config.revision,settings:config.settings,native:config.native};
  await edit(value);
  return api(headers,configPath,'PATCH',{configuration:value});
}

// Fixture-only commands run locally, or on the explicitly selected synthetic host.
export function fixtureCommand(args) {
  const host = process.env.WIDGET_FIXTURE_SSH;
  if (!host) return execFileSync(args[0], args.slice(1), { encoding: 'utf8' });
  const quote = value => "'" + String(value).replaceAll("'", "'\\''") + "'";
  return execFileSync(process.env.WIDGET_SSH_COMMAND || 'ssh', ['--', host, args.map(quote).join(' ')], { encoding: 'utf8' });
}
