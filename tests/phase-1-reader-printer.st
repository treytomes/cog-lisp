"============================================================================
 cog-lisp : Phase 1 acceptance suite  (specs/phase-1-reader-printer.md, AC-1..23)
 Headless; prints PASS/FAIL per check and a final RESULT line, then quits.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-1-reader-printer.st
 ============================================================================"

"--- Chunk 1: load the implementation into this fresh image -----------------"
| srcFile |
srcFile := Smalltalk imageDirectory parent / 'src' / 'coglisp-reader.st'.
srcFile exists
	ifTrue: [srcFile fileIn]
	ifFalse: [Stdio stdout nextPutAll: 'SOURCE NOT FOUND: ' , srcFile pathString; nextPut: Character lf; flush].
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| out pass total eq check checkErr rd sp |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
pass := 0.
total := 0.
sp := [:v | [LispPrinter writeString: v] on: Error do: [:e | v printString]].

"recursive structural equality (equal?-style), Phase-1 test helper"
eq := nil.
eq := [:a :b |
	a == b
		ifTrue: [true]
		ifFalse: [
			((a isKindOf: LispCons) and: [b isKindOf: LispCons])
				ifTrue: [(eq value: a car value: b car) and: [eq value: a cdr value: b cdr]]
				ifFalse: [
					((a isKindOf: String) and: [b isKindOf: String])
						ifTrue: [a = b]
						ifFalse: [
							(a isNumber and: [b isNumber])
								ifTrue: [(a class = b class) and: [a = b]]
								ifFalse: [a = b]]]]].

check := [:label :actual :expected |
	total := total + 1.
	(eq value: actual value: expected)
		ifTrue: [pass := pass + 1. out value: '  PASS  ' , label]
		ifFalse: [out value: '  FAIL  ' , label , '  got=' , (sp value: actual) , '  want=' , (sp value: expected)]].

checkErr := [:label :blk |
	total := total + 1.
	[blk value. out value: '  FAIL  ' , label , ' (no error raised)']
		on: LispReadError
		do: [:e | pass := pass + 1. out value: '  PASS  ' , label]].

rd := [:s | LispReader read: s].

