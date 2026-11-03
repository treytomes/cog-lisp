"============================================================================
 cog-lisp : Phase 7 acceptance suite  (specs/phase-7-macros.md, AC-1..18)
 Quasiquote, define-macro, internal define, the derived forms of
 lib/core.lisp, source retention through macros, and lib/cl.lisp.
 AC-19 (earlier suites, benchmarks, examples) and AC-20 (the built image) are
 checked by the other suites and tests\phase-5-runner.bat.
 Every bang in Lisp text is doubled for the chunk reader.
 Run from the repo root:
   pharo\PharoConsole.exe pharo\<image>.image st tests\phase-7-macros.st
 ============================================================================"

"--- Chunk 1: load all five packages into this fresh image -----------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn].
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| out pass total check checkErr checkMsg ev lst sym lib g1 g2 |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
pass := 0.
total := 0.
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
sym := [:s | LispSymbol named: s].
lib := Smalltalk imageDirectory parent / 'lib'.
check := [:label :actual :expected |
	total := total + 1.
	(LispCore equal: actual with: expected)
		ifTrue: [pass := pass + 1. out value: '  PASS  ' , label]
		ifFalse: [out value: '  FAIL  ' , label , '  got=' , ([LispPrinter writeString: actual] on: Error do: [:e | actual printString]) , '  want=' , (LispPrinter writeString: expected)]].
checkErr := [:label :errClass :blk |
	total := total + 1.
	[blk value. out value: '  FAIL  ' , label , ' (no error raised)']
		on: errClass
		do: [:e | pass := pass + 1. out value: '  PASS  ' , label]].
"an error of errClass whose message contains needle"
checkMsg := [:label :errClass :needle :blk |
	total := total + 1.
	[blk value. out value: '  FAIL  ' , label , ' (no error raised)']
		on: errClass
		do: [:e | (e messageText includesSubstring: needle)
			ifTrue: [pass := pass + 1. out value: '  PASS  ' , label]
			ifFalse: [out value: '  FAIL  ' , label , '  message=' , e messageText printString]]].

