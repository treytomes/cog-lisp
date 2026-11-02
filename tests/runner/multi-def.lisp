; several definitions, then a final display
(define (square x) (* x x))
(define (sum-of-squares a b) (+ (square a) (square b)))
(define answer (sum-of-squares 3 4))
(display "3^2 + 4^2 = ")
(display answer)
(newline)
