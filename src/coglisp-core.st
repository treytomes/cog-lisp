"============================================================================
 cog-lisp : Phase 2 implementation  (package CogLisp-Core)
 Core data model per specs/phase-2-core-data-model.md: type predicates,
 eq?/eqv?/equal?, truthiness, and the global environment.

 LOADER script (see coglisp-reader.st for the conventions). Must be filed in
 AFTER coglisp-reader.st, since its method bodies name the Phase-1 classes
 LispCons / LispSymbol / LispEmptyList.

 Classes: LispCore (stateless facade), LispEnvironment, LispUnboundError.
 ============================================================================"
| failures cm core env err |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , (src copyUpTo: Character cr) , (src copyUpTo: Character lf) , '  --  ' , e messageText]].

core := (Object << #LispCore) package: 'CogLisp-Core'; install.
env  := (Object << #LispEnvironment) slots: { #bindings }; sharedVariables: { #Default }; package: 'CogLisp-Core'; install.
err  := (Error  << #LispUnboundError) slots: { #symbol }; package: 'CogLisp-Core'; install.

"=== LispCore : type predicates (class-side) ==============================="
cm value: core class value: 'predicates' value: 'isPair: v
	^ v isKindOf: LispCons'.
cm value: core class value: 'predicates' value: 'isNull: v
	^ v == LispEmptyList default'.
cm value: core class value: 'predicates' value: 'isSymbol: v
	^ v isKindOf: LispSymbol'.
cm value: core class value: 'predicates' value: 'isBoolean: v
	^ (v == true) or: [v == false]'.
cm value: core class value: 'predicates' value: 'isString: v
	^ v isKindOf: String'.
cm value: core class value: 'predicates' value: 'isChar: v
	^ v isKindOf: Character'.
cm value: core class value: 'predicates' value: 'isNumber: v
	^ v isKindOf: Number'.
cm value: core class value: 'predicates' value: 'isInteger: v
	^ v isKindOf: Integer'.
cm value: core class value: 'predicates' value: 'isReal: v
	^ v isKindOf: Number'.
cm value: core class value: 'predicates' value: 'isList: v
	| cur |
	cur := v.
	[self isPair: cur] whileTrue: [cur := cur cdr].
	^ self isNull: cur'.

"=== LispCore : equality (class-side) ======================================"
cm value: core class value: 'equality' value: 'eq: a with: b
	^ a == b'.
cm value: core class value: 'equality' value: 'eqv: a with: b
	((self isNumber: a) and: [self isNumber: b])
		ifTrue: [^ ((a isKindOf: Float) = (b isKindOf: Float)) and: [a = b]].
	((self isChar: a) and: [self isChar: b]) ifTrue: [^ a = b].
	^ a == b'.
cm value: core class value: 'equality' value: 'equal: a with: b
	((self isPair: a) and: [self isPair: b])
		ifTrue: [^ (self equal: a car with: b car) and: [self equal: a cdr with: b cdr]].
	((self isString: a) and: [self isString: b]) ifTrue: [^ a = b].
	^ self eqv: a with: b'.

"=== LispCore : truthiness (class-side) ===================================="
cm value: core class value: 'truth' value: 'isTruthy: v
	^ v ~~ false'.

"=== LispEnvironment ======================================================="
cm value: env value: 'initialization' value: 'initialize
	bindings := IdentityDictionary new'.
cm value: env value: 'accessing' value: 'define: aSymbol value: aValue
	bindings at: aSymbol put: aValue.
	^ aValue'.
cm value: env value: 'accessing' value: 'lookup: aSymbol
	^ bindings at: aSymbol ifAbsent: [
		(LispUnboundError new) symbol: aSymbol; signal: ''unbound variable: '' , aSymbol name]'.
cm value: env value: 'accessing' value: 'at: aSymbol ifAbsent: aBlock
	^ bindings at: aSymbol ifAbsent: aBlock'.
cm value: env value: 'accessing' value: 'set: aSymbol value: aValue
	(bindings includesKey: aSymbol) ifFalse: [
		^ (LispUnboundError new) symbol: aSymbol; signal: ''unbound variable: '' , aSymbol name].
	bindings at: aSymbol put: aValue.
	^ aValue'.
cm value: env value: 'testing' value: 'isBound: aSymbol
	^ bindings includesKey: aSymbol'.
cm value: env class value: 'accessing' value: 'default
	Default isNil ifTrue: [Default := self new].
	^ Default'.

"=== LispUnboundError ======================================================"
cm value: err value: 'accessing' value: 'symbol
	^ symbol'.
cm value: err value: 'accessing' value: 'symbol: aSymbol
	symbol := aSymbol'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Core'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
