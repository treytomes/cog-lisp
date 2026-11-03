"============================================================================
 cog-lisp : compiler  (package CogLisp-Compiler)
 LISP s-expression -> Smalltalk AST (OC nodes) -> Opal -> CompiledMethod.
 Specs: phase-3-compiler-core.md (core), phase-5-repl-runner.md (source
 retention, unspecified value), phase-6-optimization.md (proper tail calls,
 fast calls, global cells, literal quote, direct let).

 LOADER script (see coglisp-reader.st). Must be filed in AFTER coglisp-reader.st
 and coglisp-core.st. Note: the set-bang symbol inside is written as a doubled
 bang so the chunk reader keeps it intact.

 Classes: LispCompiler, LispCompileError.

 Mechanism (all verified live, see CLAUDE.md): message nodes are built by
 template-splice (parse a skeleton for the selector, then swap receiver/args),
 because OCMessageNode's selector constructors fail. Methods compile via
 doSemanticAnalysis + generateMethod. Arbitrary objects (global cells, quoted
 data) can be literals and stay writable.

 Optimizations (Phase 6) are named options, all on by default:
   #tailCalls #fastCalls #globalCells #literalQuote #directLet #inlinePrimitives
 LispCompiler withoutOptions: #(...) do: [...] switches some off, for
 benchmarks and debugging.
 ============================================================================"
| failures cm comp err |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

