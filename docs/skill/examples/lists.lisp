;; lists.lisp -- the list procedures that exist, and map and for-each with one list
(define nums (list 3 1 4 1 5))
(display (car nums)) (newline)              ; the first element
(display (cdr nums)) (newline)              ; the rest
(display (cons 9 nums)) (newline)
(display (append nums (list 9 2))) (newline)
(display (reverse nums)) (newline)
(display (length nums)) (newline)
(display (map (lambda (n) (* n n)) nums)) (newline)
(for-each (lambda (n) (display n) (display " ")) nums)
(newline)
(display (assoc "b" (list (cons "a" 1) (cons "b" 2)))) (newline)
(display (null? '())) (newline)             ; test for the empty list with null?
