"============================================================================
 cog-lisp : Phase 7.9 acceptance suite (specs/12-phase-7.9-self-hosting-groundwork.md)
 AC-1..12. The runner suite covers (command-line) and stdin in programs
 (examples/program, examples/echo); run-all.bat runs tests/lisp (AC-13).
 Every bang in Lisp text is doubled for the chunk reader.
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h root ev w msg listing corpus nest captured |
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

"AC-2 code within the budget compiles exactly as before. The corpus pins the
 compiler's code by fingerprint (method-listing, lib/compiler/bootstrap.lisp:
 header, bytecode bytes and literals, blocks too). Until Phase 9 step 9.1 it
 pinned the Smalltalk compiler's symbolic listing. Each form starts from the
 same gensym counter, so macro expansions agree. To re-pin after a deliberate
 change to the generated code: COGLISP_REPIN=1 writes the actual listing over
 tests/bytecode-corpus.expected."
listing := LispCompiler new evalString: 'method-listing'.
corpus := String streamContents: [:s | | r d |
	r := LispReader on: (root / 'tests' / 'bytecode-corpus.lisp') contents.
	[(d := r next) == LispReader eofObject] whileFalse: [
		s nextPutAll: '=== '; nextPutAll: (LispPrinter writeString: d); nextPut: Character lf.
		LispPrimitives classPool at: #GensymCounter put: 0.
		s nextPutAll: (LispProcedure apply: listing to: { LispCompiler new compile: d })]].
(OSEnvironment current at: 'COGLISP_REPIN' ifAbsent: ['']) = '1' ifTrue: [
	(root / 'tests' / 'bytecode-corpus.expected') ensureDelete; writeStreamDo: [:w | w nextPutAll: corpus]].
h check: 'AC-2 the bytecode corpus is unchanged (tests/bytecode-corpus.expected)'
	actual: corpus = (root / 'tests' / 'bytecode-corpus.expected') contents
	expected: true.

"AC-3 many parameters"
#(16 20 40) do: [:k | | params |
	params := String streamContents: [:s | 1 to: k do: [:i | s nextPutAll: ' p' , i printString]].
	h check: 'AC-3 ' , k printString , ' parameters'
		actual: (ev value: '((lambda (' , params , ') (list p1 p' , k printString , ')) ' , ((1 to: k) inject: '' into: [:a :i | a , ' ' , i printString]) , ')')
		expected: (LispReader read: '(1 ' , k printString , ')')].

[ev value: '(define (f20 a b c d e f g h i j k l m n o p q r s t) a) (f20 1 2)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.9-groundwork.lisp)"

[ev value: '(define (loop20 n a b c d e f g h i j k l m n2 o p q r s) (if (= n 0) a (loop20 (- n 1) (+ a 1) b c d e f g h i j k l m n2 o p q r s))) (loop20 100000 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7.9-groundwork.lisp)"

h check: 'AC-3 a call with 30 arguments to a 30-parameter procedure'
	actual: (ev value: '((lambda (' , ((1 to: 30) inject: '' into: [:a :i | a , ' p' , i printString]) , ') (+ ' , ((1 to: 30) inject: '' into: [:a :i | a , ' p' , i printString]) , ')) ' , ((1 to: 30) inject: '' into: [:a :i | a , ' 1']) , ')')
	expected: 30.

"AC-4 file ports (files land beside the loading file, else the current directory)"

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

"AC-9 datum labels"

h check: 'AC-9 ... but is by write-shared' actual: (captured value: [ev value: '(let ((s (list 1))) (write-shared (list s s)))']) expected: '(#0=(1) #0#)'.

h check: 'AC-9 an unknown label' actual: ([LispReader read: '#3#'. #none] on: LispReadError do: [:e | e messageText]) expected: 'unknown datum label #3#'.
h check: 'AC-9 display of a cycle' actual: (LispPrinter displayString: (ev value: '(circ "a")')) expected: '#0=(a . #0#)'.

"AC-10 string escapes"

h check: 'AC-10 a bad \x escape' actual: ([LispReader read: '"\xZZ;"'. #none] on: LispReadError do: [:e | e messageText]) expected: 'bad \x escape: expected hex digits and ;'.

"AC-11 compiler structure: its two checks tested the Smalltalk compiler's
 special-form table and template cache, which retired in Phase 9 step 9.1;
 tests/lisp/phase-8.3-compiler.lisp tests the LISP compiler's table."

"AC-12 the LISP test framework, run on tests with known failures. It is a library
 (specs/27-namespaces.md), so it is loaded, and used, in a unit, as a file uses it."
LispCurrentUnit value: LispUnit session during: [ | ev |
ev := [:s | LispCompiler new evalAll: s].
ev value: '(load "' , ((root / 'lib' / 'test.lisp') fullName copyReplaceAll: '\' with: '/') , '")'.
ev value: '(define-test passes (check (+ 1 2) 3) (check-true (< 1 2)) (check-error (car 5) "not a pair"))
	(define-test fails (check (+ 1 2) 4) (check-false 1) (check-error 5) (check-error (car 5) "zzz"))
	(define-test crashes (check 1 1) (car 5) (check 2 2))'.
h check: 'AC-12 counts: 9 checks, 4 failures, 1 unexpected error'
	actual: ([:out | (out includesSubstring: '== RESULT: 4/9 checks passed ==')] value: (captured value: [ev value: '(run-tests/report)']))
	expected: true.
captured value: [ev value: '(set!! test:%pass 0) (set!! test:%total 0)'].
h check: 'AC-12 a failing check shows what it got and wanted'
	actual: ((captured value: [ev value: '(run-tests/report)']) includesSubstring: 'FAIL  fails: (+ 1 2)  got=3  want=4')
	expected: true.
captured value: [ev value: '(set!! test:%pass 0) (set!! test:%total 0)'].
h check: 'AC-12 an error inside a test fails that test only, with its message'
	actual: ([:out | (out includesSubstring: 'FAIL  crashes: unexpected error  car: not a pair: 5') and: [out includesSubstring: 'PASS  passes']]
		value: (captured value: [ev value: '(run-tests/report)']))
	expected: true].
h finish
] on: Error do: [:e | h harnessError: e].
!
