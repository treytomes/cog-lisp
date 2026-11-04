"============================================================================
 cog-lisp : Phase 7.9 acceptance suite (specs/phase-7.9-self-hosting-groundwork.md)
 AC-1..12. The runner suite covers (command-line) and stdin in programs
 (examples/program, examples/echo); run-all.bat runs tests/lisp (AC-13).
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
| h root ev w msg dump corpus nest captured |
h := LispTestHarness new.
root := Smalltalk imageDirectory parent.
ev := [:s | LispCompiler new evalAll: s].
w := [:s | LispPrinter writeString: (ev value: s)].
msg := [:s | [ev value: s. #none] on: Error do: [:e | LispError describe: e]].
captured := [:blk | String streamContents: [:o | LispPrimitives withOutput: o do: blk]].

[
h say: '== cog-lisp Phase 7.9 : self-hosting groundwork =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (root / 'lib' / 'core.lisp') fullName.

"AC-1 deep code compiles"
nest := [:depth :inner | (1 to: depth) inject: inner into: [:acc :i | '(+ 1 ' , acc , ')']].
h check: 'AC-1 a call nested 200 deep' actual: (ev value: (nest value: 200 value: '0')) expected: 200.
h check: 'AC-1 a list of 100 nested conses' actual: (ev value: '(length ' , ((1 to: 100) inject: '(quote ())' into: [:acc :i | '(cons ' , i printString , ' ' , acc , ')']) , ')') expected: 100.
h check: 'AC-1 50 nested lets in a cond'
	actual: (ev value: ([| inner |
		inner := 'x50'.
		50 to: 1 by: -1 do: [:i | inner := '(let ((x' , i printString , ' (+ x' , (i - 1) printString , ' 1))) ' , inner , ')'].
		'(let ((x0 0)) (cond (#f 0) (else ' , inner , ')))'] value))
	expected: 50.
h check: 'AC-1 deep nesting inside a procedure, called repeatedly'
	actual: (ev value: '(define (deep n) ' , (nest value: 60 value: 'n') , ') (list (deep 0) (deep 5))')
	expected: (LispReader read: '(60 65)').

"AC-2 code within the budget compiles exactly as before"
dump := nil.
dump := [:code :s | s nextPutAll: code symbolic; nextPut: Character lf.
	code literals do: [:lit |
		(lit isKindOf: CompiledBlock) ifTrue: [dump value: lit value: s].
		(lit isKindOf: BlockClosure) ifTrue: [dump value: lit compiledBlock value: s]]].
corpus := String streamContents: [:s | | r d |
	r := LispReader on: (root / 'tests' / 'bytecode-corpus.lisp') contents.
	[(d := r next) == LispReader eofObject] whileFalse: [
		s nextPutAll: '=== '; nextPutAll: (LispPrinter writeString: d); nextPut: Character lf.
		dump value: (LispCompiler new compile: d) value: s]].
h check: 'AC-2 the bytecode corpus is unchanged (tests/bytecode-corpus.expected)'
	actual: corpus = (root / 'tests' / 'bytecode-corpus.expected') contents
	expected: true.

"AC-3 many parameters"
#(16 20 40) do: [:k | | params |
	params := String streamContents: [:s | 1 to: k do: [:i | s nextPutAll: ' p' , i printString]].
	h check: 'AC-3 ' , k printString , ' parameters'
		actual: (ev value: '((lambda (' , params , ') (list p1 p' , k printString , ')) ' , ((1 to: k) inject: '' into: [:a :i | a , ' ' , i printString]) , ')')
		expected: (LispReader read: '(1 ' , k printString , ')')].
h check: 'AC-3 20 plus a rest parameter'
	actual: (ev value: '((lambda (a b c d e f g h i j k l m n o p q r s t . more) (list a t more)) 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22)')
	expected: (LispReader read: '(1 20 (21 22))').
h check: 'AC-3 arity is checked' actual: (msg value: '(define (f20 a b c d e f g h i j k l m n o p q r s t) a) (f20 1 2)') expected: 'f20: expected 20 arguments, got 2'.
h check: 'AC-3 a 20-parameter procedure tail-calling itself 100000 times'
	actual: (ev value: '(define (loop20 n a b c d e f g h i j k l m n2 o p q r s) (if (= n 0) a (loop20 (- n 1) (+ a 1) b c d e f g h i j k l m n2 o p q r s))) (loop20 100000 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)')
	expected: 100000.
h check: 'AC-3 a call with 30 arguments to a 30-parameter procedure'
	actual: (ev value: '((lambda (' , ((1 to: 30) inject: '' into: [:a :i | a , ' p' , i printString]) , ') (+ ' , ((1 to: 30) inject: '' into: [:a :i | a , ' p' , i printString]) , ')) ' , ((1 to: 30) inject: '' into: [:a :i | a , ' 1']) , ')')
	expected: 30.

"AC-4 file ports (files land beside the loading file, else the current directory)"
h check: 'AC-4 write, then read lines and data'
	actual: (w value: '(call-with-output-file "phase79.tmp" (lambda (p) (display "line one" p) (newline p) (write (list 1 "two") p) (newline p))) (call-with-input-file "phase79.tmp" (lambda (p) (list (read-line p) (read p) (eof-object? (read p)))))')
	expected: '("line one" (1 "two") #t)'.
h check: 'AC-4 read-char and peek-char on a file' actual: (w value: '(call-with-input-file "phase79.tmp" (lambda (p) (list (peek-char p) (read-char p) (read-char p))))') expected: '(#\l #\l #\i)'.
h check: 'AC-4 with-output-to-file and with-input-from-file' actual: (w value: '(with-output-to-file "phase79.tmp" (lambda () (display "replaced"))) (with-input-from-file "phase79.tmp" read-line)') expected: '"replaced"'.
h check: 'AC-4 file-exists? and delete-file' actual: (w value: '(list (file-exists? "phase79.tmp") (begin (delete-file "phase79.tmp") (file-exists? "phase79.tmp")))') expected: '(#t #f)'.
h check: 'AC-4 a missing file is a file-error' actual: (w value: '(guard (e ((file-error? e) (error-object-message e))) (open-input-file "no-such.tmp"))') expected: '"open-input-file: file not found: no-such.tmp"'.
h check: 'AC-4 open-output-file and close-port' actual: (w value: '(let ((p (open-output-file "phase79.tmp"))) (write-string "x" p) (close-port p) (let ((r (call-with-input-file "phase79.tmp" read-line))) (delete-file "phase79.tmp") r))') expected: '"x"'.

"AC-5 reading the current input"
h check: 'AC-5 read, read-line and read-char with no port'
	actual: (LispPrimitives withInput: (LispInputPort onStream: (LispLineStream on: (ReadStream on: ('(a b) 42' , String lf , 'next line' , String lf , 'xyz' , String lf))))
		do: [w value: '(list (read) (read) (read-line) (read-line) (read-char) (eof-object? (begin (read-line) (read-char))))'])
	expected: '((a b) 42 "" "next line" #\x #t)'.
h check: 'AC-5 the REPL feeds read the lines typed after the form'
	actual: ([:input | | o | o := WriteStream on: String new.
		(LispRepl in: input readStream out: o err: (WriteStream on: String new)) run. o contents]
		value: '(list (quote got) (read-line))
typed by the user
')
	expected: '> (got "typed by the user")' , String lf , '> ' , String lf.

"AC-6 load relative to the loading file"
LispPrimitives commandLine: #('main.lisp' 'arg').
h check: 'AC-6 a two-file program finds its library beside it'
	actual: ((captured value: [LispCompiler new evalFile: (root / 'examples' / 'program' / 'main.lisp') fullName])
		includesSubstring: 'loaded util.lisp')
	expected: true.
h check: 'AC-6 current-load-path is #f outside a load' actual: (w value: '(current-load-path)') expected: '#f'.

"AC-8 equal? on cycles"
ev value: '(define (circ . xs) (let ((l (apply list xs))) (let lp ((p l)) (if (pair? (cdr p)) (lp (cdr p)) (set-cdr!! p l))) l))'.
h check: 'AC-8 equal cyclic lists' actual: (w value: '(list (equal? (circ 1 2) (circ 1 2)) (equal? (circ 1 2) (circ 1 2 1 2)))') expected: '(#t #t)'.
h check: 'AC-8 different cyclic lists' actual: (w value: '(list (equal? (circ 1 2) (circ 2 1)) (equal? (circ 1) (list 1)))') expected: '(#f #f)'.
h check: 'AC-8 a cyclic vector' actual: (w value: '(let ((a (vector 1 0)) (b (vector 1 0))) (vector-set!! a 1 a) (vector-set!! b 1 b) (equal? a b))') expected: '#t'.
h check: 'AC-8 long acyclic lists unchanged' actual: (w value: '(let ((a (vector->list (make-vector 5000 7))) (b (vector->list (make-vector 5000 7)))) (list (equal? a b) (equal? a (cons 8 (cdr b)))))') expected: '(#t #f)'.

"AC-9 datum labels"
h check: 'AC-9 a cyclic list' actual: (w value: '(circ 1 2 3)') expected: '#0=(1 2 3 . #0#)'.
h check: 'AC-9 a cyclic vector' actual: (w value: '(let ((v (vector 1 2))) (vector-set!! v 1 v) v)') expected: '#0=#(1 #0#)'.
h check: 'AC-9 a list whose car is itself' actual: (w value: '(let ((l (list 1))) (set-car!! l l) l)') expected: '#0=(#0#)'.
h check: 'AC-9 two cycles' actual: (w value: '(list (circ 1) (circ 2))') expected: '(#0=(1 . #0#) #1=(2 . #1#))'.
h check: 'AC-9 sharing alone is not labelled by write' actual: (w value: '(let ((s (list 1))) (list s s))') expected: '((1) (1))'.
h check: 'AC-9 ... but is by write-shared' actual: (captured value: [ev value: '(let ((s (list 1))) (write-shared (list s s)))']) expected: '(#0=(1) #0#)'.
h check: 'AC-9 read of a label round-trips' actual: (w value: '(let ((c (read (open-input-string "#0=(a b . #0#)")))) (list (car c) (eq? c (cdr (cdr c))) (equal? c (circ (quote a) (quote b)))))') expected: '(a #t #t)'.
h check: 'AC-9 a labelled vector reads back' actual: (w value: '(let ((v (read (open-input-string "#0=#(x #0#)")))) (eq? v (vector-ref v 1)))') expected: '#t'.
h check: 'AC-9 an unknown label' actual: ([LispReader read: '#3#'. #none] on: LispReadError do: [:e | e messageText]) expected: 'unknown datum label #3#'.
h check: 'AC-9 display of a cycle' actual: (LispPrinter displayString: (ev value: '(circ "a")')) expected: '#0=(a . #0#)'.

"AC-10 string escapes"
h check: 'AC-10 \x...; reads any character' actual: (w value: '(list (string-length "\x3bb;") (char->integer (string-ref "\x3bb;" 0)) (char->integer (string-ref "\x41;" 0)))') expected: '(1 955 65)'.
h check: 'AC-10 \a and \b' actual: (w value: '(map char->integer (string->list "\a\b"))') expected: '(7 8)'.
h check: 'AC-10 control characters write as \x..;' actual: (w value: '(string (integer->char 1) (integer->char 27) #\tab)') expected: '"\x1;\x1b;\t"'.
h check: 'AC-10 and read back' actual: (w value: '(let ((s (string (integer->char 1) #\" #\\ (integer->char 127)))) (equal? s (read (open-input-string (with-output-to-string (lambda () (write s)))))))') expected: '#t'.
h check: 'AC-10 a bad \x escape' actual: ([LispReader read: '"\xZZ;"'. #none] on: LispReadError do: [:e | e messageText]) expected: 'bad \x escape: expected hex digits and ;'.

"AC-11 compiler structure"
h check: 'AC-11 special forms dispatch through the table' actual: (LispCompiler specialForms size) expected: 11.
h check: 'AC-11 message templates are cached' actual: ((LispCompiler classPool at: #TemplateCache) notNil and: [(LispCompiler classPool at: #TemplateCache) notEmpty]) expected: true.

"AC-12 the LISP test framework, run on tests with known failures"
LispCompiler new evalFile: (root / 'lib' / 'test.lisp') fullName.
ev value: '(define-test passes (check (+ 1 2) 3) (check-true (< 1 2)) (check-error (car 5) "not a pair"))
	(define-test fails (check (+ 1 2) 4) (check-false 1) (check-error 5) (check-error (car 5) "zzz"))
	(define-test crashes (check 1 1) (car 5) (check 2 2))'.
h check: 'AC-12 counts: 9 checks, 4 failures, 1 unexpected error'
	actual: ([:out | (out includesSubstring: '== RESULT: 4/9 checks passed ==')] value: (captured value: [ev value: '(run-tests/report)']))
	expected: true.
captured value: [ev value: '(set!! %pass 0) (set!! %total 0)'].
h check: 'AC-12 a failing check shows what it got and wanted'
	actual: ((captured value: [ev value: '(run-tests/report)']) includesSubstring: 'FAIL  fails: (+ 1 2)  got=3  want=4')
	expected: true.
captured value: [ev value: '(set!! %pass 0) (set!! %total 0)'].
h check: 'AC-12 an error inside a test fails that test only, with its message'
	actual: ([:out | (out includesSubstring: 'FAIL  crashes: unexpected error  car: not a pair: 5') and: [out includesSubstring: 'PASS  passes']]
		value: (captured value: [ev value: '(run-tests/report)']))
	expected: true.

h finish
] on: Error do: [:e | h harnessError: e].
!
