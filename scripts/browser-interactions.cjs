const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');process.env.TMPDIR=path.join(root,'work/tmp');
const {chromium}=require('/Users/chenmo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const base='http://127.0.0.1:8848/knhanes_atlas/';
const result={events:[],shares:[],requests:[],pdfs:[]};let context,page,frame;
async function load(p,url) {
  await p.goto(url,{waitUntil:'domcontentloaded'});
  for(let i=0;i<180;i++) {
    for(const f of p.frames())if(await f.locator('#pvarname').count()){
      await f.waitForFunction(()=>window.Shiny?.shinyapp?.$socket?.readyState===1,null,{timeout:60000});return f;
    }
    await p.waitForTimeout(1000);
  }
  throw new Error('Browser R startup timeout');
}
const save=()=>fs.writeFileSync(path.join(root,'checks/browser-interactions.json'),JSON.stringify(result,null,2));
(async()=>{
  context=await chromium.launchPersistentContext(path.join(root,'work/browser-cold'),{
    executablePath:'/Users/chenmo/Library/Caches/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-mac-arm64/chrome-headless-shell',
    headless:true,viewport:{width:1440,height:1000},acceptDownloads:true,downloadsPath:path.join(root,'checks/downloads')});
  context.on('request',r=>result.requests.push(r.url()));
  page=context.pages()[0]||await context.newPage();
  page.on('pageerror',e=>result.events.push(e.message));
  const start=Date.now();frame=await load(page,base);
  result.startup_seconds=(Date.now()-start)/1000;console.log('Startup:',result.startup_seconds);save();
  await frame.locator('a[data-value="Browse By Phenotype"]').click();
  const control=frame.locator('#pvarname + .selectize-control');
  await control.locator('.selectize-input').click();
  await control.locator('input').fill('p_ggt');
  await control.locator('.option[data-value="p_ggt"]').click();
  await frame.waitForFunction(()=>document.querySelector('#pvariable_description')?.textContent==='Gamma-glutamyl transferase');
  result.selector_search=true;
  const t=frame.locator('#by_phenotype_table');
  await t.locator('.rt-search').fill('Beer consumption frequency');
  await frame.waitForFunction(()=>{
    const rows=[...document.querySelectorAll('#by_phenotype_table .rt-tbody .rt-tr-group')];
    return rows.length>0&&rows.every(x=>x.textContent.includes('Beer consumption frequency'));
  });result.table_search=true;
  await t.locator('.rt-search').fill('');
  const sort=t.locator('[role="columnheader"]').first();
  await sort.click();assert.ok(['ascending','descending'].includes(await sort.getAttribute('aria-sort')));result.table_sort=true;
  const next=t.getByRole('button',{name:'Next page',exact:true});
  if(await next.count()){
    const previous=await t.locator('.rt-tbody').innerText();await next.click();
    await frame.waitForFunction(old=>document.querySelector('#by_phenotype_table .rt-tbody')?.innerText!==old,previous);result.table_pagination=true;
  } else throw new Error('Missing table Next button');
  for(const [kind,nav,input,button] of [
    ['phenotype','Browse By Phenotype','pvarname','copy_pheno_link'],
    ['exposure','Browse By Exposure','evarname','copy_expo_link'],
    ['group','Browse by Exposure Group','egroup','copy_group_link']]){
    await frame.locator('a[data-value="'+nav+'"]').click();
    const chosen=await frame.locator('#'+input).evaluate(el=>{const v=Object.keys(el.selectize.options).find(v=>v!==el.value);el.selectize.setValue(v);return v;});
    await frame.waitForFunction(()=>!document.documentElement.classList.contains('shiny-busy'));
    await frame.locator('#'+button).click();
    const url=await frame.locator('#share_link_text').inputValue();
    assert.equal(new URL(url).searchParams.get(kind),chosen);
    await frame.locator('#shiny-modal button[data-dismiss="modal"]').click();
    const p=await context.newPage(),f=await load(p,url);
    await f.waitForFunction(({nav,input,value})=>document.querySelector('.navbar-nav > li.active > a')?.textContent===nav&&document.getElementById(input)?.value===value,{nav,input,value:chosen},{timeout:60000});
    result.shares.push({kind,value:chosen,url,active_tab:nav,verified:true});await p.close();console.log('Changed selection share:',kind);save();
  }
  await frame.locator('a[data-value="Downloads"]').click();
  const entries=JSON.parse(fs.readFileSync(path.join(root,'src/data/figures.json')));
  for(let i=0;i<entries.length;i++){
    await frame.locator('#figure').evaluate((el,v)=>el.selectize.setValue(String(v)),i+1);
    await frame.waitForFunction(title=>document.querySelector('#figure_preview img')?.alt===title&&document.querySelector('#figure_preview img')?.complete&&document.querySelector('#figure_preview img')?.naturalWidth>0,entries[i].title,{timeout:30000});
  }
  result.figure_previews=entries.length;
  // Fetch one original manuscript PDF through the visible download control.
  const index=entries.findIndex(e=>e.file.endsWith('.pdf'));
  await frame.locator('#figure').evaluate((el,v)=>el.selectize.setValue(String(v)),index+1);
  await frame.waitForFunction(title=>document.querySelector('#figure_preview img')?.alt===title,entries[index].title);
  const event=page.waitForEvent('download');await frame.locator('#figure_preview a[download]').click();
  const d=await event;assert.equal(await d.failure(),null);
  const target=path.join(root,'checks/downloads',d.suggestedFilename());await d.saveAs(target);
  const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
  assert.equal(hash(target),hash(path.join(root,'site/research',entries[index].file)));
  result.pdfs.push({file:d.suggestedFilename(),exact_match:true});
  result.external_requests=[...new Set(result.requests.filter(u=>u.startsWith('http')&&!u.startsWith(base)))];
  assert.deepEqual(result.events,[]);assert.deepEqual(result.external_requests,[]);
  result.passed=true;save();console.log('Interaction checks passed');
})().catch(async e=>{result.error=e.stack;console.error(e.stack);save();
  if(frame)fs.writeFileSync(path.join(root,'checks/interaction-error.html'),await frame.content().catch(()=>''));
  if(page)await page.screenshot({path:path.join(root,'checks/interaction-error.png')}).catch(()=>{});
  process.exitCode=1;
}).finally(async()=>{if(context)await context.close();});
