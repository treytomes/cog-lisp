"============================================================================
 cog-lisp : Phase 6 acceptance suite  (specs/phase-6-optimization.md, AC-1..12)
 Proper tail calls and the compiler optimizations, checked for correctness.
 Speed is measured separately by bench\run-benchmarks.bat.
 The set-bang form is written with a doubled bang for the chunk reader.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-6-tail-calls.st
 ============================================================================"

"--- Chunk 1: load all five packages into this fresh image -----------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn].
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| out pass total check checkErr ev lst core |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
pass := 0.
total := 0.
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
check := [:label :actual :expected |
	total := total + 1.
	(LispCore equal: actual with: expected)
		ifTrue: [pass := pass + 1. out value: '  PASS  ' , label]
		ifFalse: [out value: '  FAIL  ' , label , '  got=' , ([LispPrinter writeString: actual] on: Error do: [:e | actual printString]) , '  want=' , (LispPrinter writeString: expected)]].
checkErr := [:label :errClass :blk |
	total := total + 1.
	[blk value. out value: '  FAIL  ' , label , ' (no error raised)']
		on: errClass
		do: [:e | pass := pass + 1. out value: '  PASS  ' , label]].

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
check value: 'AC-1 loop of 1,000,000' value: (ev value: '(define (loop n acc) (if (= n 0) acc (loop (- n 1) (+ acc 1)))) (loop 1000000 0)') value: 1000000.
check value: 'AC-1 stack depth constant across iterations'
	value: (ev value: '(define (d n first) (if (= n 0) (list first (stack-depth)) (d (- n 1) (if (= n 1000) (stack-depth) first)))) (d 1000 0)') lispElements asSet size
	value: 1.

"AC-2 mutual tail calls use the trampoline, in constant stack"
check value: 'AC-2 even?/odd? of 100,000' value: (ev value: '(define (ev? n) (if (= n 0) #t (od? (- n 1)))) (define (od? n) (if (= n 0) #f (ev? (- n 1)))) (ev? 100000)') value: true.
check value: 'AC-2 stack depth constant'
	value: (ev value: '(define (pe n) (if (= n 0) (stack-depth) (po (- n 1)))) (define (po n) (if (= n 0) (stack-depth) (pe (- n 1)))) (= (pe 10) (pe 10000))')
	value: true.

"AC-3 tail position through if, begin and let"
check value: 'AC-3 if / begin / let in tail position, constant stack'
	value: (ev value: '(define (b n samples) (begin 1 (let ((m (- n 1))) (if (= n 0) samples (b m (if (= n 500) (cons (stack-depth) samples) (if (= n 2) (cons (stack-depth) samples) samples))))))) (b 500 (list))') lispElements asSet size
	value: 1.
check value: 'AC-3 tail call from the else branch of a nested if'
	value: (ev value: '(define (z n) (if (> n 0) (if (= n 1) (z 0) (z (- n 1))) (quote done))) (z 100000)')
	value: (LispSymbol named: 'done').

"AC-4 non-tail calls are unaffected"
check value: 'AC-4 fact 20' value: (ev value: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 20)') value: 2432902008176640000.
check value: 'AC-4 non-tail recursion grows the stack'
	value: (ev value: '(define (nt n) (if (= n 0) (stack-depth) (+ 0 (nt (- n 1))))) (< (nt 10) (nt 100))')
	value: true.

"AC-5 redefinition: an old procedure that self-tail-calls its name reaches the new definition"
check value: 'AC-5 redefinition followed'
	value: (ev value: '(define (rf n) (if (= n 0) (quote old) (rf (- n 1)))) (define saved rf) (define (rf n) (quote new)) (saved 3)')
	value: (LispSymbol named: 'new').
check value: 'AC-5 unredefined still loops' value: (ev value: '(define (rg n) (if (= n 0) (quote ok) (rg (- n 1)))) (rg 100000)') value: (LispSymbol named: 'ok').

"AC-6 a bounce never escapes through map, for-each or apply"
ev value: '(define (inc x) (+ x 1))'.
check value: 'AC-6 map' value: (ev value: '(map (lambda (x) (inc x)) ''(1 2 3))') value: (lst value: '(2 3 4)').
check value: 'AC-6 apply' value: (ev value: '(apply (lambda (x y) (inc (+ x y))) ''(1 2))') value: 4.
check value: 'AC-6 for-each' value: (ev value: '(define acc 0) (for-each (lambda (x) (set!! acc (inc (+ acc x)))) ''(1 2 3)) acc') value: 9.
check value: 'AC-6 a procedure value returned from a tail call' value: (ev value: '(define (mk) (inc 1)) (mk)') value: 2.
check value: 'AC-6 a tail call through apply runs in constant stack'
	value: (ev value: '(define (ap n) (if (= n 0) (stack-depth) (apply ap (list (- n 1))))) (= (ap 10) (ap 10000))')
	value: true.
