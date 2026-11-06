// The language server spike (specs/phase-10-documentation-and-editor.md step
// 10.5): VS Code's own message layer (vscode-jsonrpc, which vscode-languageclient
// is built on) talks to lib/lsp.lisp, served by the image. Needs a built image;
// run from vscode/ with `node test/lsp.test.js`. PASS/FAIL + RESULT convention.
'use strict';
const path = require('path');
const fs = require('fs');
const cp = require('child_process');
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

async function main() {
  console.log('== cog-lisp language server, through vscode-jsonrpc ==');
  if (!fs.existsSync(path.join(root, 'pharo', 'cog-lisp.image'))) {
    console.log('  no built image in pharo/: build it first');
    process.exit(2);
  }
  const server = windows
    ? cp.spawn('cmd.exe', ['/d', '/c', '.\\cog-lisp.bat', 'lib\\lsp.lisp'], { cwd: root })
    : cp.spawn('./cog-lisp.sh', ['lib/lsp.lisp'], { cwd: root });
  const connection = rpc.createMessageConnection(
    new rpc.StreamMessageReader(server.stdout), new rpc.StreamMessageWriter(server.stdin));
  connection.listen();

  const started = Date.now();
  const init = await connection.sendRequest('initialize', { processId: process.pid, rootUri: null, capabilities: {} });
  check('initialize: hover is offered (' + (Date.now() - started) + ' ms)', init.capabilities.hoverProvider === true);
  check('... by cog-lisp', init.serverInfo.name === 'cog-lisp');
  connection.sendNotification('initialized', {});

  const uri = 'file:///spike.lisp';
  connection.sendNotification('textDocument/didOpen',
    { textDocument: { uri, languageId: 'cog-lisp', version: 1, text: '(define (f h)\n  (hash-table-ref h \'k))\n' } });
  const hover = await connection.sendRequest('textDocument/hover',
    { textDocument: { uri }, position: { line: 1, character: 5 } });
  check('hover shows the documentation from the image',
    hover && hover.contents.kind === 'markdown' && hover.contents.value.includes('(hash-table-ref table key [missing])'));
  const none = await connection.sendRequest('textDocument/hover', { textDocument: { uri }, position: { line: 0, character: 11 } });
  check('no documentation: no hover', none === null);

  const timings = [];
  for (let i = 0; i < 20; i++) {
    const t = Date.now();
    await connection.sendRequest('textDocument/hover', { textDocument: { uri }, position: { line: 1, character: 5 } });
    timings.push(Date.now() - t);
  }
  timings.sort((a, b) => a - b);
  check('a hover answers quickly (median ' + timings[10] + ' ms over 20)', timings[10] < 200);

  await connection.sendRequest('shutdown');
  const exited = new Promise((resolve) => server.on('exit', (code) => resolve(code)));
  connection.sendNotification('exit');
  const code = await Promise.race([exited, new Promise((r) => setTimeout(() => r('hung'), 20000))]);
  check('exit ends the server (' + code + ')', code === 0);
  connection.dispose();

  console.log('');
  console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
  process.exit(pass === total ? 0 : 1);
}

main().catch((e) => { console.log('  FAIL  ' + e.message); console.log('== RESULT: ' + pass + '/' + (total + 1) + ' checks passed =='); process.exit(1); });
