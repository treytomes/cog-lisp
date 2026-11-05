"============================================================================
 cog-lisp : Phase 7.6 acceptance suite  (specs/phase-7.6-smalltalk-interop.md,
 AC-1..19). AC-20 is a benchmark (bench\run-benchmarks.bat); AC-21 is every
 other suite. The examples (examples\interop-*.lisp) run in the runner suite.
 Every bang in Lisp text is doubled for the chunk reader.
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h ev lst rd msg compileMsg readErr w proc |
h := LispTestHarness new.
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
rd := [:s | LispPrinter writeString: (LispReader read: s)].
msg := [:s | [ev value: s. #none] on: Error do: [:e | LispError describe: e]].
compileMsg := [:s | [ev value: s. #none] on: LispCompileError do: [:e | e messageText]].
readErr := [:s | [LispReader read: s. #none] on: LispReadError do: [:e | { e messageText. e position. e isIncomplete }]].
w := [:v | LispPrinter writeString: v].

[
h say: '== cog-lisp Phase 7.6 : Smalltalk interop =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (Smalltalk imageDirectory parent / 'lib' / 'core.lisp') fullName.

"AC-1 send"

[ev value: '(define d (send (smalltalk Dictionary) new)) (send d at:put: 1 2) (send d at: 1)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.6-interop.lisp)"

[ev value: '(define (sz s) (send s size)) (sz "four")'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.6-interop.lisp)"

"AC-2 arity checked against the selector"
h check: 'AC-2 too few' actual: (compileMsg value: '(send 1 at:put: 2)') expected: 'send: at:put: takes 2 arguments, got 1'.
h check: 'AC-2 too many for unary' actual: (compileMsg value: '(send 1 size 2)') expected: 'send: size takes 0 arguments, got 1'.
h check: 'AC-2 not a selector' actual: (compileMsg value: '(send 1 foo:bar)') expected: 'send: not a Smalltalk selector: foo:bar'.
h check: 'AC-2 selector must be a symbol' actual: (compileMsg value: '(send 1 2)') expected: 'send: bad selector: 2'.

"AC-3 a literal selector compiles to a direct send"
h check: 'AC-3 disassembly shows send: size and no perform:'
	actual: ((ev value: '(lambda (c) (send c size))') block compiledBlock symbolic in: [:text |
		(text includesSubstring: 'send: size') and: [(text includesSubstring: 'perform') not]])
	expected: true.

"AC-4 order of evaluation"
[ev value: '(define order (list)) (define (note x) (set!! order (cons x order)) x) (send (note 5) between:and: (note 1) (note 9)) (reverse order)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.6-interop.lisp)"

"AC-5 / AC-7 brackets"
#( '[coll size]' '(send coll size)'
   '[3 + 4]' '(send 3 + 4)'
   '[d at: k put: v]' '(send d at:put: k v)'
   '[[coll asSet] size]' '(send (send coll asSet) size)'
   '[OrderedCollection new]' '(send (smalltalk OrderedCollection) new)'
   '[d at: (car keys) put: (* 2 n)]' '(send d at:put: (car keys) (* 2 n))'
   '(a [b size] c)' '(a (send b size) c)'
   '[x -> 3]' '(send x -> 3)' ) pairsDo: [:src :want |
	h check: 'AC-5 ' , src actual: (rd value: src) expected: want].

"AC-6 malformed brackets"
#('[]' '[a]' '[a b c]' '[a at: 1 put:]' '[a 1]') do: [:src |
	h check: 'AC-6 ' , src , ' is a read error with the hint'
		actual: (readErr value: src) first
		expected: 'bad message send: brackets are Smalltalk sends; use ( ) for grouping'].
h check: 'AC-6 R6RS-style brackets point at the bracket' actual: (readErr value: '(let ([x 1]) x)') second expected: 6.
h check: 'AC-6 an unclosed [ is incomplete' actual: (readErr value: '[a size') expected: { 'unterminated ['. 0. true }.
h check: 'AC-6 a stray ] is an error' actual: (readErr value: ']') first expected: 'unexpected ]'.

"AC-8 globals"
h check: 'AC-8 (smalltalk OrderedCollection)' actual: (ev value: '(smalltalk OrderedCollection)') == OrderedCollection expected: true.
h check: 'AC-8 an unknown global is a compile error' actual: (compileMsg value: '(smalltalk NoSuchThing)') expected: 'smalltalk: no Smalltalk global named NoSuchThing'.
h check: 'AC-8 smalltalk-global finds one' actual: (ev value: '(smalltalk-global "Set")') == Set expected: true.

"AC-9 dynamic sends"

h check: 'AC-9 a wrong arity fails when it runs' actual: ((msg value: '(smalltalk-send 1 "gcd:")') ~= #none) expected: true.

"AC-10 nil"
h check: 'AC-10 smalltalk-nil is nil' actual: (ev value: '(smalltalk-nil)') isNil expected: true.

"AC-11 symbols"
h check: 'AC-11 smalltalk-symbol' actual: (ev value: '(smalltalk-symbol (quote foo))') == #foo expected: true.

"AC-12 lists and arrays"
h check: 'AC-12 list->array' actual: (ev value: '(list->array (quote (1 2 3)))') expected: #(1 2 3).

h check: 'AC-12 a LISP list from Smalltalk: do:' actual: ([:l | | sum | sum := 0. l do: [:x | sum := sum + x]. sum] value: (lst value: '(1 2 3)')) expected: 6.
h check: 'AC-12 ... collect: answers a LISP list' actual: ((lst value: '(1 2 3)') collect: [:x | x * 2]) expected: (lst value: '(2 4 6)').
h check: 'AC-12 ... size and asArray' actual: { (lst value: '(1 2 3)') size. (lst value: '(1 2 3)') asArray. LispEmptyList default size } expected: { 3. #(1 2 3). 0 }.

"AC-13 printing"
h check: 'AC-13 nil' actual: (w value: nil) expected: '#<nil>'.
h check: 'AC-13 a collection' actual: (w value: OrderedCollection new) expected: '#<an OrderedCollection()>'.
h check: 'AC-13 a class' actual: (w value: OrderedCollection) expected: '#<OrderedCollection>'.
h check: 'AC-13 a Smalltalk symbol' actual: (w value: #foo) expected: '#<#foo>'.
h check: 'AC-13 display of a Smalltalk symbol' actual: (LispPrinter displayString: #foo) expected: '#<#foo>'.
h check: 'AC-13 LISP values unchanged' actual: (w value: (ev value: '(list 1 "s" #\a (quote x) car)')) expected: '(1 "s" #\a x #<procedure car>)'.

"AC-14 LISP procedures as blocks"

"AC-15 tail calls are driven before answering Smalltalk"
ev value: '(define (helper n) (* n 10)) (define (via-tail n) (helper n))'.

proc := ev value: 'via-tail'.
h check: 'AC-15 value: from Smalltalk answers the value' actual: (proc value: 4) expected: 40.
h check: 'AC-15 a deep tail loop called from Smalltalk'
	actual: ((ev value: '(define (cd n) (if (= n 0) (quote done) (cd (- n 1)))) (lambda (n) (cd n))') value: 100000)
	expected: (LispSymbol named: 'done').

"AC-16 errors and cleanup across the boundary"

[ev value: '(define trail (list)) [(lambda () (set!! trail (cons 1 trail))) ensure: (lambda () (set!! trail (cons 2 trail)))] trail'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.6-interop.lisp)"

"AC-17 procedure->block"
h check: 'AC-17 a real block with the arity' actual: ((ev value: '(procedure->block (lambda (a b) (* a b)))') in: [:b | { b isBlock. b numArgs. b value: 6 value: 7 }]) expected: { true. 2. 42 }.
h check: 'AC-17 a variadic procedure is refused' actual: ((msg value: '(procedure->block list)') beginsWith: 'procedure->block:') expected: true.

"AC-18 the CogLisp facade"
h check: 'AC-18 eval:' actual: (CogLisp eval: '(+ 1 2)') expected: 3.
CogLisp eval: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))'.
h check: 'AC-18 at: answers the procedure' actual: ((CogLisp at: #fact) value: 10) expected: 3628800.
h check: 'AC-18 call:with:' actual: (CogLisp call: #fact with: 5) expected: 120.
h check: 'AC-18 call:withArguments:' actual: (CogLisp call: 'max' withArguments: #(3 9 4)) expected: 9.
CogLisp define: #greeting as: 'hi'.
h check: 'AC-18 define:as:' actual: (ev value: 'greeting') expected: 'hi'.
h check: 'AC-18 read:' actual: (CogLisp read: '(a b)') expected: (lst value: '(a b)').

"AC-19 errors"

h check: 'AC-19 R-2 translations unchanged' actual: { msg value: '(car 5)'. msg value: '(+ 1 "a")'. msg value: '(/ 1 0)' } expected: { 'car: not a pair: 5'. '+: not a number'. 'division by zero' }.
h finish
] on: Error do: [:e | h harnessError: e].
!
