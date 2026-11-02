"============================================================================
 cog-lisp : Phase 3 acceptance suite  (specs/phase-3-compiler-core.md, AC-1..20)
 Headless; PASS/FAIL per check, final RESULT line, then quits.
 The set-bang form is written with a doubled bang so the chunk reader keeps it.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-3-compiler.st
 ============================================================================"

"--- Chunk 1: load reader, core, compiler; bind a few primitives -----------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
(dir / 'coglisp-reader.st') fileIn.
(dir / 'coglisp-core.st') fileIn.
(dir / 'coglisp-compiler.st') fileIn.
(dir / 'coglisp-runtime.st') fileIn.
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| out pass total check checkErr ev evAll eq |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
pass := 0.
total := 0.
ev := [:s | LispCompiler new evalString: s].
evAll := [:s | LispCompiler new evalAll: s].
"structural equality for list results (reuse LispCore)"
eq := [:a :b | LispCore equal: a with: b].
check := [:label :actual :expected |
	total := total + 1.
	(eq value: actual value: expected)
		ifTrue: [pass := pass + 1. out value: '  PASS  ' , label]
		ifFalse: [out value: '  FAIL  ' , label , '  got=' , (LispPrinter writeString: actual) , '  want=' , (LispPrinter writeString: expected)]].
checkErr := [:label :blk |
	total := total + 1.
	[blk value. out value: '  FAIL  ' , label , ' (no error raised)']
		on: Error
		do: [:e | pass := pass + 1. out value: '  PASS  ' , label]].

"Since Phase 4, procedures are LispProcedures; install the real primitive library."
LispPrimitives installDefault.

[
out value: '== cog-lisp Phase 3 : compiler core =='.

"AC-1 self-evaluating"
check value: 'AC-1 42' value: (ev value: '42') value: 42.
check value: 'AC-1 string' value: (ev value: '"hi"') value: 'hi'.
check value: 'AC-1 #t' value: (ev value: '#t') value: true.
check value: 'AC-1 #\a' value: (ev value: '#\a') value: $a.
check value: 'AC-1 ()' value: (ev value: '()') value: LispEmptyList default.

"AC-2 / AC-3 quote"
check value: 'AC-2 (quote x)' value: (ev value: '(quote x)') value: (LispSymbol named: 'x').
check value: 'AC-2 ''x' value: (ev value: '''x') value: (LispSymbol named: 'x').
check value: 'AC-3 ''(1 2 3)' value: (ev value: '''(1 2 3)') value: (LispReader read: '(1 2 3)').
check value: 'AC-3 ''(1 . 2)' value: (ev value: '''(1 . 2)') value: (LispReader read: '(1 . 2)').

"AC-4 / AC-5 variables"
check value: 'AC-4 global read' value: (evAll value: '(define x 5) x') value: 5.
checkErr value: 'AC-5 unbound read signals' value: [ev value: 'nosuchvar'].

"AC-6 / AC-7 if"
check value: 'AC-6 (if #t 1 2)' value: (ev value: '(if #t 1 2)') value: 1.
check value: 'AC-6 (if #f 1 2)' value: (ev value: '(if #f 1 2)') value: 2.
check value: 'AC-6 (if 0 1 2) [0 truthy]' value: (ev value: '(if 0 1 2)') value: 1.
check value: 'AC-7 (if #f 1) unspecified' value: (ev value: '(if #f 1)') value: LispEmptyList default.

"AC-8 begin"
check value: 'AC-8 (begin 1 2 3)' value: (ev value: '(begin 1 2 3)') value: 3.
check value: 'AC-8 begin order' value: (evAll value: '(define c 0) (begin (set!! c 1) (set!! c (+ c 10)) c)') value: 11.

"AC-9..12 lambda / application / closures"
check value: 'AC-9 ((lambda (x) x) 5)' value: (ev value: '((lambda (x) x) 5)') value: 5.
check value: 'AC-10 ((lambda (x y) (+ x y)) 2 3)' value: (ev value: '((lambda (x y) (+ x y)) 2 3)') value: 5.
check value: 'AC-11 lambda is LispProcedure' value: ((ev value: '(lambda (x) x)') isKindOf: LispProcedure) value: true.
check value: 'AC-11 compile: is CompiledMethod' value: ((LispCompiler new compile: (LispReader read: '42')) isKindOf: CompiledMethod) value: true.
check value: 'AC-12 closure capture' value: (ev value: '(((lambda (x) (lambda (y) (+ x y))) 2) 3)') value: 5.

"AC-13 / AC-14 let"
check value: 'AC-13 let' value: (ev value: '(let ((x 1) (y 2)) (+ x y))') value: 3.
check value: 'AC-14 let shadowing' value: (ev value: '(let ((x 1)) (let ((x 2)) x))') value: 2.

"AC-15 / AC-16 define"
check value: 'AC-15 define value' value: (evAll value: '(define y 10) y') value: 10.
check value: 'AC-16 define fn sugar' value: (evAll value: '(define (sq n) (* n n)) (sq 4)') value: 16.

"AC-17 / AC-18 set-bang"
check value: 'AC-17 global set!!' value: (evAll value: '(define z 1) (set!! z 2) z') value: 2.
checkErr value: 'AC-17 set!! unbound signals' value: [ev value: '(set!! nope 5)'].
check value: 'AC-18 local set!!' value: (ev value: '((lambda (x) (set!! x (+ x 1)) x) 10)') value: 11.

"AC-19 recursion"
check value: 'AC-19 (fact 5)=120'
	value: (evAll value: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)')
	value: 120.

"AC-20 evalAll returns last"
check value: 'AC-20 evalAll last' value: (evAll value: '(define a 7) (+ a 1)') value: 8.

out value: ''.
out value: '== RESULT: ' , pass printString , '/' , total printString , ' checks passed =='
]
	on: Error
	do: [:e | out value: 'HARNESS ERROR: ' , e class name , ': ' , e messageText printString].

Smalltalk snapshot: false andQuit: true.
!
