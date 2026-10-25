// Keep study files outside the R startup bundle and resolve them on the static site.
(() => {
  function siteRoot() {
    let current = window;
    for (let depth = 0; depth < 5; depth++) {
      if (current.knhanesSiteRoot) return current.knhanesSiteRoot;
      if (current === current.parent) break;
      current = current.parent;
    }
    return null;
  }
  function resolveAssets() {
    const base = siteRoot();
    if (!base) return;
    document.querySelectorAll('[href^="research/"], [data-atlas-src]').forEach(element => {
      for (const attribute of ['href', 'data-atlas-src']) {
        const value = element.getAttribute(attribute);
        if (value?.startsWith('research/')) {
          const target = attribute === 'data-atlas-src' ? 'src' : 'href';
          const resolved = new URL(value, base).href;
          if (element.getAttribute(target) !== resolved) element.setAttribute(target, resolved);
        }
      }
    });
  }
  function connect() {
    const base = siteRoot();
    if (base && typeof window.Shiny?.setInputValue === 'function') {
      window.Shiny.setInputValue('atlas_site_url', base);
      window.Shiny.setInputValue('atlas_url_search', window.parent.location.search);
    }
    resolveAssets();
  }
  // Fetch generated Shiny files through its browser service worker before saving.
  document.addEventListener('click', async event => {
    const link = event.target.closest('a.shiny-download-link');
    if (!link || link.classList.contains('disabled') || !link.getAttribute('href')) return;
    event.preventDefault();
    if (link.getAttribute('aria-busy') === 'true') return;
    link.setAttribute('aria-busy', 'true');
    let url;
    try {
      const response = await fetch(link.href);
      if (!response.ok) throw new Error(`Download failed (${response.status})`);
      const disposition = response.headers.get('content-disposition') || '';
      const utf8 = disposition.match(/filename\*=UTF-8''([^;]+)/i);
      const plain = disposition.match(/filename="?([^";]+)"?/i);
      const filename = utf8 ? decodeURIComponent(utf8[1]) : (plain?.[1] || 'results.csv');
      url = URL.createObjectURL(await response.blob());
      const save = document.createElement('a');
      save.href = url;
      save.download = filename;
      document.body.append(save);
      save.click();
      save.remove();
    } catch (error) {
      window.Shiny.showNotification(error.message, {type: 'error', duration: null});
    } finally {
      link.removeAttribute('aria-busy');
      if (url) setTimeout(() => URL.revokeObjectURL(url), 1000);
    }
  });
  document.addEventListener('DOMContentLoaded', () => {
    new MutationObserver(resolveAssets).observe(document.body, {childList: true, subtree: true});
    if (window.jQuery) window.jQuery(document).on('shiny:connected', connect);
    connect();
  });
})();
