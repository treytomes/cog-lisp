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

; keep only the elements that satisfy keep?
(define (filter keep? lst)
  (if (null? lst)
      '()
      (if (keep? (car lst))
          (cons (car lst) (filter keep? (cdr lst)))
          (filter keep? (cdr lst)))))

(show "evens" (filter (lambda (n) (= (modulo n 2) 0)) nums))

(define (sum lst)
  (if (null? lst)
      0
      (+ (car lst) (sum (cdr lst)))))

(show "sum" (sum nums))
(show "a dotted pair" (cons 'a 'b))
