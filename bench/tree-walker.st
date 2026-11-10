"============================================================================
 cog-lisp : tree-walking interpreter  (specs/05-phase-6-optimization.md section 6)
 A BASELINE for the benchmarks only: it evaluates the same LISP data by walking
 it, with an environment of frames, instead of compiling it. It is loaded by
 bench/bench.st and is not part of the cog-lisp image.

 It covers the Phase 3 core forms (quote, if, begin, lambda, let, define, set-bang) and
 application. Its closures are LispProcedure subclasses, so primitives such as
 map can call them. It has its own global environment, with the primitives
 installed, so its definitions never collide with compiled ones. It does not
 do tail calls: like any simple interpreter, it recurses on the host stack.
 The set-bang name is written with a doubled bang for the chunk reader.
 ============================================================================"
| cm walker frame closure |
cm := [:cls :cat :src | cls compile: src classified: cat].
walker  := (Object << #LispTreeWalker) slots: { #globals }; package: 'CogLisp-Bench'; install.
frame   := (Object << #LispTreeWalkerFrame) slots: { #vars. #parent }; package: 'CogLisp-Bench'; install.
closure := (LispProcedure << #LispTreeWalkerClosure) slots: { #params. #restParam. #body. #env. #walker }; package: 'CogLisp-Bench'; install.

"=== frames ================================================================"
cm value: frame value: 'private' value: 'setParent: aFrame
	vars := IdentityDictionary new.
	parent := aFrame'.
cm value: frame value: 'accessing' value: 'at: aSymbol put: aValue
	^ vars at: aSymbol put: aValue'.
cm value: frame value: 'accessing' value: 'frameFor: aSymbol
	"The innermost frame binding aSymbol, or nil."
	| f |
	f := self.
	[f notNil] whileTrue: [
		(f includes: aSymbol) ifTrue: [^ f].
		f := f parent].
	^ nil'.
cm value: frame value: 'accessing' value: 'includes: aSymbol
	^ vars includesKey: aSymbol'.
cm value: frame value: 'accessing' value: 'at: aSymbol
	^ vars at: aSymbol'.
cm value: frame value: 'accessing' value: 'parent
	^ parent'.
cm value: frame class value: 'instance creation' value: 'parent: aFrame
	^ self new setParent: aFrame'.

"=== closures =============================================================="
cm value: closure value: 'private' value: 'setParams: fixed rest: rest body: forms env: aFrame walker: aWalker
	params := fixed.
	restParam := rest.
	body := forms.
	env := aFrame.
	walker := aWalker.
	required := fixed size.
	hasRest := rest notNil'.
cm value: closure value: 'applying' value: 'applyTo: anArray
	| f result |
	hasRest
		ifTrue: [anArray size >= required ifFalse: [^ self signalArity: anArray size]]
		ifFalse: [anArray size = required ifFalse: [^ self signalArity: anArray size]].
	f := LispTreeWalkerFrame parent: env.
	params doWithIndex: [:p :i | f at: p put: (anArray at: i)].
	hasRest ifTrue: [f at: restParam put: (LispCons fromArray: (anArray allButFirst: required))].
	result := LispUnspecified default.
	body do: [:form | result := walker eval: form in: f].
	^ result'.

"=== the interpreter ======================================================="
cm value: walker value: 'initialization' value: 'initialize
	globals := LispEnvironment new.
	LispPrimitives installInto: globals'.
cm value: walker value: 'evaluating' value: 'evalAll: aString
	| result |
	result := LispUnspecified default.
	(LispReader readAll: aString) do: [:form | result := self eval: form in: nil].
	^ result'.
cm value: walker value: 'evaluating' value: 'eval: x in: env
	| f op |
	(x isKindOf: LispSymbol) ifTrue: [
		f := env ifNotNil: [env frameFor: x].
		f notNil ifTrue: [^ f at: x].
		^ globals lookup: x].
	(x isKindOf: LispCons) ifFalse: [^ x].
	op := x car.
	(op isKindOf: LispSymbol) ifTrue: [
		op name = ''quote'' ifTrue: [^ x cdr car].
		op name = ''if'' ifTrue: [^ self evalIf: x in: env].
		op name = ''begin'' ifTrue: [^ self evalBody: x cdr lispElements in: env].
		op name = ''lambda'' ifTrue: [^ self makeClosure: x cdr car body: x cdr cdr lispElements in: env].
		op name = ''let'' ifTrue: [^ self evalLet: x in: env].
		op name = ''define'' ifTrue: [^ self evalDefine: x in: env].
		op name = ''set!!'' ifTrue: [^ self evalSet: x in: env]].
	^ LispProcedure apply: (self eval: op in: env)
		to: (x cdr lispElements collect: [:a | self eval: a in: env]) asArray'.
cm value: walker value: 'evaluating' value: 'evalIf: x in: env
	| parts |
	parts := x cdr lispElements.
	(LispCore isTruthy: (self eval: (parts at: 1) in: env)) ifTrue: [^ self eval: (parts at: 2) in: env].
	parts size >= 3 ifTrue: [^ self eval: (parts at: 3) in: env].
	^ LispUnspecified default'.
cm value: walker value: 'evaluating' value: 'evalBody: forms in: env
	| result |
	result := LispUnspecified default.
	forms do: [:form | result := self eval: form in: env].
	^ result'.
cm value: walker value: 'evaluating' value: 'makeClosure: spec body: forms in: env
	| fixed cur |
	fixed := OrderedCollection new.
	cur := spec.
	[cur isKindOf: LispCons] whileTrue: [fixed add: cur car. cur := cur cdr].
	^ LispTreeWalkerClosure new
		setParams: fixed asArray
		rest: ((cur isKindOf: LispSymbol) ifTrue: [cur] ifFalse: [nil])
		body: forms
		env: env
		walker: self'.
cm value: walker value: 'evaluating' value: 'evalLet: x in: env
	| f |
	f := LispTreeWalkerFrame parent: env.
	x cdr car lispElements do: [:binding |
		f at: binding car put: (self eval: binding cdr car in: env)].
	^ self evalBody: x cdr cdr lispElements in: f'.
cm value: walker value: 'evaluating' value: 'evalDefine: x in: env
	| target |
	target := x cdr car.
	(target isKindOf: LispCons)
		ifTrue: [globals define: target car value: (self makeClosure: target cdr body: x cdr cdr lispElements in: env)]
		ifFalse: [globals define: target value: (self eval: x cdr cdr car in: env)].
	^ LispUnspecified default'.
cm value: walker value: 'evaluating' value: 'evalSet: x in: env
	| sym f |
	sym := x cdr car.
	f := env ifNotNil: [env frameFor: sym].
	f notNil
		ifTrue: [f at: sym put: (self eval: x cdr cdr car in: env)]
		ifFalse: [globals set: sym value: (self eval: x cdr cdr car in: env)].
	^ LispUnspecified default'.
!
