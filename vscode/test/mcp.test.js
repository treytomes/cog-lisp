// The MCP server (specs/35-mcp-server.md): the real server, started through its
// launcher (mcp-server.bat / mcp-server.sh) as every host starts it, driven in
// both eras over newline-delimited JSON. Also compares the tool table with the
// language server's capabilities (AC-3). Needs a built image; run from vscode/
// with `node test/mcp.test.js`. PASS/FAIL + RESULT convention.
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

// a workspace: a library, a program that uses it, a broken file, a messy one,
// and one that draws a compiler warning (a built-in redefined)
const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'cog-lisp-mcptest-ws-'));
const files = {
  'shapes.lisp': '(define (area w h)\n  "(area w h)\nThe area of a w by h rectangle."\n  (* w h))\n',
  'main.lisp': '(define-syntax twice (syntax-rules () ((_ e) (begin e e))))\n(display (area 2 3))\n(twice (display "x"))\n',
  'broken.lisp': '(define ok 1)\n(display "unterminated\n',
  'messy.lisp': '(define (f x)\n(* x x))\n',
  'warns.lisp': '(define (car x) x)\n(display (car 1))\n',
};
for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(workspace, name), text);
const file = (name) => path.join(workspace, name);

// the copies the launchers make, in the temporary folder they use
const tmpBase = windows ? (process.env.TEMP || os.tmpdir()) : (process.env.TMPDIR || '/tmp');
const copies = () => fs.readdirSync(tmpBase).filter((n) => n.startsWith('cog-lisp-mcp-image-'));

/** Starts the server through its launcher, with folder (or none). */
function start(folder) {
  const args = folder ? [folder] : [];
  const child = windows
    ? cp.spawn('cmd.exe', ['/d', '/c', '.\\mcp-server.bat', ...args], { cwd: root })
    : cp.spawn('./mcp-server.sh', args, { cwd: root });
  const server = { child, lines: [], stderr: '', waiting: new Map(), exited: null };
  let buffer = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => {
    buffer += chunk;
    let i;
    while ((i = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, i);
      buffer = buffer.slice(i + 1);
      server.lines.push(line);
      let message = null;
      try { message = JSON.parse(line); } catch (e) { /* counted by AC-9 */ }
      if (message && message.id !== undefined && server.waiting.has(message.id)) {
        server.waiting.get(message.id)(message);
        server.waiting.delete(message.id);
      }
    }
  });
  child.stderr.on('data', (d) => { server.stderr += d; });
  server.done = new Promise((resolve) => child.on('exit', (code) => { server.exited = code; resolve(code); }));
  return server;
}

let nextId = 1;
function send(server, method, params, id = nextId++) {
  const message = { jsonrpc: '2.0', id, method };
  if (params !== undefined) message.params = params;
  server.child.stdin.write(JSON.stringify(message) + '\n');
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('no answer to ' + method)), 60000);
    server.waiting.set(id, (m) => { clearTimeout(timer); resolve(m); });
  });
}
const notify = (server, method, params) =>
  server.child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');
const raw = (server, line, id) => {
  server.child.stdin.write(line + '\n');
  return new Promise((resolve) => server.waiting.set(id, resolve));
};

const meta = { 'io.modelcontextprotocol/protocolVersion': '2026-07-28', 'io.modelcontextprotocol/clientCapabilities': {} };
const call = (server, name, args, modern) =>
  send(server, 'tools/call', Object.assign({ name, arguments: args }, modern ? { _meta: meta } : {}));
const textOf = (answer) => answer.result && answer.result.content && answer.result.content[0].text;
const jsonOf = (answer) => JSON.parse(textOf(answer));

// is a file free for the build to replace? On Windows a file another process
// holds open cannot be renamed; elsewhere the build never collides
function free(f) {
  if (!windows) return true;
  try { fs.renameSync(f, f + '.probe'); fs.renameSync(f + '.probe', f); return true; } catch (e) { return false; }
}

