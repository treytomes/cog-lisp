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
	slots: { #counter. #sourceMap. #options. #selfLoop. #inlineTemps. #topForm. #sourceContext. #inBody };
	sharedVariables: { #DefaultOptions };
	package: 'CogLisp-Compiler';
	install.
err  := (Error  << #LispCompileError) package: 'CogLisp-Compiler'; install.

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
	^ self messageNode: (self blockWithArgs: #() statements: { aNode. self unspecifiedNode })
		selector: #value
		arguments: #()'.
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
	(aList isKindOf: LispCons) ifTrue: [^ aList lispElements asArray].
	^ #()'.

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
	(scope includesKey: op) ifTrue: [^ false].
	^ argData size = (selfLoop at: #params) size'.
cm value: comp value: 'calls' value: 'translateSelfTailCall: argData inScope: scope
	"Go round the loop again (Phase 6 section 4.2) if the global still names this
	 procedure; otherwise make an ordinary tail call to whatever it names now."
	| newTemps thenStatements check elseNode |
	selfLoop at: #used put: true.
	newTemps := argData collect: [:d | | nm | nm := self nextName. (selfLoop at: #temps) add: nm. nm].
	thenStatements := OrderedCollection new.
	newTemps with: argData do: [:t :d | thenStatements add: (self assign: t value: (self translate: d inScope: scope))].
	(selfLoop at: #params) with: newTemps do: [:p :t | thenStatements add: (self assign: p value: (self var: t))].
	thenStatements add: (self assign: (selfLoop at: #again) value: (self literalNode: true)).
	thenStatements add: (self literalNode: nil).
	check := self messageNode: (self globalRead: (selfLoop at: #name)) selector: #== arguments: { self var: (selfLoop at: #proc) }.
	elseNode := self tailCallNode: (self globalRead: (selfLoop at: #name))
		args: (argData collect: [:d | self translate: d inScope: scope]).
	^ self messageNode: check selector: #ifTrue:ifFalse: arguments: {
		self blockWithArgs: #() statements: thenStatements asArray.
		self thunk: elseNode }'.
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
	opName = ''quote'' ifTrue: [^ self quoteNode: form cdr car].
	opName = ''if'' ifTrue: [^ self translateIf: form inScope: scope tail: tail].
	opName = ''begin'' ifTrue: [^ self translateBegin: (self listToArray: form cdr) inScope: scope tail: tail].
	opName = ''lambda'' ifTrue: [^ self translateLambda: form inScope: scope].
	opName = ''let'' ifTrue: [^ self translateLet: form inScope: scope tail: tail].
	opName = ''define'' ifTrue: [^ self translateDefine: form inScope: scope].
	opName = ''set!!'' ifTrue: [^ self translateSet: form inScope: scope].
	opName = ''quasiquote'' ifTrue: [^ self qqNode: form cdr car level: 0 inScope: scope].
	opName = ''define-macro'' ifTrue: [^ self translateDefineMacro: form inScope: scope].
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
	expansion := self expand: form with: aMacro.
	text := self recordedSourceOf: form.
	savedContext := sourceContext.
	savedTop := topForm.
	text notNil ifTrue: [sourceContext := text].
	form == topForm ifTrue: [topForm := expansion].
	^ [self translate: expansion inScope: scope tail: tail]
		ensure: [sourceContext := savedContext. topForm := savedTop]'.
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
	| current next |
	current := form.
	[next := self macroexpand1: current. next == current] whileFalse: [current := next].
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
	head := t car.
	((self isTagged: head as: ''unquote-splicing'') and: [n = 0]) ifTrue: [
		^ self messageNode: (self var: ''LispCons'') selector: #qqAppend:to: arguments: {
			self translate: head cdr car inScope: scope.
			self qqNode: t cdr level: n inScope: scope }].
	^ self messageNode: (self var: ''LispCons'') selector: #car:cdr: arguments: {
		self qqNode: head level: n inScope: scope.
		self qqNode: t cdr level: n inScope: scope }'.

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
	| pending defs rest temps statements item datum m savedContext savedInBody beginSym |
	beginSym := LispSymbol named: ''begin''.
	pending := OrderedCollection new.
	dataArray do: [:d | pending add: { d. sourceContext }].
	defs := OrderedCollection new.
	rest := nil.
	[rest isNil and: [pending notEmpty]] whileTrue: [
		item := pending removeFirst.
		datum := item first.
		m := (datum isKindOf: LispCons) ifTrue: [self macroFor: datum car inScope: childScope] ifFalse: [nil].
		m notNil
			ifTrue: [pending addFirst: { self expand: datum with: m. (self recordedSourceOf: datum) ifNil: [item second] }]
			ifFalse: [
				(self isDefineForm: datum)
					ifTrue: [ | target nm |
						"in scope at once, so it shadows a macro of the same name in later forms"
						target := (self listToArray: datum cdr) first.
						nm := self nextName.
						childScope at: ((target isKindOf: LispCons) ifTrue: [target car] ifFalse: [target]) put: nm.
						defs add: { datum. item second. nm }]
					ifFalse: [
						((datum isKindOf: LispCons) and: [datum car == beginSym and: [(childScope includesKey: beginSym) not]])
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
			ifTrue: [self translateLambda: (self makeLambda: target cdr body: parts allButFirst)
				inScope: childScope source: (self sourceOf: d first) defining: nil]
			ifFalse: [
				valueData := parts at: 2.
				(self isLambdaForm: valueData)
					ifTrue: [self translateLambda: valueData inScope: childScope source: (self sourceOf: valueData) defining: nil]
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
	(datum isKindOf: LispSymbol) ifTrue: [^ self symbolNode: datum].
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
	| fixed cur |
	(spec isKindOf: LispSymbol) ifTrue: [^ { #(). spec }].
	fixed := OrderedCollection new.
	cur := spec.
	[cur isKindOf: LispCons] whileTrue: [fixed add: cur car. cur := cur cdr].
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
	"nameSym is the global this lambda is being defined as, or nil. A defined,
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
		loop at: #name put: nameSym; at: #params put: (bound at: 4);
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
		^ self translateNamedLet: parts inScope: scope tail: tail].
	bindings := self listToArray: parts first.
	bodyData := parts allButFirst.
	params := bindings collect: [:b | (self listToArray: b) first].
	valueData := bindings collect: [:b | (self listToArray: b) second].
	(self uses: #directLet) ifFalse: [
		"as in Phase 3: an immediately applied lambda"
		^ self translate: (LispCons
				car: (self makeLambda: (LispCons fromArray: params asArray) body: bodyData)
				cdr: (LispCons fromArray: valueData asArray))
			inScope: scope tail: tail].
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
cm value: comp value: 'translating' value: 'translateNamedLet: parts inScope: scope tail: tail
	"(let name ((v e)...) body...) is ((let () (define (name v...) body...) name) e...):
	 name is visible in the body only, and the initial values are evaluated outside it."
	| name bindings vars inits defineForm |
	name := parts first.
	bindings := self listToArray: (parts at: 2).
	vars := bindings collect: [:b | (self listToArray: b) first].
	inits := bindings collect: [:b | (self listToArray: b) second].
	defineForm := LispCons car: (LispSymbol named: ''define'')
		cdr: (LispCons car: (LispCons car: name cdr: (LispCons fromArray: vars asArray))
			cdr: (LispCons fromArray: (parts allButFirst: 2))).
	^ self translate: (LispCons
			car: (LispCons fromArray: { LispSymbol named: ''let''. LispEmptyList default. defineForm. name })
			cdr: (LispCons fromArray: inits asArray))
		inScope: scope tail: tail'.
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
			valueNode := self translateLambda: (self makeLambda: target cdr body: parts allButFirst)
				inScope: scope
				source: (self sourceOf: form)
				defining: nameSym]
		ifFalse: [
			nameSym := target.
			valueData := parts at: 2.
			valueNode := (self isLambdaForm: valueData)
				ifTrue: [self translateLambda: valueData inScope: scope source: (self sourceOf: valueData) defining: nameSym]
				ifFalse: [self translate: valueData inScope: scope]].
	^ self andUnspecified: (self globalDefine: nameSym value: valueNode)'.
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
	"A top-level form is not in tail position: its calls are ordinary calls."
	| exprNode method |
	counter := 0.
	selfLoop := nil.
	topForm := datum.
	sourceContext := nil.
	inBody := false.
	inlineTemps := 0.
	exprNode := self translate: datum inScope: IdentityDictionary new tail: false.
	method := OCMethodNode selector: #doIt arguments: #()
		body: (OCSequenceNode statements: { OCReturnNode value: exprNode }).
	method doSemanticAnalysis.
	^ method generateMethod'.
cm value: comp value: 'evaluating' value: 'eval: datum
	^ (self compile: datum) valueWithReceiver: nil arguments: #()'.
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
cm value: comp value: 'evaluating' value: 'evalFile: aPath
	| file |
	file := aPath asFileReference.
	file exists ifFalse: [^ self compileError: ''file not found: '' , aPath].
	^ self evalAll: file contents'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Compiler'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Compiler: ' , failures size printString].
