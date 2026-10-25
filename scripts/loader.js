// Show the study immediately; start one R session behind it after the first paint.
(() => {
  const shell = document.getElementById('atlas-shell');
  const root = document.getElementById('root');
  const status = document.getElementById('atlas-status');
  const open = document.getElementById('atlas-open');
  const retry = document.getElementById('atlas-retry');
  const query = new URLSearchParams(location.search);
  let pending = query.has('group') ? 'Browse by Exposure Group'
    : query.has('exposure') ? 'Browse By Exposure'
    : query.has('phenotype') ? 'Browse By Phenotype' : null;
  let appWindow, ready = false, failed = false;
  let slowTimer;
  let homeScroll = 0;

  function showHome() {
    pending = null;
    shell.hidden = false;
    root.classList.add('atlas-staging');
    root.inert = true;
    root.setAttribute('aria-hidden', 'true');
    window.scrollTo(0, homeScroll);
    status.textContent = ready ? 'Interactive analyses are ready.' : 'Preparing interactive analyses…';
  }

  function openTab(tab) {
    pending = tab;
    if (!ready) {
      if (!failed) status.textContent = `Preparing ${tab} — it will open when ready.`;
      document.getElementById('atlas-loading').scrollIntoView({block: 'nearest'});
      return;
    }
    homeScroll = window.scrollY;
    appWindow.knhanesNavigate(tab);
    root.classList.remove('atlas-staging');
    root.inert = false;
    root.removeAttribute('aria-hidden');
    shell.hidden = true;
    appWindow.focus();
    appWindow.dispatchEvent(new Event('resize'));
    pending = null;
  }

  function fail(message) {
    failed = true;
    ready = false;
    showHome();
    status.textContent = message;
    retry.hidden = false;
    open.hidden = true;
    clearTimeout(slowTimer);
  }

  shell.addEventListener('click', event => {
    const link = event.target.closest('[data-atlas-tab]');
    if (link) {
      event.preventDefault();
      openTab(link.dataset.atlasTab);
    } else if (event.target.closest('a[href="#about"], a[href="#downloads"]')) {
      pending = null;
      if (!failed) status.textContent = ready ? 'Interactive analyses are ready.' : 'Preparing interactive analyses…';
    }
  });
  open.addEventListener('click', () => openTab('About'));
  retry.addEventListener('click', () => location.reload());

  window.addEventListener('message', event => {
    const frame = root.querySelector('iframe.app-frame');
    if (event.origin !== location.origin || event.source !== frame?.contentWindow) return;
    if (event.data?.type === 'knhanes:ready') {
      appWindow = event.source;
      ready = true;
      failed = false;
      clearTimeout(slowTimer);
      performance.mark('atlas-interactive-ready');
      status.textContent = 'Interactive analyses are ready.';
      open.hidden = false;
      retry.hidden = true;
      if (pending) openTab(pending);
    } else if (event.data?.type === 'knhanes:home') {
      showHome();
    } else if (event.data?.type === 'knhanes:disconnected') {
      fail('The interactive session stopped. Reload to start again.');
    }
  });

  new MutationObserver(() => {
    if (!ready && !failed && root.querySelector('.loading-wrapper-error, .error-alert')) {
      fail('Interactive analyses could not load. Reload to try again.');
    }
  }).observe(root, {childList: true, subtree: true});

  async function start() {
    performance.mark('atlas-home-visible');
    if (!('serviceWorker' in navigator) || !('WebAssembly' in window)) {
      fail('Open this site in a current browser to use the interactive analyses.');
      retry.hidden = true;
      return;
    }
    slowTimer = setTimeout(() => {
      if (!ready && !failed) {
        status.textContent = 'Interactive analyses are still loading. The study and downloads are available below.';
        retry.hidden = false;
      }
    }, 120000);
    try {
      // Wait for control without reloading the page or interrupting the reader.
      await navigator.serviceWorker.register('./shinylive-sw.js', {type: 'module', updateViaCache: 'none'});
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => { cleanup(); reject(new Error('Service worker unavailable')); }, 30000);
        function cleanup() {
          clearTimeout(timeout);
          navigator.serviceWorker.removeEventListener('controllerchange', controlled);
        }
        function controlled() {
          if (navigator.serviceWorker.controller) { cleanup(); resolve(); }
        }
        navigator.serviceWorker.addEventListener('controllerchange', controlled);
        controlled();
      });
      const css = document.createElement('link');
      css.rel = 'stylesheet';
      css.href = './shinylive/shinylive.css';
      document.head.append(css);
      const version = document.querySelector('meta[name="atlas-build"]').content;
      const [module, appResponse, metadata, manifest] = await Promise.all([
        import('./shinylive/shinylive.js'),
        fetch(`./app.json?v=${version}`),
        // Refresh the small package index; keep versioned runtime/package files cached.
        fetch('./shinylive/webr/packages/metadata.rds', {cache: 'reload'}),
        fetch(`./build.json?v=${version}`),
      ]);
      if (!appResponse.ok || !metadata.ok || !manifest.ok) throw new Error('Study files unavailable');
      await metadata.arrayBuffer();
      const files = await appResponse.json();
      const assets = ['R.wasm', 'library.data.gz', ...(await manifest.json()).active_package_archives];
      let next = 0, loaded = 0;
      const downloads = new AbortController();
      // Four downloads at a time avoid serial network waits and limit memory use.
      try {
        await Promise.all(Array.from({length:4}, async () => {
          while (next < assets.length) {
            const asset = assets[next++];
            const response = await fetch(`./shinylive/webr/${asset}`, {signal:downloads.signal});
            if (!response.ok) throw new Error('Analysis file unavailable');
            const reader = response.body.getReader();
            while (!(await reader.read()).done) { /* Drain into the browser cache. */ }
            loaded++;
            if (!pending) status.textContent = `Loading analysis files (${loaded}/${assets.length})…`;
          }
        }));
      } catch (error) {
        downloads.abort();
        throw error;
      }
      performance.mark('atlas-assets-ready');
      status.textContent = pending ? `Preparing ${pending} — it will open when ready.` : 'Starting interactive analyses…';
      module.runApp(root, 'viewer', {startFiles: files}, 'r');
    } catch (error) {
      console.error('Atlas startup:', error);
      fail('Interactive analyses could not load. Check your connection and reload.');
    }
  }
  requestAnimationFrame(() => requestAnimationFrame(start));
})();
