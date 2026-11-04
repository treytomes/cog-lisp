"============================================================================
 cog-lisp : Phase 7.8 acceptance suite  (specs/phase-7.8-native-data.md,
 AC-1..11). AC-12 is every other suite; the examples (strings, vectors,
 hash-tables, string-ports, tiny-reader) run in the runner suite.
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
h check: 'AC-1 char->integer, integer->char (lambda)' actual: (w value: '(list (char->integer #\A) (char->integer (integer->char 955)) (char? (integer->char 955)))') expected: '(65 955 #t)'.
h check: 'AC-1 comparisons, chained' actual: (w value: '(list (char<? #\a #\b #\c) (char<? #\a #\c #\b) (char=? #\x #\x) (char-ci=? #\A #\a) (char>=? #\b #\a))') expected: '(#t #f #t #t #t)'.
h check: 'AC-1 classes' actual: (w value: '(list (char-alphabetic? #\a) (char-numeric? #\7) (char-whitespace? #\space) (char-upper-case? #\A) (char-lower-case? #\A))') expected: '(#t #t #t #t #f)'.
h check: 'AC-1 case and digits' actual: (w value: '(list (char-upcase #\a) (char-downcase #\B) (digit-value #\7) (digit-value #\x))') expected: '(#\A #\b 7 #f)'.

"AC-2 strings"
h check: 'AC-2 make-string, string, length, ref' actual: (w value: '(list (make-string 3 #\z) (string #\a #\b) (string-length "hello") (string-ref "hello" 1))') expected: '("zzz" "ab" 5 #\e)'.
h check: 'AC-2 substring and string-copy with optional ranges' actual: (w value: '(list (substring "hello" 1 3) (substring "hello" 2) (string-copy "hello" 1 2) (string-copy "hi"))') expected: '("el" "llo" "e" "hi")'.
h check: 'AC-2 append, ->list, list->' actual: (w value: '(list (string-append "a" "b" "c") (string->list "abc" 1) (list->string (list #\x #\y)) (string-append))') expected: '("abc" (#\b #\c) "xy" "")'.
h check: 'AC-2 symbols' actual: (w value: '(list (eq? (string->symbol "foo") (quote foo)) (symbol->string (quote bar)))') expected: '(#t "bar")'.
h check: 'AC-2 comparisons' actual: (w value: '(list (string=? "a" "a" "a") (string<? "apple" "banana") (string<? "b" "a") (string>? "b" "a") (string<=? "a" "a") (string-ci=? "AbC" "aBc") (string<? "Z" "a"))') expected: '(#t #t #f #t #t #t #t)'.
h check: 'AC-2 conveniences' actual: (w value: '(list (string-upcase "ab") (string-index "hello" #\l) (string-index "hello" #\z) (string-search "hello" "lo") (string-split "a,,b" #\,) (string-join (list "x" "y") "+") (string-trim "  t  "))') expected: '("AB" 2 #f 3 ("a" "" "b") "x+y" "t")'.
h check: 'AC-2 number->string' actual: (w value: '(list (number->string 42) (number->string 255 16) (number->string 2.5))') expected: '("42" "ff" "2.5")'.

"AC-3 mutation"
h check: 'AC-3 string-set!! on a made string' actual: (w value: '(let ((s (make-string 3 #\a))) (string-set!! s 1 #\b) s)') expected: '"aba"'.
h check: 'AC-3 a wide character into a byte string' actual: (w value: '(let ((s (string-copy "abc"))) (string-set!! s 0 (integer->char 955)) (list (char->integer (string-ref s 0)) (string-length s) (string-ref s 1)))') expected: '(955 3 #\b)'.
h check: 'AC-3 fill!! and copy!!' actual: (w value: '(let ((s (make-string 4 #\-)) (t (make-string 3 #\.))) (string-copy!! s 1 "xy") (string-fill!! t #\o) (list s t))') expected: '("-xy-" "ooo")'.
h check: 'AC-3 string-set!! on a literal is an error' actual: (msg value: '(string-set!! "lit" 0 #\x)') expected: 'string-set!!: string is immutable (a literal); copy it first'.

"AC-4 string->number"
h check: 'AC-4 numbers and not' actual: (w value: '(list (string->number "42") (string->number "-7") (string->number "2.5") (string->number "1e3") (string->number "x") (string->number "") (string->number "1 2") (string->number "ff" 16) (string->number "-101" 2) (string->number "9" 8))') expected: '(42 -7 2.5 1000.0 #f #f #f 255 -5 #f)'.
h check: 'AC-4 -0.0 keeps its sign' actual: (ev value: '(string->number "-0.0")') signBit expected: 1.

