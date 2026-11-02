"============================================================================
 cog-lisp : Phase 3 implementation  (package CogLisp-Compiler)
 Compiler core per specs/phase-3-compiler-core.md: LISP s-expression ->
 Smalltalk AST (OC nodes) -> Opal -> CompiledMethod.

 LOADER script (see coglisp-reader.st). Must be filed in AFTER coglisp-reader.st
 and coglisp-core.st. Note: the set-bang symbol inside is written as a doubled
 bang so the chunk reader keeps it intact.

 Classes: LispCompiler, LispCompileError.

 Mechanism (all verified live, see CLAUDE.md): message nodes are built by
 template-splice (parse a skeleton for the selector, then swap receiver/args),
 because OCMessageNode's selector constructors fail. Methods compile via
 doSemanticAnalysis + generateMethod.
 ============================================================================"
| failures cm comp err |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , (src copyUpTo: Character cr) , (src copyUpTo: Character lf) , '  --  ' , e messageText]].

comp := (Object << #LispCompiler) slots: { #counter }; package: 'CogLisp-Compiler'; install.
err  := (Error  << #LispCompileError) package: 'CogLisp-Compiler'; install.

"=== node-building helpers ================================================="
cm value: comp value: 'initialization' value: 'initialize
	counter := 0'.
cm value: comp value: 'private' value: 'nextName
	counter := counter + 1.
	^ ''l'' , counter printString'.
cm value: comp value: 'private' value: 'compileError: aString
	^ (LispCompileError new) signal: aString'.
cm value: comp value: 'nodes' value: 'literalNode: aValue
	^ OCLiteralValueNode value: aValue'.
cm value: comp value: 'nodes' value: 'templateFor: aSelector
	aSelector isUnary ifTrue: [^ ''0 '' , aSelector].
	aSelector isBinary ifTrue: [^ ''0 '' , aSelector , '' 0''].
	^ String streamContents: [:s |
		s nextPutAll: ''0''.
		aSelector keywords do: [:kw | s nextPutAll: '' ''; nextPutAll: kw; nextPutAll: '' 0'']]'.
cm value: comp value: 'nodes' value: 'messageNode: receiverNode selector: aSelector arguments: argNodes
	| m |
	m := OCParser parseExpression: (self templateFor: aSelector).
	m receiver: receiverNode.
	m arguments: argNodes.
	^ m'.
cm value: comp value: 'nodes' value: 'thunk: aNode
	^ OCBlockNode arguments: #() body: (OCSequenceNode statements: { aNode })'.
cm value: comp value: 'nodes' value: 'blockWithArgs: argNodes temps: tempNodes statements: statementNodes
	^ OCBlockNode arguments: argNodes body: (OCSequenceNode temporaries: tempNodes statements: statementNodes)'.
cm value: comp value: 'nodes' value: 'blockWithArgs: argNodes statements: statementNodes
	^ self blockWithArgs: argNodes temps: #() statements: statementNodes'.
cm value: comp value: 'nodes' value: 'globalEnvNode
	^ self messageNode: (OCVariableNode named: ''LispEnvironment'') selector: #default arguments: #()'.
cm value: comp value: 'nodes' value: 'emptyListNode
	^ self messageNode: (OCVariableNode named: ''LispEmptyList'') selector: #default arguments: #()'.
cm value: comp value: 'nodes' value: 'symbolNode: aLispSymbol
	^ self messageNode: (OCVariableNode named: ''LispSymbol'')
		selector: #named:
		arguments: { OCLiteralValueNode value: aLispSymbol name }'.

"=== list helpers =========================================================="
cm value: comp value: 'private' value: 'listToArray: aList
	(aList isKindOf: LispCons) ifTrue: [^ aList lispElements asArray].
	^ #()'.

"=== application ==========================================================="
cm value: comp value: 'translating' value: 'applyFn: fnNode toArgNodes: argNodes
	| n sel |
	n := argNodes size.
	n = 0 ifTrue: [^ self messageNode: fnNode selector: #value arguments: #()].
	n > 4 ifTrue: [^ self compileError: ''application with more than 4 arguments is not supported in Phase 3''].
	sel := (String streamContents: [:s | n timesRepeat: [s nextPutAll: ''value:'']]) asSymbol.
	^ self messageNode: fnNode selector: sel arguments: argNodes'.
cm value: comp value: 'translating' value: 'translateApplication: form inScope: scope
	| items fnNode argNodes |
	items := self listToArray: form.
	fnNode := self translate: items first inScope: scope.
	argNodes := items allButFirst collect: [:d | self translate: d inScope: scope].
	^ self applyFn: fnNode toArgNodes: argNodes'.

"=== core dispatch ========================================================="
cm value: comp value: 'translating' value: 'translate: datum inScope: scope
	(datum isKindOf: LispCons) ifTrue: [^ self translateForm: datum inScope: scope].
	(datum isKindOf: LispSymbol) ifTrue: [^ self translateVariable: datum inScope: scope].
	(datum == LispEmptyList default) ifTrue: [^ self emptyListNode].
	^ self literalNode: datum'.
cm value: comp value: 'translating' value: 'translateVariable: sym inScope: scope
	| name |
	name := scope at: sym ifAbsent: [nil].
	name notNil ifTrue: [^ OCVariableNode named: name].
	^ self messageNode: self globalEnvNode selector: #lookup: arguments: { self symbolNode: sym }'.
cm value: comp value: 'translating' value: 'translateForm: form inScope: scope
	| op opName |
	op := form car.
	opName := (op isKindOf: LispSymbol) ifTrue: [op name] ifFalse: [nil].
	opName = ''quote'' ifTrue: [^ self reconstruct: form cdr car].
	opName = ''if'' ifTrue: [^ self translateIf: form inScope: scope].
	opName = ''begin'' ifTrue: [^ self translateBegin: (self listToArray: form cdr) inScope: scope].
	opName = ''lambda'' ifTrue: [^ self translateLambda: form inScope: scope].
	opName = ''let'' ifTrue: [^ self translateLet: form inScope: scope].
	opName = ''define'' ifTrue: [^ self translateDefine: form inScope: scope].
	opName = ''set!!'' ifTrue: [^ self translateSet: form inScope: scope].
	^ self translateApplication: form inScope: scope'.

"=== special forms ========================================================="
cm value: comp value: 'translating' value: 'reconstruct: datum
	(datum isKindOf: LispCons) ifTrue: [
		^ self messageNode: (OCVariableNode named: ''LispCons'')
			selector: #car:cdr:
			arguments: { self reconstruct: datum car. self reconstruct: datum cdr }].
	(datum isKindOf: LispSymbol) ifTrue: [^ self symbolNode: datum].
	(datum == LispEmptyList default) ifTrue: [^ self emptyListNode].
	^ self literalNode: datum'.
cm value: comp value: 'translating' value: 'translateIf: form inScope: scope
	| args testN thenN elseN truthyN |
	args := self listToArray: form cdr.
	args size < 2 ifTrue: [^ self compileError: ''if needs a test and a then-branch''].
	testN := self translate: (args at: 1) inScope: scope.
	thenN := self translate: (args at: 2) inScope: scope.
	elseN := args size >= 3 ifTrue: [self translate: (args at: 3) inScope: scope] ifFalse: [self emptyListNode].
	truthyN := self messageNode: (OCVariableNode named: ''LispCore'') selector: #isTruthy: arguments: { testN }.
	^ self messageNode: truthyN selector: #ifTrue:ifFalse: arguments: { self thunk: thenN. self thunk: elseN }'.
cm value: comp value: 'translating' value: 'translateBegin: dataArray inScope: scope
	dataArray isEmpty ifTrue: [^ self emptyListNode].
	dataArray size = 1 ifTrue: [^ self translate: dataArray first inScope: scope].
	^ self messageNode: (self blockWithArgs: #() statements: (dataArray collect: [:d | self translate: d inScope: scope]))
		selector: #value
		arguments: #()'.
cm value: comp value: 'translating' value: 'translateLambda: form inScope: scope
	| parts params bodyData childScope argNodes tempNodes inits bodyNodes |
	parts := self listToArray: form cdr.
	params := self listToArray: parts first.
	bodyData := parts allButFirst.
	childScope := scope copy.
	argNodes := OrderedCollection new.
	tempNodes := OrderedCollection new.
	inits := OrderedCollection new.
	params do: [:p | | argNm tempNm |
		argNm := self nextName.
		tempNm := self nextName.
		childScope at: p put: tempNm.
		argNodes add: (OCVariableNode named: argNm).
		tempNodes add: (OCVariableNode named: tempNm).
		inits add: (OCAssignmentNode variable: (OCVariableNode named: tempNm) value: (OCVariableNode named: argNm))].
	bodyNodes := bodyData collect: [:d | self translate: d inScope: childScope].
	bodyNodes isEmpty ifTrue: [bodyNodes := { self emptyListNode }].
	^ self blockWithArgs: argNodes asArray temps: tempNodes asArray statements: (inits asArray , bodyNodes)'.
cm value: comp value: 'translating' value: 'translateLet: form inScope: scope
	| parts bindings bodyData params valueData lambdaForm appForm |
	parts := self listToArray: form cdr.
	bindings := self listToArray: parts first.
	bodyData := parts allButFirst.
	params := bindings collect: [:b | (self listToArray: b) first].
	valueData := bindings collect: [:b | (self listToArray: b) second].
	lambdaForm := LispCons car: (LispSymbol named: ''lambda'')
		cdr: (LispCons car: (LispCons fromArray: params asArray) cdr: (LispCons fromArray: bodyData)).
	appForm := LispCons car: lambdaForm cdr: (LispCons fromArray: valueData asArray).
	^ self translate: appForm inScope: scope'.
cm value: comp value: 'translating' value: 'translateDefine: form inScope: scope
	| parts target nameSym valueNode |
	parts := self listToArray: form cdr.
	target := parts first.
	(target isKindOf: LispCons)
		ifTrue: [
			nameSym := target car.
			valueNode := self translateLambda: (self makeLambda: target cdr body: parts allButFirst) inScope: scope]
		ifFalse: [
			nameSym := target.
			valueNode := self translate: (parts at: 2) inScope: scope].
	^ self messageNode: self globalEnvNode selector: #define:value: arguments: { self symbolNode: nameSym. valueNode }'.
cm value: comp value: 'translating' value: 'makeLambda: paramsList body: bodyArray
	^ LispCons car: (LispSymbol named: ''lambda'')
		cdr: (LispCons car: paramsList cdr: (LispCons fromArray: bodyArray))'.
cm value: comp value: 'translating' value: 'translateSet: form inScope: scope
	| parts sym name valueNode |
	parts := self listToArray: form cdr.
	sym := parts first.
	valueNode := self translate: (parts at: 2) inScope: scope.
	name := scope at: sym ifAbsent: [nil].
	name notNil
		ifTrue: [^ OCAssignmentNode variable: (OCVariableNode named: name) value: valueNode]
		ifFalse: [^ self messageNode: self globalEnvNode selector: #set:value: arguments: { self symbolNode: sym. valueNode }]'.

"=== entry points =========================================================="
cm value: comp value: 'compiling' value: 'compile: datum
	| exprNode method |
	counter := 0.
	exprNode := self translate: datum inScope: IdentityDictionary new.
	method := OCMethodNode selector: #doIt arguments: #()
		body: (OCSequenceNode statements: { OCReturnNode value: exprNode }).
	method doSemanticAnalysis.
	^ method generateMethod'.
cm value: comp value: 'evaluating' value: 'eval: datum
	^ (self compile: datum) valueWithReceiver: nil arguments: #()'.
cm value: comp value: 'evaluating' value: 'evalString: aString
	^ self eval: (LispReader read: aString)'.
cm value: comp value: 'evaluating' value: 'evalAll: aString
	| result |
	result := LispEmptyList default.
	(LispReader readAll: aString) do: [:f | result := self eval: f].
	^ result'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Compiler'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
