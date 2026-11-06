// Inside VS Code: open sample.lisp and ask the editor itself for hovers and
// completions, as a person hovering would. PASS/FAIL + RESULT convention.
'use strict';
const vscode = require('vscode');
const path = require('path');

async function run() {
  let pass = 0;
  let total = 0;
  const check = (label, ok) => { total++; if (ok) pass++; console.log((ok ? '  PASS  ' : '  FAIL  ') + label); };
  console.log('== cog-lisp in VS Code ' + vscode.version + ' : hover help and completion ==');

  const file = path.join(vscode.workspace.workspaceFolders[0].uri.fsPath, 'sample.lisp');
  const doc = await vscode.workspace.openTextDocument(file);
  await vscode.window.showTextDocument(doc);
  check('a .lisp file outside the repository is cog-lisp (got ' + doc.languageId + ')', doc.languageId === 'cog-lisp');

  const hoverText = async (line, character) => {
    const hovers = await vscode.commands.executeCommand('vscode.executeHoverProvider', doc.uri, new vscode.Position(line, character));
    return (hovers || []).map((h) => h.contents.map((c) => (typeof c === 'string' ? c : c.value)).join('\n')).join('\n');
  };
  // the extension activates on the language; give it a moment the first time
  let defineHover = '';
  for (let i = 0; i < 20 && !defineHover.includes('(define'); i++) {
    defineHover = await hoverText(0, 3);
    if (!defineHover.includes('(define')) await new Promise((r) => setTimeout(r, 250));
  }
  check('hover over define shows its call form', defineHover.includes('(define name value)'));
  check('hover over display shows its call form', (await hoverText(1, 4)).includes('(display x [port])'));
  check('no hover over a name of the program (greet)', (await hoverText(0, 10)) === '');

  const list = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', doc.uri, new vscode.Position(1, 5));
  const labels = (list ? list.items : []).map((i) => (typeof i.label === 'string' ? i.label : i.label.label));
  check('completion offers the built-ins (display-)', labels.includes('display'));

  console.log('');
  console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
  if (pass !== total) throw new Error(total - pass + ' checks failed');
}
module.exports = { run };
