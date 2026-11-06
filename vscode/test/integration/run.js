// Runs the extension in a real VS Code (downloaded and cached by
// @vscode/test-electron in .vscode-test/) and checks hover help and completion
// there (Phase 10 step 10.3). The workspace is a temporary folder with no
// cog-lisp settings, so the .lisp association must come from the extension.
'use strict';
const path = require('path');
const fs = require('fs');
const os = require('os');
const { runTests } = require('@vscode/test-electron');

// A VS Code (or Claude Code) terminal sets ELECTRON_RUN_AS_NODE=1, which makes the
// downloaded VS Code run as plain Node; the test VS Code must not inherit it.
delete process.env.ELECTRON_RUN_AS_NODE;

async function main() {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'cog-lisp-hover-'));
  fs.writeFileSync(path.join(workspace, 'sample.lisp'), '(define (greet name)\n  (display name))\n');
  try {
    await runTests({
      version: '1.90.0',
      extensionDevelopmentPath: path.join(__dirname, '..', '..'),
      extensionTestsPath: path.join(__dirname, 'suite.js'),
      launchArgs: [workspace, '--disable-extensions', '--skip-welcome', '--skip-release-notes'],
    });
  } catch (e) {
    console.log('== RESULT: the VS Code checks failed or did not run: ' + e);
    process.exit(1);
  }
}
main();
