"============================================================================
 cog-lisp : Phase 4 implementation  (package CogLisp-Runtime)
 Procedures + primitive library per specs/phase-4-runtime-primitives.md.

 LOADER script. Must be filed in AFTER coglisp-reader.st, coglisp-core.st, and
 coglisp-compiler.st. Set-car and set-cdr contain a bang, written doubled so the
 chunk reader keeps it.

 Classes: LispError, LispArityError, LispProcedure, LispPrimitives.
 ============================================================================"
| failures cm lerr aerr proc prims |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , (src copyUpTo: Character cr) , (src copyUpTo: Character lf) , '  --  ' , e messageText]].

lerr  := (Error  << #LispError) package: 'CogLisp-Runtime'; install.
aerr  := (lerr   << #LispArityError) slots: { #proc. #given }; package: 'CogLisp-Runtime'; install.
proc  := (Object << #LispProcedure) slots: { #block. #required. #hasRest. #name }; package: 'CogLisp-Runtime'; install.
prims := (Object << #LispPrimitives) package: 'CogLisp-Runtime'; install.

"=== LispArityError ========================================================"
cm value: aerr value: 'accessing' value: 'proc
	^ proc'.
cm value: aerr value: 'accessing' value: 'proc: aProc
	proc := aProc'.
cm value: aerr value: 'accessing' value: 'given
	^ given'.
cm value: aerr value: 'accessing' value: 'given: anInteger
	given := anInteger'.

"=== LispProcedure ========================================================="
cm value: proc value: 'private' value: 'setBlock: aBlock required: n rest: aBool
	block := aBlock.
	required := n.
	hasRest := aBool'.
cm value: proc value: 'accessing' value: 'name
	^ name'.
cm value: proc value: 'accessing' value: 'name: aString
	name := aString'.
cm value: proc value: 'testing' value: 'isVariadic
	^ hasRest'.
cm value: proc value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''<procedure''.
	name ifNotNil: [aStream nextPut: Character space; nextPutAll: name].
	aStream nextPut: $>'.
cm value: proc value: 'applying' value: 'signalArity: givenCount
	^ (LispArityError new) proc: self; given: givenCount; signal: ''wrong number of arguments''.'.
cm value: proc value: 'applying' value: 'applyTo: anArray
	hasRest ifFalse: [
		anArray size = required ifFalse: [^ self signalArity: anArray size].
		^ block valueWithArguments: anArray].
	anArray size >= required ifFalse: [^ self signalArity: anArray size].
	^ block valueWithArguments: ((anArray first: required) , { LispCons fromArray: (anArray allButFirst: required) })'.
cm value: proc class value: 'instance creation' value: 'fixed: aBlock arity: n
	^ self new setBlock: aBlock required: n rest: false'.
cm value: proc class value: 'instance creation' value: 'variadic: aBlock required: n
	^ self new setBlock: aBlock required: n rest: true'.
cm value: proc class value: 'applying' value: 'apply: fn to: anArray
	(fn isKindOf: LispProcedure) ifFalse: [^ (LispError new) signal: ''object is not applicable: '' , fn printString].
	^ fn applyTo: anArray'.

"=== LispPrimitives : install the library (class-side) ====================="
cm value: prims class value: 'installing' value: 'installInto: anEnv
	self installListsInto: anEnv.
	self installNumbersInto: anEnv.
	self installComparisonsInto: anEnv.
	self installPredicatesInto: anEnv.
	self installIOInto: anEnv.
	self installControlInto: anEnv.
	^ anEnv'.
cm value: prims class value: 'installing' value: 'installDefault
	^ self installInto: LispEnvironment default'.
cm value: prims class value: 'installing' value: 'installListsInto: anEnv
	anEnv define: (LispSymbol named: ''cons'') value: (LispProcedure fixed: [:a :b | LispCons car: a cdr: b] arity: 2).
	anEnv define: (LispSymbol named: ''car'') value: (LispProcedure fixed: [:p | p car] arity: 1).
	anEnv define: (LispSymbol named: ''cdr'') value: (LispProcedure fixed: [:p | p cdr] arity: 1).
	anEnv define: (LispSymbol named: ''pair?'') value: (LispProcedure fixed: [:x | LispCore isPair: x] arity: 1).
	anEnv define: (LispSymbol named: ''null?'') value: (LispProcedure fixed: [:x | LispCore isNull: x] arity: 1).
	anEnv define: (LispSymbol named: ''list?'') value: (LispProcedure fixed: [:x | LispCore isList: x] arity: 1).
	anEnv define: (LispSymbol named: ''list'') value: (LispProcedure variadic: [:args | args] required: 0).
	anEnv define: (LispSymbol named: ''length'') value: (LispProcedure fixed: [:lst | lst lispElements size] arity: 1).
	anEnv define: (LispSymbol named: ''reverse'') value: (LispProcedure fixed: [:lst | LispCons fromArray: lst lispElements asArray reverse] arity: 1).
	anEnv define: (LispSymbol named: ''append'') value: (LispProcedure variadic: [:lists | | els | els := OrderedCollection new. lists lispElements do: [:l | els addAll: l lispElements]. LispCons fromArray: els asArray] required: 0).
	anEnv define: (LispSymbol named: ''set-car!!'') value: (LispProcedure fixed: [:p :v | p car: v. v] arity: 2).
	anEnv define: (LispSymbol named: ''set-cdr!!'') value: (LispProcedure fixed: [:p :v | p cdr: v. v] arity: 2).
	anEnv define: (LispSymbol named: ''map'') value: (LispProcedure fixed: [:prc :lst | LispCons fromArray: (lst lispElements collect: [:e | LispProcedure apply: prc to: { e }]) asArray] arity: 2).
	anEnv define: (LispSymbol named: ''for-each'') value: (LispProcedure fixed: [:prc :lst | lst lispElements do: [:e | LispProcedure apply: prc to: { e }]. LispEmptyList default] arity: 2)'.
cm value: prims class value: 'installing' value: 'installNumbersInto: anEnv
	anEnv define: (LispSymbol named: ''+'') value: (LispProcedure variadic: [:nums | nums lispElements inject: 0 into: [:a :b | a + b]] required: 0).
	anEnv define: (LispSymbol named: ''*'') value: (LispProcedure variadic: [:nums | nums lispElements inject: 1 into: [:a :b | a * b]] required: 0).
	anEnv define: (LispSymbol named: ''-'') value: (LispProcedure variadic: [:first :rest | rest lispElements isEmpty ifTrue: [first negated] ifFalse: [rest lispElements inject: first into: [:a :b | a - b]]] required: 1).
	anEnv define: (LispSymbol named: ''/'') value: (LispProcedure variadic: [:first :rest | rest lispElements isEmpty ifTrue: [1 / first] ifFalse: [rest lispElements inject: first into: [:a :b | a / b]]] required: 1).
	anEnv define: (LispSymbol named: ''modulo'') value: (LispProcedure fixed: [:a :b | a \\ b] arity: 2).
	anEnv define: (LispSymbol named: ''quotient'') value: (LispProcedure fixed: [:a :b | a quo: b] arity: 2).
	anEnv define: (LispSymbol named: ''abs'') value: (LispProcedure fixed: [:a | a abs] arity: 1).
	anEnv define: (LispSymbol named: ''min'') value: (LispProcedure variadic: [:first :rest | rest lispElements inject: first into: [:a :b | a min: b]] required: 1).
	anEnv define: (LispSymbol named: ''max'') value: (LispProcedure variadic: [:first :rest | rest lispElements inject: first into: [:a :b | a max: b]] required: 1).
	anEnv define: (LispSymbol named: ''zero?'') value: (LispProcedure fixed: [:a | a = 0] arity: 1).
	anEnv define: (LispSymbol named: ''positive?'') value: (LispProcedure fixed: [:a | a > 0] arity: 1).
	anEnv define: (LispSymbol named: ''negative?'') value: (LispProcedure fixed: [:a | a < 0] arity: 1)'.
cm value: prims class value: 'installing' value: 'installComparisonsInto: anEnv
	anEnv define: (LispSymbol named: ''='') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev = x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''<'') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev < x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''>'') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev > x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''<='') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev <= x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''>='') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev >= x) ifFalse: [ok := false]. prev := x]. ok] required: 1)'.
