; big-code.lisp -- code the size a code generator writes (Phase 7.9 section 4)
; Deep nesting and many parameters used to stop at Pharo's limits; now they compile.

; A call nested 60 deep, built as data and then compiled with eval.
(define (nest depth)
  (if (= depth 0) 0 (list '+ 1 (nest (- depth 1)))))
(display (eval (nest 60)))
(newline)

; A list built by 100 nested conses.
(define (conses n)
  (if (= n 0) ''() (list 'cons n (conses (- n 1)))))
(display (length (eval (conses 100))))
(newline)

; A procedure with 20 parameters (Pharo blocks take at most 15).
(define (weighted a b c d e f g h i j k l m n o p q r s t)
  (+ a (* 2 b) (* 3 c) t))
(display (weighted 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 10))
(newline)

; ... built and called by a program, with a rest parameter too.
(define (iota n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc)))))
(define params (map (lambda (i) (string->symbol (string-append "p" (number->string i)))) (iota 25)))
(define sum-25 (eval `(lambda (,@params . more) (+ ,@params (length more)))))
(display (apply sum-25 (append (iota 25) '(x y))))
(newline)
(display (guard (e ((error-object? e) (error-object-message e))) (sum-25 1 2)))
(newline)