"AC-5 vector syntax"
h check: 'AC-5 #( ) reads as an Array' actual: (lst value: '#(1 "x" (a))') class expected: Array.
h check: 'AC-5 self-evaluating, quoted or not' actual: (w value: '(list #(1 2) (quote #(a b)) #())') expected: '(#(1 2) #(a b) #())'.
h check: 'AC-5 round trip' actual: (LispPrinter writeString: (lst value: (LispPrinter writeString: (lst value: '#(1 #(2) "s" #\c)')))) expected: '#(1 #(2) "s" #\c)'.
h check: 'AC-5 equal? and eqv?' actual: (w value: '(list (equal? #(1 (2)) (vector 1 (list 2))) (equal? #(1) #(2)) (eqv? (vector 1) (vector 1)))') expected: '(#t #f #f)'.
h check: 'AC-5 a dotted vector is a read error' actual: ([lst value: '#(1 . 2)'. #none] on: LispReadError do: [:e | e messageText]) expected: 'bad vector: a dotted tail'.

"AC-6 vector procedures"
h check: 'AC-6 construct and inspect' actual: (w value: '(list (make-vector 2 0) (vector 1 2) (vector-length #(1 2 3)) (vector-ref #(a b) 1) (vector? #(1)) (vector? (list 1)))') expected: '(#(0 0) #(1 2) 3 b #t #f)'.
h check: 'AC-6 conversions with ranges' actual: (w value: '(list (vector->list #(1 2 3 4) 1 3) (list->vector (list 1 2)) (vector-copy #(1 2 3) 1) (subvector #(1 2 3 4) 1 3) (vector-append #(1) #() #(2 3)))') expected: '((2 3) #(1 2) #(2 3) #(2 3) #(1 2 3))'.
h check: 'AC-6 set!!, fill!!, map, for-each'
	actual: (w value: '(let ((v (make-vector 3 0)) (acc 0)) (vector-set!! v 0 5) (vector-for-each (lambda (x) (set!! acc (+ acc x))) v) (list v (vector-map (lambda (x) (* 2 x)) v) acc (begin (vector-fill!! v 1) v)))')
	expected: '(#(1 1 1) #(10 0 0) 5 #(1 1 1))'.
h check: 'AC-6 vector-set!! on a literal is an error' actual: (msg value: '(vector-set!! #(1 2) 0 9)') expected: 'vector-set!!: vector is immutable (a literal); copy it first'.
h check: 'AC-6 list->array is still there and makes a vector' actual: (w value: '(vector? (list->array (list 1 2)))') expected: '#t'.

"AC-7 quasiquote over vectors"
h check: 'AC-7 unquote and splicing' actual: (w value: '(let ((x 1) (ys (list 2 3))) `#(0 ,x ,@ys 4))') expected: '#(0 1 2 3 4)'.
h check: 'AC-7 a constant vector template' actual: (w value: '`#(a b)') expected: '#(a b)'.
h check: 'AC-7 nested in a list' actual: (w value: '(let ((x 5)) `(v #(,x)))') expected: '(v #(5))'.

"AC-8 hash tables"
h check: 'AC-8 equal? keys' actual: (w value: '(let ((t (make-hash-table))) (hash-table-set!! t "k" 1) (hash-table-set!! t (list 1 2) 2) (hash-table-set!! t 3 3) (hash-table-set!! t #(1) 4) (list (hash-table-ref t (string-copy "k")) (hash-table-ref t (list 1 2)) (hash-table-ref t 3) (hash-table-ref t (vector 1))))') expected: '(1 2 3 4)'.
h check: 'AC-8 eq? table: distinct strings are different keys' actual: (w value: '(let ((t (make-hash-table eq?))) (hash-table-set!! t (string-copy "k") 1) (hash-table-contains? t (string-copy "k")))') expected: '#f'.
h check: 'AC-8 eqv? table: numbers by value, 1 and 1.0 differ' actual: (w value: '(let ((t (make-hash-table eqv?))) (hash-table-set!! t 1 (quote int)) (list (hash-table-ref/default t 1 #f) (hash-table-ref/default t 1.0 #f)))') expected: '(int #f)'.
h check: 'AC-8 ref with a thunk, and missing' actual: (w value: '(let ((t (make-hash-table))) (list (hash-table-ref t 1 (lambda () (quote dflt))) (hash-table-ref/default t 1 0)))') expected: '(dflt 0)'.
h check: 'AC-8 missing without a default is an error' actual: (msg value: '(hash-table-ref (make-hash-table) (quote k))') expected: 'hash-table-ref: no key: k'.
h check: 'AC-8 insertion order of keys, values, alist'
	actual: (w value: '(let ((t (make-hash-table))) (for-each (lambda (k) (hash-table-set!! t k (* k 10))) (list 5 1 9 3)) (list (hash-table-keys t) (hash-table-values t) (hash-table->alist t)))')
	expected: '((5 1 9 3) (50 10 90 30) ((5 . 50) (1 . 10) (9 . 90) (3 . 30)))'.
h check: 'AC-8 update!!, update!!/default, delete!!, count, clear!!'
	actual: (w value: '(let ((t (make-hash-table))) (hash-table-set!! t (quote a) 1) (hash-table-update!! t (quote a) (lambda (v) (+ v 1))) (hash-table-update!!/default t (quote b) (lambda (v) (+ v 1)) 10) (hash-table-delete!! t (quote zz)) (let ((before (list (hash-table-ref t (quote a)) (hash-table-ref t (quote b)) (hash-table-count t)))) (hash-table-clear!! t) (list before (hash-table-count t))))')
	expected: '((2 11 2) 0)'.
h check: 'AC-8 walk, copy, alist->hash-table, printing'
	actual: (w value: '(let* ((t (alist->hash-table (quote ((a . 1) (b . 2) (a . 9))) eq?)) (c (hash-table-copy t)) (sum 0)) (hash-table-set!! c (quote z) 26) (hash-table-walk t (lambda (k v) (set!! sum (+ sum v)))) (list t (hash-table-count c) sum (hash-table-ref t (quote a)) (hash-table? t)))')
	expected: '(#<hash-table 2> 3 3 1 #t)'.
h check: 'AC-8 an unsupported equality' actual: (msg value: '(make-hash-table string=?)') expected: 'make-hash-table: the equality must be eq?, eqv? or equal?: #<procedure string=?>'.

"AC-9 string ports"
h check: 'AC-9 read-char, peek-char, read-line, eof'
	actual: (w value: '(let ((p (open-input-string "ab\ncd"))) (list (peek-char p) (read-char p) (read-line p) (read-line p) (eof-object? (read-line p)) (eof-object? (read-char p))))')
	expected: '(#\a #\a "b" "cd" #t #t)'.
h check: 'AC-9 read-string' actual: (w value: '(let ((p (open-input-string "abcdef"))) (list (read-string 4 p) (read-string 9 p) (eof-object? (read-string 1 p))))') expected: '("abcd" "ef" #t)'.
h check: 'AC-9 read several datums, then eof'
	actual: (w value: '(let ((p (open-input-string "(1 2) foo \"s\" #(v)"))) (list (read p) (read p) (read p) (read p) (eof-object? (read p))))')
	expected: '((1 2) foo "s" #(v) #t)'.
h check: 'AC-9 output port: display, write, write-char, newline'
	actual: (w value: '(let ((o (open-output-string))) (display "x" o) (write "y" o) (write-char #\z o) (newline o) (write-string "w" o) (get-output-string o))')
	expected: '"x\"y\"z\nw"'.
h check: 'AC-9 with-output-to-string' actual: (w value: '(with-output-to-string (lambda () (display 1) (display "a")))') expected: '"1a"'.
h check: 'AC-9 the eof object prints' actual: (w value: '(eof-object)') expected: '#<eof>'.
h check: 'AC-9 read without a port reads the current input (none here: eof; Phase 7.9)' actual: (w value: '(eof-object? (read))') expected: '#t'.

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
h check: 'AC-10 guard catches them' actual: (w value: '(guard (e ((error-object? e) (quote caught))) (vector-ref #() 0))') expected: 'caught'.

"AC-11 interop"
h check: 'AC-11 a LISP vector is a Smalltalk Array' actual: (w value: '(list [#(3 1 2) class] (vector? [(smalltalk Array) with: 1 with: 2]) [#(3 1 2) asSortedCollection])') expected: '(#<Array> #t #<a SortedCollection(1 2 3)>)'.
h check: 'AC-11 strings unchanged' actual: (w value: '[(string-append "ab" "c") reversed]') expected: '"cba"'.

h finish
] on: Error do: [:e | h harnessError: e].
!
