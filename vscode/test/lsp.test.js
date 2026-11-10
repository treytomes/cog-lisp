// The language server (specs/phase-10-documentation-and-editor.md step 10.5):
// VS Code's own message layer (vscode-jsonrpc, which vscode-languageclient is
// built on) talks to lib/lsp.lisp, served by the image. Needs a built image;
// run from vscode/ with `node test/lsp.test.js`. PASS/FAIL + RESULT convention.
'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');
const cp = require('child_process');
const { pathToFileURL } = require('url');
const rpc = require('vscode-jsonrpc/node');

const root = path.join(__dirname, '..', '..');
const windows = process.platform === 'win32';
let pass = 0;
let total = 0;
function check(label, ok) {
  total++;
  if (ok) pass++;
  console.log((ok ? '  PASS  ' : '  FAIL  ') + label);
}
const median = (xs) => xs.slice().sort((a, b) => a - b)[Math.floor(xs.length / 2)];

// a workspace of its own: a library, a program that uses it, and a broken file
const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'cog-lisp-lsp-'));
const files = {
  'lib.lisp': '(define (area w h)\n  "(area w h)\nThe area of a w by h rectangle."\n  (* w h))\n\n' +
    '(define-syntax swap!\n  "(swap! a b)\nExchanges a and b."\n  (syntax-rules () ((_ a b) (let ((t a)) (set! a b) (set! b t)))))\n',
  'main.lisp': '(define-syntax twice (syntax-rules () ((_ e) (begin e e))))\n' +
    '(display (area 2 3))\n(twice (display "x"))\n(define (f x) (if))\n; 😀 (string-ref "s" 0)\n(string-ref "s" 0)\n',
  'broken.lisp': '(define ok 1)\n(display "unterminated\n',
  // specs/library-path.md AC-5: a required library's macros are known to diagnostics.
  // (defun broken) is an error only as cl.lisp's macro: as a call it compiles quietly.
  'cl-user.lisp': "(require 'cl)\n(defun square (x) (* x x))\n(defun broken)\n",
  // specs/namespaces.md R-13: a library, a document importing it under a prefix,
  // and one defining a name it imported
  'geo.lisp': '(library geo (export rule))\n(define (rule n)\n  "(rule n)\nA line of n dashes."\n  (make-string n #\\-))\n',
  'uses-geo.lisp': "(require \"geo.lisp\" 'prefix 'g:)\n(display (g:rule 3))\n",
  'clash.lisp': "(require \"geo.lisp\")\n(define (rule x) x)\n",
};
for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(workspace, name), text);
const uri = (name) => pathToFileURL(path.join(workspace, name)).href;
// two URIs of one file may spell ~ or a drive letter differently
const same = (a, b) => decodeURIComponent(a).toLowerCase() === decodeURIComponent(b).toLowerCase();

