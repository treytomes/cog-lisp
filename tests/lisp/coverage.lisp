;;; coverage.lisp -- which procedures and branches a run reached (specs/coverage.md
;;; AC-1 to AC-4). The code under test is compiled inside each test, from a string,
;;; while a session runs; its lines are the string's.
(load "../../lib/test.lisp")

;; the counts for the code in source, after running it with run (a thunk)
(define (covered source run)
  (coverage-start)
  (eval-all source)
  (run)
  (coverage-stop))

(define (count-of counts kind line)
  (let loop ((cs counts))
    (cond ((null? cs) 'no-probe)
          ((and (eq? (vector-ref (car cs) 3) kind) (eqv? (vector-ref (car cs) 1) line)) (vector-ref (car cs) 4))
          (else (loop (cdr cs))))))

(define-test "AC-1 a called procedure is counted; one never called is reported, with its line"
  (let ((counts (covered "(define (used x) (* x 2))\n(define (unused x) x)\n" (lambda () (used 1) (used 2)))))
    (check (count-of counts 'procedure 1) 2)
    (check (count-of counts 'procedure 2) 0)
    (let ((report (with-output-to-string (lambda () (coverage-report counts)))))
      (check-true (string-search report "coverage: 1 of 2 probes reached"))
      (check-true (string-search report "2:1: never called: (define (unused x) x)"))
      (check-false (string-search report "(define (used x)")))))

(define-test "AC-2 both sides of if, cond and case, nested, are counted apart"
  (let ((counts (covered "(define (f n)\n  (if (> n 0)\n      (cond ((= n 1) 'one)\n            (else (case n ((2) 'two) (else 'many))))\n      'none))\n"
                         (lambda () (f 1) (f 2) (f 2)))))
    (check (count-of counts 'true 2) 3)               ; (> n 0)
    (check (count-of counts 'false 2) 0)
    (check (count-of counts 'true 3) 1)               ; (= n 1)
    (check (count-of counts 'false 3) 2)
    (let ((report (with-output-to-string (lambda () (coverage-report counts)))))
      (check-true (string-search report "2:7: never taken, the false side of: (> n 0)")))))

(define-syntax my-unless
  (syntax-rules () ((_ test body) (if test #f body))))

(define-test "AC-3 a macro's expansion counts at its use; a closure's body at its lambda"
  (let ((counts (covered "(define (g x)\n  (my-unless (> x 5)\n    'small))\n(define make-adder (lambda (n) (lambda (m) (+ n m))))\n"
                         (lambda () (g 1) ((make-adder 1) 2)))))
    (check (count-of counts 'false 2) 1)              ; the if my-unless made, at (> x 5)
    (check (count-of counts 'true 2) 0)
    (check (count-of counts 'procedure 4) 1)          ; make-adder, and the closure it made
    (check (length (let loop ((cs counts) (acc '()))
                     (cond ((null? cs) acc)
                           ((and (eq? (vector-ref (car cs) 3) 'procedure) (eqv? (vector-ref (car cs) 1) 4))
                            (loop (cdr cs) (cons (car cs) acc)))
                           (else (loop (cdr cs) acc)))))
           2)))

(define-test "AC-4 coverage keeps tail calls: a loop of a million runs in constant space"
  (let ((counts (covered "(define (spin n) (if (= n 0) 'done (spin (- n 1))))\n" (lambda () (check (spin 1000000) 'done)))))
    (check (count-of counts 'procedure 1) 1)          ; a self-call is a loop, not a new entry
    (check (count-of counts 'true 1) 1)
    (check (count-of counts 'false 1) 1000000)))

(define-test "without a session nothing is probed, and coverage-stop answers ()"
  (check (coverage-stop) '())
  (eval-all "(define (later) 1)")
  (coverage-start)
  (check (later) 1)
  (check (coverage-stop) '()))

(define-test "cog-lisp's own lib folder is not instrumented (R-7)"
  (coverage-start)
  (require 'cl)
  (check (coverage-stop) '()))

(define-test "coverage-start with files covers only those"
  (coverage-start (list "elsewhere.lisp"))
  (eval-all "(define (not-listed) 1)")
  (check (coverage-stop) '()))

(run-tests)
