"============================================================================
 cog-lisp : Phase 7.8 acceptance suite  (specs/phase-7.8-native-data.md,
 AC-1..11). AC-12 is every other suite; the examples (strings, vectors,
 hash-tables, string-ports, tiny-reader) run in the runner suite.
 Every bang in Lisp text is doubled for the chunk reader.
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h ev lst msg w |
h := LispTestHarness new.
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
msg := [:s | [ev value: s. #none] on: LispError do: [:e | LispError describe: e]].
w := [:s | LispPrinter writeString: (ev value: s)].

[
h say: '== cog-lisp Phase 7.8 : strings, characters, vectors, hash tables =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (Smalltalk imageDirectory parent / 'lib' / 'core.lisp') fullName.

"AC-1 characters"

"AC-2 strings"

"AC-3 mutation"

"AC-4 string->number"

h check: 'AC-4 -0.0 keeps its sign' actual: (ev value: '(string->number "-0.0")') signBit expected: 1.

"AC-5 vector syntax"
h check: 'AC-5 #( ) reads as an Array' actual: (lst value: '#(1 "x" (a))') class expected: Array.

h check: 'AC-5 round trip' actual: (LispPrinter writeString: (lst value: (LispPrinter writeString: (lst value: '#(1 #(2) "s" #\c)')))) expected: '#(1 #(2) "s" #\c)'.

h check: 'AC-5 a dotted vector is a read error' actual: ([lst value: '#(1 . 2)'. #none] on: LispReadError do: [:e | e messageText]) expected: 'bad vector: a dotted tail'.

"AC-6 vector procedures"

[ev value: '(let ((v (make-vector 3 0)) (acc 0)) (vector-set!! v 0 5) (vector-for-each (lambda (x) (set!! acc (+ acc x))) v) (list v (vector-map (lambda (x) (* 2 x)) v) acc (begin (vector-fill!! v 1) v)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.8-native-data.lisp)"

"AC-7 quasiquote over vectors"

"AC-8 hash tables"

[ev value: '(let* ((t (alist->hash-table (quote ((a . 1) (b . 2) (a . 9))) eq?)) (c (hash-table-copy t)) (sum 0)) (hash-table-set!! c (quote z) 26) (hash-table-walk t (lambda (k v) (set!! sum (+ sum v)))) (list t (hash-table-count c) sum (hash-table-ref t (quote a)) (hash-table? t)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.8-native-data.lisp)"

"AC-9 string ports"

"AC-10 errors are LispErrors naming the procedure"
#( '(string-ref "abc" 9)' 'string-ref: index 9 out of range for a string of length 3'
   '(string-ref 5 0)' 'string-ref: not a string: 5'
   '(vector-ref #(1) -1)' 'vector-ref: index -1 out of range for a vector of length 1'
   '(substring "abc" 2 1)' 'substring: bad range 2 to 1 for length 3'
   '(char->integer "a")' 'char->integer: not a character: "a"'
   '(hash-table-ref 5 1)' 'hash-table-ref: not a hash table: 5'
   '(read-char 5)' 'read-char: not an input port: 5'
   '(integer->char -1)' 'integer->char: not a character code: -1'
   '(make-vector -1)' 'make-vector: not a non-negative integer: -1' ) pairsDo: [:src :want |
	h check: 'AC-10 ' , src actual: (msg value: src) expected: want].

"AC-11 interop"


h finish
] on: Error do: [:e | h harnessError: e].
!
