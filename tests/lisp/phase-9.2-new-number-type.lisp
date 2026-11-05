;;; phase-9.2-new-number-type.lisp -- the tower is open to new kinds of number
;;; (specs/phase-9-language.md step 9.2c, AC-2): a number type added through
;;; interop (examples/dual.lisp) works in arithmetic, comparison, predicates and
;;; printing, and define-number-syntax gives it a read syntax, in the sealed
;;; reader and in string->number alike.
(load "../../lib/test.lisp")
(load "../../examples/dual.lisp")

(define (read-1 s) (read (open-input-string s)))

(define-test "AC-2 a new number type in ordinary arithmetic"
  (let ((d (dual 3 1)))
    (check (+ d 1) (dual 4 1))
    (check (+ 1 d) (dual 4 1))
    (check (+ d d d) (dual 9 3))
    (check (* d d) (dual 9 6))
    (check (* 1/2 d) (dual 3/2 1/2))
    (check (- 10 d) (dual 7 -1))
    (check (/ 1 d) (dual 1/3 -1/9))
    (check (apply + (list 1 d 2)) (dual 6 1))
    (check (- d) (dual -3 -1))))

(define-test "AC-2 ... mixed with floats, which make it inexact"
  (check (+ (dual 1 2) 0.5) (dual 1.5 2))
  (check-false (exact? (+ (dual 1 2) 0.5)))
  (check-true (exact? (dual 1/2 3))))

(define-test "AC-2 ... in comparisons"
  (check-true (= (dual 2 1) (dual 2 1)))
  (check-false (= (dual 2 1) (dual 2 0)))
  (check-true (= (dual 2 0) 2))
  (check-true (< 1 (dual 2 5) 3))
  (check-true (eqv? (dual 1 1) (dual 1 1))))

(define-test "AC-2 ... in the predicates, which ask the number"
  (check (map (lambda (p) (p (dual 1 1))) (list number? complex? real? rational? integer?)) '(#t #t #f #f #f))
  (check (list (exact? (dual 1 1)) (inexact? (dual 1.0 1))) '(#t #t))
  (check-error (positive? (dual 1 1)) "positive?: not a real number"))

(define-test "AC-2 ... in printing, which asks the number"
  (check-written (list (dual 3 2) (dual 1/2 -1) (dual 0 1)) "(3+2eps 1/2-eps 0+eps)")
  (check (number->string (dual 5 -3)) "5-3eps"))

(define-test "AC-2 define-number-syntax: the reader reads the new syntax"
  (check 3+2eps (dual 3 2))
  (check (read-1 "-1/2-eps") (dual -1/2 -1))
  (check (string->number "2+0.5eps") (dual 2 0.5))
  (check (string->number "eps") #f)
  (check-true (symbol? (read-1 "steps")))
  (check-true (symbol? (read-1 "x+eps"))))

(define-test "AC-2 a syntax registered later is tried after the earlier ones"
  (define-number-syntax (lambda (s) (string=? s "forty-two")) (lambda (s) 42))
  (check (read-1 "forty-two") 42)
  (check (string->number "forty-two") 42)
  (check (read-1 "1+eps") (dual 1 1)))

(define-test "AC-2 what the new numbers are for: exact derivatives"
  (check (derivative (lambda (x) (* x x x)) 2) 12)
  (check (derivative (lambda (x) (/ (+ (* x x) 1) (- x 3))) 1) -3/2)
  (check (derivative (lambda (x) (* 5 x)) 1/7) 5))

(run-tests)
