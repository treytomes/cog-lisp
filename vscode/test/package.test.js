// What a packaged .vsix must hold for hover help to work (Phase 10 step 10.3):
// the help data and its code, and the claim on .lisp files, so the editor gives
// those files the cog-lisp language in any folder, not only in this repository
// (whose .vscode/settings.json associates them). And that its code is the one
// bundled file, with a notice and a license text for every npm package in it
// (specs/31-vsix-bundle.md AC-1 to AC-3). Run after `npm run package` (or
// `npm run bundle`): `vsce ls` lists the files, but does not bundle.
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

const root = path.join(__dirname, '..');
const dist = path.join(root, 'dist');
const read = (f) => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '');

console.log('== cog-lisp VS Code extension : the package ==');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const language = manifest.contributes.languages.find((l) => l.id === 'cog-lisp');
check('the cog-lisp language claims .lisp files', !!language && (language.extensions || []).includes('.lisp'));
check('the extension activates on a cog-lisp file', manifest.activationEvents.includes('onLanguage:cog-lisp'));

// the files vsce packages, as it lists them
const listed = cp.execSync('npx --no-install vsce ls', { cwd: root, encoding: 'utf8' })
  .split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
for (const f of ['builtins.json', 'dist/extension.js', 'dist/THIRD-PARTY-LICENSES.txt', 'cspell/cspell-ext.json',
                 'cspell/cog-lisp-words.txt', 'package.json', 'THIRD-PARTY-NOTICES.md']) {
  check('the package holds ' + f, listed.includes(f));
}

// the bundle, and nothing it replaces (AC-1, AC-2)
const strays = listed.filter((f) => /^(node_modules|src|scripts|test|\.vscode-test)\//.test(f) || f === 'dist/meta.json');
check('no file of node_modules/, src/, scripts/ or test/ is packaged, nor the bundle\'s metafile' +
  (strays.length ? ': ' + strays.slice(0, 5).join(', ') : ''), strays.length === 0);
const scripts = listed.filter((f) => /\.[cm]?js$/.test(f));
check('the only script packaged is dist/extension.js (' + scripts.join(', ') + ')',
  scripts.length === 1 && scripts[0] === 'dist/extension.js');
check('the package holds at most 20 files (' + listed.length + ')', listed.length <= 20);
check('the extension starts from the bundle', manifest.main === './dist/extension.js');
check('vsce has no dependency to package: the language client is a development dependency',
  !manifest.dependencies || Object.keys(manifest.dependencies).length === 0);

// a notice and a license text for every npm package in the bundle (AC-3), by
// the metafile esbuild wrote: name and version, from the innermost
// node_modules/<name> of each input
const meta = JSON.parse(read(path.join(dist, 'meta.json')) || '{"inputs": {}}');
const bundled = [...new Set(Object.keys(meta.inputs)
  .map((f) => /^(.*node_modules\/((?:@[^/]+\/)?[^/]+))\//.exec(f))
  .filter(Boolean)
  .map((m) => m[2] + ' ' + JSON.parse(fs.readFileSync(path.join(root, m[1], 'package.json'), 'utf8')).version))];
const notices = read(path.join(root, 'THIRD-PARTY-NOTICES.md'));
const licenses = read(path.join(dist, 'THIRD-PARTY-LICENSES.txt'));
const lacking = bundled.filter((p) => {
  const [name, version] = p.split(' ');
  return !notices.includes('| ' + name + ' | ' + version + ' |') || !licenses.includes('\n' + p + '\n');
});
check('every npm package in the bundle has its row in THIRD-PARTY-NOTICES.md and its license text (' + bundled.length + ')' +
  (lacking.length ? ': lacking ' + lacking.join(', ') : ''), bundled.length > 0 && lacking.length === 0);
check('the bundle holds the language client',
  bundled.some((p) => p.startsWith('vscode-languageclient ')) && bundled.some((p) => p.startsWith('vscode-jsonrpc ')));

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
