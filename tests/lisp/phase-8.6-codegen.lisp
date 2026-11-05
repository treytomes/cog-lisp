;;; phase-8.6-codegen.lisp -- the direct code generator (lib/compiler/codegen.lisp;
;;; specs/phase-8-self-hosting.md step 8.6, AC-8). Everything else runs on it too;
;;; these check what it had to get right that Opal did before: closures and
;;; their variables, inlined control flow, globals read as literal variables,
;;; frame limits, literals. (Since step 9.1 it is the only generator.)
(load "../../lib/test.lisp")

(define-test "AC-8 closures made in a loop keep their own iteration's values"
  (check (eval-all "(let loop ((i 0) (acc '())) (if (= i 3) (map (lambda (f) (f)) acc) (loop (+ i 1) (cons (lambda () i) acc))))")
         '(2 1 0))
  (check (eval-all "(do ((i 0 (+ i 1)) (fs '() (cons (lambda () (* i 10)) fs))) ((= i 3) (map (lambda (f) (f)) fs)))")
         '(20 10 0)))

(define-test "AC-8 a captured variable written later is shared, not copied"
  (check (eval-all "(define (cg-counter) (let ((n 0)) (lambda () (set! n (+ n 1)) n))) (let ((c (cg-counter))) (c) (c) (c))") 3)
  (check (eval-all "(let ((x 1)) (let ((get (lambda () x))) (set! x 5) (get)))") 5)
  (check (eval-all "(let ((x 1)) (define (bump!) (set! x (+ x 1))) (bump!) (bump!) x)") 3)
  (check (eval-all "(let ((a 1)) ((lambda () ((lambda () (set! a 7))))) a)") 7))

(define-test "AC-8 internal definitions see each other (letrec*)"
  (check (eval-all "(define (cg-parity n) (define (ev? k) (if (= k 0) #t (od? (- k 1)))) (define (od? k) (if (= k 0) #f (ev? (- k 1)))) (list (ev? n) (od? n))) (cg-parity 7)")
         '(#f #t)))

(define-test "AC-8 self tail calls loop in constant space, also inside a let"
  (check (eval-all "(define (cg-loop n acc) (let ((m (- n 1))) (if (= n 0) acc (cg-loop m (+ acc 1))))) (cg-loop 100000 0)") 100000))

(define-test "AC-8 truth: only #f is false"
  (check (map (lambda (x) (if x 'yes 'no)) (list #f #t 0 '() "" (smalltalk-nil)))
         '(no yes yes yes yes yes)))

(define-test "AC-8 a global is read as it is now"
  (check (eval-all "(define cg-g 1) (define (cg-read-g) cg-g) (define cg-g 2) (cg-read-g)") 2)
  (check (eval-all "(define cg-h 1) (define (cg-read-h) cg-h) (set! cg-h 3) (cg-read-h)") 3)
  ;; a forward reference: unbound when compiled, checked when read
  (check (eval-all "(define (cg-calls-later) (cg-later 2)) (define (cg-later x) (* x 21)) (cg-calls-later)") 42)
  (check-error (eval-all "(define (cg-calls-missing) (cg-never-defined 1)) (cg-calls-missing)")
               "unbound variable: cg-never-defined"))

(define-test "AC-8 big and deep code"
  (check (eval-all "((lambda (a b c d e f g h i j k l m n o p q r s t) (list a t)) 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)")
         '(1 20))
  (check (eval-all "(length (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25))") 25)
  (check (eval-all "(let ((v1 1) (v2 2) (v3 3) (v4 4) (v5 5) (v6 6) (v7 7) (v8 8) (v9 9) (v10 10) (v11 11) (v12 12) (v13 13) (v14 14) (v15 15) (v16 16) (v17 17)) (+ v1 v17))")
         18)
  (check (eval-all "(+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 0))))))))))))))))))))")
         20))

(define-test "AC-8 too large a frame is a compile error"
  (check-error (eval-all (string-append "(lambda () "
                                        (apply string-append
                                               (map (lambda (i) (string-append "(define a" (number->string i) " " (number->string i) ") "))
                                                    (vector->list (list->vector (cg-iota 80)))))
                                        "a1)"))
               "too large or too deeply nested to compile"))

(define (cg-iota n) (let loop ((i n) (acc '())) (if (= i 0) acc (loop (- i 1) (cons i acc)))))

(define-test "AC-8 string literals are read-only, as Opal made them"
  (check-error (eval-all "(define (cg-lit) \"abc\") (string-set! (cg-lit) 0 #\\z)")))

(define-test "AC-8 quasiquote, vectors, sends"
  (check (eval-all "(let ((x 2)) `(1 ,x ,@(list 3 4) #(5 ,x)))") '(1 2 3 4 #(5 2)))
  (check (eval-all "[(smalltalk Array) with: 1 with: (+ 1 1)]") #(1 2))
  (check (eval-all "(let ((c (send (smalltalk OrderedCollection) new))) (send c add: 5) (send c size))") 1))

(run-tests)
