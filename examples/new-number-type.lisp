;;; new-number-type.lisp -- a kind of number added from outside the core
;;; (Phase 9 step 9.2)
;;;
;;; examples/dual.lisp defines dual numbers, a + b*eps with eps*eps = 0, as a
;;; Smalltalk Number subclass, with a read syntax. Here they are used like any
;;; other number.

(load "dual.lisp")

(define (show label x) (display label) (display " ") (write x) (newline))

;; The read syntax, and printing
(show "3+2eps reads as" 3+2eps)
(show "(dual 1/2 -1) prints as" (dual 1/2 -1))
(show "(string->number \"2-eps\") =" (string->number "2-eps"))

;; Ordinary arithmetic, mixed with integers, rationals and floats
(define d 3+eps)
(show "(+ d 1) =" (+ d 1))
(show "(+ 1 d) =" (+ 1 d))
(show "(* d d) =" (* d d))
(show "(* 1/2 d) =" (* 1/2 d))
(show "(- d 0.5) =" (- d 0.5))
(show "(/ 1 d) =" (/ 1 d))

;; Comparisons and predicates
(show "(= d 3+eps) =" (= d 3+eps))
(show "(< 2 d 4) =" (< 2 d 4))
(show "(number? d) =" (number? d))
(show "(exact? d) =" (exact? d))
(show "(real? d) =" (real? d))
(show "(exact? 1.5+eps) =" (exact? 1.5+eps))

;; What they are for: exact derivatives of ordinary procedures
(define (cube x) (* x x x))
(show "the derivative of x^3 at 2 is" (derivative cube 2))
(define (f x) (/ (+ (* x x) 1) (- x 3)))
(show "the derivative of (x^2+1)/(x-3) at 1 is" (derivative f 1))
(show "... and at 1/2 it is" (derivative f 1/2))
