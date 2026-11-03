"============================================================================
 cog-lisp : Phase 1 implementation  (package CogLisp-Reader)
 Scheme-like reader + write-style printer, per specs/phase-1-reader-printer.md.

 This is a LOADER script: executed as one chunk, it installs the classes and
 compiles every method with #compile:classified:. It is filed in by the test
 harness (tests/phase-1-reader-printer.st) at the start of each fresh-image run,
 since the image is never saved. Compile failures are collected and reported at
 the end rather than aborting the load, so all problems surface in one pass.

 Classes: LispCons, LispSymbol, LispEmptyList, LispReadError, LispReader,
 LispPrinter.
 ============================================================================"
| failures cm cons sym empty unspec err rdr prn |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

"--- install all classes first, so method bodies may name their siblings ------"
cons  := (Object << #LispCons) slots: { #car. #cdr }; package: 'CogLisp-Reader'; install.
sym   := (Object << #LispSymbol) slots: { #name }; sharedVariables: { #Interned }; package: 'CogLisp-Reader'; install.
empty := (Object << #LispEmptyList) sharedVariables: { #Default }; package: 'CogLisp-Reader'; install.
unspec := (Object << #LispUnspecified) sharedVariables: { #Default }; package: 'CogLisp-Reader'; install.
err   := (Error  << #LispReadError) slots: { #position. #incomplete }; package: 'CogLisp-Reader'; install.
rdr   := (Object << #LispReader) slots: { #stream. #source. #ranges }; sharedVariables: { #Eof }; package: 'CogLisp-Reader'; install.
prn   := (Object << #LispPrinter) package: 'CogLisp-Reader'; install.

"=== LispCons =============================================================="
cm value: cons value: 'accessing' value: 'car
	^ car'.
cm value: cons value: 'accessing' value: 'cdr
	^ cdr'.
cm value: cons value: 'accessing' value: 'car: aValue
	car := aValue'.
cm value: cons value: 'accessing' value: 'cdr: aValue
	cdr := aValue'.
cm value: cons value: 'private' value: 'setCar: a cdr: b
	car := a.
	cdr := b'.
cm value: cons value: 'testing' value: 'isLispCons
	^ true'.
cm value: cons value: 'testing' value: 'isProperList
	| cur |
	cur := self.
	[cur isKindOf: LispCons] whileTrue: [cur := cur cdr].
	^ cur isKindOf: LispEmptyList'.
cm value: cons value: 'enumerating' value: 'lispElements
	| cur els |
	els := OrderedCollection new.
	cur := self.
	[cur isKindOf: LispCons] whileTrue: [els add: cur car. cur := cur cdr].
	^ els'.
cm value: cons value: 'enumerating' value: 'lispTail
	| cur |
	cur := self.
	[cur isKindOf: LispCons] whileTrue: [cur := cur cdr].
	^ cur'.
cm value: cons class value: 'instance creation' value: 'car: a cdr: b
	^ self new setCar: a cdr: b'.
cm value: cons class value: 'instance creation' value: 'fromArray: anArray
	| result |
	result := LispEmptyList default.
	anArray reverseDo: [:e | result := self car: e cdr: result].
	^ result'.
cm value: cons class value: 'quasiquote' value: 'qqAppend: aList to: tail
	"Fresh copy of the proper list aList, ending in tail: the runtime part of
	 unquote-splicing (Phase 7 section 4). Never uses the global append."
	| result |
	(aList == LispEmptyList default or: [(aList isKindOf: LispCons) and: [aList isProperList]])
		ifFalse: [^ (Error new) signal: ''unquote-splicing: not a list''].
	result := tail.
	aList lispElements reverseDo: [:e | result := self car: e cdr: result].
	^ result'.

"=== LispSymbol ============================================================"
cm value: sym value: 'accessing' value: 'name
	^ name'.
cm value: sym value: 'private' value: 'setName: aString
	name := aString'.
cm value: sym value: 'testing' value: 'isLispSymbol
	^ true'.
cm value: sym class value: 'instance creation' value: 'named: aString
	Interned isNil ifTrue: [Interned := Dictionary new].
	^ Interned at: aString ifAbsent: [Interned at: aString put: (self new setName: aString)]'.

"=== LispEmptyList ========================================================="
cm value: empty value: 'testing' value: 'isLispEmptyList
	^ true'.
cm value: empty value: 'testing' value: 'isProperList
	^ true'.
cm value: empty value: 'enumerating' value: 'lispElements
	^ OrderedCollection new'.
cm value: empty value: 'enumerating' value: 'lispTail
	^ self'.
cm value: empty class value: 'accessing' value: 'default
	Default isNil ifTrue: [Default := self basicNew].
	^ Default'.

"=== LispUnspecified (Phase 5 section 5.1) ================================="
cm value: unspec value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<unspecified>'''.
cm value: unspec class value: 'accessing' value: 'default
	Default isNil ifTrue: [Default := self basicNew].
	^ Default'.

"=== LispReadError ========================================================="
cm value: err value: 'accessing' value: 'position
	^ position'.
cm value: err value: 'accessing' value: 'position: anInteger
	position := anInteger'.
cm value: err value: 'accessing' value: 'incomplete: aBoolean
	incomplete := aBoolean'.
cm value: err value: 'testing' value: 'isIncomplete
	"True when the error happened because the input ran out, so more input could complete it."
	^ incomplete == true'.

"=== LispReader ============================================================"
cm value: rdr value: 'private' value: 'setStream: aStream source: aString
	stream := aStream.
	source := aString.
	ranges := IdentityDictionary new'.
cm value: rdr value: 'source' value: 'sourceFor: aCons
	"The exact source text a list was read from, or nil (Phase 5 section 5.2)."
	| range |
	source isNil ifTrue: [^ nil].
	range := ranges at: aCons ifAbsent: [^ nil].
	^ source copyFrom: range key to: range value'.
cm value: rdr value: 'error handling' value: 'signalError: aString
	^ (LispReadError new) position: stream position; incomplete: stream atEnd; signal: aString'.
cm value: rdr value: 'scanning' value: 'isDelimiter: aChar
	^ aChar isSeparator or: [#($( $) $" $; $'' $` $,) includes: aChar]'.
cm value: rdr value: 'reading' value: 'next
	self skipIntertoken.
	stream atEnd ifTrue: [^ self class eofObject].
	^ self readDatum'.
cm value: rdr value: 'reading' value: 'atEnd
	self skipIntertoken.
	^ stream atEnd'.
cm value: rdr value: 'scanning' value: 'skipIntertoken
	[stream atEnd] whileFalse: [
		| c |
		c := stream peek.
		c isSeparator
			ifTrue: [stream next]
			ifFalse: [
				c = $;
					ifTrue: [self skipLineComment]
					ifFalse: [
						(c = $# and: [self peekAheadIsBlockComment])
							ifTrue: [self skipBlockComment]
							ifFalse: [^ self]]]]'.
cm value: rdr value: 'scanning' value: 'peekAheadIsBlockComment
	| pos result |
	pos := stream position.
	stream next.
	result := stream atEnd not and: [stream peek = $|].
	stream position: pos.
	^ result'.
cm value: rdr value: 'scanning' value: 'skipLineComment
	[stream atEnd or: [stream peek = Character lf]] whileFalse: [stream next].
	stream atEnd ifFalse: [stream next]'.
cm value: rdr value: 'scanning' value: 'skipBlockComment
	| depth |
	stream next. stream next.
	depth := 1.
	[depth > 0] whileTrue: [
		stream atEnd ifTrue: [^ self signalError: ''unterminated block comment''].
		(self tryConsume: $# next: $|)
			ifTrue: [depth := depth + 1]
			ifFalse: [
				(self tryConsume: $| next: $#)
					ifTrue: [depth := depth - 1]
					ifFalse: [stream next]]]'.
cm value: rdr value: 'scanning' value: 'tryConsume: a next: b
	| pos |
	pos := stream position.
	(stream atEnd not and: [stream peek = a]) ifFalse: [^ false].
	stream next.
	(stream atEnd not and: [stream peek = b]) ifFalse: [stream position: pos. ^ false].
	stream next.
	^ true'.
cm value: rdr value: 'reading' value: 'readDatum
	| c |
	c := stream peek.
	c = $( ifTrue: [^ self readList].
	c = $) ifTrue: [^ self signalError: ''unexpected )''].
	c = $'' ifTrue: [stream next. ^ self readQuote].
	c = $` ifTrue: [stream next. ^ self readAbbreviation: ''quasiquote''].
	c = $, ifTrue: [
		stream next.
		(stream atEnd not and: [stream peek = $@]) ifTrue: [stream next. ^ self readAbbreviation: ''unquote-splicing''].
		^ self readAbbreviation: ''unquote''].
	c = $" ifTrue: [^ self readString].
	c = $# ifTrue: [^ self readHash].
	^ self readToken'.
cm value: rdr value: 'reading' value: 'readNextDatum
	self skipIntertoken.
	stream atEnd ifTrue: [^ self signalError: ''unexpected end of input''].
	^ self readDatum'.
cm value: rdr value: 'reading' value: 'readQuote
	^ self readAbbreviation: ''quote'''.
cm value: rdr value: 'reading' value: 'readAbbreviation: aName
	"''x `x ,x ,@x read as (quote x) (quasiquote x) (unquote x) (unquote-splicing x)."
	^ LispCons
		car: (LispSymbol named: aName)
		cdr: (LispCons car: self readNextDatum cdr: LispEmptyList default)'.
cm value: rdr value: 'reading' value: 'readList
	| start result |
	start := stream position.
	result := self readListBody.
	(result isKindOf: LispCons) ifTrue: [ranges at: result put: (start + 1) -> stream position].
	^ result'.
cm value: rdr value: 'reading' value: 'readListBody
	| elements tail |
	stream next.
	elements := OrderedCollection new.
	tail := LispEmptyList default.
	[self skipIntertoken.
	 stream atEnd ifTrue: [^ self signalError: ''unterminated list''].
	 stream peek = $)] whileFalse: [
		self atDotMarker
			ifTrue: [
				elements isEmpty ifTrue: [^ self signalError: ''bad dotted pair''].
				stream next.
				tail := self readNextDatum.
				self skipIntertoken.
				(stream atEnd not and: [stream peek = $)]) ifFalse: [^ self signalError: ''bad dotted pair''].
				stream next.
				^ self buildList: elements tail: tail]
			ifFalse: [elements add: self readDatum]].
	stream next.
	^ self buildList: elements tail: tail'.
cm value: rdr value: 'scanning' value: 'atDotMarker
	| pos isDot |
	stream peek = $. ifFalse: [^ false].
	pos := stream position.
	stream next.
	isDot := stream atEnd or: [self isDelimiter: stream peek].
	stream position: pos.
	^ isDot'.
cm value: rdr value: 'private' value: 'buildList: anOrderedCollection tail: tailValue
	| result |
	result := tailValue.
	anOrderedCollection reverseDo: [:e | result := LispCons car: e cdr: result].
	^ result'.
cm value: rdr value: 'reading' value: 'readString
	| s c |
	stream next.
	s := WriteStream on: String new.
	[stream atEnd ifTrue: [^ self signalError: ''unterminated string''].
	 (c := stream next) = $"] whileFalse: [
		c = $\ ifTrue: [s nextPut: self readEscape] ifFalse: [s nextPut: c]].
	^ s contents'.
cm value: rdr value: 'reading' value: 'readEscape
	| c |
	stream atEnd ifTrue: [^ self signalError: ''unterminated string escape''].
	c := stream next.
	c = $" ifTrue: [^ $"].
	c = $\ ifTrue: [^ $\].
	c = $n ifTrue: [^ Character lf].
	c = $t ifTrue: [^ Character tab].
	c = $r ifTrue: [^ Character cr].
	c = $0 ifTrue: [^ Character value: 0].
	^ self signalError: ''unknown string escape''.'.
cm value: rdr value: 'reading' value: 'readToken
	| s str |
	s := WriteStream on: String new.
	[stream atEnd or: [self isDelimiter: stream peek]] whileFalse: [s nextPut: stream next].
	str := s contents.
	str isEmpty ifTrue: [^ self signalError: ''unexpected character''].
	^ self classifyToken: str'.
cm value: rdr value: 'reading' value: 'classifyToken: str
	(self looksLikeInteger: str) ifTrue: [^ str asInteger].
	(self looksLikeFloat: str) ifTrue: [^ self parseFloat: str].
	^ LispSymbol named: str'.
cm value: rdr value: 'number parsing' value: 'looksLikeInteger: str
	| i |
	str isEmpty ifTrue: [^ false].
	i := 1.
	((str at: 1) = $+ or: [(str at: 1) = $-]) ifTrue: [i := 2].
	i > str size ifTrue: [^ false].
	i to: str size do: [:k | (str at: k) isDigit ifFalse: [^ false]].
	^ true'.
cm value: rdr value: 'number parsing' value: 'looksLikeFloat: str
	| i sz digitsBefore digitsAfter hasDot hasExp expDigits |
	sz := str size.
	i := 1.
	(i <= sz and: [(str at: i) = $+ or: [(str at: i) = $-]]) ifTrue: [i := i + 1].
	digitsBefore := 0.
	[i <= sz and: [(str at: i) isDigit]] whileTrue: [digitsBefore := digitsBefore + 1. i := i + 1].
	hasDot := false.
	(i <= sz and: [(str at: i) = $.]) ifTrue: [hasDot := true. i := i + 1].
	digitsAfter := 0.
	[i <= sz and: [(str at: i) isDigit]] whileTrue: [digitsAfter := digitsAfter + 1. i := i + 1].
	digitsBefore + digitsAfter = 0 ifTrue: [^ false].
	hasExp := false.
	(i <= sz and: [(str at: i) = $e or: [(str at: i) = $E]]) ifTrue: [
		hasExp := true.
		i := i + 1.
		(i <= sz and: [(str at: i) = $+ or: [(str at: i) = $-]]) ifTrue: [i := i + 1].
		expDigits := 0.
		[i <= sz and: [(str at: i) isDigit]] whileTrue: [expDigits := expDigits + 1. i := i + 1].
		expDigits = 0 ifTrue: [^ false]].
	(hasDot or: [hasExp]) ifFalse: [^ false].
	^ i > sz'.
cm value: rdr value: 'number parsing' value: 'parseFloat: str
	| i sz sign intPart fracPart fracLen expSign exp mantissa value |
	i := 1. sz := str size. sign := 1.
	(str at: i) = $- ifTrue: [sign := -1. i := i + 1] ifFalse: [(str at: i) = $+ ifTrue: [i := i + 1]].
	intPart := 0.
	[i <= sz and: [(str at: i) isDigit]] whileTrue: [intPart := intPart * 10 + (str at: i) digitValue. i := i + 1].
	fracPart := 0. fracLen := 0.
	(i <= sz and: [(str at: i) = $.]) ifTrue: [
		i := i + 1.
		[i <= sz and: [(str at: i) isDigit]] whileTrue: [fracPart := fracPart * 10 + (str at: i) digitValue. fracLen := fracLen + 1. i := i + 1]].
	exp := 0. expSign := 1.
	(i <= sz and: [(str at: i) = $e or: [(str at: i) = $E]]) ifTrue: [
		i := i + 1.
		(str at: i) = $- ifTrue: [expSign := -1. i := i + 1] ifFalse: [(str at: i) = $+ ifTrue: [i := i + 1]].
		[i <= sz and: [(str at: i) isDigit]] whileTrue: [exp := exp * 10 + (str at: i) digitValue. i := i + 1]].
	mantissa := intPart * (10 raisedTo: fracLen) + fracPart.
	value := sign * mantissa / (10 raisedTo: fracLen).
	value := value * (10 raisedTo: expSign * exp).
	^ value asFloat'.
cm value: rdr value: 'reading' value: 'readHash
	| c word |
	stream next.
	stream atEnd ifTrue: [^ self signalError: ''unexpected # at end of input''].
	c := stream peek.
	c = $\ ifTrue: [stream next. ^ self readCharacter].
	word := self readHashWord.
	(word = ''t'' or: [word = ''true'']) ifTrue: [^ true].
	(word = ''f'' or: [word = ''false'']) ifTrue: [^ false].
	^ self signalError: ''unknown # syntax: #'' , word'.
cm value: rdr value: 'reading' value: 'readHashWord
	| s |
	s := WriteStream on: String new.
	[stream atEnd or: [self isDelimiter: stream peek]] whileFalse: [s nextPut: stream next].
	^ s contents'.
cm value: rdr value: 'reading' value: 'readCharacter
	| s |
	stream atEnd ifTrue: [^ self signalError: ''unterminated character literal''].
	s := WriteStream on: String new.
	s nextPut: stream next.
	[stream atEnd or: [self isDelimiter: stream peek]] whileFalse: [s nextPut: stream next].
	^ self decodeCharacter: s contents'.
cm value: rdr value: 'reading' value: 'decodeCharacter: aName
	aName size = 1 ifTrue: [^ aName first].
	aName = ''space'' ifTrue: [^ Character space].
	aName = ''newline'' ifTrue: [^ Character lf].
	aName = ''tab'' ifTrue: [^ Character tab].
	aName = ''return'' ifTrue: [^ Character cr].
	aName = ''null'' ifTrue: [^ Character value: 0].
	((aName first = $x or: [aName first = $X]) and: [aName size > 1])
		ifTrue: [^ Character value: (Integer readFrom: aName allButFirst readStream base: 16)].
	^ self signalError: ''unknown character name''.'.
cm value: rdr value: 'reading' value: 'readSingle
	| d |
	d := self next.
	d == self class eofObject ifTrue: [^ (LispReadError new) incomplete: true; signal: ''read: empty input''].
	self next == self class eofObject ifFalse: [^ (LispReadError new) signal: ''read: more than one datum''].
	^ d'.
cm value: rdr class value: 'instance creation' value: 'on: aStringOrStream
	aStringOrStream isString ifTrue: [^ self new setStream: aStringOrStream readStream source: aStringOrStream].
	^ self new setStream: aStringOrStream source: nil'.
cm value: rdr class value: 'accessing' value: 'eofObject
	Eof isNil ifTrue: [Eof := Object new].
	^ Eof'.
cm value: rdr class value: 'reading' value: 'read: aString
	^ (self on: aString) readSingle'.
cm value: rdr class value: 'reading' value: 'readAll: aString
	| r d result |
	r := self on: aString.
	result := OrderedCollection new.
	[(d := r next) == self eofObject] whileFalse: [result add: d].
	^ result'.

"=== LispPrinter (stateless, class-side) ==================================="
cm value: prn class value: 'writing' value: 'writeString: aValue
	^ String streamContents: [:s | self write: aValue on: s]'.
cm value: prn class value: 'writing' value: 'write: v on: s
	v == true ifTrue: [^ s nextPutAll: ''#t''].
	v == false ifTrue: [^ s nextPutAll: ''#f''].
	(v isKindOf: LispEmptyList) ifTrue: [^ s nextPutAll: ''()''].
	(v isKindOf: LispSymbol) ifTrue: [^ s nextPutAll: v name].
	(v isKindOf: LispCons) ifTrue: [^ self writeList: v on: s].
	(v isKindOf: Integer) ifTrue: [^ s nextPutAll: v printString].
	(v isKindOf: Float) ifTrue: [^ self writeFloat: v on: s].
	(v isKindOf: Character) ifTrue: [^ self writeCharacter: v on: s].
	(v isKindOf: String) ifTrue: [^ self writeStringLiteral: v on: s].
	"Anything else (the unspecified value, procedures, host objects) writes its printString."
	^ s nextPutAll: v printString'.
cm value: prn class value: 'writing' value: 'writeList: aCons on: s
	| cur |
	s nextPut: $(.
	cur := aCons.
	[cur isKindOf: LispCons] whileTrue: [
		self write: cur car on: s.
		cur := cur cdr.
		(cur isKindOf: LispCons) ifTrue: [s nextPut: Character space]].
	(cur isKindOf: LispEmptyList) ifFalse: [s nextPutAll: '' . ''. self write: cur on: s].
	s nextPut: $)'.
cm value: prn class value: 'writing' value: 'writeFloat: aFloat on: s
	s nextPutAll: aFloat printString'.
cm value: prn class value: 'writing' value: 'writeCharacter: c on: s
	c = Character space ifTrue: [^ s nextPutAll: ''#\space''].
	c = Character lf ifTrue: [^ s nextPutAll: ''#\newline''].
	c = Character tab ifTrue: [^ s nextPutAll: ''#\tab''].
	c = Character cr ifTrue: [^ s nextPutAll: ''#\return''].
	c = (Character value: 0) ifTrue: [^ s nextPutAll: ''#\null''].
	s nextPutAll: ''#\''.
	s nextPut: c'.
cm value: prn class value: 'writing' value: 'writeStringLiteral: str on: s
	s nextPut: $".
	str do: [:ch |
		ch = $" ifTrue: [s nextPut: $\. s nextPut: $"]
		ifFalse: [ch = $\ ifTrue: [s nextPut: $\. s nextPut: $\]
		ifFalse: [ch = Character lf ifTrue: [s nextPut: $\. s nextPut: $n]
		ifFalse: [ch = Character tab ifTrue: [s nextPut: $\. s nextPut: $t]
		ifFalse: [ch = Character cr ifTrue: [s nextPut: $\. s nextPut: $r]
		ifFalse: [ch = (Character value: 0) ifTrue: [s nextPut: $\. s nextPut: $0]
		ifFalse: [s nextPut: ch]]]]]]].
	s nextPut: $"'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Reader'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Reader: ' , failures size printString].
