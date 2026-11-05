;;; numbers.lisp -- the numeric tower (Phase 9 step 9.2)
;;;
;;; Three kinds of number: exact integers of any size, exact rationals, and
;;; inexact reals (64-bit floats). Exact arithmetic stays exact; a float anywhere
;;; makes the answer inexact.

(define (show label x) (display label) (display " ") (write x) (newline))

;; Exact rationals read, print and compute exactly.
(show "1/3 + 1/6 =" (+ 1/3 1/6))
(show "-6/4 reads as" -6/4)
(show "(* 1/3 3) =" (* 1/3 3))
(show "2 to the 100th =" (* 1024 1024 1024 1024 1024 1024 1024 1024 1024 1024))

;; Exactness: exact? asks, exact and inexact convert. A float's exact value is
;; exactly what the float holds, which shows why 0.1 is not one tenth.
(show "(exact? 1/2) =" (exact? 1/2))
(show "(inexact 1/3) =" (inexact 1/3))
(show "(exact 0.5) =" (exact 0.5))
(show "(exact 0.1) =" (exact 0.1))
(show "(integer? 2.0) =" (integer? 2.0))

;; The prefixes: #x #o #b #d choose the radix, #e #i the exactness.
(show "#xff #b1010 #o777 =" (list #xff #b1010 #o777))
(show "#e1.25 =" #e1.25)
(show "#i3/8 =" #i3/8)
(show "(number->string 255 2) =" (number->string 255 2))
(show "(string->number \"1/a\" 16) =" (string->number "1/a" 16))

;; Infinities and NaN: dividing a float by zero follows IEEE; an exact zero
;; divisor of an exact number is still an error.
(show "(/ 1.0 0) =" (/ 1.0 0))
(show "(- (/ 1.0 0)) =" (- (/ 1.0 0)))
(show "(/ 0.0 0) =" (/ 0.0 0))
(show "(nan? +nan.0) =" (nan? +nan.0))
(show "(infinite? -inf.0) =" (infinite? -inf.0))
(show "(/ 1 0) is" (guard (e (#t (error-object-message e))) (/ 1 0)))

;; Arithmetic on something that is not a number is an error that says so.
(show "(+ 1 'apple) is" (guard (e (#t (error-object-message e))) (+ 1 'apple)))
