// Inside VS Code: open sample.lisp and ask the editor itself for hovers,
// completions, definitions and diagnostics, as a person would. Run twice by
// run.js: offline (COGLISP_TEST_MODE=offline) and with the language server
// (server). PASS/FAIL + RESULT convention.
'use strict';
const vscode = require('vscode');
const path = require('path');
const fs = require('fs');
const cp = require('child_process');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function run() {
  const mode = process.env.COGLISP_TEST_MODE || 'offline';
  let pass = 0;
  let total = 0;
  const check = (label, ok) => { total++; if (ok) pass++; console.log((ok ? '  PASS  ' : '  FAIL  ') + label); };
  console.log('== cog-lisp in VS Code ' + vscode.version + ' (' + mode + ') ==');

  const folder = vscode.workspace.workspaceFolders[0].uri.fsPath;
  const doc = await vscode.workspace.openTextDocument(path.join(folder, 'sample.lisp'));
  await vscode.window.showTextDocument(doc);
  check('a .lisp file outside the repository is cog-lisp (got ' + doc.languageId + ')', doc.languageId === 'cog-lisp');

  const hovers = async (d, line, character) => {
    const hs = await vscode.commands.executeCommand('vscode.executeHoverProvider', d.uri, new vscode.Position(line, character));
    return (hs || []).map((h) => h.contents.map((c) => (typeof c === 'string' ? c : c.value)).join('\n'));
  };
  const hoverText = async (d, line, character) => (await hovers(d, line, character)).join('\n');
  // the extension activates on the language (and the server starts); wait for it
  const until = async (probe, ms) => {
    for (let waited = 0; waited < ms; waited += 250) {
      if (await probe()) return true;
      await sleep(250);
    }
    return false;
  };

  if (mode === 'offline') {
    await until(async () => (await hoverText(doc, 0, 3)).includes('(define'), 5000);
    check('hover over define shows its call form', (await hoverText(doc, 0, 3)).includes('(define name value)'));
    check('hover over display shows its call form', (await hoverText(doc, 1, 4)).includes('(display x [port])'));
    check('no hover over a name of the program (greet)', (await hoverText(doc, 0, 10)) === '');
    const list = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', doc.uri, new vscode.Position(1, 5));
    const labels = (list ? list.items : []).map((i) => (typeof i.label === 'string' ? i.label : i.label.label));
    check('completion offers the built-ins (display-)', labels.includes('display'));
  } else {
    const uses = await vscode.workspace.openTextDocument(path.join(folder, 'uses.lisp'));
    await vscode.window.showTextDocument(uses);
    const started = await until(async () => (await hoverText(uses, 1, 2)).includes('(display name)'), 60000);
    check('the server starts and answers hover over a workspace definition (greet)', started);
    const defineHovers = (await hovers(uses, 0, 3)).filter((h) => h.includes('define-syntax'));
    check('hover over a built-in comes once, from the server (got ' + defineHovers.length + ')', defineHovers.length === 1);
    const defs = await vscode.commands.executeCommand('vscode.executeDefinitionProvider', uses.uri, new vscode.Position(1, 2));
    const def = (defs || [])[0];
    const defUri = def && (def.uri || def.targetUri);
    check('go to definition finds greet in sample.lisp',
      !!defUri && defUri.fsPath.toLowerCase() === doc.uri.fsPath.toLowerCase());
    let diags = [];
    await until(async () => (diags = vscode.languages.getDiagnostics(uses.uri)).length > 0, 10000);
    check('a compile error is underlined at its form, and the document\'s macro use is not',
      diags.length === 1 && diags[0].range.start.line === 3 && diags[0].message.includes('if: bad syntax'));
    const list = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', uses.uri, new vscode.Position(1, 2));
    const labels = (list ? list.items : []).map((i) => (typeof i.label === 'string' ? i.label : i.label.label));
    check('completion offers built-ins and the workspace\'s names, once each',
      labels.includes('display') && labels.includes('greet') && labels.filter((l) => l === 'display').length === 1);
    const editor = await vscode.window.showTextDocument(uses);
    editor.selection = new vscode.Selection(2, 2, 2, 2);
    await vscode.commands.executeCommand('cog-lisp.expandMacro');
    let expansion = '';
    await until(async () => {
      const shown = vscode.window.visibleTextEditors.find((e) => e.document.isUntitled);
      expansion = shown ? shown.document.getText() : '';
      return expansion !== '';
    }, 10000);
    check('Expand Macro shows the expansion of the call at the cursor',
      expansion.includes('(twice (greet "b"))') && expansion.includes('(begin (greet "b") (greet "b"))'));

    // Format Document, through the server (specs/formatter.md R-4, R-5, AC-4)
    const fmtPath = path.join(folder, 'to-format.lisp');
    fs.writeFileSync(fmtPath, '(define (f x) (* x x))\n');
    const fmtDoc = await vscode.workspace.openTextDocument(fmtPath);
    await vscode.window.showTextDocument(fmtDoc);
    const indent = vscode.workspace.getConfiguration('editor', { languageId: 'cog-lisp' });
    check('cog-lisp files indent with tabs by default', indent.get('insertSpaces') === false && indent.get('detectIndentation') === false);
    let edits = [];
    await until(async () => (edits = (await vscode.commands.executeCommand('vscode.executeFormatDocumentProvider', fmtDoc.uri,
      { tabSize: 4, insertSpaces: false })) || []).length > 0, 10000);
    const formatted = new vscode.WorkspaceEdit();
    edits.forEach((e) => formatted.replace(fmtDoc.uri, e.range, e.newText));
    await vscode.workspace.applyEdit(formatted);
    check('Format Document lays the file out with tabs', fmtDoc.getText() === '(define (f x)\n\t(* x x)\n)\n');

    // the server must not hold the checkout's image: two VMs on one image collide
    const ext = require(path.join(__dirname, '..', '..', 'src', 'extension.js'))._test;
    const root = vscode.workspace.getConfiguration('cogLisp').get('root');
    const firstCopy = ext.serverImageDir();
    check('the server runs on a private copy of the image',
      !!firstCopy && fs.existsSync(path.join(firstCopy, 'cog-lisp.image')) &&
      !path.resolve(firstCopy).toLowerCase().startsWith(path.resolve(root).toLowerCase()));
    const program = path.join(folder, 'hello-while-serving.lisp');
    fs.writeFileSync(program, '(display "ran beside the server")\n(newline)\n');
    const windows = process.platform === 'win32';
    const ran = windows
      ? cp.spawnSync('cmd.exe', ['/d', '/c', '.\\cog-lisp.bat', program], { cwd: root, encoding: 'utf8', input: '' })
      : cp.spawnSync('./cog-lisp.sh', [program], { cwd: root, encoding: 'utf8', input: '' });
    if (ran.status !== 0) console.log('    output: ' + ((ran.stdout || '') + (ran.stderr || '')).split('\n')[0]);
    check('a program runs from the same checkout while the server runs (exit ' + ran.status + ')',
      ran.status === 0 && (ran.stdout || '').includes('ran beside the server'));
    const image = path.join(root, 'pharo', 'cog-lisp.image');
    const now = new Date();
    fs.utimesSync(image, now, now);
    const restarted = await until(async () => {
      const dir = ext.serverImageDir();
      return !!dir && dir !== firstCopy && ext.serverActive() &&
        (await hoverText(uses, 1, 2)).includes('(display name)');
    }, 60000);
    console.log('    restart: ' + JSON.stringify({ restarted, first: firstCopy, now: ext.serverImageDir(), active: ext.serverActive(), oldLeft: fs.existsSync(firstCopy) }));
    check('a rebuilt image restarts the server on a new copy, and the old copy is removed',
      restarted && !fs.existsSync(firstCopy));
  }

  console.log('');
  console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
  if (pass !== total) throw new Error(total - pass + ' checks failed');
}
module.exports = { run };
