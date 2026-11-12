import {writeFile,readFile} from 'node:fs/promises';
import {chromium,expect,base,login,api,staff,configPath} from './helpers.mjs';
const browser=await chromium.launch({channel:'chrome',headless:true});const headers=await login();const evidence={base,checks:[],errors:[]};const ok=name=>{evidence.checks.push(name);console.log('PASS',name)};
try{
 const ctx=await staff(browser,headers);const p=await ctx.newPage();p.on('pageerror',e=>evidence.errors.push(e.message));await p.goto(base+'/app/accounts/1/settings/website-widget?inbox=2');await p.getByRole('tab',{name:'Appearance',exact:true}).waitFor();
 await p.getByRole('tab',{name:'Home screen'}).click();
 await p.getByRole('button',{name:'Add button',exact:true}).click();const last=p.locator('article.widget-entry').filter({has:p.getByLabel('Message to send')}).last();await last.getByLabel('Button label',{exact:true}).fill('New draft intent');await last.getByLabel('Message to send').fill('Draft intent message');
 await last.getByLabel('Move intent up').click();const labels=await p.getByLabel('Button label',{exact:true}).evaluateAll(inputs=>inputs.map(x=>x.value));expect(labels.at(-2)).toBe('New draft intent');
 const intents=p.locator('article.widget-entry').filter({has:p.getByLabel('Message to send')});await intents.nth(labels.length-2).getByLabel('Enabled',{exact:true}).uncheck();
 const preview=p.frameLocator('iframe[title="Website widget preview"]');await expect(preview.getByRole('button',{name:'New draft intent',exact:false})).toHaveCount(0);
 await intents.nth(labels.length-2).getByRole('button',{name:'Remove',exact:true}).click();expect(await p.getByLabel('Button label',{exact:true}).count()).toBe(labels.length-1);
 await p.getByRole('button',{name:'Add link',exact:true}).click();await p.getByLabel('Link label',{exact:true}).last().fill('Invalid draft link');await p.getByLabel('HTTPS address',{exact:true}).last().fill('javascript:alert(1)');await p.getByRole('button',{name:'Save changes',exact:true}).click();await expect(p.getByRole('alert')).toContainText('HTTPS');await expect(p.getByLabel('Link label',{exact:true}).last()).toHaveValue('Invalid draft link');
 const saved=await api(headers,configPath);expect(saved.settings.links.some(l=>l.label==='Invalid draft link')).toBe(false);
 let dialogSeen=false;p.once('dialog',async d=>{dialogSeen=true;await d.dismiss()});await p.getByRole('link',{name:'Customers',exact:true}).click();expect(dialogSeen).toBe(true);await expect(p).toHaveURL(/website-widget/);
 p.once('dialog',d=>d.accept());await p.getByRole('button',{name:'Reload saved settings'}).click();await p.getByRole('tab',{name:'Appearance',exact:true}).click();
 ok('home editing: add, reorder, disable, remove, validation and navigation-away protection');
 const imageBuffer=await readFile('build/website-widget-workspace/chatwoot/spec/assets/avatar.png');
 await p.getByLabel('Upload header logo',{exact:true}).setInputFiles({name:'header.png',mimeType:'image/png',buffer:imageBuffer});await p.getByRole('button',{name:'Save changes',exact:true}).click();await p.getByRole('status').filter({hasText:'Changes saved'}).waitFor();await expect(preview.locator('header img')).toHaveJSProperty('complete',true);expect((await api(headers,configPath)).avatar_url).not.toEqual((await api(headers,configPath)).icon_url);
 await p.getByRole('button',{name:'Remove logo',exact:true}).click();await p.getByRole('button',{name:'Save changes',exact:true}).click();await p.getByRole('status').filter({hasText:'Changes saved'}).waitFor();
 ok('header upload/removal remains independent of launcher identity');
 const nativeLinks=[];await p.getByRole('tab',{name:'Behavior',exact:true}).click();for(const a of await p.locator('a.widget-native-link').all())nativeLinks.push(await a.getAttribute('href'));
 for(const href of nativeLinks){await p.goto(base+href);await expect(p.locator('.inclamo-brand-mark')).toBeVisible();expect(p.url()).toContain(href);await expect(p.locator('body')).not.toContainText('Page not found')}
 ok('all six native settings destinations remain valid');
 await p.goto(base+'/app/accounts/1/dashboard');
 for(const mode of ['light','dark']){
  await p.evaluate(v=>localStorage.setItem('color_scheme',v),mode);await p.reload();
  for(const [label,size] of [['desktop',{width:1440,height:900}],['short',{width:1280,height:600}],['mobile',{width:390,height:844}]]){
   await p.setViewportSize(size);if(label==='mobile')await p.locator('#mobile-sidebar-launcher button').click();
   const logo=p.locator('.inclamo-brand-mark img').first();await expect(logo).toBeVisible();const rect=await logo.boundingBox();expect(Math.abs(rect.width-rect.height)).toBeLessThan(1);expect(await logo.getAttribute('src')).toContain('inclamo-logo-combined.jpg');
   await expect(p.getByTestId('inclamo-profile-trigger')).toBeInViewport();await expect(p.getByRole('link',{name:'Customers',exact:true})).toBeInViewport();
   await p.screenshot({path:`build/evidence/website-widget/logo-${label}-${mode}.png`});
   if(label==='mobile')await p.setViewportSize({width:1440,height:900});
  }
 }
 ok('combined logo: desktop, short height, mobile, light/dark; navigation and profile remain reachable');
 const agentCtx=await staff(browser,await login('agent'));const agent=await agentCtx.newPage();await agent.goto(base+'/app/accounts/1/settings/website-widget?inbox=2');await expect(agent.getByRole('heading',{name:'Website widget',exact:true})).toHaveCount(0);const forbidden=await agent.request.get(base+configPath,{headers:await login('agent')});expect(forbidden.status()).toBe(403);await agentCtx.close();
ok('agent cannot open administrator editor or configuration');
 const emptyContext=await staff(browser,await login());const empty=await emptyContext.newPage();await empty.goto(base+'/app/accounts/2/settings/website-widget');await expect(empty.getByRole('heading',{name:'Connect your first website',exact:true})).toBeVisible();expect(await empty.getByRole('link',{name:'Add website channel',exact:false}).getAttribute('href')).toBe('/app/accounts/2/settings/inboxes/new/website');await empty.getByRole('link',{name:'Add website channel',exact:false}).click();await expect(empty).toHaveURL(/inboxes\/new\/website/);await emptyContext.close();
 ok('empty account opens native website creation without other-account settings');
 expect(evidence.errors).toEqual([]);
}finally{await writeFile('build/evidence/website-widget/editor-checks.json',JSON.stringify(evidence,null,2)+'\n');await browser.close()}
