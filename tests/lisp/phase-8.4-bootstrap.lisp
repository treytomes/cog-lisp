;;; phase-8.4-bootstrap.lisp -- the compiler compiles itself to a fixpoint
;;; (lib/compiler/bootstrap.lisp; specs/phase-8-self-hosting.md step 8.4, AC-4).
;;; The built image loads lib/compiler/ and runs stage 1 (compiled by stage 0,
;;; the Smalltalk compiler); this file makes stages 2 and 3 and compares the
;;; methods each stage makes of the compiler's own source.
(load "../../lib/test.lisp")

(define stage-1-compile-form compile-form)
(define stage-1-translate-if lc-translate-if)
(define b (bootstrap-compiler "lib/compiler"))

(define-test "AC-4 stages 2 and 3 replaced the running compiler"
  (check-false (eq? compile-form stage-1-compile-form))
  (check-false (eq? lc-translate-if stage-1-translate-if)))

(define-test "AC-4 every stage compiles the same forms"
  (check-true (> (length (vector-ref b 0)) 150))
  (check (map length (list (vector-ref b 1) (vector-ref b 2) (vector-ref b 3)))
         (let ((n (length (vector-ref b 0)))) (list n n n))))

(define-test "AC-4 stage 1 = stage 0: the LISP compiler compiles itself as the Smalltalk one does"
  (check (bootstrap-differences b 0 1) '()))

(define-test "AC-4 stage 2 = stage 1: compiled by itself, it still compiles the same"
  (check (bootstrap-differences b 1 2) '()))

(define-test "AC-4 stage 3 = stage 2: the fixpoint"
  (check (bootstrap-differences b 2 3) '())
  (check-true (bootstrap-fixpoint? b)))

(define-test "AC-4 the comparison sees a difference"
  ;; stage 1's first method replaced: the difference is reported by its label
  (let ((changed (vector (vector-ref b 0)
                         (cons (cons "changed" "x") (cdr (vector-ref b 1)))
                         (vector-ref b 2) (vector-ref b 3))))
    (check (bootstrap-differences changed 0 1) (list (car (car (vector-ref b 0)))))
    (check-false (bootstrap-fixpoint? changed))))

;; stage 3 is now the compiler that is installed: it was compiled by stage 2
(define-test "AC-4 stage 3 works: it compiles as the Smalltalk compiler does"
  (for-each (lambda (d)
              (check (method-listing (compile-form d)) (method-listing [[(smalltalk LispCompiler) new] compile: d])))
            '((define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
              (let loop ((i 0) (acc '())) (if (= i 3) acc (loop (+ i 1) (cons i acc))))
              `(1 ,(+ 1 1) ,@(list 3)))))

(define-test "AC-4 stage 3 works: it reads and runs programs"
  (check (lisp-eval-string "(define (stage3-sq x) (* x x)) (stage3-sq 9)") 81)
  (check (read-all "(a . b) #(1 2)") '((a . b) #(1 2)))
  (check (procedure-source stage3-sq) "(define (stage3-sq x) (* x x))"))

(define-test "AC-4 stage 3's own procedures keep their source"
  (check-true (string? (procedure-source lc-translate-if)))
  (check (substring (procedure-source lc-translate-if) 0 26) "(define (lc-translate-if c"))

(run-tests)
