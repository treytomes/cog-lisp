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
for (const f of ['builtins.json', 'src/builtins.js', 'src/extension.js', 'package.json']) {
  check('the package holds ' + f, listed.includes(f));
}

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