comp := (Object << #LispCompiler)
	slots: { #counter. #sourceMap. #options. #selfLoop. #inlineTemps. #topForm. #sourceContext. #inBody. #expansionDepth };
	sharedVariables: { #DefaultOptions };
	package: 'CogLisp-Compiler';
	install.
err  := (LispError << #LispCompileError) package: 'CogLisp-Compiler'; install.

"=== options ==============================================================="
cm value: comp class value: 'options' value: 'allOptions
	^ #(#tailCalls #fastCalls #globalCells #literalQuote #directLet #inlinePrimitives)'.
cm value: comp class value: 'options' value: 'defaultOptions
	DefaultOptions isNil ifTrue: [DefaultOptions := self allOptions asSet].
	^ DefaultOptions'.
cm value: comp class value: 'options' value: 'withoutOptions: anArray do: aBlock
	"Compile with some optimizations switched off while aBlock runs."
	| saved |
	saved := self defaultOptions copy.
	DefaultOptions := saved copy.
	anArray do: [:each | DefaultOptions remove: each ifAbsent: []].
	^ aBlock ensure: [DefaultOptions := saved]'.
cm value: comp value: 'options' value: 'uses: anOption
	^ options includes: anOption'.

"=== node-building helpers ================================================="
cm value: comp value: 'initialization' value: 'initialize
	counter := 0.
	options := self class defaultOptions copy'.
cm value: comp value: 'private' value: 'nextName
	counter := counter + 1.
	^ ''l'' , counter printString'.
cm value: comp value: 'private' value: 'compileError: aString
	^ (LispCompileError new) signal: aString'.
cm value: comp value: 'nodes' value: 'literalNode: aValue
	^ OCLiteralValueNode value: aValue'.
cm value: comp value: 'nodes' value: 'var: aName
	^ OCVariableNode named: aName'.
cm value: comp value: 'nodes' value: 'assign: aName value: aNode
	^ OCAssignmentNode variable: (self var: aName) value: aNode'.
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
cm value: comp value: 'nodes' value: 'valueSelectorFor: n
	"value, value:, value:value:, ... for evaluating a block of n arguments"
	n = 0 ifTrue: [^ #value].
	^ (String streamContents: [:s | n timesRepeat: [s nextPutAll: ''value:'']]) asSymbol'.
cm value: comp value: 'nodes' value: 'unspecifiedNode
	^ self messageNode: (self var: ''LispUnspecified'') selector: #default arguments: #()'.
cm value: comp value: 'nodes' value: 'andUnspecified: aNode
	"Evaluate aNode for effect, then yield the unspecified value (Phase 5 section 5.1)."
	"true ifTrue: [...] is inlined by Opal: no closure, and no variable it assigns is
	 forced into the heap (review C-9)."
	^ self messageNode: (self literalNode: true)
		selector: #ifTrue:
		arguments: { self blockWithArgs: #() statements: { aNode. self unspecifiedNode } }'.
cm value: comp value: 'source' value: 'sourceOf: form
	"Exact source text of form if the reader recorded it (Phase 5 section 5.2). A
	 form built by a macro has no text of its own, so it gets the text of the macro
	 call it came from (Phase 7 section 5.3). Otherwise, its printed form."
	| text |
	sourceMap notNil ifTrue: [
		text := sourceMap sourceFor: form.
		text notNil ifTrue: [^ text]].
	sourceContext notNil ifTrue: [^ sourceContext].
	^ LispPrinter writeString: form'.
cm value: comp value: 'source' value: 'recordedSourceOf: form
	"Only text the reader recorded for form itself, or nil."
	sourceMap isNil ifTrue: [^ nil].
	^ sourceMap sourceFor: form'.
cm value: comp value: 'nodes' value: 'thunk: aNode
	^ OCBlockNode arguments: #() body: (OCSequenceNode statements: { aNode })'.
cm value: comp value: 'nodes' value: 'blockWithArgs: argNodes temps: tempNodes statements: statementNodes
	^ OCBlockNode arguments: argNodes body: (OCSequenceNode temporaries: tempNodes statements: statementNodes)'.
cm value: comp value: 'nodes' value: 'blockWithArgs: argNodes statements: statementNodes
	^ self blockWithArgs: argNodes temps: #() statements: statementNodes'.
cm value: comp value: 'nodes' value: 'arrayNode: elementNodes
	| n |
	n := OCParser parseExpression: ''{0}''.
	n statements: elementNodes.
	^ n'.
cm value: comp value: 'nodes' value: 'emptyListNode
	^ self messageNode: (self var: ''LispEmptyList'') selector: #default arguments: #()'.
cm value: comp value: 'nodes' value: 'symbolNode: aLispSymbol
	^ self messageNode: (self var: ''LispSymbol'')
		selector: #named:
		arguments: { OCLiteralValueNode value: aLispSymbol name }'.
cm value: comp value: 'private' value: 'listToArray: aList
	"The elements of a proper list in code. Anything else is bad syntax (review C-6)."
	aList == LispEmptyList default ifTrue: [^ #()].
	(aList isKindOf: LispCons) ifFalse: [^ self compileError: ''bad syntax: expected a list: '' , (self show: aList)].
	aList isProperList ifFalse: [^ self compileError: ''bad syntax: improper list: '' , (self show: aList)].
	^ aList lispElements asArray'.
cm value: comp value: 'syntax checks' value: 'show: aDatum
	^ LispPrinter writeString: aDatum limitedTo: 60'.
cm value: comp value: 'syntax checks' value: 'syntaxError: aName form: aForm
	^ self compileError: aName , '': bad syntax: '' , (self show: aForm)'.
cm value: comp value: 'syntax checks' value: 'check: aForm operands: min to: max
	"aForm has between min and max operands (max nil: no limit)."
	| n |
	n := (self listToArray: aForm cdr) size.
	(n < min or: [max notNil and: [n > max]]) ifTrue: [^ self syntaxError: aForm car name form: aForm]'.
cm value: comp value: 'syntax checks' value: 'checkDefine: aForm
	"(define name expr) or (define (name . params) body...)"
	| parts target |
	parts := self listToArray: aForm cdr.
	parts isEmpty ifTrue: [^ self syntaxError: ''define'' form: aForm].
	target := parts first.
	(target isKindOf: LispCons) ifTrue: [
		(target car isKindOf: LispSymbol) ifFalse: [^ self compileError: ''define: bad name: '' , (self show: target car)].
		^ self].
	(target isKindOf: LispSymbol) ifFalse: [^ self compileError: ''define: bad name: '' , (self show: target)].
	parts size = 2 ifFalse: [^ self syntaxError: ''define'' form: aForm]'.
cm value: comp value: 'syntax checks' value: 'checkBindings: data in: aForm
	"((name expr) ...), each name a symbol, none twice. Answer the bindings as arrays."
	| bindings seen |
	seen := IdentitySet new.
	bindings := (self listToArray: data) collect: [:b | | pair |
		pair := (b isKindOf: LispCons) ifTrue: [self listToArray: b] ifFalse: [#()].
		(pair size = 2 and: [pair first isKindOf: LispSymbol]) ifFalse: [
			^ self compileError: ''let: bad binding: '' , (self show: b)].
		(seen includes: pair first) ifTrue: [^ self compileError: ''let: duplicate name: '' , pair first name].
		seen add: pair first.
		pair].
	^ bindings'.

"=== globals: cells (Phase 6 section 5.2) or environment lookups ==========="
cm value: comp value: 'globals' value: 'globalEnvNode
	^ self messageNode: (self var: ''LispEnvironment'') selector: #default arguments: #()'.
cm value: comp value: 'globals' value: 'cellNode: aSymbol
	"The global cell itself, resolved now and held as a literal."
	^ self literalNode: (LispEnvironment default cellFor: aSymbol)'.
cm value: comp value: 'globals' value: 'globalRead: aSymbol
	(self uses: #globalCells) ifTrue: [^ self messageNode: (self cellNode: aSymbol) selector: #value arguments: #()].
	^ self messageNode: self globalEnvNode selector: #lookup: arguments: { self symbolNode: aSymbol }'.
cm value: comp value: 'globals' value: 'globalDefine: aSymbol value: aNode
	(self uses: #globalCells) ifTrue: [^ self messageNode: (self cellNode: aSymbol) selector: #define: arguments: { aNode }].
	^ self messageNode: self globalEnvNode selector: #define:value: arguments: { self symbolNode: aSymbol. aNode }'.
cm value: comp value: 'globals' value: 'globalAssign: aSymbol value: aNode
	(self uses: #globalCells) ifTrue: [^ self messageNode: (self cellNode: aSymbol) selector: #assign: arguments: { aNode }].
	^ self messageNode: self globalEnvNode selector: #set:value: arguments: { self symbolNode: aSymbol. aNode }'.

"=== calls (Phase 6 sections 4 and 5.1) ===================================="
cm value: comp value: 'calls' value: 'callNode: fnNode args: argNodes
	"An ordinary (non-tail) call. It drives any bounce the callee returns."
	| n sel |
	n := argNodes size.
	((self uses: #fastCalls) and: [n <= 4]) ifTrue: [
		sel := (String streamContents: [:s |
			s nextPutAll: ''call:''.
			n timesRepeat: [s nextPutAll: ''with:'']]) asSymbol.
		^ self messageNode: (self var: ''LispProcedure'') selector: sel arguments: { fnNode } , argNodes].
	^ self messageNode: (self var: ''LispProcedure'') selector: #apply:to: arguments: { fnNode. self arrayNode: argNodes }'.
cm value: comp value: 'calls' value: 'tailCallNode: fnNode args: argNodes
	"A call in tail position: return a bounce for the caller to run, or, for a
	 primitive, call it directly (it cannot grow the stack)."
	| n sel |
	n := argNodes size.
	((self uses: #fastCalls) and: [n <= 4]) ifTrue: [
		sel := (String streamContents: [:s |
			s nextPutAll: ''tailCall:''.
			n timesRepeat: [s nextPutAll: ''with:'']]) asSymbol.
		^ self messageNode: (self var: ''LispProcedure'') selector: sel arguments: { fnNode } , argNodes].
	^ self messageNode: (self var: ''LispProcedure'') selector: #tailCall:to: arguments: { fnNode. self arrayNode: argNodes }'.
cm value: comp value: 'calls' value: 'isSelfTailCall: op args: argData inScope: scope
	selfLoop isNil ifTrue: [^ false].
	op == (selfLoop at: #name) ifFalse: [^ false].
	"a global procedure: op must not be shadowed; a local one (review C-8): op must
	 still name the same local, not one bound inside the body"
	(selfLoop at: #local)
		ifNil: [(scope includesKey: op) ifTrue: [^ false]]
		ifNotNil: [:t | (scope at: op ifAbsent: [nil]) = t ifFalse: [^ false]].
	^ argData size = (selfLoop at: #params) size'.
cm value: comp value: 'calls' value: 'selfLoopRead
	"What the loop compares with itself: the global cell, or the local variable."
	^ (selfLoop at: #local)
		ifNil: [self globalRead: (selfLoop at: #name)]
		ifNotNil: [:t | self var: t]'.
cm value: comp value: 'calls' value: 'translateSelfTailCall: argData inScope: scope
	"Go round the loop again (Phase 6 section 4.2) if the global still names this
	 procedure; otherwise make an ordinary tail call to whatever it names now."
	"The arguments are evaluated once, into scratch temps shared by every self tail
	 call of this loop (review C-1, C-12): safe, since no self tail call can run
	 while another one''s arguments are being evaluated (they are not in tail
	 position). Then: true ifTrue: [s1 := a1. ... (p == f) ifTrue: [again] ifFalse: [tail call]]."
	| scratch statements thenStatements check elseNode |
	selfLoop at: #used put: true.
	scratch := selfLoop at: #scratch ifAbsentPut: [
		argData collect: [:d | | nm | nm := self nextName. (selfLoop at: #temps) add: nm. nm]].
	statements := OrderedCollection new.
	scratch with: argData do: [:t :d | statements add: (self assign: t value: (self translate: d inScope: scope))].
	thenStatements := OrderedCollection new.
	(selfLoop at: #params) with: scratch do: [:p :t | thenStatements add: (self assign: p value: (self var: t))].
	thenStatements add: (self assign: (selfLoop at: #again) value: (self literalNode: true)).
	thenStatements add: (self literalNode: nil).
	check := self messageNode: self selfLoopRead selector: #== arguments: { self var: (selfLoop at: #proc) }.
	elseNode := self tailCallNode: self selfLoopRead args: (scratch collect: [:t | self var: t]).
	statements add: (self messageNode: check selector: #ifTrue:ifFalse: arguments: {
		self blockWithArgs: #() statements: thenStatements asArray.
		self thunk: elseNode }).
	^ self messageNode: (self literalNode: true)
		selector: #ifTrue:
		arguments: { self blockWithArgs: #() statements: statements asArray }'.
cm value: comp value: 'calls' value: 'translateApplication: form inScope: scope tail: tail
	| items op argData fnNode argNodes |
	items := self listToArray: form.
	op := items first.
	argData := items allButFirst.
	(tail and: [self isSelfTailCall: op args: argData inScope: scope])
		ifTrue: [^ self translateSelfTailCall: argData inScope: scope].
	(self inlinablePrimitive: op args: argData inScope: scope) ifNotNil: [:prim |
		^ self translateInline: prim op: op args: argData inScope: scope tail: tail].
	fnNode := self translate: op inScope: scope.
	argNodes := argData collect: [:d | self translate: d inScope: scope].
	(tail and: [self uses: #tailCalls]) ifTrue: [^ self tailCallNode: fnNode args: argNodes].
	^ self callNode: fnNode args: argNodes'.

"=== guarded inlining of primitives (Phase 6 section 11) ==================="
cm value: comp value: 'inlining' value: 'inlinablePrimitive: op args: argData inScope: scope
	"The primitive that op names right now, if a call to it can be inlined; else nil."
	| prim spec |
	(self uses: #inlinePrimitives) ifFalse: [^ nil].
	(op isKindOf: LispSymbol) ifFalse: [^ nil].
	(scope includesKey: op) ifTrue: [^ nil].
	prim := (LispEnvironment default cellFor: op) valueIfUnbound: [^ nil].
	"LispProcedure is in the runtime package, which loads after this one"
	(prim respondsTo: #inlineSpec) ifFalse: [^ nil].
	spec := prim inlineSpec.
	(spec notNil and: [spec first = argData size]) ifFalse: [^ nil].
	"Each nested call among the arguments needs a temporary, and temporaries of
	 inlined blocks all land in the enclosing procedure frame, which the VM caps.
	 Past a budget per procedure, just make an ordinary call."
	inlineTemps + (argData count: [:d | (self isSimpleArg: d) not]) > 12 ifTrue: [^ nil].
	^ prim'.
cm value: comp value: 'inlining' value: 'isSimpleArg: datum
	"Cheap to evaluate and free of side effects other than an unbound-variable
	 error: a literal, a quoted datum, or a variable. Used directly in the code,
	 without a temporary; it is still evaluated once, as only one branch runs."
	(datum isKindOf: LispCons) ifFalse: [^ true].
	^ datum car == (LispSymbol named: ''quote'')'.
cm value: comp value: 'inlining' value: 'translateInline: prim op: op args: argData inScope: scope tail: tail
	"op == prim ifTrue: [<inline form>] ifFalse: [<ordinary call of op>]
	 where each argument is used directly if simple, else evaluated first into a
	 temporary: true ifTrue: [| x | x := a. <the conditional above>]. Opal inlines
	 every block here, so this costs no closure. The guard keeps a redefinition of
	 op working, in code compiled before it as well."
	| spec temps statements argNode fast slow guard |
	spec := prim inlineSpec.
	temps := OrderedCollection new.
	statements := OrderedCollection new.
	argData do: [:d | (self isSimpleArg: d) ifFalse: [ | nm |
		nm := self nextName.
		temps add: nm.
		statements add: (self assign: nm value: (self translate: d inScope: scope))]].
	inlineTemps := inlineTemps + temps size.
	argNode := [:i | | d |
		d := argData at: i.
		(self isSimpleArg: d)
			ifTrue: [self translate: d inScope: scope]
			ifFalse: [self var: (temps at: ((1 to: i) count: [:k | (self isSimpleArg: (argData at: k)) not]))]].
	(spec at: 2) = #identity
		ifTrue: [fast := self messageNode: (argNode value: 1) selector: #== arguments: { self literalNode: (spec at: 3) }]
		ifFalse: [fast := self messageNode: (argNode value: 1) selector: (spec at: 3)
			arguments: ((2 to: argData size) collect: [:i | argNode value: i])].
	slow := (tail and: [self uses: #tailCalls])
		ifTrue: [self tailCallNode: (self globalRead: op) args: ((1 to: argData size) collect: [:i | argNode value: i])]
		ifFalse: [self callNode: (self globalRead: op) args: ((1 to: argData size) collect: [:i | argNode value: i])].
	guard := self messageNode: (self globalRead: op) selector: #== arguments: { self literalNode: prim }.
	guard := self messageNode: guard selector: #ifTrue:ifFalse: arguments: { self thunk: fast. self thunk: slow }.
	temps isEmpty ifTrue: [^ guard].
	statements add: guard.
	^ self messageNode: (self literalNode: true)
		selector: #ifTrue:
		arguments: { self blockWithArgs: #() temps: (temps collect: [:nm | self var: nm]) asArray statements: statements asArray }'.

"=== core dispatch ========================================================="
cm value: comp value: 'translating' value: 'translate: datum inScope: scope
	^ self translate: datum inScope: scope tail: false'.
cm value: comp value: 'translating' value: 'translate: datum inScope: scope tail: tail
	(datum isKindOf: LispCons) ifTrue: [^ self translateForm: datum inScope: scope tail: tail].
	(datum isKindOf: LispSymbol) ifTrue: [^ self translateVariable: datum inScope: scope].
	(datum == LispEmptyList default) ifTrue: [^ self emptyListNode].
	^ self literalNode: datum'.
cm value: comp value: 'translating' value: 'translateVariable: sym inScope: scope
	| name |
	name := scope at: sym ifAbsent: [nil].
	name notNil ifTrue: [^ self var: name].
	(self macroFor: sym inScope: scope) notNil ifTrue: [
		^ self compileError: ''macro used as a value: '' , sym name].
	^ self globalRead: sym'.
cm value: comp value: 'translating' value: 'translateForm: form inScope: scope tail: tail
	| op opName |
	op := form car.
	opName := (op isKindOf: LispSymbol) ifTrue: [op name] ifFalse: [nil].
	opName = ''quote'' ifTrue: [self check: form operands: 1 to: 1. ^ self quoteNode: form cdr car].
	opName = ''if'' ifTrue: [self check: form operands: 2 to: 3. ^ self translateIf: form inScope: scope tail: tail].
	opName = ''begin'' ifTrue: [^ self translateBegin: (self listToArray: form cdr) inScope: scope tail: tail].
	opName = ''lambda'' ifTrue: [self check: form operands: 1 to: nil. ^ self translateLambda: form inScope: scope].
	opName = ''let'' ifTrue: [self check: form operands: 1 to: nil. ^ self translateLet: form inScope: scope tail: tail].
	opName = ''define'' ifTrue: [self checkDefine: form. ^ self translateDefine: form inScope: scope].
	opName = ''set!!'' ifTrue: [
		self check: form operands: 2 to: 2.
		(form cdr car isKindOf: LispSymbol) ifFalse: [^ self compileError: ''set!!: bad name: '' , (self show: form cdr car)].
		^ self translateSet: form inScope: scope].
	opName = ''quasiquote'' ifTrue: [self check: form operands: 1 to: 1. ^ self qqNode: form cdr car level: 0 inScope: scope].
	opName = ''define-macro'' ifTrue: [self check: form operands: 2 to: nil. ^ self translateDefineMacro: form inScope: scope].
	opName = ''send'' ifTrue: [^ self translateSend: form inScope: scope].
	opName = ''smalltalk'' ifTrue: [^ self translateSmalltalkGlobal: form].
	(self macroFor: op inScope: scope) ifNotNil: [:m |
		^ self translateMacroCall: form macro: m inScope: scope tail: tail].
	^ self translateApplication: form inScope: scope tail: tail'.

"=== macros (Phase 7 section 5) ============================================"
cm value: comp value: 'macros' value: 'macroFor: op inScope: scope
	"The macro op names at compile time, if op is a symbol that is not a local."
	| value |
	(op isKindOf: LispSymbol) ifFalse: [^ nil].
	(scope includesKey: op) ifTrue: [^ nil].
	value := (LispEnvironment default cellFor: op) valueIfUnbound: [^ nil].
	(value isKindOf: LispMacro) ifFalse: [^ nil].
	^ value'.
cm value: comp value: 'macros' value: 'expand: form with: aMacro
	"Run the expander on the operands of form, unevaluated."
	| name |
	name := (form car isKindOf: LispSymbol) ifTrue: [form car name] ifFalse: [''?''].
	^ [(Smalltalk at: #LispProcedure) apply: aMacro expander to: (self listToArray: form cdr)]
		on: Error
		do: [:e | self compileError: ''error expanding '' , name , '': '' ,
			((e messageText isNil or: [e messageText isEmpty]) ifTrue: [e class name] ifFalse: [e messageText])]'.
cm value: comp value: 'macros' value: 'translateMacroCall: form macro: aMacro inScope: scope tail: tail
	"Compile the expansion in place of form, keeping its tail position. Lambdas the
	 expansion builds take the source text of this call (section 5.3), and a macro
	 call at top level keeps its expansion at top level."
	| expansion text savedContext savedTop |
	expansionDepth := (expansionDepth ifNil: [0]) + 1.
	expansionDepth > self class maxExpansions ifTrue: [expansionDepth := 0. ^ self expansionTooDeep: form].
	expansion := [self expand: form with: aMacro] ifCurtailed: [expansionDepth := expansionDepth - 1].
	text := self recordedSourceOf: form.
	savedContext := sourceContext.
	savedTop := topForm.
	text notNil ifTrue: [sourceContext := text].
	form == topForm ifTrue: [topForm := expansion].
	^ [self translate: expansion inScope: scope tail: tail]
		ensure: [sourceContext := savedContext. topForm := savedTop. expansionDepth := expansionDepth - 1]'.
cm value: comp value: 'macros' value: 'expansionTooDeep: form
	"A macro that expands into itself forever would otherwise hang (review C-7)."
	^ self compileError: ''macro expansion too deep (more than '' , self class maxExpansions printString ,
		'' steps): '' , ((form car isKindOf: LispSymbol) ifTrue: [form car name] ifFalse: [self show: form])'.
cm value: comp class value: 'limits' value: 'maxExpansions
	^ 10000'.
cm value: comp value: 'macros' value: 'translateDefineMacro: form inScope: scope
	"(define-macro (name . params) body...) or (define-macro name expander-expr)"
	| parts target nameSym valueNode |
	form == topForm ifFalse: [^ self compileError: ''define-macro is allowed only at top level''].
	parts := self listToArray: form cdr.
	parts isEmpty ifTrue: [^ self compileError: ''define-macro needs a name''].
	target := parts first.
	(target isKindOf: LispCons)
		ifTrue: [
			nameSym := target car.
			valueNode := self translateLambda: (self makeLambda: target cdr body: parts allButFirst)
				inScope: scope source: (self sourceOf: form) defining: nil]
		ifFalse: [
			nameSym := target.
			valueNode := self translate: (parts at: 2) inScope: scope].
	^ self andUnspecified: (self globalDefine: nameSym
		value: (self messageNode: (self var: ''LispMacro'') selector: #expander: arguments: { valueNode }))'.
cm value: comp value: 'macros' value: 'macroexpand1: form
	"Expand form once if it is a call of a global macro; else answer it unchanged."
	| m |
	(form isKindOf: LispCons) ifFalse: [^ form].
	m := self macroFor: form car inScope: IdentityDictionary new.
	m isNil ifTrue: [^ form].
	^ self expand: form with: m'.
cm value: comp value: 'macros' value: 'macroexpand: form
	| current next steps |
	current := form.
	steps := 0.
	[next := self macroexpand1: current. next == current] whileFalse: [
		(steps := steps + 1) > self class maxExpansions ifTrue: [^ self expansionTooDeep: form].
		current := next].
	^ current'.

"=== quasiquote (Phase 7 section 4) ========================================"
cm value: comp value: 'quasiquote' value: 'isTagged: datum as: aName
	"datum is the two-element list (aName x)"
	^ (datum isKindOf: LispCons)
		and: [datum car == (LispSymbol named: aName)
		and: [(datum cdr isKindOf: LispCons) and: [datum cdr cdr == LispEmptyList default]]]'.
cm value: comp value: 'quasiquote' value: 'qqIsConstant: t level: n
	"True if nothing in t is evaluated at quasiquote level n."
	(t isKindOf: LispCons) ifFalse: [^ true].
	((self isTagged: t as: ''unquote'') or: [self isTagged: t as: ''unquote-splicing'']) ifTrue: [
		n = 0 ifTrue: [^ false].
		^ self qqIsConstant: t cdr car level: n - 1].
	(self isTagged: t as: ''quasiquote'') ifTrue: [^ self qqIsConstant: t cdr car level: n + 1].
	^ (self qqIsConstant: t car level: n) and: [self qqIsConstant: t cdr level: n]'.
cm value: comp value: 'quasiquote' value: 'qqTagged: aName with: aNode
	"code building the list (aName <aNode value>)"
	^ self messageNode: (self var: ''LispCons'') selector: #car:cdr: arguments: {
		self literalNode: (LispSymbol named: aName).
		self messageNode: (self var: ''LispCons'') selector: #car:cdr: arguments: { aNode. self emptyListNode } }'.
cm value: comp value: 'quasiquote' value: 'qqNode: t level: n inScope: scope
	"Code that builds the structure the template t describes. Constant parts are
	 literals; construction uses LispCons directly, never the global cons/append."
	| head |
	(self qqIsConstant: t level: n) ifTrue: [^ self quoteNode: t].
	(self isTagged: t as: ''unquote'') ifTrue: [
		n = 0 ifTrue: [^ self translate: t cdr car inScope: scope].
		^ self qqTagged: ''unquote'' with: (self qqNode: t cdr car level: n - 1 inScope: scope)].
	(self isTagged: t as: ''unquote-splicing'') ifTrue: [
		n = 0 ifTrue: [^ self compileError: ''unquote-splicing outside a list''].
		^ self qqTagged: ''unquote-splicing'' with: (self qqNode: t cdr car level: n - 1 inScope: scope)].
	(self isTagged: t as: ''quasiquote'') ifTrue: [
		^ self qqTagged: ''quasiquote'' with: (self qqNode: t cdr car level: n + 1 inScope: scope)].
	^ self qqListNode: t level: n inScope: scope'.
cm value: comp value: 'quasiquote' value: 'isLevelZeroSplice: datum level: n
	^ n = 0 and: [self isTagged: datum as: ''unquote-splicing'']'.
cm value: comp value: 'quasiquote' value: 'qqListNode: t level: n inScope: scope
	"The run of elements before a level-0 splice or the tail goes into one brace
	 array: LispCons fromArray: {e1. e2. ...} tail: rest. Nested car:cdr: took two
	 stack slots an element and overflowed the frame at ~25 (review C-3)."
	| elements cur tailNode |
	elements := OrderedCollection new.
	cur := t.
	[(cur isKindOf: LispCons)
		and: [(self isTagged: cur as: ''unquote'') not
		and: [(self isTagged: cur as: ''unquote-splicing'') not
		and: [(self isTagged: cur as: ''quasiquote'') not
		and: [(self isLevelZeroSplice: cur car level: n) not]]]]]
		whileTrue: [
			elements add: (self qqNode: cur car level: n inScope: scope).
			cur := cur cdr].
	tailNode := ((cur isKindOf: LispCons) and: [self isLevelZeroSplice: cur car level: n])
		ifTrue: [self messageNode: (self var: ''LispCons'') selector: #qqAppend:to: arguments: {
			self translate: cur car cdr car inScope: scope.
			self qqNode: cur cdr level: n inScope: scope }]
		ifFalse: [self qqNode: cur level: n inScope: scope].
	elements isEmpty ifTrue: [^ tailNode].
	^ self messageNode: (self var: ''LispCons'') selector: #fromArray:tail: arguments: {
		self arrayNode: elements asArray.
		tailNode }'.

"=== bodies with internal define (Phase 7 section 6) ======================="
cm value: comp value: 'translating' value: 'isDefineForm: datum
	^ (datum isKindOf: LispCons) and: [datum car == (LispSymbol named: ''define'')]'.
cm value: comp value: 'translating' value: 'translateScopedBody: dataArray inScope: childScope tail: tail
	"A procedure or let body. Leading defines are locals of the body, with letrec*
	 semantics: all are in scope throughout, assigned in order. Adds them to
	 childScope and answers { tempNames. statements }.
	 As in R7RS 5.3.2, macro calls at the start of the body are expanded while
	 looking for defines, so a macro may expand to a define, and a begin there is
	 spliced into the body, so a macro may expand to several. Each form carries the
	 source text its lambdas take (section 5.3): the macro call it came from."
	| pending defs rest temps statements item datum m savedContext savedInBody beginSym steps |
	beginSym := LispSymbol named: ''begin''.
	steps := 0.
	pending := OrderedCollection new.
	dataArray do: [:d | pending add: { d. sourceContext }].
	defs := OrderedCollection new.
	rest := nil.
	[rest isNil and: [pending notEmpty]] whileTrue: [
		item := pending removeFirst.
		datum := item first.
		m := (datum isKindOf: LispCons) ifTrue: [self macroFor: datum car inScope: childScope] ifFalse: [nil].
		m notNil
			ifTrue: [
				(steps := steps + 1) > self class maxExpansions ifTrue: [^ self expansionTooDeep: datum].
				pending addFirst: { self expand: datum with: m. (self recordedSourceOf: datum) ifNil: [item second] }]
			ifFalse: [
				(self isDefineForm: datum)
					ifTrue: [ | target nm |
						"in scope at once, so it shadows a macro of the same name in later forms"
						self checkDefine: datum.
						target := (self listToArray: datum cdr) first.
						nm := self nextName.
						childScope at: ((target isKindOf: LispCons) ifTrue: [target car] ifFalse: [target]) put: nm.
						defs add: { datum. item second. nm }]
					ifFalse: [
						"special-form names cannot be rebound locally (review C-14), here as in translateForm:"
						((datum isKindOf: LispCons) and: [datum car == beginSym])
							ifTrue: [(self listToArray: datum cdr) reverseDo: [:d | pending addFirst: { d. item second }]]
							ifFalse: [rest := OrderedCollection with: item]]]].
	rest isNil ifTrue: [rest := OrderedCollection new].
	rest addAll: pending.
	(rest anySatisfy: [:it | self isDefineForm: it first])
		ifTrue: [^ self compileError: ''define after an expression in a body''].
	temps := OrderedCollection new.
	statements := OrderedCollection new.
	defs do: [:d |
		temps add: d third.
		statements add: (self assign: d third value: self unspecifiedNode)].
	savedContext := sourceContext.
	savedInBody := inBody.
	inBody := true.
	[defs do: [:d | | parts target valueData |
		sourceContext := d second.
		parts := self listToArray: d first cdr.
		target := parts first.
		statements add: (self assign: d third value: ((target isKindOf: LispCons)
			ifTrue: [self named: (self translateLambda: (self makeLambda: target cdr body: parts allButFirst)
				inScope: childScope source: (self sourceOf: d first) defining: target car local: d third) as: target car]
			ifFalse: [
				valueData := parts at: 2.
				(self isLambdaForm: valueData)
					ifTrue: [self named: (self translateLambda: valueData inScope: childScope source: (self sourceOf: valueData) defining: target local: d third) as: target]
					ifFalse: [self translate: valueData inScope: childScope]]))].
	 rest isEmpty ifTrue: [statements add: self unspecifiedNode].
	 rest withIndexDo: [:it :i |
		sourceContext := it second.
		statements add: (self translate: it first inScope: childScope tail: (tail and: [i = rest size]))]]
		ensure: [sourceContext := savedContext. inBody := savedInBody].
	^ { temps. statements asArray }'.
cm value: comp value: 'translating' value: 'translateBody: dataArray inScope: scope tail: tail
	"Statements for a body: every form for effect, the last in tail position if the body is."
	dataArray isEmpty ifTrue: [^ { self unspecifiedNode }].
	^ (1 to: dataArray size) collect: [:i |
		self translate: (dataArray at: i) inScope: scope tail: (tail and: [i = dataArray size])]'.

"=== special forms ========================================================="
cm value: comp value: 'translating' value: 'quoteNode: datum
	"A quoted datum is a literal: the same object every time (Phase 6 section 5.3)."
	(self uses: #literalQuote) ifTrue: [^ self literalNode: datum].
	^ self reconstruct: datum'.
cm value: comp value: 'translating' value: 'reconstruct: datum
	(datum isKindOf: LispCons) ifTrue: [
		^ self messageNode: (self var: ''LispCons'')
			selector: #car:cdr:
			arguments: { self reconstruct: datum car. self reconstruct: datum cdr }].
	(datum isKindOf: LispSymbol) ifTrue: [
		"a gensym cannot be looked up by name; embed the symbol itself (review C-13)"
		(LispSymbol isInterned: datum) ifFalse: [^ self literalNode: datum].
		^ self symbolNode: datum].
	(datum == LispEmptyList default) ifTrue: [^ self emptyListNode].
	^ self literalNode: datum'.
cm value: comp value: 'translating' value: 'translateIf: form inScope: scope tail: tail
	| args testN thenN elseN truthyN |
	args := self listToArray: form cdr.
	args size < 2 ifTrue: [^ self compileError: ''if needs a test and a then-branch''].
	testN := self translate: (args at: 1) inScope: scope.
	thenN := self translate: (args at: 2) inScope: scope tail: tail.
	elseN := args size >= 3
		ifTrue: [self translate: (args at: 3) inScope: scope tail: tail]
		ifFalse: [self unspecifiedNode].
	truthyN := self messageNode: (self var: ''LispCore'') selector: #isTruthy: arguments: { testN }.
	^ self messageNode: truthyN selector: #ifTrue:ifFalse: arguments: { self thunk: thenN. self thunk: elseN }'.
cm value: comp value: 'translating' value: 'translateBegin: dataArray inScope: scope tail: tail
	dataArray isEmpty ifTrue: [^ self unspecifiedNode].
	dataArray size = 1 ifTrue: [^ self translate: dataArray first inScope: scope tail: tail].
	"true ifTrue: [...] rather than [...] value: Opal inlines it, so a sequence
	 costs no closure and no frame (derived forms expand to begin often)"
	^ self messageNode: (self literalNode: true)
		selector: #ifTrue:
		arguments: { self blockWithArgs: #() statements: (self translateBody: dataArray inScope: scope tail: tail) }'.
cm value: comp value: 'translating' value: 'parseParams: spec
	"(a b . rest), (a b) or rest: symbols only, none twice (review C-6)."
	| fixed cur all bad |
	bad := [^ self compileError: ''lambda: bad parameter list: '' , (self show: spec)].
	(spec isKindOf: LispSymbol) ifTrue: [^ { #(). spec }].
	fixed := OrderedCollection new.
	cur := spec.
	[cur isKindOf: LispCons] whileTrue: [
		(cur car isKindOf: LispSymbol) ifFalse: [bad value].
		fixed add: cur car.
		cur := cur cdr].
	((cur isKindOf: LispSymbol) or: [cur == LispEmptyList default]) ifFalse: [bad value].
	all := (cur isKindOf: LispSymbol) ifTrue: [fixed , { cur }] ifFalse: [fixed].
	all asSet size = all size ifFalse: [
		^ self compileError: ''lambda: duplicate parameter in '' , (self show: spec)].
	(cur isKindOf: LispSymbol)
		ifTrue: [^ { fixed asArray. cur }]
		ifFalse: [^ { fixed asArray. nil }]'.
cm value: comp value: 'translating' value: 'bindParams: params into: childScope
	"Block arguments are read-only, so each LISP variable is a temporary initialized
	 from its argument. Answer { argNodes. tempNodes. initNodes. tempNames }."
	| argNodes tempNodes inits names |
	argNodes := OrderedCollection new.
	tempNodes := OrderedCollection new.
	inits := OrderedCollection new.
	names := OrderedCollection new.
	params do: [:p | | argNm tempNm |
		argNm := self nextName.
		tempNm := self nextName.
		childScope at: p put: tempNm.
		argNodes add: (self var: argNm).
		tempNodes add: (self var: tempNm).
		names add: tempNm.
		inits add: (self assign: tempNm value: (self var: argNm))].
	^ { argNodes asArray. tempNodes asArray. inits asArray. names asArray }'.
cm value: comp value: 'translating' value: 'translateLambda: form inScope: scope
	^ self translateLambda: form inScope: scope source: (self sourceOf: form) defining: nil'.
cm value: comp value: 'translating' value: 'translateLambda: form inScope: scope source: sourceText defining: nameSym
	^ self translateLambda: form inScope: scope source: sourceText defining: nameSym local: nil'.
cm value: comp value: 'translating' value: 'translateLambda: form inScope: scope source: sourceText defining: nameSym local: localTemp
	"nameSym is the name this lambda is being defined as, or nil: a global, or a local
	 held in the temp localTemp (internal define, named let; review C-8). A defined,
	 fixed-arity procedure compiles its self tail calls as a loop (section 4.2)."
	| parts parsed fixed restSym allParams childScope bound savedLoop savedInlineTemps loop tail body bodyNodes iterNames iterInits localNodes statements temps block procNode procName |
	parts := self listToArray: form cdr.
	parsed := self parseParams: parts first.
	fixed := parsed first.
	restSym := parsed second.
	allParams := restSym isNil ifTrue: [fixed] ifFalse: [fixed , { restSym }].
	childScope := scope copy.
	bound := self bindParams: allParams into: childScope.
	tail := self uses: #tailCalls.
	loop := nil.
	iterNames := #().
	iterInits := #().
	(tail and: [nameSym notNil and: [restSym isNil]]) ifTrue: [
		loop := IdentityDictionary new.
		loop at: #name put: nameSym; at: #local put: localTemp; at: #params put: (bound at: 4);
			at: #proc put: self nextName; at: #again put: self nextName; at: #result put: self nextName;
			at: #temps put: OrderedCollection new; at: #used put: false.
		"The body works on per-iteration copies of the parameters, declared inside the
		 loop block, so a closure made in one iteration keeps that iteration''s
		 values: Opal gives such temps fresh storage each time round (Phase 7)."
		iterNames := allParams collect: [:p | | q | q := self nextName. childScope at: p put: q. q].
		iterInits := (1 to: iterNames size) collect: [:i |
			self assign: (iterNames at: i) value: (self var: ((bound at: 4) at: i))]].
	savedLoop := selfLoop.
	savedInlineTemps := inlineTemps.
	selfLoop := loop.
	inlineTemps := 0.
	body := [self translateScopedBody: parts allButFirst inScope: childScope tail: tail]
		ensure: [selfLoop := savedLoop. inlineTemps := savedInlineTemps].
	bodyNodes := body at: 2.
	localNodes := (iterNames , (body at: 1) asArray) collect: [:nm | self var: nm].
	(loop notNil and: [loop at: #used])
		ifTrue: [
			"again := true. [again] whileTrue: [| q... | again := false. q := p... body... result := last]. result"
			statements := (bound at: 3) asOrderedCollection.
			statements add: (self assign: (loop at: #again) value: (self literalNode: true)).
			statements add: (self messageNode: (self thunk: (self var: (loop at: #again)))
				selector: #whileTrue:
				arguments: { self blockWithArgs: #() temps: localNodes statements:
					({ self assign: (loop at: #again) value: (self literalNode: false) } ,
					 iterInits ,
					 bodyNodes allButLast ,
					 { self assign: (loop at: #result) value: bodyNodes last }) }).
			statements add: (self var: (loop at: #result)).
			temps := (bound at: 2) , ({ loop at: #again. loop at: #result } , (loop at: #temps) asArray
				collect: [:nm | self var: nm]).
			block := self blockWithArgs: (bound at: 1) temps: temps statements: statements asArray]
		ifFalse: [
			block := self blockWithArgs: (bound at: 1) temps: (bound at: 2) , localNodes
				statements: (bound at: 3) , iterInits , bodyNodes].
	procNode := self messageNode: (self var: ''LispProcedure'')
		selector: (restSym isNil ifTrue: [#fixed:arity:source:] ifFalse: [#variadic:required:source:])
		arguments: { block. self literalNode: fixed size. self literalNode: sourceText }.
	(loop notNil and: [loop at: #used]) ifFalse: [^ procNode].
	"The loop compares the global with this very procedure, so bind it to a variable
	 the block can see: [| p | p := LispProcedure fixed: [...p...] .... p] value"
	procName := loop at: #proc.
	^ self messageNode: (self blockWithArgs: #() temps: { self var: procName }
			statements: { self assign: procName value: procNode. self var: procName })
		selector: #value
		arguments: #()'.
cm value: comp value: 'translating' value: 'translateLet: form inScope: scope tail: tail
	| parts bindings bodyData params valueData childScope bound body block |
	parts := self listToArray: form cdr.
	(parts notEmpty and: [parts first isKindOf: LispSymbol]) ifTrue: [
		^ self withSourceOf: form do: [self translateNamedLet: parts inScope: scope tail: tail]].
	bindings := self checkBindings: parts first in: form.
	bodyData := parts allButFirst.
	params := bindings collect: [:b | b first].
	valueData := bindings collect: [:b | b second].
	(self uses: #directLet) ifFalse: [
		"as in Phase 3: an immediately applied lambda"
		^ self withSourceOf: form do: [self translate: (LispCons
				car: (self makeLambda: (LispCons fromArray: params asArray) body: bodyData)
				cdr: (LispCons fromArray: valueData asArray))
			inScope: scope tail: tail]].
	params size > 15 ifTrue: [^ self translateLargeLet: params values: valueData body: bodyData inScope: scope tail: tail].
	"Phase 6 section 5.4: a block evaluated in place; the body inherits tail position."
	childScope := scope copy.
	bound := self bindParams: params into: childScope.
	body := self translateScopedBody: bodyData inScope: childScope tail: tail.
	block := self blockWithArgs: (bound at: 1)
		temps: (bound at: 2) , ((body at: 1) asArray collect: [:nm | self var: nm])
		statements: (bound at: 3) , (body at: 2).
	params size > 4 ifTrue: [
		^ self messageNode: block selector: #valueWithArguments:
			arguments: { self arrayNode: (valueData collect: [:d | self translate: d inScope: scope]) }].
	^ self messageNode: block
		selector: (self valueSelectorFor: params size)
		arguments: (valueData collect: [:d | self translate: d inScope: scope])'.
cm value: comp value: 'translating' value: 'withSourceOf: form do: aBlock
	"Translate code made up from form (named let, let as a lambda) so that its
	 lambdas keep form''s source text, as for a macro call (review C-10)."
	| text saved |
	text := self recordedSourceOf: form.
	text isNil ifTrue: [^ aBlock value].
	saved := sourceContext.
	sourceContext := text.
	^ aBlock ensure: [sourceContext := saved]'.
cm value: comp value: 'translating' value: 'translateLargeLet: params values: valueData body: bodyData inScope: scope tail: tail
	"A let with more bindings than a block may have arguments (15; review C-4):
	 [| v1 ... vn | v1 := e1. ... body] value, each e evaluated in the outer scope."
	| childScope names assigns body |
	names := params collect: [:p | self nextName].
	assigns := names with: valueData collect: [:t :d | self assign: t value: (self translate: d inScope: scope)].
	childScope := scope copy.
	params with: names do: [:p :t | childScope at: p put: t].
	body := self translateScopedBody: bodyData inScope: childScope tail: tail.
	^ self messageNode: (self blockWithArgs: #()
			temps: (names , (body at: 1) asArray collect: [:nm | self var: nm])
			statements: assigns , (body at: 2))
		selector: #value
		arguments: #()'.
cm value: comp value: 'translating' value: 'translateNamedLet: parts inScope: scope tail: tail
	"(let name ((v e)...) body...) is ((let () (define (name v...) body...) name) e...):
	 name is visible in the body only, and the initial values are evaluated outside it."
	| name bindings vars inits defineForm |
	name := parts first.
	parts size < 2 ifTrue: [^ self compileError: ''let: bad syntax: named let '' , name name , '' has no bindings''].
	bindings := self checkBindings: (parts at: 2) in: nil.
	vars := bindings collect: [:b | b first].
	inits := bindings collect: [:b | b second].
	defineForm := LispCons car: (LispSymbol named: ''define'')
		cdr: (LispCons car: (LispCons car: name cdr: (LispCons fromArray: vars asArray))
			cdr: (LispCons fromArray: (parts allButFirst: 2))).
	^ self translate: (LispCons
			car: (LispCons fromArray: { LispSymbol named: ''let''. LispEmptyList default. defineForm. name })
			cdr: (LispCons fromArray: inits asArray))
		inScope: scope tail: tail'.
cm value: comp value: 'interop' value: 'selectorArity: aString
	"The number of arguments of a Smalltalk selector spelled aString, or nil if it
	 is not one: unary (foo), binary (+, ->, ==) or keyword (at:put:)."
	(aString notEmpty and: [aString allSatisfy: [:c | ''+-*/\<>=~@%|&?,'' includes: c]]) ifTrue: [^ 1].
	(aString matchesRegex: ''[a-zA-Z_][a-zA-Z0-9_]*'') ifTrue: [^ 0].
	(aString matchesRegex: ''([a-zA-Z_][a-zA-Z0-9_]*\:)+'') ifTrue: [^ aString occurrencesOf: $:].
	^ nil'.
cm value: comp value: 'interop' value: 'translateSend: form inScope: scope
	"(send receiver selector arg ...): a real Smalltalk message send, the selector
	 unevaluated (specs/phase-7.6-smalltalk-interop.md section 4.1)."
	| parts selector arity args |
	self check: form operands: 2 to: nil.
	parts := self listToArray: form cdr.
	(parts second isKindOf: LispSymbol) ifFalse: [^ self compileError: ''send: bad selector: '' , (self show: parts second)].
	arity := self selectorArity: parts second name.
	arity isNil ifTrue: [^ self compileError: ''send: not a Smalltalk selector: '' , parts second name].
	args := parts allButFirst: 2.
	args size = arity ifFalse: [
		^ self compileError: ''send: '' , parts second name , '' takes '' , arity printString ,
			(arity = 1 ifTrue: ['' argument''] ifFalse: ['' arguments'']) , '', got '' , args size printString].
	selector := parts second name asSymbol.
	"Opal compiles these selectors inline, taking a non-block argument as a plain value:
	 (send #t ifTrue: f) would answer f instead of calling it. Perform them, so the
	 real method runs and sends value to the procedure."
	(self class inlinedSelectors includes: selector) ifTrue: [
		^ self messageNode: (self translate: parts first inScope: scope)
			selector: #perform:withArguments:
			arguments: { self literalNode: selector. self arrayNode: (args collect: [:d | self translate: d inScope: scope]) }].
	^ self messageNode: (self translate: parts first inScope: scope)
		selector: selector
		arguments: (args collect: [:d | self translate: d inScope: scope])'.
cm value: comp class value: 'interop' value: 'inlinedSelectors
	"The messages Opal compiles inline instead of sending (OCASTTranslator)."
	^ #(#ifTrue: #ifFalse: #ifTrue:ifFalse: #ifFalse:ifTrue: #and: #or: #and:and: #or:or:
		#whileTrue: #whileFalse: #whileTrue #whileFalse #to:do: #to:by:do: #timesRepeat: #repeat
		#ifNil: #ifNotNil: #ifNil:ifNotNil: #ifNotNil:ifNil:
		#ifEmpty: #ifNotEmpty: #ifEmpty:ifNotEmpty: #ifNotEmpty:ifEmpty:) asSet'.
cm value: comp value: 'interop' value: 'translateSmalltalkGlobal: form
	"(smalltalk Name): the Smalltalk global, resolved when compiled (section 4.3)."
	| name |
	self check: form operands: 1 to: 1.
	name := form cdr car.
	(name isKindOf: LispSymbol) ifFalse: [^ self compileError: ''smalltalk: bad name: '' , (self show: name)].
	(Smalltalk globals includesKey: name name asSymbol)
		ifFalse: [^ self compileError: ''smalltalk: no Smalltalk global named '' , name name].
	^ self var: name name'.
cm value: comp value: 'translating' value: 'isLambdaForm: datum
	^ (datum isKindOf: LispCons) and: [datum car == (LispSymbol named: ''lambda'')]'.
cm value: comp value: 'translating' value: 'translateDefine: form inScope: scope
	"A global definition. Inside a procedure or let body, a define is a local and is
	 handled by translateScopedBody:, but only at the start of the body; reaching one
	 here from a body means it is in an expression, an error as in R7RS."
	| parts target nameSym valueData valueNode |
	inBody == true ifTrue: [^ self compileError: ''define is allowed only at top level or at the start of a body''].
	parts := self listToArray: form cdr.
	target := parts first.
	(target isKindOf: LispCons)
		ifTrue: [
			nameSym := target car.
			"the source text of the procedure is the whole define form"
			valueNode := self named: (self translateLambda: (self makeLambda: target cdr body: parts allButFirst)
				inScope: scope
				source: (self sourceOf: form)
				defining: nameSym) as: nameSym]
		ifFalse: [
			nameSym := target.
			valueData := parts at: 2.
			valueNode := (self isLambdaForm: valueData)
				ifTrue: [self named: (self translateLambda: valueData inScope: scope source: (self sourceOf: valueData) defining: nameSym) as: nameSym]
				ifFalse: [self translate: valueData inScope: scope]].
	^ self andUnspecified: (self globalDefine: nameSym value: valueNode)'.
cm value: comp value: 'translating' value: 'named: procNode as: aSymbol
	"procNode, a procedure-building node, sent named: so the procedure knows its name (review C-17)."
	^ self messageNode: procNode selector: #named: arguments: { self literalNode: aSymbol name }'.
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
		ifTrue: [^ self andUnspecified: (self assign: name value: valueNode)]
		ifFalse: [^ self andUnspecified: (self globalAssign: sym value: valueNode)]'.

"=== entry points =========================================================="
cm value: comp value: 'compiling' value: 'compile: datum
	^ self compile: datum context: nil'.
cm value: comp value: 'compiling' value: 'compile: datum context: text
	"A top-level form is not in tail position: its calls are ordinary calls."
	| exprNode method |
	counter := 0.
	selfLoop := nil.
	topForm := datum.
	sourceContext := text.
	inBody := false.
	inlineTemps := 0.
	expansionDepth := 0.
	"A host error while translating is malformed input the checks did not catch (review C-6)"
	exprNode := [self translate: datum inScope: IdentityDictionary new tail: false]
		on: Error
		do: [:e | (e isKindOf: LispError) ifTrue: [e pass].
			self compileError: ''bad syntax: '' , (self show: datum)].
	method := OCMethodNode selector: #doIt arguments: #()
		body: (OCSequenceNode statements: { OCReturnNode value: exprNode }).
	"Pharo''s limits (frame size, 15 block arguments) as LISP errors (review C-2)"
	^ [method doSemanticAnalysis.
	   method generateMethod]
		on: Error
		do: [:e | self compileError: (self describeBackEndError: e) , '': '' , (self show: datum)]'.
cm value: comp value: 'compiling' value: 'describeBackEndError: anError
	| text |
	text := anError messageText ifNil: [''''].
	((text includesSubstring: ''too deep'') or: [text includesSubstring: ''out of range''])
		ifTrue: [^ ''too large or too deeply nested to compile''].
	(text includesSubstring: ''Too many arguments'')
		ifTrue: [^ ''too many parameters or let bindings (at most 15)''].
	^ ''cannot compile ('' , anError class name , '' '' , text , '')'''.
cm value: comp value: 'evaluating' value: 'eval: datum
	^ self eval: datum context: nil steps: 0'.
cm value: comp value: 'evaluating' value: 'eval: datum context: text steps: n
	"At top level, the forms of a begin and the expansion of a macro call are
	 themselves top-level forms, compiled and run one after another (R7RS; review
	 C-11). So a define-macro there is at top level, and a macro it defines can be
	 used by the forms after it. text is the source a made-up lambda takes."
	| m result |
	n > self class maxExpansions ifTrue: [^ self expansionTooDeep: datum].
	((datum isKindOf: LispCons) and: [datum car == (LispSymbol named: ''begin'')]) ifTrue: [
		result := LispUnspecified default.
		(self listToArray: datum cdr) do: [:f | result := self eval: f context: text steps: n].
		^ result].
	m := (datum isKindOf: LispCons) ifTrue: [self macroFor: datum car inScope: IdentityDictionary new] ifFalse: [nil].
	m notNil ifTrue: [
		^ self eval: (self expand: datum with: m)
			context: ((self recordedSourceOf: datum) ifNil: [text])
			steps: n + 1].
	^ (self compile: datum context: text) valueWithReceiver: nil arguments: #()'.
cm value: comp value: 'evaluating' value: 'eval: datum from: aReader
	"Evaluate a datum read by aReader, so procedures can keep their exact source text."
	sourceMap := aReader.
	^ [self eval: datum] ensure: [sourceMap := nil]'.
cm value: comp value: 'evaluating' value: 'evalString: aString
	| r |
	r := LispReader on: aString.
	^ self eval: r readSingle from: r'.
cm value: comp value: 'evaluating' value: 'evalAll: aString
	| r d result |
	r := LispReader on: aString.
	result := LispUnspecified default.
	[(d := r next) == LispReader eofObject] whileFalse: [result := self eval: d from: r].
	^ result'.
cm value: comp value: 'evaluating' value: 'evalAll: aString named: aName
	"Like evalAll:, but an error from any form is signalled again as a
	 LispLocatedError saying where it happened: the start of the top-level form, or
	 the offending character for a read error (review R-1). An error that is already
	 located, from a nested load, keeps its own (innermost) location."
	| r d result |
	r := LispReader on: aString.
	result := LispUnspecified default.
	[[(d := r next) == LispReader eofObject] whileFalse: [result := self eval: d from: r]]
		on: Error
		do: [:e | | offset |
			(e isKindOf: LispLocatedError) ifTrue: [e pass].
			offset := (e isKindOf: LispReadError)
				ifTrue: [e position ifNil: [r datumStart]]
				ifFalse: [r datumStart].
			^ (LispLocatedError cause: e file: aName source: aString offset: (offset ifNil: [0])) signal].
	^ result'.
cm value: comp value: 'evaluating' value: 'evalFile: aPath
	| file |
	file := aPath asFileReference.
	file exists ifFalse: [^ self compileError: ''file not found: '' , aPath].
	^ self evalAll: file contents named: file fullName'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Compiler'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Compiler: ' , failures size printString].
