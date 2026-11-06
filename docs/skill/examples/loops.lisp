;; loops.lisp -- loop with a named let (or do); there is no loop macro
(define (sum-to n)
  (let loop ((i 1) (total 0))
    (if (> i n)
        total
        (loop (+ i 1) (+ total i)))))
(display (sum-to 100)) (newline)

(do ((i 0 (+ i 1)))
    ((= i 3))
  (display i)
  (display " "))
(newline)

(define count 0)
(set! count (+ count 1))           ; set! changes a variable
(display count) (newline)
