;;; phase-9.2-procedures.lisp -- the numeric procedures and multiple values
;;; (specs/phase-9-language.md step 9.2b, AC-2; R7RS 6.2.6 and 6.10).
(load "../../lib/test.lisp")

(define (values->list thunk) (call-with-values thunk list))

;;; Multiple values

(define-test "AC-2 values and call-with-values"
  (check (values->list (lambda () (values 1 2 3))) '(1 2 3))
  (check (values->list (lambda () (values))) '())
  (check (values->list (lambda () 7)) '(7))
  (check (values 5) 5)
  (check (call-with-values (lambda () (values 1 2)) +) 3)
  (check-written (values 1 "two" 'three) "1 \"two\" three"))

(define-test "AC-2 call-with-values calls its consumer as a tail call"
  (define (count-down n) (if (= n 0) 'done (call-with-values (lambda () (values (- n 1))) count-down)))
  (check (count-down 100000) 'done))

(define-test "AC-2 let-values and let*-values"
  (check (let-values (((a b) (values 1 2)) ((c) (values 3))) (list a b c)) '(1 2 3))
  (check (let-values (((a . rest) (values 1 2 3)) (all (values 4 5))) (list a rest all)) '(1 (2 3) (4 5)))
  (check (let ((a 'outer)) (let-values (((a) (values 1)) ((b) (values a))) (list a b))) '(1 outer))
  (check (let*-values (((a b) (values 1 2)) ((c) (values (+ a b)))) c) 3)
  (check (let-values () 'empty) 'empty))

;;; Rounding

(define-test "AC-2 floor, ceiling, truncate, round keep exactness"
  (check (map floor (list 2.5 -2.5 7/2 -7/2 3)) (list 2.0 -3.0 3 -4 3))
  (check (map ceiling (list 2.5 -2.5 7/2 3)) (list 3.0 -2.0 4 3))
  (check (map truncate (list 2.7 -2.7 -7/2)) (list 2.0 -2.0 -3))
  (check-written (ceiling -0.5) "-0.0")
  (check-written (list (floor +inf.0) (round +nan.0)) "(+inf.0 +nan.0)"))

(define-test "AC-2 round goes to even on a half"
  (check (map round (list 0.5 1.5 2.5 -2.5 2.6 5/2 7/2 -7/2 1/3)) (list 0.0 2.0 2.0 -2.0 3.0 2 4 -4 0)))

;;; The division family

(define-test "AC-2 floor/ and truncate/ answer two values"
  (check (values->list (lambda () (floor/ 5 2))) '(2 1))
  (check (values->list (lambda () (floor/ -5 2))) '(-3 1))
  (check (values->list (lambda () (floor/ 5 -2))) '(-3 -1))
  (check (values->list (lambda () (floor/ -5 -2))) '(2 -1))
  (check (values->list (lambda () (truncate/ 5 2))) '(2 1))
  (check (values->list (lambda () (truncate/ -5 2))) '(-2 -1))
  (check (values->list (lambda () (truncate/ 5 -2))) '(-2 1))
  (check (values->list (lambda () (truncate/ -5.0 2))) '(-2.0 -1.0)))

(define-test "AC-2 the quotients and remainders, and the old names"
  (check (list (floor-quotient -7 2) (floor-remainder -7 2) (truncate-quotient -7 2) (truncate-remainder -7 2)) '(-4 1 -3 -1))
  (check (list (quotient 17 5) (remainder 17 -5) (modulo 17 -5) (modulo -7 2)) '(3 2 -3 1))
  (check (list (quotient 7.0 2) (modulo 7 2.0)) '(3.0 1.0))
  (check (list (modulo 123456789012345678901234567891 7) (modulo -123456789012345678901234567891 7)) (list 1 6))
  (check-error (quotient 1 0) "quotient: division by zero")
  (check-error (modulo 1.5 1) "modulo: not an integer: 1.5")
  (check-error (remainder 'a 1) "remainder: not an integer: a"))

;;; Rationals and integers

(define-test "AC-2 numerator, denominator"
  (check (list (numerator 6/4) (denominator 6/4) (numerator 5) (denominator 5) (numerator -1/2)) '(3 2 5 1 -1))
  (check (list (numerator 0.5) (denominator 0.5)) '(1.0 2.0))
  (check-error (numerator +inf.0) "numerator: not a rational number"))

(define-test "AC-2 gcd, lcm, abs, square"
  (check (list (gcd 32 -36) (gcd) (gcd 7) (lcm 32 -36) (lcm) (lcm 0 5)) '(4 0 7 288 1 0))
  (check (list (gcd 32.0 -36) (lcm 4 6.0)) '(4.0 12.0))
  (check (list (abs -7) (abs -7/2) (abs -2.5) (abs 0)) (list 7 7/2 2.5 0))
  (check (list (square 5) (square -1/2) (square 1.5)) (list 25 1/4 2.25))
  (check-written (abs -inf.0) "+inf.0"))

;;; Roots and powers

(define-test "AC-2 sqrt: exact for an exact perfect square"
  (check (list (sqrt 16) (sqrt 1/4) (sqrt 0) (sqrt 1000000000000000000000000000000)) (list 4 1/2 0 1000000000000000))
  (check (list (sqrt 16.0) (sqrt 2.25)) '(4.0 1.5))
  (check-true (inexact? (sqrt 2)))
  (check (sqrt 2) 1.4142135623730951)
  (check-error (sqrt -4) "sqrt: no real square root of -4"))

(define-test "AC-2 exact-integer-sqrt answers two values"
  (check (values->list (lambda () (exact-integer-sqrt 17))) '(4 1))
  (check (values->list (lambda () (exact-integer-sqrt 16))) '(4 0))
  (check-error (exact-integer-sqrt 2.0) "not an exact non-negative integer"))

(define-test "AC-2 expt"
  (check (list (expt 2 10) (expt 2 -2) (expt 1/2 3) (expt -2 3) (expt 0 0) (expt 0 5)) (list 1024 1/4 1/8 -8 1 0))
  (check (expt 2 100) 1267650600228229401496703205376)
  (check (list (expt 2.0 3) (expt 0.0 0) (expt 4 1/2)) (list 8.0 1.0 2))
  (check-true (inexact? (expt 2 0.5)))
  (check-written (expt 0.0 -1) "+inf.0")
  (check-error (expt 0 -1) "division by zero")
  (check-error (expt -8 1/3) "no real value"))

(define-test "AC-2 rationalize: the simplest rational within the tolerance"
  (check (rationalize 3/10 1/10) 1/3)
  (check (rationalize 1/3 1/100) 1/3)
  (check (rationalize 5 1/2) 5)
  (check (rationalize -3/10 1/10) -1/3)
  (check (rationalize .3 1/10) #i1/3)
  (check (rationalize 1/4 1/4) 0))

;;; Transcendental functions

(define-test "AC-2 exp, log, sin, cos, tan, asin, acos, atan"
  (check (list (exp 0) (log 1) (sin 0) (cos 0) (tan 0) (asin 0) (acos 1) (atan 0)) '(1.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0))
  (check (log 8 2) 3.0)
  (check (log 100 10) 2.0)
  (check (atan 1 1) (atan 1))
  (check-written (list (log 0) (log -1) (asin 2) (sin +inf.0)) "(-inf.0 +nan.0 +nan.0 +nan.0)")
  (check-true (< (abs (- (exp 1) 2.718281828459045)) 1e-15))
  (check-error (exp 'a) "exp: not a real number: a"))

(run-tests)