cm value: prims class value: 'installing' value: 'installPredicatesInto: anEnv
	anEnv define: (LispSymbol named: ''eq?'') value: (LispProcedure fixed: [:a :b | LispCore eq: a with: b] arity: 2).
	anEnv define: (LispSymbol named: ''eqv?'') value: (LispProcedure fixed: [:a :b | LispCore eqv: a with: b] arity: 2).
	anEnv define: (LispSymbol named: ''equal?'') value: (LispProcedure fixed: [:a :b | LispCore equal: a with: b] arity: 2).
	anEnv define: (LispSymbol named: ''not'') value: (LispProcedure fixed: [:x | x == false] arity: 1).
	anEnv define: (LispSymbol named: ''symbol?'') value: (LispProcedure fixed: [:x | LispCore isSymbol: x] arity: 1).
	anEnv define: (LispSymbol named: ''number?'') value: (LispProcedure fixed: [:x | LispCore isNumber: x] arity: 1).
	anEnv define: (LispSymbol named: ''integer?'') value: (LispProcedure fixed: [:x | LispCore isInteger: x] arity: 1).
	anEnv define: (LispSymbol named: ''string?'') value: (LispProcedure fixed: [:x | LispCore isString: x] arity: 1).
	anEnv define: (LispSymbol named: ''char?'') value: (LispProcedure fixed: [:x | LispCore isChar: x] arity: 1).
	anEnv define: (LispSymbol named: ''boolean?'') value: (LispProcedure fixed: [:x | LispCore isBoolean: x] arity: 1).
	anEnv define: (LispSymbol named: ''procedure?'') value: (LispProcedure fixed: [:x | x isKindOf: LispProcedure] arity: 1)'.
cm value: prims class value: 'installing' value: 'installIOInto: anEnv
	anEnv define: (LispSymbol named: ''display'') value: (LispProcedure fixed: [:x | Stdio stdout nextPutAll: ((x isKindOf: String) ifTrue: [x] ifFalse: [LispPrinter writeString: x]); flush. LispEmptyList default] arity: 1).
	anEnv define: (LispSymbol named: ''write'') value: (LispProcedure fixed: [:x | Stdio stdout nextPutAll: (LispPrinter writeString: x); flush. LispEmptyList default] arity: 1).
	anEnv define: (LispSymbol named: ''newline'') value: (LispProcedure fixed: [Stdio stdout nextPut: Character lf; flush. LispEmptyList default] arity: 0)'.
cm value: prims class value: 'installing' value: 'installControlInto: anEnv
	anEnv define: (LispSymbol named: ''apply'') value: (LispProcedure fixed: [:prc :argList | LispProcedure apply: prc to: argList lispElements asArray] arity: 2)'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Runtime'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
