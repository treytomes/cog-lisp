; factorial.lisp -- recursion, and integers that grow past 64 bits

(define (factorial n)
  (if (= n 0)
      1
      (* n (factorial (- n 1)))))

(define (show-row n)
  (display n)
  (display "! = ")
  (display (factorial n))
  (newline))

(define (count-up from to)
  (if (<= from to)
      (begin
        (show-row from)
        (count-up (+ from 1) to))))

(count-up 0 10)
(show-row 25)   ; a bignum, courtesy of the host's integers
