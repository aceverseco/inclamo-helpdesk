import {writeFile} from 'node:fs/promises';
import {chromium,expect,base,login,staff} from './helpers.mjs';
const browser=await chromium.launch({channel:'chrome',headless:true});const results=[];
try{
 const ctx=await staff(browser,await login());const p=await ctx.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));await p.goto(base+'/app/accounts/1/settings/website-widget?inbox=2');await p.getByRole('tab',{name:'Appearance',exact:true}).waitFor();const preview=p.frameLocator('iframe[title="Website widget preview"]');await preview.getByText("Let's find your answer",{exact:true}).waitFor();
 await p.getByRole('combobox',{name:/^Position/}).selectOption('left');await expect(preview.locator('.woot-widget-bubble:not(.woot--close)')).toHaveClass(/woot-elements--left/);
 await p.getByRole('combobox',{name:/^Appearance/}).selectOption('dark');await expect(preview.locator('#app .preview-app > div')).toHaveClass(/dark/);
 await p.getByLabel('Brand color',{exact:true}).fill('#8dc4f2');await expect(preview.locator('.woot-widget-bubble').first()).toHaveCSS('background-color','rgb(141, 196, 242)');
 await p.getByRole('combobox',{name:/^Button style/}).selectOption('expanded_bubble');await p.getByLabel('Button label',{exact:true}).fill('Unsaved launcher label');await expect(preview.getByRole('button',{name:'Unsaved launcher label',exact:true})).toBeVisible();
 await p.getByLabel('Side offset, px',{exact:true}).fill('160');await p.getByLabel('Bottom offset, px',{exact:true}).fill('160');await expect(preview.locator('#cw-widget-holder')).toHaveCSS('--inclamo-widget-y','160px');
 await p.getByRole('combobox',{name:/^Chat icon/}).selectOption('help');await expect(preview.locator('.inclamo-launcher-image')).toHaveCount(0);await expect(preview.locator('.woot-widget-bubble svg path').first()).toHaveAttribute('d',/^M120 10/);
 await p.getByRole('button',{name:'Mobile',exact:true}).click();await expect(preview.locator('.preview-app > div')).toHaveClass(/is-mobile/);await p.getByLabel('Online',{exact:true}).uncheck();await expect(preview.getByText('We are online',{exact:true})).toHaveCount(0);
 await p.getByLabel('Preview screen').selectOption('messages');await expect(preview.locator('#chat-input')).toBeVisible();
 results.push('unsaved position, theme, color, label, icon, offsets, mobile, offline and conversation states use native presentation');
 p.once('dialog',d=>d.accept());await p.goto(base+'/app/accounts/1/dashboard');await p.waitForTimeout(750);await p.getByText('Loading Conversations',{exact:true}).waitFor({state:'hidden'});
 for(const mode of ['light','dark']){
  await p.evaluate(m=>localStorage.setItem('color_scheme',m),mode);await p.reload();await p.waitForTimeout(750);await p.getByText('Loading Conversations',{exact:true}).waitFor({state:'hidden'});const handle=p.locator('.inclamo-sidebar .cursor-col-resize');await handle.dblclick();const logo=p.locator('.inclamo-brand-mark img');await expect(logo).toHaveAttribute('src','/brand-assets/inclamo-mark.svg');await expect(p.getByTestId('inclamo-profile-trigger')).toBeInViewport();await p.screenshot({path:`build/evidence/website-widget/logo-compact-${mode}.png`});await handle.dblclick();await expect(logo).toHaveAttribute('src','/brand-assets/inclamo-logo-combined.jpg');
 }
 results.push('compact sidebar keeps symbol and profile access in light/dark mode');expect(errors).toEqual([]);console.log(JSON.stringify(results));
}finally{await writeFile('build/evidence/website-widget/presentation.json',JSON.stringify(results,null,2)+'\n');await browser.close()}
