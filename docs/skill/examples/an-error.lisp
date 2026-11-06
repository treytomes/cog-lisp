;; an-error.lisp -- what an error looks like: file:line:column, then the message
(define (first-of x) (car x))
(display "before") (newline)
(first-of 5)
(display "never printed") (newline)