[
out value: '== cog-lisp Phase 1 : reader & printer =='.

"AC-1 integers"
check value: 'AC-1 int 42' value: (rd value: '42') value: 42.
check value: 'AC-1 int -3' value: (rd value: '-3') value: -3.
check value: 'AC-1 int +7' value: (rd value: '+7') value: 7.

"AC-2 reals"
check value: 'AC-2 float 3.14' value: (rd value: '3.14') value: 3.14.
check value: 'AC-2 float .5' value: (rd value: '.5') value: 0.5.
check value: 'AC-2 float 2.' value: (rd value: '2.') value: 2.0.
check value: 'AC-2 float -1e9' value: (rd value: '-1e9') value: -1.0e9.

"AC-3 strings"
check value: 'AC-3 string hi' value: (rd value: '"hi"') value: 'hi'.
check value: 'AC-3 string nl escape' value: (rd value: '"a\nb"') value: (String with: $a with: Character lf with: $b).
check value: 'AC-3 string quote escape' value: (rd value: '"a\"b"') value: (String with: $a with: $" with: $b).

"AC-4 booleans"
check value: 'AC-4 #t' value: (rd value: '#t') value: true.
check value: 'AC-4 #true' value: (rd value: '#true') value: true.
check value: 'AC-4 #f' value: (rd value: '#f') value: false.
check value: 'AC-4 #false' value: (rd value: '#false') value: false.

"AC-5 characters"
check value: 'AC-5 #\a' value: (rd value: '#\a') value: $a.
check value: 'AC-5 #\space' value: (rd value: '#\space') value: Character space.
check value: 'AC-5 #\newline' value: (rd value: '#\newline') value: Character lf.
check value: 'AC-5 #\x41' value: (rd value: '#\x41') value: $A.

"AC-6 symbols"
check value: 'AC-6 foo isSymbol' value: ((rd value: 'foo') isKindOf: LispSymbol) value: true.
check value: 'AC-6 foo name' value: (rd value: 'foo') name value: 'foo'.
check value: 'AC-6 set!! isSymbol' value: ((rd value: 'set!!') isKindOf: LispSymbol) value: true.
check value: 'AC-6 + isSymbol' value: ((rd value: '+') isKindOf: LispSymbol) value: true.
check value: 'AC-6 ->x isSymbol' value: ((rd value: '->x') isKindOf: LispSymbol) value: true.
check value: 'AC-6 ... isSymbol' value: ((rd value: '...') isKindOf: LispSymbol) value: true.

"AC-7 interning + case sensitivity"
check value: 'AC-7 interned identity' value: ((rd value: 'foo') == (rd value: 'foo')) value: true.
check value: 'AC-7 case sensitive' value: ((rd value: 'Foo') == (rd value: 'foo')) value: false.

"AC-8 number vs symbol"
check value: 'AC-8 + is symbol' value: ((rd value: '+') isKindOf: LispSymbol) value: true.
check value: 'AC-8 +1 is number' value: (rd value: '+1') value: 1.

"AC-9 empty list"
check value: 'AC-9 () is empty singleton' value: ((rd value: '()') == LispEmptyList default) value: true.
check value: 'AC-9 () is not false' value: ((rd value: '()') == false) value: false.

"AC-10 proper list"
check value: 'AC-10 (1 2 3) proper' value: (rd value: '(1 2 3)') isProperList value: true.
check value: 'AC-10 (1 2 3) length' value: (rd value: '(1 2 3)') lispElements size value: 3.
check value: 'AC-10 (1 2 3) elements' value: (rd value: '(1 2 3)') lispElements asArray value: #(1 2 3).

"AC-11 dotted pair"
check value: 'AC-11 (1 . 2) car' value: (rd value: '(1 . 2)') car value: 1.
check value: 'AC-11 (1 . 2) cdr' value: (rd value: '(1 . 2)') cdr value: 2.

"AC-12 nesting"
check value: 'AC-12 nested inner is list' value: (((rd value: '(1 (2 3) 4)') lispElements at: 2) isKindOf: LispCons) value: true.
check value: 'AC-12 nested inner elements' value: ((rd value: '(1 (2 3) 4)') lispElements at: 2) lispElements asArray value: #(2 3).
check value: 'AC-12 outer length' value: (rd value: '(1 (2 3) 4)') lispElements size value: 3.

"AC-13 quote abbreviation"
check value: 'AC-13 ''x => (quote x)'
	value: (rd value: '''x')
	value: (LispCons fromArray: { LispSymbol named: 'quote'. LispSymbol named: 'x' }).

"AC-14 whitespace"
check value: 'AC-14 whitespace ignored' value: (rd value: '   (1   2)   ') lispElements asArray value: #(1 2).

"AC-15 comments"
check value: 'AC-15 line comment' value: (rd value: ('; hi' , (String with: Character lf) , ' 1')) value: 1.
check value: 'AC-15 nested block comment' value: (rd value: '#| a #| b |# c |# 2') value: 2.

"AC-16 readAll"
check value: 'AC-16 readAll size' value: (LispReader readAll: '1 2 3') size value: 3.
check value: 'AC-16 readAll elements' value: (LispReader readAll: '1 2 3') asArray value: #(1 2 3).

"AC-17 reader protocol"
checkErr value: 'AC-17 read empty signals' value: [LispReader read: '   '].
checkErr value: 'AC-17 read two signals' value: [LispReader read: '1 2'].
check value: 'AC-17 next at end = eof' value: ((LispReader on: '') next == LispReader eofObject) value: true.
check value: 'AC-17 readAll empty' value: (LispReader readAll: '') size value: 0.

"AC-18..21 errors"
checkErr value: 'AC-18 unterminated string' value: [LispReader read: '"abc'].
checkErr value: 'AC-19 unterminated list' value: [LispReader read: '(1 2'].
checkErr value: 'AC-19 stray close' value: [LispReader read: '1)'].
checkErr value: 'AC-20 dotted empty head' value: [LispReader read: '( . a )'].
checkErr value: 'AC-20 dotted no tail' value: [LispReader read: '( a . )'].
checkErr value: 'AC-20 dotted extra' value: [LispReader read: '( a . b c )'].
checkErr value: 'AC-21 unknown hash' value: [LispReader read: '#q'].

"AC-22 round trip corpus"
(Array
	with: 42 with: -3 with: 0 with: 3.14) ,
(Array
	with: 'hello' with: (String with: $a with: Character lf with: $b)
	with: true with: false) ,
(Array
	with: $a with: Character space
	with: (LispSymbol named: 'foo') with: (LispSymbol named: 'set!!')) ,
(Array
	with: LispEmptyList default
	with: (LispCons fromArray: { 1. 2. 3 })
	with: (LispCons fromArray: { LispSymbol named: 'a'. LispCons fromArray: { 1. 2 }. 3 })
	with: (LispCons car: 1 cdr: 2))
		keysAndValuesDo: [:i :d |
			check value: 'AC-22 roundtrip #' , i printString
				value: (LispReader read: (LispPrinter writeString: d))
				value: d].

"AC-23 float round trip exactness"
{ 0.1. 1.0e100. -3.14159. 1.0e-10. 1.5. 100.0 } keysAndValuesDo: [:i :f |
	check value: 'AC-23 float roundtrip #' , i printString
		value: (LispReader read: (LispPrinter writeString: f))
		value: f].

out value: ''.
out value: '== RESULT: ' , pass printString , '/' , total printString , ' checks passed =='
]
	on: Error
	do: [:e | out value: 'HARNESS ERROR: ' , e class name , ': ' , e messageText printString].

Smalltalk snapshot: false andQuit: true.
!
