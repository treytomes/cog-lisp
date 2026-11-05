;;; phase-9.3-syntax-rules.lisp -- hygienic macros (specs/phase-9-language.md
;;; step 9.3, AC-3; review C-14): syntax-rules patterns and templates, capture in
;;; both directions, let-syntax and letrec-syntax, shadowed special forms.
(load "../../lib/test.lisp")

;;; Shadowing special forms (C-14)

(define-test "AC-3 a local variable may be named as a special form (C-14)"
  (check ((lambda (if) (if 1 2 3)) +) 6)
  (check (let ((quote list)) (quote 1 2)) '(1 2))
  (check (let ((define 5) (lambda 6)) (+ define lambda)) 11)
  (check (let ((set! (lambda (x) (* x 10)))) (set! 4)) 40))

;;; Capture, both directions

(define-syntax swap!
  (syntax-rules ()
    ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))

(define-test "AC-3 a binding the macro introduces captures nothing of the program's"
  (let ((tmp 1) (other 2))
    (swap! tmp other)
    (check (list tmp other) '(2 1)))
  (let ((x 'a) (y 'b))
    (swap! x y)
    (check (list x y) '(b a))))

(define-syntax my-or
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e r ...) (let ((t e)) (if t t (my-or r ...))))))

(define-test "AC-3 ... even recursively"
  (check (let ((t 5)) (my-or #f t)) 5)
  (check (my-or #f #f) #f)
  (check (my-or) #f))

(define-syntax my-if (syntax-rules () ((_ c a b) (if c a b))))
(define-syntax call-list (syntax-rules () ((_ x ...) (list x ...))))

(define-test "AC-3 a free name in a template means what it meant where the macro was defined"
  (check (let ((if list)) (my-if #t 'yes 'no)) 'yes)
  (check (let ((list vector)) (call-list 1 2)) '(1 2))
  (check (let ((list vector)) (list 1 2)) #(1 2)))

(define-test "AC-3 a loop name a template introduces is not the program's"
  (define-syntax my-while
    (syntax-rules () ((_ c body ...) (let lp () (when c body ... (lp))))))
  (check (let ((i 0) (lp 'mine)) (my-while (< i 3) (set! i (+ i 1))) (list i lp)) '(3 mine)))

;;; Patterns

(define-test "AC-3 literals match by binding, not by spelling"
  (define-syntax arrow
    (syntax-rules (=>)
      ((_ a => b) (list 'arrow a b))
      ((_ a b c) (list 'plain a b c))))
  (check (arrow 1 => 2) '(arrow 1 2))
  (check (let ((=> 9)) (arrow 1 => 2)) '(plain 1 9 2)))

(define-test "AC-3 _ matches anything, and is no variable"
  (define-syntax second (syntax-rules () ((_ _ b . _) b)))
  (check (second 1 2 3 4) 2))

(define-test "AC-3 ellipses: after any element, with patterns after them, and dotted tails"
  (define-syntax tail (syntax-rules () ((_ a ... z) '(z a ...))))
  (define-syntax dotted (syntax-rules () ((_ a . rest) '(a rest))))
  (define-syntax ends (syntax-rules () ((_ a b ... c d) '(a (b ...) c d))))
  (define-syntax rest-tail (syntax-rules () ((_ a ... . r) '((a ...) r))))
  (check (tail 1 2 3 4) '(4 1 2 3))
  (check (tail 1) '(1))
  (check (dotted 1 2 3) '(1 (2 3)))
  (check (ends 1 2 3 4 5) '(1 (2 3) 4 5))
  (check (ends 1 4 5) '(1 () 4 5))
  (check (rest-tail 1 2 . 3) '((1 2) 3)))

(define-test "AC-3 nested ellipses"
  (define-syntax flat (syntax-rules () ((_ (a ...) ...) '(a ... ...))))
  (define-syntax pairs (syntax-rules () ((_ (k v ...) ...) '((k (v ...)) ...))))
  (define-syntax my-let* (syntax-rules ()
                           ((_ () body ...) (let () body ...))
                           ((_ ((x v) rest ...) body ...) (let ((x v)) (my-let* (rest ...) body ...)))))
  (check (flat (1 2) (3) () (4 5 6)) '(1 2 3 4 5 6))
  (check (pairs (a 1 2) (b 3) (c)) '((a (1 2)) (b (3)) (c ())))
  (check (my-let* ((a 1) (b (+ a 1)) (c (* b 3))) (list a b c)) '(1 2 6)))

(define-test "AC-3 a variable under fewer ellipses repeats"
  (define-syntax with-each (syntax-rules () ((_ x (y ...)) '((x y) ...))))
  (check (with-each k (1 2 3)) '((k 1) (k 2) (k 3))))

(define-test "AC-3 vector patterns and templates"
  (define-syntax vec (syntax-rules () ((_ #(a ...) last) (list a ... last))))
  (define-syntax to-vec (syntax-rules () ((_ a ...) #(a ...))))
  (check (vec #(1 2 3) 4) '(1 2 3 4))
  (check (to-vec 1 2) #(1 2)))

(define-test "AC-3 a custom ellipsis, and (... ...)"
  (define-syntax my-list (syntax-rules ::: () ((_ x :::) (list x :::))))
  (define-syntax dots (syntax-rules () ((_ x) '(x (... ...)))))
  (check (my-list 1 2 3) '(1 2 3))
  (check (dots 7) '(7 ...)))

(define-test "AC-3 rules are tried in order"
  (define-syntax kind (syntax-rules () ((_ (a . b)) 'pair) ((_ #(a ...)) 'vector) ((_ 1) 'one) ((_ x) 'other)))
  (check (list (kind (1 2)) (kind #(1)) (kind 1) (kind "s")) '(pair vector one other)))

;;; Templates

(define-test "AC-3 quote in a template gives symbols"
  (define-syntax q (syntax-rules () ((_) '(a b #(c)))))
  (define-syntax qq (syntax-rules () ((_ x) `(a ,x ,@(list x x)))))
  (check (q) '(a b #(c)))
  (check-true (symbol? (car (q))))
  (check (qq 1) '(a 1 1 1)))

(define-test "AC-3 a template may define at top level, and define a macro"
  (eval-all "(define-syntax def-two (syntax-rules () ((_ a b v) (begin (define a v) (define b v)))))")
  (eval-all "(def-two st-p1 st-p2 3)")
  (check (eval-all "(list st-p1 st-p2)") '(3 3))
  (eval-all "(define-syntax def-const (syntax-rules () ((_ name val) (define-syntax name (syntax-rules () ((_) val))))))")
  (eval-all "(def-const st-forty-two 42)")
  (check (eval-all "(st-forty-two)") 42))

(define-test "AC-3 interop names in templates"
  (define-syntax size-of (syntax-rules () ((_ x) [x size])))
  (define-syntax new-oc (syntax-rules () ((_) (send (smalltalk OrderedCollection) new))))
  (check (size-of "abc") 3)
  (check [(new-oc) isEmpty] #t))

;;; let-syntax, letrec-syntax, internal define-syntax

(define-test "AC-3 let-syntax: the macros see the enclosing scope"
  (check (let ((x 'outer))
           (let-syntax ((m (syntax-rules () ((_) x))))
             (let ((x 'inner)) (m))))
         'outer)
  (check (let-syntax ((one (syntax-rules () ((_) 1)))) (define z (one)) (+ z 1)) 2))

(define-test "AC-3 letrec-syntax: the macros see each other"
  (check (letrec-syntax ((ev? (syntax-rules () ((_ n) (if (= n 0) #t (od? (- n 1))))))
                         (od? (syntax-rules () ((_ n) (if (= n 0) #f #t)))))
           (list (ev? 2) (ev? 1)))
         '(#t #f)))

(define-test "AC-3 define-syntax in a body is local to it"
  (define (f x)
    (define-syntax twice (syntax-rules () ((_ e) (begin e e))))
    (define n 0)
    (twice (set! n (+ n x)))
    n)
  (check (f 5) 10)
  (check-error (eval-all "(twice 1)") "unbound variable: twice"))

;;; Errors

(define-test "AC-3 syntax-error, and a use no pattern matches"
  (eval-all "(define-syntax one-arg (syntax-rules () ((_ x) x) ((_ x y . z) (syntax-error \"one-arg takes one form\" x y))))")
  (check-error (eval-all "(one-arg 1 2)") "one-arg takes one form 1 2")
  (check-error (eval-all "(swap! 1)") "swap!: no syntax-rules pattern matches (swap! 1)")
  (check-error (eval-all "(define-syntax bad (lambda (x) x))") "the transformer must be syntax-rules")
  (check-error (eval-all "(syntax-rules () ((_) 1))") "syntax-rules is used only in define-syntax")
  (check-error (eval-all "(define-syntax v (syntax-rules () ((_ x ...) x)))(v 1 2)") "used without its ellipsis")
  (check-error (eval-all "(define (g) (if #t (define-syntax m (syntax-rules () ((_) 1)))) 1)") "define-syntax is allowed only"))

(define-test "AC-3 a syntax-rules macro is a macro"
  (check-error (eval-all "(let ((y swap!)) y)") "macro used as a value: swap!")
  (check-written [[(smalltalk LispEnvironment) default] lookup: 'swap!] "#<syntax swap!>")
  (check-written (macroexpand '(swap! a b)) "(let ((tmp a)) (set! a b) (set! b tmp))"))

(run-tests)
