// What a packaged .vsix must hold for hover help to work (Phase 10 step 10.3):
// the help data and its code, and the claim on .lisp files, so the editor gives
// those files the cog-lisp language in any folder, not only in this repository
// (whose .vscode/settings.json associates them). Run after `npm run package`.
// PASS/FAIL + RESULT convention.
'use strict';
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

let pass = 0;
let total = 0;
function check(label, ok) {
  total++;
  if (ok) pass++;
  console.log((ok ? '  PASS  ' : '  FAIL  ') + label);
}

console.log('== cog-lisp VS Code extension : the package ==');
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));
const language = manifest.contributes.languages.find((l) => l.id === 'cog-lisp');
check('the cog-lisp language claims .lisp files', !!language && (language.extensions || []).includes('.lisp'));
check('the extension activates on a cog-lisp file', manifest.activationEvents.includes('onLanguage:cog-lisp'));

// the files vsce packages, as it lists them
const listed = cp.execSync('npx --no-install vsce ls', { cwd: path.join(__dirname, '..'), encoding: 'utf8' })
  .split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
for (const f of ['builtins.json', 'src/builtins.js', 'src/extension.js', 'package.json', 'THIRD-PARTY-NOTICES.md']) {
  check('the package holds ' + f, listed.includes(f));
}

// the language client (Phase 10 step 10.5), and a notice for every npm package
check('the package holds the language client',
  listed.includes('node_modules/vscode-languageclient/node.js') && listed.includes('node_modules/vscode-jsonrpc/node.js'));
check('no test or build tool is packaged',
  !listed.some((f) => f.startsWith('node_modules/@vscode/') || f.startsWith('test/') || f.startsWith('.vscode-test/')));
const notices = fs.readFileSync(path.join(__dirname, '..', 'THIRD-PARTY-NOTICES.md'), 'utf8');
const packaged = [...new Set(listed.filter((f) => f.endsWith('/package.json'))
  .map((f) => /^(?:.*\/)?node_modules\/((?:@[^/]+\/)?[^/]+)\/package\.json$/.exec(f))
  .filter(Boolean).map((m) => m[1] + '@' + JSON.parse(fs.readFileSync(path.join(__dirname, '..', m[0]), 'utf8')).version))];
const unlisted = packaged.filter((p) => {
  const [name, version] = [p.slice(0, p.lastIndexOf('@')), p.slice(p.lastIndexOf('@') + 1)];
  return !notices.includes('| ' + name + ' | ' + version + ' |');
});
check('THIRD-PARTY-NOTICES.md lists every packaged npm package at its version (' + packaged.length + ')' +
  (unlisted.length ? ': missing ' + unlisted.join(', ') : ''), packaged.length > 0 && unlisted.length === 0);

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
