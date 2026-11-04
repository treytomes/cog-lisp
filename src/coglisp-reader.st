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
| failures cm cons sym empty unspec lerr err loc ferr eofc rdr prn |
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
"LispError is the root of every cog-lisp error, so a handler can tell a LISP error
 from a host bug (specs/review-phases-1-7.md R-16). It lives here, in the first
 package, so every later package can subclass it."
lerr  := (Error  << #LispError) slots: { #irritants }; package: 'CogLisp-Reader'; install.
"A file that cannot be found or opened (R7RS file-error?; Phase 7.7)."
ferr  := (lerr   << #LispFileError) package: 'CogLisp-Reader'; install.
err   := (lerr   << #LispReadError) slots: { #position. #incomplete }; package: 'CogLisp-Reader'; install.
"An error raised while running a file, with where it happened (review R-1). The
 runner prints it as path:line:col: error: message, which editors can parse."
loc   := (lerr   << #LispLocatedError) slots: { #cause. #file. #line. #column }; package: 'CogLisp-Reader'; install.
"The end-of-file object: read, read-char and friends answer it (Phase 7.8)."
eofc  := (Object << #LispEofObject) package: 'CogLisp-Reader'; install.
rdr   := (Object << #LispReader) slots: { #stream. #source. #ranges. #datumStart }; sharedVariables: { #Eof }; package: 'CogLisp-Reader'; install.
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
cm value: cons class value: 'instance creation' value: 'fromArray: anArray tail: tail
	"A fresh list of anArray''s elements ending in tail (quasiquote, review C-3)."
	| result |
	result := tail.
	anArray reverseDo: [:e | result := self car: e cdr: result].
	^ result'.
cm value: cons class value: 'instance creation' value: 'fromArray: anArray
	| result |
	result := LispEmptyList default.
	anArray reverseDo: [:e | result := self car: e cdr: result].
	^ result'.
cm value: cons class value: 'checked access' value: 'elementsOf: aList for: aName
	"The elements of the proper list aList, or a LispError naming the procedure
	 aName: for a non-list, a dotted list, or a circular one (review R-2, R-4, R-9).
	 The cycle check is Floyd''s: a second pointer moving at half speed."
	| els cur slow step |
	els := OrderedCollection new.
	cur := aList.
	slow := aList.
	step := 0.
	[cur isKindOf: LispCons] whileTrue: [
		els add: cur car.
		cur := cur cdr.
		step := step + 1.
		step even ifTrue: [
			slow := slow cdr.
			slow == cur ifTrue: [^ (LispError new) signal: aName , '': circular list'']]].
	cur == LispEmptyList default ifFalse: [
		^ (LispError new) signal: aName , '': not a proper list: '' , (LispPrinter writeString: aList limitedTo: 60)].
	^ els'.
cm value: cons class value: 'quasiquote' value: 'qqAppend: aList to: tail
	"Fresh copy of the proper list aList, ending in tail: the runtime part of
	 unquote-splicing (Phase 7 section 4). Never uses the global append."
	| result |
	(aList == LispEmptyList default or: [(aList isKindOf: LispCons) and: [aList isProperList]])
		ifFalse: [^ (LispError new) signal: ''unquote-splicing: not a list''].	"review C-18"
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
cm value: sym class value: 'testing' value: 'isInterned: aSymbol
	"False for a gensym: no symbol read from text is identical to it."
	^ Interned notNil and: [(Interned at: aSymbol name ifAbsent: [nil]) == aSymbol]'.
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
cm value: cons value: 'smalltalk protocol' value: 'do: aBlock
	"Smalltalk code can iterate a LISP list (Phase 7.6 section 4.5)."
	| cur |
	cur := self.
	[cur isKindOf: LispCons] whileTrue: [aBlock value: cur car. cur := cur cdr]'.
cm value: cons value: 'smalltalk protocol' value: 'collect: aBlock
	"A new LISP list of the results."
	^ LispCons fromArray: (self lispElements collect: [:e | aBlock value: e]) asArray'.
cm value: cons value: 'smalltalk protocol' value: 'size
	^ self lispElements size'.
cm value: cons value: 'smalltalk protocol' value: 'asArray
	^ self lispElements asArray'.
cm value: cons value: 'smalltalk protocol' value: 'asOrderedCollection
	^ self lispElements asOrderedCollection'.
cm value: empty value: 'smalltalk protocol' value: 'do: aBlock
	^ self'.
cm value: empty value: 'smalltalk protocol' value: 'collect: aBlock
	^ self'.
cm value: empty value: 'smalltalk protocol' value: 'size
	^ 0'.
cm value: empty value: 'smalltalk protocol' value: 'asArray
	^ #()'.
cm value: empty value: 'smalltalk protocol' value: 'asOrderedCollection
	^ OrderedCollection new'.
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

"=== LispError: what a user is told about an error (review R-2) ============="
cm value: lerr value: 'accessing' value: 'irritants
	"The values given to (error message irritant ...), as a LISP list; nil otherwise."
	^ irritants'.
cm value: lerr value: 'accessing' value: 'irritants: aList
	irritants := aList'.
cm value: lerr class value: 'describing' value: 'show: aValue
	^ LispPrinter writeString: aValue limitedTo: 60'.
cm value: lerr class value: 'describing' value: 'describe: anError
	"The message for anError in LISP terms. Host errors that LISP code commonly
	 causes are translated: car of a non-pair, arithmetic on a non-number, division
	 by zero. Anything else keeps its own message (or its class name)."
	| text |
	(anError isKindOf: LispLocatedError) ifTrue: [^ anError messageText].
	(anError isKindOf: MessageNotUnderstood) ifTrue: [ | sel rcv |
		sel := anError message selector.
		rcv := anError receiver.
		sel = #car ifTrue: [^ ''car: not a pair: '' , (self show: rcv)].
		sel = #cdr ifTrue: [^ ''cdr: not a pair: '' , (self show: rcv)].
		sel = #car: ifTrue: [^ ''set-car!!: not a pair: '' , (self show: rcv)].
		sel = #cdr: ifTrue: [^ ''set-cdr!!: not a pair: '' , (self show: rcv)].
		(#(#adaptToNumber:andSend: #adaptToInteger:andSend: #adaptToFloat:andSend: #adaptToFraction:andSend:) includes: sel)
			ifTrue: [^ anError message arguments last asString , '': not a number''].
		"any other message: say so plainly, as Smalltalk would (Phase 7.6 section 7)"
		^ (self show: rcv) , '' does not understand #'' , sel].
	(anError isKindOf: ZeroDivide) ifTrue: [^ ''division by zero''].
	text := anError messageText.
	(text isNil or: [text isEmpty]) ifTrue: [text := anError class name].
	"an error made by the error procedure reports its message, then its irritants as
	 write shows them (Phase 7.7 section 4.1)"
	((anError isKindOf: LispError) and: [anError irritants isKindOf: LispCons]) ifTrue: [
		text := String streamContents: [:s |
			s nextPutAll: text.
			anError irritants do: [:each | s space; nextPutAll: (self show: each)]]].
	^ text'.

"=== LispLocatedError (review R-1) =========================================="
cm value: loc value: 'private' value: 'setCause: anError file: aName line: l column: c
	cause := anError.
	file := aName.
	line := l.
	column := c'.
cm value: loc value: 'accessing' value: 'cause
	^ cause'.
cm value: loc value: 'accessing' value: 'file
	^ file'.
cm value: loc value: 'accessing' value: 'line
	^ line'.
cm value: loc value: 'accessing' value: 'column
	^ column'.
cm value: loc value: 'accessing' value: 'messageText
	"The message of the error itself, in LISP terms."
	^ LispError describe: cause'.
cm value: loc value: 'accessing' value: 'locationText
	^ file , '':'' , line printString , '':'' , column printString'.
cm value: loc value: 'accessing' value: 'reportText
	"path:line:col: error: message (the format a VS Code problem matcher reads)"
	^ self locationText , '': error: '' , self messageText'.
cm value: loc class value: 'instance creation' value: 'cause: anError file: aName source: aString offset: anOffset
	| lc |
	lc := LispReader lineAndColumnOf: anOffset in: aString.
	^ self new setCause: anError file: aName line: lc first column: lc last'.

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
	"An error at the current character. More input would not fix it."
	^ self signalError: aString at: stream position incomplete: false'.
cm value: rdr value: 'error handling' value: 'signalIncomplete: aString at: anOffset
	"The input ran out inside a datum that starts at anOffset: more input could complete it."
	^ self signalError: aString at: anOffset incomplete: true'.
cm value: rdr value: 'error handling' value: 'signalError: aString at: anOffset incomplete: aBoolean
	"anOffset is the 0-based offset of the character the error is about."
	^ (LispReadError new) position: anOffset; incomplete: aBoolean; signal: aString'.
cm value: rdr value: 'scanning' value: 'isDelimiter: aChar
	^ aChar isSeparator or: [#($( $) $[ $] $" $; $'' $` $,) includes: aChar]'.
cm value: rdr value: 'reading' value: 'next
	self skipIntertoken.
	stream atEnd ifTrue: [^ self class eofObject].
	datumStart := stream position.
	^ self readDatum'.
cm value: rdr value: 'source' value: 'datumStart
	"The 0-based offset where the datum last answered by next starts."
	^ datumStart'.
cm value: rdr value: 'source' value: 'source
	^ source'.
cm value: rdr value: 'source' value: 'position
	"How many characters have been read so far."
	^ stream position'.
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
	| depth start |
	start := stream position.
	stream next. stream next.
	depth := 1.
	[depth > 0] whileTrue: [
		stream atEnd ifTrue: [^ self signalIncomplete: ''unterminated block comment'' at: start].
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
	c = $[ ifTrue: [^ self readBracket].
	c = $] ifTrue: [^ self signalError: ''unexpected ]''].
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
	stream atEnd ifTrue: [^ self signalIncomplete: ''unexpected end of input'' at: stream position].
	^ self readDatum'.
cm value: rdr value: 'reading' value: 'readQuote
	^ self readAbbreviation: ''quote'''.
cm value: rdr value: 'reading' value: 'readAbbreviation: aName
	"''x `x ,x ,@x read as (quote x) (quasiquote x) (unquote x) (unquote-splicing x)."
	^ LispCons
		car: (LispSymbol named: aName)
		cdr: (LispCons car: self readNextDatum cdr: LispEmptyList default)'.
cm value: rdr value: 'reading' value: 'readBracket
	"[receiver message ...] reads as (send receiver selector arg ...): Phase 7.6
	 section 4.2. The list keeps the bracket''s source range, like any list."
	| start parts result |
	start := stream position.
	stream next.
	parts := OrderedCollection new.
	[self skipIntertoken.
	 stream atEnd ifTrue: [^ self signalIncomplete: ''unterminated ['' at: start].
	 stream peek = $]] whileFalse: [parts add: self readDatum].
	stream next.
	result := self sendFormFrom: parts at: start.
	ranges at: result put: (start + 1) -> stream position.
	^ result'.
cm value: rdr value: 'reading' value: 'sendFormFrom: parts at: start
	"Unary [r sel], binary [r + a], or keyword [r k1: a1 k2: a2]. A capitalized
	 receiver symbol names a Smalltalk global (section 10, decision 2)."
	| recv rest selector args identifier |
	identifier := ''[a-zA-Z_][a-zA-Z0-9_]*''.
	parts size < 2 ifTrue: [^ self badSendAt: start].
	recv := parts first.
	((recv isKindOf: LispSymbol) and: [recv name first isUppercase]) ifTrue: [
		recv := LispCons fromArray: { LispSymbol named: ''smalltalk''. recv }].
	rest := parts allButFirst.
	(rest size = 1 and: [(rest first isKindOf: LispSymbol) and: [rest first name matchesRegex: identifier]])
		ifTrue: [selector := rest first. args := #()].
	(selector isNil and: [rest size = 2 and: [(rest first isKindOf: LispSymbol)
		and: [rest first name allSatisfy: [:c | ''+-*/\<>=~@%|&?'' includes: c]]]])
		ifTrue: [selector := rest first. args := { rest second }].
	(selector isNil and: [rest size even and: [(1 to: rest size by: 2) allSatisfy: [:i |
		((rest at: i) isKindOf: LispSymbol) and: [(rest at: i) name matchesRegex: identifier , ''\:'']]]])
		ifTrue: [
			selector := LispSymbol named: (String streamContents: [:s |
				1 to: rest size by: 2 do: [:i | s nextPutAll: (rest at: i) name]]).
			args := (2 to: rest size by: 2) collect: [:i | rest at: i]].
	selector isNil ifTrue: [^ self badSendAt: start].
	^ LispCons fromArray: { LispSymbol named: ''send''. recv. selector } , args asArray'.
cm value: rdr value: 'error handling' value: 'badSendAt: start
	^ self signalError: ''bad message send: brackets are Smalltalk sends; use ( ) for grouping''
		at: start incomplete: false'.
cm value: rdr value: 'reading' value: 'readList
	| start result |
	start := stream position.
	result := self readListBodyFrom: start.
	(result isKindOf: LispCons) ifTrue: [ranges at: result put: (start + 1) -> stream position].
	^ result'.
cm value: rdr value: 'reading' value: 'readListBodyFrom: start
	"start is the offset of the opening parenthesis; errors about the whole list point there."
	| elements tail |
	stream next.
	elements := OrderedCollection new.
	tail := LispEmptyList default.
	[self skipIntertoken.
	 stream atEnd ifTrue: [^ self signalIncomplete: ''unterminated list'' at: start].
	 stream peek = $)] whileFalse: [
		self atDotMarker
			ifTrue: [
				elements isEmpty ifTrue: [^ self signalError: ''bad dotted pair''].
				stream next.
				tail := self readNextDatum.
				self skipIntertoken.
				stream atEnd ifTrue: [^ self signalIncomplete: ''unterminated list'' at: start].
				stream peek = $) ifFalse: [^ self signalError: ''bad dotted pair''].
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
	| s c start |
	start := stream position.
	stream next.
	s := WriteStream on: String new.
	[stream atEnd ifTrue: [^ self signalIncomplete: ''unterminated string'' at: start].
	 (c := stream next) = $"] whileFalse: [
		c = $\ ifTrue: [s nextPut: (self readEscapeFrom: start)] ifFalse: [s nextPut: c]].
	^ s contents'.
cm value: rdr value: 'reading' value: 'readEscapeFrom: start
	| c |
	stream atEnd ifTrue: [^ self signalIncomplete: ''unterminated string'' at: start].
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
	"R-23: #| starts a block comment, so it ends a token too"
	[stream atEnd or: [(self isDelimiter: stream peek) or: [stream peek = $# and: [self peekAheadIsBlockComment]]]]
		whileFalse: [s nextPut: stream next].
	str := s contents.
	str isEmpty ifTrue: [^ self signalError: ''unexpected character''].
	"R-14: a lone dot means something only inside a list, where atDotMarker sees it"
	str = ''.'' ifTrue: [^ self signalError: ''unexpected dot'' at: stream position - 1 incomplete: false].
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
	"-0.0 keeps its sign (Phase 1 round trip; review R-12)"
	(value = 0 and: [sign = -1]) ifTrue: [^ Float negativeZero].
	^ value asFloat'.
cm value: rdr value: 'reading' value: 'readHash
	| c word |
	stream next.
	stream atEnd ifTrue: [^ self signalIncomplete: ''unexpected # at end of input'' at: stream position - 1].
	c := stream peek.
	c = $\ ifTrue: [stream next. ^ self readCharacter].
	c = $( ifTrue: [^ self readVector].
	word := self readHashWord.
	(word = ''t'' or: [word = ''true'']) ifTrue: [^ true].
	(word = ''f'' or: [word = ''false'']) ifTrue: [^ false].
	^ self signalError: ''unknown # syntax: #'' , word'.
cm value: eofc value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<eof>'''.
cm value: rdr value: 'reading' value: 'readVector
	"#(...) reads as a vector (a Smalltalk Array), read-only like every literal
	 (Phase 7.8 section 6)."
	| start list |
	start := stream position.
	list := self readListBodyFrom: start.
	(list == LispEmptyList default or: [list isProperList])
		ifFalse: [^ self signalError: ''bad vector: a dotted tail'' at: start - 1 incomplete: false].
	^ (list == LispEmptyList default ifTrue: [Array new] ifFalse: [list lispElements asArray])
		beReadOnlyObject; yourself'.
cm value: rdr value: 'reading' value: 'readHashWord
	| s |
	s := WriteStream on: String new.
	[stream atEnd or: [self isDelimiter: stream peek]] whileFalse: [s nextPut: stream next].
	^ s contents'.
cm value: rdr value: 'reading' value: 'readCharacter
	| s |
	stream atEnd ifTrue: [^ self signalIncomplete: ''unterminated character literal'' at: stream position - 2].
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
	((aName first = $x or: [aName first = $X]) and: [aName size > 1]) ifTrue: [ | code |
		"R-13: a bad code is a read error, not a host number-parsing error"
		(aName allButFirst allSatisfy: [:ch | ''0123456789abcdefABCDEF'' includes: ch])
			ifFalse: [^ self signalError: ''bad character code: #\'' , aName].
		code := Integer readFrom: aName allButFirst readStream base: 16.
		code > 16r10FFFF ifTrue: [^ self signalError: ''bad character code: #\'' , aName].
		^ Character value: code].
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
cm value: rdr class value: 'source' value: 'lineAndColumnOf: anOffset in: aString
	"1-based line and column of the character at the 0-based anOffset."
	| line lineStart limit |
	line := 1.
	lineStart := 1.
	limit := (anOffset max: 0) min: aString size.
	1 to: limit do: [:i | (aString at: i) = Character lf ifTrue: [line := line + 1. lineStart := i + 1]].
	^ { line. limit + 1 - lineStart + 1 }'.
cm value: rdr class value: 'accessing' value: 'eofObject
	Eof isNil ifTrue: [Eof := LispEofObject new].
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
cm value: prn class value: 'writing' value: 'writeString: aValue limitedTo: n
	"At most n characters, ending in ... when cut short: safe on circular lists."
	| text |
	text := [String streamContents: [:s | self write: aValue on: s] limitedTo: n]
		on: Error do: [:e | aValue printString].
	^ text size >= n ifTrue: [(text first: n) , ''...''] ifFalse: [text]'.
cm value: prn class value: 'writing' value: 'displayString: aValue
	"As display shows it: strings and characters as their own text, also inside
	 lists (R7RS; review R-8)."
	^ String streamContents: [:s | self print: aValue on: s display: true]'.
cm value: prn class value: 'writing' value: 'write: v on: s
	^ self print: v on: s display: false'.
cm value: prn class value: 'writing' value: 'print: v on: s display: displaying
	displaying ifTrue: [
		((v isKindOf: String) and: [v isSymbol not]) ifTrue: [^ s nextPutAll: v].
		(v isKindOf: Character) ifTrue: [^ s nextPut: v]].
	(v isKindOf: Array) ifTrue: [
		s nextPutAll: ''#(''.
		v do: [:e | self print: e on: s display: displaying] separatedBy: [s nextPut: Character space].
		^ s nextPut: $)].
	(v isKindOf: LispCons) ifTrue: [^ self printList: v on: s display: displaying].
	"3/2, which reads back as a symbol for now; Smalltalk prints (3/2) (review R-11)"
	(v isKindOf: Fraction) ifTrue: [^ s print: v numerator; nextPut: $/; print: v denominator].
	v == true ifTrue: [^ s nextPutAll: ''#t''].
	v == false ifTrue: [^ s nextPutAll: ''#f''].
	(v isKindOf: LispEmptyList) ifTrue: [^ s nextPutAll: ''()''].
	(v isKindOf: LispSymbol) ifTrue: [^ s nextPutAll: v name].
	(v isKindOf: LispCons) ifTrue: [^ self writeList: v on: s].
	(v isKindOf: Integer) ifTrue: [^ s nextPutAll: v printString].
	(v isKindOf: Float) ifTrue: [^ self writeFloat: v on: s].
	(v isKindOf: Character) ifTrue: [^ self writeCharacter: v on: s].
	(v isKindOf: Symbol) ifTrue: [^ s nextPutAll: ''#<''; nextPutAll: v printString; nextPut: $>].
	(v isKindOf: String) ifTrue: [^ self writeStringLiteral: v on: s].
	"cog-lisp''s own objects (the unspecified value, procedures, macros) print as they
	 say; any other Smalltalk object as #<its printString>, so it cannot be mistaken
	 for LISP data: nil used to print as nil, which reads back as a symbol (Phase 7.6
	 section 4.6; review R-18)."
	(v class package name beginsWith: ''CogLisp'') ifTrue: [^ s nextPutAll: v printString].
	^ s nextPutAll: ''#<''; nextPutAll: v printString; nextPut: $>'.
cm value: prn class value: 'writing' value: 'writeList: aCons on: s
	^ self printList: aCons on: s display: false'.
cm value: prn class value: 'writing' value: 'printList: aCons on: s display: displaying
	| cur |
	s nextPut: $(.
	cur := aCons.
	[cur isKindOf: LispCons] whileTrue: [
		self print: cur car on: s display: displaying.
		cur := cur cdr.
		(cur isKindOf: LispCons) ifTrue: [s nextPut: Character space]].
	(cur isKindOf: LispEmptyList) ifFalse: [s nextPutAll: '' . ''. self print: cur on: s display: displaying].
	s nextPut: $)'.
cm value: prn class value: 'writing' value: 'writeFloat: aFloat on: s
	s nextPutAll: aFloat printString'.
cm value: prn class value: 'writing' value: 'writeCharacter: c on: s
	c = Character space ifTrue: [^ s nextPutAll: ''#\space''].
	c = Character lf ifTrue: [^ s nextPutAll: ''#\newline''].
	c = Character tab ifTrue: [^ s nextPutAll: ''#\tab''].
	c = Character cr ifTrue: [^ s nextPutAll: ''#\return''].
	c = (Character value: 0) ifTrue: [^ s nextPutAll: ''#\null''].
	"other control characters by code, so they are visible (Phase 1 section 8; review R-20)"
	(c asInteger < 32 or: [c asInteger = 127]) ifTrue: [^ s nextPutAll: ''#\x''; nextPutAll: (c asInteger printStringBase: 16) asLowercase].
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
