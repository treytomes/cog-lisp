; lists.lisp -- building and taking apart lists

(define nums '(1 2 3 4 5))

(define (show label value)
  (display label)
  (display ": ")
  (display value)
  (newline))

(show "squares" (map (lambda (x) (* x x)) nums))
(show "appended" (append nums '(6 7)))
(show "reversed" (reverse nums))

; keep only the elements that satisfy keep?: the built-in filter does this; here
; is how such a procedure is written
(define (keep-if keep? lst)
  (if (null? lst)
      '()
      (if (keep? (car lst))
          (cons (car lst) (keep-if keep? (cdr lst)))
          (keep-if keep? (cdr lst)))))

(show "evens" (keep-if (lambda (n) (= (modulo n 2) 0)) nums))

(define (sum lst)
  (if (null? lst)
      0
      (+ (car lst) (sum (cdr lst)))))

(show "sum" (sum nums))
(show "a dotted pair" (cons 'a 'b))
