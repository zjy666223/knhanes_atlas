const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
process.env.TMPDIR = path.join(root, 'work/tmp');
const { chromium } = require('/Users/chenmo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const base = process.env.ATLAS_URL || 'http://127.0.0.1:8848/knhanes_atlas/';
const checkDir = process.env.ATLAS_CHECK_DIR || 'checks';
const results = { plots: [], tables: [], downloads: [], shares: [], cases: {}, events: [] };
let context, page, frame;
const report = () => fs.writeFileSync(path.join(root, checkDir, 'browser-check.json'), JSON.stringify(results, null, 2));
async function waitApp(p) {
  const started = Date.now();
  while (Date.now() - started < 180000) {
    for (const f of p.frames()) {
      if (await f.locator('#pvarname').count()) {
        await f.waitForFunction(() => typeof window.Shiny?.setInputValue === 'function' && window.Shiny?.shinyapp?.$socket?.readyState === 1, null, { timeout: 60000 });
        return f;
      }
    }
    await p.waitForTimeout(1000);
  }
  throw new Error('Browser R startup timed out');
}
async function idle() {
  await frame.waitForFunction(() => !document.documentElement.classList.contains('shiny-busy'), null, { timeout: 90000 });
  await page.waitForTimeout(250);
}
async function tab(name) {
  await frame.locator('a[data-value]').filter({visible:true}).filter({hasText:new RegExp('^'+name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'$')}).first().click();
}
async function plot(id) {
  await frame.waitForFunction(id => {
    const el=document.getElementById(id), im=el?.querySelector('img');
    return el && !el.classList.contains('recalculating') && im?.complete && im.naturalWidth>0 && im.getAttribute('src');
  },id,{timeout:90000});
  await idle();
  results.plots.push(id); console.log('Plot:',id); report();
}
async function table(id) {
  await frame.locator('#'+id+' .rt-table').waitFor({timeout:60000});
  await idle();
  results.tables.push(id); report();
}
async function download(id,label) {
  const event=page.waitForEvent('download',{timeout:60000});
  await frame.locator('#'+id).click();
  const d=await event;
  assert.equal(await d.failure(),null);
  const target=path.join(root,checkDir,'downloads',label+'_'+d.suggestedFilename());
  await d.saveAs(target);
  results.downloads.push({label,file:target,bytes:fs.statSync(target).size}); report();
  return target;
}
async function select(id,value) {
  await frame.evaluate(({id,value}) => document.getElementById(id).selectize.setValue(value),{id,value});
  await idle();
}
(async()=>{
  fs.mkdirSync(path.join(root,checkDir,'downloads'),{recursive:true});
  context=await chromium.launchPersistentContext(path.join(root,'work/browser'),{
    executablePath:'/Users/chenmo/Library/Caches/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-mac-arm64/chrome-headless-shell',
    headless:true,viewport:{width:1440,height:1000},acceptDownloads:true,
    downloadsPath:path.join(root,checkDir,'downloads'),args:['--disable-crash-reporter']
  });
  page=context.pages()[0]||await context.newPage();
  page.on('pageerror',e=>results.events.push({type:'pageerror',text:e.message}));
  page.on('requestfailed',r=>results.events.push({type:'requestfailed',url:r.url(),error:r.failure()}));
  page.on('response',r=>{if(r.status()>=400)results.events.push({type:'http',status:r.status(),url:r.url()});});
  page.on('console',m=>{if(m.type()==='error' && !m.text().startsWith('preload error:'))results.events.push({type:'console',text:m.text()});});
  const start=Date.now();
  await page.goto(base,{waitUntil:'domcontentloaded'});
  frame=await waitApp(page);
  results.startup_seconds=(Date.now()-start)/1000;
  await frame.waitForFunction(()=>{const im=document.querySelector('.study-flowchart');return im?.complete && im.naturalWidth>0;},null,{timeout:30000});
  await page.screenshot({path:path.join(root,checkDir,'home.png'),fullPage:true});
  results.cover=true; console.log('Home ready',results.startup_seconds,'seconds'); report();
  await tab('Browse By Phenotype');
  for(const [name,id] of [
    ['-log(P) vs. Exposure Group','by_phenotype_manhattan_plot'],['Effect Sizes','by_phenotype_effect_size'],
    ['R^2','by_phenotype_r2_plot'],['-log(P) vs. Effect Size','by_phenotype_volcano_plot'],
    ['Globe','by_phenotype_globe_plot'],['Model comparison','by_phenotype_estimate_plot']]) {await tab(name);await plot(id);}
  await table('by_phenotype_table');await table('exposure_corr_table');
  await download('by_phenotype_table_download','phenotype');
  await frame.locator('#copy_pheno_link').click();
  results.shares.push({kind:'phenotype',url:await frame.locator('#share_link_text').inputValue()});
  await frame.locator('#shiny-modal button[data-dismiss="modal"]').click();
  await tab('Browse By Exposure');
  for(const [name,id] of [['-log(P) vs. Effect Size','by_exposure_volcano_plot'],['ES Histogram','by_exposure_context_plot'],['R^2','by_exposure_r2_plot'],['Model comparison','by_exposure_estimate_plot']]){await tab(name);await plot(id);}
  await table('by_exposure_table');await table('phenotype_corr_table');
  await download('by_exposure_table_download','exposure');
  await frame.locator('#copy_expo_link').click();
  results.shares.push({kind:'exposure',url:await frame.locator('#share_link_text').inputValue()});
  await frame.locator('#shiny-modal button[data-dismiss="modal"]').click();
  await tab('Browse by Exposure Group');
  for(const [name,id] of [['-log(P) vs. Effect Size','by_exposure_group_volcano_plot'],['ES Histogram','by_exposure_group_context_plot'],['R^2','by_exposure_group_r2_plot'],['Model comparison','by_exposure_group_estimate_plot']]){await tab(name);await plot(id);}
  await table('by_exposure_group_table');await download('by_exposure_group_table_download','group');
  await frame.locator('#copy_group_link').click();
  results.shares.push({kind:'group',url:await frame.locator('#share_link_text').inputValue()});
  await frame.locator('#shiny-modal button[data-dismiss="modal"]').click();
  await tab('E Catalog');await table('e_catalog_table');
  await tab('P Catalog');await table('p_catalog_table');
  await tab('Vibration of effects');
  await plot('voe_scatter');await plot('voe_driver_plot');
  await page.screenshot({path:path.join(root,checkDir,'vibration.png'),fullPage:true});
  await download('voe_models_download','voe_default');
  await download('voe_drivers_download','voe_drivers');
  await tab('Model specifications');await plot('voe_specification_plot');
  await page.screenshot({path:path.join(root,checkDir,'specifications.png'),fullPage:true});
  await tab('Results');await table('voe_model_table');await table('voe_summary_table');
  await download('voe_summary_download','voe_summary');
  results.default_stats=await frame.locator('#voe_pair_stats').innerText();
  await tab('Atlas overview');await plot('voe_range_plot');await plot('voe_retention_plot');await table('voe_overview_table');
  await tab('Methods');assert.match(await frame.locator('body').innerText(),/1,536,512/);
  await tab('Results');
  const cases=JSON.parse(fs.readFileSync(path.join(root,'checks/cases.json')));
  for(const label of ['categorical','education','failed']) {
    const c=cases[label];
    await select('voe_phenotype',c.phenotype_id);
    await frame.waitForFunction(id=>Object.hasOwn(document.getElementById('voe_exposure').selectize.options,id),c.exposure_id,{timeout:30000});
    await select('voe_exposure',c.exposure_id);
    await frame.waitForFunction(id=>Object.hasOwn(document.getElementById('voe_contrast').selectize.options,id),c.contrast_id,{timeout:30000});
    await select('voe_contrast',c.contrast_id);
    await frame.waitForFunction(expected=>document.getElementById('voe_contrast_text').innerText===expected,c.contrast_label,{timeout:30000});
    await table('voe_model_table');
    results.cases[label]={title:await frame.locator('#voe_pair_title').innerText(),contrast:await frame.locator('#voe_contrast_text').innerText(),stats:await frame.locator('#voe_pair_stats').innerText(),factors:await frame.locator('#voe_factor').evaluate(e=>Object.keys(e.selectize.options))};
    await download('voe_models_download','voe_'+label); console.log('Case:',label);report();
  }
  await tab('Downloads');await table('joint_table');
  await frame.waitForFunction(()=>{const im=document.querySelector('#figure_preview img');return im?.complete&&im.naturalWidth>0;});
  results.static_links=await frame.locator('a[href*="/research/"]').evaluateAll(els=>els.map(e=>({text:e.textContent,href:e.href})));
  for(const item of results.shares){
    assert.ok(item.url.startsWith(base+'?'));
    const p=await context.newPage();await p.goto(item.url,{waitUntil:'domcontentloaded'});
    const f=await waitApp(p);
    const input={phenotype:'pvarname',exposure:'evarname',group:'egroup'}[item.kind];
    const expected=new URL(item.url).searchParams.get(item.kind);
    await f.waitForFunction(({id,value})=>document.getElementById(id).value===value,{id:input,value:expected},{timeout:60000});
    const active = {phenotype:'Browse By Phenotype', exposure:'Browse By Exposure', group:'Browse by Exposure Group'}[item.kind];
    await f.waitForFunction(text=>document.querySelector('.navbar-nav > li.active > a')?.textContent===text,active,{timeout:60000});
    item.active_tab=await f.locator('.navbar-nav > li.active > a').innerText();
    item.verified=true;await p.close();console.log('Share:',item.kind);report();
  }
  results.visible_errors=await frame.locator('.shiny-output-error:visible').allTextContents();
  assert.deepEqual(results.visible_errors,[]);
  results.passed=true;report();console.log('Browser checks passed');
})().catch(async e=>{
  results.error=e.stack;report();console.error(e.stack);
  if(page){await page.screenshot({path:path.join(root,checkDir,'browser-error.png'),fullPage:true}).catch(()=>{});
    if(frame)fs.writeFileSync(path.join(root,checkDir,'browser-error.html'),await frame.content().catch(()=>''));}
  process.exitCode=1;
}).finally(async()=>{if(context)await context.close();});
