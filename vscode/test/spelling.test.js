// cog-lisp's names in Code Spell Checker (specs/25-vscode-spelling.md AC-2):
// registration against a stand-in for cSpell's API, the shipped configuration,
// and the extension's list of the libraries the build compiles.
// PASS/FAIL + RESULT convention.
'use strict';
const fs = require('fs');
const path = require('path');
const { registerSpelling, CSPELL_ID } = require('../src/spelling');

let pass = 0;
let total = 0;
function check(label, ok) {
  total++;
  if (ok) pass++;
  console.log((ok ? '  PASS  ' : '  FAIL  ') + label);
}

const root = path.join(__dirname, '..');
const context = { asAbsolutePath: (p) => path.join(root, p) };
const stand = (extension) => ({ extensions: { getExtension: (id) => (id === CSPELL_ID ? extension : undefined) } });

(async () => {
  console.log('== cog-lisp VS Code extension : the spell checker ==');

  // cSpell installed: registerConfig gets cspell-ext.json's absolute path
  const registered = [];
  const logs = [];
  const ok = await registerSpelling(context, stand({ activate: async () => ({ registerConfig: async (p) => registered.push(p) }) }),
    (line) => logs.push(line));
  check('with cSpell installed, it registers once', ok === true && registered.length === 1);
  check('it registers cspell/cspell-ext.json by its absolute path',
    registered[0] === path.join(root, 'cspell', 'cspell-ext.json') && path.isAbsolute(registered[0]));
  check('and logs nothing', logs.length === 0);

  // no cSpell: nothing is registered, nothing is logged
  const none = [];
  check('without cSpell, it registers nothing', (await registerSpelling(context, stand(undefined), (l) => none.push(l))) === false);
  check('and logs nothing', none.length === 0);

  // a cSpell that fails, or has no such API: logged, never thrown
  const failed = [];
  const answer = await registerSpelling(context, stand({ activate: async () => { throw new Error('boom'); } }), (l) => failed.push(l));
  check('a failing cSpell is logged, not thrown', answer === false && failed.length === 1 && /boom/.test(failed[0]));
  const old = [];
  check('a cSpell without registerConfig is logged',
    (await registerSpelling(context, stand({ activate: async () => ({}) }), (l) => old.push(l))) === false && old.length === 1);

  // the configuration and its word list
  const ext = JSON.parse(fs.readFileSync(path.join(root, 'cspell', 'cspell-ext.json'), 'utf8'));
  const def = (ext.dictionaryDefinitions || []).find((d) => d.name === 'cog-lisp');
  check('cspell-ext.json defines the cog-lisp dictionary', !!def);
  const wordsFile = def && path.join(root, 'cspell', def.path);
  check('its word list exists', !!wordsFile && fs.existsSync(wordsFile));
  const setting = (ext.languageSettings || []).find((s) => (s.dictionaries || []).includes('cog-lisp'));
  check('it applies to cog-lisp files and Markdown',
    !!setting && setting.languageId.split(',').map((s) => s.trim()).sort().join() === 'cog-lisp,markdown');
  const words = wordsFile && fs.existsSync(wordsFile) ? fs.readFileSync(wordsFile, 'utf8').split('\n').filter(Boolean) : [];
  check('the words are sorted, unique, lower case and three letters or more',
    words.length > 100 && words.every((w, i) => /^[a-z]{3,}$/.test(w) && (i === 0 || words[i - 1] < w)));
  for (const w of ['nthcdr', 'zerop', 'letrec', 'cdar', 'cadddr']) check('the words hold ' + w, words.includes(w));

  // the extension's stale-image check knows every library the build compiles
  const extensionText = fs.readFileSync(path.join(root, 'src', 'extension.js'), 'utf8');
  const listed = /const BUILT_IN_LIBRARIES = \[([^\]]*)\]/.exec(extensionText);
  const inExtension = listed ? listed[1].split(',').map((s) => s.trim().replace(/'/g, '')).sort() : [];
  const compilerText = fs.readFileSync(path.join(root, '..', 'src', 'coglisp-compiler.st'), 'utf8');
  const built = [...compilerText.matchAll(/evalFile: \(lib \/ ''([a-z-]+\.lisp)''\)/g)].map((m) => m[1]).sort();
  check('BUILT_IN_LIBRARIES is the build\'s list of lib/ files (' + built.join(' ') + ')',
    built.length > 0 && JSON.stringify(inExtension) === JSON.stringify(built));

  console.log('');
  console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
  process.exit(pass === total ? 0 : 1);
})();
