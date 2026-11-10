;;; parameterize.lisp -- make-parameter and parameterize, R7RS 4.2.6
;;; (specs/23-lisp-expert-review.md R-3, AC-2)
(load "../../lib/test.lisp")

(define-test "a parameter answers its value"
  (let ((p (make-parameter 10)))
    (check (p) 10)
    (check (parameterize ((p 20)) (p)) 20)
    (check (p) 10)))

(define-test "a converter applies to the initial value and to parameterize's"
  (let ((p (make-parameter 5 (lambda (x) (* x 2)))))
    (check (p) 10)
    (check (parameterize ((p 7)) (p)) 14)
    (check (p) 10)))

(define-test "nesting, and several parameters at once"
  (let ((a (make-parameter 1)) (b (make-parameter 2)))
    (check (parameterize ((a 10) (b 20))
             (list (a) (b) (parameterize ((a 100)) (list (a) (b))) (a)))
           '(10 20 (100 20) 10))
    (check (list (a) (b)) '(1 2))))

(define-test "the values are evaluated before any is bound"
  (let ((a (make-parameter 1)) (b (make-parameter 0)))
    (check (parameterize ((a 5) (b (a))) (b)) 1)))

(define-test "the old value comes back after an error caught outside"
  (let ((p (make-parameter 'outer)))
    (check (guard (e (#t (p)))
             (parameterize ((p 'inner))
               (error "boom")))
           'outer)
    (check (p) 'outer)))

(define-test "and after a restart leaves it (cog-lisp's non-local exit)"
  (let ((p (make-parameter 'outer)))
    (check (restart-case
             (parameterize ((p 'inner))
               (invoke-restart 'leave (p)))
             (leave (v) (list v (p))))
           '(inner outer))
    (check (p) 'outer)))

(define-test "the body's value, and its several forms"
  (let ((p (make-parameter 1)) (log '()))
    (check (parameterize ((p 2)) (set! log (cons (p) log)) (* (p) 10)) 20)
    (check log '(2))
    (check (parameterize () 'empty) 'empty)))

(define-test "a parameter called with an argument is an error"
  (check-error ((make-parameter 1) 2) "a parameter takes no arguments"))

(define-test "documented"
  (check-true (string? (documentation 'make-parameter)))
  (check-true (string? (documentation 'parameterize))))

(run-tests)
