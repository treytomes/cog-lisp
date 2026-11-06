// Runs the extension in a real VS Code (downloaded and cached by
// @vscode/test-electron in .vscode-test/) and checks it there, twice:
//  - offline (Phase 10 step 10.3): a temporary folder with no cog-lisp settings,
//    so the .lisp association and the built-ins' help must come from the
//    extension alone;
//  - with the language server (step 10.5): the same kind of folder, with
//    cogLisp.root set to this checkout, whose built image serves lib/lsp.lisp.
//    Skipped (and said so) when there is no built image.
'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');
const { runTests } = require('@vscode/test-electron');

// A VS Code (or Claude Code) terminal sets ELECTRON_RUN_AS_NODE=1, which makes the
// downloaded VS Code run as plain Node; the test VS Code must not inherit it.
delete process.env.ELECTRON_RUN_AS_NODE;

const repo = path.join(__dirname, '..', '..', '..');

function makeWorkspace(prefix, settings) {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  fs.writeFileSync(path.join(workspace, 'sample.lisp'), '(define (greet name)\n  (display name))\n');
  fs.writeFileSync(path.join(workspace, 'uses.lisp'),
    '(define-syntax twice (syntax-rules () ((_ e) (begin e e))))\n(greet "a")\n(twice (greet "b"))\n(define (f x) (if))\n');
  if (settings) {
    fs.mkdirSync(path.join(workspace, '.vscode'));
    fs.writeFileSync(path.join(workspace, '.vscode', 'settings.json'), JSON.stringify(settings, null, 2));
  }
  return workspace;
}

async function run(mode, workspace) {
  await runTests({
    version: '1.90.0',
    extensionDevelopmentPath: path.join(__dirname, '..', '..'),
    extensionTestsPath: path.join(__dirname, 'suite.js'),
    extensionTestsEnv: { COGLISP_TEST_MODE: mode },
    launchArgs: [workspace, '--disable-extensions', '--skip-welcome', '--skip-release-notes'],
  });
}

async function main() {
  try {
    await run('offline', makeWorkspace('cog-lisp-hover-', null));
    if (fs.existsSync(path.join(repo, 'pharo', 'cog-lisp.image'))) {
      await run('server', makeWorkspace('cog-lisp-lsp-', { 'cogLisp.root': repo }));
    } else {
      console.log('== the language server checks need a built image in pharo/: skipped ==');
    }
  } catch (e) {
    console.log('== RESULT: the VS Code checks failed or did not run: ' + e);
    process.exit(1);
  }
}
main();
