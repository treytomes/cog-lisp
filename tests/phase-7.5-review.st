"============================================================================
 cog-lisp : Phase 7.5 regression suite  (specs/phase-7.5-review-and-tooling.md
 AC-3; specs/review-phases-1-7.md). One or more checks per fixed finding, named
 by its id. Runner-level fixes (R-1 located errors, the build refusing to save)
 are checked by tests\phase-5-runner.bat fixtures and by hand.
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
| h ev lst msg readErr |
h := LispTestHarness new.
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
"the user-facing message of the error s raises, or #none"
msg := [:s | [ev value: s. #none] on: Error do: [:e | LispError describe: e]].
"{ message. position. incomplete } of the read error s raises"
readErr := [:s | [LispReader read: s. #none] on: LispReadError do: [:e | { e messageText. e position. e isIncomplete }]].

[
h say: '== cog-lisp Phase 7.5 : review regressions =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (Smalltalk imageDirectory parent / 'lib' / 'core.lisp') fullName.

"R-16 one root for LISP errors"
h check: 'R-16 read, compile, unbound and arity errors are LispErrors'
	actual: ({ LispReadError. LispCompileError. LispUnboundError. LispArityError. LispLocatedError } allSatisfy: [:c | c inheritsFrom: LispError])
	expected: true.

"R-1 / R-15 positions, and incomplete only when more input could help"
h check: 'R-15 unterminated list points at its open paren, incomplete' actual: (readErr value: '(1 (2 3') expected: { 'unterminated list'. 3. true }.
h check: 'R-15 unterminated string points at its quote, incomplete' actual: (readErr value: '  "abc') expected: { 'unterminated string'. 2. true }.
h check: 'R-15 unterminated block comment, incomplete' actual: (readErr value: '#| x') expected: { 'unterminated block comment'. 0. true }.
h check: 'R-15 an unknown # word at the end is not incomplete' actual: (readErr value: '#tru') third expected: false.
h check: 'R-15 a bad character name at the end is not incomplete' actual: (readErr value: '#\spacex') third expected: false.
h check: 'R-15 a stray ) is not incomplete' actual: (readErr value: '1)') third expected: false.
h check: 'R-1 line and column of an offset'
	actual: { LispReader lineAndColumnOf: 0 in: 'ab
cd'. LispReader lineAndColumnOf: 4 in: 'ab
cd' }
	expected: { #(1 1). #(2 2) }.
h check: 'R-1 evalAll:named: locates an error at its top-level form'
	actual: ([LispCompiler new evalAll: '(define a 1)
  (car a)' named: 'f.lisp'. #none] on: LispLocatedError do: [:e | e reportText])
	expected: 'f.lisp:2:3: error: car: not a pair: 1'.
h check: 'R-1 a read error is located at the offending character'
	actual: ([LispCompiler new evalAll: '(display 1)
(f (g' named: 'f.lisp'. #none] on: LispLocatedError do: [:e | e reportText])
	expected: 'f.lisp:2:4: error: unterminated list'.

"R-13 / R-14 / R-23 reader"
h check: 'R-13 a bad hex character code is a read error' actual: (readErr value: '#\xZZ') first expected: 'bad character code: #\xZZ'.
h check: 'R-13 a code past Unicode is a read error' actual: (readErr value: '#\x110000') first expected: 'bad character code: #\x110000'.
h check: 'R-14 a lone dot is a read error' actual: (readErr value: '.') first expected: 'unexpected dot'.
h check: 'R-14 a dotted pair still reads' actual: (lst value: '(1 . 2)') cdr expected: 2.
h check: 'R-23 #| ends a token' actual: (LispPrinter writeString: (lst value: '(abc#|c|#def)')) expected: '(abc def)'.

"R-2 / R-9 / R-4 list primitives"
h check: 'R-2 car of a number' actual: (msg value: '(car 5)') expected: 'car: not a pair: 5'.
h check: 'R-2 car of the empty list' actual: (msg value: '(car (quote ()))') expected: 'car: not a pair: ()'.
h check: 'R-2 set-car!! of a number' actual: (msg value: '(set-car!! 5 1)') expected: 'set-car!!: not a pair: 5'.
h check: 'R-2 length of a number' actual: (msg value: '(length 5)') expected: 'length: not a proper list: 5'.
h check: 'R-2 map over a non-list' actual: (msg value: '(map car 5)') expected: 'map: not a proper list: 5'.
h check: 'R-2 assq over a non-list' actual: (msg value: '(assq 1 5)') expected: 'assq: not a proper list: 5'.
h check: 'R-2 arithmetic on a string' actual: (msg value: '(+ 1 "a")') expected: '+: not a number'.
h check: 'R-2 division by zero' actual: (msg value: '(/ 1 0)') expected: 'division by zero'.
h check: 'R-2 comparison of a string' actual: ((msg value: '(< "1" 2)') beginsWith: 'wrong type of argument') expected: true.
h check: 'R-9 length of a dotted list is an error' actual: (msg value: '(length (quote (1 . 2)))') expected: 'length: not a proper list: (1 . 2)'.
h check: 'R-9 apply of a dotted list is an error' actual: (msg value: '(apply + (quote (1 . 2)))') expected: 'apply: not a proper list: (1 . 2)'.
h check: 'R-9 append keeps an improper last argument' actual: (ev value: '(append (quote (1)) (quote (2 . 3)))') expected: (lst value: '(1 2 . 3)').
h check: 'R-9 append of () and an atom is the atom' actual: (ev value: '(append (quote ()) 5)') expected: 5.
h check: 'R-9 append shares its last argument' actual: (ev value: '(define tl (list 3)) (eq? tl (cdr (cdr (append (list 1 2) tl))))') expected: true.
h check: 'R-9 append with no arguments' actual: (ev value: '(append)') expected: LispEmptyList default.
h check: 'R-4 length of a circular list is an error, not a hang'
	actual: (msg value: '(define cy (list 1 2)) (set-cdr!! (cdr cy) cy) (length cy)')
	expected: 'length: circular list'.
h check: 'R-4 an error message about a circular list is cut short'
	actual: (msg value: '(define cy2 (list 1 2)) (set-cdr!! (cdr cy2) cy2) (car (cons 5 cy2)) (map car (cons 1 cy2))') size < 120
	expected: true.

"C-17 / R-7 named procedures and arity messages"
h check: 'C-17 a defined procedure prints its name' actual: (LispPrinter writeString: (ev value: '(define (sq x) (* x x)) sq')) expected: '#<procedure sq>'.
h check: 'C-17 a primitive prints its name' actual: (LispPrinter writeString: (ev value: 'car')) expected: '#<procedure car>'.
h check: 'C-17 an alias keeps the first name' actual: (LispPrinter writeString: (ev value: '(define sq-alias sq) sq-alias')) expected: '#<procedure sq>'.
h check: 'C-17 an internal define is named' actual: (LispPrinter writeString: (ev value: '(define (outer) (define (inner y) y) inner) (outer)')) expected: '#<procedure inner>'.
h check: 'C-17 (define f (lambda ...)) is named' actual: (LispPrinter writeString: (ev value: '(define lam (lambda (x) x)) lam')) expected: '#<procedure lam>'.
h check: 'R-7 arity message names the procedure' actual: (msg value: '(sq)') expected: 'sq: expected 1 argument, got 0'.
h check: 'R-7 arity message for a primitive' actual: (msg value: '(car 1 2)') expected: 'car: expected 1 argument, got 2'.
h check: 'R-7 arity message for a variadic procedure' actual: (msg value: '(define (va a . r) a) (va)') expected: 'va: expected at least 1 argument, got 0'.
h check: 'R-7 a self-looping procedure is named too' actual: (LispPrinter writeString: (ev value: '(define (lp n) (if (= n 0) 0 (lp (- n 1)))) lp')) expected: '#<procedure lp>'.

"C-6 malformed special forms are compile errors with the form named"
#( '(lambda)' 'lambda: bad syntax: (lambda)'
   '(let ((x)) x)' 'let: bad binding: (x)'
   '(let (x) x)' 'let: bad binding: x'
   '(let ((x 1) (x 2)) x)' 'let: duplicate name: x'
   '(let loop)' 'let: bad syntax: named let loop has no bindings'
   '(define)' 'define: bad syntax: (define)'
   '(define x)' 'define: bad syntax: (define x)'
   '(define 5 1)' 'define: bad name: 5'
   '(set!! x)' 'set!!: bad syntax: (set!! x)'
   '(set!! 5 1)' 'set!!: bad name: 5'
   '(define-macro foo)' 'define-macro: bad syntax: (define-macro foo)'
   '(quote)' 'quote: bad syntax: (quote)'
   '(quote 1 2)' 'quote: bad syntax: (quote 1 2)'
   '(quasiquote)' 'quasiquote: bad syntax: (quasiquote)'
   '(if #t 1 2 3)' 'if: bad syntax: (if #t 1 2 3)'
   '(+ 1 . 2)' 'bad syntax: improper list: (+ 1 . 2)'
   '((lambda (x x) x) 1 2)' 'lambda: duplicate parameter in (x x)'
   '(lambda (x . 5) x)' 'lambda: bad parameter list: (x . 5)'
   '(lambda (1) 1)' 'lambda: bad parameter list: (1)'
) pairsDo: [:src :want |
	h check: 'C-6 ' , src actual: ([ev value: src. #none] on: LispCompileError do: [:e | e messageText]) expected: want].
h check: 'C-6 well-formed forms still compile' actual: (ev value: '(let ((a 1)) ((lambda (x . r) (list x r)) a 2 3))') expected: (lst value: '(1 (2 3))').

"C-2 Pharo's limits are compile errors"
h check: 'C-2 sixteen parameters is a LispCompileError'
	actual: ([ev value: '(lambda (a b c d e f g h i j k l m n o p) a)'. #none] on: LispCompileError do: [:e | e messageText beginsWith: 'too many parameters'])
	expected: true.

"C-7 a macro that expands forever is an error, not a hang"
h check: 'C-7 nested expansion' actual: ([ev value: '(define-macro (forever) (quote (forever))) (forever)'. #none] on: LispCompileError do: [:e | e messageText]) expected: 'macro expansion too deep (more than 10000 steps): forever'.
h check: 'C-7 expansion at the start of a body' actual: ([ev value: '(define (fv) (forever) 1)'. #none] on: LispCompileError do: [:e | e messageText beginsWith: 'macro expansion too deep']) expected: true.
h check: 'C-7 deep but finite expansion still works' actual: (ev value: '(define-macro (count-down n) (if (= n 0) (quote (quote done)) `(count-down ,(- n 1)))) (count-down 2000)') expected: (LispSymbol named: 'done').

"R-10 exit checks its argument (the valid cases end the process, so are not run here)"
#('"x"' '-1' '300' '2.5') do: [:arg |
	h check: 'R-10 (exit ' , arg , ') is an error'
		actual: ((msg value: '(exit ' , arg , ')') beginsWith: 'exit: expected')
		expected: true].

"R-3 the memory watchdog stops runaway recursion"
h check: 'R-3 runaway recursion becomes a LispError'
	actual: ([LispShellCommand new withMemoryLimit: Smalltalk vm memorySize + 100000000 do: [ev value: '(define (rr) (+ 1 (rr))) (rr)']. #none]
		on: LispError do: [:e | e messageText beginsWith: 'out of memory'])
	expected: true.
Smalltalk garbageCollect.
h check: 'R-3 ordinary work under the watchdog is unaffected'
	actual: (LispShellCommand new withMemoryLimit: Smalltalk vm memorySize + 100000000 do: [ev value: '(define (cnt n) (if (= n 0) 0 (+ 1 (cnt (- n 1))))) (cnt 10000)'])
	expected: 10000.

"C-1 / C-12 self tail calls share scratch temps and evaluate arguments once"
h check: 'C-1 thirty self tail calls in one procedure compile'
	actual: (ev value: (String streamContents: [:s |
		s nextPutAll: '(define (st n a b c) (cond ((= n 0) (list a b c))'.
		1 to: 30 do: [:i | s nextPutAll: ' ((= n ' , (1000 + i) printString , ') (st (- n 1) b c a))'].
		s nextPutAll: ' (else (st (- n 1) a b c)))) (st 3 1 2 3)']))
	expected: (lst value: '(1 2 3)').
h check: 'C-1 arguments are all evaluated before any is assigned' actual: (ev value: '(define (sw n a b) (if (= n 0) (list a b) (sw (- n 1) b a))) (sw 3 1 2)') expected: (lst value: '(2 1)').
h check: 'C-1 a non-tail self call inside an argument' actual: (ev value: '(define (nt n acc) (if (= n 0) acc (nt (- n 1) (+ acc (if (= n 1) (nt 0 100) 1))))) (nt 5 0)') expected: 104.
h check: 'C-12 a macro in a self-tail-call argument expands once'
	actual: (ev value: '(define expansions 0) (define-macro (counted x) (set!! expansions (+ expansions 1)) x) (define (ce n) (if (= n 0) 0 (ce (counted (- n 1))))) (ce 3) expansions')
	expected: 1.

"C-8 local procedures (internal define, named let, do) loop too"
h check: 'C-8 redefining a local procedure with set!! mid-loop is followed'
	actual: (ev value: '(define (rl) (define (f n) (if (= n 0) (quote old) (begin (if (= n 2) (set!! f (lambda (k) (quote new)))) (f (- n 1))))) (f 5)) (rl)')
	expected: (LispSymbol named: 'new').
h check: 'C-8 a name rebound in the body is not a self call'
	actual: (ev value: '(define (sh) (define (f n) (if (= n 0) 0 (let ((f (lambda (k) 42))) (f (- n 1))))) (f 3)) (sh)')
	expected: 42.
h check: 'C-8 closures made in a named let keep each iteration'
	actual: (ev value: '(map (lambda (g) (g)) (let lp ((i 3) (acc (list))) (if (= i 0) acc (lp (- i 1) (cons (lambda () i) acc)))))')
	expected: (lst value: '(1 2 3)').
ev value: '(define (gl n acc) (if (= n 0) acc (gl (- n 1) (+ acc 1)))) (define (nl n) (let lp ((i n) (acc 0)) (if (= i 0) acc (lp (- i 1) (+ acc 1)))))'.
ev value: '(gl 100000 0) (nl 100000)'.
Smalltalk garbageCollect.
h check: 'C-8 a named let runs about as fast as a global self-loop (was ~9x slower)'
	actual: ([ev value: '(nl 3000000)'] timeToRun asMilliSeconds < (3 * ([ev value: '(gl 3000000 0)'] timeToRun asMilliSeconds max: 20)))
	expected: true.

"C-9 set!! and define no longer make a closure (behavior unchanged)"
h check: 'C-9 set!! of a parameter' actual: (ev value: '(define (f9 x) (set!! x (+ x 1)) x) (f9 1)') expected: 2.
h check: 'C-9 a closure over a set!! variable still sees updates'
	actual: (ev value: '(define (mkc) (let ((c 0)) (lambda () (set!! c (+ c 1)) c))) (define c9 (mkc)) (c9) (c9)')
	expected: 2.

"C-10 named let keeps its own text"
h check: 'C-10 named let source' actual: (ev value: '(procedure-source (let lp ((i 0)) lp))') expected: '(let lp ((i 0)) lp)'.
h check: 'C-10 let with directLet off keeps the let text'
	actual: (LispCompiler withoutOptions: #(#directLet) do: [ev value: '(procedure-source (let ((k 1)) (lambda () k)))'])
	expected: '(lambda () k)'.

"C-11 a top-level begin is top level"
h check: 'C-11 define-macro in a top-level begin, used later in it' actual: (ev value: '(begin (define-macro (m11) 11) (m11))') expected: 11.
h check: 'C-11 a macro that defines two macros'
	actual: (ev value: '(define-macro (two-macros) (quote (begin (define-macro (ma) 1) (define-macro (mb) 2)))) (two-macros) (+ (ma) (mb))')
	expected: 3.
h check: 'C-11 an empty top-level begin' actual: (ev value: '(begin)') expected: LispUnspecified default.

"C-13 gensyms survive quoting with literalQuote off"
h check: 'C-13 a quoted gensym is itself'
	actual: (LispCompiler withoutOptions: #(#literalQuote) do: [
		ev value: '(define-macro (qg) (let ((g (gensym))) `(eq? (quote ,g) (quote ,g)))) (qg)'])
	expected: true.

"C-3 large quasiquote templates"
h check: 'C-3 sixty unquoted elements'
	actual: (ev value: '(let ((x 1)) (length `(' , ((1 to: 60) inject: '' into: [:a :i | a , ' ,x']) , ')))')
	expected: 60.
h check: 'C-3 splices between runs' actual: (ev value: '(let ((x 1) (ys (list 2 3))) `(0 ,x ,@ys 4 ,x ,@ys . 5))') expected: (lst value: '(0 1 2 3 4 1 2 3 . 5)').
h check: 'C-3 a dotted unquote tail' actual: (ev value: '(let ((x 2)) `(1 . ,x))') expected: (lst value: '(1 . 2)').
h check: 'C-3 nested levels still right' actual: (ev value: '`(a `(b ,(c ,(+ 1 2))))') expected: (lst value: '(a (quasiquote (b (unquote (c 3)))))').

"C-4 a let with more than 15 bindings"
h check: 'C-4 twenty bindings'
	actual: (ev value: '(let (' , ((1 to: 20) inject: '' into: [:a :i | a , ' (v' , i printString , ' ' , i printString , ')']) , ') (+ v1 v20 (* v10 2)))')
	expected: 41.
h check: 'C-4 the values see the outer scope' actual: (ev value: '(let ((v1 100)) (let (' , ((1 to: 16) inject: '' into: [:a :i | a , ' (v' , i printString , ' v1)']) , ') v16))') expected: 100.

"O-1 0 to 4 argument entries"
h check: 'O-1 + and * have entries for 0 to 4 arguments'
	actual: ((0 to: 4) allSatisfy: [:n | ((LispEnvironment default lookup: (LispSymbol named: '+')) entryFor: n) notNil
		and: [((LispEnvironment default lookup: (LispSymbol named: '*')) entryFor: n) notNil]])
	expected: true.
h check: 'O-1 four-argument arithmetic' actual: (ev value: '(list (+ 1 2 3 4) (* 1 2 3 4) (- 10 1 2 3) (+) (*))') expected: (lst value: '(10 24 4 0 1)').
h check: 'O-1 chained comparisons' actual: (ev value: '(list (< 1 2 3) (< 1 3 2) (<= 1 1 2 2) (= 2 2 2 2) (> 3 2 1) (>= 3 3 4))') expected: (lst value: '(#t #f #t #t #t #f)').

"R-4 list? on a circular list"
h check: 'R-4 list? of a circular list is #f' actual: (ev value: '(define cy3 (list 1 2)) (set-cdr!! (cdr cy3) cy3) (list? cy3)') expected: false.
h check: 'R-4 list? still right on proper and dotted lists' actual: (ev value: '(list (list? (quote (1 2 3))) (list? (quote (1 . 2))) (list? (quote ())))') expected: (lst value: '(#t #f #t)').

"R-6 the REPL evaluates forms as it reads them"
h check: 'R-6 forms before a read error on the same line still run, then the error'
	actual: ([:input | | o e | o := WriteStream on: String new. e := WriteStream on: String new.
		(LispRepl in: input readStream out: o err: e) run. { o contents. e contents }] value: '(display 1) (display 2) )
')
	expected: { '> 12> ' , (String with: Character lf). 'error: unexpected )' , (String with: Character lf) }.
h check: 'R-6 a form split across lines runs once, after the forms before it'
	actual: ([:input | | o e | o := WriteStream on: String new. e := WriteStream on: String new.
		(LispRepl in: input readStream out: o err: e) run. o contents] value: '(display 1) (display
 2)
(+ 1 2)
')
	expected: '> 12> 3' , (String with: Character lf) , '> ' , (String with: Character lf).

"R-8 display shows strings and characters as text, also inside lists"
h check: 'R-8 display of a character' actual: (LispPrinter displayString: $a) expected: 'a'.
h check: 'R-8 display of a list with strings and characters' actual: (LispPrinter displayString: (lst value: '("a" #\b c (d "e") . "f")')) expected: '(a b c (d e) . f)'.
h check: 'R-8 write is unchanged' actual: (LispPrinter writeString: (lst value: '("a" #\b c)')) expected: '("a" #\b c)'.
h check: 'R-8 display goes through the new printer'
	actual: (String streamContents: [:s | LispPrimitives withOutput: s do: [ev value: '(display (list "x" #\y))']])
	expected: '(x y)'.

"R-11 fractions print as n/d"
h check: 'R-11 a fraction' actual: (LispPrinter writeString: (ev value: '(/ 6 4)')) expected: '3/2'.
h check: 'R-11 a negative fraction in a list' actual: (LispPrinter writeString: (ev value: '(list (/ -1 3))')) expected: '(-1/3)'.

"R-12 -0.0"
h check: 'R-12 -0.0 reads with its sign' actual: (lst value: '-0.0') signBit expected: 1.
h check: 'R-12 -0.0 round-trips' actual: (LispPrinter writeString: (lst value: '-0.0')) expected: '-0.0'.
h check: 'R-12 eqv? tells 0.0 from -0.0' actual: (ev value: '(list (eqv? 0.0 -0.0) (eqv? -0.0 -0.0) (= 0.0 -0.0))') expected: (lst value: '(#f #t #t)').

"R-19 gensym takes a symbol prefix"
h check: 'R-19 (gensym (quote pre))' actual: ((LispPrinter writeString: (ev value: '(gensym (quote pre))')) beginsWith: 'pre') expected: true.

"R-20 control characters are written by code"
h check: 'R-20 character 1' actual: (LispPrinter writeString: (Character value: 1)) expected: '#\x1'.
h check: 'R-20 character 127' actual: (LispPrinter writeString: (Character value: 127)) expected: '#\x7f'.
h check: 'R-20 ... and read back' actual: (lst value: (LispPrinter writeString: (Character value: 1))) expected: (Character value: 1).
h check: 'R-20 named characters unchanged' actual: (LispPrinter writeString: (lst value: '(#\a #\space #\newline)')) expected: '(#\a #\space #\newline)'.

h finish
] on: Error do: [:e | h harnessError: e].
!
