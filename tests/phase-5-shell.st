"============================================================================
 cog-lisp : Phase 5 in-image acceptance suite  (specs/04-phase-5-repl-runner.md)
 Covers the language additions, source retention, and LispRepl driven by
 in-memory streams. The real entry points (build, runner, REPL over stdin,
 persistence) are covered by tests\phase-5-runner.bat.
 This suite never calls save-image or exit: it runs in the stock image.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-5-shell.st
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| h out check checkErr ev evAll nl repl r captured tmp unspec |
h := LispTestHarness new.
out := [:s | h say: s].
nl := String with: Character lf.
ev := [:s | LispCompiler new evalString: s].
evAll := [:s | LispCompiler new evalAll: s].
unspec := LispUnspecified default.
check := h checkBlock.
checkErr := h checkErrBlock.
"run the REPL over a string; answer {stdout. stderr}"
repl := [:input | | o e |
	o := WriteStream on: String new.
	e := WriteStream on: String new.
	(LispRepl in: (ReadStream on: input) out: o err: e) run.
	{ o contents. e contents }].
"evaluate with display/write output captured; answer the captured text"
captured := [:src | | w |
	w := WriteStream on: String new.
	LispPrimitives withOutput: w do: [evAll value: src].
	w contents].

LispPrimitives installDefault.

[
out value: '== cog-lisp Phase 5 : shell, language additions, source =='.

"AC-14 the unspecified value"
check value: 'AC-14 (if #f 1) is unspecified' value: ((ev value: '(if #f 1)') == unspec) value: true.
check value: 'AC-14 define yields unspecified' value: ((ev value: '(define y 1)') == unspec) value: true.
check value: 'AC-14 set-bang yields unspecified' value: ((evAll value: '(define z 1) (set!! z 2)') == unspec) value: true.
check value: 'AC-14 display yields unspecified'
	value: ((LispPrimitives withOutput: (WriteStream on: String new) do: [ev value: '(display 1)']) == unspec)
	value: true.
check value: 'AC-14 writes as #<unspecified>' value: (LispPrinter writeString: unspec) value: '#<unspecified>'.
check value: 'AC-14 (list) is still the empty list' value: ((ev value: '(list)') == LispEmptyList default) value: true.

"AC-17 it is a first-class value, and it is not 'unbound'"
[evAll value: '(define u (if #f #f)) (eq? u (if #f #f))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-5-shell.lisp)"

"AC-8..12 LispRepl over in-memory streams"
r := repl value: '(+ 1 2)' , nl.
check value: 'AC-8 (+ 1 2) prints 3' value: r first value: '> 3' , nl , '> ' , nl.
r := repl value: '(define x' , nl , '  5)' , nl , 'x' , nl.
check value: 'AC-9/10 multi-line define is one form and prints nothing; x prints 5' value: r first value: '> > 5' , nl , '> ' , nl.
r := repl value: '(car 5)' , nl , '(+ 1 1)' , nl.
check value: 'AC-11 after an error the next form still evaluates' value: r first value: '> > 2' , nl , '> ' , nl.
check value: 'AC-11 the error is reported on err' value: (r second beginsWith: 'error: ') value: true.
r := repl value: ''.
check value: 'AC-12 empty input ends cleanly' value: r first value: '> ' , nl.
r := repl value: '(+ 1' , nl.
check value: 'AC-12 input ending mid-datum is reported' value: (r second includesSubstring: 'unexpected end of input') value: true.
r := repl value: '(display "hi")' , nl.
check value: 'REPL display output goes to the REPL stream' value: r first value: '> hi> ' , nl.
r := repl value: '1 2 3' , nl.
check value: 'REPL evaluates several forms on one line' value: r first value: '> 1' , nl , '2' , nl , '3' , nl , '> ' , nl.

"reader: errors know whether more input could complete them"
checkErr value: 'reader: unterminated list is incomplete' value: LispReadError value: [
	[LispReader read: '(1 2'] on: LispReadError do: [:e | e isIncomplete ifTrue: [e pass]]].
check value: 'reader: stray close paren is not incomplete'
	value: ([LispReader read: '1)'. #none] on: LispReadError do: [:e | e isIncomplete])
	value: false.

"AC-15 load"
tmp := FileLocator imageDirectory / 'coglisp-load-test.lisp'.
tmp writeStreamDo: [:s | s nextPutAll: '(define (loaded-fn x) (* x 3))'].
check value: 'AC-15 load evaluates the file' value: (evAll value: '(load "' , (tmp fullName copyReplaceAll: '\' with: '/') , '") (loaded-fn 4)') value: 12.
tmp ensureDelete.
[ev value: '(load "no/such/file.lisp")'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-5-shell.lisp)"

"AC-16 disassemble"
evAll value: '(define (sq n) (* n n))'.
check value: 'AC-16 disassemble prints bytecode' value: ((captured value: '(disassemble sq)') includesSubstring: 'send:') value: true.

"AC-18..20 source retention"
check value: 'AC-18 define keeps its exact text, comment and line break included'
	value: (evAll value: '(define (sq2 n) ; square it' , nl , '  (* n n))' , nl , '(procedure-source sq2)')
	value: '(define (sq2 n) ; square it' , nl , '  (* n n))'.

[evAll value: '(define (adder n) (lambda (x) (+ x n))) (procedure-source (adder 1))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-5-shell.lisp)"

[evAll value: '(define f (lambda (a) a)) (procedure-source f)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-5-shell.lisp)"


h finish
]
	on: Error
	do: [:e | h harnessError: e].

Smalltalk snapshot: false andQuit: true.
!
