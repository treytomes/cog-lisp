// site.js -- the cog-lisp site's script (specs/30-site-theme.md R-3, R-6): a link
// from each heading to itself, the sidebar's "on this page", and the reference's
// filter. Nothing is fetched; without it every page still reads in full.
'use strict';

document.addEventListener('DOMContentLoaded', () => {
  const content = document.getElementById('content');
  if (!content) return;
  const reference = document.body.classList.contains('page-reference');

  // on this page: the sections of a chapter or of the reference (whose
  // libraries are h3s under its Libraries)
  const sections = [...content.querySelectorAll(reference ? 'h2[id], h3[id]' : 'h2[id]')];
  const toc = document.querySelector('.on-this-page');
  if (toc && sections.length > 1 && !document.body.classList.contains('page-home')) {
    const label = document.createElement('p');
    label.textContent = 'On this page';
    const list = document.createElement('ul');
    for (const h of sections) {
      const li = document.createElement('li');
      if (h.tagName === 'H3') li.className = 'sub';
      const a = document.createElement('a');
      a.href = '#' + h.id;
      a.textContent = h.textContent.trim();
      li.appendChild(a);
      list.appendChild(li);
    }
    toc.append(label, list);
    toc.hidden = false;
  }

  // a link from each heading to itself (what anchor-js did)
  for (const h of content.querySelectorAll('h1[id], h2[id], h3[id], h4[id]')) {
    const a = document.createElement('a');
    a.className = 'anchor';
    a.href = '#' + h.id;
    a.setAttribute('aria-label', 'Link to this section');
    a.textContent = '#';
    h.appendChild(a);
  }

  if (reference) buildFilter(content);
});

// The reference's filter: rows whose name does not hold the text are hidden, and
// so is a section left with none. Each section is a heading and what follows it,
// up to the next heading.
function buildFilter(content) {
  const firstSection = content.querySelector('h2');
  if (!firstSection) return;

  const groups = [];
  let group = null;
  for (const el of content.children) {
    if (/^H[23]$/.test(el.tagName)) {
      group = { heading: el, level: el.tagName, elements: [el], rows: [] };
      groups.push(group);
    } else if (group) {
      group.elements.push(el);
      if (el.tagName === 'TABLE') {
        for (const tr of el.querySelectorAll('tbody tr')) {
          const cell = tr.cells[0];
          group.rows.push({ tr, name: (cell ? cell.textContent : '').trim().toLowerCase() });
        }
      }
    }
  }
  const total = groups.reduce((n, g) => n + g.rows.length, 0);

  const box = document.createElement('div');
  box.className = 'filter';
  box.setAttribute('role', 'search');
  box.innerHTML =
    '<label for="filter-names">&gt;</label>' +
    '<input id="filter-names" type="search" autocomplete="off" spellcheck="false" ' +
    'placeholder="filter the names (press / to start, Escape to clear)">' +
    '<output for="filter-names" aria-live="polite"></output>';
  content.insertBefore(box, firstSection);
  const input = box.querySelector('input');
  const count = box.querySelector('output');
  count.textContent = total + ' names';

  const apply = () => {
    const q = input.value.trim().toLowerCase();
    let shown = 0;
    // a section with a table, then an h2 with none (Libraries), which stays while
    // any of the h3s after it does
    let parent = null;
    let parentShown = false;
    const finishParent = () => {
      if (parent) for (const el of parent.elements) toggle(el, q !== '' && !parentShown);
    };
    for (const g of groups) {
      if (g.level === 'H2' && g.rows.length === 0) {
        finishParent();
        parent = g;
        parentShown = false;
        continue;
      }
      if (g.level === 'H2') { finishParent(); parent = null; }
      let n = 0;
      for (const r of g.rows) {
        const match = q === '' || r.name.includes(q);
        toggle(r.tr, !match);
        if (match) n++;
      }
      shown += n;
      for (const el of g.elements) toggle(el, q !== '' && n === 0);
      if (n > 0) parentShown = true;
    }
    finishParent();
    // the contents list says nothing while filtering
    const contents = content.querySelector(':scope > ul');
    if (contents) toggle(contents, q !== '');
    count.textContent = q === '' ? total + ' names' : shown + ' of ' + total + ' names';
  };
  input.addEventListener('input', apply);
  // a filter from the address (builtins.html?q=string), so a filtered view can be
  // shared
  const initial = new URLSearchParams(location.search).get('q');
  if (initial) { input.value = initial; apply(); }

  document.addEventListener('keydown', (e) => {
    const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
    if (e.key === '/' && !typing && !e.ctrlKey && !e.metaKey && !e.altKey) {
      e.preventDefault();
      input.focus();
      input.select();
    } else if (e.key === 'Escape' && document.activeElement === input) {
      input.value = '';
      apply();
    }
  });
}

function toggle(el, hide) {
  if (hide) el.setAttribute('data-filtered-out', '');
  else el.removeAttribute('data-filtered-out');
}