async function main() {
  console.log('== cog-lisp language server, through vscode-jsonrpc ==');
  if (!fs.existsSync(path.join(root, 'pharo', 'cog-lisp.image'))) {
    console.log('  no built image in pharo/: build it first');
    process.exit(2);
  }
  // on a private copy of the image, as the extension runs it: a VM on the
  // checkout's own image would collide with any other one running there
  const imageCopy = fs.mkdtempSync(path.join(os.tmpdir(), 'cog-lisp-lsp-image-'));
  for (const f of ['cog-lisp.image', 'cog-lisp.changes']) {
    fs.copyFileSync(path.join(root, 'pharo', f), path.join(imageCopy, f));
  }
  const env = Object.assign({}, process.env, { COGLISP_IMAGE: path.join(imageCopy, 'cog-lisp.image') });
  const server = windows
    ? cp.spawn('cmd.exe', ['/d', '/c', '.\\cog-lisp.bat', 'lib\\lsp.lisp'], { cwd: root, env })
    : cp.spawn('./cog-lisp.sh', ['lib/lsp.lisp'], { cwd: root, env });
  // drained, as VS Code's client does: a full stderr pipe would stop the server
  server.stderr.on('data', () => {});
  const connection = rpc.createMessageConnection(
    new rpc.StreamMessageReader(server.stdout), new rpc.StreamMessageWriter(server.stdin));
  const diagnostics = {};
  const waiters = [];
  connection.onNotification('textDocument/publishDiagnostics', (p) => {
    diagnostics[p.uri] = p.diagnostics;
    waiters.splice(0).forEach((w) => w());
  });
  const nextDiagnostics = () => new Promise((r) => waiters.push(r));
  connection.listen();

  let t = Date.now();
  const init = await connection.sendRequest('initialize',
    { processId: process.pid, rootUri: pathToFileURL(workspace).href, workspaceFolders: [{ uri: pathToFileURL(workspace).href, name: 'w' }], capabilities: {} });
  const startup = Date.now() - t;
  const caps = init.capabilities;
  check('initialize offers hover, completion and definition (' + startup + ' ms)',
    caps.hoverProvider === true && !!caps.completionProvider && caps.definitionProvider === true);
  connection.sendNotification('initialized', {});

  const open = async (name) => {
    const seen = nextDiagnostics();
    connection.sendNotification('textDocument/didOpen',
      { textDocument: { uri: uri(name), languageId: 'cog-lisp', version: 1, text: files[name] } });
    await seen;
  };
  t = Date.now();
  await open('main.lisp');
  const diagnoseTime = Date.now() - t;
  await open('broken.lisp');
  await open('cl-user.lisp');
  const at = (name, line, character) => ({ textDocument: { uri: uri(name) }, position: { line, character } });
  const hover = async (name, line, character) => {
    const h = await connection.sendRequest('textDocument/hover', at(name, line, character));
    return h ? h.contents.value : '';
  };

  // hover
  check('hover on a built-in shows its documentation', (await hover('main.lisp', 1, 3)).includes('(display x [port])'));
  const areaHover = await hover('main.lisp', 1, 11);
  check('hover on a definition in the workspace shows its documentation and source',
    areaHover.includes('The area of a w by h rectangle.') && areaHover.includes('(* w h)'));
  check('hover after a character outside the BMP is placed in UTF-16 units',
    (await hover('main.lisp', 5, 3)).includes('(string-ref string k)'));
  check('no hover on white space', (await hover('main.lisp', 1, 0)) === '');

  // completion
  const items = await connection.sendRequest('textDocument/completion', at('main.lisp', 1, 2));
  const labels = new Set(items.map((i) => i.label));
  check('completion offers built-ins, special forms and derived forms',
    labels.has('display') && labels.has('lambda') && labels.has('case'));
  check('completion offers the names the workspace defines', labels.has('area') && labels.has('swap!'));
  check('a built-in completion carries its call form', items.find((i) => i.label === 'string-ref').detail === '(string-ref string k)');

  // definition
  const defs = await connection.sendRequest('textDocument/definition', at('main.lisp', 1, 11));
  check('go to definition finds area in lib.lisp, at its define',
    defs.length === 1 && same(defs[0].uri, uri('lib.lisp')) && defs[0].range.start.line === 0);

  // diagnostics
  const mainDiags = diagnostics[uri('main.lisp')] || [];
  check('a compile error is reported once, at its innermost form (C-18)',
    mainDiags.length === 1 && mainDiags[0].message.includes('if: bad syntax') &&
    mainDiags[0].range.start.line === 3 && mainDiags[0].range.start.character === 14);
  check("the document's own macro (twice) is known: no error at its use",
    !mainDiags.some((d) => d.range.start.line === 2));
  const brokenDiags = diagnostics[uri('broken.lisp')] || [];
  // errors only: (defun square ...) also redefines the built-in square, a warning (specs/namespaces.md R-10)
  const clDiags = (diagnostics[uri('cl-user.lisp')] || []).filter((d) => d.severity === 1);
  check("a document's (require 'cl) is run, so its defun is a macro: only the misused one is reported (library-path AC-5)",
    clDiags.length === 1 && clDiags[0].range.start.line === 2 && clDiags[0].message.includes('defun'));
  check('a read error is reported where reading stopped', brokenDiags.length === 1 && brokenDiags[0].message.includes('string'));
  let seen = nextDiagnostics();
  connection.sendNotification('textDocument/didChange',
    { textDocument: { uri: uri('main.lisp'), version: 2 }, contentChanges: [{ text: '(display 1)\n' }] });
  await seen;
  check('a fixed document has no diagnostics', (diagnostics[uri('main.lisp')] || ['x']).length === 0);

  // macro expansion
  connection.sendNotification('textDocument/didChange',
    { textDocument: { uri: uri('main.lisp'), version: 3 }, contentChanges: [{ text: files['lib.lisp'] + '(define (g p q) (when p (swap! p q)))\n' }] });
  const ex = await connection.sendRequest('cog-lisp/expand', at('main.lisp', 9, 27));
  check('expand the innermost macro call at the cursor',
    ex && ex.form === '(swap! p q)' && ex.expansion.startsWith('(let ((t p))'));
  const ex2 = await connection.sendRequest('cog-lisp/expand', at('main.lisp', 9, 18));
  check('... or the enclosing one', ex2 && ex2.form.startsWith('(when p') && ex2.expansion.startsWith('(if p'));

  // formatting (specs/formatter.md R-4, AC-4)
  check('initialize offers formatting', caps.documentFormattingProvider === true);
  const openText = async (name, text) => {
    const seen = nextDiagnostics();
    connection.sendNotification('textDocument/didOpen', { textDocument: { uri: uri(name), languageId: 'cog-lisp', version: 1, text } });
    await seen;
  };
  await openText('fmt.lisp', '(define (f x) (* x x))\n');
  const format = (name, options) => connection.sendRequest('textDocument/formatting', { textDocument: { uri: uri(name) }, options });
  const tabbed = await format('fmt.lisp', { tabSize: 4, insertSpaces: false });
  check('formatting answers one edit over the whole document, with tabs',
    tabbed.length === 1 && tabbed[0].newText === '(define (f x)\n\t(* x x)\n)\n' &&
    tabbed[0].range.start.line === 0 && tabbed[0].range.start.character === 0 && tabbed[0].range.end.line === 1);
  const spaced = await format('fmt.lisp', { tabSize: 2, insertSpaces: true });
  check('... or with the spaces the request asks for', spaced.length === 1 && spaced[0].newText === '(define (f x)\n  (* x x)\n)\n');
  await openText('fmt-done.lisp', '(define (f x)\n\t(* x x)\n)\n');
  check('a document already formatted gets no edit', (await format('fmt-done.lisp', { tabSize: 4, insertSpaces: false })).length === 0);
  await openText('fmt-broken.lisp', '(define (f x)\n');
  let refused = null;
  try { await format('fmt-broken.lisp', { tabSize: 4, insertSpaces: false }); } catch (e) { refused = e.message; }
  check('a document that does not read is an error, naming the line', !!refused && refused.includes('never closed (line 1)'));

  // namespaces (specs/namespaces.md R-13, AC-4): through the document's imports
  await openText('uses-geo.lisp', files['uses-geo.lisp']);
  const geoHover = await connection.sendRequest('textDocument/hover', at('uses-geo.lisp', 1, 11));
  check("hover through a prefix shows the library's documentation",
    !!geoHover && JSON.stringify(geoHover.contents).includes('A line of n dashes'));
  const geoDefs = await connection.sendRequest('textDocument/definition', at('uses-geo.lisp', 1, 11));
  check("go to definition through a prefix finds the library's file",
    Array.isArray(geoDefs) && geoDefs.length === 1 && same(geoDefs[0].uri, uri('geo.lisp')));
  const geoItems = await connection.sendRequest('textDocument/completion', at('uses-geo.lisp', 1, 10));
  check('completion offers the names the document imported, under their prefix',
    geoItems.some((i) => i.label === 'g:rule'));
  await openText('clash.lisp', files['clash.lisp']);
  const clash = diagnostics[uri('clash.lisp')] || [];
  check('defining a name the document imported is a diagnostic (R-8)',
    clash.length === 1 && clash[0].message.includes('rule is imported (as geo:rule)'));
  await openText('redefines.lisp', '(define (http-request . args) args)\n');
  const redefines = diagnostics[uri('redefines.lisp')] || [];
  check('redefining a built-in is a warning in the editor, on its form (R-10)',
    redefines.length === 1 && redefines[0].severity === 2 && redefines[0].message.includes('replaces the built-in http-request'));

  // speed, on a file the size of the compiler
  const big = fs.readFileSync(path.join(root, 'lib', 'compiler', 'compiler.lisp'), 'utf8');
  seen = nextDiagnostics();
  t = Date.now();
  connection.sendNotification('textDocument/didChange', { textDocument: { uri: uri('main.lisp'), version: 4 }, contentChanges: [{ text: big }] });
  await seen;
  const bigDiagnose = Date.now() - t;
  const hoverTimes = [];
  const completionTimes = [];
  for (let i = 0; i < 15; i++) {
    t = Date.now(); await connection.sendRequest('textDocument/hover', at('main.lisp', 40, 3)); hoverTimes.push(Date.now() - t);
    t = Date.now(); await connection.sendRequest('textDocument/completion', at('main.lisp', 40, 3)); completionTimes.push(Date.now() - t);
  }
  console.log('  times: start-up ' + startup + ' ms; diagnostics ' + diagnoseTime + ' ms on a small file, ' + bigDiagnose +
    ' ms on compiler.lisp (' + big.split('\n').length + ' lines); hover median ' + median(hoverTimes) +
    ' ms; completion median ' + median(completionTimes) + ' ms');
  check('diagnostics on the compiler source within 5 s', bigDiagnose < 5000);
  check('hover and completion answer quickly (medians under 300 ms)', median(hoverTimes) < 300 && median(completionTimes) < 300);

  await connection.sendRequest('shutdown');
  const exited = new Promise((resolve) => server.on('exit', (code) => resolve(code)));
  connection.sendNotification('exit');
  const code = await Promise.race([exited, new Promise((r) => setTimeout(() => r('hung'), 20000))]);
  check('exit ends the server (' + code + ')', code === 0);
  connection.dispose();
  for (let i = 0; i < 10 && fs.existsSync(imageCopy); i++) {
    try { fs.rmSync(imageCopy, { recursive: true, force: true }); } catch (e) { await new Promise((r) => setTimeout(r, 200)); }
  }

  console.log('');
  console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
  process.exit(pass === total ? 0 : 1);
}

main().catch((e) => { console.log('  FAIL  ' + e.message); console.log('== RESULT: ' + pass + '/' + (total + 1) + ' checks passed =='); process.exit(1); });
