const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
process.env.TMPDIR = path.join(root, 'work/tmp');
const { chromium } = require('/Users/chenmo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

(async () => {
  const context = await chromium.launchPersistentContext(path.join(root, 'work/browser'), {
    executablePath: '/Users/chenmo/Library/Caches/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-mac-arm64/chrome-headless-shell',
    headless: true, viewport: { width: 1440, height: 1000 },
    acceptDownloads: true, downloadsPath: path.join(root, 'checks/downloads'),
    args: ['--disable-crash-reporter'],
  });
  const page = context.pages()[0] || await context.newPage();
  const events = [];
  page.on('console', msg => events.push({ type: msg.type(), text: msg.text() }));
  page.on('pageerror', error => events.push({ type: 'pageerror', text: error.message }));
  page.on('requestfailed', request => events.push({ type: 'requestfailed', url: request.url(), error: request.failure() }));
  page.on('response', response => { if (response.status() >= 400) events.push({type:'http',status:response.status(),url:response.url()}); });
  await page.goto('http://127.0.0.1:8848/knhanes_atlas/', { waitUntil: 'domcontentloaded' });
  let ready = false;
  for (let count = 0; count < 90; count++) {
    await page.waitForTimeout(2000);
    for (const frame of page.frames()) {
      if (await frame.locator('#pvarname').count()) ready = true;
    }
    if (ready) break;
    if (count % 5 === 0) console.log('Loading browser R:', count * 2, 'seconds');
  }
  const frames = [];
  for (const frame of page.frames()) {
    frames.push({ url: frame.url(), text: (await frame.locator('body').innerText().catch(() => '')).slice(0, 12000) });
  }
  await page.screenshot({ path: path.join(root, 'checks/initial.png'), fullPage: true });
  fs.writeFileSync(path.join(root,'checks/browser-initial.json'), JSON.stringify({ready,frames,events}, null, 2));
  console.log(JSON.stringify({ready,frames:frames.map(f=>({url:f.url,text:f.text.slice(-1800)})),events:events.slice(-12)},null,2));
  await context.close();
  if (!ready) process.exitCode = 1;
})();
