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
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| h out check checkErr ev evAll eq |
h := LispTestHarness new.
out := [:s | h say: s].
ev := [:s | LispCompiler new evalString: s].
evAll := [:s | LispCompiler new evalAll: s].
"structural equality for list results (reuse LispCore)"
eq := [:a :b | LispCore equal: a with: b].
check := h checkBlock.
checkErr := [:label :blk | h check: label raises: Error do: blk].

"Since Phase 4, procedures are LispProcedures; install the real primitive library."
LispPrimitives installDefault.

[
out value: '== cog-lisp Phase 3 : compiler core =='.

"AC-1 self-evaluating"

"AC-2 / AC-3 quote"

"AC-4 / AC-5 variables"
[evAll value: '(define x 5) x'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

"AC-6 / AC-7 if"

"Since Phase 5 the unspecified value is LispUnspecified, no longer the empty list."

"AC-8 begin"

[evAll value: '(define c 0) (begin (set!! c 1) (set!! c (+ c 10)) c)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

"AC-9..12 lambda / application / closures"

check value: 'AC-11 lambda is LispProcedure' value: ((ev value: '(lambda (x) x)') isKindOf: LispProcedure) value: true.
check value: 'AC-11 compile: is CompiledMethod' value: ((LispCompiler new compile: (LispReader read: '42')) isKindOf: CompiledMethod) value: true.

"AC-13 / AC-14 let"

"AC-15 / AC-16 define"
[evAll value: '(define y 10) y'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

[evAll value: '(define (sq n) (* n n)) (sq 4)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

"AC-17 / AC-18 set-bang"
[evAll value: '(define z 1) (set!! z 2) z'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

[ev value: '(set!! nope 5)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

[ev value: '((lambda (x) (set!! x (+ x 1)) x) 10)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

"AC-19 recursion"
[evAll value: '(define (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) (fact 5)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

"AC-20 evalAll returns last"
[evAll value: '(define a 7) (+ a 1)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-3-compiler.lisp)"

h finish
]
	on: Error
	do: [:e | h harnessError: e].

Smalltalk snapshot: false andQuit: true.
!
