const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
process.env.TMPDIR = path.join(root, 'work/tmp');
const {chromium} = require('/Users/chenmo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const base = process.env.ATLAS_URL || 'http://127.0.0.1:8848/knhanes_atlas/';
const out = path.join(root, process.env.ATLAS_CHECK_DIR || 'checks/loading');
fs.mkdirSync(out, {recursive:true});
let browser;
const result = {url:base, errors:[]};
const report = () => fs.writeFileSync(path.join(out, 'loading.json'), JSON.stringify(result, null, 2));
async function ready(page) {
  await page.waitForFunction(() => performance.getEntriesByName('atlas-interactive-ready').length > 0, null, {timeout:180000});
  return page.frames().find(frame => frame.url().includes('/app_'));
}
(async () => {
  browser = await chromium.launch({
    executablePath:'/Users/chenmo/Library/Caches/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-mac-arm64/chrome-headless-shell',
    headless:true, args:['--disable-crash-reporter']
  });
  // Study text and every direct download remain usable without the R engine or JS.
  let context = await browser.newContext({javaScriptEnabled:false,viewport:{width:390,height:844}});
  let page = await context.newPage();
  await page.goto(base,{waitUntil:'load'});
  assert.equal(await page.locator('#downloads a[download]').count(), 19);
  assert.ok(await page.locator('#about').isVisible());
  assert.equal(await page.locator('#about').innerText().then(x=>x.includes('26,078')), true);
  await page.screenshot({path:path.join(out,'mobile-static.png')});
  result.no_javascript = true;
  await context.close();

  // A fresh browser cache measures actual shell and engine readiness separately.
  context = await browser.newContext({viewport:{width:1440,height:1000}});
  page = await context.newPage();
  const requests = [];
  page.on('request', request=>requests.push(request.url()));
  page.on('pageerror', error=>result.errors.push(error.message));
  await page.goto(base, {waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>performance.getEntriesByName('atlas-home-visible').length>0);
  result.home_seconds = await page.evaluate(()=>performance.getEntriesByName('atlas-home-visible')[0].startTime/1000);
  assert.ok(await page.locator('#atlas-shell').isVisible());
  assert.equal(await page.locator('#root').getAttribute('aria-hidden'), 'true');
  await page.waitForFunction(()=>{const im=document.querySelector('#about img');return im.complete&&im.naturalWidth>0;});
  result.cover_seconds = await page.evaluate(()=>performance.now()/1000);
  await page.screenshot({path:path.join(out,'home.png')});
  await page.locator('.atlas-header a[href="#downloads"]').click();
  const scroll = await page.evaluate(()=>scrollY);
  let frame = await ready(page);
  result.interactive_seconds = await page.evaluate(()=>performance.getEntriesByName('atlas-interactive-ready')[0].startTime/1000);
  result.scroll = {before:scroll, after:await page.evaluate(()=>scrollY)};
  assert.ok(await page.locator('#atlas-shell').isVisible(), 'Readiness must not replace the page while reading');
  assert.ok(Math.abs(await page.evaluate(()=>scrollY)-scroll)<3, 'Reading position changed');
  assert.equal(requests.filter(url=>url.includes('/data/voe/')).length, 0, 'VoE must wait for its tab');
  result.voe_not_loaded_on_home = true;
  result.reading_position_preserved = true;
  result.package_requests = [...new Set(requests.filter(url=>url.endsWith('.tgz')))];
  assert.ok(!result.package_requests.some(url=>url.includes('/ggpubr/')||url.includes('/rstatix/')||url.includes('/lme4/')));
  report();
  console.log('First paint', result.home_seconds, 'cover', result.cover_seconds, 'interactive', result.interactive_seconds);

  await page.setViewportSize({width:390,height:844});
  await page.locator('.atlas-brand').click();
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth), 'Mobile homepage overflows');
  await page.screenshot({path:path.join(out,'mobile.png')});
  result.mobile_no_overflow = true;
  await page.setViewportSize({width:1440,height:1000});
  await page.locator('.atlas-header [data-atlas-tab="Vibration of effects"]').click();
  await frame.waitForFunction(()=>{const im=document.querySelector('#voe_scatter img');return im?.complete&&im.naturalWidth>0;},null,{timeout:60000});
  assert.equal(requests.filter(url=>url.includes('/data/voe/')).length, 1);
  await frame.locator('.navbar-nav a[data-value="About"]').click();
  await page.locator('#atlas-shell').waitFor({state:'visible'});
  assert.ok(await page.locator('#atlas-open').isVisible());
  result.return_to_home = true;

  // An early choice is retained and opens once R is ready, without a second session.
  await page.reload({waitUntil:'domcontentloaded'});
  await page.locator('.atlas-header [data-atlas-tab="Browse By Exposure"]').click();
  frame = await ready(page);
  await frame.waitForFunction(()=>document.querySelector('.navbar-nav>li.active>a')?.textContent==='Browse By Exposure');
  assert.ok(await page.locator('#atlas-shell').isHidden());
  assert.equal(await page.locator('#root iframe.app-frame').count(), 1);
  result.early_navigation_preserved = true;
  result.cached_interactive_seconds = await page.evaluate(()=>performance.getEntriesByName('atlas-interactive-ready')[0].startTime/1000);
  await context.close();

  // A failed startup leaves the real study page and downloads, with a manual retry.
  context = await browser.newContext();
  await context.route('**/app.json?*', route=>route.fulfill({status:503,body:'Unavailable'}));
  page = await context.newPage();
  await page.goto(base,{waitUntil:'domcontentloaded'});
  await page.locator('#atlas-retry').waitFor({state:'visible',timeout:30000});
  assert.match(await page.locator('#atlas-status').innerText(), /could not load/);
  assert.ok(await page.locator('#atlas-shell').isVisible());
  const event = page.waitForEvent('download');
  await page.locator('#downloads a[href="research/data/exposures.csv"]').click();
  const download = await event;
  assert.equal(await download.failure(), null);
  result.failure_keeps_downloads = true;
  await context.close();
  assert.deepEqual(result.errors, []);
  result.passed = true;
  report(); console.log('Progressive loading checks passed');
})().catch(error=>{result.error=error.stack;report();console.error(error.stack);process.exitCode=1;})
  .finally(async()=>{if(browser)await browser.close();});
