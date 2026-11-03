"============================================================================
 cog-lisp : Phase 4 acceptance suite  (specs/phase-4-runtime-primitives.md, AC-1..20)
 Headless; PASS/FAIL per check, final RESULT line, then quits.
 Bang-suffixed names are written with a doubled bang for the chunk reader.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-4-runtime.st
 ============================================================================"

"--- Chunk 1: load all four packages into this fresh image -----------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
(dir / 'coglisp-reader.st') fileIn.
(dir / 'coglisp-core.st') fileIn.
(dir / 'coglisp-compiler.st') fileIn.
(dir / 'coglisp-runtime.st') fileIn.
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
check value: 'AC-1 procedure? of lambda' value: (ev value: '(procedure? (lambda (x) x))') value: true.

"AC-2 fixed arity"
check value: 'AC-2 fixed arity call' value: (ev value: '((lambda (x y) (+ x y)) 2 3)') value: 5.
checkErrClass value: 'AC-2 wrong count signals LispArityError' value: LispArityError value: [ev value: '((lambda (x y) x) 1)'].

"AC-3 rest parameters"
check value: 'AC-3 (lambda args args)' value: (ev value: '((lambda args args) 1 2 3)') value: (lst value: '(1 2 3)').
check value: 'AC-3 (lambda (a . r) r)' value: (ev value: '((lambda (a . r) r) 1 2 3)') value: (lst value: '(2 3)').
check value: 'AC-3 empty rest' value: (ev value: '((lambda (a . r) r) 9)') value: LispEmptyList default.
checkErrClass value: 'AC-3 too few for variadic signals' value: LispArityError value: [ev value: '((lambda (a b . r) r) 1)'].

"AC-4 variadic define"
check value: 'AC-4 variadic define' value: (evAll value: '(define (f a . rest) rest) (f 1 2 3)') value: (lst value: '(2 3)').

"AC-5 cons / car / cdr"
check value: 'AC-5 car of cons' value: (ev value: '(car (cons 1 2))') value: 1.
check value: 'AC-5 cdr of cons' value: (ev value: '(cdr (cons 1 2))') value: 2.

"AC-6 list / length / null?"
check value: 'AC-6 list' value: (ev value: '(list 1 2 3)') value: (lst value: '(1 2 3)').
check value: 'AC-6 length' value: (ev value: '(length (list 1 2 3))') value: 3.
check value: 'AC-6 null? of (list)' value: (ev value: '(null? (list))') value: true.

"AC-7 append / reverse"
check value: 'AC-7 append' value: (ev value: '(append ''(1 2) ''(3 4))') value: (lst value: '(1 2 3 4)').
check value: 'AC-7 reverse' value: (ev value: '(reverse ''(1 2 3))') value: (lst value: '(3 2 1)').

"AC-8 set-car / set-cdr mutate a pair"
check value: 'AC-8 set-car' value: (evAll value: '(define p (cons 1 2)) (set-car!! p 10) p') value: (lst value: '(10 . 2)').
check value: 'AC-8 set-cdr' value: (evAll value: '(define q (cons 1 2)) (set-cdr!! q 20) q') value: (lst value: '(1 . 20)').

"AC-9 map"
check value: 'AC-9 map square' value: (ev value: '(map (lambda (x) (* x x)) ''(1 2 3))') value: (lst value: '(1 4 9)').

"AC-10 variadic + and *"
check value: 'AC-10 (+ 1 2 3)' value: (ev value: '(+ 1 2 3)') value: 6.
check value: 'AC-10 (+)' value: (ev value: '(+)') value: 0.
check value: 'AC-10 (* 2 3 4)' value: (ev value: '(* 2 3 4)') value: 24.
check value: 'AC-10 (*)' value: (ev value: '(*)') value: 1.

"AC-11 - and /"
check value: 'AC-11 (- 5)' value: (ev value: '(- 5)') value: -5.
check value: 'AC-11 (- 10 3 2)' value: (ev value: '(- 10 3 2)') value: 5.

"AC-12 chained comparison"
check value: 'AC-12 (< 1 2 3)' value: (ev value: '(< 1 2 3)') value: true.
check value: 'AC-12 (< 1 3 2)' value: (ev value: '(< 1 3 2)') value: false.
check value: 'AC-12 (= 2 2 2)' value: (ev value: '(= 2 2 2)') value: true.

"AC-13 modulo / quotient / zero?"
check value: 'AC-13 (modulo 7 3)' value: (ev value: '(modulo 7 3)') value: 1.
check value: 'AC-13 (quotient 7 2)' value: (ev value: '(quotient 7 2)') value: 3.
check value: 'AC-13 (zero? 0)' value: (ev value: '(zero? 0)') value: true.

"AC-14 eq? / equal? / not"
check value: 'AC-14 equal? lists' value: (ev value: '(equal? ''(1 2) ''(1 2))') value: true.
check value: 'AC-14 eq? symbols' value: (ev value: '(eq? ''a ''a)') value: true.
check value: 'AC-14 (not #f)' value: (ev value: '(not #f)') value: true.
check value: 'AC-14 (not 0)' value: (ev value: '(not 0)') value: false.

"AC-15 type predicates callable"
check value: 'AC-15 number?' value: (ev value: '(number? 3)') value: true.
check value: 'AC-15 symbol?' value: (ev value: '(symbol? ''x)') value: true.
check value: 'AC-15 procedure? car' value: (ev value: '(procedure? car)') value: true.

"AC-16 apply"
check value: 'AC-16 (apply + (list 1 2 3))' value: (ev value: '(apply + (list 1 2 3))') value: 6.

"AC-17 applying a non-procedure"
checkErrClass value: 'AC-17 (5 6) signals LispError' value: LispError value: [ev value: '(5 6)'].

"AC-18 end-to-end: recursive list sum"
check value: 'AC-18 (sum (1 2 3 4 5)) = 15'
	value: (evAll value: '(define (sum lst) (if (null? lst) 0 (+ (car lst) (sum (cdr lst))))) (sum ''(1 2 3 4 5))')
	value: 15.

"AC-19 end-to-end: compose"
check value: 'AC-19 compose = 25'
	value: (evAll value: '(define (compose f g) (lambda (x) (f (g x)))) ((compose (lambda (x) (* x x)) (lambda (x) (+ x 1))) 4)')
	value: 25.

"AC-20 regression: key Phase 3 cases under the new convention"
check value: 'AC-20 fact 5' value: (evAll value: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)') value: 120.
check value: 'AC-20 closure capture' value: (ev value: '(((lambda (x) (lambda (y) (+ x y))) 2) 3)') value: 5.

h finish
]
	on: Error
	do: [:e | h harnessError: e].

Smalltalk snapshot: false andQuit: true.
!
