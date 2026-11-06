;; errors.lisp -- signal an error, and catch one with guard
(define (safe-divide a b)
  (guard (e (#t (display "caught: ")
                (display (error-object-message e))
                (newline)
                0))
    (if (= b 0)
        (error "cannot divide by zero" a)
        (/ a b))))
(display (safe-divide 10 2)) (newline)
(display (safe-divide 1 0)) (newline)
(display (/ 1 3)) (newline)                 ; exact: a fraction
(display (exact->inexact (/ 1 3))) (newline)
