// Runs vscode-tmgrammar-test on test/*.test.lisp and judges it by its output.
// The tool's exit code cannot be used: on Node 24 for Windows it ends every run
// with a libuv assertion (exit 127), pass or fail, after printing its results.
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');

const root = path.join(__dirname, '..');
const cli = path.join(root, 'node_modules', 'vscode-tmgrammar-test', 'dist', 'unit.js');
const run = spawnSync(process.execPath, [cli, '-g', 'syntaxes/cog-lisp.tmLanguage.json', 'test/*.test.lisp'],
  { cwd: root, encoding: 'utf8' });
const out = (run.stdout || '') + (run.stderr || '');
const passed = (out.match(/√ .* run successful/g) || []).length;
const failed = (out.match(/× .* failed/g) || []).length;

console.log('== cog-lisp VS Code extension : grammar ==');
process.stdout.write(out.split('\n').filter((l) => !l.startsWith('Assertion failed: !(handle->flags')).join('\n'));
console.log('');
console.log('== RESULT: ' + passed + '/' + (passed + failed) + ' grammar test files passed ==');
process.exit(failed === 0 && passed > 0 ? 0 : 1);
