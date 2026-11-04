"============================================================================
 cog-lisp : Phase 8 step 8.2 suite  (specs/phase-8-self-hosting.md AC-2)
 The LISP reader (lib/compiler/reader.lisp) against the Smalltalk reader
 (LispReader): on the Phase 1 corpus, on the inputs of every later reader
 feature and error, and on every .lisp file in the repository. For each input
 both readers give the same events: per datum its start and end offsets and its
 shape (every list with its source text, every vector with its size and
 read-only flag, every atom with its class and printed form), then the end
 position, or the read error's class, message, position and incomplete flag.
 The reader's own unit tests are tests/lisp/phase-8.2-reader.lisp.
 Every bang in Lisp text is doubled for the chunk reader.
 ============================================================================"

"--- Chunk 1: load the packages and the harness -----------------------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn].
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h root global shape events stEvents lispEvents firstDiff compare lf corpus files skip count |
h := LispTestHarness new.
root := Smalltalk imageDirectory parent.
global := [:name | LispCompiler new evalString: name].
lf := String with: Character lf.

"the shape of a datum: what both readers must agree on, cycle-safe"
shape := [:datum :sourceFor | | out seen walk |
	out := OrderedCollection new.
	seen := IdentitySet new.
	walk := nil.
	walk := [:x |
		(seen includes: x)
			ifTrue: [out add: #seen]
			ifFalse: [
				(x isKindOf: LispCons)
					ifTrue: [
						seen add: x.
						out add: { #list. sourceFor value: x }.
						walk value: x car.
						walk value: x cdr]
					ifFalse: [
						(x isKindOf: Array)
							ifTrue: [
								seen add: x.
								out add: { #vector. x size. x isReadOnlyObject }.
								x do: [:y | walk value: y]]
							ifFalse: [out add: { x class name. LispPrinter writeString: x }]]]].
	walk value: datum.
	out].

"next answers a datum or the eof object; the rest reads the reader's state"
events := [:next :datumStart :position :sourceFor | | out d |
	out := OrderedCollection new.
	[[(d := next value) == LispReader eofObject] whileFalse: [
		out add: { #datum. datumStart value. position value }.
		out addAll: (shape value: d value: sourceFor)].
	 out add: { #eof. position value }]
		on: LispReadError
		do: [:e | out add: { #error. e class name. e messageText. e position. e isIncomplete }].
	out asArray].

stEvents := [:src | | r |
	r := LispReader on: src.
	events value: [r next] value: [r datumStart] value: [r position] value: [:c | r sourceFor: c]].

lispEvents := [:src | | r mk nx ds ps sf |
	mk := global value: 'make-reader'. nx := global value: 'reader-next'.
	ds := global value: 'reader-datum-start'. ps := global value: 'reader-position'.
	sf := global value: 'reader-source-for'.
	r := mk value: src.
	events value: [nx value: r] value: [ds value: r] value: [ps value: r]
		value: [:c | | s | s := sf value: r value: c. s == false ifTrue: [nil] ifFalse: [s]]].

"nil when the two event lists agree, else where and how they first differ"
firstDiff := [:a :b | | n diff |
	diff := nil.
	n := a size min: b size.
	1 to: n do: [:i | (diff isNil and: [(a at: i) ~= (b at: i)]) ifTrue: [
		diff := 'event ' , i printString , ': lisp ' , (a at: i) printString , ', smalltalk ' , (b at: i) printString]].
	(diff isNil and: [a size ~= b size]) ifTrue: [
		diff := 'lisp gave ' , a size printString , ' events, smalltalk ' , b size printString].
	diff].

"labels go to stdout as bytes: a short input is shown, with control and
 non-ASCII characters as \x..;"
compare := [:label :src | | a b shown |
	shown := String streamContents: [:s | src printString do: [:c |
		(c asInteger between: 32 and: 126) ifTrue: [s nextPut: c] ifFalse: [s nextPutAll: '\x' , (c asInteger printStringBase: 16) asLowercase , ';']]].
	a := [lispEvents value: src] on: Error do: [:e | { #crashed. e class name. e messageText }].
	b := stEvents value: src.
	h check: (src size < 60 ifTrue: [label , ' ' , shown] ifFalse: [label]) actual: (firstDiff value: a value: b) expected: nil].

[
h say: '== cog-lisp Phase 8.2 : the reader in LISP =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (root / 'lib' / 'core.lisp') fullName.
LispCompiler new evalFile: (root / 'lib' / 'compiler' / 'reader.lisp') fullName.

"the comparison itself: it must see a difference in source text, in an error
 position, and in an atom's class"
h check: 'control: a different source range is a difference'
	actual: (firstDiff value: (stEvents value: '(a b)') value: (stEvents value: '(a  b)')) notNil expected: true.
h check: 'control: a different error position is a difference'
	actual: (firstDiff value: (stEvents value: '(a') value: (stEvents value: ' (a')) notNil expected: true.
h check: 'control: 1 and 1.0 differ'
	actual: (firstDiff value: (stEvents value: '1') value: (stEvents value: '1.0')) notNil expected: true.
h check: 'control: the LISP reader reads (a b)'
	actual: (lispEvents value: '(a b)') size expected: 7.

"AC-2 the Phase 1 corpus: the inputs of tests/phase-1-reader-printer.st"
corpus := OrderedCollection new.
corpus addAll: #('42' '-3' '+7' '0' '3.14' '.5' '2.' '-1e9' '"hi"' '"a\nb"' '"a\"b"'
	'#t' '#true' '#f' '#false' '#\a' '#\space' '#\newline' '#\x41'
	'foo' 'set!!' '+' '->x' '...' 'Foo' '+1' '()' '(1 2 3)' '(1 . 2)' '(1 (2 3) 4)' '''x'
	'   (1   2)   ' '#| a #| b |# c |# 2' '1 2 3' '   ' '1 2' ''
	'"abc' '(1 2' '1)' '( . a )' '( a . )' '( a . b c )' '#q'
	'(a (1 2) 3)' '0.1' '1.0e100' '-3.14159' '1.0e-10' '1.5' '100.0').
corpus add: '; hi' , lf , ' 1'.
corpus keysAndValuesDo: [:i :src | compare value: 'AC-2 Phase 1 corpus #' , i printString value: src].

"AC-2 every later reader feature and error"
corpus := OrderedCollection new.
corpus addAll: #(
	"numbers and symbols"
	'-0.0' '+.5' '1e' '1e+' '1.5e-3' '1E3' '-' '1+' '12345678901234567890' '-.5e2' '1.0e400' '.e1' '+-1' '0x10'
	"strings and escapes"
	'"\t\r\0\a\b\\"' '"\x41;\x3bb;"' '"\x;"' '"\xZ;"' '"\x110000;"' '"\q"' '"abc\' '"\x41' '"λ"'
	"characters"
	'#\(' '#\)' '#\;' '#\xZZ' '#\x110000' '#\foo' '#\' '#\λ' '#\X41' '#\x' '#\tab #\return #\null'
	"hash syntax"
	'#' '#tru' '#t#f' '#(' '#(1 . 2)' '#()' '#(1 #(2) "s" #\c)' '#(a (b c) . d)'
	"datum labels"
	'#0=(a . #0#)' '#0=#(x #0#)' '#1#' '#1x' '#0=(#0# #0#)' '(#0=(1) #0#)' '#12=12' '#0='
	"lists, dots, abbreviations"
	'.' '(a .b)' '(a . b . c)' '(a .)' '(. b)' '(a . b' '`(a ,b ,@c)' ',' ''''  '(quote)' '()()' '((()))'
	"brackets"
	'[a foo]' '[Foo bar: 1 baz: 2]' '[1 + 2]' '[x]' '[x 1 2]' '[a' ']' '[a foo: 1 bar]' '[a b c d]'
	'[(f) <= 3]' '[OrderedCollection new]' '[s matchesRegex: "x"]' '[]' '[a foo:]' '[a 1]'
	"comments and token ends"
	'a#|c|#b' '#|unterminated' '#| #| |#' 'abc;x' 'a"b"' 'a(b)' 'x#y' '#|a|##t')
	asOrderedCollection.
corpus add: '(a ; comment' , lf , ' b)'.
corpus add: '#;' , lf.
corpus add: (String with: Character tab with: (Character value: 12) with: Character cr) , 'x'.
corpus keysAndValuesDo: [:i :src | compare value: 'AC-2 feature #' , i printString value: src].

"AC-2 every .lisp file in the repository (all but the VM and node_modules)"
skip := [:f | (f pathString includesSubstring: 'node_modules') or: [(f relativeTo: root) segments first = 'pharo']].
files := ((root allChildrenMatching: '*.lisp') reject: skip) asSortedCollection: [:x :y | x pathString <= y pathString].
count := 0.
files do: [:f |
	count := count + 1.
	compare value: 'AC-2 file ' , (f relativeTo: root) pathString value: f contents].
h check: 'AC-2 the repository has .lisp files to compare' actual: count > 50 expected: true.

h finish
] on: Error do: [:e | h harnessError: e].
!
