// check-site.js -- check the built documentation site (specs/phase-10-documentation-
// and-editor.md step 10.6, AC-6): every link and anchor between its pages
// resolves, and every page the site must have is there. Node, no dependencies.
//
//   node tools/check-site.js <built site> <docs folder> [site URL]
//
// The site URL (default https://treytomes.github.io/cog-lisp) is where the site is
// published: links to it, and to its base path (/cog-lisp), are links within the
// site. PASS/FAIL + RESULT convention; exits 1 on any failure.
'use strict';
const fs = require('fs');
const path = require('path');

const [site, docs, siteUrl = 'https://treytomes.github.io/cog-lisp'] = process.argv.slice(2);
if (!site || !docs) {
  console.log('usage: node tools/check-site.js <built site> <docs folder> [site URL]');
  process.exit(2);
}
const base = new URL(siteUrl).pathname.replace(/\/$/, '');   // /cog-lisp

let pass = 0;
let total = 0;
function check(label, ok, detail) {
  total++;
  if (ok) pass++;
  console.log((ok ? '  PASS  ' : '  FAIL  ') + label + (ok || !detail ? '' : ': ' + detail));
}

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);
}
const rel = (file) => path.relative(site, file).split(path.sep).join('/');
const pages = walk(site).filter((f) => f.endsWith('.html')).map(rel).sort();
const text = Object.fromEntries(pages.map((p) => [p, fs.readFileSync(path.join(site, p), 'utf8')]));
const ids = Object.fromEntries(pages.map((p) =>
  [p, new Set([...text[p].matchAll(/\s(?:id|name)="([^"]*)"/g)].map((m) => m[1]))]));

// a link within the site, as the page it reaches (relative to the site) and its
// fragment; null for a link to elsewhere
function target(page, href) {
  let h = href.replace(/&amp;/g, '&');
  if (h.startsWith(siteUrl)) h = base + h.slice(siteUrl.length);
  if (/^[a-z][a-z0-9+.-]*:/i.test(h) || h.startsWith('//')) return null;
  const [beforeHash, fragment = null] = h.split('#');
  const p = beforeHash.split('?')[0];
  let file;
  if (p === '') file = page;
  else if (p.startsWith('/')) {
    if (p !== base && !p.startsWith(base + '/')) return { file: p, fragment, outside: true };
    file = p.slice(base.length + 1);
  } else file = path.posix.normalize(path.posix.join(path.posix.dirname(page), p));
  if (file === '' || file.endsWith('/')) file += 'index.html';
  else if (!path.posix.extname(file) && fs.existsSync(path.join(site, file)) &&
           fs.statSync(path.join(site, file)).isDirectory()) file += '/index.html';
  return { file, fragment };
}

console.log('== the cog-lisp site: ' + site + ' ==');

// the pages it must have: the home page, the manual and each chapter, the reference
const chapters = fs.readdirSync(path.join(docs, 'manual')).filter((f) => /^\d\d-.*\.md$/.test(f)).sort();
const required = ['index.html', 'manual/index.html', 'builtins.html', ...chapters.map((c) => 'manual/' + c.replace(/\.md$/, '.html'))];
const missing = required.filter((p) => !text[p]);
check('the home page, the manual, its ' + chapters.length + ' chapters and the reference are built', chapters.length > 0 && missing.length === 0, missing.join(', '));
check('no page of the manual sources is published (chapters.lisp, introduction)',
  !fs.existsSync(path.join(site, 'manual', 'chapters.lisp')) && !text['manual/introduction.html']);
check('the agent skill\'s sources (docs/skill/) are not published', !fs.existsSync(path.join(site, 'skill')));

// every link and stylesheet within the site, and every anchor
const broken = [];
let links = 0;
for (const page of pages) {
  const refs = [...text[page].matchAll(/<a\s[^>]*href="([^"]*)"/g), ...text[page].matchAll(/<link\s[^>]*rel="stylesheet"[^>]*href="([^"]*)"/g)]
    .map((m) => m[1]);
  for (const href of refs) {
    const t = target(page, href);
    if (!t) continue;
    links++;
    if (t.outside) broken.push(page + ': ' + href + ' (outside ' + base + ')');
    else if (!fs.existsSync(path.join(site, t.file))) broken.push(page + ': ' + href + ' (no ' + t.file + ')');
    else if (t.fragment && !(ids[t.file] && ids[t.file].has(decodeURIComponent(t.fragment)))) broken.push(page + ': ' + href + ' (no anchor)');
  }
}
check('every link within the site reaches a page, and every anchor is on it (' + links + ' links in ' + pages.length + ' pages)',
  links > 0 && broken.length === 0, broken.slice(0, 20).join('; '));

// every Markdown table became a table: kramdown leaves one it cannot read as a
// paragraph of | text (its |---| row turned into dashes)
const rawTables = pages.filter((p) => /^\s*\|.*\|\s*$/m.test(text[p].replace(/<pre[\s\S]*?<\/pre>/g, '')));
check('every table is rendered as a table, none left as | text', rawTables.length === 0, rawTables.join(', '));
// a section is an h2, or under Libraries (which has none of its own) an h3
const refHtml = text['builtins.html'] || '';
const refSections = [...refHtml.matchAll(/<h[23] /g)].length - (/<h2 id="libraries"/.test(refHtml) ? 1 : 0);
const refTables = [...(text['builtins.html'] || '').matchAll(/<table/g)].length;
check('each of the reference\'s ' + refSections + ' sections has its table (' + refTables + ')', refSections > 0 && refTables === refSections);

// the reference's contents link to each of its sections
const sections = [...(text['builtins.html'] || '').matchAll(/href="#([^"]+)"/g)].length;
check('the reference links to its sections (' + sections + ')', sections >= 10);

// the theme (specs/30-site-theme.md AC-1 to AC-5)
const sheet = 'assets/css/site.css';
const linksSheet = (p) => [...text[p].matchAll(/<link\s[^>]*rel="stylesheet"[^>]*href="([^"]*)"/g)]
  .some((m) => { const t = target(p, m[1]); return t && t.file === sheet; });
const noSheet = pages.filter((p) => !linksSheet(p));
const primer = pages.filter((p) => /href="[^"]*assets\/css\/style\.css/.test(text[p]));
check('every page links the theme\'s ' + sheet + ', and none Primer\'s style.css (AC-1)',
  fs.existsSync(path.join(site, sheet)) && noSheet.length === 0 && primer.length === 0,
  [...noSheet.map((p) => p + ' (no site.css)'), ...primer.map((p) => p + ' (style.css)')].join(', '));

// the sidebar: its links, as the pages they reach, and which one is current
const sidebarOf = (p) => (text[p].match(/<aside class="sidebar"[\s\S]*?<\/aside>/) || [''])[0];
const sidebarLinks = (p) => [...sidebarOf(p).matchAll(/<a\s+href="([^"]*)"([^>]*)>/g)]
  .map((m) => ({ file: (target(p, m[1]) || {}).file, current: /aria-current="page"/.test(m[2]) }));
const navProblems = [];
for (const p of pages) {
  const nav = (text[p].match(/<nav class="site-nav"[\s\S]*?<\/nav>/) || [''])[0];
  const navCount = [...nav.matchAll(/<a\s/g)].length;
  if (navCount !== 4) navProblems.push(p + ' (' + navCount + ' links in the header)');
  const links = sidebarLinks(p);
  const reached = new Set(links.map((l) => l.file));
  const lacking = ['manual/index.html', 'builtins.html', ...chapters.map((c) => 'manual/' + c.replace(/\.md$/, '.html'))]
    .filter((f) => !reached.has(f));
  if (lacking.length) navProblems.push(p + ' (its sidebar lacks ' + lacking.join(', ') + ')');
  const current = links.filter((l) => l.current).map((l) => l.file);
  if (/^manual\/\d\d-/.test(p) && (current.length !== 1 || current[0] !== p))
    navProblems.push(p + ' (marked current: ' + (current.join(', ') || 'none') + ')');
}
check('every page has the header\'s four links and the sidebar of every chapter and the reference; a chapter is marked current (AC-2)',
  navProblems.length === 0, navProblems.slice(0, 10).join('; '));

const foreign = [];
for (const p of pages) {
  const refs = [...text[p].matchAll(/<script\s[^>]*src="([^"]*)"/g), ...text[p].matchAll(/<link\s[^>]*rel="stylesheet"[^>]*href="([^"]*)"/g)];
  for (const m of refs) if (!target(p, m[1])) foreign.push(p + ': ' + m[1]);
}
check('no page loads a script or stylesheet from another site (AC-3)', foreign.length === 0, foreign.slice(0, 10).join('; '));

// WCAG 2's contrast ratio of two #rrggbb colors
function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
const contrast = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
const css = fs.existsSync(path.join(site, sheet)) ? fs.readFileSync(path.join(site, sheet), 'utf8') : '';
const root = (css.match(/:root\s*\{([\s\S]*?)\}/) || ['', ''])[1];
const colors = (prefix) => [...root.matchAll(new RegExp('(--' + prefix + '-[a-z0-9-]+):\\s*(#[0-9a-fA-F]{6})\\s*;', 'g'))].map((m) => [m[1], m[2]]);
const fgs = colors('fg');
const bgs = colors('bg');
const weak = [];
for (const [f, fc] of fgs) for (const [b, bc] of bgs) {
  const r = contrast(fc, bc);
  if (r < 4.5) weak.push(f + ' on ' + b + ' ' + r.toFixed(2) + ':1');
}
check('every foreground color has a contrast of 4.5:1 or more against every background (' + fgs.length + ' on ' + bgs.length + '; AC-4)',
  fgs.length > 0 && bgs.length > 0 && weak.length === 0, weak.join(', '));

const refText = (text['builtins.html'] || '').replace(/<!--[\s\S]*?-->/g, '');
check('the reference shows readers no note for maintainers (AC-5)',
  text['builtins.html'] !== undefined && !refText.includes('generate-docs.lisp'));

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
