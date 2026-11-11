import { mkdirSync } from 'node:fs';
mkdirSync('build/evidence/website-widget', { recursive: true });
import { chromium } from '@playwright/test';
import { writeFile } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
const prefix = process.env.WIDGET_EVIDENCE || 'baseline';
const base = process.env.WIDGET_BASE || 'http://localhost:3194';
const r = await fetch(`${base}/auth/sign_in`, { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({email:'theme-admin@example.test',password:'Synthetic-theme-only-123!'}), signal: AbortSignal.timeout(15000) });
if (!r.ok) throw new Error(`Login ${r.status}`);
const headers = Object.fromEntries(['access-token','client','uid','expiry','token-type'].map(k=>[k,r.headers.get(k)]));
const inbox = await (await fetch(`${base}/api/v1/accounts/1/inboxes/2`,{headers})).json();
const browser = await chromium.launch({channel:'chrome',headless:true});
const result = {base,settings:Object.fromEntries(['id','name','widget_color','welcome_title','welcome_tagline','pre_chat_form_enabled','selected_feature_flags','reply_time'].map(k=>[k,inbox[k]])), assets:[], requests:[], connections:[]};
try {
  const context = await browser.newContext();
  await context.grantPermissions(['local-network-access']);
  const page = await context.newPage();
  await page.route(`${base}/widget-audit-host`, route=>route.fulfill({contentType:'text/html',body:`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><h1>Widget test website</h1><script src="${base}/packs/js/sdk.js"></script><script>chatwootSDK.run({baseUrl:${JSON.stringify(base)},websiteToken:${JSON.stringify(inbox.website_token)}})</script></body></html>`}));
  const pending = [];
  page.on('response',response=>{
    if(response.request().resourceType()==='script') pending.push(response.body().then(bytes=>result.assets.push({url:response.url().replace(base,''),gzip:gzipSync(bytes).length})).catch(()=>{}));
  });
  page.on('request',r=>{if(!['script','image','font','stylesheet','document'].includes(r.resourceType())) result.requests.push({path:new URL(r.url()).pathname,type:r.resourceType(),at:Date.now()});});
  page.on('websocket',s=>result.connections.push(s.url().replace(/\?.*/,'')));
  await page.goto(`${base}/widget-audit-host`);
  await page.locator('.woot-widget-bubble:not(.woot--close)').waitFor();
  await page.locator('.woot-widget-bubble:not(.woot--close)').click();
  await page.frameLocator('#chatwoot_live_chat_widget').getByText('Start Conversation',{exact:false}).first().waitFor();
  await page.screenshot({path:`build/evidence/website-widget/${prefix}-desktop.png`});
  await page.setViewportSize({width:375,height:812});
  await page.screenshot({path:`build/evidence/website-widget/${prefix}-mobile.png`});
  result.idleStart = Date.now();
  await new Promise(r=>setTimeout(r,12000));
  await Promise.all(pending);
  result.gzipTotal = result.assets.reduce((sum,a)=>sum+a.gzip,0);
  await writeFile(`build/evidence/website-widget/${prefix}.json`,JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify({assets:result.assets.length,gzipTotal:result.gzipTotal,connections:result.connections,requests:result.requests.map(r=>r.path)}));
} finally {await browser.close();}