check value: 'AC-6 a tail call to a primitive returns its value' value: (ev value: '(define (tp a b) (+ a b)) (tp 2 3)') value: 5.

"AC-7 errors still occur through fast calls and tail calls"
checkErr value: 'AC-7 arity error, fast path' value: LispArityError value: [ev value: '((lambda (x) x) 1 2)'].
checkErr value: 'AC-7 arity error, tail call' value: LispArityError value: [ev value: '(define (t1) ((lambda (x) x))) (t1)'].
checkErr value: 'AC-7 not applicable, tail call' value: LispError value: [ev value: '(define (t2) (5 6)) (t2)'].
checkErr value: 'AC-7 not applicable, fast path' value: LispError value: [ev value: '(5 6)'].

"AC-8 fast calls of every shape"
check value: 'AC-8 zero arguments' value: (ev value: '((lambda () 7))') value: 7.
check value: 'AC-8 four arguments' value: (ev value: '((lambda (a b c d) (list a b c d)) 1 2 3 4)') value: (lst value: '(1 2 3 4)').
check value: 'AC-8 six arguments' value: (ev value: '((lambda (a b c d e f) (+ a b c d e f)) 1 2 3 4 5 6)') value: 21.
check value: 'AC-8 variadic primitive' value: (ev value: '(list 1 2 3 4 5 6)') value: (lst value: '(1 2 3 4 5 6)').
check value: 'AC-8 direct entries of variadic primitives agree with the general path'
	value: (ev value: '(list (+ 7) (+ 1 2) (+ 1 2 3) (+ 1 2 3 4) (- 5) (- 10 3) (- 10 3 2) (* 3 4) (/ 8 2) (< 1 2) (< 1 3 2) (= 2 2) (> 1 2) (<= 2 2) (>= 1 2) (min 3 1) (max 3 1))')
	value: (lst value: '(7 3 6 10 -5 7 5 12 4 #t #f #t #f #t #f 1 3)').
checkErr value: 'AC-8 an entry still type-checks its arguments' value: Error value: [ev value: '(+ 1 (quote a))'].

"AC-9 global cells"
check value: 'AC-9 forward reference' value: (ev value: '(define (fwa) (fwb 4)) (define (fwb x) (* x 10)) (fwa)') value: 40.
check value: 'AC-9 redefinition visible to compiled code' value: (ev value: '(define v 1) (define (get-v) v) (define v 2) (get-v)') value: 2.
checkErr value: 'AC-9 unbound reference raises' value: LispUnboundError value: [ev value: '(define (bad) not-yet-defined-anywhere) (bad)'].
checkErr value: 'AC-9 set-bang of unbound raises' value: LispUnboundError value: [ev value: '(set!! also-not-defined 1)'].
check value: 'AC-9 environment API: lookup' value: (LispEnvironment default lookup: (LispSymbol named: 'v')) value: 2.
check value: 'AC-9 environment API: a referenced-but-undefined name is not bound'
	value: (LispEnvironment default isBound: (LispSymbol named: 'not-yet-defined-anywhere'))
	value: false.
check value: 'AC-9 environment API: at:ifAbsent: on an unbound cell'
	value: (LispEnvironment default at: (LispSymbol named: 'not-yet-defined-anywhere') ifAbsent: [#absent])
	value: #absent.

"AC-10 quoted constants are literals"
check value: 'AC-10 same object each evaluation' value: (ev value: '(define (k) ''(1 2)) (eq? (k) (k))') value: true.

"AC-11 let still scopes correctly"
check value: 'AC-11 two bindings' value: (ev value: '(let ((x 1) (y 2)) (+ x y))') value: 3.
check value: 'AC-11 bindings see the outer scope' value: (ev value: '(let ((x 1)) (let ((x 2) (y x)) y))') value: 1.
check value: 'AC-11 five bindings' value: (ev value: '(let ((a 1) (b 2) (c 3) (d 4) (e 5)) (+ a b c d e))') value: 15.
check value: 'AC-11 a fresh binding per evaluation'
	value: (ev value: '(define (mk n acc) (if (= n 0) acc (mk (- n 1) (cons (let ((k n)) (lambda () k)) acc)))) (map (lambda (f) (f)) (mk 3 (list)))')
	value: (lst value: '(1 2 3)').

"AC-12 every correctness check, with all optimizations on and with each one off"
core value: 'AC-12 all on:'.
LispCompiler allOptions do: [:opt |
	LispCompiler withoutOptions: { opt } do: [core value: 'AC-12 without ' , opt , ':']].
check value: 'AC-12 options restored afterwards' value: LispCompiler defaultOptions size value: LispCompiler allOptions size.

out value: ''.
out value: '== RESULT: ' , pass printString , '/' , total printString , ' checks passed =='
]
	on: Error
	do: [:e | out value: 'HARNESS ERROR: ' , e class name , ': ' , e messageText printString].

Smalltalk snapshot: false andQuit: true.
!
