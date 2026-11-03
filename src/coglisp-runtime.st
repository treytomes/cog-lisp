"============================================================================
 cog-lisp : Phase 4 implementation  (package CogLisp-Runtime)
 Procedures + primitive library per specs/phase-4-runtime-primitives.md.

 LOADER script. Must be filed in AFTER coglisp-reader.st, coglisp-core.st, and
 coglisp-compiler.st. Set-car and set-cdr contain a bang, written doubled so the
 chunk reader keeps it.

 Classes: LispError, LispArityError, LispProcedure, LispTailCall, LispPrimitives,
 LispTextOutput.
 ============================================================================"
| failures cm lerr aerr proc tcall prims tout |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

lerr  := LispError.  "defined by the reader package"
aerr  := (lerr   << #LispArityError) slots: { #proc. #given }; package: 'CogLisp-Runtime'; install.
proc  := (Object << #LispProcedure) slots: { #block. #required. #hasRest. #name. #source. #entries. #inline }; package: 'CogLisp-Runtime'; install.
tcall := (Object << #LispTailCall) slots: { #fn. #args }; package: 'CogLisp-Runtime'; install.
prims := (Object << #LispPrimitives) sharedVariables: { #Output. #GensymCounter }; package: 'CogLisp-Runtime'; install.
tout  := (Object << #LispTextOutput) slots: { #kind. #handle. #stream. #buffer. #midLine }; sharedVariables: { #Session. #Stdout. #Stderr }; package: 'CogLisp-Runtime'; install.

"=== LispTextOutput =========================================================
 Text output to stdout or stderr that encodes properly. Pharo's Stdio streams
 write a string's internal representation (Latin-1 bytes, or four bytes per
 character for wide strings), so non-ASCII text came out garbled. Text is
 buffered until flush, then written:
   to a console  with WriteConsoleW (UTF-16): Windows draws the characters, so
                 the console code page does not matter and is never changed;
   otherwise     as UTF-8 bytes on the Stdio stream (pipes, files, non-Windows)."
cm value: tout class value: 'win32' value: 'getStdHandle: n
	^ self ffiCall: #(void* GetStdHandle(long n)) module: ''kernel32.dll'''.
cm value: tout class value: 'win32' value: 'getFileType: h
	^ self ffiCall: #(uint32 GetFileType(void* h)) module: ''kernel32.dll'''.
cm value: tout class value: 'win32' value: 'writeConsole: h buffer: b count: n written: w reserved: r
	^ self ffiCall: #(int WriteConsoleW(void* h, void* b, uint32 n, void* w, void* r)) module: ''kernel32.dll'''.
cm value: tout class value: 'accessing' value: 'stdout
	"The shared stdout writer for this session (handles change when the image restarts)."
	self ensureSession.
	^ Stdout ifNil: [Stdout := self onStd: -11 stream: Stdio stdout]'.
cm value: tout class value: 'accessing' value: 'stderr
	self ensureSession.
	^ Stderr ifNil: [Stderr := self onStd: -12 stream: Stdio stderr]'.
cm value: tout class value: 'private' value: 'ensureSession
	Session == Smalltalk session ifFalse: [
		Session := Smalltalk session.
		Stdout := nil.
		Stderr := nil]'.
cm value: tout class value: 'instance creation' value: 'onStd: stdHandleNumber stream: aStdioStream
	| h |
	OSPlatform current isWindows ifTrue: [
		[h := self getStdHandle: stdHandleNumber.
		 (self getFileType: h) = 2 ifTrue: [^ self onConsoleHandle: h]]
			on: Error do: [:e | ]].
	^ self basicNew setKind: #stream handle: nil stream: aStdioStream'.
cm value: tout class value: 'instance creation' value: 'onConsoleHandle: aHandle
	"A writer for a specific console output handle (used by tests)."
	^ self basicNew setKind: #console handle: aHandle stream: nil'.
cm value: tout value: 'private' value: 'setKind: aSymbol handle: aHandle stream: aStream
	kind := aSymbol.
	handle := aHandle.
	stream := aStream.
	buffer := WriteStream on: (String new: 256)'.
cm value: tout value: 'accessing' value: 'kind
	^ kind'.
cm value: tout value: 'writing' value: 'nextPutAll: aString
	aString isEmpty ifFalse: [midLine := aString last ~= Character lf].
	buffer nextPutAll: aString'.
cm value: tout value: 'writing' value: 'nextPut: aCharacter
	midLine := aCharacter ~= Character lf.
	buffer nextPut: aCharacter'.
cm value: tout value: 'accessing' value: 'isMidLine
	"True when the last character written was not a line feed: the next text
	 would continue that line."
	^ midLine == true'.
cm value: tout value: 'writing' value: 'flush
	| text units |
	text := buffer contents.
	buffer := WriteStream on: (String new: 256).
	text isEmpty ifTrue: [^ self].
	kind = #console ifTrue: [
		units := self utf16: text.
		self class writeConsole: handle buffer: units count: units size // 2 written: (ByteArray new: 4) reserved: nil.
		^ self].
	stream nextPutAll: text utf8Encoded; flush'.
cm value: tout value: 'private' value: 'utf16: aString
	"Little-endian UTF-16 code units for aString, with surrogate pairs above U+FFFF."
	| out code v |
	out := WriteStream on: (ByteArray new: aString size * 2).
	aString do: [:ch |
		code := ch asInteger.
		code < 16r10000
			ifTrue: [out nextPut: (code bitAnd: 255); nextPut: (code bitShift: -8)]
			ifFalse: [
				v := code - 16r10000.
				out nextPut: (((v bitShift: -10) + 16rD800) bitAnd: 255); nextPut: (((v bitShift: -10) + 16rD800) bitShift: -8).
				out nextPut: (((v bitAnd: 16r3FF) + 16rDC00) bitAnd: 255); nextPut: (((v bitAnd: 16r3FF) + 16rDC00) bitShift: -8)]].
	^ out contents'.

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
cm value: proc value: 'accessing' value: 'named: aString
	"Name this procedure (once: an alias does not rename it) and answer it. The
	 compiler sends this to the value of (define (f ...) ...) (review C-17)."
	name isNil ifTrue: [name := aString].
	^ self'.
cm value: proc value: 'testing' value: 'isVariadic
	^ hasRest'.
cm value: proc value: 'accessing' value: 'source
	"The exact LISP text this procedure was compiled from; nil for primitives (Phase 5 section 5.2)."
	^ source'.
cm value: proc value: 'accessing' value: 'source: aString
	source := aString'.
cm value: proc value: 'accessing' value: 'block
	^ block'.
cm value: proc value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<procedure''.
	name ifNotNil: [aStream nextPut: Character space; nextPutAll: name].
	aStream nextPut: $>'.
cm value: proc value: 'applying' value: 'signalArity: givenCount
	"sq: expected 1 argument, got 0 (review R-7)"
	| wanted |
	wanted := (hasRest ifTrue: [''at least ''] ifFalse: ['''']) , required printString ,
		(required = 1 ifTrue: ['' argument''] ifFalse: ['' arguments'']).
	^ (LispArityError new) proc: self; given: givenCount;
		signal: (name ifNil: [''procedure'']) , '': expected '' , wanted , '', got '' , givenCount printString'.
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
cm value: proc class value: 'instance creation' value: 'fixed: aBlock arity: n source: aString
	^ (self fixed: aBlock arity: n) source: aString; yourself'.
cm value: proc class value: 'instance creation' value: 'variadic: aBlock required: n source: aString
	^ (self variadic: aBlock required: n) source: aString; yourself'.
cm value: proc value: 'testing' value: 'isFixedArity: n
	^ hasRest not and: [required = n]'.
cm value: proc value: 'testing' value: 'isPrimitive
	"Primitives are the procedures with no LISP source (Phase 5 section 5.2). They
	 never grow the stack without bound, so a tail call to one needs no bounce."
	^ source isNil'.
cm value: proc value: 'fast calls' value: 'entry: n is: aBlock
	"Give a variadic primitive a direct entry for exactly n arguments (0-4), used by
	 the fast-call path instead of building an argument array and a rest list. The
	 block must be a trusted primitive: it returns a plain value, never a bounce."
	entries isNil ifTrue: [entries := Array new: 5].
	entries at: n + 1 put: aBlock'.
cm value: proc value: 'fast calls' value: 'entryFor: n
	entries isNil ifTrue: [^ nil].
	^ entries at: n + 1'.
cm value: proc value: 'inlining' value: 'inline: aSpec
	"Declare how the compiler may inline a call to this primitive (Phase 6 section 11):
	 { argCount. #send. selector }    -> x sel  or  x sel y
	 { argCount. #identity. object }  -> x == object
	 It must do exactly what the primitive does for that many arguments."
	inline := aSpec'.
cm value: proc value: 'inlining' value: 'inlineSpec
	^ inline'.

"--- calling, with proper tail calls (Phase 6 section 4.3) -------------------
 A call in tail position returns a LispTailCall (a bounce) instead of calling.
 Every non-tail call site goes through apply:to: or call:with:..., which drive the
 result: while it is a bounce, run it. So a bounce never reaches LISP code, and a
 chain of tail calls uses one stack frame.
 applyTo: is the raw invocation and does not drive."
cm value: proc class value: 'applying' value: 'invoke: fn with: anArray
	(fn isKindOf: LispProcedure) ifFalse: [^ (LispError new) signal: ''object is not applicable: '' , fn printString].
	^ fn applyTo: anArray'.
cm value: proc class value: 'applying' value: 'drive: aResult
	| r |
	r := aResult.
	[r class == LispTailCall] whileTrue: [r := self invoke: r fn with: r args].
	^ r'.
cm value: proc class value: 'applying' value: 'apply: fn to: anArray
	^ self drive: (self invoke: fn with: anArray)'.
cm value: proc class value: 'applying' value: 'tailCall: fn to: anArray
	^ LispTailCall fn: fn args: anArray'.
cm value: proc class value: 'tail calls' value: 'tailCall: fn
	"A primitive is called directly; its result, which may itself be a bounce
	 (apply), goes back to our caller to drive. Anything else becomes a bounce."
	| e |
	(fn class == LispProcedure and: [fn isPrimitive]) ifTrue: [
		(fn isFixedArity: 0) ifTrue: [^ fn block value].
		(e := fn entryFor: 0) notNil ifTrue: [^ e value]].
	^ LispTailCall fn: fn args: #()'.
cm value: proc class value: 'tail calls' value: 'tailCall: fn with: a
	"A primitive is called directly; its result, which may itself be a bounce
	 (apply), goes back to our caller to drive. Anything else becomes a bounce."
	| e |
	(fn class == LispProcedure and: [fn isPrimitive]) ifTrue: [
		(fn isFixedArity: 1) ifTrue: [^ fn block value: a].
		(e := fn entryFor: 1) notNil ifTrue: [^ e value: a]].
	^ LispTailCall fn: fn args: { a }'.
cm value: proc class value: 'tail calls' value: 'tailCall: fn with: a with: b
	"A primitive is called directly; its result, which may itself be a bounce
	 (apply), goes back to our caller to drive. Anything else becomes a bounce."
	| e |
	(fn class == LispProcedure and: [fn isPrimitive]) ifTrue: [
		(fn isFixedArity: 2) ifTrue: [^ fn block value: a value: b].
		(e := fn entryFor: 2) notNil ifTrue: [^ e value: a value: b]].
	^ LispTailCall fn: fn args: { a. b }'.
cm value: proc class value: 'tail calls' value: 'tailCall: fn with: a with: b with: c
	"A primitive is called directly; its result, which may itself be a bounce
	 (apply), goes back to our caller to drive. Anything else becomes a bounce."
	| e |
	(fn class == LispProcedure and: [fn isPrimitive]) ifTrue: [
		(fn isFixedArity: 3) ifTrue: [^ fn block value: a value: b value: c].
		(e := fn entryFor: 3) notNil ifTrue: [^ e value: a value: b value: c]].
	^ LispTailCall fn: fn args: { a. b. c }'.
cm value: proc class value: 'tail calls' value: 'tailCall: fn with: a with: b with: c with: d
	"A primitive is called directly; its result, which may itself be a bounce
	 (apply), goes back to our caller to drive. Anything else becomes a bounce."
	| e |
	(fn class == LispProcedure and: [fn isPrimitive]) ifTrue: [
		(fn isFixedArity: 4) ifTrue: [^ fn block value: a value: b value: c value: d].
		(e := fn entryFor: 4) notNil ifTrue: [^ e value: a value: b value: c value: d]].
	^ LispTailCall fn: fn args: { a. b. c. d }'.
"Fast calls (Phase 6 section 5.1): a fixed-arity procedure of exactly this arity is
 called through its block directly, with no argument array."
cm value: proc class value: 'fast calls' value: 'call: fn
	| r e |
	fn class == LispProcedure ifFalse: [^ self apply: fn to: #()].
	(fn isFixedArity: 0) ifTrue: [
		r := fn block value.
		r class == LispTailCall ifTrue: [^ self drive: r].
		^ r].
	(e := fn entryFor: 0) notNil ifTrue: [^ e value].
	^ self apply: fn to: #()'.
cm value: proc class value: 'fast calls' value: 'call: fn with: a
	| r e |
	fn class == LispProcedure ifFalse: [^ self apply: fn to: { a }].
	(fn isFixedArity: 1) ifTrue: [
		r := fn block value: a.
		r class == LispTailCall ifTrue: [^ self drive: r].
		^ r].
	(e := fn entryFor: 1) notNil ifTrue: [^ e value: a].
	^ self apply: fn to: { a }'.
cm value: proc class value: 'fast calls' value: 'call: fn with: a with: b
	| r e |
	fn class == LispProcedure ifFalse: [^ self apply: fn to: { a. b }].
	(fn isFixedArity: 2) ifTrue: [
		r := fn block value: a value: b.
		r class == LispTailCall ifTrue: [^ self drive: r].
		^ r].
	(e := fn entryFor: 2) notNil ifTrue: [^ e value: a value: b].
	^ self apply: fn to: { a. b }'.
cm value: proc class value: 'fast calls' value: 'call: fn with: a with: b with: c
	| r e |
	fn class == LispProcedure ifFalse: [^ self apply: fn to: { a. b. c }].
	(fn isFixedArity: 3) ifTrue: [
		r := fn block value: a value: b value: c.
		r class == LispTailCall ifTrue: [^ self drive: r].
		^ r].
	(e := fn entryFor: 3) notNil ifTrue: [^ e value: a value: b value: c].
	^ self apply: fn to: { a. b. c }'.
cm value: proc class value: 'fast calls' value: 'call: fn with: a with: b with: c with: d
	| r e |
	fn class == LispProcedure ifFalse: [^ self apply: fn to: { a. b. c. d }].
	(fn isFixedArity: 4) ifTrue: [
		r := fn block value: a value: b value: c value: d.
		r class == LispTailCall ifTrue: [^ self drive: r].
		^ r].
	(e := fn entryFor: 4) notNil ifTrue: [^ e value: a value: b value: c value: d].
	^ self apply: fn to: { a. b. c. d }'.

"=== LispTailCall ==========================================================="
cm value: tcall value: 'private' value: 'setFn: aProcedure args: anArray
	fn := aProcedure.
	args := anArray'.
cm value: tcall value: 'accessing' value: 'fn
	^ fn'.
cm value: tcall value: 'accessing' value: 'args
	^ args'.
cm value: tcall class value: 'instance creation' value: 'fn: aProcedure args: anArray
	^ self basicNew setFn: aProcedure args: anArray'.

"=== LispPrimitives : install the library (class-side) ====================="
cm value: prims class value: 'installing' value: 'installInto: anEnv
	self installListsInto: anEnv.
	self installNumbersInto: anEnv.
	self installComparisonsInto: anEnv.
	self installPredicatesInto: anEnv.
	self installIOInto: anEnv.
	self installControlInto: anEnv.
	self installSystemInto: anEnv.
	self installMacroSupportInto: anEnv.
	self installListSearchInto: anEnv.
	"every primitive knows its name, for printing and error messages (review R-7)"
	anEnv cellsDo: [:c | | v |
		v := c valueIfUnbound: [nil].
		(v isKindOf: LispProcedure) ifTrue: [v named: c symbol name]].
	self installInlineFormsInto: anEnv.
	^ anEnv'.
cm value: prims class value: 'installing' value: 'installMacroSupportInto: anEnv
	"Phase 7 section 5.2. gensym makes uninterned symbols: not in the intern table,
	 so no symbol the reader produces is ever identical to one."
	anEnv define: (LispSymbol named: ''gensym'') value: (LispProcedure variadic: [:prefix |
		GensymCounter := (GensymCounter ifNil: [0]) + 1.
		"the prefix may be a string or a symbol (review R-19)"
		LispSymbol new setName: (prefix lispElements ifEmpty: [''g''] ifNotEmpty: [:p |
			(p first isKindOf: LispSymbol) ifTrue: [p first name] ifFalse: [p first asString]]) , GensymCounter printString]
		required: 0).
	anEnv define: (LispSymbol named: ''macroexpand-1'') value: (LispProcedure fixed: [:form | LispCompiler new macroexpand1: form] arity: 1).
	anEnv define: (LispSymbol named: ''macroexpand'') value: (LispProcedure fixed: [:form | LispCompiler new macroexpand: form] arity: 1).
	anEnv define: (LispSymbol named: ''eval'') value: (LispProcedure fixed: [:form | LispCompiler new eval: form] arity: 1)'.
cm value: prims class value: 'installing' value: 'installListSearchInto: anEnv
	"memq memv member: the first tail of lst whose car matches, else #f.
	 assq assv assoc: the first pair in alist whose car matches, else #f."
	| mem ass |
	mem := [:test | [:x :lst | | cur |
		cur := lst.
		[(cur isKindOf: LispCons) and: [(test value: x value: cur car) not]] whileTrue: [cur := cur cdr].
		(cur isKindOf: LispCons) ifTrue: [cur] ifFalse: [false]]].
	ass := [:test :nm | [:x :alist | | found |
		found := (LispCons elementsOf: alist for: nm) detect: [:pair | (pair isKindOf: LispCons) and: [test value: x value: pair car]] ifNone: [false].
		found]].
	anEnv define: (LispSymbol named: ''memq'') value: (LispProcedure fixed: (mem value: [:a :b | LispCore eq: a with: b]) arity: 2).
	anEnv define: (LispSymbol named: ''memv'') value: (LispProcedure fixed: (mem value: [:a :b | LispCore eqv: a with: b]) arity: 2).
	anEnv define: (LispSymbol named: ''member'') value: (LispProcedure fixed: (mem value: [:a :b | LispCore equal: a with: b]) arity: 2).
	anEnv define: (LispSymbol named: ''assq'') value: (LispProcedure fixed: (ass value: [:a :b | LispCore eq: a with: b] value: ''assq'') arity: 2).
	anEnv define: (LispSymbol named: ''assv'') value: (LispProcedure fixed: (ass value: [:a :b | LispCore eqv: a with: b] value: ''assv'') arity: 2).
	anEnv define: (LispSymbol named: ''assoc'') value: (LispProcedure fixed: (ass value: [:a :b | LispCore equal: a with: b] value: ''assoc'') arity: 2)'.
cm value: prims class value: 'installing' value: 'installInlineFormsInto: anEnv
	"Inline forms for guarded inlining (Phase 6 section 11.2). Each matches what
	 the primitive does for that many arguments."
	| e |
	e := [:name | anEnv lookup: (LispSymbol named: name)].
	#(''+'' ''-'' ''*'' ''='' ''<'' ''>'' ''<='' ''>='') do: [:op |
		(e value: op) inline: { 2. #send. op asSymbol }].
	(e value: ''eq?'') inline: #(2 #send #==).
	(e value: ''car'') inline: #(1 #send #car).
	(e value: ''cdr'') inline: #(1 #send #cdr).
	(e value: ''not'') inline: { 1. #identity. false }.
	(e value: ''null?'') inline: { 1. #identity. LispEmptyList default }'.
cm value: prims class value: 'installing' value: 'installDefault
	^ self installInto: LispEnvironment default'.
cm value: prims class value: 'output' value: 'output
	"Where display/write/newline/disassemble write. Defaults to stdout; the REPL and tests redirect it."
	^ Output ifNil: [LispTextOutput stdout]'.
cm value: prims class value: 'output' value: 'withOutput: aStream do: aBlock
	| previous |
	previous := Output.
	Output := aStream.
	^ aBlock ensure: [Output := previous]'.
cm value: prims class value: 'system' value: 'saveImage
	"Snapshot the running image in place (Phase 5). On the resume path, when the saved
	 image next starts, the process that saved must not keep running: terminate it."
	(Smalltalk snapshot: true andQuit: false) isImageStarting
		ifTrue: [Processor activeProcess terminate].
	^ LispUnspecified default'.
cm value: prims class value: 'installing' value: 'installListsInto: anEnv
	anEnv define: (LispSymbol named: ''cons'') value: (LispProcedure fixed: [:a :b | LispCons car: a cdr: b] arity: 2).
	anEnv define: (LispSymbol named: ''car'') value: (LispProcedure fixed: [:p | p car] arity: 1).
	anEnv define: (LispSymbol named: ''cdr'') value: (LispProcedure fixed: [:p | p cdr] arity: 1).
	anEnv define: (LispSymbol named: ''pair?'') value: (LispProcedure fixed: [:x | LispCore isPair: x] arity: 1).
	anEnv define: (LispSymbol named: ''null?'') value: (LispProcedure fixed: [:x | LispCore isNull: x] arity: 1).
	anEnv define: (LispSymbol named: ''list?'') value: (LispProcedure fixed: [:x | LispCore isList: x] arity: 1).
	anEnv define: (LispSymbol named: ''list'') value: (LispProcedure variadic: [:args | args] required: 0).
	anEnv define: (LispSymbol named: ''length'') value: (LispProcedure fixed: [:lst | (LispCons elementsOf: lst for: ''length'') size] arity: 1).
	anEnv define: (LispSymbol named: ''reverse'') value: (LispProcedure fixed: [:lst | LispCons fromArray: (LispCons elementsOf: lst for: ''reverse'') asArray reverse] arity: 1).
	"R7RS append: copies all but the last argument; the last becomes the tail as it is, so it may be improper or not a list at all (review R-9)"
	anEnv define: (LispSymbol named: ''append'') value: (LispProcedure variadic: [:lists | | args result |
		args := lists lispElements.
		args isEmpty
			ifTrue: [LispEmptyList default]
			ifFalse: [
				result := args last.
				(args allButLast) reverseDo: [:l | (LispCons elementsOf: l for: ''append'') reverseDo: [:e | result := LispCons car: e cdr: result]].
				result]] required: 0).
	anEnv define: (LispSymbol named: ''set-car!!'') value: (LispProcedure fixed: [:p :v | p car: v. LispUnspecified default] arity: 2).
	anEnv define: (LispSymbol named: ''set-cdr!!'') value: (LispProcedure fixed: [:p :v | p cdr: v. LispUnspecified default] arity: 2).
	anEnv define: (LispSymbol named: ''map'') value: (LispProcedure fixed: [:prc :lst | LispCons fromArray: ((LispCons elementsOf: lst for: ''map'') collect: [:e | LispProcedure apply: prc to: { e }]) asArray] arity: 2).
	anEnv define: (LispSymbol named: ''for-each'') value: (LispProcedure fixed: [:prc :lst | (LispCons elementsOf: lst for: ''for-each'') do: [:e | LispProcedure apply: prc to: { e }]. LispUnspecified default] arity: 2)'.
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
	anEnv define: (LispSymbol named: ''negative?'') value: (LispProcedure fixed: [:a | a < 0] arity: 1).
	self installNumberEntriesInto: anEnv'.
cm value: prims class value: 'installing' value: 'installNumberEntriesInto: anEnv
	"Phase 6 section 5.1: direct entries for the common fixed-arity uses of the
	 variadic arithmetic primitives, so (+ a b) costs one block call."
	| e |
	e := [:name | anEnv lookup: (LispSymbol named: name)].
	"0 to 4 arguments, as Phase 6 section 10 says: with four, (+ acc g1 g2 g3) used to take
	 the variadic path, 14 times slower (review O-1)"
	(e value: ''+'') entry: 0 is: [0]; entry: 1 is: [:a | a]; entry: 2 is: [:a :b | a + b]; entry: 3 is: [:a :b :c | a + b + c]; entry: 4 is: [:a :b :c :d | a + b + c + d].
	(e value: ''*'') entry: 0 is: [1]; entry: 1 is: [:a | a]; entry: 2 is: [:a :b | a * b]; entry: 3 is: [:a :b :c | a * b * c]; entry: 4 is: [:a :b :c :d | a * b * c * d].
	(e value: ''-'') entry: 1 is: [:a | a negated]; entry: 2 is: [:a :b | a - b]; entry: 3 is: [:a :b :c | a - b - c]; entry: 4 is: [:a :b :c :d | a - b - c - d].
	(e value: ''/'') entry: 1 is: [:a | 1 / a]; entry: 2 is: [:a :b | a / b].
	(e value: ''min'') entry: 2 is: [:a :b | a min: b].
	(e value: ''max'') entry: 2 is: [:a :b | a max: b]'.
cm value: prims class value: 'installing' value: 'installComparisonsInto: anEnv
	| e |
	anEnv define: (LispSymbol named: ''='') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev = x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''<'') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev < x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''>'') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev > x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''<='') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev <= x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	anEnv define: (LispSymbol named: ''>='') value: (LispProcedure variadic: [:first :rest | | prev ok | prev := first. ok := true. rest lispElements do: [:x | (prev >= x) ifFalse: [ok := false]. prev := x]. ok] required: 1).
	"direct two-argument entries (Phase 6 section 5.1)"
	e := [:name | anEnv lookup: (LispSymbol named: name)].
	(e value: ''='') entry: 2 is: [:a :b | a = b].
	"chained three- and four-argument comparisons (review O-1)"
	#(#= #< #> #<= #>=) do: [:op |
		(e value: op asString)
			entry: 3 is: [:a :b :c | (a perform: op with: b) and: [b perform: op with: c]];
			entry: 4 is: [:a :b :c :d | ((a perform: op with: b) and: [b perform: op with: c]) and: [c perform: op with: d]]].
	(e value: ''<'') entry: 2 is: [:a :b | a < b].
	(e value: ''>'') entry: 2 is: [:a :b | a > b].
	(e value: ''<='') entry: 2 is: [:a :b | a <= b].
	(e value: ''>='') entry: 2 is: [:a :b | a >= b]'.
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
	anEnv define: (LispSymbol named: ''display'') value: (LispProcedure fixed: [:x | self output nextPutAll: (LispPrinter displayString: x); flush. LispUnspecified default] arity: 1).
	anEnv define: (LispSymbol named: ''write'') value: (LispProcedure fixed: [:x | self output nextPutAll: (LispPrinter writeString: x); flush. LispUnspecified default] arity: 1).
	anEnv define: (LispSymbol named: ''newline'') value: (LispProcedure fixed: [self output nextPut: Character lf; flush. LispUnspecified default] arity: 0)'.
cm value: prims class value: 'installing' value: 'installSystemInto: anEnv
	anEnv define: (LispSymbol named: ''load'') value: (LispProcedure fixed: [:path | LispCompiler new evalFile: path. LispUnspecified default] arity: 1).
	"(exit) and (exit #t) succeed, (exit #f) fails, (exit n) for n in 0..255 (R7RS; review R-10)"
	anEnv define: (LispSymbol named: ''exit'') value: (LispProcedure variadic: [:codes | | c |
		c := codes lispElements ifEmpty: [0] ifNotEmpty: [:cs | cs first].
		c == true ifTrue: [c := 0].
		c == false ifTrue: [c := 1].
		((c isKindOf: Integer) and: [c between: 0 and: 255])
			ifTrue: [Smalltalk exit: c]
			ifFalse: [(LispError new) signal: ''exit: expected #t, #f or an integer from 0 to 255: '' , (LispPrinter writeString: c limitedTo: 60)]] required: 0).
	anEnv define: (LispSymbol named: ''save-image'') value: (LispProcedure fixed: [self saveImage] arity: 0).
	anEnv define: (LispSymbol named: ''procedure-source'') value: (LispProcedure fixed: [:p | p source ifNil: [false]] arity: 1).
	anEnv define: (LispSymbol named: ''stack-depth'') value: (LispProcedure fixed: [| c n |
		c := thisContext.
		n := 0.
		[c notNil] whileTrue: [n := n + 1. c := c sender].
		n] arity: 0).
	anEnv define: (LispSymbol named: ''disassemble'') value: (LispProcedure fixed: [:p |
		self output nextPutAll: p block compiledBlock symbolic; nextPut: Character lf; flush.
		LispUnspecified default] arity: 1)'.
cm value: prims class value: 'installing' value: 'installControlInto: anEnv
	"apply answers a bounce rather than calling, so that a tail call through apply
	 runs in constant stack; every caller of a procedure drives bounces (Phase 6)."
	anEnv define: (LispSymbol named: ''apply'') value: (LispProcedure fixed: [:prc :argList | LispProcedure tailCall: prc to: (LispCons elementsOf: argList for: ''apply'') asArray] arity: 2)'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Runtime'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Runtime: ' , failures size printString].