/** The language server's capabilities and its nonstandard methods (AC-3). */
async function languageServerSurface() {
  const imageCopy = fs.mkdtempSync(path.join(os.tmpdir(), 'cog-lisp-mcp-lsp-'));
  for (const f of ['cog-lisp.image', 'cog-lisp.changes']) fs.copyFileSync(path.join(root, 'pharo', f), path.join(imageCopy, f));
  const env = Object.assign({}, process.env, { COGLISP_IMAGE: path.join(imageCopy, 'cog-lisp.image') });
  const lsp = windows
    ? cp.spawn('cmd.exe', ['/d', '/c', '.\\cog-lisp.bat', 'lib\\lsp.lisp'], { cwd: root, env })
    : cp.spawn('./cog-lisp.sh', ['lib/lsp.lisp'], { cwd: root, env });
  lsp.stderr.on('data', () => {});
  const connection = rpc.createMessageConnection(new rpc.StreamMessageReader(lsp.stdout), new rpc.StreamMessageWriter(lsp.stdin));
  connection.listen();
  const init = await connection.sendRequest('initialize', { processId: process.pid, rootUri: pathToFileURL(workspace).href, capabilities: {} });
  await connection.sendRequest('shutdown');
  connection.sendNotification('exit');
  await new Promise((r) => lsp.on('exit', r));
  connection.dispose();
  fs.rmSync(imageCopy, { recursive: true, force: true });
  // the methods lsp.lisp dispatches on, less the protocol's own
  const source = fs.readFileSync(path.join(root, 'lib', 'lsp.lisp'), 'utf8');
  const methods = [...source.matchAll(/\(string=\? method "([^"]+)"\)/g)].map((m) => m[1])
    .filter((m) => !/^(initialize|initialized|shutdown|exit|textDocument\/.*)$/.test(m));
  return { capabilities: Object.keys(init.capabilities), methods };
}

// what each of the language server's capabilities and methods is as a tool (R-7)
const TOOL_FOR = {
  textDocumentSync: 'lisp_check',
  hoverProvider: 'lisp_hover',
  definitionProvider: 'lisp_definition',
  completionProvider: 'lisp_completion',
  documentFormattingProvider: 'lisp_format',
  'cog-lisp/expand': 'lisp_expand_macro',
};

async function main() {
  console.log('== cog-lisp MCP server, through ' + (windows ? 'mcp-server.bat' : 'mcp-server.sh') + ' ==');
  if (!fs.existsSync(path.join(root, 'pharo', 'cog-lisp.image'))) {
    console.log('  no built image in pharo/: build it first');
    process.exit(2);
  }
  // AC-11: a copy a killed server left behind goes at the next start
  // (its launcher has gone: owner.pid names a process that has ended), and a
  // folder of that name the launcher did not make is left alone
  const ended = cp.spawnSync(process.execPath, ['-e', '0']).pid;
  const leftover = path.join(tmpBase, 'cog-lisp-mcp-image-leftover-test');
  fs.mkdirSync(leftover, { recursive: true });
  for (const [f, text] of [['cog-lisp.image', 'stale'], ['cog-lisp-mcp.copy', ''], ['owner.pid', String(ended)]]) {
    fs.writeFileSync(path.join(leftover, f), text);
  }
  const notOurs = path.join(tmpBase, 'cog-lisp-mcp-image-not-ours-test');
  fs.mkdirSync(notOurs, { recursive: true });
  fs.writeFileSync(path.join(notOurs, 'keep.txt'), 'mine');
  const changes = path.join(root, 'pharo', 'cog-lisp.changes');
  // the image's version, as a program run on it reads it (R-18)
  const versionProgram = path.join(workspace, 'version.lisp');
  fs.writeFileSync(versionProgram, "(display (hash-table-ref/default *env* 'version \"dev\"))\n");
  const version = (windows
    ? cp.spawnSync('cmd.exe', ['/d', '/c', '.\\cog-lisp.bat', versionProgram], { cwd: root, encoding: 'utf8', input: '' })
    : cp.spawnSync('./cog-lisp.sh', [versionProgram], { cwd: root, encoding: 'utf8', input: '' })).stdout.trim();
  fs.rmSync(versionProgram);
  const freeBefore = free(changes);

  const t = Date.now();
  const s = start(workspace);

  // --- legacy (AC-1) ---------------------------------------------------------
  const init = await send(s, 'initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'mcp.test', version: '1' } });
  console.log('    initialize answered in ' + (Date.now() - t) + ' ms');
  check('initialize: protocol version, tools capability, serverInfo with the image\'s version (' + (init.result && init.result.serverInfo.version) + ')',
    !!init.result && init.result.protocolVersion === '2025-11-25' && !!init.result.capabilities.tools &&
    init.result.serverInfo.name === 'cog-lisp' && init.result.serverInfo.version === version &&
    typeof init.result.instructions === 'string' && !('resultType' in init.result));
  notify(s, 'notifications/initialized');
  check('ping answers {}', JSON.stringify((await send(s, 'ping')).result) === '{}');

  // AC-11: while the server runs, the checkout's changes file is free for the build
  check('the checkout\'s pharo/cog-lisp.changes is not held while the server runs' + (freeBefore ? '' : ' (held before it started: not checked)'),
    !freeBefore || free(changes));
  check('the copy a killed server left behind is removed at the next start', !fs.existsSync(leftover));
  check('a folder of that name the launcher did not make is left alone', fs.existsSync(path.join(notOurs, 'keep.txt')));
  fs.rmSync(notOurs, { recursive: true, force: true });
  check('the server runs on a copy in the temporary folder', copies().length >= 1);

  // --- the catalog (AC-3, AC-4) ------------------------------------------------
  const list = (await send(s, 'tools/list')).result;
  const names = list.tools.map((x) => x.name);
  check('tools/list: the six tools', JSON.stringify(names) ===
    JSON.stringify(['lisp_check', 'lisp_hover', 'lisp_definition', 'lisp_completion', 'lisp_expand_macro', 'lisp_format']));
  check('each tool has a title, a description, an object inputSchema closed to other properties, and read-only annotations',
    list.tools.every((x) => x.title && x.description && x.inputSchema.type === 'object' &&
      x.inputSchema.additionalProperties === false && x.annotations.readOnlyHint === true && x.annotations.openWorldHint === false));
  check('no tool runs source (R-14)', !names.some((n) => /eval|run|load/.test(n)));
  const surface = await languageServerSurface();
  const mapped = [...surface.capabilities, ...surface.methods].map((c) => TOOL_FOR[c]);
  console.log('    the language server: ' + surface.capabilities.join(', ') + '; ' + surface.methods.join(', '));
  check('every capability and method of the language server is one tool (AC-3)', mapped.every((x) => x && names.includes(x)));
  check('every tool is one of the language server\'s capabilities or methods (AC-3)',
    names.every((n) => mapped.includes(n)) && mapped.length === names.length);

  // --- every tool (AC-5) --------------------------------------------------------
  const check1 = await call(s, 'lisp_check', { path: file('broken.lisp') });
  if (!check1.result || !check1.result.structuredContent) console.log('    ' + JSON.stringify(check1) + ' ' + s.stderr);
  const problems = check1.result.structuredContent.problems;
  check('lisp_check finds the unterminated string, at its line',
    problems.length === 1 && problems[0].message === 'unterminated string' && problems[0].line === 2);
  check('lisp_check: the text is the structured content as JSON', JSON.stringify(jsonOf(check1)) === JSON.stringify(check1.result.structuredContent));
  check('lisp_check: the structured content matches the output schema',
    !!list.tools[0].outputSchema && problems.every((p) => list.tools[0].outputSchema.properties.problems.items.required.every((k) => k in p)));
  const def = jsonOf(await call(s, 'lisp_definition', { path: file('main.lisp'), line: 2, column: 11 })).definitions;
  check('lisp_definition on a call into the library gives its path and line',
    def.length === 1 && path.resolve(def[0].path).toLowerCase() === path.resolve(file('shapes.lisp')).toLowerCase() && def[0].line === 1);
  check('lisp_hover gives the procedure\'s documentation',
    (textOf(await call(s, 'lisp_hover', { path: file('main.lisp'), line: 2, column: 11 })) || '').includes('The area of a w by h rectangle.'));
  check('lisp_hover gives a built-in\'s documentation',
    (textOf(await call(s, 'lisp_hover', { path: file('main.lisp'), line: 2, column: 3 })) || '').includes('(display x [port])'));
  const completions = jsonOf(await call(s, 'lisp_completion', { prefix: 'string-', limit: 5 }));
  check('lisp_completion completes a prefix, at most limit names, and says how many more',
    completions.completions.length === 5 && completions.more > 0 && completions.completions.every((c) => c.label.startsWith('string-')));
  const expanded = jsonOf(await call(s, 'lisp_expand_macro', { path: file('main.lisp'), line: 3, column: 2 }));
  check('lisp_expand_macro expands the file\'s macro call', expanded.expansion === '(begin (display "x") (display "x"))');
  check('lisp_format reindents a misindented file',
    textOf(await call(s, 'lisp_format', { path: file('messy.lisp') })) === '(define (f x)\n\t(* x x)\n)\n');

  // --- path, text, both; places (AC-6, AC-7) -------------------------------------
  let same = true;
  for (const [tool, args] of [['lisp_check', {}], ['lisp_hover', { line: 2, column: 11 }], ['lisp_definition', { line: 2, column: 11 }],
    ['lisp_completion', { prefix: 'are' }], ['lisp_expand_macro', { line: 3, column: 2 }], ['lisp_format', {}]]) {
    const a = textOf(await call(s, tool, Object.assign({ path: file('main.lisp') }, args)));
    const b = textOf(await call(s, tool, Object.assign({ path: file('main.lisp'), text: files['main.lisp'] }, args)));
    if (a !== b) { same = false; console.log('    differs: ' + tool); }
  }
  check('every tool answers the same for path, and for path with the same text', same);
  const unsaved = jsonOf(await call(s, 'lisp_check', { path: file('broken.lisp'), text: '(define ok 1)\n' }));
  check('an unsaved change given as text is checked as the text says', unsaved.problems.length === 0);
  check('a following call with path alone sees the file on disk again',
    jsonOf(await call(s, 'lisp_check', { path: file('broken.lisp') })).problems.length === 1);
  const neither = await call(s, 'lisp_check', {});
  check('a tool given neither path nor text says so with isError', neither.result.isError === true);
  const offset = files['main.lisp'].indexOf('area');
  check('a place as line and column and as the same offset answers the same',
    textOf(await call(s, 'lisp_hover', { path: file('main.lisp'), line: 2, column: 11 })) ===
    textOf(await call(s, 'lisp_hover', { path: file('main.lisp'), offset })));
  check('both forms of a place at once is isError',
    (await call(s, 'lisp_hover', { path: file('main.lisp'), line: 2, column: 11, offset })).result.isError === true);
  check('a place outside the text is isError',
    (await call(s, 'lisp_hover', { path: file('main.lisp'), line: 40, column: 1 })).result.isError === true);

  // --- the modern era, in the same process (AC-2) ----------------------------------
  const discover = await send(s, 'server/discover', { _meta: meta });
  const d = discover.result || {};
  check('server/discover: resultType, supportedVersions, tools, instructions, serverInfo, ttlMs 0, cacheScope public',
    d.resultType === 'complete' && JSON.stringify(d.supportedVersions) === '["2026-07-28"]' && !!d.capabilities.tools &&
    typeof d.instructions === 'string' && d._meta['io.modelcontextprotocol/serverInfo'].version === version &&
    d.ttlMs === 0 && d.cacheScope === 'public');
  const modernList = (await send(s, 'tools/list', { _meta: meta })).result || {};
  check('a modern tools/list: the envelope and the hints around the six tools',
    modernList.resultType === 'complete' && modernList.tools.length === 6 && modernList.ttlMs === 0 &&
    modernList.cacheScope === 'public' && !!modernList._meta['io.modelcontextprotocol/serverInfo']);
  const modernCall = await call(s, 'lisp_check', { path: file('broken.lisp') }, true);
  check('a modern tools/call answers the same problems, in the modern envelope',
    modernCall.result.resultType === 'complete' && modernCall.result.structuredContent.problems.length === 1 && !('ttlMs' in modernCall.result));
  const noCaps = await send(s, 'tools/list', { _meta: { 'io.modelcontextprotocol/protocolVersion': '2026-07-28' } });
  check('a modern request without clientCapabilities is -32602', noCaps.error && noCaps.error.code === -32602);
  const old = await send(s, 'tools/list', { _meta: Object.assign({}, meta, { 'io.modelcontextprotocol/protocolVersion': '1900-01-01' }) });
  check('a modern request naming 1900-01-01 is -32022, with both revisions supported and the client\'s requested',
    old.error && old.error.code === -32022 && JSON.stringify(old.error.data.supported) === '["2026-07-28","2025-11-25"]' &&
    old.error.data.requested === '1900-01-01');
  check('the legacy session goes on answering after modern requests', JSON.stringify((await send(s, 'ping')).result) === '{}');

  // --- errors (AC-8) ----------------------------------------------------------------
  for (const [era, modern] of [['legacy', false], ['modern', true]]) {
    const unknownTool = await call(s, 'nope', {}, modern);
    check(era + ': an unknown tool is -32602', unknownTool.error && unknownTool.error.code === -32602);
    const unknownMethod = await send(s, 'resources/list', modern ? { _meta: meta } : {});
    check(era + ': an unknown method is -32601', unknownMethod.error && unknownMethod.error.code === -32601);
  }
  const shutdown = await send(s, 'shutdown');
  check('shutdown is -32601, and the server keeps serving', shutdown.error && shutdown.error.code === -32601);
  const parse = await raw(s, 'this is not JSON', null);
  check('a line that is not JSON is -32700, with a null id', parse.error && parse.error.code === -32700 && parse.id === null);
  check('the next message still gets its answer', JSON.stringify((await send(s, 'ping')).result) === '{}');

  // --- AC-9: nothing but protocol on stdout, a compiler warning included -----------------
  const warned = jsonOf(await call(s, 'lisp_check', { path: file('warns.lisp') }));
  check('a file that draws a compiler warning is checked (' + warned.problems.length + ' problems)', Array.isArray(warned.problems));

  // --- AC-10: the end of input ends it with 0, and the copy goes ---------------------------
  s.child.stdin.end();
  const code = await s.done;
  check('the server exits 0 when its input ends (exit ' + code + ')', code === 0);
  check('every line on stdout was JSON (' + s.lines.length + ' lines)', s.lines.every((l) => { try { JSON.parse(l); return true; } catch (e) { return false; } }));
  check('the launcher removed its copy', copies().length === 0);

  // started with no folder: no workspace, and a tool says so
  const bare = start(null);
  await send(bare, 'initialize', { protocolVersion: '2025-11-25', capabilities: {} });
  const none = jsonOf(await call(bare, 'lisp_definition', { name: 'area' }));
  check('with no folder, lisp_definition by name says there is no workspace', none.definitions.length === 0 && typeof none.note === 'string');
  bare.child.stdin.end();
  check('it exits 0 too', (await bare.done) === 0);

  fs.rmSync(workspace, { recursive: true, force: true });
  console.log('');
  console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
  process.exit(pass === total ? 0 : 1);
}

main().catch((e) => { console.log('  FAIL  ' + e.message); console.log('== RESULT: ' + pass + '/' + (total + 1) + ' checks passed =='); process.exit(1); });
