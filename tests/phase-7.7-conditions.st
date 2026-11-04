"============================================================================
 cog-lisp : Phase 7.7 acceptance suite  (specs/phase-7.7-conditions-restarts.md,
 AC-1..16). AC-12 is tests/runner/abort.*; AC-17 is every other suite. The
 examples (examples/conditions-*.lisp, examples/restarts.lisp) run in the
 runner suite. Every bang in Lisp text is doubled for the chunk reader.
 ============================================================================"

"--- Chunk 1: load the packages and the harness -----------------------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn].
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
h check: 'AC-1 message and written irritants' actual: (msg value: '(error "bad size:" 5 (quote x) "s")') expected: 'bad size: 5 x "s"'.
h check: 'AC-1 accessors'
	actual: (ev value: '(guard (e (#t (list (error-object? e) (error-object-message e) (error-object-irritants e)))) (error "bad size:" 5 (quote x)))')
	expected: (lst value: '(#t "bad size:" (5 x))').
h check: 'AC-1 no irritants' actual: (ev value: '(guard (e (#t (error-object-irritants e))) (error "plain"))') expected: LispEmptyList default.

"AC-2 guard catches everything raisable"
h check: 'AC-2 a raised symbol' actual: (ev value: '(guard (e ((symbol? e) e)) (raise (quote oops)))') expected: (sym value: 'oops').
h check: 'AC-2 a raised list' actual: (ev value: '(guard (e ((pair? e) (car e))) (raise (list 1 2)))') expected: 1.
h check: 'AC-2 car of a number' actual: (ev value: '(guard (e ((error-object? e) (error-object-message e))) (car 5))') expected: 'car: not a pair: 5'.
h check: 'AC-2 division by zero' actual: (ev value: '(guard (e ((error-object? e) (error-object-message e))) (/ 1 0))') expected: 'division by zero'.
h check: 'AC-2 a send not understood' actual: (ev value: '(guard (e ((error-object? e) (error-object-message e))) [3 frobnicate])') expected: '3 does not understand #frobnicate'.
h check: 'AC-2 =>' actual: (ev value: '(guard (e ((assq (quote a) e) => cdr)) (raise (list (cons (quote a) 42))))') expected: 42.
h check: 'AC-2 else' actual: (ev value: '(guard (e ((string? e) 1) (else 2)) (raise 3))') expected: 2.
h check: 'AC-2 no matching clause reaches the outer guard'
	actual: (ev value: '(guard (o (#t (list (quote outer) o))) (guard (i ((string? i) (quote inner))) (raise 7)))')
	expected: (lst value: '(outer 7)').
h check: 'AC-2 uncaught, a raise is reported' actual: (msg value: '(raise (list 1 2))') expected: 'uncaught raise: (1 2)'.

"AC-3 guard values and nesting"
h check: 'AC-3 the body''s value when nothing is raised' actual: (ev value: '(guard (e (#t 0)) (+ 1 2))') expected: 3.
h check: 'AC-3 the innermost guard catches first' actual: (ev value: '(guard (o (#t (quote outer))) (guard (i (#t (quote inner))) (raise 1)))') expected: (sym value: 'inner').

"AC-4 with-exception-handler"
h check: 'AC-4 raise-continuable resumes with the handler''s value'
	actual: (ev value: '(with-exception-handler (lambda (c) 10) (lambda () (+ 1 (raise-continuable (quote need)))))') expected: 11.
h check: 'AC-4 the handler runs before unwinding: dynamic-wind after has not run'
	actual: (ev value: '(define w4 (list)) (with-exception-handler (lambda (c) (set!! w4 (cons (quote handler) w4)) 0) (lambda () (dynamic-wind (lambda () #f) (lambda () (raise-continuable 1)) (lambda () (set!! w4 (cons (quote after) w4)))))) (reverse w4)')
	expected: (lst value: '(handler after)').
