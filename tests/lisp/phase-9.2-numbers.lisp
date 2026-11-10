;;; phase-9.2-numbers.lisp -- the numeric tower (specs/15-phase-9-language.md step
;;; 9.2, AC-2; review R-11 and R-21): reading, printing, the predicates,
;;; exactness, IEEE division, type errors.
(load "../../lib/test.lisp")

(define (read-1 s) (read (open-input-string s)))

;;; Reading

(define-test "AC-2 rationals read, normalized"
  (check '(1/3 -6/4 4/2 0/5) (list 1/3 -3/2 2 0))
  (check-true (exact? 1/3))
  (check (+ 1/3 1/6) 1/2))

(define-test "AC-2 decimals: every form R7RS allows"
  (check (list 1.5 .5 5. 1e3 1E3 -2.5e-1 +5) (list 1.5 0.5 5.0 1000.0 1000.0 -0.25 5))
  (check-written -0.0 "-0.0"))

(define-test "AC-2 radix and exactness prefixes, in either order"
  (check (list #x1F #XFF #b101 #o17 #d10 #x-a) (list 31 255 5 15 10 -10))
  (check (list #e1.1 #e1e3 #e.5) (list 11/10 1000 1/2))
  (check (list #i1/4 #i3) (list 0.25 3.0))
  (check (list #x#e1/2 #e#x10 #i#b11) (list 1/2 16 3.0)))

(define-test "AC-2 infinities and NaN"
  (check-written (list +inf.0 -inf.0 +nan.0 -nan.0 +INF.0) "(+inf.0 -inf.0 +nan.0 +nan.0 +inf.0)")
  (check-true (> +inf.0 1e308))
  (check-true (< -inf.0 -1e308)))

(define-test "AC-2 tokens that only look like numbers stay symbols"
  (check (map symbol? '(+ - ... -> 1+ -x a1 1/x 1/ /2 1.2.3 ++1 1e e3)) '(#t #t #t #t #t #t #t #t #t #t #t #t #t #t)))

(define-test "AC-2 errors: a zero denominator, and # syntax that is no number"
  (check-error (read-1 "1/0") "division by zero: 1/0")
  (check-error (read-1 "#x1/0") "division by zero")
  (check-error (read-1 "#e+inf.0") "unknown # syntax")
  (check-error (read-1 "#x1.5") "unknown # syntax")
  (check-error (read-1 "#e#e1") "unknown # syntax")
  (check-error (read-1 "#x#b1") "unknown # syntax"))

(define-test "AC-2 string->number reads the same, with a radix"
  (check (map string->number '("1/3" "#b101" "1e2" "-0.5" "+inf.0")) (list 1/3 5 100.0 -0.5 +inf.0))
  (check (list (string->number "ff" 16) (string->number "-101" 2) (string->number "17" 8) (string->number "1/a" 16)) (list 255 -5 15 1/10))
  (check (map string->number '("1/0" "abc" "" "1.5" " 1" "#e+nan.0")) '(#f #f #f 1.5 #f #f))
  (check (string->number "1.5" 16) #f)
  (check-error (string->number "1" 7) "the radix must be 2, 8, 10 or 16"))

;;; Printing

(define-test "AC-2 printing reads back"
  (check-written (list 1/3 -6/4 0.1 1e100 1e-7 123.0) "(1/3 -3/2 0.1 1.0e100 1.0e-7 123.0)")
  (for-each (lambda (x) (check (read-1 (number->string x)) x))
            (list 1/3 -7/2 0.1 1e300 -1e-300 12345678901234567890 2.5)))

(define-test "AC-2 number->string with a radix, for rationals too"
  (check (list (number->string 255 16) (number->string 1/3 2) (number->string -10 8) (number->string 3/4 16)) '("ff" "1/11" "-12" "3/4"))
  (check (number->string 1.5) "1.5")
  (check-error (number->string 1.5 2) "radix 2 is for exact numbers")
  (check-error (number->string 'a) "not a number: a"))

;;; Predicates (R-11)

(define-test "AC-2 integer? and rational? of floats (R-11)"
  (check (map integer? (list 2.0 2.5 2 1/2 +inf.0 +nan.0)) '(#t #f #t #f #f #f))
  (check (map rational? (list 1.5 1/2 3 +inf.0 +nan.0)) '(#t #t #t #f #f))
  (check (map real? (list 1 1/2 1.5 +inf.0 'a "1")) '(#t #t #t #t #f #f))
  (check (map complex? (list 1 1.5 'a)) '(#t #t #f))
  (check (map number? (list 1 1/2 1.5 +nan.0 'a #\1)) '(#t #t #t #t #f #f)))

(define-test "AC-2 exactness"
  (check (map exact? (list 1 1/2 1.0 +inf.0)) '(#t #t #f #f))
  (check (map inexact? (list 1 1.0)) '(#f #t))
  (check (map exact-integer? (list 2 2.0 1/2 'a)) '(#t #f #f #f))
  (check (map exact-rational? (list 2 1/2 0.5)) '(#t #t #f))
  (check-error (exact? 'a) "exact?: not a number: a"))

(define-test "AC-2 nan?, infinite?, finite? (R-21)"
  (check (map nan? (list +nan.0 1.0 1 +inf.0)) '(#t #f #f #f))
  (check (map infinite? (list +inf.0 -inf.0 +nan.0 1e308 5)) '(#t #t #f #f #f))
  (check (map finite? (list 1 1.5 +inf.0 +nan.0)) '(#t #t #f #f))
  (check-error (nan? "x") "nan?: not a number"))

(define-test "AC-2 zero?, positive?, negative?, odd?, even?"
  (check (list (zero? 0) (zero? 0.0) (zero? -0.0) (zero? 1/2)) '(#t #t #t #f))
  (check (list (positive? 1/2) (negative? -inf.0) (positive? 0)) '(#t #t #f))
  (check (list (odd? 3) (odd? 3.0) (even? -4) (even? 0)) '(#t #t #t #t))
  (check-error (odd? 1.5) "odd?: not an integer: 1.5")
  (check-error (zero? 'a) "zero?: not a number: a")
  (check-error (positive? 'a) "positive?: not a real number: a"))

;;; Exactness conversions

(define-test "AC-2 exact and inexact, and the old names"
  (check (exact 0.1) 3602879701896397/36028797018963968)
  (check (list (exact 2.0) (exact 2.5) (exact 7) (exact -0.0)) (list 2 5/2 7 0))
  (check (list (inexact 1/4) (inexact 3) (inexact 1.5)) '(0.25 3.0 1.5))
  (check (list (inexact->exact 0.5) (exact->inexact 1/2)) (list 1/2 0.5))
  (check-error (exact +inf.0) "exact: no exact value for +inf.0")
  (check-error (exact +nan.0) "no exact value"))

;;; Division and type errors

(define-test "AC-2 division by zero: exact is an error, a float gives IEEE's answer"
  (check-error (/ 1 0) "division by zero")
  (check-error (/ 0) "division by zero")
  (check-written (list (/ 1.0 0) (/ -1 0.0) (/ 1 -0.0) (/ 0.0 0) (/ 1.0 0.0) (/ 2 0.0 1)) "(+inf.0 -inf.0 -inf.0 +nan.0 +inf.0 +inf.0)")
  (check (/ 1 4) 1/4)
  (check (/ 2) 1/2))

(define-test "AC-2 arithmetic on a non-number is an error, not an answer (R-11)"
  (check-error (+ 'a) "+: not a number: a")
  (check-error (* 'a) "*: not a number: a")
  (check-error (- 'a) "-: not a number: a")
  (check-error (/ 'a) "/: not a number: a")
  (check-error (+ 1 'a) "+: not a number: a")
  (check-error (+ 'a 1) "+: not a number: a")
  (check-error (min 'a) "min: not a real number: a")
  (check-error (+ 1 "3") "+: not a number: a string or a character")
  (check-error (apply + (list 1 2 'x)) "+: not a number: x"))

(define-test "AC-2 min and max are inexact if any argument is"
  (check (list (min 1 2.0) (max 1 2.0) (max 1/2 1/3) (min 3)) (list 1.0 2.0 1/2 3))
  (check (max 1 2 3.0 0) 3.0))

(define-test "AC-2 mixed arithmetic keeps exactness where it can"
  (check (list (+ 1/2 1/2) (* 2 1/2) (+ 1/2 0.5) (- 1/3 1/3)) (list 1 1 1.0 0))
  (check-true (exact? (* 1/3 3)))
  (check-false (exact? (* 1/3 3.0))))

(run-tests)
