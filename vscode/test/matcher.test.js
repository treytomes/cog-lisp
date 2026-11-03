// Checks the problem matcher's regexp in package.json against runner output.
'use strict';
const fs = require('fs');
const path = require('path');

const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));
const pattern = pkg.contributes.problemMatchers[0].pattern;
const re = new RegExp(pattern.regexp);

let pass = 0;
let total = 0;
function check(label, line, expected) {
  total++;
  const m = re.exec(line);
  const actual = m && { file: m[pattern.file], line: m[pattern.line], column: m[pattern.column], message: m[pattern.message] };
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) { pass++; console.log('  PASS  ' + label); }
  else console.log('  FAIL  ' + label + '  got=' + a + '  want=' + e);
}

console.log('== cog-lisp VS Code extension : problem matcher ==');
check('a located error',
  'C:\\Users\\me\\cog-lisp\\examples\\hello.lisp:4:3: error: car: not a pair: 5',
  { file: 'C:\\Users\\me\\cog-lisp\\examples\\hello.lisp', line: '4', column: '3', message: 'car: not a pair: 5' });
check('program output before it on the same line is not part of the path',
  'Hello from cog-lisp!c:\\Users\\me\\cog-lisp\\examples\\hello.lisp:2:1: error: unbound variable: x',
  { file: 'c:\\Users\\me\\cog-lisp\\examples\\hello.lisp', line: '2', column: '1', message: 'unbound variable: x' });
check('a path with spaces',
  'C:\\Users\\me\\dir with space\\err prog.lisp:4:4: error: division by zero',
  { file: 'C:\\Users\\me\\dir with space\\err prog.lisp', line: '4', column: '4', message: 'division by zero' });
check('a message containing colons',
  'C:\\p\\a.lisp:1:1: error: let: bad binding: (x)',
  { file: 'C:\\p\\a.lisp', line: '1', column: '1', message: 'let: bad binding: (x)' });
check('an unlocated error is not a problem', 'error: no program file given', null);
check('ordinary output is not a problem', 'Hello from cog-lisp!', null);

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
