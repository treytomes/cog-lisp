"============================================================================
 cog-lisp : Phase 2 implementation  (package CogLisp-Core)
 Core data model per specs/phase-2-core-data-model.md: type predicates,
 eq?/eqv?/equal?, truthiness, and the global environment.

 LOADER script (see coglisp-reader.st for the conventions). Must be filed in
 AFTER coglisp-reader.st, since its method bodies name the Phase-1 classes
 LispCons / LispSymbol / LispEmptyList.

 Classes: LispCore (stateless facade), LispEnvironment, LispGlobal, LispMacro,
 LispUnboundError.
 ============================================================================"
| failures cm core env cell macro err raise rst rstvar |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

core := (Object << #LispCore) package: 'CogLisp-Core'; install.
env  := (Object << #LispEnvironment) slots: { #bindings }; sharedVariables: { #Default }; package: 'CogLisp-Core'; install.
cell := (Object << #LispGlobal) slots: { #symbol. #value. #bound }; package: 'CogLisp-Core'; install.
macro := (Object << #LispMacro) slots: { #expander }; package: 'CogLisp-Core'; install.
err  := (LispError << #LispUnboundError) slots: { #symbol }; package: 'CogLisp-Core'; install.
"Phase 7.7: a raised value that is not itself an exception; continuable for raise-continuable."
raise := (LispError << #LispRaise) slots: { #payload. #continuable }; package: 'CogLisp-Core'; install.
"A named way to recover, established by restart-case; the active ones live in LispRestarts."
rst  := (Object << #LispRestart) slots: { #name. #action. #escape }; package: 'CogLisp-Core'; install.
rstvar := (DynamicVariable << #LispRestarts) package: 'CogLisp-Core'; install.

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
	"A Smalltalk symbol is a String in Smalltalk, but not a string in LISP (Phase 7.6 section 4.5)."
	^ (v isKindOf: String) and: [v isSymbol not]'.
cm value: core class value: 'predicates' value: 'isChar: v
	^ v isKindOf: Character'.
cm value: core class value: 'predicates' value: 'isNumber: v
	^ v isKindOf: Number'.
cm value: core class value: 'predicates' value: 'isInteger: v
	^ v isKindOf: Integer'.
cm value: core class value: 'predicates' value: 'isReal: v
	^ v isKindOf: Number'.
cm value: core class value: 'predicates' value: 'isList: v
	"False for a circular list, as R7RS requires (review R-4): a second pointer at
	 half speed meets the first one if the spine loops."
	| cur slow step |
	cur := v.
	slow := v.
	step := 0.
	[self isPair: cur] whileTrue: [
		cur := cur cdr.
		step := step + 1.
		step even ifTrue: [slow := slow cdr. slow == cur ifTrue: [^ false]]].
	^ self isNull: cur'.

"=== LispCore : equality (class-side) ======================================"
cm value: core class value: 'equality' value: 'eq: a with: b
	^ a == b'.
cm value: core class value: 'equality' value: 'eqv: a with: b
	((self isNumber: a) and: [self isNumber: b]) ifTrue: [
		"floats also by sign, so 0.0 and -0.0 differ (R7RS; review R-12)"
		((a isKindOf: Float) and: [b isKindOf: Float]) ifTrue: [^ a = b and: [a signBit = b signBit]].
		^ ((a isKindOf: Float) = (b isKindOf: Float)) and: [a = b]].
	((self isChar: a) and: [self isChar: b]) ifTrue: [^ a = b].
	^ a == b'.
cm value: core class value: 'equality' value: 'equal: a with: b
	^ self equal: a with: b depth: 0 seen: nil'.
cm value: core class value: 'equality' value: 'equal: a with: b depth: d seen: aSeen
	"Deep equality that terminates on cycles: past a depth, every pair of nodes being
	 compared is remembered, and meeting the same pair again counts as equal (two
	 cyclic structures that unfold to the same infinite tree are equal?, R7RS;
	 Phase 7.9 section 6). Shallow data never pays for the bookkeeping."
	| seen |
	(((self isPair: a) and: [self isPair: b]) or: [(a isKindOf: Array) and: [b isKindOf: Array]]) ifFalse: [
		((self isString: a) and: [self isString: b]) ifTrue: [^ a = b].
		^ self eqv: a with: b].
	a == b ifTrue: [^ true].
	seen := aSeen.
	d > 200 ifTrue: [
		seen isNil ifTrue: [seen := IdentityDictionary new].
		((seen at: a ifAbsent: [nil]) ifNil: [false] ifNotNil: [:set | set includes: b]) ifTrue: [^ true].
		(seen at: a ifAbsentPut: [IdentitySet new]) add: b].
	(a isKindOf: Array) ifTrue: [
		a size = b size ifFalse: [^ false].
		1 to: a size do: [:i | (self equal: (a at: i) with: (b at: i) depth: d + 1 seen: seen) ifFalse: [^ false]].
		^ true].
	^ (self equal: a car with: b car depth: d + 1 seen: seen)
		and: [self equal: a cdr with: b cdr depth: d + 1 seen: seen]'.

"=== LispCore : truthiness (class-side) ===================================="
cm value: core class value: 'truth' value: 'isTruthy: v
	^ v ~~ false'.

"=== LispMacro (Phase 7 section 5) =========================================
 What define-macro binds a global to: a holder for the expander procedure. The
 compiler recognizes it at compile time and expands calls instead of compiling
 them as calls. Defined here because the compiler loads before the runtime."
cm value: macro value: 'private' value: 'setExpander: aProcedure
	expander := aProcedure'.
cm value: macro value: 'accessing' value: 'expander
	^ expander'.
cm value: macro value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<macro>'''.
cm value: macro class value: 'instance creation' value: 'expander: aProcedure
	^ self new setExpander: aProcedure'.

"=== LispGlobal (Phase 6 section 5.2) ======================================
 One global variable: a cell owned by an environment. Compiled code holds the
 cell itself as a literal, so a reference is one indirection at run time. A cell
 may exist before its variable is defined (a forward reference); reading or
 assigning it then raises LispUnboundError."
cm value: cell value: 'private' value: 'setSymbol: aSymbol
	symbol := aSymbol.
	bound := false'.
cm value: cell value: 'accessing' value: 'symbol
	^ symbol'.
cm value: cell value: 'testing' value: 'isBound
	^ bound'.
cm value: cell value: 'accessing' value: 'value
	bound ifFalse: [^ self signalUnboundWithRestarts].
	^ value'.
cm value: cell value: 'private' value: 'signalUnboundWithRestarts
	"An unbound variable offers use-value (this once) and store-value (define it,
	 then use it): Phase 7.7 section 5.2."
	^ LispRestart
		withRestarts: {
			LispRestart name: ''use-value'' action: [:v | v].
			LispRestart name: ''store-value'' action: [:v | self define: v. v] }
		do: [self signalUnbound]'.
cm value: cell value: 'accessing' value: 'valueIfUnbound: aBlock
	bound ifFalse: [^ aBlock value].
	^ value'.
cm value: cell value: 'accessing' value: 'define: aValue
	value := aValue.
	bound := true.
	^ aValue'.
cm value: cell value: 'accessing' value: 'assign: aValue
	bound ifFalse: [^ self signalUnbound].
	value := aValue.
	^ aValue'.
cm value: cell value: 'private' value: 'signalUnbound
	^ (LispUnboundError new) symbol: symbol; signal: ''unbound variable: '' , symbol name'.
cm value: cell value: 'copying' value: 'frozenCopy
	"A private cell with this one''s name and present value, in no environment: what
	 sealed code reads instead (specs/phase-8-self-hosting.md step 8.5)."
	| copy |
	copy := self class symbol: symbol.
	bound ifTrue: [copy define: value].
	^ copy'.
"=== LispRaise (Phase 7.7 section 4.1) ====================================="
cm value: raise value: 'accessing' value: 'payload
	^ payload'.
cm value: raise value: 'accessing' value: 'payload: anObject
	payload := anObject'.
cm value: raise value: 'accessing' value: 'continuable
	^ continuable == true'.
cm value: raise value: 'accessing' value: 'continuable: aBoolean
	continuable := aBoolean'.
cm value: raise value: 'testing' value: 'isResumable
	^ self continuable'.
cm value: raise value: 'accessing' value: 'messageText
	^ ''uncaught raise: '' , (LispPrinter writeString: payload limitedTo: 60)'.

"=== LispRestart and LispRestarts (section 5) ==============================="
cm value: rst value: 'private' value: 'setName: aName action: aBlock
	name := aName.
	action := aBlock'.
cm value: rst value: 'accessing' value: 'name
	^ name'.
cm value: rst value: 'accessing' value: 'action
	^ action'.
cm value: rst value: 'private' value: 'escape: aBlock
	escape := aBlock'.
cm value: rst value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<restart ''; nextPutAll: name name; nextPut: $>'.
cm value: rst class value: 'instance creation' value: 'name: aName action: aBlock
	"aName: a LISP symbol or a string. aBlock: anything answering valueWithArguments:."
	^ self new setName: ((aName isKindOf: LispSymbol) ifTrue: [aName] ifFalse: [LispSymbol named: aName asString]) action: aBlock'.
cm value: rst class value: 'restarts' value: 'active
	"The restarts established in this process, innermost first."
	^ LispRestarts value ifNil: [#()]'.
cm value: rst class value: 'restarts' value: 'find: aName
	| sym |
	sym := (aName isKindOf: LispSymbol) ifTrue: [aName] ifFalse: [LispSymbol named: aName asString].
	^ self active detect: [:r | r name == sym] ifNone: [nil]'.
cm value: rst class value: 'restarts' value: 'withRestarts: restarts do: aBlock
	"Evaluate aBlock with restarts established. Invoking one unwinds to here, then
	 runs its action with the arguments; the action''s value is the answer."
	| outcome |
	outcome := self establish: restarts asArray during: aBlock.
	outcome first == #normal ifTrue: [^ outcome second].
	^ outcome second action valueWithArguments: outcome third'.
cm value: rst class value: 'restarts' value: 'establish: restarts during: aBlock
	"{#normal. value}, or {#restart. r. args} when restart r was invoked. Invoking is
	 a non-local return from the escape block to this method: it unwinds the stack
	 (running ensure: blocks) without an exception, because Smalltalk looks for the
	 handler of an exception signalled in a handler only outside that handler, so it
	 would never find a restart established between the error and the handler."
	restarts do: [:r | r escape: [:args | ^ { #restart. r. args }]].
	^ { #normal. LispRestarts value: restarts , self active during: aBlock }'.
cm value: rst class value: 'restarts' value: 'invoke: aRestartOrName with: anArray
	| r |
	r := (aRestartOrName isKindOf: LispRestart) ifTrue: [aRestartOrName] ifFalse: [self find: aRestartOrName].
	r isNil ifTrue: [^ (LispError new) signal: ''invoke-restart: no active restart named '' ,
		((aRestartOrName isKindOf: LispSymbol) ifTrue: [aRestartOrName name] ifFalse: [aRestartOrName asString])].
	(self active identityIncludes: r) ifFalse: [^ (LispError new) signal: ''invoke-restart: restart is not active: '' , r name name].
	^ r invokeWith: anArray'.
cm value: rst value: 'private' value: 'invokeWith: anArray
	^ escape value: anArray asArray'.
cm value: rstvar value: 'accessing' value: 'default
	^ #()'.

cm value: cell value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<global '' , symbol name , ''>'''.
cm value: cell class value: 'instance creation' value: 'symbol: aSymbol
	^ self new setSymbol: aSymbol'.

"=== LispEnvironment ======================================================="
cm value: env value: 'initialization' value: 'initialize
	bindings := IdentityDictionary new'.
cm value: env value: 'cells' value: 'cellFor: aSymbol
	"The cell for aSymbol, created unbound if it does not exist yet."
	^ bindings at: aSymbol ifAbsentPut: [LispGlobal symbol: aSymbol]'.
cm value: env value: 'accessing' value: 'define: aSymbol value: aValue
	^ (self cellFor: aSymbol) define: aValue'.
cm value: env value: 'accessing' value: 'lookup: aSymbol
	^ (self cellFor: aSymbol) value'.
cm value: env value: 'accessing' value: 'at: aSymbol ifAbsent: aBlock
	^ (bindings at: aSymbol ifAbsent: [^ aBlock value]) valueIfUnbound: aBlock'.
cm value: env value: 'accessing' value: 'set: aSymbol value: aValue
	^ (self cellFor: aSymbol) assign: aValue'.
cm value: env value: 'enumerating' value: 'cellsDo: aBlock
	"Every global cell, bound or not."
	bindings do: aBlock'.
cm value: env value: 'testing' value: 'isBound: aSymbol
	^ (bindings at: aSymbol ifAbsent: [^ false]) isBound'.
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
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Core: ' , failures size printString].
