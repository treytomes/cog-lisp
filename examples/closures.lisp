; closures.lisp -- each counter keeps its own private state

(define (make-counter)
  (let ((count 0))
    (lambda ()
      (set! count (+ count 1))
      count)))

(define a (make-counter))
(define b (make-counter))

(a)
(a)
(a)
(b)

(display "a has counted to ")
(display (a))
(display ", b to ")
(display (b))
(newline)

; procedures remember the text they were compiled from
(display (procedure-source make-counter))
(newline)