h check: 'AC-4 ... and it sees restarts established below it'
	actual: (ev value: '(with-exception-handler (lambda (c) (use-value (map restart-name (compute-restarts)))) (lambda () (restart-case (error "x") (use-value (v) v) (other () 0))))')
	expected: (lst value: '(use-value other)').
h check: 'AC-4 returning from a plain raise is an error' actual: (msg value: '(with-exception-handler (lambda (c) 1) (lambda () (raise (quote x))))') expected: 'handler returned from a non-continuable raise'.
h check: 'AC-4 a raise in the handler goes to the next handler out'
	actual: (ev value: '(guard (e (#t (list (quote outer) e))) (with-exception-handler (lambda (c) (raise (quote from-handler))) (lambda () (raise (quote first)))))')
	expected: (lst value: '(outer from-handler)').

"AC-5 predicates and report"
h check: 'AC-5 condition?' actual: (ev value: '(list (guard (e (#t (condition? e))) (car 5)) (condition? 5) (guard (e (#t (condition? e))) (raise 5)))') expected: (lst value: '(#t #f #f)').
h check: 'AC-5 read-error?' actual: (ev value: '(guard (e (#t (read-error? e))) (eval [(smalltalk LispReader) read: "(1 2"]))') expected: true.
h check: 'AC-5 file-error?' actual: (ev value: '(guard (e (#t (file-error? e))) (load "no-such-file.lisp"))') expected: true.
h check: 'AC-5 condition-report' actual: (ev value: '(guard (e (#t (condition-report e))) (error "bad:" 1 2))') expected: 'bad: 1 2'.

"AC-6 handlers do not see notifications or warnings"
h check: 'AC-6 a Notification passes a guard'
	actual: ([ev value: '(guard (e (#t (quote caught))) [[(smalltalk Notification) new] signal] (quote passed))'] on: Notification do: [:n | n resume: nil])
	expected: (sym value: 'passed').
h check: 'AC-6 a Warning passes with-exception-handler'
	actual: ([ev value: '(with-exception-handler (lambda (c) (quote caught)) (lambda () [[(smalltalk Warning) new] signal] (quote passed)))'] on: Warning do: [:w | w resume: nil])
	expected: (sym value: 'passed').

"AC-7 dynamic-wind"
h check: 'AC-7 normal exit' actual: (ev value: '(define w7 (list)) (dynamic-wind (lambda () (set!! w7 (cons 1 w7))) (lambda () (set!! w7 (cons 2 w7))) (lambda () (set!! w7 (cons 3 w7)))) (reverse w7)') expected: (lst value: '(1 2 3)').
h check: 'AC-7 an error unwinding to a guard: after runs before the clause'
	actual: (ev value: '(define w7b (list)) (guard (e (#t (reverse w7b))) (dynamic-wind (lambda () (set!! w7b (cons (quote before) w7b))) (lambda () (error "x")) (lambda () (set!! w7b (cons (quote after) w7b)))))')
	expected: (lst value: '(before after)').
h check: 'AC-7 a restart unwinding through it'
	actual: (ev value: '(define w7c (list)) (restart-case (dynamic-wind (lambda () #f) (lambda () (invoke-restart (quote out) 9)) (lambda () (set!! w7c (cons (quote after) w7c)))) (out (v) (list v w7c)))')
	expected: (lst value: '(9 (after))').

"AC-8 restart-case"
h check: 'AC-8 a restart from a handler gives the restart-case its value'
	actual: (ev value: '(restart-case (+ 1 (with-exception-handler (lambda (c) (invoke-restart (quote use-value) 41)) (lambda () (error "boom")))) (use-value (v) v))')
	expected: 41.
h check: 'AC-8 several arguments' actual: (ev value: '(restart-case (invoke-restart (quote both) 3 4) (both (a b) (* a b)))') expected: 12.
h check: 'AC-8 no restart invoked: the form''s value' actual: (ev value: '(restart-case (+ 2 3) (never () 0))') expected: 5.
h check: 'AC-8 the restart body runs after unwinding (its own restarts are gone)'
	actual: (ev value: '(restart-case (invoke-restart (quote r)) (r () (find-restart (quote r))))')
	expected: false.

