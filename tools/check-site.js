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

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
