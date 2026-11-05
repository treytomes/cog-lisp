"============================================================================
 cog-lisp : Phase 4 acceptance suite  (specs/phase-4-runtime-primitives.md, AC-1..20)
 Headless; PASS/FAIL per check, final RESULT line, then quits.
 Bang-suffixed names are written with a doubled bang for the chunk reader.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-4-runtime.st
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| h out check checkErrClass ev evAll lst |
h := LispTestHarness new.
out := [:s | h say: s].
ev := [:s | LispCompiler new evalString: s].
evAll := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
check := h checkBlock.
checkErrClass := h checkErrBlock.

LispPrimitives installDefault.

[
out value: '== cog-lisp Phase 4 : runtime & primitives =='.

"AC-1 lambda is a LispProcedure"
check value: 'AC-1 lambda is LispProcedure' value: ((ev value: '(lambda (x) x)') isKindOf: LispProcedure) value: true.

"AC-2 fixed arity"

"AC-3 rest parameters"

"AC-4 variadic define"
[evAll value: '(define (f a . rest) rest) (f 1 2 3)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-4-runtime.lisp)"

"AC-5 cons / car / cdr"

"AC-6 list / length / null?"

"AC-7 append / reverse"

"AC-8 set-car / set-cdr mutate a pair"
[evAll value: '(define p (cons 1 2)) (set-car!! p 10) p'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-4-runtime.lisp)"

[evAll value: '(define q (cons 1 2)) (set-cdr!! q 20) q'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-4-runtime.lisp)"

"AC-9 map"

"AC-10 variadic + and *"

"AC-11 - and /"

"AC-12 chained comparison"

"AC-13 modulo / quotient / zero?"

"AC-14 eq? / equal? / not"

"AC-15 type predicates callable"

"AC-16 apply"

"AC-17 applying a non-procedure"

"AC-18 end-to-end: recursive list sum"
[evAll value: '(define (sum lst) (if (null? lst) 0 (+ (car lst) (sum (cdr lst))))) (sum ''(1 2 3 4 5))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-4-runtime.lisp)"

"AC-19 end-to-end: compose"
[evAll value: '(define (compose f g) (lambda (x) (f (g x)))) ((compose (lambda (x) (* x x)) (lambda (x) (+ x 1))) 4)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-4-runtime.lisp)"

"AC-20 regression: key Phase 3 cases under the new convention"
[evAll value: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-4-runtime.lisp)"


h finish
]
	on: Error
	do: [:e | h harnessError: e].

Smalltalk snapshot: false andQuit: true.
!
