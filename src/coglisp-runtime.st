"============================================================================
 cog-lisp : Phase 4 implementation  (package CogLisp-Runtime)
 Procedures + primitive library per specs/phase-4-runtime-primitives.md.

 LOADER script. Must be filed in AFTER coglisp-reader.st, coglisp-core.st, and
 coglisp-compiler.st. Set-car and set-cdr contain a bang, written doubled so the
 chunk reader keeps it.

 Classes: LispError, LispArityError, LispProcedure, LispTailCall, LispPrimitives,
 LispTextOutput.
 ============================================================================"
| failures cm lerr aerr proc tcall prims tout facade htab hkey iport oport lines vals |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

lerr  := LispError.  "defined by the reader package"
aerr  := (lerr   << #LispArityError) slots: { #proc. #given }; package: 'CogLisp-Runtime'; install.
proc  := (Object << #LispProcedure) slots: { #block. #required. #hasRest. #name. #source. #entries. #inline. #packed. #documentation. #category }; package: 'CogLisp-Runtime'; install.
tcall := (Object << #LispTailCall) slots: { #fn. #args }; package: 'CogLisp-Runtime'; install.
"Zero or several values, as values answers them (R7RS 6.10; Phase 9 step 9.2)."
vals := (Object << #LispValues) slots: { #values }; package: 'CogLisp-Runtime'; install.
prims := (Object << #LispPrimitives) sharedVariables: { #Output. #Input. #CommandLine. #GensymCounter. #EqualityTests }; package: 'CogLisp-Runtime'; install.
"CogLisp: the Smalltalk-side facade for evaluating and calling LISP (Phase 7.6 section 5.2)."
facade := (Object << #CogLisp) package: 'CogLisp-Runtime'; install.
"Phase 7.8: hash tables (keys wrapped so a Pharo OrderedDictionary compares them
 with eq?, eqv? or equal?) and string ports."
htab := (Object << #LispHashTable) slots: { #dict. #test }; package: 'CogLisp-Runtime'; install.
hkey := (Object << #LispHashKey) slots: { #key. #test }; package: 'CogLisp-Runtime'; install.
iport := (Object << #LispInputPort) slots: { #stream }; package: 'CogLisp-Runtime'; install.
oport := (Object << #LispOutputPort) slots: { #stream }; package: 'CogLisp-Runtime'; install.
"Characters from a line source (stdin, the REPL) with the stream protocol the reader needs (Phase 7.9 section 5.2)."
lines := (Object << #LispLineStream) slots: { #source. #text. #pos }; package: 'CogLisp-Runtime'; install.
tout  := (Object << #LispTextOutput) slots: { #kind. #handle. #stream. #buffer. #midLine }; sharedVariables: { #Session. #Stdout. #Stderr }; package: 'CogLisp-Runtime'; install.


"=== LispHashTable, LispHashKey (Phase 7.8 section 7) ======================="
cm value: htab class value: 'instance creation' value: 'test: aSymbol
	"aSymbol: #eq, #eqv or #equal"
	^ self new setTest: aSymbol'.
cm value: htab class value: 'equality' value: 'same: a as: b test: t
	t == #eq ifTrue: [^ a == b].
	t == #eqv ifTrue: [^ LispCore eqv: a with: b].
	^ LispCore equal: a with: b'.
cm value: htab class value: 'equality' value: 'hashOf: x test: t
	t == #eq ifTrue: [^ x identityHash].
	t == #eqv ifTrue: [^ self eqvHash: x].
	^ self equalHash: x depth: 0'.
cm value: htab class value: 'equality' value: 'eqvHash: x
	(x isNumber or: [x isKindOf: Character]) ifTrue: [^ x hash].
	^ x identityHash'.
cm value: htab class value: 'equality' value: 'equalHash: x depth: d
	"Consistent with equal?, and bounded in depth so a circular list cannot hang it."
	| h |
	d > 4 ifTrue: [^ 7].
	(x isKindOf: LispCons) ifTrue: [
		^ ((self equalHash: x car depth: d + 1) * 31 + (self equalHash: x cdr depth: d + 1)) bitAnd: 16r3FFFFFFF].
	(x isKindOf: Array) ifTrue: [
		h := x size.
		(x first: (x size min: 4)) do: [:e | h := (h * 31 + (self equalHash: e depth: d + 1)) bitAnd: 16r3FFFFFFF].
		^ h].
	(LispCore isString: x) ifTrue: [^ x hash].
	^ self eqvHash: x'.
cm value: htab value: 'private' value: 'setTest: aSymbol
	test := aSymbol.
	dict := OrderedDictionary new'.
cm value: htab value: 'private' value: 'wrap: aKey
	^ LispHashKey key: aKey test: test'.
cm value: htab value: 'accessing' value: 'test
	^ test'.
cm value: htab value: 'accessing' value: 'at: aKey ifAbsent: aBlock
	^ dict at: (self wrap: aKey) ifAbsent: aBlock'.
cm value: htab value: 'accessing' value: 'at: aKey put: aValue
	^ dict at: (self wrap: aKey) put: aValue'.
cm value: htab value: 'accessing' value: 'includesKey: aKey
	^ dict includesKey: (self wrap: aKey)'.
cm value: htab value: 'accessing' value: 'removeKey: aKey
	dict removeKey: (self wrap: aKey) ifAbsent: [nil]'.
cm value: htab value: 'accessing' value: 'removeAll
	dict := OrderedDictionary new'.
cm value: htab value: 'accessing' value: 'size
	^ dict size'.
cm value: htab value: 'accessing' value: 'keys
	"in insertion order"
	^ dict keys asArray collect: [:w | w key]'.
cm value: htab value: 'accessing' value: 'values
	^ dict values asArray'.
cm value: htab value: 'accessing' value: 'pairs
	^ dict associations asArray collect: [:a | a key key -> a value]'.
cm value: htab value: 'copying' value: 'copyTable
	| t |
	t := LispHashTable test: test.
	self pairs do: [:a | t at: a key put: a value].
	^ t'.
cm value: htab value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<hash-table ''; print: dict size; nextPut: $>'.
cm value: hkey class value: 'instance creation' value: 'key: aKey test: aSymbol
	^ self new setKey: aKey test: aSymbol'.
cm value: hkey value: 'private' value: 'setKey: aKey test: aSymbol
	key := aKey.
	test := aSymbol'.
cm value: hkey value: 'accessing' value: 'key
	^ key'.
cm value: hkey value: 'comparing' value: '= other
	^ other class == LispHashKey and: [LispHashTable same: key as: other key test: test]'.
cm value: hkey value: 'comparing' value: 'hash
	^ LispHashTable hashOf: key test: test'.

"=== multiple values (Phase 9 step 9.2) ======================================"
cm value: vals class value: 'instance creation' value: 'withAll: anArray
	^ self new setValues: anArray'.
cm value: vals value: 'private' value: 'setValues: anArray
	values := anArray'.
cm value: vals value: 'accessing' value: 'values
	^ values'.
cm value: vals value: 'printing' value: 'printOn: aStream
	"what the REPL shows: each value as write shows it, separated by spaces"
	values do: [:v | aStream nextPutAll: (LispPrinter writeString: v)] separatedBy: [aStream space]'.

"=== string ports (section 8) ==============================================="
cm value: iport class value: 'instance creation' value: 'on: aString
	^ self new setStream: (ReadStream on: aString)'.
cm value: iport value: 'private' value: 'setStream: aStream
	stream := aStream'.
cm value: iport value: 'accessing' value: 'stream
	^ stream'.
cm value: iport value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<input-port>'''.
cm value: oport class value: 'instance creation' value: 'on: aStream
	^ self new setStream: aStream'.
cm value: oport value: 'accessing' value: 'stream
	^ stream'.
cm value: oport value: 'closing' value: 'close
	(stream respondsTo: #close) ifTrue: [stream close]'.
cm value: iport class value: 'instance creation' value: 'onStream: aStream
	^ self new setStream: aStream'.
cm value: iport value: 'closing' value: 'close
	^ self'.
cm value: lines class value: 'instance creation' value: 'on: aLineSource
	"aLineSource answers atEnd and nextLine (LispStdin, a ReadStream)."
	^ self new setSource: aLineSource'.
cm value: lines value: 'private' value: 'setSource: aLineSource
	source := aLineSource.
	text := ''''.
	pos := 0'.
cm value: lines value: 'reading' value: 'atEnd
	"Waits for another line when the text read so far is used up."
	[pos < text size] whileFalse: [
		source atEnd ifTrue: [^ true].
		pos > 4096 ifTrue: [text := text copyFrom: pos + 1 to: text size. pos := 0].
		text := text , source nextLine , (String with: Character lf)].
	^ false'.
cm value: lines value: 'reading' value: 'next
	self atEnd ifTrue: [^ nil].
	pos := pos + 1.
	^ text at: pos'.
cm value: lines value: 'reading' value: 'peek
	self atEnd ifTrue: [^ nil].
	^ text at: pos + 1'.
cm value: lines value: 'positioning' value: 'position
	^ pos'.
cm value: lines value: 'positioning' value: 'position: n
	pos := n'.
cm value: lines value: 'reading' value: 'readDatum
	"The next datum, read by the LISP reader from the text read so far, which reads
	 another line while the datum is incomplete; the eof object at the end of input
	 (Phase 9 step 9.1: read on standard input, once the Smalltalk reader, which
	 pulled characters one at a time, retired)."
	| entries r d more |
	entries := LispCompiler entries.
	[true] whileTrue: [
		self atEnd ifTrue: [^ LispReader eofObject].
		r := (entries at: #makeReader) value: text.
		(entries at: #setPosition) value: r value: pos.
		more := false.
		d := [(entries at: #next) value: r]
			on: LispReadError
			do: [:e |
				(e isIncomplete and: [source atEnd not]) ifFalse: [e pass].
				more := true.
				nil].
		more
			ifTrue: [text := text , source nextLine , (String with: Character lf)]
			ifFalse: [
				d == LispReader eofObject
					ifTrue: [pos := text size]
					ifFalse: [pos := (entries at: #position) value: r. ^ d]]]'.
cm value: lines value: 'reading' value: 'upTo: aCharacter
	| out |
	out := WriteStream on: String new.
	[self atEnd or: [self peek = aCharacter]] whileFalse: [out nextPut: self next].
	self atEnd ifFalse: [self next].
	^ out contents'.
cm value: oport class value: 'instance creation' value: 'open
	^ self new setStream: (WriteStream on: String new)'.
cm value: oport value: 'private' value: 'setStream: aStream
	stream := aStream'.
cm value: oport value: 'writing' value: 'nextPutAll: aString
	stream nextPutAll: aString'.
cm value: oport value: 'writing' value: 'nextPut: aCharacter
	stream nextPut: aCharacter'.
cm value: oport value: 'writing' value: 'flush
	stream flush'.
cm value: oport value: 'accessing' value: 'contents
	^ stream contents'.
cm value: oport value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''#<output-port>'''.

"=== argument checks shared by the Phase 7.8 primitives (section 9) ========="
cm value: prims class value: 'documentation' value: 'document: anEnv category: aCategory with: triples
	"Each primitive in triples (name, call form, description) gets its documentation
	 and category. A name that is not bound is an error, so a table cannot document a
	 primitive that is not there (Phase 10 step 10.1)."
	1 to: triples size by: 3 do: [:i | | v |
		v := anEnv lookup: (LispSymbol named: (triples at: i)).
		v documentation: (triples at: i + 1) , (String with: Character lf) , (triples at: i + 2).
		v category: aCategory]'.
cm value: prims class value: 'checks' value: 'fail: who with: aString
	^ (LispError new) signal: who , '': '' , aString'.
cm value: prims class value: 'checks' value: 'show: x
	^ LispPrinter writeString: x limitedTo: 60'.
cm value: prims class value: 'checks' value: 'string: x for: who
	(LispCore isString: x) ifFalse: [self fail: who with: ''not a string: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'char: x for: who
	(x isKindOf: Character) ifFalse: [self fail: who with: ''not a character: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'vector: x for: who
	(x isKindOf: Array) ifFalse: [self fail: who with: ''not a vector: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'table: x for: who
	(x isKindOf: LispHashTable) ifFalse: [self fail: who with: ''not a hash table: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'inPort: x for: who
	(x isKindOf: LispInputPort) ifFalse: [self fail: who with: ''not an input port: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'outPort: x for: who
	(x isKindOf: LispOutputPort) ifFalse: [self fail: who with: ''not an output port: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'count: x for: who
	((x isKindOf: Integer) and: [x >= 0]) ifFalse: [self fail: who with: ''not a non-negative integer: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'index: i size: n for: who what: what
	"The 1-based Smalltalk index for the 0-based LISP index i."
	((i isKindOf: Integer) and: [i between: 0 and: n - 1]) ifFalse: [
		self fail: who with: ''index '' , (self show: i) , '' out of range for a '' , what , '' of length '' , n printString].
	^ i + 1'.
cm value: prims class value: 'checks' value: 'range: optional size: n for: who
	"optional: 0, 1 or 2 LISP arguments start [end]. Answer { first. last } as
	 1-based Smalltalk indexes (last may be first - 1: empty)."
	| s e |
	s := optional size >= 1 ifTrue: [optional first] ifFalse: [0].
	e := optional size >= 2 ifTrue: [optional second] ifFalse: [n].
	((s isKindOf: Integer) and: [(e isKindOf: Integer) and: [0 <= s and: [s <= e and: [e <= n]]]])
		ifFalse: [self fail: who with: ''bad range '' , (self show: s) , '' to '' , (self show: e) , '' for length '' , n printString].
	^ { s + 1. e }'.
cm value: prims class value: 'checks' value: 'mutable: x for: who what: what
	x isReadOnlyObject ifTrue: [self fail: who with: what , '' is immutable (a literal); copy it first''].
	^ x'.
cm value: prims class value: 'checks' value: 'chain: values with: aBlock
	"true when aBlock holds for every adjacent pair"
	1 to: values size - 1 do: [:i | (aBlock value: (values at: i) value: (values at: i + 1)) ifFalse: [^ false]].
	^ true'.
cm value: prims class value: 'checks' value: 'stringFrom: characters
	"A new mutable string; becomes a WideString as needed (lambda, etc.)."
	^ String streamContents: [:s | characters do: [:c | s nextPut: c]]'.
cm value: prims class value: 'checks' value: 'compare: a with: b
	"-1, 0 or 1, by character codes."
	1 to: (a size min: b size) do: [:i | | x y |
		x := (a at: i) asInteger. y := (b at: i) asInteger.
		x < y ifTrue: [^ -1].
		x > y ifTrue: [^ 1]].
	^ (a size - b size) sign'.
cm value: prims class value: 'checks' value: 'numberFrom: s radix: radix
	"string->number: what the reader reads as a number, or #f (the reader''s own
	 parser, Phase 9 step 9.2)."
	^ (LispCompiler entries at: #parseNumber) value: s value: radix'.
cm value: prims class value: 'checks' value: 'radix: rest for: who
	"The optional radix of string->number and number->string: 2, 8, 10 or 16."
	| radix |
	radix := rest lispElements ifEmpty: [10] ifNotEmpty: [:r | r first].
	(#(2 8 10 16) includes: radix) ifFalse: [self fail: who with: ''the radix must be 2, 8, 10 or 16: '' , (self show: radix)].
	^ radix'.
cm value: prims class value: 'checks' value: 'number: x for: who
	"x, if it is a number; else an error naming who."
	x isNumber ifFalse: [self fail: who with: ''not a number: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'real: x for: who
	((x isNumber) and: [x lispIsReal]) ifFalse: [self fail: who with: ''not a real number: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'checks' value: 'integer: x for: who
	((x isNumber) and: [x lispIsInteger]) ifFalse: [self fail: who with: ''not an integer: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'arithmetic' value: 'divide: a by: b
	"a / b. An exact zero divisor of an exact dividend is an error; with a float
	 either side the answer is IEEE''s: +inf.0, -inf.0 or +nan.0 (Phase 9 step 9.2)."
	b = 0 ifFalse: [^ a / b].
	((a isKindOf: Float) or: [b isKindOf: Float]) ifFalse: [^ a / b].
	(a isNumber and: [a lispIsReal]) ifFalse: [^ a / b].
	(a = 0 or: [a lispIsNaN]) ifTrue: [^ Float nan].
	^ ((a > 0) = ((b isKindOf: Float) and: [b signBit = 1]))
		ifTrue: [Float infinity negated]
		ifFalse: [Float infinity]'.
cm value: prims class value: 'checks' value: 'equalityTests
	"The eq?, eqv? and equal? primitives ever installed, with the test each makes.
	 A table knows its test by the procedure itself, not by what the names are
	 bound to now: code sealed with an earlier eq? (the compiler, Phase 8 step 8.5)
	 still makes eq? tables, and a procedure that merely took the name does not."
	^ EqualityTests ifNil: [EqualityTests := WeakIdentityKeyDictionary new]'.
cm value: prims class value: 'checks' value: 'equalityTest: p in: anEnv
	p isNil ifTrue: [^ #equal].
	^ self equalityTests at: p ifAbsent: [
		self fail: ''make-hash-table'' with: ''the equality must be eq?, eqv? or equal?: '' , (self show: p)]'.

"=== characters (section 4) ================================================="
cm value: prims class value: 'installing' value: 'installCharactersInto: anEnv
	| def ch cmp unspec |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	ch := [:x :who | self char: x for: who].
	def value: ''char->integer'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char->integer'') asInteger] arity: 1).
	def value: ''integer->char'' value: (LispProcedure fixed: [:n |
		((n isKindOf: Integer) and: [n between: 0 and: 16r10FFFF])
			ifTrue: [Character value: n]
			ifFalse: [self fail: ''integer->char'' with: ''not a character code: '' , (self show: n)]] arity: 1).
	cmp := [:name :key :test | def value: name value: (LispProcedure variadic: [:first :rest | | all |
		all := ({ first } , rest lispElements asArray) collect: [:c | key value: (ch value: c value: name)].
		self chain: all with: test] required: 1)].
	cmp value: ''char=?'' value: [:c | c asInteger] value: [:a :b | a = b].
	cmp value: ''char<?'' value: [:c | c asInteger] value: [:a :b | a < b].
	cmp value: ''char>?'' value: [:c | c asInteger] value: [:a :b | a > b].
	cmp value: ''char<=?'' value: [:c | c asInteger] value: [:a :b | a <= b].
	cmp value: ''char>=?'' value: [:c | c asInteger] value: [:a :b | a >= b].
	cmp value: ''char-ci=?'' value: [:c | c asLowercase asInteger] value: [:a :b | a = b].
	def value: ''char-alphabetic?'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char-alphabetic?'') isLetter] arity: 1).
	def value: ''char-numeric?'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char-numeric?'') isDigit] arity: 1).
	def value: ''char-whitespace?'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char-whitespace?'') isSeparator] arity: 1).
	def value: ''char-upper-case?'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char-upper-case?'') isUppercase] arity: 1).
	def value: ''char-lower-case?'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char-lower-case?'') isLowercase] arity: 1).
	def value: ''char-upcase'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char-upcase'') asUppercase] arity: 1).
	def value: ''char-downcase'' value: (LispProcedure fixed: [:c | (ch value: c value: ''char-downcase'') asLowercase] arity: 1).
	def value: ''digit-value'' value: (LispProcedure fixed: [:c |
		(ch value: c value: ''digit-value'') isDigit ifTrue: [c digitValue] ifFalse: [false]] arity: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Characters'' with: #(
		''char->integer'' ''(char->integer char)''
			''The Unicode code point of char.''
		''integer->char'' ''(integer->char n)''
			''The character with the Unicode code point n.''
		''char=?'' ''(char=? c1 c2 ...)''
			''True if the characters are all the same.''
		''char<?'' ''(char<? c1 c2 ...)''
			''True if the code points are strictly increasing.''
		''char>?'' ''(char>? c1 c2 ...)''
			''True if the code points are strictly decreasing.''
		''char<=?'' ''(char<=? c1 c2 ...)''
			''True if the code points never decrease.''
		''char>=?'' ''(char>=? c1 c2 ...)''
			''True if the code points never increase.''
		''char-ci=?'' ''(char-ci=? c1 c2 ...)''
			''True if the characters are the same, ignoring case.''
		''char-alphabetic?'' ''(char-alphabetic? char)''
			''True if char is a letter.''
		''char-numeric?'' ''(char-numeric? char)''
			''True if char is a digit.''
		''char-whitespace?'' ''(char-whitespace? char)''
			''True if char is white space.''
		''char-upper-case?'' ''(char-upper-case? char)''
			''True if char is an upper-case letter.''
		''char-lower-case?'' ''(char-lower-case? char)''
			''True if char is a lower-case letter.''
		''char-upcase'' ''(char-upcase char)''
			''The upper-case form of char.''
		''char-downcase'' ''(char-downcase char)''
			''The lower-case form of char.''
		''digit-value'' ''(digit-value char)''
			''The value of the digit char, or #f if it is not a digit.'')'.

"=== strings and symbols (section 5) ========================================"
cm value: prims class value: 'installing' value: 'installStringsInto: anEnv
	| def str opt cmp unspec |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	str := [:x :who | self string: x for: who].
	opt := [:rest | rest lispElements asArray].
	unspec := LispUnspecified default.
	def value: ''make-string'' value: (LispProcedure variadic: [:k :rest | | c |
		self count: k for: ''make-string''.
		c := (opt value: rest) ifEmpty: [Character space] ifNotEmpty: [:r | self char: r first for: ''make-string''].
		self stringFrom: (Array new: k withAll: c)] required: 1).
	def value: ''string'' value: (LispProcedure variadic: [:chars |
		self stringFrom: ((opt value: chars) collect: [:c | self char: c for: ''string''])] required: 0).
	def value: ''string-length'' value: (LispProcedure fixed: [:s | (str value: s value: ''string-length'') size] arity: 1).
	def value: ''string-ref'' value: (LispProcedure fixed: [:s :i |
		(str value: s value: ''string-ref'') at: (self index: i size: s size for: ''string-ref'' what: ''string'')] arity: 2).
	def value: ''substring'' value: (LispProcedure variadic: [:s :rest | | r |
		r := self range: (opt value: rest) size: (str value: s value: ''substring'') size for: ''substring''.
		s copyFrom: r first to: r second] required: 1).
	def value: ''string-copy'' value: (LispProcedure variadic: [:s :rest | | r |
		r := self range: (opt value: rest) size: (str value: s value: ''string-copy'') size for: ''string-copy''.
		s copyFrom: r first to: r second] required: 1).
	def value: ''string-append'' value: (LispProcedure variadic: [:ss |
		String streamContents: [:o | (opt value: ss) do: [:s | o nextPutAll: (str value: s value: ''string-append'')]]] required: 0).
	def value: ''string->list'' value: (LispProcedure variadic: [:s :rest | | r |
		r := self range: (opt value: rest) size: (str value: s value: ''string->list'') size for: ''string->list''.
		LispCons fromArray: (s copyFrom: r first to: r second) asArray] required: 1).
	def value: ''list->string'' value: (LispProcedure fixed: [:l |
		self stringFrom: ((LispCons elementsOf: l for: ''list->string'') collect: [:c | self char: c for: ''list->string''])] arity: 1).
	def value: ''string->symbol'' value: (LispProcedure fixed: [:s | LispSymbol named: (str value: s value: ''string->symbol'') copy] arity: 1).
	def value: ''symbol->string'' value: (LispProcedure fixed: [:y |
		(y isKindOf: LispSymbol) ifTrue: [y name copy] ifFalse: [self fail: ''symbol->string'' with: ''not a symbol: '' , (self show: y)]] arity: 1).
	def value: ''string->number'' value: (LispProcedure variadic: [:s :rest |
		self numberFrom: (str value: s value: ''string->number'') radix: (self radix: rest for: ''string->number'')] required: 1).
	def value: ''number->string'' value: (LispProcedure variadic: [:z :rest | | radix |
		z isNumber ifFalse: [self fail: ''number->string'' with: ''not a number: '' , (self show: z)].
		radix := self radix: rest for: ''number->string''.
		String streamContents: [:o | z lispWriteOn: o base: radix]] required: 1).
	cmp := [:name :key :test | def value: name value: (LispProcedure variadic: [:first :rest | | all |
		all := ({ first } , rest lispElements asArray) collect: [:s | key value: (str value: s value: name)].
		self chain: all with: [:a :b | test value: (self compare: a with: b)]] required: 1)].
	cmp value: ''string=?'' value: [:s | s] value: [:c | c = 0].
	cmp value: ''string<?'' value: [:s | s] value: [:c | c < 0].
	cmp value: ''string>?'' value: [:s | s] value: [:c | c > 0].
	cmp value: ''string<=?'' value: [:s | s] value: [:c | c <= 0].
	cmp value: ''string>=?'' value: [:s | s] value: [:c | c >= 0].
	cmp value: ''string-ci=?'' value: [:s | s asLowercase] value: [:c | c = 0].
	def value: ''string-set!!'' value: (LispProcedure fixed: [:s :i :c | | k |
		k := self index: i size: (str value: s value: ''string-set!!'') size for: ''string-set!!'' what: ''string''.
		self mutable: s for: ''string-set!!'' what: ''string''.
		s at: k put: (self char: c for: ''string-set!!'').
		unspec] arity: 3).
	def value: ''string-fill!!'' value: (LispProcedure fixed: [:s :c |
		self mutable: (str value: s value: ''string-fill!!'') for: ''string-fill!!'' what: ''string''.
		s atAllPut: (self char: c for: ''string-fill!!'').
		unspec] arity: 2).
	def value: ''string-copy!!'' value: (LispProcedure variadic: [:to :at :from :rest | | r n |
		self mutable: (str value: to value: ''string-copy!!'') for: ''string-copy!!'' what: ''string''.
		r := self range: (opt value: rest) size: (str value: from value: ''string-copy!!'') size for: ''string-copy!!''.
		n := r second - r first + 1.
		((at isKindOf: Integer) and: [at >= 0 and: [at + n <= to size]])
			ifFalse: [self fail: ''string-copy!!'' with: ''does not fit at '' , (self show: at)].
		to replaceFrom: at + 1 to: at + n with: from startingAt: r first.
		unspec] required: 3).
	def value: ''string-upcase'' value: (LispProcedure fixed: [:s | (str value: s value: ''string-upcase'') asUppercase] arity: 1).
	def value: ''string-downcase'' value: (LispProcedure fixed: [:s | (str value: s value: ''string-downcase'') asLowercase] arity: 1).
	def value: ''string-index'' value: (LispProcedure fixed: [:s :c | | i |
		i := (str value: s value: ''string-index'') indexOf: (self char: c for: ''string-index'').
		i = 0 ifTrue: [false] ifFalse: [i - 1]] arity: 2).
	def value: ''string-search'' value: (LispProcedure fixed: [:s :p | | i |
		i := (str value: s value: ''string-search'') findString: (str value: p value: ''string-search'') startingAt: 1.
		i = 0 ifTrue: [false] ifFalse: [i - 1]] arity: 2).
	def value: ''string-split'' value: (LispProcedure fixed: [:s :c | | parts cur |
		self char: c for: ''string-split''.
		parts := OrderedCollection new.
		cur := WriteStream on: String new.
		(str value: s value: ''string-split'') do: [:x |
			x = c ifTrue: [parts add: cur contents. cur := WriteStream on: String new] ifFalse: [cur nextPut: x]].
		parts add: cur contents.
		LispCons fromArray: parts asArray] arity: 2).
	def value: ''string-join'' value: (LispProcedure variadic: [:l :rest | | sep |
		sep := (opt value: rest) ifEmpty: ['' ''] ifNotEmpty: [:r | str value: r first value: ''string-join''].
		String streamContents: [:o |
			(LispCons elementsOf: l for: ''string-join'')
				do: [:x | o nextPutAll: (str value: x value: ''string-join'')]
				separatedBy: [o nextPutAll: sep]]] required: 1).
	def value: ''string-trim'' value: (LispProcedure fixed: [:s | (str value: s value: ''string-trim'') trimBoth copy] arity: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Strings'' with: #(
		''string'' ''(string char ...)''
			''A new string of the characters.''
		''make-string'' ''(make-string k [char])''
			''A new string of k characters, each char (a space by default).''
		''string-length'' ''(string-length string)''
			''The number of characters of string.''
		''string-ref'' ''(string-ref string k)''
			''The character of string at index k, from 0.''
		''string-set!!'' ''(string-set!! string k char)''
			''Replaces the character of string at index k with char.''
		''substring'' ''(substring string start [end])''
			''A new string of the characters of string from start to end.''
		''string-copy'' ''(string-copy string [start [end]])''
			''A new string of the characters of string from start to end.''
		''string-copy!!'' ''(string-copy!! to at from [start [end]])''
			''Copies the characters of from, start to end, into to at index at.''
		''string-fill!!'' ''(string-fill!! string char)''
			''Replaces every character of string with char.''
		''string-append'' ''(string-append string ...)''
			''A new string of the characters of each string in turn.''
		''string->list'' ''(string->list string [start [end]])''
			''A list of the characters of string.''
		''list->string'' ''(list->string list)''
			''A new string of the characters of list.''
		''string->symbol'' ''(string->symbol string)''
			''The symbol spelled string.''
		''symbol->string'' ''(symbol->string symbol)''
			''A new string of the name of symbol.''
		''string->number'' ''(string->number string [radix])''
			''The number string reads as, or #f; radix is 2, 8, 10 or 16.''
		''number->string'' ''(number->string z [radix])''
			''The text of the number z, as write writes it, in radix.''
		''string=?'' ''(string=? s1 s2 ...)''
			''True if the strings are all the same.''
		''string<?'' ''(string<? s1 s2 ...)''
			''True if the strings are strictly increasing, by code point.''
		''string>?'' ''(string>? s1 s2 ...)''
			''True if the strings are strictly decreasing, by code point.''
		''string<=?'' ''(string<=? s1 s2 ...)''
			''True if the strings never decrease, by code point.''
		''string>=?'' ''(string>=? s1 s2 ...)''
			''True if the strings never increase, by code point.''
		''string-ci=?'' ''(string-ci=? s1 s2 ...)''
			''True if the strings are the same, ignoring case.''
		''string-upcase'' ''(string-upcase string)''
			''A new string of string in upper case.''
		''string-downcase'' ''(string-downcase string)''
			''A new string of string in lower case.''
		''string-index'' ''(string-index string char)''
			''The index of the first char in string, or #f.''
		''string-search'' ''(string-search string pattern)''
			''The index where pattern first occurs in string, or #f.''
		''string-split'' ''(string-split string char)''
			''A list of the parts of string between the occurrences of char.''
		''string-join'' ''(string-join list [separator])''
			''A new string of the strings of list, with separator between them.''
		''string-trim'' ''(string-trim string)''
			''A new string of string without the white space at either end.'')'.

"=== vectors (section 6) ===================================================="
cm value: prims class value: 'installing' value: 'installVectorsInto: anEnv
	| def vec opt unspec |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	vec := [:x :who | self vector: x for: who].
	opt := [:rest | rest lispElements asArray].
	unspec := LispUnspecified default.
	def value: ''vector?'' value: (LispProcedure fixed: [:x | x isKindOf: Array] arity: 1).
	def value: ''make-vector'' value: (LispProcedure variadic: [:k :rest |
		Array new: (self count: k for: ''make-vector'') withAll: ((opt value: rest) ifEmpty: [false] ifNotEmpty: [:r | r first])] required: 1).
	def value: ''vector'' value: (LispProcedure variadic: [:xs | (opt value: xs) copy] required: 0).
	def value: ''vector-length'' value: (LispProcedure fixed: [:v | (vec value: v value: ''vector-length'') size] arity: 1).
	def value: ''vector-ref'' value: (LispProcedure fixed: [:v :i |
		(vec value: v value: ''vector-ref'') at: (self index: i size: v size for: ''vector-ref'' what: ''vector'')] arity: 2).
	def value: ''vector-set!!'' value: (LispProcedure fixed: [:v :i :x | | k |
		k := self index: i size: (vec value: v value: ''vector-set!!'') size for: ''vector-set!!'' what: ''vector''.
		self mutable: v for: ''vector-set!!'' what: ''vector''.
		v at: k put: x.
		unspec] arity: 3).
	def value: ''vector->list'' value: (LispProcedure variadic: [:v :rest | | r |
		r := self range: (opt value: rest) size: (vec value: v value: ''vector->list'') size for: ''vector->list''.
		LispCons fromArray: (v copyFrom: r first to: r second)] required: 1).
	def value: ''list->vector'' value: (LispProcedure fixed: [:l | (LispCons elementsOf: l for: ''list->vector'') asArray] arity: 1).
	def value: ''vector-fill!!'' value: (LispProcedure fixed: [:v :x |
		self mutable: (vec value: v value: ''vector-fill!!'') for: ''vector-fill!!'' what: ''vector''.
		v atAllPut: x.
		unspec] arity: 2).
	def value: ''vector-copy'' value: (LispProcedure variadic: [:v :rest | | r |
		r := self range: (opt value: rest) size: (vec value: v value: ''vector-copy'') size for: ''vector-copy''.
		v copyFrom: r first to: r second] required: 1).
	def value: ''subvector'' value: (LispProcedure fixed: [:v :s :e | | r |
		r := self range: { s. e } size: (vec value: v value: ''subvector'') size for: ''subvector''.
		v copyFrom: r first to: r second] arity: 3).
	def value: ''vector-append'' value: (LispProcedure variadic: [:vs |
		(opt value: vs) inject: Array new into: [:acc :v | acc , (vec value: v value: ''vector-append'')]] required: 0).
	def value: ''vector-map'' value: (LispProcedure fixed: [:p :v |
		(vec value: v value: ''vector-map'') collect: [:x | LispProcedure apply: p to: { x }]] arity: 2).
	def value: ''vector-for-each'' value: (LispProcedure fixed: [:p :v |
		(vec value: v value: ''vector-for-each'') do: [:x | LispProcedure apply: p to: { x }].
		unspec] arity: 2).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Vectors'' with: #(
		''vector'' ''(vector x ...)''
			''A new vector of the arguments.''
		''make-vector'' ''(make-vector k [fill])''
			''A new vector of k elements, each fill.''
		''vector?'' ''(vector? x)''
			''True if x is a vector.''
		''vector-length'' ''(vector-length vector)''
			''The number of elements of vector.''
		''vector-ref'' ''(vector-ref vector k)''
			''The element of vector at index k, from 0.''
		''vector-set!!'' ''(vector-set!! vector k x)''
			''Replaces the element of vector at index k with x.''
		''vector->list'' ''(vector->list vector [start [end]])''
			''A list of the elements of vector.''
		''list->vector'' ''(list->vector list)''
			''A new vector of the elements of list.''
		''vector-copy'' ''(vector-copy vector [start [end]])''
			''A new vector of the elements of vector from start to end.''
		''subvector'' ''(subvector vector start end)''
			''A new vector of the elements of vector from start to end.''
		''vector-append'' ''(vector-append vector ...)''
			''A new vector of the elements of each vector in turn.''
		''vector-fill!!'' ''(vector-fill!! vector x)''
			''Replaces every element of vector with x.''
		''vector-map'' ''(vector-map proc vector)''
			''A new vector of the results of calling proc on each element of vector.''
		''vector-for-each'' ''(vector-for-each proc vector)''
			''Calls proc on each element of vector, in order.'')'.

"=== hash tables (section 7) ================================================"
cm value: prims class value: 'installing' value: 'installHashTablesInto: anEnv
	| def tbl opt unspec missing |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	tbl := [:x :who | self table: x for: who].
	opt := [:rest | rest lispElements asArray].
	unspec := LispUnspecified default.
	missing := [:who :k :rest | (opt value: rest)
		ifEmpty: [self fail: who with: ''no key: '' , (self show: k)]
		ifNotEmpty: [:r | LispProcedure apply: r first to: #()]].
	def value: ''make-hash-table'' value: (LispProcedure variadic: [:rest |
		LispHashTable test: (self equalityTest: ((opt value: rest) ifEmpty: [nil] ifNotEmpty: [:r | r first]) in: anEnv)] required: 0).
	def value: ''hash-table?'' value: (LispProcedure fixed: [:x | x isKindOf: LispHashTable] arity: 1).
	def value: ''hash-table-set!!'' value: (LispProcedure fixed: [:t :k :v | (tbl value: t value: ''hash-table-set!!'') at: k put: v. unspec] arity: 3).
	def value: ''hash-table-ref'' value: (LispProcedure variadic: [:t :k :rest |
		(tbl value: t value: ''hash-table-ref'') at: k ifAbsent: [missing value: ''hash-table-ref'' value: k value: rest]] required: 2).
	def value: ''hash-table-ref/default'' value: (LispProcedure fixed: [:t :k :d |
		(tbl value: t value: ''hash-table-ref/default'') at: k ifAbsent: [d]] arity: 3).
	def value: ''hash-table-delete!!'' value: (LispProcedure fixed: [:t :k | (tbl value: t value: ''hash-table-delete!!'') removeKey: k. unspec] arity: 2).
	def value: ''hash-table-contains?'' value: (LispProcedure fixed: [:t :k | (tbl value: t value: ''hash-table-contains?'') includesKey: k] arity: 2).
	def value: ''hash-table-exists?'' value: (anEnv lookup: (LispSymbol named: ''hash-table-contains?'')) copy.
	def value: ''hash-table-count'' value: (LispProcedure fixed: [:t | (tbl value: t value: ''hash-table-count'') size] arity: 1).
	def value: ''hash-table-size'' value: (anEnv lookup: (LispSymbol named: ''hash-table-count'')) copy.
	def value: ''hash-table-keys'' value: (LispProcedure fixed: [:t | LispCons fromArray: (tbl value: t value: ''hash-table-keys'') keys] arity: 1).
	def value: ''hash-table-values'' value: (LispProcedure fixed: [:t | LispCons fromArray: (tbl value: t value: ''hash-table-values'') values] arity: 1).
	def value: ''hash-table->alist'' value: (LispProcedure fixed: [:t |
		LispCons fromArray: ((tbl value: t value: ''hash-table->alist'') pairs collect: [:a | LispCons car: a key cdr: a value])] arity: 1).
	def value: ''hash-table-walk'' value: (LispProcedure fixed: [:t :p |
		(tbl value: t value: ''hash-table-walk'') pairs do: [:a | LispProcedure apply: p to: { a key. a value }].
		unspec] arity: 2).
	def value: ''hash-table-update!!'' value: (LispProcedure variadic: [:t :k :p :rest | | cur |
		cur := (tbl value: t value: ''hash-table-update!!'') at: k ifAbsent: [missing value: ''hash-table-update!!'' value: k value: rest].
		t at: k put: (LispProcedure apply: p to: { cur }).
		unspec] required: 3).
	def value: ''hash-table-update!!/default'' value: (LispProcedure fixed: [:t :k :p :d |
		(tbl value: t value: ''hash-table-update!!/default'') at: k put: (LispProcedure apply: p to: { t at: k ifAbsent: [d] }).
		unspec] arity: 4).
	def value: ''hash-table-copy'' value: (LispProcedure fixed: [:t | (tbl value: t value: ''hash-table-copy'') copyTable] arity: 1).
	def value: ''hash-table-clear!!'' value: (LispProcedure fixed: [:t | (tbl value: t value: ''hash-table-clear!!'') removeAll. unspec] arity: 1).
	def value: ''alist->hash-table'' value: (LispProcedure variadic: [:al :rest | | t |
		t := LispHashTable test: (self equalityTest: ((opt value: rest) ifEmpty: [nil] ifNotEmpty: [:r | r first]) in: anEnv).
		(LispCons elementsOf: al for: ''alist->hash-table'') do: [:pair |
			(pair isKindOf: LispCons) ifFalse: [self fail: ''alist->hash-table'' with: ''not a pair: '' , (self show: pair)].
			(t includesKey: pair car) ifFalse: [t at: pair car put: pair cdr]].
		t] required: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Hash tables'' with: #(
		''make-hash-table'' ''(make-hash-table [equality])''
			''A new hash table comparing keys with equality: eq?, eqv? or equal? (the default).''
		''hash-table?'' ''(hash-table? x)''
			''True if x is a hash table.''
		''hash-table-set!!'' ''(hash-table-set!! table key value)''
			''Associates key with value in table.''
		''hash-table-ref'' ''(hash-table-ref table key [missing])''
			''The value of key in table; if there is none, the result of calling missing, or an error.''
		''hash-table-ref/default'' ''(hash-table-ref/default table key default)''
			''The value of key in table, or default.''
		''hash-table-contains?'' ''(hash-table-contains? table key)''
			''True if table has a value for key.''
		''hash-table-exists?'' ''(hash-table-exists? table key)''
			''The old name of hash-table-contains?.''
		''hash-table-delete!!'' ''(hash-table-delete!! table key)''
			''Removes key and its value from table.''
		''hash-table-update!!'' ''(hash-table-update!! table key proc [missing])''
			''Replaces the value of key with the result of calling proc on it.''
		''hash-table-update!!/default'' ''(hash-table-update!!/default table key proc default)''
			''As hash-table-update!!, with default as the value of a missing key.''
		''hash-table-count'' ''(hash-table-count table)''
			''The number of keys in table.''
		''hash-table-size'' ''(hash-table-size table)''
			''The old name of hash-table-count.''
		''hash-table-keys'' ''(hash-table-keys table)''
			''A list of the keys of table, in the order they were added.''
		''hash-table-values'' ''(hash-table-values table)''
			''A list of the values of table, in the order of their keys.''
		''hash-table->alist'' ''(hash-table->alist table)''
			''An association list of the keys and values of table.''
		''alist->hash-table'' ''(alist->hash-table alist [equality])''
			''A new hash table of the pairs of alist; the first of a repeated key wins.''
		''hash-table-walk'' ''(hash-table-walk table proc)''
			''Calls proc on each key and its value.''
		''hash-table-copy'' ''(hash-table-copy table)''
			''A new hash table with the keys and values of table.''
		''hash-table-clear!!'' ''(hash-table-clear!! table)''
			''Removes every key from table.'')'.

"=== string ports, read, and output to a port (section 8) =================="
cm value: prims class value: 'installing' value: 'installPortsInto: anEnv
	| def opt inArg outArg eof unspec |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	opt := [:rest | rest lispElements asArray].
	eof := LispReader eofObject.
	unspec := LispUnspecified default.
	inArg := [:rest :who | (opt value: rest)
		ifEmpty: [self input stream]
		ifNotEmpty: [:r | (self inPort: r first for: who) stream]].
	outArg := [:rest :who | (opt value: rest) ifEmpty: [self output] ifNotEmpty: [:r | self outPort: r first for: who]].
	def value: ''open-input-string'' value: (LispProcedure fixed: [:s | LispInputPort on: (self string: s for: ''open-input-string'')] arity: 1).
	def value: ''read-char'' value: (LispProcedure variadic: [:rest | | st |
		st := inArg value: rest value: ''read-char''.
		st atEnd ifTrue: [eof] ifFalse: [st next]] required: 0).
	def value: ''peek-char'' value: (LispProcedure variadic: [:rest | | st |
		st := inArg value: rest value: ''peek-char''.
		st atEnd ifTrue: [eof] ifFalse: [st peek]] required: 0).
	def value: ''read-line'' value: (LispProcedure variadic: [:rest | | st line |
		st := inArg value: rest value: ''read-line''.
		st atEnd
			ifTrue: [eof]
			ifFalse: [
				line := st upTo: Character lf.
				(line notEmpty and: [line last = Character cr]) ifTrue: [line := line allButLast].
				line]] required: 0).
	def value: ''read-string'' value: (LispProcedure variadic: [:k :rest | | st |
		self count: k for: ''read-string''.
		st := inArg value: rest value: ''read-string''.
		st atEnd
			ifTrue: [eof]
			ifFalse: [String streamContents: [:o | | n | n := 0. [n < k and: [st atEnd not]] whileTrue: [o nextPut: st next. n := n + 1]]]] required: 1).
	def value: ''char-ready?'' value: (LispProcedure variadic: [:rest | true] required: 0).
	def value: ''eof-object'' value: (LispProcedure fixed: [eof] arity: 0).
	def value: ''eof-object?'' value: (LispProcedure fixed: [:x | x == eof] arity: 1).
	def value: ''read'' value: (LispProcedure variadic: [:rest | LispReader readFrom: (inArg value: rest value: ''read'')] required: 0).
	def value: ''open-output-string'' value: (LispProcedure fixed: [LispOutputPort open] arity: 0).
	def value: ''get-output-string'' value: (LispProcedure fixed: [:p | (self outPort: p for: ''get-output-string'') contents] arity: 1).
	def value: ''write-char'' value: (LispProcedure variadic: [:c :rest |
		(outArg value: rest value: ''write-char'') nextPut: (self char: c for: ''write-char''); flush. unspec] required: 1).
	def value: ''write-string'' value: (LispProcedure variadic: [:s :rest |
		(outArg value: rest value: ''write-string'') nextPutAll: (self string: s for: ''write-string''); flush. unspec] required: 1).
	"display, write and newline take an optional port (R7RS)"
	def value: ''display'' value: (LispProcedure variadic: [:x :rest |
		(outArg value: rest value: ''display'') nextPutAll: (LispPrinter displayString: x); flush. unspec] required: 1).
	def value: ''write'' value: (LispProcedure variadic: [:x :rest |
		(outArg value: rest value: ''write'') nextPutAll: (LispPrinter writeString: x); flush. unspec] required: 1).
	def value: ''newline'' value: (LispProcedure variadic: [:rest |
		(outArg value: rest value: ''newline'') nextPut: Character lf; flush. unspec] required: 0).
	def value: ''with-output-to-string'' value: (LispProcedure fixed: [:thunk | | o |
		o := WriteStream on: String new.
		self withOutput: o do: [LispProcedure apply: thunk to: #()].
		o contents] arity: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Ports'' with: #(
		''open-input-string'' ''(open-input-string string)''
			''An input port that reads the characters of string.''
		''open-output-string'' ''(open-output-string)''
			''An output port that collects what is written to it.''
		''get-output-string'' ''(get-output-string port)''
			''The string of what has been written to the output string port.''
		''with-output-to-string'' ''(with-output-to-string thunk)''
			''Calls thunk with its output collected, and answers it as a string.''
		''read'' ''(read [port])''
			''The next datum from port (the current input by default), or the eof object.''
		''read-char'' ''(read-char [port])''
			''The next character from port, or the eof object.''
		''peek-char'' ''(peek-char [port])''
			''The next character from port, without reading it, or the eof object.''
		''read-line'' ''(read-line [port])''
			''The rest of the line from port, without its line break, or the eof object.''
		''read-string'' ''(read-string k [port])''
			''A string of the next k characters from port, fewer at its end, or the eof object.''
		''char-ready?'' ''(char-ready? [port])''
			''True: a character can always be read without waiting for it here.''
		''write-char'' ''(write-char char [port])''
			''Writes char to port.''
		''write-string'' ''(write-string string [port])''
			''Writes the characters of string to port.''
		''eof-object'' ''(eof-object)''
			''The eof object, which reading answers at the end of its input.''
		''eof-object?'' ''(eof-object? x)''
			''True if x is the eof object.'').
	"display, write and newline were first installed without a port (installIOInto:);
	 these are their final definitions"
	self document: anEnv category: ''Output'' with: #(
		''display'' ''(display x [port])''
			''Writes x for a person: strings and characters as they are, to port or the current output.''
		''write'' ''(write x [port])''
			''Writes x so that read reads it back: strings in quotes, characters as #\x.''
		''newline'' ''(newline [port])''
			''Writes a line break.'')'.

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
cm value: tout value: 'writing' value: 'space
	"The usual stream conveniences, so code written against a WriteStream works on
	 the real stdout and stderr too (the break loop used space; Phase 7.7)."
	self nextPut: Character space'.
cm value: tout value: 'writing' value: 'tab
	self nextPut: Character tab'.
cm value: tout value: 'writing' value: 'lf
	self nextPut: Character lf'.
cm value: tout value: 'writing' value: 'print: anObject
	self nextPutAll: anObject printString'.
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
cm value: proc value: 'documentation' value: 'documentation: aString
	"Its documentation (Phase 10 step 10.1): the call form on the first line, then
	 what it does."
	documentation := aString'.
cm value: proc value: 'documentation' value: 'category: aString
	"The section of the reference of the built-ins it belongs in."
	category := aString'.
cm value: proc value: 'documentation' value: 'lispDocumentation
	^ documentation'.
cm value: proc value: 'documentation' value: 'lispCategory
	^ category'.
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
cm value: proc value: 'block protocol' value: 'value
	"A LISP procedure answers the messages Smalltalk sends to a block, and each
	 drives its tail calls, so Smalltalk never sees a LispTailCall (Phase 7.6
	 section 5.1; review R-18)."
	^ LispProcedure apply: self to: #()'.
cm value: proc value: 'block protocol' value: 'value: a
	^ LispProcedure apply: self to: { a }'.
cm value: proc value: 'block protocol' value: 'value: a value: b
	^ LispProcedure apply: self to: { a. b }'.
cm value: proc value: 'block protocol' value: 'value: a value: b value: c
	^ LispProcedure apply: self to: { a. b. c }'.
cm value: proc value: 'block protocol' value: 'value: a value: b value: c value: d
	^ LispProcedure apply: self to: { a. b. c. d }'.
cm value: proc value: 'block protocol' value: 'valueWithArguments: anArray
	^ LispProcedure apply: self to: anArray asArray'.
cm value: proc value: 'block protocol' value: 'numArgs
	^ required'.
cm value: proc value: 'block protocol' value: 'cull: a
	^ (required = 0 and: [hasRest not]) ifTrue: [self value] ifFalse: [self value: a]'.
cm value: proc value: 'block protocol' value: 'cull: a cull: b
	required >= 2 ifTrue: [^ self value: a value: b].
	^ self cull: a'.
cm value: proc value: 'block protocol' value: 'on: exceptionClass do: handler
	"The procedure as the protected block of an exception handler."
	^ [self value] on: exceptionClass do: handler'.
cm value: proc value: 'block protocol' value: 'ensure: aBlock
	^ [self value] ensure: aBlock'.
cm value: proc value: 'block protocol' value: 'ifCurtailed: aBlock
	^ [self value] ifCurtailed: aBlock'.
cm value: proc value: 'block protocol' value: 'asBlock
	"A real BlockClosure that calls this procedure, for code that needs one (fork)."
	(hasRest not and: [required <= 4]) ifFalse: [
		^ (LispError new) signal: ''procedure->block: needs a procedure of at most 4 fixed arguments''].
	required = 0 ifTrue: [^ [self value]].
	required = 1 ifTrue: [^ [:a | self value: a]].
	required = 2 ifTrue: [^ [:a :b | self value: a value: b]].
	required = 3 ifTrue: [^ [:a :b :c | self value: a value: b value: c]].
	^ [:a :b :c :d | self value: a value: b value: c value: d]'.
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
	| args |
	hasRest ifFalse: [
		anArray size = required ifFalse: [^ self signalArity: anArray size].
		packed == true ifTrue: [^ block value: anArray].
		^ block valueWithArguments: anArray].
	anArray size >= required ifFalse: [^ self signalArity: anArray size].
	args := (anArray first: required) , { LispCons fromArray: (anArray allButFirst: required) }.
	packed == true ifTrue: [^ block value: args].
	^ block valueWithArguments: args'.
cm value: proc value: 'applying' value: 'packed
	"The block takes one Array of all the arguments: a procedure with more parameters
	 than a block may have (15; Phase 7.9 section 4.2). Answers the procedure."
	packed := true'.
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
	self installInteropInto: anEnv.
	self installConditionsInto: anEnv.
	self installCharactersInto: anEnv.
	self installStringsInto: anEnv.
	self installVectorsInto: anEnv.
	self installHashTablesInto: anEnv.
	self installPortsInto: anEnv.
	self installFilesInto: anEnv.
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
	anEnv define: (LispSymbol named: ''macroexpand-1'') value: (LispProcedure fixed: [:form | (LispCompiler entries at: #macroexpand1) value: form] arity: 1).
	anEnv define: (LispSymbol named: ''macroexpand'') value: (LispProcedure fixed: [:form | (LispCompiler entries at: #macroexpand) value: form] arity: 1).
	anEnv define: (LispSymbol named: ''eval'') value: (LispProcedure fixed: [:form | LispCompiler new eval: form] arity: 1).
	"how this image was built: its seed, and the bootstrap (Phase 9 step 9.1)"
	anEnv define: (LispSymbol named: ''image-build-info'') value: (LispProcedure fixed: [
		LispCompiler buildInfoList] arity: 0).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Evaluation and macros'' with: #(
		''eval'' ''(eval form)''
			''Compiles and runs form at top level, and answers its value.''
		''gensym'' ''(gensym [prefix])''
			''A new uninterned symbol, unlike any other, for a name a macro makes up.''
		''macroexpand-1'' ''(macroexpand-1 form)''
			''form expanded once, if it is a macro call; else form itself.''
		''macroexpand'' ''(macroexpand form)''
			''form expanded until it is no longer a macro call.''
		''image-build-info'' ''(image-build-info)''
			''How this image was built: an association list of its seed, the bootstrap and its fixpoint.'')'.
cm value: prims class value: 'installing' value: 'installConditionsInto: anEnv
	"Phase 7.7: conditions are Pharo exceptions. Handlers catch Error (which includes
	 LispRaise), never Notifications, Warnings or restart transfers. A handler gets
	 the raised value for raise, and the exception itself otherwise."
	| def payload noMatch fileException |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	payload := [:ex | (ex isKindOf: LispRaise) ifTrue: [ex payload] ifFalse: [ex]].
	noMatch := Object new.
	fileException := Smalltalk at: #FileException ifAbsent: [nil].
	"signalling (section 4.1)"
	def value: ''error'' value: (LispProcedure variadic: [:msg :rest |
		(LispError new)
			irritants: rest;
			signal: ((LispCore isString: msg) ifTrue: [msg] ifFalse: [LispPrinter displayString: msg])] required: 1).
	def value: ''raise'' value: (LispProcedure fixed: [:obj |
		(obj isKindOf: Exception)
			ifTrue: [obj signal]
			ifFalse: [(LispRaise new) payload: obj; continuable: false; signal]] arity: 1).
	def value: ''raise-continuable'' value: (LispProcedure fixed: [:obj |
		(LispRaise new) payload: obj; continuable: true; signal] arity: 1).
	"handling (section 4.2)"
	def value: ''with-exception-handler'' value: (LispProcedure fixed: [:handler :thunk |
		[thunk value] on: Error do: [:ex | | v |
			v := handler value: (payload value: ex).
			((ex isKindOf: LispRaise) and: [ex continuable])
				ifTrue: [ex resume: v]
				ifFalse: [(LispError new) signal: ''handler returned from a non-continuable raise'']]] arity: 2).
	def value: ''%handler-bind'' value: (LispProcedure fixed: [:handler :thunk |
		"Common Lisp handler-bind: a handler that returns declines, and the search goes on"
		[thunk value] on: Error do: [:ex | handler value: (payload value: ex). ex pass]] arity: 2).
	def value: ''%guard'' value: (LispProcedure fixed: [:thunk :handler | | caught result |
		"guard, as R7RS: unwind to the guard first (so dynamic-wind afters have run), then
		 the clauses; with none matching, the condition is raised again from here"
		caught := nil.
		result := [thunk value] on: Error do: [:ex | caught := ex. ex return: nil].
		caught isNil
			ifTrue: [result]
			ifFalse: [ | v |
				v := handler value: (payload value: caught).
				v == noMatch ifTrue: [caught signal] ifFalse: [v]]] arity: 2).
	def value: ''%guard-no-match'' value: (LispProcedure fixed: [noMatch] arity: 0).
	"cleanup (section 4.4)"
	def value: ''dynamic-wind'' value: (LispProcedure fixed: [:before :thunk :after |
		before value.
		[thunk value] ensure: [after value]] arity: 3).
	"inspecting (section 4.3)"
	def value: ''condition?'' value: (LispProcedure fixed: [:x | x isKindOf: Exception] arity: 1).
	def value: ''error-object?'' value: (LispProcedure fixed: [:x | (x isKindOf: Error) and: [(x isKindOf: LispRaise) not]] arity: 1).
	def value: ''error-object-message'' value: (LispProcedure fixed: [:c |
		(c isKindOf: LispError) ifTrue: [c messageText ifNil: ['''']] ifFalse: [LispError describe: c]] arity: 1).
	def value: ''error-object-irritants'' value: (LispProcedure fixed: [:c |
		((c isKindOf: LispError) and: [c irritants notNil]) ifTrue: [c irritants] ifFalse: [LispEmptyList default]] arity: 1).
	def value: ''condition-report'' value: (LispProcedure fixed: [:c | LispError describe: c] arity: 1).
	def value: ''read-error?'' value: (LispProcedure fixed: [:c |
		(c isKindOf: LispReadError) or: [(c isKindOf: LispLocatedError) and: [c cause isKindOf: LispReadError]]] arity: 1).
	def value: ''file-error?'' value: (LispProcedure fixed: [:c |
		(c isKindOf: LispFileError) or: [fileException notNil and: [c isKindOf: fileException]]] arity: 1).
	"restarts (section 5)"
	def value: ''%restart-case'' value: (LispProcedure fixed: [:thunk :specs |
		LispRestart
			withRestarts: (specs lispElements collect: [:pair | LispRestart name: pair car action: pair cdr]) asArray
			do: [thunk value]] arity: 2).
	def value: ''invoke-restart'' value: (LispProcedure variadic: [:r :args | LispRestart invoke: r with: args lispElements asArray] required: 1).
	def value: ''find-restart'' value: (LispProcedure fixed: [:n | (LispRestart find: n) ifNil: [false]] arity: 1).
	def value: ''compute-restarts'' value: (LispProcedure fixed: [LispCons fromArray: LispRestart active] arity: 0).
	def value: ''restart-name'' value: (LispProcedure fixed: [:r | r name] arity: 1).
	def value: ''use-value'' value: (LispProcedure fixed: [:v | LispRestart invoke: ''use-value'' with: { v }] arity: 1).
	def value: ''store-value'' value: (LispProcedure fixed: [:v | LispRestart invoke: ''store-value'' with: { v }] arity: 1).
	def value: ''abort'' value: (LispProcedure fixed: [LispRestart invoke: ''abort'' with: #()] arity: 0).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Conditions and restarts'' with: #(
		''error'' ''(error message irritant ...)''
			''Signals an error with message, and the irritants for its report.''
		''raise'' ''(raise obj)''
			''Raises obj to the current handlers; a handler that returns is an error.''
		''raise-continuable'' ''(raise-continuable obj)''
			''Raises obj; the value the handler returns is the value of raise-continuable.''
		''with-exception-handler'' ''(with-exception-handler handler thunk)''
			''Calls thunk with handler handling what it raises.''
		''dynamic-wind'' ''(dynamic-wind before thunk after)''
			''Calls before, thunk and after, and calls after however thunk is left.''
		''condition?'' ''(condition? x)''
			''True if x is a condition: anything raised or signalled.''
		''error-object?'' ''(error-object? x)''
			''True if x is an error, as error and the system signal them.''
		''error-object-message'' ''(error-object-message e)''
			''The message of the error e.''
		''error-object-irritants'' ''(error-object-irritants e)''
			''The irritants of the error e, as a list.''
		''condition-report'' ''(condition-report c)''
			''The text that describes the condition c, as the runner shows it.''
		''read-error?'' ''(read-error? x)''
			''True if x is an error from reading.''
		''file-error?'' ''(file-error? x)''
			''True if x is an error from opening a file.''
		''invoke-restart'' ''(invoke-restart restart arg ...)''
			''Transfers to the active restart (or the one with that name), with the arguments.''
		''find-restart'' ''(find-restart name)''
			''The innermost active restart named name, or #f.''
		''compute-restarts'' ''(compute-restarts)''
			''A list of the active restarts, innermost first.''
		''restart-name'' ''(restart-name restart)''
			''The name of restart, a symbol.''
		''use-value'' ''(use-value x)''
			''Invokes the use-value restart with x.''
		''store-value'' ''(store-value x)''
			''Invokes the store-value restart with x.''
		''abort'' ''(abort)''
			''Invokes the abort restart.'')'.
cm value: prims class value: 'installing' value: 'installInteropInto: anEnv
	"Phase 7.6 sections 4.3 to 4.5: dynamic sends and lookups, and the values that
	 differ between the languages. Names arrive as LISP symbols or strings."
	| def nameOf |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	nameOf := [:x | (x isKindOf: LispSymbol) ifTrue: [x name] ifFalse: [x asString]].
	def value: ''smalltalk-global'' value: (LispProcedure fixed: [:name |
		Smalltalk globals at: (nameOf value: name) asSymbol ifAbsent: [false]] arity: 1).
	def value: ''smalltalk-selector'' value: (LispProcedure fixed: [:name | (nameOf value: name) asSymbol] arity: 1).
	def value: ''smalltalk-send'' value: (LispProcedure variadic: [:recv :sel :rest |
		recv perform: (nameOf value: sel) asSymbol withArguments: rest lispElements asArray] required: 2).
	def value: ''smalltalk-nil'' value: (LispProcedure fixed: [nil] arity: 0).
	def value: ''smalltalk-nil?'' value: (LispProcedure fixed: [:x | x isNil] arity: 1).
	def value: ''smalltalk-symbol'' value: (LispProcedure fixed: [:x | (nameOf value: x) asSymbol] arity: 1).
	def value: ''lisp-symbol'' value: (LispProcedure fixed: [:x | LispSymbol named: x asString] arity: 1).
	def value: ''list->array'' value: (LispProcedure fixed: [:l | (LispCons elementsOf: l for: ''list->array'') asArray] arity: 1).
	def value: ''array->list'' value: (LispProcedure fixed: [:a | LispCons fromArray: a asArray] arity: 1).
	def value: ''procedure->block'' value: (LispProcedure fixed: [:p | p asBlock] arity: 1).
	def value: ''smalltalk-object?'' value: (LispProcedure fixed: [:x |
		(x class package name beginsWith: ''CogLisp'') not
			and: [(x isKindOf: Boolean) not and: [x isNumber not
			and: [(x isKindOf: Character) not and: [(LispCore isString: x) not and: [(x isKindOf: Array) not]]]]]] arity: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Smalltalk interop'' with: #(
		''smalltalk-global'' ''(smalltalk-global name)''
			''The Smalltalk global named name (a symbol or a string), or #f.''
		''smalltalk-selector'' ''(smalltalk-selector name)''
			''The Smalltalk selector spelled name.''
		''smalltalk-send'' ''(smalltalk-send receiver selector arg ...)''
			''Sends the message selector to receiver with the arguments, chosen at run time.''
		''smalltalk-symbol'' ''(smalltalk-symbol name)''
			''The Smalltalk symbol spelled name.''
		''lisp-symbol'' ''(lisp-symbol x)''
			''The LISP symbol spelled as x, a Smalltalk symbol or string.''
		''smalltalk-nil'' ''(smalltalk-nil)''
			''Smalltalk nil, which is not a LISP value.''
		''smalltalk-nil?'' ''(smalltalk-nil? x)''
			''True if x is Smalltalk nil.''
		''smalltalk-object?'' ''(smalltalk-object? x)''
			''True if x is a Smalltalk object that is not also a LISP value.''
		''list->array'' ''(list->array list)''
			''A Smalltalk Array of the elements of list.''
		''array->list'' ''(array->list array)''
			''A list of the elements of a Smalltalk collection.''
		''procedure->block'' ''(procedure->block proc)''
			''A Smalltalk block that calls proc, for Smalltalk code that wants one.'')'.
cm value: facade class value: 'evaluating' value: 'eval: aString
	"Evaluate LISP source in the global environment; answer the last value."
	^ LispCompiler new evalAll: aString'.
cm value: facade class value: 'evaluating' value: 'read: aString
	"The datum aString holds, unevaluated."
	^ LispReader read: aString'.
cm value: facade class value: 'globals' value: 'at: aName
	"The value of the LISP global aName (a string or Smalltalk symbol)."
	^ LispEnvironment default lookup: (LispSymbol named: aName asString)'.
cm value: facade class value: 'globals' value: 'define: aName as: aValue
	^ LispEnvironment default define: (LispSymbol named: aName asString) value: aValue'.
cm value: facade class value: 'calling' value: 'call: aName
	^ LispProcedure apply: (self at: aName) to: #()'.
cm value: facade class value: 'calling' value: 'call: aName with: a
	^ LispProcedure apply: (self at: aName) to: { a }'.
cm value: facade class value: 'calling' value: 'call: aName with: a with: b
	^ LispProcedure apply: (self at: aName) to: { a. b }'.
cm value: facade class value: 'calling' value: 'call: aName withArguments: anArray
	^ LispProcedure apply: (self at: aName) to: anArray asArray'.
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
	anEnv define: (LispSymbol named: ''assoc'') value: (LispProcedure fixed: (ass value: [:a :b | LispCore equal: a with: b] value: ''assoc'') arity: 2).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Lists'' with: #(
		''memq'' ''(memq x list)''
			''The first tail of list whose car is eq? to x, or #f.''
		''memv'' ''(memv x list)''
			''The first tail of list whose car is eqv? to x, or #f.''
		''member'' ''(member x list)''
			''The first tail of list whose car is equal? to x, or #f.''
		''assq'' ''(assq key alist)''
			''The first pair of the association list whose car is eq? to key, or #f.''
		''assv'' ''(assv key alist)''
			''The first pair of the association list whose car is eqv? to key, or #f.''
		''assoc'' ''(assoc key alist)''
			''The first pair of the association list whose car is equal? to key, or #f.'')'.
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
	(e value: ''null?'') inline: { 1. #identity. LispEmptyList default }.
	"Phase 8 step 8.6: one send, not a call of the primitive"
	(e value: ''pair?'') inline: #(1 #send #isLispPair).
	(e value: ''symbol?'') inline: #(1 #send #isLispSymbol)'.
cm value: prims class value: 'installing' value: 'installDefault
	^ self installInto: LispEnvironment default'.
cm value: prims class value: 'output' value: 'output
	"Where display/write/newline/disassemble write. Defaults to stdout; the REPL and tests redirect it."
	^ Output ifNil: [LispTextOutput stdout]'.
cm value: prims class value: 'input' value: 'input
	"The current input port: set by the REPL and the runner to read stdin."
	^ Input ifNil: [Input := LispInputPort onStream: (LispLineStream on: (ReadStream on: #()))]'.
cm value: prims class value: 'input' value: 'withInput: aPort do: aBlock
	| previous |
	previous := Input.
	Input := aPort.
	^ aBlock ensure: [Input := previous]'.
cm value: prims class value: 'system' value: 'commandLine: anArray
	CommandLine := anArray'.
cm value: prims class value: 'installing' value: 'installFilesInto: anEnv
	"Phase 7.9 section 5: file ports, standard ports, and programs."
	| def opt unspec inFile outFile closing |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	opt := [:rest | rest lispElements asArray].
	unspec := LispUnspecified default.
	inFile := [:path :who | | ref |
		ref := LispCompiler resolveInput: (self string: path for: who).
		ref exists ifFalse: [(LispFileError new) signal: who , '': file not found: '' , path].
		LispInputPort on: ref contents].
	outFile := [:path :who | | ref |
		ref := LispCompiler resolve: (self string: path for: who).
		[ref ensureDelete. LispOutputPort on: ref writeStream]
			on: FileException do: [:e | (LispFileError new) signal: who , '': cannot write '' , path]].
	closing := [:port :blk | [blk value: port] ensure: [port close]].
	def value: ''open-input-file'' value: (LispProcedure fixed: [:p | inFile value: p value: ''open-input-file''] arity: 1).
	def value: ''open-output-file'' value: (LispProcedure fixed: [:p | outFile value: p value: ''open-output-file''] arity: 1).
	def value: ''close-port'' value: (LispProcedure fixed: [:p | p close. unspec] arity: 1).
	def value: ''close-input-port'' value: (LispProcedure fixed: [:p | (self inPort: p for: ''close-input-port'') close. unspec] arity: 1).
	def value: ''close-output-port'' value: (LispProcedure fixed: [:p | (self outPort: p for: ''close-output-port'') close. unspec] arity: 1).
	def value: ''call-with-input-file'' value: (LispProcedure fixed: [:path :proc |
		closing value: (inFile value: path value: ''call-with-input-file'') value: [:port | LispProcedure apply: proc to: { port }]] arity: 2).
	def value: ''call-with-output-file'' value: (LispProcedure fixed: [:path :proc |
		closing value: (outFile value: path value: ''call-with-output-file'') value: [:port | LispProcedure apply: proc to: { port }]] arity: 2).
	def value: ''with-input-from-file'' value: (LispProcedure fixed: [:path :thunk |
		closing value: (inFile value: path value: ''with-input-from-file'') value: [:port |
			self withInput: port do: [LispProcedure apply: thunk to: #()]]] arity: 2).
	def value: ''with-output-to-file'' value: (LispProcedure fixed: [:path :thunk |
		closing value: (outFile value: path value: ''with-output-to-file'') value: [:port |
			self withOutput: port do: [LispProcedure apply: thunk to: #()]]] arity: 2).
	def value: ''file-exists?'' value: (LispProcedure fixed: [:p | (LispCompiler resolveInput: (self string: p for: ''file-exists?'')) exists] arity: 1).
	def value: ''delete-file'' value: (LispProcedure fixed: [:p | | ref |
		ref := LispCompiler resolve: (self string: p for: ''delete-file'').
		ref exists ifFalse: [(LispFileError new) signal: ''delete-file: file not found: '' , p].
		ref delete.
		unspec] arity: 1).
	def value: ''current-input-port'' value: (LispProcedure fixed: [self input] arity: 0).
	def value: ''current-output-port'' value: (LispProcedure fixed: [LispOutputPort on: self output] arity: 0).
	def value: ''current-error-port'' value: (LispProcedure fixed: [LispOutputPort on: LispTextOutput stderr] arity: 0).
	def value: ''command-line'' value: (LispProcedure fixed: [LispCons fromArray: (CommandLine ifNil: [#()])] arity: 0).
	def value: ''current-load-path'' value: (LispProcedure fixed: [LispLoadPath value ifNil: [false]] arity: 0).
	def value: ''write-shared'' value: (LispProcedure variadic: [:x :rest |
		((opt value: rest) ifEmpty: [self output] ifNotEmpty: [:r | self outPort: r first for: ''write-shared''])
			nextPutAll: (LispPrinter writeSharedString: x); flush.
		unspec] required: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Files'' with: #(
		''open-input-file'' ''(open-input-file path)''
			''An input port reading the file at path.''
		''open-output-file'' ''(open-output-file path)''
			''An output port writing the file at path, which is replaced.''
		''close-port'' ''(close-port port)''
			''Closes port.''
		''close-input-port'' ''(close-input-port port)''
			''Closes the input port.''
		''close-output-port'' ''(close-output-port port)''
			''Closes the output port, so what was written is in its file.''
		''call-with-input-file'' ''(call-with-input-file path proc)''
			''Calls proc with an input port on the file, closed afterwards.''
		''call-with-output-file'' ''(call-with-output-file path proc)''
			''Calls proc with an output port on the file, closed afterwards.''
		''with-input-from-file'' ''(with-input-from-file path thunk)''
			''Calls thunk with the current input read from the file.''
		''with-output-to-file'' ''(with-output-to-file path thunk)''
			''Calls thunk with the current output written to the file.''
		''file-exists?'' ''(file-exists? path)''
			''True if there is a file at path.''
		''delete-file'' ''(delete-file path)''
			''Deletes the file at path.''
		''current-input-port'' ''(current-input-port)''
			''The port read reads from by default.''
		''current-output-port'' ''(current-output-port)''
			''The port display and write write to by default.''
		''current-error-port'' ''(current-error-port)''
			''The port for error messages.''
		''current-load-path'' ''(current-load-path)''
			''The full path of the file being loaded or run, or #f.''
		''command-line'' ''(command-line)''
			''A list of the program name and its arguments, as strings.''
		''write-shared'' ''(write-shared x [port])''
			''Writes x with a datum label for every part it shares, so the sharing reads back.'')'.
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
	anEnv define: (LispSymbol named: ''for-each'') value: (LispProcedure fixed: [:prc :lst | (LispCons elementsOf: lst for: ''for-each'') do: [:e | LispProcedure apply: prc to: { e }]. LispUnspecified default] arity: 2).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Lists'' with: #(
		''cons'' ''(cons a b)''
			''A new pair whose car is a and whose cdr is b.''
		''car'' ''(car pair)''
			''The first element of pair.''
		''cdr'' ''(cdr pair)''
			''The second element of pair: for a list, the rest of it.''
		''set-car!!'' ''(set-car!! pair x)''
			''Replaces the car of pair with x.''
		''set-cdr!!'' ''(set-cdr!! pair x)''
			''Replaces the cdr of pair with x.''
		''list'' ''(list x ...)''
			''A new list of the arguments.''
		''length'' ''(length list)''
			''The number of elements of list; an error for an improper or circular list.''
		''append'' ''(append list ... x)''
			''A list of the elements of each list in turn, ending in x, which is shared, not copied.''
		''reverse'' ''(reverse list)''
			''A new list of the elements of list in reverse order.''
		''map'' ''(map proc list)''
			''A new list of the results of calling proc on each element of list.''
		''for-each'' ''(for-each proc list)''
			''Calls proc on each element of list, in order, for its effect.''
		''null?'' ''(null? x)''
			''True if x is the empty list.''
		''pair?'' ''(pair? x)''
			''True if x is a pair.''
		''list?'' ''(list? x)''
			''True if x is a proper list: finite, and ending in the empty list.'')'.
cm value: prims class value: 'installing' value: 'installNumbersInto: anEnv
	"(+ x) and (* x) check x: they used to answer it whatever it was (review R-11)"
	anEnv define: (LispSymbol named: ''+'') value: (LispProcedure variadic: [:nums | | xs | xs := nums lispElements. xs size = 1 ifTrue: [self number: xs first for: ''+''] ifFalse: [xs inject: 0 into: [:a :b | a + b]]] required: 0).
	anEnv define: (LispSymbol named: ''*'') value: (LispProcedure variadic: [:nums | | xs | xs := nums lispElements. xs size = 1 ifTrue: [self number: xs first for: ''*''] ifFalse: [xs inject: 1 into: [:a :b | a * b]]] required: 0).
	anEnv define: (LispSymbol named: ''-'') value: (LispProcedure variadic: [:first :rest | rest lispElements isEmpty ifTrue: [(self number: first for: ''-'') negated] ifFalse: [rest lispElements inject: first into: [:a :b | a - b]]] required: 1).
	anEnv define: (LispSymbol named: ''/'') value: (LispProcedure variadic: [:first :rest | rest lispElements isEmpty ifTrue: [self divide: 1 by: (self number: first for: ''/'')] ifFalse: [rest lispElements inject: first into: [:a :b | self divide: a by: b]]] required: 1).
	anEnv define: (LispSymbol named: ''min'') value: (LispProcedure variadic: [:first :rest | self extreme: #min: of: first and: rest for: ''min''] required: 1).
	anEnv define: (LispSymbol named: ''max'') value: (LispProcedure variadic: [:first :rest | self extreme: #max: of: first and: rest for: ''max''] required: 1).
	anEnv define: (LispSymbol named: ''zero?'') value: (LispProcedure fixed: [:a | (self number: a for: ''zero?'') = 0] arity: 1).
	anEnv define: (LispSymbol named: ''positive?'') value: (LispProcedure fixed: [:a | (self real: a for: ''positive?'') > 0] arity: 1).
	anEnv define: (LispSymbol named: ''negative?'') value: (LispProcedure fixed: [:a | (self real: a for: ''negative?'') < 0] arity: 1).
	self installNumericTowerInto: anEnv.
	self installNumericProceduresInto: anEnv.
	self installNumberEntriesInto: anEnv.
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Numbers'' with: #(
		''+'' ''(+ z ...)''
			''The sum of the numbers; 0 for none.''
		''*'' ''(* z ...)''
			''The product of the numbers; 1 for none.''
		''-'' ''(- z w ...)''
			''z minus each w in turn; with one argument, its negation.''
		''/'' ''(/ z w ...)''
			''z divided by each w in turn; with one argument, its reciprocal. Exact division stays exact (1/3); a float divided by zero gives an infinity or NaN.''
		''abs'' ''(abs x)''
			''The absolute value of the real number x.''
		''magnitude'' ''(magnitude x)''
			''The magnitude of x: for a real number, its absolute value.''
		''square'' ''(square z)''
			''z times z.''
		''min'' ''(min x y ...)''
			''The smallest of the real numbers; inexact if any of them is.''
		''max'' ''(max x y ...)''
			''The largest of the real numbers; inexact if any of them is.''
		''zero?'' ''(zero? z)''
			''True if z is zero, exact or inexact.''
		''positive?'' ''(positive? x)''
			''True if the real number x is greater than zero.''
		''negative?'' ''(negative? x)''
			''True if the real number x is less than zero.''
		''odd?'' ''(odd? n)''
			''True if the integer n is odd.''
		''even?'' ''(even? n)''
			''True if the integer n is even.''
		''complex?'' ''(complex? x)''
			''True if x is a number: there are no non-real numbers built in.''
		''real?'' ''(real? x)''
			''True if x is a real number.''
		''rational?'' ''(rational? x)''
			''True if x is a rational number: an exact rational, or a finite float.''
		''exact?'' ''(exact? z)''
			''True if the number z is exact.''
		''inexact?'' ''(inexact? z)''
			''True if the number z is inexact (a float).''
		''exact-integer?'' ''(exact-integer? x)''
			''True if x is an exact integer.''
		''exact-rational?'' ''(exact-rational? x)''
			''True if x is an exact integer or an exact fraction.''
		''nan?'' ''(nan? z)''
			''True if the number z is a NaN.''
		''infinite?'' ''(infinite? z)''
			''True if the number z is +inf.0 or -inf.0.''
		''finite?'' ''(finite? z)''
			''True if the number z is neither infinite nor NaN.''
		''exact'' ''(exact z)''
			''The exact number equal to z: a float gives the fraction it holds exactly. An error for an infinity or NaN.''
		''inexact'' ''(inexact z)''
			''The float nearest to z.''
		''exact->inexact'' ''(exact->inexact z)''
			''The old name of inexact.''
		''inexact->exact'' ''(inexact->exact z)''
			''The old name of exact.''
		''floor'' ''(floor x)''
			''The largest integer not greater than x; a float stays a float.''
		''ceiling'' ''(ceiling x)''
			''The smallest integer not less than x; a float stays a float.''
		''truncate'' ''(truncate x)''
			''x with its fraction dropped, toward zero; a float stays a float.''
		''round'' ''(round x)''
			''The nearest integer to x, a half going to the even one; a float stays a float.''
		''floor/'' ''(floor/ n d)''
			''Two values: the quotient of n by d rounded toward minus infinity, and the remainder, which has the sign of d.''
		''floor-quotient'' ''(floor-quotient n d)''
			''The quotient of n by d, rounded toward minus infinity.''
		''floor-remainder'' ''(floor-remainder n d)''
			''The remainder of n by d after floor-quotient; it has the sign of d.''
		''truncate/'' ''(truncate/ n d)''
			''Two values: the quotient of n by d rounded toward zero, and the remainder, which has the sign of n.''
		''truncate-quotient'' ''(truncate-quotient n d)''
			''The quotient of n by d, rounded toward zero.''
		''truncate-remainder'' ''(truncate-remainder n d)''
			''The remainder of n by d after truncate-quotient; it has the sign of n.''
		''quotient'' ''(quotient n d)''
			''The old name of truncate-quotient.''
		''remainder'' ''(remainder n d)''
			''The old name of truncate-remainder.''
		''modulo'' ''(modulo n d)''
			''The old name of floor-remainder.''
		''numerator'' ''(numerator q)''
			''The numerator of the rational q in lowest terms.''
		''denominator'' ''(denominator q)''
			''The denominator of the rational q in lowest terms, always positive.''
		''gcd'' ''(gcd n ...)''
			''The greatest common divisor of the integers, never negative; 0 for none.''
		''lcm'' ''(lcm n ...)''
			''The least common multiple of the integers, never negative; 1 for none.''
		''sqrt'' ''(sqrt x)''
			''The square root of x: exact for an exact perfect square, else inexact. An error for a negative number (complex numbers are not built in).''
		''exact-integer-sqrt'' ''(exact-integer-sqrt n)''
			''Two values: the largest integer s with s*s not above n, and n - s*s.''
		''expt'' ''(expt z1 z2)''
			''z1 raised to the power z2: exact for an exact base and an exact integer power.''
		''rationalize'' ''(rationalize x y)''
			''The simplest rational number within y of x; inexact if either is.''
		''exp'' ''(exp z)''
			''e raised to the power z.''
		''log'' ''(log z [base])''
			''The natural logarithm of z, or its logarithm in base; -inf.0 at zero, +nan.0 below it.''
		''sin'' ''(sin z)''
			''The sine of z, in radians.''
		''cos'' ''(cos z)''
			''The cosine of z, in radians.''
		''tan'' ''(tan z)''
			''The tangent of z, in radians.''
		''asin'' ''(asin z)''
			''The arcsine of z; +nan.0 outside -1 to 1.''
		''acos'' ''(acos z)''
			''The arccosine of z; +nan.0 outside -1 to 1.''
		''atan'' ''(atan y [x])''
			''The arctangent of y, or of y/x in the right quadrant.'').
	self document: anEnv category: ''Control'' with: #(
		''values'' ''(values x ...)''
			''Answers its arguments as several values; one value is just itself.''
		''call-with-values'' ''(call-with-values producer consumer)''
			''Calls consumer with the values producer answers.'')'.
cm value: prims class value: 'installing' value: 'installNumberEntriesInto: anEnv
	"Phase 6 section 5.1: direct entries for the common fixed-arity uses of the
	 variadic arithmetic primitives, so (+ a b) costs one block call."
	| e |
	e := [:name | anEnv lookup: (LispSymbol named: name)].
	"0 to 4 arguments, as Phase 6 section 10 says: with four, (+ acc g1 g2 g3) used to take
	 the variadic path, 14 times slower (review O-1)"
	(e value: ''+'') entry: 0 is: [0]; entry: 1 is: [:a | self number: a for: ''+'']; entry: 2 is: [:a :b | a + b]; entry: 3 is: [:a :b :c | a + b + c]; entry: 4 is: [:a :b :c :d | a + b + c + d].
	(e value: ''*'') entry: 0 is: [1]; entry: 1 is: [:a | self number: a for: ''*'']; entry: 2 is: [:a :b | a * b]; entry: 3 is: [:a :b :c | a * b * c]; entry: 4 is: [:a :b :c :d | a * b * c * d].
	(e value: ''-'') entry: 1 is: [:a | (self number: a for: ''-'') negated]; entry: 2 is: [:a :b | a - b]; entry: 3 is: [:a :b :c | a - b - c]; entry: 4 is: [:a :b :c :d | a - b - c - d].
	(e value: ''/'') entry: 1 is: [:a | self divide: 1 by: (self number: a for: ''/'')]; entry: 2 is: [:a :b | self divide: a by: b].
	(e value: ''min'') entry: 2 is: [:a :b | self extreme: #min: of: a and: (LispCons car: b cdr: LispEmptyList default) for: ''min''].
	(e value: ''max'') entry: 2 is: [:a :b | self extreme: #max: of: a and: (LispCons car: b cdr: LispEmptyList default) for: ''max'']'.
cm value: prims class value: 'arithmetic' value: 'extreme: aSelector of: first and: rest for: who
	"min or max: inexact if any argument is (R7RS 6.2.6)."
	| result inexact |
	result := self real: first for: who.
	inexact := result lispIsExact not.
	rest lispElements do: [:x |
		(self real: x for: who) lispIsExact ifFalse: [inexact := true].
		result := result perform: aSelector with: x].
	^ inexact ifTrue: [result asFloat] ifFalse: [result]'.
cm value: prims class value: 'installing' value: 'installNumericTowerInto: anEnv
	"Phase 9 step 9.2a: the predicates, from the number protocol (Number>>lispIsExact
	 and the rest, in CogLisp-Core), and exactness."
	| def num |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	num := [:x :who | self number: x for: who].
	def value: ''complex?'' value: (LispProcedure fixed: [:x | x isNumber] arity: 1).
	def value: ''real?'' value: (LispProcedure fixed: [:x | x isNumber and: [x lispIsReal]] arity: 1).
	def value: ''rational?'' value: (LispProcedure fixed: [:x | x isNumber and: [x lispIsRational]] arity: 1).
	def value: ''exact-integer?'' value: (LispProcedure fixed: [:x | x isNumber and: [x lispIsExact and: [x lispIsInteger]]] arity: 1).
	def value: ''exact-rational?'' value: (LispProcedure fixed: [:x | x isNumber and: [x lispIsExact and: [x lispIsRational]]] arity: 1).
	def value: ''exact?'' value: (LispProcedure fixed: [:x | (num value: x value: ''exact?'') lispIsExact] arity: 1).
	def value: ''inexact?'' value: (LispProcedure fixed: [:x | (num value: x value: ''inexact?'') lispIsExact not] arity: 1).
	def value: ''nan?'' value: (LispProcedure fixed: [:x | (num value: x value: ''nan?'') lispIsNaN] arity: 1).
	def value: ''infinite?'' value: (LispProcedure fixed: [:x | (num value: x value: ''infinite?'') lispIsInfinite] arity: 1).
	def value: ''finite?'' value: (LispProcedure fixed: [:x | (num value: x value: ''finite?'') lispIsInfinite not and: [x lispIsNaN not]] arity: 1).
	def value: ''odd?'' value: (LispProcedure fixed: [:x | ((self integer: x for: ''odd?'') \\ 2) = 1] arity: 1).
	def value: ''even?'' value: (LispProcedure fixed: [:x | ((self integer: x for: ''even?'') \\ 2) = 0] arity: 1).
	def value: ''exact'' value: (LispProcedure fixed: [:x | self exact: x for: ''exact''] arity: 1).
	def value: ''inexact->exact'' value: (LispProcedure fixed: [:x | self exact: x for: ''inexact->exact''] arity: 1).
	def value: ''inexact'' value: (LispProcedure fixed: [:x | (num value: x value: ''inexact'') lispIsExact ifTrue: [x asFloat] ifFalse: [x]] arity: 1).
	def value: ''exact->inexact'' value: (LispProcedure fixed: [:x | (num value: x value: ''exact->inexact'') lispIsExact ifTrue: [x asFloat] ifFalse: [x]] arity: 1)'.
cm value: prims class value: 'installing' value: 'installNumericProceduresInto: anEnv
	"Phase 9 step 9.2b: multiple values, rounding, the division family, roots and
	 powers, the transcendental functions (R7RS 6.2.6, 6.10)."
	| def real int inexactIf values float |
	def := [:name :proc | anEnv define: (LispSymbol named: name) value: proc].
	real := [:x :who | self real: x for: who].
	int := [:x :who | self integer: x for: who].
	values := [:a :b | LispValues withAll: { a. b }].
	"x, inexact when any of the numbers is"
	inexactIf := [:x :nums | (nums anySatisfy: [:n | n lispIsExact not]) ifTrue: [x asFloat] ifFalse: [x]].
	float := [:x :who | (real value: x value: who) asFloat].

	"multiple values"
	def value: ''values'' value: (LispProcedure variadic: [:rest | | xs |
		xs := rest lispElements asArray.
		xs size = 1 ifTrue: [xs first] ifFalse: [LispValues withAll: xs]] required: 0).
	def value: ''call-with-values'' value: (LispProcedure fixed: [:producer :consumer | | v |
		v := LispProcedure call: producer.
		LispProcedure tailCall: consumer to: ((v isKindOf: LispValues) ifTrue: [v values] ifFalse: [{ v }])] arity: 2).

	"rounding: exact stays exact, a float stays a float"
	def value: ''floor'' value: (LispProcedure fixed: [:x | self round: (real value: x value: ''floor'') with: [:y | y floor]] arity: 1).
	def value: ''ceiling'' value: (LispProcedure fixed: [:x | self round: (real value: x value: ''ceiling'') with: [:y | y ceiling]] arity: 1).
	def value: ''truncate'' value: (LispProcedure fixed: [:x | self round: (real value: x value: ''truncate'') with: [:y | y truncated]] arity: 1).
	def value: ''round'' value: (LispProcedure fixed: [:x | self round: (real value: x value: ''round'') with: [:y | self roundToEven: y]] arity: 1).

	"the division family, on integers (2.0 is one too)"
	#( (''floor-quotient'' #//) (''floor-remainder'' #\\) (''modulo'' #\\)
	   (''truncate-quotient'' #quo:) (''truncate-remainder'' #rem:) (''quotient'' #quo:) (''remainder'' #rem:) ) do: [:pair |
		def value: pair first value: (LispProcedure fixed: [:a :b | self integerDivide: a by: b with: pair second for: pair first] arity: 2)].
	def value: ''floor/'' value: (LispProcedure fixed: [:a :b |
		values value: (self integerDivide: a by: b with: #// for: ''floor/'') value: (self integerDivide: a by: b with: #\\ for: ''floor/'')] arity: 2).
	def value: ''truncate/'' value: (LispProcedure fixed: [:a :b |
		values value: (self integerDivide: a by: b with: #quo: for: ''truncate/'') value: (self integerDivide: a by: b with: #rem: for: ''truncate/'')] arity: 2).

	"rationals and integers"
	def value: ''numerator'' value: (LispProcedure fixed: [:x | | e |
		e := self exact: (self rational: x for: ''numerator'') for: ''numerator''.
		inexactIf value: e numerator value: { x }] arity: 1).
	def value: ''denominator'' value: (LispProcedure fixed: [:x | | e |
		e := self exact: (self rational: x for: ''denominator'') for: ''denominator''.
		inexactIf value: e denominator value: { x }] arity: 1).
	def value: ''gcd'' value: (LispProcedure variadic: [:rest | | xs |
		xs := rest lispElements collect: [:x | int value: x value: ''gcd''].
		inexactIf value: (xs inject: 0 into: [:a :b | a asInteger gcd: b asInteger]) abs value: xs] required: 0).
	def value: ''lcm'' value: (LispProcedure variadic: [:rest | | xs |
		xs := rest lispElements collect: [:x | int value: x value: ''lcm''].
		inexactIf value: (xs inject: 1 into: [:a :b | (a = 0 or: [b = 0]) ifTrue: [0] ifFalse: [a asInteger lcm: b asInteger]]) abs value: xs] required: 0).
	def value: ''abs'' value: (LispProcedure fixed: [:x | (real value: x value: ''abs'') abs] arity: 1).
	def value: ''magnitude'' value: (LispProcedure fixed: [:x | (real value: x value: ''magnitude'') abs] arity: 1).
	def value: ''square'' value: (LispProcedure fixed: [:x | | n | n := self number: x for: ''square''. n * n] arity: 1).

	"roots and powers"
	def value: ''sqrt'' value: (LispProcedure fixed: [:x | self sqrt: (real value: x value: ''sqrt'')] arity: 1).
	def value: ''exact-integer-sqrt'' value: (LispProcedure fixed: [:n | | s |
		((n isNumber and: [n lispIsExact and: [n lispIsInteger]]) and: [n >= 0])
			ifFalse: [self fail: ''exact-integer-sqrt'' with: ''not an exact non-negative integer: '' , (self show: n)].
		s := n sqrtFloor.
		values value: s value: n - (s * s)] arity: 1).
	def value: ''expt'' value: (LispProcedure fixed: [:a :b | self expt: (self number: a for: ''expt'') to: (self number: b for: ''expt'')] arity: 2).
	def value: ''rationalize'' value: (LispProcedure fixed: [:x :y | self rationalize: (real value: x value: ''rationalize'') within: (real value: y value: ''rationalize'')] arity: 2).

	"the transcendental functions: inexact; +nan.0 outside the real domain"
	def value: ''exp'' value: (LispProcedure fixed: [:x | (float value: x value: ''exp'') exp] arity: 1).
	def value: ''log'' value: (LispProcedure variadic: [:x :rest | | ln |
		ln := [:y :who | self naturalLog: (float value: y value: who)].
		rest lispElements isEmpty
			ifTrue: [ln value: x value: ''log'']
			ifFalse: [(ln value: x value: ''log'') / (ln value: rest lispElements first value: ''log'')]] required: 1).
	#( (''sin'' #sin) (''cos'' #cos) (''tan'' #tan) ) do: [:pair |
		def value: pair first value: (LispProcedure fixed: [:x | | f |
			f := float value: x value: pair first.
			f isFinite ifTrue: [f perform: pair second] ifFalse: [Float nan]] arity: 1)].
	#( (''asin'' #arcSin) (''acos'' #arcCos) ) do: [:pair |
		def value: pair first value: (LispProcedure fixed: [:x | | f |
			f := float value: x value: pair first.
			(f between: -1.0 and: 1.0) ifTrue: [f perform: pair second] ifFalse: [Float nan]] arity: 1)].
	def value: ''atan'' value: (LispProcedure variadic: [:y :rest |
		rest lispElements isEmpty
			ifTrue: [(float value: y value: ''atan'') arcTan]
			ifFalse: [(float value: y value: ''atan'') arcTan: (float value: rest lispElements first value: ''atan'')]] required: 1)'.
cm value: prims class value: 'checks' value: 'rational: x for: who
	((x isNumber) and: [x lispIsRational]) ifFalse: [self fail: who with: ''not a rational number: '' , (self show: x)].
	^ x'.
cm value: prims class value: 'arithmetic' value: 'round: x with: aBlock
	"floor, ceiling, round, truncate: exact gives exact; a float gives a float,
	 keeping the sign of zero (ceiling -0.5 is -0.0) and leaving infinities and
	 NaN as they are"
	| r |
	x lispIsExact ifTrue: [^ aBlock value: x].
	(x isFinite) ifFalse: [^ x].
	r := (aBlock value: x) asFloat.
	^ (r = 0.0 and: [x signBit = 1]) ifTrue: [Float negativeZero] ifFalse: [r]'.
cm value: prims class value: 'arithmetic' value: 'roundToEven: x
	"to the nearest integer, a half to the even one (R7RS round)"
	| f diff |
	f := x floor.
	diff := x - f.
	diff < (1/2) ifTrue: [^ f].
	diff > (1/2) ifTrue: [^ f + 1].
	^ f even ifTrue: [f] ifFalse: [f + 1]'.
cm value: prims class value: 'arithmetic' value: 'integerDivide: a by: b with: aSelector for: who
	"The division family on integers; inexact if either is (a float with an
	 integer value counts as an integer)."
	| r |
	self integer: a for: who.
	self integer: b for: who.
	b = 0 ifTrue: [self fail: who with: ''division by zero''].
	r := a asInteger perform: aSelector with: b asInteger.
	^ (a lispIsExact and: [b lispIsExact]) ifTrue: [r] ifFalse: [r asFloat]'.
cm value: prims class value: 'arithmetic' value: 'sqrt: x
	"Exact for an exact perfect square (of a rational), else inexact. No real square
	 root for a negative number: complex numbers are a library."
	| n d sn sd |
	(x < 0) ifTrue: [self fail: ''sqrt'' with: ''no real square root of '' , (self show: x) , '' (complex numbers are not built in)''].
	x lispIsExact ifFalse: [^ x sqrt].
	n := x numerator. d := x denominator.
	sn := n sqrtFloor. sd := d sqrtFloor.
	((sn * sn) = n and: [(sd * sd) = d]) ifTrue: [^ sn / sd].
	^ x asFloat sqrt'.
cm value: prims class value: 'arithmetic' value: 'expt: a to: b
	"Exact for an exact base and an exact integer power; a zero base by its own
	 rules; a negative base to a non-integer power has no real answer."
	(a lispIsReal and: [b lispIsReal]) ifFalse: [^ a raisedTo: b].
	(b lispIsExact and: [b lispIsInteger]) ifTrue: [
		b < 0 ifTrue: [^ self divide: 1 by: (a raisedTo: b negated)].
		^ a raisedTo: b].
	a = 0 ifTrue: [
		b = 0 ifTrue: [^ (a lispIsExact and: [b lispIsExact]) ifTrue: [1] ifFalse: [1.0]].
		b > 0 ifTrue: [^ (a lispIsExact and: [b lispIsExact]) ifTrue: [0] ifFalse: [0.0]].
		^ Float infinity].
	a < 0 ifTrue: [
		b lispIsInteger ifTrue: [^ a asFloat raisedTo: b asInteger].
		self fail: ''expt'' with: ''no real value for '' , (self show: a) , '' to the power '' , (self show: b) , '' (complex numbers are not built in)''].
	(a lispIsExact and: [b lispIsExact]) ifTrue: [^ a raisedTo: b].
	^ a asFloat raisedTo: b asFloat'.
cm value: prims class value: 'arithmetic' value: 'naturalLog: f
	"ln of a float: -inf.0 at zero, +nan.0 below it"
	f isNaN ifTrue: [^ f].
	f = 0.0 ifTrue: [^ Float infinity negated].
	f < 0.0 ifTrue: [^ Float nan].
	f isInfinite ifTrue: [^ f].
	^ f ln'.
cm value: prims class value: 'arithmetic' value: 'rationalize: x within: y
	"The simplest rational within y of x (R7RS 6.2.6): inexact if either is."
	| exact lo hi r |
	(x lispIsNaN or: [y lispIsNaN]) ifTrue: [^ Float nan].
	y lispIsInfinite ifTrue: [^ x lispIsInfinite ifTrue: [Float nan] ifFalse: [0.0]].
	x lispIsInfinite ifTrue: [^ x].
	exact := x lispIsExact and: [y lispIsExact].
	lo := (self exact: x for: ''rationalize'') - (self exact: y for: ''rationalize'') abs.
	hi := (self exact: x for: ''rationalize'') + (self exact: y for: ''rationalize'') abs.
	r := self simplestBetween: lo and: hi.
	^ exact ifTrue: [r] ifFalse: [r asFloat]'.
cm value: prims class value: 'arithmetic' value: 'simplestBetween: lo and: hi
	"the rational with the smallest denominator in [lo, hi], lo <= hi (Stern-Brocot)"
	| fl |
	(lo <= 0 and: [hi >= 0]) ifTrue: [^ 0].
	hi < 0 ifTrue: [^ (self simplestBetween: hi negated and: lo negated) negated].
	fl := lo floor.
	fl = lo ifTrue: [^ fl].
	fl < hi floor ifTrue: [^ fl + 1].
	^ fl + (1 / (self simplestBetween: 1 / (hi - fl) and: 1 / (lo - fl)))'.
cm value: prims class value: 'arithmetic' value: 'exact: x for: who
	"The exact number equal to x: a float''s exact value, not a nearby fraction."
	(self number: x for: who) lispIsExact ifTrue: [^ x].
	(x isKindOf: Float) ifFalse: [self fail: who with: ''no exact value for '' , (self show: x)].
	(x isNaN or: [x isInfinite]) ifTrue: [self fail: who with: ''no exact value for '' , (self show: x)].
	^ x asTrueFraction'.
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
	(e value: ''>='') entry: 2 is: [:a :b | a >= b].
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Numbers'' with: #(
		''='' ''(= z1 z2 ...)''
			''True if the numbers are all equal.''
		''<'' ''(< x1 x2 ...)''
			''True if the numbers are strictly increasing.''
		''>'' ''(> x1 x2 ...)''
			''True if the numbers are strictly decreasing.''
		''<='' ''(<= x1 x2 ...)''
			''True if the numbers never decrease.''
		''>='' ''(>= x1 x2 ...)''
			''True if the numbers never increase.'')'.
cm value: prims class value: 'installing' value: 'installPredicatesInto: anEnv
	| equality |
	"each registered, so make-hash-table knows it (equalityTests)"
	equality := [:name :test :aBlock | | p |
		p := LispProcedure fixed: aBlock arity: 2.
		self equalityTests at: p put: test.
		anEnv define: (LispSymbol named: name) value: p].
	equality value: ''eq?'' value: #eq value: [:a :b | LispCore eq: a with: b].
	equality value: ''eqv?'' value: #eqv value: [:a :b | LispCore eqv: a with: b].
	equality value: ''equal?'' value: #equal value: [:a :b | LispCore equal: a with: b].
	anEnv define: (LispSymbol named: ''not'') value: (LispProcedure fixed: [:x | x == false] arity: 1).
	anEnv define: (LispSymbol named: ''symbol?'') value: (LispProcedure fixed: [:x | LispCore isSymbol: x] arity: 1).
	anEnv define: (LispSymbol named: ''number?'') value: (LispProcedure fixed: [:x | LispCore isNumber: x] arity: 1).
	anEnv define: (LispSymbol named: ''integer?'') value: (LispProcedure fixed: [:x | LispCore isInteger: x] arity: 1).
	anEnv define: (LispSymbol named: ''string?'') value: (LispProcedure fixed: [:x | LispCore isString: x] arity: 1).
	anEnv define: (LispSymbol named: ''char?'') value: (LispProcedure fixed: [:x | LispCore isChar: x] arity: 1).
	anEnv define: (LispSymbol named: ''boolean?'') value: (LispProcedure fixed: [:x | LispCore isBoolean: x] arity: 1).
	anEnv define: (LispSymbol named: ''procedure?'') value: (LispProcedure fixed: [:x | x isKindOf: LispProcedure] arity: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Equality and types'' with: #(
		''eq?'' ''(eq? a b)''
			''True if a and b are the same object.''
		''eqv?'' ''(eqv? a b)''
			''True if a and b are the same object, or numbers of the same exactness and value, or the same character.''
		''equal?'' ''(equal? a b)''
			''True if a and b are eqv?, or pairs, vectors or strings with equal? contents.''
		''not'' ''(not x)''
			''True if x is #f, the only false value.''
		''boolean?'' ''(boolean? x)''
			''True if x is #t or #f.''
		''symbol?'' ''(symbol? x)''
			''True if x is a symbol.''
		''number?'' ''(number? x)''
			''True if x is a number.''
		''integer?'' ''(integer? x)''
			''True if x is an integer, exact or not: (integer? 2.0) is true.''
		''string?'' ''(string? x)''
			''True if x is a string.''
		''char?'' ''(char? x)''
			''True if x is a character.''
		''procedure?'' ''(procedure? x)''
			''True if x is a procedure.'')'.
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
	anEnv define: (LispSymbol named: ''procedure-documentation'') value: (LispProcedure fixed: [:p | p lispDocumentation ifNil: [false]] arity: 1).
	anEnv define: (LispSymbol named: ''stack-depth'') value: (LispProcedure fixed: [| c n |
		c := thisContext.
		n := 0.
		[c notNil] whileTrue: [n := n + 1. c := c sender].
		n] arity: 0).
	anEnv define: (LispSymbol named: ''disassemble'') value: (LispProcedure fixed: [:p |
		self output nextPutAll: p block compiledBlock symbolic; nextPut: Character lf; flush.
		LispUnspecified default] arity: 1).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''The system'' with: #(
		''load'' ''(load path)''
			''Reads and evaluates every form of the file at path, relative to the file being loaded.''
		''exit'' ''(exit [code])''
			''Ends the program: (exit) and (exit #t) succeed, (exit #f) fails, (exit n) exits with n.''
		''save-image'' ''(save-image)''
			''Saves the running image, so its definitions are there when it next starts.''
		''procedure-documentation'' ''(procedure-documentation proc)''
			''The documentation of proc, or #f: the call form on its first line, then what it does.''
		''procedure-source'' ''(procedure-source proc)''
			''The text proc was compiled from, or #f for a primitive.''
		''stack-depth'' ''(stack-depth)''
			''The number of frames on the stack, for testing that loops run in constant space.''
		''disassemble'' ''(disassemble proc)''
			''Writes the bytecode of the procedure proc.'')'.
cm value: prims class value: 'installing' value: 'installControlInto: anEnv
	"apply answers a bounce rather than calling, so that a tail call through apply
	 runs in constant stack; every caller of a procedure drives bounces (Phase 6)."
	anEnv define: (LispSymbol named: ''apply'') value: (LispProcedure fixed: [:prc :argList | LispProcedure tailCall: prc to: (LispCons elementsOf: argList for: ''apply'') asArray] arity: 2).
	"its documentation (Phase 10 step 10.1): name, call form, description"
	self document: anEnv category: ''Control'' with: #(
		''apply'' ''(apply proc list)''
			''Calls proc with the elements of list as its arguments.'')'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Runtime'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Runtime: ' , failures size printString].
