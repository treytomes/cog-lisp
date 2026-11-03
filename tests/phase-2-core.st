"============================================================================
 cog-lisp : Phase 2 acceptance suite  (specs/phase-2-core-data-model.md, AC-1..13)
 Headless; PASS/FAIL per check, final RESULT line, then quits.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-2-core.st
 ============================================================================"

"--- Chunk 1: load reader then core into this fresh image -------------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
(dir / 'coglisp-reader.st') fileIn.
(dir / 'coglisp-core.st') fileIn.
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| h out check checkErr rd sym env env2 |
h := LispTestHarness new.
out := [:s | h say: s].
check := h checkBlock.
checkErr := [:label :blk | h check: label raises: LispUnboundError do: blk].
rd := [:s | LispReader read: s].
sym := [:s | LispSymbol named: s].

[
out value: '== cog-lisp Phase 2 : core data model =='.

"AC-1 isPair / isNull"
check value: 'AC-1 isPair ()' value: (LispCore isPair: LispEmptyList default) value: false.
check value: 'AC-1 isPair (1)' value: (LispCore isPair: (rd value: '(1)')) value: true.
check value: 'AC-1 isNull ()' value: (LispCore isNull: LispEmptyList default) value: true.
check value: 'AC-1 isNull (1)' value: (LispCore isNull: (rd value: '(1)')) value: false.
check value: 'AC-1 isPair 5' value: (LispCore isPair: 5) value: false.

"AC-2 type predicates"
check value: 'AC-2 isSymbol foo' value: (LispCore isSymbol: (sym value: 'foo')) value: true.
check value: 'AC-2 isSymbol 5' value: (LispCore isSymbol: 5) value: false.
check value: 'AC-2 isBoolean #t' value: (LispCore isBoolean: true) value: true.
check value: 'AC-2 isBoolean 0' value: (LispCore isBoolean: 0) value: false.
check value: 'AC-2 isString' value: (LispCore isString: 'hi') value: true.
check value: 'AC-2 isString sym' value: (LispCore isString: (sym value: 'hi')) value: false.
check value: 'AC-2 isChar' value: (LispCore isChar: $a) value: true.
check value: 'AC-2 isNumber 3.14' value: (LispCore isNumber: 3.14) value: true.
check value: 'AC-2 isInteger 3' value: (LispCore isInteger: 3) value: true.
check value: 'AC-2 isInteger 3.0' value: (LispCore isInteger: 3.0) value: false.

"AC-3 isList (proper list, terminating)"
check value: 'AC-3 isList ()' value: (LispCore isList: LispEmptyList default) value: true.
check value: 'AC-3 isList (1 2 3)' value: (LispCore isList: (rd value: '(1 2 3)')) value: true.
check value: 'AC-3 isList (1 . 2)' value: (LispCore isList: (rd value: '(1 . 2)')) value: false.
check value: 'AC-3 isList 5' value: (LispCore isList: 5) value: false.

"AC-4 eq?"
check value: 'AC-4 eq symbols (interned)' value: (LispCore eq: (sym value: 'foo') with: (rd value: 'foo')) value: true.
check value: 'AC-4 eq strings (distinct)' value: (LispCore eq: 'ab' with: 'ab' copy) value: false.

"AC-5 eqv?"
check value: 'AC-5 eqv 1 1' value: (LispCore eqv: 1 with: 1) value: true.
check value: 'AC-5 eqv 1 1.0' value: (LispCore eqv: 1 with: 1.0) value: false.
check value: 'AC-5 eqv 1.0 1.0' value: (LispCore eqv: 1.0 with: 1.0) value: true.
check value: 'AC-5 eqv chars' value: (LispCore eqv: $a with: $a) value: true.
check value: 'AC-5 eqv bigints' value: (LispCore eqv: (10 raisedTo: 30) with: (10 raisedTo: 30)) value: true.

"AC-6 equal?"
check value: 'AC-6 equal strings' value: (LispCore equal: 'ab' with: 'ab' copy) value: true.
check value: 'AC-6 equal lists' value: (LispCore equal: (rd value: '(1 2)') with: (rd value: '(1 2)')) value: true.
check value: 'AC-6 equal nested' value: (LispCore equal: (rd value: '(1 (2) 3)') with: (rd value: '(1 (2) 3)')) value: true.
check value: 'AC-6 equal diff' value: (LispCore equal: (rd value: '(1 2)') with: (rd value: '(1 3)')) value: false.
check value: 'AC-6 equal 1 1.0' value: (LispCore equal: 1 with: 1.0) value: false.

"AC-7 equal? on dotted pairs"
check value: 'AC-7 equal dotted' value: (LispCore equal: (rd value: '(1 . 2)') with: (rd value: '(1 . 2)')) value: true.
check value: 'AC-7 equal dotted diff' value: (LispCore equal: (rd value: '(1 . 2)') with: (rd value: '(1 . 3)')) value: false.

"AC-8 truthiness"
check value: 'AC-8 false not truthy' value: (LispCore isTruthy: false) value: false.
check value: 'AC-8 () truthy' value: (LispCore isTruthy: LispEmptyList default) value: true.
check value: 'AC-8 0 truthy' value: (LispCore isTruthy: 0) value: true.
check value: 'AC-8 empty string truthy' value: (LispCore isTruthy: '') value: true.
check value: 'AC-8 #t truthy' value: (LispCore isTruthy: true) value: true.
check value: 'AC-8 symbol truthy' value: (LispCore isTruthy: (sym value: 'x')) value: true.

"AC-9 define / lookup / redefine"
env := LispEnvironment new.
env define: (sym value: 'a') value: 42.
check value: 'AC-9 lookup' value: (env lookup: (sym value: 'a')) value: 42.
env define: (sym value: 'a') value: 99.
check value: 'AC-9 redefine' value: (env lookup: (sym value: 'a')) value: 99.

"AC-10 unbound lookup signals"
checkErr value: 'AC-10 unbound lookup signals' value: [env lookup: (sym value: 'zzz')].

"AC-11 set!! on bound / unbound"
env define: (sym value: 'b') value: 1.
env set: (sym value: 'b') value: 2.
check value: 'AC-11 set!! bound' value: (env lookup: (sym value: 'b')) value: 2.
checkErr value: 'AC-11 set!! unbound signals' value: [env set: (sym value: 'qqq') value: 5].

"AC-12 isBound / at:ifAbsent:"
check value: 'AC-12 isBound true' value: (env isBound: (sym value: 'a')) value: true.
check value: 'AC-12 isBound false' value: (env isBound: (sym value: 'nope')) value: false.
check value: 'AC-12 at:ifAbsent present' value: (env at: (sym value: 'a') ifAbsent: [#absent]) value: 99.
check value: 'AC-12 at:ifAbsent absent' value: (env at: (sym value: 'nope') ifAbsent: [#absent]) value: #absent.

"AC-13 interning bridges source and table"
env2 := LispEnvironment new.
env2 define: (rd value: 'x') value: 7.
check value: 'AC-13 interning bridge' value: (env2 lookup: (rd value: 'x')) value: 7.

h finish
]
	on: Error
	do: [:e | h harnessError: e].

Smalltalk snapshot: false andQuit: true.
!
