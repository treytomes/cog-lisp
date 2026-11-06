// Inside VS Code: open sample.lisp and ask the editor itself for hovers,
// completions, definitions and diagnostics, as a person would. Run twice by
// run.js: offline (COGLISP_TEST_MODE=offline) and with the language server
// (server). PASS/FAIL + RESULT convention.
'use strict';
const vscode = require('vscode');
const path = require('path');

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
  }

  console.log('');
  console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
  if (pass !== total) throw new Error(total - pass + ' checks failed');
}
module.exports = { run };
