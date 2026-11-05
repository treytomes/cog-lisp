"============================================================================
 cog-lisp : Phase 1 implementation  (package CogLisp-Reader)
 The data the reader makes and the write-style printer, per
 specs/phase-1-reader-printer.md. The reader itself is written in LISP
 (lib/compiler/reader.lisp) since Phase 9 step 9.1; LispReader keeps its
 Smalltalk-side protocol.

 This is a LOADER script: executed as one chunk, it installs the classes and
 compiles every method with #compile:classified:. It is filed in by the test
 harness (tests/phase-1-reader-printer.st) at the start of each fresh-image run,
 since the image is never saved. Compile failures are collected and reported at
 the end rather than aborting the load, so all problems surface in one pass.

 Classes: LispCons, LispSymbol, LispEmptyList, LispReadError, LispReader,
 LispPrinter.
 ============================================================================"
| failures cm cons sym empty unspec lerr err loc ferr eofc hole rdr prn |
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
"A datum label not yet filled in, while #n=datum is being read (Phase 7.9 section 6)."
hole  := (Object << #LispLabelHole) package: 'CogLisp-Reader'; install.
rdr   := (Object << #LispReader) sharedVariables: { #Eof }; package: 'CogLisp-Reader'; install.
prn   := (Object << #LispPrinter) sharedVariables: { #Labels. #LabelCount }; package: 'CogLisp-Reader'; install.

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
		"arithmetic on a non-number: (+ 1 x) fails coercing x, (+ x 1) sends + to x"
		(#(#adaptToNumber:andSend: #adaptToInteger:andSend: #adaptToFloat:andSend: #adaptToFraction:andSend:) includes: sel)
			ifTrue: [^ anError message arguments last asString , '': not a number: '' ,
				"Pharo coerces a string a character at a time, so a character fails here"
				((rcv isKindOf: Character) ifTrue: [''a string or a character''] ifFalse: [self show: rcv])].
		((#(#+ #- #* #/ #< #> #<= #>= #negated #abs #// #\\ #rem: #quo: #min: #max:) includes: sel) and: [rcv isNumber not])
			ifTrue: [^ sel asString , '': not a number: '' , (self show: rcv)].
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

"=== LispReader: the reader's Smalltalk-side protocol ======================
 The reader itself is written in LISP (lib/compiler/reader.lisp, Phase 8) and
 built into the image; the one written in Smalltalk retired in Phase 9 step 9.1.
 These class-side methods are how Smalltalk code reads LISP text."
cm value: rdr class value: 'instance creation' value: 'on: aStringOrStream
	"A reader over a string, or a ReadStream over one, answering next, atEnd,
	 readSingle, datumStart, position and sourceFor: (a LispReaderInLisp). The
	 compiler package loads after this one, so it is looked up by name."
	^ (Smalltalk at: #LispCompiler) readerOn: aStringOrStream'.
cm value: rdr class value: 'reading' value: 'readFrom: aStream
	"One datum from an input port''s stream, or the eof object: a LispLineStream
	 (standard input) reads more lines while the datum is incomplete; anything else
	 is a ReadStream over a string."
	(aStream respondsTo: #readDatum) ifTrue: [^ aStream readDatum].
	^ (self on: aStream) next'.
cm value: eofc value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<eof>'''.
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
cm value: prn class value: 'writing' value: 'writeSharedString: aValue
	"write-shared: labels every shared pair or vector, not only cycles."
	^ String streamContents: [:s | self printTop: aValue on: s display: false shared: true]'.
cm value: prn class value: 'labels' value: 'printTop: v on: s display: displaying shared: sharedToo
	"Print v; pairs and vectors on a cycle (or, with sharedToo, met twice) are written
	 with datum labels #n= and #n#, so printing never loops (R7RS write; Phase 7.9
	 section 6). Values with no cycles print exactly as before."
	| labels savedLabels savedCount |
	labels := self labelsFor: v shared: sharedToo.
	labels isEmpty ifTrue: [^ self print: v on: s display: displaying].
	savedLabels := Labels.
	savedCount := LabelCount.
	Labels := labels.
	LabelCount := 0.
	[self print: v on: s display: displaying] ensure: [Labels := savedLabels. LabelCount := savedCount]'.
cm value: prn class value: 'labels' value: 'labelsFor: v shared: sharedToo
	| labels |
	((v isKindOf: LispCons) or: [v isKindOf: Array]) ifFalse: [^ #()].
	labels := IdentityDictionary new.
	self scan: v visited: IdentitySet new onPath: IdentitySet new labels: labels shared: sharedToo.
	^ labels'.
cm value: prn class value: 'labels' value: 'scan: v visited: visited onPath: onPath labels: labels shared: sharedToo
	"Depth first, iterative along cdrs: a node met again while it is on the path
	 being printed is on a cycle."
	| cur pushed done |
	pushed := OrderedCollection new.
	cur := v.
	done := false.
	[done not and: [(cur isKindOf: LispCons) or: [cur isKindOf: Array]]] whileTrue: [
		(onPath includes: cur)
			ifTrue: [labels at: cur put: nil. done := true]
			ifFalse: [(visited includes: cur)
				ifTrue: [sharedToo ifTrue: [labels at: cur put: nil]. done := true]
				ifFalse: [
					visited add: cur. onPath add: cur. pushed add: cur.
					(cur isKindOf: Array)
						ifTrue: [
							cur do: [:e | self scan: e visited: visited onPath: onPath labels: labels shared: sharedToo].
							done := true]
						ifFalse: [
							self scan: cur car visited: visited onPath: onPath labels: labels shared: sharedToo.
							cur := cur cdr]]]].
	pushed do: [:x | onPath remove: x]'.
cm value: prn class value: 'labels' value: 'printLabel: v on: s
	"Write #n# and answer true if v was labelled already; else write #n= and answer false."
	| n |
	n := Labels at: v.
	n notNil ifTrue: [s nextPut: $#; print: n; nextPut: $#. ^ true].
	Labels at: v put: LabelCount.
	s nextPut: $#; print: LabelCount; nextPut: $=.
	LabelCount := LabelCount + 1.
	^ false'.
cm value: prn class value: 'writing' value: 'writeString: aValue limitedTo: n
	"At most n characters, ending in ... when cut short: safe on circular lists."
	| text |
	text := [String streamContents: [:s | self write: aValue on: s] limitedTo: n]
		on: Error do: [:e | aValue printString].
	^ text size >= n ifTrue: [(text first: n) , ''...''] ifFalse: [text]'.
cm value: prn class value: 'writing' value: 'displayString: aValue
	"As display shows it: strings and characters as their own text, also inside
	 lists (R7RS; review R-8)."
	^ String streamContents: [:s | self printTop: aValue on: s display: true shared: false]'.
cm value: prn class value: 'writing' value: 'write: v on: s
	^ self printTop: v on: s display: false shared: false'.
cm value: prn class value: 'writing' value: 'print: v on: s display: displaying
	(Labels notNil and: [(Labels includesKey: v) and: [self printLabel: v on: s]]) ifTrue: [^ self].
	displaying ifTrue: [
		((v isKindOf: String) and: [v isSymbol not]) ifTrue: [^ s nextPutAll: v].
		(v isKindOf: Character) ifTrue: [^ s nextPut: v]].
	(v isKindOf: Array) ifTrue: [
		s nextPutAll: ''#(''.
		v do: [:e | self print: e on: s display: displaying] separatedBy: [s nextPut: Character space].
		^ s nextPut: $)].
	(v isKindOf: LispCons) ifTrue: [^ self printList: v on: s display: displaying].
	"a number writes itself (the number protocol, Phase 9 step 9.2): 3/2, +inf.0"
	v isNumber ifTrue: [^ v lispWriteOn: s base: 10].
	v == true ifTrue: [^ s nextPutAll: ''#t''].
	v == false ifTrue: [^ s nextPutAll: ''#f''].
	(v isKindOf: LispEmptyList) ifTrue: [^ s nextPutAll: ''()''].
	(v isKindOf: LispSymbol) ifTrue: [^ s nextPutAll: v name].
	(v isKindOf: LispCons) ifTrue: [^ self writeList: v on: s].
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
	[self print: cur car on: s display: displaying.
	 cur := cur cdr.
	 "a labelled cdr is written after a dot: (1 2 . #0#)"
	 (cur isKindOf: LispCons) and: [Labels isNil or: [(Labels includesKey: cur) not]]]
		whileTrue: [s nextPut: Character space].
	(cur isKindOf: LispEmptyList) ifFalse: [s nextPutAll: '' . ''. self print: cur on: s display: displaying].
	s nextPut: $)'.
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
		ifFalse: [(ch asInteger < 32 or: [ch asInteger = 127])
			ifTrue: [s nextPutAll: ''\x''; nextPutAll: (ch asInteger printStringBase: 16) asLowercase; nextPut: $;]
			ifFalse: [s nextPut: ch]]]]]]]].
	s nextPut: $"'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Reader'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Reader: ' , failures size printString].
