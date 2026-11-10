// Unit checks for src/builtins.js and the generated builtins.json
// (specs/16-phase-10-documentation-and-editor.md step 10.3, AC-3), in the repo's
// PASS/FAIL + RESULT convention. That builtins.json matches the image is checked
// by tests/lisp/phase-10.2-reference.lisp.
'use strict';
const path = require('path');
const { loadBuiltins, symbolAt, hoverMarkdown, completions } = require('../src/builtins');

let pass = 0;
let total = 0;
function check(label, actual, expected) {
  total++;
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) { pass++; console.log('  PASS  ' + label); }
  else console.log('  FAIL  ' + label + '  got=' + a + '  want=' + e);
}
// the symbol at the | in a line
const at = (line) => {
  const i = line.indexOf('|');
  const found = symbolAt(line.replace('|', ''), i);
  return found && found.name;
};

console.log('== cog-lisp VS Code extension : hover help and completion ==');
const builtins = loadBuiltins(path.join(__dirname, '..', 'builtins.json'));
const names = Object.keys(builtins);

check('the data has every public built-in', names.length > 280, true);
check('each entry has a call form, a kind, a category and a description',
  names.filter((n) => !(builtins[n].call && builtins[n].kind && builtins[n].category && builtins[n].description !== undefined)), []);
check('each call form names its built-in', names.filter((n) => !builtins[n].call.includes('(' + n)), []);

check('the symbol under the cursor', at('(string-r|ef s 0)'), 'string-ref');
check('... at its first character', at('(|car x)'), 'car');
check('... just after it', at('(car| x)'), 'car');
check('... with punctuation in the name', at('(set-car!| p 1)'), 'set-car!');
check('... after a quote', at("(f '|sym)"), 'sym');
check('... none on white space', at('(f  |  x)'), null);
check('... none on a parenthesis', at('(|(f))'), null);

check('hover shows the call form, what it does, and its kind',
  hoverMarkdown('string-ref', builtins['string-ref']),
  '```cog-lisp\n(string-ref string k)\n```\n\nThe character of string at index k, from 0.\n\n*procedure · Strings*');
check('a special form says so', hoverMarkdown('if', builtins['if']).endsWith('*special form · Special forms*'), true);

check('completion by prefix', completions(builtins, 'string-u'), ['string-upcase']);
check('completion of a family', completions(builtins, 'hash-table-ref'), ['hash-table-ref', 'hash-table-ref/default']);
check('completion with no prefix offers everything', completions(builtins, '').length, names.length);

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
