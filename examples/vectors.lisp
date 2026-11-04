; vectors.lisp -- fixed-size, indexed data (Phase 7.8 section 6)
; #(...) is a vector constant; make-vector, vector and vector-copy make ones you
; can change. A vector is a Smalltalk Array, so it passes to Smalltalk as it is.

(define primes #(2 3 5 7 11))
(display (list (vector-length primes) (vector-ref primes 2)))
(newline)
(write (vector->list primes 1 3))
(newline)
(write (vector-map (lambda (p) (* p p)) primes))
(newline)

; Building one up.
(define squares (make-vector 5 0))
(do ((i 0 (+ i 1))) ((= i 5))
  (vector-set! squares i (* i i)))
(write squares)
(newline)
(write (list (vector 'a "b" #\c) (vector-append #(1) #(2 3)) (subvector primes 3 5)))
(newline)

; Quasiquote works inside vectors.
(define n 42)
(write `#(answer ,n ,@(list 'and 'more)))
(newline)
(display (equal? #(1 (2 "x")) (vector 1 (list 2 "x"))))
(newline)

; An insertion sort, in place.
(define (vector-sort! v less?)
  (do ((i 1 (+ i 1))) ((>= i (vector-length v)) v)
    (let ((x (vector-ref v i)))
      (let loop ((j (- i 1)))
        (if (and (>= j 0) (less? x (vector-ref v j)))
            (begin (vector-set! v (+ j 1) (vector-ref v j))
                   (loop (- j 1)))
            (vector-set! v (+ j 1) x))))))
(write (vector-sort! (vector-copy #(31 4 15 9 26 5)) <))
(newline)
(write (vector-sort! (vector "pear" "fig" "apple") string<?))
(newline)

; Smalltalk sees an Array.
(display [#(3 1 2) asSortedCollection])
(newline)
