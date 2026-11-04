// Unit checks for src/forms.js, in the repo's PASS/FAIL + RESULT convention.
'use strict';
const { topLevelForms, topLevelFormAt } = require('../src/forms');

let pass = 0;
let total = 0;
function check(label, actual, expected) {
  total++;
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) { pass++; console.log('  PASS  ' + label); }
  else console.log('  FAIL  ' + label + '  got=' + a + '  want=' + e);
}
const texts = (src) => topLevelForms(src).map(([s, e]) => src.slice(s, e));
const at = (src, marker) => {
  const offset = src.indexOf('|');
  const text = src.replace('|', '');
  const r = topLevelFormAt(text, offset);
  return r && text.slice(r[0], r[1]);
};

console.log('== cog-lisp VS Code extension : form scanner ==');
check('separate forms', texts('(a b) (c)\n(d (e))'), ['(a b)', '(c)', '(d (e))']);
check('atoms at top level', texts('x 42 "s" #t'), ['x', '42', '"s"', '#t']);
check('quote prefixes belong to the datum', texts("'(1 2) `(a ,b ,@c) 'x"), ["'(1 2)", '`(a ,b ,@c)', "'x"]);
check('parens inside strings are skipped', texts('(display "(not a list") (x)'), ['(display "(not a list")', '(x)']);
check('escaped quote in a string', texts('(f "a\\"(b") (g)'), ['(f "a\\"(b")', '(g)']);
check('line comments are skipped', texts('; (no)\n(yes) ; (no)\n'), ['(yes)']);
check('nested block comments are skipped', texts('#| (no #| (no) |# no) |# (yes)'), ['(yes)']);
check('character literals, including #\\( and #\\)', texts('(list #\\( #\\) #\\space) (z)'), ['(list #\\( #\\) #\\space)', '(z)']);
check('an unterminated form runs to the end', texts('(a) (b (c'), ['(a)', '(b (c']);
check('cursor inside a form', at('(a) (b | c) (d)'), '(b  c)');
check('cursor in a nested form sends the top-level one', at('(define (f x)\n  (+ x| 1))\n(f 2)'), '(define (f x)\n  (+ x 1))');
check('cursor just after a form', at('(a)\n(b)|\n'), '(b)');
check('cursor on a blank line after a form', at('(a)\n\n|'), '(a)');
check('cursor before every form', at('|  (a) (b)'), '(a)');
check('no forms', topLevelFormAt('; just a comment\n', 3), null);
check('a bracket send is a form', texts('[coll size] (a [b c: 1])'), ['[coll size]', '(a [b c: 1])']);
check('cursor inside a bracket inside a form', at('(define c [OrderedCollection |new])'), '(define c [OrderedCollection new])');
check('#\\[ is a character, not a bracket', texts('(list #\\[ #\\]) (z)'), ['(list #\\[ #\\])', '(z)']);

check('a vector is one form', texts('(a #(1 2)) #(3) x'), ['(a #(1 2))', '#(3)', 'x']);

console.log('');
console.log('== RESULT: ' + pass + '/' + total + ' checks passed ==');
process.exit(pass === total ? 0 : 1);
