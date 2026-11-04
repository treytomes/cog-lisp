"============================================================================
 cog-lisp : the shared acceptance-suite harness  (specs/review-phases-1-7.md T-2)
 Filed in by every tests/phase-*.st after the packages it tests. Counts checks,
 prints PASS/FAIL per check and a final RESULT line, and exits with status 0
 when every check passed, 1 otherwise (so tests\run-all.bat can tell).

   h := LispTestHarness new.
   h check: 'label' actual: x expected: y.
   h check: 'label' raises: SomeError do: [...].
   h check: 'label' raises: SomeError containing: 'text' do: [...].
   h finish.                       prints RESULT and exits
   h harnessError: anError         an unexpected error stops the suite (exit 1)

 Suites keep their block style through h checkBlock, h checkErrBlock and
 h checkMsgBlock. Equality is LispCore equal:with: once the core package is
 loaded; before that (Phase 1) a structural equality of the same rules.
 ============================================================================"

| cls cm |
cls := (Object << #LispTestHarness) slots: { #pass. #total. #equality }; package: 'CogLisp-Tests'; install.
cm := [:sel :src | cls compile: src classified: 'harness'].

cm value: #initialize value: 'initialize
	pass := 0.
	total := 0'.
cm value: #say: value: 'say: aString
	Stdio stdout nextPutAll: aString asString; nextPut: Character lf; flush'.
cm value: #writeString: value: 'writeString: v
	^ [(Smalltalk at: #LispPrinter) writeString: v] on: Error do: [:e | v printString]'.
cm value: #equality: value: 'equality: aBlock
	equality := aBlock'.
cm value: #is:equalTo: value: 'is: a equalTo: b
	equality notNil ifTrue: [^ equality value: a value: b].
	"Smalltalk Arrays (used to check several results at once) compare element by element"
	((a isKindOf: Array) and: [b isKindOf: Array]) ifTrue: [
		^ a size = b size and: [(1 to: a size) allSatisfy: [:i | self is: (a at: i) equalTo: (b at: i)]]].
	(Smalltalk includesKey: #LispCore) ifTrue: [^ (Smalltalk at: #LispCore) equal: a with: b].
	^ self structurallyEqual: a to: b'.
cm value: #structurallyEqual:to: value: 'structurallyEqual: a to: b
	"equal?-style equality for suites that run before the core package exists"
	| cons |
	a == b ifTrue: [^ true].
	cons := Smalltalk at: #LispCons.
	((a isKindOf: cons) and: [b isKindOf: cons]) ifTrue: [
		^ (self structurallyEqual: a car to: b car) and: [self structurallyEqual: a cdr to: b cdr]].
	((a isKindOf: String) and: [b isKindOf: String]) ifTrue: [^ a = b].
	(a isNumber and: [b isNumber]) ifTrue: [^ a class = b class and: [a = b]].
	^ a = b'.
cm value: #passed: value: 'passed: label
	total := total + 1.
	pass := pass + 1.
	self say: ''  PASS  '' , label'.
cm value: #failed:because: value: 'failed: label because: aString
	total := total + 1.
	self say: ''  FAIL  '' , label , aString'.
cm value: #check:actual:expected: value: 'check: label actual: actual expected: expected
	(self is: actual equalTo: expected)
		ifTrue: [self passed: label]
		ifFalse: [self failed: label because: ''  got='' , (self writeString: actual) , ''  want='' , (self writeString: expected)]'.
cm value: #check:raises:do: value: 'check: label raises: errClass do: aBlock
	| raised |
	raised := false.
	[aBlock value] on: errClass do: [:e | raised := true. e return: nil].
	raised
		ifTrue: [self passed: label]
		ifFalse: [self failed: label because: '' (no error raised)'']'.
cm value: #check:raises:containing:do: value: 'check: label raises: errClass containing: needle do: aBlock
	| message |
	message := nil.
	[aBlock value] on: errClass do: [:e | message := e messageText ifNil: [''''] . e return: nil].
	message isNil ifTrue: [^ self failed: label because: '' (no error raised)''].
	(message includesSubstring: needle)
		ifTrue: [self passed: label]
		ifFalse: [self failed: label because: ''  message='' , message printString]'.
cm value: #checkBlock value: 'checkBlock
	^ [:label :actual :expected | self check: label actual: actual expected: expected]'.
cm value: #checkErrBlock value: 'checkErrBlock
	^ [:label :errClass :aBlock | self check: label raises: errClass do: aBlock]'.
cm value: #checkMsgBlock value: 'checkMsgBlock
	^ [:label :errClass :needle :aBlock | self check: label raises: errClass containing: needle do: aBlock]'.
cm value: #pass value: 'pass
	^ pass'.
cm value: #total value: 'total
	^ total'.
cm value: #finish value: 'finish
	self say: ''''.
	"which compiler this suite ran on (Phase 8 step 8.5): the one written in LISP is
	 installed at the first compile unless COGLISP_COMPILER=smalltalk"
	(Smalltalk at: #LispCompiler ifAbsent: [nil]) ifNotNil: [:c |
		self say: ''== compiler: '' , ((c hasLispCompiler and: [c implementation = #lisp])
			ifTrue: [''lisp'']
			ifFalse: [''smalltalk'']) , '' ==''].
	self say: ''== RESULT: '' , pass printString , ''/'' , total printString , '' checks passed ==''.
	Smalltalk exit: ((total > 0 and: [pass = total]) ifTrue: [0] ifFalse: [1])'.
cm value: #harnessError: value: 'harnessError: anError
	self say: ''HARNESS ERROR: '' , anError class name , '': '' , anError messageText printString.
	self say: ''== RESULT: '' , pass printString , ''/'' , total printString , '' checks passed (stopped early) ==''.
	Smalltalk exit: 1'.

cls class compile: 'new
	^ self basicNew initialize; yourself' classified: 'instance creation'.
!