[
out value: '== cog-lisp Phase 7 : macros & derived forms =='.
LispPrimitives installDefault.
LispCompiler new evalFile: (lib / 'core.lisp') fullName.

"AC-1 the quasiquote abbreviations"
check value: 'AC-1 `x' value: (lst value: '`x') value: (lst value: '(quasiquote x)').
check value: 'AC-1 ,x' value: (lst value: ',x') value: (lst value: '(unquote x)').
check value: 'AC-1 ,@x' value: (lst value: ',@x') value: (lst value: '(unquote-splicing x)').
check value: 'AC-1 inside a list' value: (lst value: '(a `(b ,c ,@d))') value: (lst value: '(a (quasiquote (b (unquote c) (unquote-splicing d))))').
check value: 'AC-1 comma ends a symbol' value: (lst value: '(a,b)') value: (lst value: '(a (unquote b))').

"AC-2 quasiquote builds lists"
check value: 'AC-2 unquote and splice' value: (ev value: '`(1 ,(+ 1 1) ,@(list 3 4) 5)') value: (lst value: '(1 2 3 4 5)').
check value: 'AC-2 dotted tail' value: (ev value: '`(1 . ,(+ 1 1))') value: (lst value: '(1 . 2)').
check value: 'AC-2 splice at the end' value: (ev value: '`(1 ,@(list 2 3))') value: (lst value: '(1 2 3)').
check value: 'AC-2 splice of the empty list' value: (ev value: '`(1 ,@(list) 2)') value: (lst value: '(1 2)').
check value: 'AC-2 constant template' value: (ev value: '`(a (b c))') value: (lst value: '(a (b c))').
check value: 'AC-2 unquote of a local' value: (ev value: '(let ((x 5)) `(x is ,x))') value: (lst value: '(x is 5)').
checkMsg value: 'AC-2 splice of a non-list is an error' value: Error value: 'not a list' value: [ev value: '`(1 ,@5)'].
checkErr value: 'AC-2 splice outside a list is an error' value: LispCompileError value: [ev value: '`,@(list 1)'].

"AC-3 nested quasiquote"
check value: 'AC-3 only level-0 unquotes run'
	value: (ev value: '`(a `(b ,(c ,(+ 1 2))))')
	value: (lst value: '(a (quasiquote (b (unquote (c 3)))))').

"AC-4 quasiquote does not use the global cons or append"
check value: 'AC-4 cons and append redefined'
	value: (ev value: '(define saved-cons cons) (define saved-append append)
		(define (cons a b) (quote broken)) (define (append . xs) (quote broken))
		(define r `(1 ,(+ 1 1) ,@(list 3 4) 5))
		(set!! cons saved-cons) (set!! append saved-append)
		r')
	value: (lst value: '(1 2 3 4 5)').

"AC-5 define-macro"
ev value: '(define-macro (swap!! a b) (let ((tmp (gensym))) `(let ((,tmp ,a)) (set!! ,a ,b) (set!! ,b ,tmp))))'.
check value: 'AC-5 swap!! on globals' value: (ev value: '(define p 1) (define q 2) (swap!! p q) (list p q)') value: (lst value: '(2 1)').
check value: 'AC-5 swap!! on locals' value: (ev value: '(let ((x (quote a)) (y (quote b))) (swap!! x y) (list x y))') value: (lst value: '(b a)').
check value: 'AC-5 define-macro returns a macro, printed #<macro>'
	value: (LispPrinter writeString: (LispEnvironment default lookup: (sym value: 'swap!!')))
	value: '#<macro>'.

"AC-6 recursive expansion"
ev value: '(define-macro (m2 x) `(+ ,x 1)) (define-macro (m1 x) `(m2 (m2 ,x)))'.
check value: 'AC-6 a macro expanding into macro calls' value: (ev value: '(m1 5)') value: 7.
ev value: '(define-macro (my-unless test . body) `(when (not ,test) ,@body))'.
check value: 'AC-6 a user macro over a core macro' value: (ev value: '(my-unless #f 1 42)') value: 42.
check value: 'AC-6 a macro used inside a lambda' value: (ev value: '((lambda (n) (m1 n)) 10)') value: 12.

"AC-7 a macro call in tail position keeps the tail call"
check value: 'AC-7 self loop through cond'
	value: (ev value: '(define (lp n) (cond ((= n 0) (quote done)) (else (lp (- n 1))))) (lp 1000000)')
	value: (sym value: 'done').
check value: 'AC-7 mutual recursion through cond, constant stack'
	value: (ev value: '(define (pe2 n) (cond ((= n 0) (stack-depth)) (else (po2 (- n 1)))))
		(define (po2 n) (cond ((= n 0) (stack-depth)) (else (pe2 (- n 1)))))
		(= (pe2 10) (pe2 10000))')
	value: true.
check value: 'AC-7 mutual recursion through and / or'
	value: (ev value: '(define (ev3 n) (or (= n 0) (od3 (- n 1)))) (define (od3 n) (and (not (= n 0)) (ev3 (- n 1)))) (list (ev3 100000) (ev3 100001))')
	value: (lst value: '(#t #f)').

"AC-8 macroexpand-1 / macroexpand"
check value: 'AC-8 macroexpand-1 of when' value: (ev value: '(macroexpand-1 (quote (when x 1 2)))') value: (lst value: '(if x (begin 1 2))').
check value: 'AC-8 macroexpand-1 expands once' value: (ev value: '(macroexpand-1 (quote (m1 5)))') value: (lst value: '(m2 (m2 5))').
check value: 'AC-8 macroexpand expands the top repeatedly' value: (ev value: '(macroexpand (quote (m1 5)))') value: (lst value: '(+ (m2 5) 1)').
check value: 'AC-8 a non-macro form is unchanged' value: (ev value: '(macroexpand-1 (quote (foo 1)))') value: (lst value: '(foo 1)').
check value: 'AC-8 an atom is unchanged' value: (ev value: '(macroexpand (quote x))') value: (sym value: 'x').

"AC-9 gensym"
check value: 'AC-9 two gensyms differ' value: (ev value: '(eq? (gensym) (gensym))') value: false.
g1 := ev value: '(gensym)'.
g2 := ev value: '(gensym)'.
check value: 'AC-9 a gensym is a symbol' value: (LispCore isSymbol: g1) value: true.
check value: 'AC-9 printed g<n>' value: ((LispPrinter writeString: g1) first = $g and: [(LispPrinter writeString: g1) allButFirst allSatisfy: [:c | c isDigit]]) value: true.
check value: 'AC-9 names are unique' value: (LispPrinter writeString: g1) = (LispPrinter writeString: g2) value: false.
check value: 'AC-9 uninterned: reading the name gives another symbol' value: (lst value: (LispPrinter writeString: g1)) == g1 value: false.
check value: 'AC-9 a gensym macro does not capture a user variable'
	value: (ev value: '(define-macro (my-or a b) (let ((t (gensym))) `(let ((,t ,a)) (if ,t ,t ,b)))) (let ((t 5)) (my-or #f t))')
	value: 5.
check value: 'AC-9 core or does not capture either' value: (ev value: '(let ((t 6)) (or #f t))') value: 6.
check value: 'AC-9 gensym with a prefix' value: ((LispPrinter writeString: (ev value: '(gensym "loop")')) beginsWith: 'loop') value: true.

"AC-10 a local binding shadows a macro"
check value: 'AC-10 let-bound when is a variable' value: (ev value: '(let ((when 5)) when)') value: 5.
check value: 'AC-10 let-bound when is called' value: (ev value: '(let ((when (lambda (x) (* x 2)))) (when 4))') value: 8.
check value: 'AC-10 a lambda parameter shadows' value: (ev value: '((lambda (and) (and 1 2)) +)') value: 3.

"AC-11 errors"
checkMsg value: 'AC-11 a macro used as a value' value: LispCompileError value: 'macro used as a value' value: [ev value: '(map and (list 1))'].
checkErr value: 'AC-11 define-macro inside a body' value: LispCompileError value: [ev value: '(define (f) (define-macro (mm) 1) 1)'].
checkErr value: 'AC-11 define-macro inside an expression' value: LispCompileError value: [ev value: '(list (define-macro (mm) 1))'].
ev value: '(define-macro (bad-macro x) (car x))'.
checkMsg value: 'AC-11 an expander error names the macro' value: LispCompileError value: 'bad-macro' value: [ev value: '(bad-macro 5)'].

"AC-12 eval"
check value: 'AC-12 eval of a built list' value: (ev value: '(eval (list (quote +) 1 2))') value: 3.
check value: 'AC-12 eval of a quasiquoted form' value: (ev value: '(eval `(* ,(+ 1 1) 5))') value: 10.
check value: 'AC-12 eval of a define' value: (ev value: '(eval (quote (define ev-made 9))) ev-made') value: 9.

"AC-13 internal define"
check value: 'AC-13 internal defines in a lambda body'
	value: (ev value: '(define (f1 x) (define y (* x 2)) (define z (+ y 1)) (list y z)) (f1 5)')
	value: (lst value: '(10 11)').
check value: 'AC-13 mutually recursive local procedures'
	value: (ev value: '(define (f2 n) (define (e? k) (if (= k 0) #t (o? (- k 1)))) (define (o? k) (if (= k 0) #f (e? (- k 1)))) (list (e? n) (o? n))) (f2 7)')
	value: (lst value: '(#f #t)').
check value: 'AC-13 internal defines do not leak' value: (ev value: '(define (f3) (define hidden-x 1) hidden-x) (f3)') value: 1.
checkErr value: 'AC-13 ... and are not global' value: LispUnboundError value: [ev value: 'hidden-x'].
check value: 'AC-13 internal defines in a let body' value: (ev value: '(let ((a 1)) (define b (+ a 1)) (* a b 10))') value: 20.
check value: 'AC-13 internal define with set!!' value: (ev value: '(define (f4) (define c 0) (set!! c (+ c 5)) c) (f4)') value: 5.
check value: 'AC-13 local procedure as a closure' value: (ev value: '(define (adder n) (define (add k) (+ n k)) add) ((adder 3) 4)') value: 7.
checkErr value: 'AC-13 a define after an expression is an error' value: LispCompileError value: [ev value: '(define (f5) 1 (define x 2) x)'].

"AC-14 the derived forms"
check value: 'AC-14 cond' value: (ev value: '(cond ((= 1 2) 1) ((= 1 1) 2) (else 3))') value: 2.
check value: 'AC-14 cond else' value: (ev value: '(cond (#f 1) (else 3))') value: 3.
check value: 'AC-14 cond test only' value: (ev value: '(cond (#f) (7))') value: 7.
check value: 'AC-14 cond =>' value: (ev value: '(cond ((assv 2 (quote ((1 . a) (2 . b)))) => cdr) (else 0))') value: (sym value: 'b').
check value: 'AC-14 case' value: (ev value: '(case 3 ((1 2) (quote low)) ((3 4) (quote mid)) (else (quote high)))') value: (sym value: 'mid').
check value: 'AC-14 case else' value: (ev value: '(case 9 ((1 2) (quote low)) (else (quote high)))') value: (sym value: 'high').
check value: 'AC-14 case on symbols' value: (ev value: '(case (quote b) ((a) 1) ((b c) 2))') value: 2.
check value: 'AC-14 and' value: (ev value: '(list (and 1 2 3) (and 1 #f 3))') value: (lst value: '(3 #f)').
check value: 'AC-14 or' value: (ev value: '(list (or #f #f 7) (or #f #f))') value: (lst value: '(7 #f)').
check value: 'AC-14 (and) and (or)' value: (ev value: '(list (and) (or))') value: (lst value: '(#t #f)').
check value: 'AC-14 when' value: (ev value: '(when (= 1 1) 1 2)') value: 2.
check value: 'AC-14 unless' value: (ev value: '(unless (= 1 2) 3)') value: 3.
check value: 'AC-14 let*' value: (ev value: '(let* ((x 1) (y (+ x 1)) (z (* y 10))) (list x y z))') value: (lst value: '(1 2 20)').
check value: 'AC-14 let* with no bindings' value: (ev value: '(let* () 5)') value: 5.
check value: 'AC-14 letrec'
	value: (ev value: '(letrec ((e? (lambda (n) (if (= n 0) #t (o? (- n 1))))) (o? (lambda (n) (if (= n 0) #f (e? (- n 1)))))) (e? 10))')
	value: true.
check value: 'AC-14 letrec*' value: (ev value: '(letrec* ((a 1) (b (+ a 1))) (list a b))') value: (lst value: '(1 2)').
check value: 'AC-14 named let' value: (ev value: '(let loop ((i 0) (acc (list))) (if (= i 3) acc (loop (+ i 1) (cons i acc))))') value: (lst value: '(2 1 0)').
check value: 'AC-14 do' value: (ev value: '(do ((i 0 (+ i 1)) (s 0 (+ s i))) ((= i 5) s))') value: 10.
check value: 'AC-14 do with a body and a stepless variable'
	value: (ev value: '(do ((v (list)) (i 0 (+ i 1))) ((= i 3) v) (set!! v (cons i v)))')
	value: (lst value: '(2 1 0)').

"AC-15 short-circuit"
ev value: '(define trail (list)) (define (note x) (set!! trail (cons x trail)) x)'.
check value: 'AC-15 and stops at the first false' value: (ev value: '(set!! trail (list)) (and (note 1) (note #f) (note 3)) trail') value: (lst value: '(#f 1)').
check value: 'AC-15 or stops at the first true' value: (ev value: '(set!! trail (list)) (or (note #f) (note 2) (note 3)) trail') value: (lst value: '(2 #f)').
check value: 'AC-15 or evaluates its operand once' value: (ev value: '(set!! trail (list)) (or (note 5)) trail') value: (lst value: '(5)').

"AC-16 named let and do loop in constant stack"
check value: 'AC-16 named let 100,000'
	value: (ev value: '(let loop ((i 0) (d 0)) (if (= i 100000) (= d (stack-depth)) (loop (+ i 1) (if (= i 1) (stack-depth) d))))')
	value: true.
check value: 'AC-16 do 100,000'
	value: (ev value: '(do ((i 0 (+ i 1)) (d 0 (if (= i 1) (stack-depth) d))) ((= i 100000) (= d (stack-depth))))')
	value: true.
check value: 'AC-16 named let sum' value: (ev value: '(let loop ((i 0) (acc 0)) (if (= i 100000) acc (loop (+ i 1) (+ acc i))))') value: 4999950000.

"AC-17 source retention through macros"
ev value: '(define-macro (defn name params . body) `(define (,name ,@params) ,@body))'.
ev value: '(defn sq (x) (* x x))'.
check value: 'AC-17 a procedure defined by a user macro keeps the call text' value: (ev value: '(procedure-source sq)') value: '(defn sq (x) (* x x))'.
check value: 'AC-17 ... and still works' value: (ev value: '(sq 9)') value: 81.
check value: 'AC-17 an expander keeps its define-macro text'
	value: (LispEnvironment default lookup: (sym value: 'defn')) expander source
	value: '(define-macro (defn name params . body) `(define (,name ,@params) ,@body))'.
check value: 'AC-17 a core expander keeps its text'
	value: ((LispEnvironment default lookup: (sym value: 'when')) expander source beginsWith: '(define-macro (when test . body)')
	value: true.
check value: 'AC-17 an internal define keeps its text'
	value: (ev value: '(define (outer) (define (inner y) (+ y 1)) inner) (procedure-source (outer))')
	value: '(define (inner y) (+ y 1))'.

"AC-18 the CL library"
LispCompiler new evalFile: (lib / 'cl.lisp') fullName.
check value: 'AC-18 defun' value: (ev value: '(defun sq2 (x) (* x x)) (sq2 5)') value: 25.
check value: 'AC-18 defun keeps its text' value: (ev value: '(procedure-source sq2)') value: '(defun sq2 (x) (* x x))'.
check value: 'AC-18 defun with &rest' value: (ev value: '(defun collect (a &rest xs) (cons a xs)) (collect 1 2 3)') value: (lst value: '(1 2 3)').
check value: 'AC-18 defmacro and defvar'
	value: (ev value: '(defmacro my-inc (place &rest amt) `(setq ,place (+ ,place ,(if (null amt) 1 (car amt))))) (defvar cnt 0) (my-inc cnt) (my-inc cnt 5) cnt')
	value: 6.
check value: 'AC-18 defparameter' value: (ev value: '(defparameter *limit* 10) *limit*') value: 10.
check value: 'AC-18 setq with pairs' value: (ev value: '(defvar a1 0) (defvar b1 0) (list (setq a1 1 b1 2) a1 b1)') value: (lst value: '(2 1 2)').
check value: 'AC-18 progn and prog1' value: (ev value: '(list (progn 1 2 3) (prog1 1 2 3))') value: (lst value: '(3 1)').
check value: 'AC-18 dolist' value: (ev value: '(let ((s 0)) (dolist (x (list 1 2 3) s) (setq s (+ s x))))') value: 6.
check value: 'AC-18 dotimes' value: (ev value: '(let ((s 0)) (dotimes (i 5 s) (setq s (+ s i))))') value: 10.
check value: 'AC-18 labels'
	value: (ev value: '(labels ((f (n) (if (= n 0) 0 (+ 1 (g (- n 1))))) (g (n) (if (= n 0) 0 (+ 1 (f (- n 1)))))) (f 6))')
	value: 6.
check value: 'AC-18 flet' value: (ev value: '(flet ((dbl (x) (* 2 x))) (dbl 21))') value: 42.
check value: 'AC-18 push and pop' value: (ev value: '(let ((stk nil)) (push 1 stk) (push 2 stk) (list (pop stk) stk))') value: (lst value: '(2 (1))').
check value: 'AC-18 mapcar' value: (ev value: '(mapcar (lambda (x) (* x x)) (list 1 2 3))') value: (lst value: '(1 4 9)').
check value: 'AC-18 funcall' value: (ev value: '(funcall + 1 2 3)') value: 6.
check value: 'AC-18 nth and nthcdr' value: (ev value: '(list (nth 2 (quote (a b c))) (nthcdr 1 (quote (a b c))))') value: (lst value: '(c (b c))').
check value: 'AC-18 first second third rest last'
	value: (ev value: '(let ((l (quote (1 2 3)))) (list (first l) (second l) (third l) (rest l) (last l)))')
	value: (lst value: '(1 2 3 (2 3) (3))').
check value: 'AC-18 predicates'
	value: (ev value: '(list (consp (list 1)) (listp nil) (atom 3) (null nil) (eql 2 2))')
	value: (lst value: '(#t #t #t #t #t)').
check value: 'AC-18 cond with null and t'
	value: (ev value: '(defun len (x) (cond ((null x) 0) (t (+ 1 (len (cdr x)))))) (len (list 1 2 3))')
	value: 3.

"Phase 6 regression: a self-loop gives each iteration its own variables"
check value: 'regression: closures in a self-loop capture each iteration'
	value: (ev value: '(define (mk n acc) (if (= n 0) acc (mk (- n 1) (cons (lambda () n) acc)))) (map (lambda (g) (g)) (mk 3 (list)))')
	value: (lst value: '(1 2 3)').
check value: 'regression: ... with a set!! inside the loop'
	value: (ev value: '(define (mk2 n acc) (if (= n 0) acc (begin (set!! n n) (mk2 (- n 1) (cons (lambda () n) acc))))) (map (lambda (g) (g)) (mk2 3 (list)))')
	value: (lst value: '(1 2 3)').
] on: Error do: [:e |
	out value: '  FAIL  unexpected error: ' , e class name , ' ' , e messageText printString].

out value: ''.
out value: '== RESULT: ' , pass printString , '/' , total printString , ' checks passed =='.
Smalltalk exit: (pass = total ifTrue: [0] ifFalse: [1]).
!
