"============================================================================
 cog-lisp : Phase 7.7 acceptance suite  (specs/10-phase-7.7-conditions-restarts.md,
 AC-1..16). AC-12 is tests/runner/abort.*; AC-17 is every other suite. The
 examples (examples/conditions-*.lisp, examples/restarts.lisp) run in the
 runner suite. Every bang in Lisp text is doubled for the chunk reader.
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h ev lst msg sym repl lines |
h := LispTestHarness new.
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
sym := [:s | LispSymbol named: s].
msg := [:s | [ev value: s. #none] on: Error do: [:e | LispError describe: e]].
"{ stdout. stderr } of an interactive REPL session over input"
repl := [:input | | o e |
	o := WriteStream on: String new. e := WriteStream on: String new.
	(LispRepl in: input readStream out: o err: e) interactive: true; run.
	{ o contents. e contents }].

[
h say: '== cog-lisp Phase 7.7 : conditions & restarts =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (Smalltalk imageDirectory parent / 'lib' / 'core.lisp') fullName.

"AC-1 error and its accessors"

"AC-2 guard catches everything raisable"

"AC-3 guard values and nesting"

"AC-4 with-exception-handler"

[ev value: '(define w4 (list)) (with-exception-handler (lambda (c) (set!! w4 (cons (quote handler) w4)) 0) (lambda () (dynamic-wind (lambda () #f) (lambda () (raise-continuable 1)) (lambda () (set!! w4 (cons (quote after) w4)))))) (reverse w4)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.7-conditions.lisp)"

h check: 'AC-4 ... and it sees restarts established below it'
	actual: (ev value: '(with-exception-handler (lambda (c) (use-value (map restart-name (compute-restarts)))) (lambda () (restart-case (error "x") (use-value (v) v) (other () 0))))')
	expected: (lst value: '(use-value other)').

"AC-5 predicates and report"

[ev value: '(guard (e (#t (file-error? e))) (load "no-such-file.lisp"))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.7-conditions.lisp)"

"AC-6 handlers do not see notifications or warnings"
h check: 'AC-6 a Notification passes a guard'
	actual: ([ev value: '(guard (e (#t (quote caught))) [[(smalltalk Notification) new] signal] (quote passed))'] on: Notification do: [:n | n resume: nil])
	expected: (sym value: 'passed').
h check: 'AC-6 a Warning passes with-exception-handler'
	actual: ([ev value: '(with-exception-handler (lambda (c) (quote caught)) (lambda () [[(smalltalk Warning) new] signal] (quote passed)))'] on: Warning do: [:w | w resume: nil])
	expected: (sym value: 'passed').

"AC-7 dynamic-wind"
[ev value: '(define w7 (list)) (dynamic-wind (lambda () (set!! w7 (cons 1 w7))) (lambda () (set!! w7 (cons 2 w7))) (lambda () (set!! w7 (cons 3 w7)))) (reverse w7)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.7-conditions.lisp)"

[ev value: '(define w7b (list)) (guard (e (#t (reverse w7b))) (dynamic-wind (lambda () (set!! w7b (cons (quote before) w7b))) (lambda () (error "x")) (lambda () (set!! w7b (cons (quote after) w7b)))))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.7-conditions.lisp)"

[ev value: '(define w7c (list)) (restart-case (dynamic-wind (lambda () #f) (lambda () (invoke-restart (quote out) 9)) (lambda () (set!! w7c (cons (quote after) w7c)))) (out (v) (list v w7c)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.7-conditions.lisp)"

"AC-8 restart-case"

"AC-9 introspection"
h check: 'AC-9 compute-restarts, innermost first'
	actual: (ev value: '(restart-case (restart-case (map restart-name (compute-restarts)) (inner () 0)) (outer () 0))')
	expected: (lst value: '(inner outer)').

[ev value: '(define saved (restart-case (find-restart (quote gone)) (gone () 0))) (invoke-restart saved)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.7-conditions.lisp)"

"AC-10 transfers pass Smalltalk handlers and run ensure: blocks"
[ev value: '(define w10 (list)) (restart-case [(lambda () [(lambda () (invoke-restart (quote out) 1)) ensure: (lambda () (set!! w10 (cons (quote ensured) w10)))]) on: (smalltalk Error) do: (lambda (e) (quote intercepted))] (out (v) (list v w10)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.7-conditions.lisp)"

"AC-11 an unbound variable's restarts"

h check: 'AC-11 the restarts on offer' actual: (ev value: '(with-exception-handler (lambda (c) (use-value (map restart-name (compute-restarts)))) (lambda () unbound-c))') expected: (lst value: '(use-value store-value)').

"AC-13 to AC-15 the break loop. lines joins its strings with line feeds, so a
 prompt's trailing space cannot be lost from the expected text."
lines := [:parts | String streamContents: [:s | parts do: [:p | s nextPutAll: p] separatedBy: [s nextPut: Character lf]]].
h check: 'AC-13 an error opens 1>, use-value continues the computation'
	actual: (repl value: (lines value: #('(+ undefined-z 1)' '(use-value 41)' '(+ 1 1)' '')))
	expected: { lines value: #('> 1> 42' '> 2' '> ' ''). lines value: #('error: unbound variable: undefined-z' 'restarts: use-value store-value abort' '') }.
h check: 'AC-14 an error at 1> opens 2>; (abort) returns to >'
	actual: (repl value: (lines value: #('(+ undefined-z 1)' '(car 5)' '(abort)' '(quote back)' ''))) first
	expected: (lines value: #('> 1> 2> > back' '> ' '')).
h check: 'AC-14 end of input in the break loop ends the session'
	actual: (repl value: (lines value: #('(+ undefined-z 1)' ''))) first
	expected: (lines value: #('> 1> > ' '')).
h check: 'AC-14 a compile error does not open a break loop'
	actual: (repl value: (lines value: #('(lambda)' '1' ''))) first
	expected: (lines value: #('> > 1' '> ' '')).
h check: 'AC-15 piped input (not interactive) reports and goes on'
	actual: ([:input | | o e | o := WriteStream on: String new. e := WriteStream on: String new.
		(LispRepl in: input readStream out: o err: e) run. { o contents. e contents }] value: (lines value: #('(+ undefined-z 1)' '(+ 1 1)' '')))
	expected: { lines value: #('> > 2' '> ' ''). lines value: #('error: unbound variable: undefined-z' '') }.

h check: 'AC-13 the break loop writes to the real stderr (LispTextOutput), not only to a WriteStream'
	actual: ([:o | (LispRepl in: (lines value: #('(+ undefined-q 1)' '')) readStream out: (WriteStream on: String new) err: o)
			interactive: true; run. #ok] value: (LispTextOutput onStd: -12 stream: Stdio stderr))
	expected: #ok.

"AC-16 the CL library"
LispCompiler new evalFile: (Smalltalk imageDirectory parent / 'lib' / 'cl.lisp') fullName.

"review C-18"
h check: 'C-18 unquote-splicing of a non-list is a LispError' actual: ([ev value: '`(1 ,@5)'. #none] on: LispError do: [:e | e messageText]) expected: 'unquote-splicing: not a list'.
h finish
] on: Error do: [:e | h harnessError: e].
!