"AC-9 introspection"
h check: 'AC-9 compute-restarts, innermost first'
	actual: (ev value: '(restart-case (restart-case (map restart-name (compute-restarts)) (inner () 0)) (outer () 0))')
	expected: (lst value: '(inner outer)').
h check: 'AC-9 find-restart' actual: (ev value: '(restart-case (restart-name (find-restart (quote here))) (here () 0))') expected: (sym value: 'here').
h check: 'AC-9 find-restart of none' actual: (ev value: '(find-restart (quote nope))') expected: false.
h check: 'AC-9 invoke-restart of an inactive restart' actual: (msg value: '(invoke-restart (quote nope))') expected: 'invoke-restart: no active restart named nope'.
h check: 'AC-9 a restart object, used after its restart-case ended'
	actual: (msg value: '(define saved (restart-case (find-restart (quote gone)) (gone () 0))) (invoke-restart saved)')
	expected: 'invoke-restart: restart is not active: gone'.

"AC-10 transfers pass Smalltalk handlers and run ensure: blocks"
h check: 'AC-10 through on: Error do: and ensure:'
	actual: (ev value: '(define w10 (list)) (restart-case [(lambda () [(lambda () (invoke-restart (quote out) 1)) ensure: (lambda () (set!! w10 (cons (quote ensured) w10)))]) on: (smalltalk Error) do: (lambda (e) (quote intercepted))] (out (v) (list v w10)))')
	expected: (lst value: '(1 (ensured))').

"AC-11 an unbound variable's restarts"
h check: 'AC-11 use-value' actual: (ev value: '(with-exception-handler (lambda (c) (use-value 0)) (lambda () (+ unbound-a 1)))') expected: 1.
h check: 'AC-11 store-value' actual: (ev value: '(with-exception-handler (lambda (c) (store-value 5)) (lambda () (+ unbound-b 1)))') expected: 6.
h check: 'AC-11 ... defines the global' actual: (ev value: 'unbound-b') expected: 5.
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
h check: 'AC-16 handler-case by type'
	actual: (ev value: '(list (handler-case (/ 1 0) (ZeroDivide (c) (quote zd))) (handler-case (car 5) (error (c) (quote err))) (handler-case (raise 1) (t (c) c)))')
	expected: (lst value: '(zd err 1)').
h check: 'AC-16 handler-case with no matching type passes it on'
	actual: (ev value: '(handler-case (handler-case (car 5) (ZeroDivide () (quote zd))) (error () (quote outer)))')
	expected: (sym value: 'outer').
h check: 'AC-16 handler-bind declines by returning, then an outer handler acts'
	actual: (ev value: '(defvar seen16 nil) (handler-case (handler-bind ((error (lambda (c) (push (quote saw) seen16)))) (car 5)) (error () (list (quote outer) seen16)))')
	expected: (lst value: '(outer (saw))').
h check: 'AC-16 handler-bind choosing a restart'
	actual: (ev value: '(handler-bind ((error (lambda (c) (invoke-restart (quote use-value) -1)))) (restart-case (error "x") (use-value (v) v)))')
	expected: -1.
h check: 'AC-16 ignore-errors' actual: (ev value: '(list (ignore-errors (car 5)) (ignore-errors 7))') expected: (lst value: '(() 7)').
h check: 'AC-16 unwind-protect'
	actual: (ev value: '(defvar log16 nil) (ignore-errors (unwind-protect (error "x") (push (quote cleanup) log16))) log16')
	expected: (lst value: '(cleanup)').

"review C-18"
h check: 'C-18 unquote-splicing of a non-list is a LispError' actual: ([ev value: '`(1 ,@5)'. #none] on: LispError do: [:e | e messageText]) expected: 'unquote-splicing: not a list'.

h finish
] on: Error do: [:e | h harnessError: e].
!
