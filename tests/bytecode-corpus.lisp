; Procedures whose bytecode must not change when the compiler changes in ways
; that should not affect them (Phase 7.9 AC-2: the nesting spill, the
; dispatch table and the template cache). tests/phase-7.9-groundwork.st
; disassembles each and compares with tests/bytecode-corpus.expected.
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(define (tak x y z) (if (not (< y x)) z (tak (tak (- x 1) y z) (tak (- y 1) z x) (tak (- z 1) x y))))
(define (count-loop n acc) (if (= n 0) acc (count-loop (- n 1) (+ acc 1))))
(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))
(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))
(define (sum-list lst acc) (if (null? lst) acc (sum-list (cdr lst) (+ acc (car lst)))))
(define (make-counter) (let ((n 0)) (lambda () (set! n (+ n 1)) n)))
(define (classify x) (cond ((< x 0) 'neg) ((= x 0) 'zero) (else (case x ((1 2 3) 'small) (else 'big)))))
(define (qq a b) `(a ,a b ,@b end))
(define (with-locals x) (define (sq y) (* y y)) (define z (sq x)) (list z (sq z)))
(define (loop-do n) (do ((i 0 (+ i 1)) (s 0 (+ s i))) ((= i n) s)))
(define (send-it c) [c add: 1] [c size])
(define (guarded f) (guard (e (#t 'caught)) (f)))
