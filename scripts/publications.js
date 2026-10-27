(() => {
  const main = document.getElementById('publication');
  const title = document.getElementById('item-title');
  const actions = document.getElementById('item-actions');
  const preview = document.getElementById('item-preview');
  const legend = document.getElementById('item-legend');
  const status = document.getElementById('load-status');
  const controls = document.getElementById('table-controls');
  const search = document.getElementById('table-search');
  const pageSize = document.getElementById('page-size');
  let catalog, request, activeId, sections = [], pageNumbers = [];
  let cachedId, cachedTable, searchTimer;
  if (new URLSearchParams(location.search).get('embedded') === '1') document.body.classList.add('embedded');

  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (className) node.className = className;
    return node;
  }
  function versioned(file, hash) { return `${file}?v=${hash.slice(0, 16)}`; }
  function link(text, file, hash, download) {
    const node = element('a', text);
    node.href = versioned(file, hash);
    if (download) node.download = download;
    else { node.target = '_blank'; node.rel = 'noopener'; }
    return node;
  }
  function showError(error) {
    status.textContent = `Could not load this preview. ${error.message}`;
    status.classList.add('load-error');
    const retry = element('button', 'Retry');
    retry.type = 'button';
    retry.addEventListener('click', () => catalog ? showItem() : location.reload());
    preview.replaceChildren(retry);
    main.setAttribute('aria-busy', 'false');
  }
  function renderTables() {
    const query = search.value.trim().toLocaleLowerCase();
    const size = Number(pageSize.value);
    let total = 0;
    const output = document.createDocumentFragment();
    sections.forEach((section, index) => {
      const rows = query ? section.rows.filter((row, i) => section.search[i].includes(query)) : section.rows;
      total += rows.length;
      const pages = Math.max(1, Math.ceil(rows.length / size));
      pageNumbers[index] = Math.min(pageNumbers[index] || 0, pages - 1);
      const start = pageNumbers[index] * size;
      const block = element('section', undefined, 'table-section');
      block.dataset.columns = section.columns.length;
      const heading = section.title || title.textContent;
      if (section.title) block.append(element('h2', section.title));
      const scroll = element('div', undefined, 'table-scroll');
      scroll.tabIndex = 0;
      scroll.setAttribute('role', 'region');
      scroll.setAttribute('aria-label', `${heading} data`);
      const table = element('table');
      table.setAttribute('aria-label', heading);
      const head = element('thead');
      const header = element('tr');
      section.columns.forEach(name => { const cell = element('th', name); cell.scope = 'col'; header.append(cell); });
      head.append(header);
      const body = element('tbody');
      rows.slice(start, start + size).forEach(row => {
        const tr = element('tr');
        row.forEach(value => {
          const numeric = /^[-+−]?(?:\d[\d,]*\.?\d*|\.\d+)(?:[eE][-+]?\d+)?%?$/.test(value);
          tr.append(element('td', value, numeric ? 'numeric' : ''));
        });
        body.append(tr);
      });
      table.append(head, body);
      scroll.append(table);
      block.append(scroll);
      const paging = element('div', undefined, 'pagination');
      paging.append(element('span', rows.length ? `${(start + 1).toLocaleString()}–${Math.min(start + size, rows.length).toLocaleString()} of ${rows.length.toLocaleString()} rows` : 'No matching rows'));
      for (const [label, delta, disabled] of [['Previous', -1, pageNumbers[index] === 0], ['Next', 1, pageNumbers[index] >= pages - 1]]) {
        const button = element('button', label);
        button.type = 'button';
        button.disabled = disabled;
        button.setAttribute('aria-label', `${label} page — ${heading}`);
        button.addEventListener('click', () => {
          pageNumbers[index] += delta;
          renderTables();
          preview.children[index].scrollIntoView({block: 'start'});
        });
        paging.append(button);
      }
      block.append(paging);
      output.append(block);
    });
    preview.replaceChildren(output);
    status.textContent = `${total.toLocaleString()} ${query ? 'matching ' : ''}rows${sections.length > 1 ? ` across ${sections.length} sections` : ''}.`;
  }
  async function showItem() {
    if (!catalog) return;
    request?.abort();
    clearTimeout(searchTimer);
    request = new AbortController();
    const signal = request.signal;
    const items = [...catalog.figures, ...catalog.tables];
    const requested = decodeURIComponent(location.hash.slice(1));
    const item = items.find(entry => entry.id === requested) || items[0];
    const wasViewing = Boolean(activeId);
    activeId = item.id;
    document.querySelectorAll('nav a').forEach(node => {
      if (node.hash === `#${item.id}`) node.setAttribute('aria-current', 'page');
      else node.removeAttribute('aria-current');
    });
    document.title = `${item.label} · KNHANES Atlas`;
    title.textContent = `${item.label}. ${item.title}`;
    main.classList.toggle('table-view', item.kind === 'table');
    main.setAttribute('aria-busy', 'true');
    status.classList.remove('load-error');
    search.value = '';
    pageNumbers = [];
    sections = [];
    controls.hidden = true;
    preview.replaceChildren();
    legend.replaceChildren(...item.legend.map(text => element('p', text)));
    const format = item.source_file.split('.').pop().toUpperCase();
    actions.replaceChildren(link(`Download ${format === 'XLSX' ? 'Excel' : format}`, item.file, item.sha256, item.source_file));
    if (wasViewing) main.scrollIntoView({block: 'start'});
    try {
      if (item.kind === 'figure') {
        actions.append(link('Open full resolution', item.file, item.sha256));
        const full = link('', item.file, item.sha256);
        full.setAttribute('aria-label', `Open ${item.label} at full resolution`);
        const image = element('img', undefined, 'figure-image');
        image.alt = `${item.label}. ${item.title}`;
        image.src = versioned(item.preview, item.preview_sha256);
        image.addEventListener('load', () => { if (activeId === item.id) { status.textContent = ''; main.setAttribute('aria-busy', 'false'); } });
        image.addEventListener('error', () => { if (activeId === item.id) showError(new Error('Image unavailable.')); });
        full.append(image);
        preview.append(full);
        status.textContent = 'Loading figure…';
      } else {
        actions.append(link('Download complete workbook', catalog.workbook.file, catalog.workbook.sha256, 'Supplementary_Tables_KNHANES.xlsx'));
        status.textContent = 'Loading complete table…';
        let data = cachedId === item.id ? cachedTable : null;
        if (!data) {
          const response = await fetch(versioned(item.data, item.data_sha256), {signal});
          if (!response.ok) throw new Error(`Table unavailable (${response.status}).`);
          data = await response.json();
          data.sections.forEach(section => { section.search = section.rows.map(row => row.join(' ').toLocaleLowerCase()); });
          if (signal.aborted) return;
          cachedId = item.id;
          cachedTable = data;
        }
        sections = data.sections;
        controls.hidden = false;
        renderTables();
        main.setAttribute('aria-busy', 'false');
      }
    } catch (error) { if (error.name !== 'AbortError') showError(error); }
  }
  controls.addEventListener('submit', event => event.preventDefault());
  search.addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => { pageNumbers = []; renderTables(); }, 180);
  });
  pageSize.addEventListener('change', () => { pageNumbers = []; renderTables(); });
  window.addEventListener('hashchange', showItem);
  fetch(document.body.dataset.manifest).then(response => {
    if (!response.ok) throw new Error(`Catalog unavailable (${response.status}).`);
    return response.json();
  }).then(data => { catalog = data; showItem(); }).catch(showError);
})();
