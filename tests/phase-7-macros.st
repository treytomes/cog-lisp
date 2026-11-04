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
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the acceptance checks ----------------------------------------"
| h out check checkErr checkMsg ev lst sym lib g1 g2 |
h := LispTestHarness new.
out := [:s | h say: s].
ev := [:s | LispCompiler new evalAll: s].
lst := [:s | LispReader read: s].
sym := [:s | LispSymbol named: s].
lib := Smalltalk imageDirectory parent / 'lib'.
check := h checkBlock.
checkErr := h checkErrBlock.
"an error of errClass whose message contains needle"
checkMsg := h checkMsgBlock.

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

"AC-3 nested quasiquote"

"AC-4 quasiquote does not use the global cons or append"
[ev value: '(define saved-cons cons) (define saved-append append)
		(define (cons a b) (quote broken)) (define (append . xs) (quote broken))
		(define r `(1 ,(+ 1 1) ,@(list 3 4) 5))
		(set!! cons saved-cons) (set!! append saved-append)
		r'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"AC-5 define-macro"
ev value: '(define-macro (swap!! a b) (let ((tmp (gensym))) `(let ((,tmp ,a)) (set!! ,a ,b) (set!! ,b ,tmp))))'.
[ev value: '(define p 1) (define q 2) (swap!! p q) (list p q)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

check value: 'AC-5 define-macro returns a macro, printed #<macro>'
	value: (LispPrinter writeString: (LispEnvironment default lookup: (sym value: 'swap!!')))
	value: '#<macro>'.

"AC-6 recursive expansion"
ev value: '(define-macro (m2 x) `(+ ,x 1)) (define-macro (m1 x) `(m2 (m2 ,x)))'.

ev value: '(define-macro (my-unless test . body) `(when (not ,test) ,@body))'.

"AC-7 a macro call in tail position keeps the tail call"
[ev value: '(define (lp n) (cond ((= n 0) (quote done)) (else (lp (- n 1))))) (lp 1000000)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (pe2 n) (cond ((= n 0) (stack-depth)) (else (po2 (- n 1)))))
		(define (po2 n) (cond ((= n 0) (stack-depth)) (else (pe2 (- n 1)))))
		(= (pe2 10) (pe2 10000))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (ev3 n) (or (= n 0) (od3 (- n 1)))) (define (od3 n) (and (not (= n 0)) (ev3 (- n 1)))) (list (ev3 100000) (ev3 100001))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"AC-8 macroexpand-1 / macroexpand"

"AC-9 gensym"

g1 := ev value: '(gensym)'.
g2 := ev value: '(gensym)'.
check value: 'AC-9 a gensym is a symbol' value: (LispCore isSymbol: g1) value: true.
check value: 'AC-9 printed g<n>' value: ((LispPrinter writeString: g1) first = $g and: [(LispPrinter writeString: g1) allButFirst allSatisfy: [:c | c isDigit]]) value: true.
check value: 'AC-9 names are unique' value: (LispPrinter writeString: g1) = (LispPrinter writeString: g2) value: false.
check value: 'AC-9 uninterned: reading the name gives another symbol' value: (lst value: (LispPrinter writeString: g1)) == g1 value: false.
[ev value: '(define-macro (my-or a b) (let ((t (gensym))) `(let ((,t ,a)) (if ,t ,t ,b)))) (let ((t 5)) (my-or #f t))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

check value: 'AC-9 gensym with a prefix' value: ((LispPrinter writeString: (ev value: '(gensym "loop")')) beginsWith: 'loop') value: true.

"AC-10 a local binding shadows a macro"

"AC-11 errors"

[ev value: '(define (f) (define-macro (mm) 1) 1)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(list (define-macro (mm) 1))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

ev value: '(define-macro (bad-macro x) (car x))'.

"AC-12 eval"

[ev value: '(eval (quote (define ev-made 9))) ev-made'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"AC-13 internal define"
[ev value: '(define (f1 x) (define y (* x 2)) (define z (+ y 1)) (list y z)) (f1 5)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f2 n) (define (e? k) (if (= k 0) #t (o? (- k 1)))) (define (o? k) (if (= k 0) #f (e? (- k 1)))) (list (e? n) (o? n))) (f2 7)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f3) (define hidden-x 1) hidden-x) (f3)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(let ((a 1)) (define b (+ a 1)) (* a b 10))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f4) (define c 0) (set!! c (+ c 5)) c) (f4)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (adder n) (define (add k) (+ n k)) add) ((adder 3) 4)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f5) 1 (define x 2) x)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"... including defines that come from macros (spec section 6)"
ev value: '(define-macro (defn2 name params . body) `(define (,name ,@params) ,@body))'.
[ev value: '(define (f6) (defn2 helper6 (x) (* x 3)) (helper6 4)) (f6)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f7) (defn2 sq7 (x) (* x x)) sq7) (procedure-source (f7))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define-macro (two-defs a b) `(begin (define ,a 1) (define ,b 2))) (define (f8) (two-defs p8 q8) (+ p8 q8)) (f8)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f9) (begin (define a 1) (define b 2)) (+ a b)) (f9)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f10) (define (when x) (* x 10)) (when 4)) (f10)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f11) (if #t (define zz 1)) 2)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (f12) 1 (defn2 late (x) x) 2)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(begin (define tb1 1) (define tb2 2)) (+ tb1 tb2)'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"AC-14 the derived forms"

[ev value: '(do ((v (list)) (i 0 (+ i 1))) ((= i 3) v) (set!! v (cons i v)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"AC-15 short-circuit"
ev value: '(define trail (list)) (define (note x) (set!! trail (cons x trail)) x)'.
[ev value: '(set!! trail (list)) (and (note 1) (note #f) (note 3)) trail'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(set!! trail (list)) (or (note #f) (note 2) (note 3)) trail'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(set!! trail (list)) (or (note 5)) trail'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"AC-16 named let and do loop in constant stack"

"AC-17 source retention through macros"
ev value: '(define-macro (defn name params . body) `(define (,name ,@params) ,@body))'.
ev value: '(defn sq (x) (* x x))'.

check value: 'AC-17 an expander keeps its define-macro text'
	value: (LispEnvironment default lookup: (sym value: 'defn')) expander source
	value: '(define-macro (defn name params . body) `(define (,name ,@params) ,@body))'.
check value: 'AC-17 a core expander keeps its text'
	value: ((LispEnvironment default lookup: (sym value: 'when')) expander source beginsWith: '(define-macro (when test . body)')
	value: true.
[ev value: '(define (outer) (define (inner y) (+ y 1)) inner) (procedure-source (outer))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

"AC-18 the CL library"
LispCompiler new evalFile: (lib / 'cl.lisp') fullName.

"Phase 6 regression: a self-loop gives each iteration its own variables"
[ev value: '(define (mk n acc) (if (= n 0) acc (mk (- n 1) (cons (lambda () n) acc)))) (map (lambda (g) (g)) (mk 3 (list)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

[ev value: '(define (mk2 n acc) (if (= n 0) acc (begin (set!! n n) (mk2 (- n 1) (cons (lambda () n) acc))))) (map (lambda (g) (g)) (mk2 3 (list)))'] on: Error do: [:e | nil].
"(the check itself moved to tests/lisp/phase-7-macros.lisp)"

h finish
] on: Error do: [:e | h harnessError: e].
!
