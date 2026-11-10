"============================================================================
 cog-lisp : Phase 6 acceptance suite  (specs/05-phase-6-optimization.md, AC-1..12)
 Proper tail calls and the compiler optimizations, checked for correctness.
 Speed is measured separately by bench\run-benchmarks.bat.
 The set-bang form is written with a doubled bang for the chunk reader.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-6-tail-calls.st
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| h out check checkErr ev lst core |
h := LispTestHarness new.
out := [:s | h say: s].
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
check := h checkBlock.
checkErr := h checkErrBlock.

LispPrimitives installDefault.

"Correctness checks that must hold with every optimization on or off (AC-12).
 Loop sizes stay small so they also pass without tail calls."
core := [:tag |
	check value: tag , ' fact 20' value: (ev value: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 20)') value: 2432902008176640000.
	check value: tag , ' self loop' value: (ev value: '(define (cnt n acc) (if (= n 0) acc (cnt (- n 1) (+ acc 1)))) (cnt 500 0)') value: 500.
	check value: tag , ' mutual recursion' value: (ev value: '(define (e1 n) (if (= n 0) #t (o1 (- n 1)))) (define (o1 n) (if (= n 0) #f (e1 (- n 1)))) (e1 300)') value: true.
	check value: tag , ' closure capture' value: (ev value: '(((lambda (x) (lambda (y) (+ x y))) 2) 3)') value: 5.
	check value: tag , ' let shadowing' value: (ev value: '(let ((x 1)) (let ((x 2)) x))') value: 2.
	check value: tag , ' let set-bang' value: (ev value: '(let ((x 1)) (set!! x (+ x 1)) x)') value: 2.
	check value: tag , ' quote' value: (ev value: '''(1 (2 . 3))') value: (lst value: '(1 (2 . 3))').
	check value: tag , ' forward reference' value: (ev value: '(define (fw1) (fw2 4)) (define (fw2 x) (* x 10)) (fw1)') value: 40.
	check value: tag , ' five arguments' value: (ev value: '((lambda (a b c d e) (+ a b c d e)) 1 2 3 4 5)') value: 15.
	check value: tag , ' rest arguments' value: (ev value: '((lambda (a . r) r) 1 2 3)') value: (lst value: '(2 3)').
	check value: tag , ' map with tail-calling lambda' value: (ev value: '(define (inc x) (+ x 1)) (map (lambda (x) (inc x)) ''(1 2 3))') value: (lst value: '(2 3 4)')].

[
out value: '== cog-lisp Phase 6 : tail calls & optimization =='.

"AC-1 self tail calls run as loops, in constant stack"
[ev value: '(define (loop n acc) (if (= n 0) acc (loop (- n 1) (+ acc 1)))) (loop 1000000 0)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

check value: 'AC-1 stack depth constant across iterations'
	value: (ev value: '(define (d n first) (if (= n 0) (list first (stack-depth)) (d (- n 1) (if (= n 1000) (stack-depth) first)))) (d 1000 0)') lispElements asSet size
	value: 1.

"AC-2 mutual tail calls use the trampoline, in constant stack"
[ev value: '(define (ev? n) (if (= n 0) #t (od? (- n 1)))) (define (od? n) (if (= n 0) #f (ev? (- n 1)))) (ev? 100000)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (pe n) (if (= n 0) (stack-depth) (po (- n 1)))) (define (po n) (if (= n 0) (stack-depth) (pe (- n 1)))) (= (pe 10) (pe 10000))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-3 tail position through if, begin and let"
check value: 'AC-3 if / begin / let in tail position, constant stack'
	value: (ev value: '(define (b n samples) (begin 1 (let ((m (- n 1))) (if (= n 0) samples (b m (if (= n 500) (cons (stack-depth) samples) (if (= n 2) (cons (stack-depth) samples) samples))))))) (b 500 (list))') lispElements asSet size
	value: 1.
[ev value: '(define (z n) (if (> n 0) (if (= n 1) (z 0) (z (- n 1))) (quote done))) (z 100000)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-4 non-tail calls are unaffected"
[ev value: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 20)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (nt n) (if (= n 0) (stack-depth) (+ 0 (nt (- n 1))))) (< (nt 10) (nt 100))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-5 redefinition: an old procedure that self-tail-calls its name reaches the new definition"
[ev value: '(define (rf n) (if (= n 0) (quote old) (rf (- n 1)))) (define saved rf) (define (rf n) (quote new)) (saved 3)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (rg n) (if (= n 0) (quote ok) (rg (- n 1)))) (rg 100000)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-6 a bounce never escapes through map, for-each or apply"
ev value: '(define (inc x) (+ x 1))'.

[ev value: '(define acc 0) (for-each (lambda (x) (set!! acc (inc (+ acc x)))) ''(1 2 3)) acc'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (mk) (inc 1)) (mk)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (ap n) (if (= n 0) (stack-depth) (apply ap (list (- n 1))))) (= (ap 10) (ap 10000))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (tp a b) (+ a b)) (tp 2 3)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-7 errors still occur through fast calls and tail calls"

[ev value: '(define (t1) ((lambda (x) x))) (t1)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (t2) (5 6)) (t2)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-8 fast calls of every shape"

"AC-9 global cells"
[ev value: '(define (fwa) (fwb 4)) (define (fwb x) (* x 10)) (fwa)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define v 1) (define (get-v) v) (define v 2) (get-v)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (bad) not-yet-defined-anywhere) (bad)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(set!! also-not-defined 1)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

check value: 'AC-9 environment API: lookup' value: (LispEnvironment default lookup: (LispSymbol named: 'v')) value: 2.
check value: 'AC-9 environment API: a referenced-but-undefined name is not bound'
	value: (LispEnvironment default isBound: (LispSymbol named: 'not-yet-defined-anywhere'))
	value: false.
check value: 'AC-9 environment API: at:ifAbsent: on an unbound cell'
	value: (LispEnvironment default at: (LispSymbol named: 'not-yet-defined-anywhere') ifAbsent: [#absent])
	value: #absent.

"AC-10 quoted constants are literals"
[ev value: '(define (k) ''(1 2)) (eq? (k) (k))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-11 let still scopes correctly"

[ev value: '(define (mk n acc) (if (= n 0) acc (mk (- n 1) (cons (let ((k n)) (lambda () k)) acc)))) (map (lambda (f) (f)) (mk 3 (list)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

"AC-19..23 guarded inlining of primitives (section 11)"

[ev value: '(define (in-tail a b) (* a b)) (in-tail 6 7)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (poly x) (+ (* x (+ (* x 2) 3)) 4)) (poly 5)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (bad-car x) (car x)) (bad-car 5)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (add2 a b) (+ a b)) (define orig-plus +) (define (+ a b) (quote plus)) (add2 1 2)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (add3 a b) (+ a b)) (add3 1 2)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define + orig-plus) (list (add2 1 2) (add3 1 2))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

[ev value: '(define (wide p) (list (car p) (+ (car p) (cdr p)) (* (car p) (car p)) (- (cdr p) (car p)) (+ (car p) (car p)) (+ (cdr p) (cdr p)) (* (cdr p) (car p)) (+ (car p) (* 2 (cdr p))) (- (car p) (+ 1 (cdr p))) (+ (+ (car p) 1) (+ (cdr p) 1)) (* (+ (car p) 1) (- (cdr p) 1)) (+ (car p) (+ (car p) (+ (car p) (cdr p)))) (- (* (car p) 3) (* (cdr p) 2)) (+ (* (car p) (car p)) (* (cdr p) (cdr p))))) (wide (cons 2 3))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-6-tail-calls.lisp)"

ev value: '(define (inl a b) (+ a b))'.
check value: 'AC-23 the compiled code contains the + send'
	value: (((LispEnvironment default lookup: (LispSymbol named: 'inl')) block compiledBlock symbolic) includesSubstring: 'send: +')
	value: true.

"AC-12 every correctness check, with all optimizations on and with each one off"
core value: 'AC-12 all on:'.
LispCompiler allOptions do: [:opt |
	LispCompiler withoutOptions: { opt } do: [core value: 'AC-12 without ' , opt , ':']].
check value: 'AC-12 options restored afterwards' value: LispCompiler defaultOptions size value: LispCompiler allOptions size.
h finish
]
	on: Error
	do: [:e | h harnessError: e].

Smalltalk snapshot: false andQuit: true.
!
