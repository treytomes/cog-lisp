; interop-callbacks.lisp -- Smalltalk calling LISP (Phase 7.6 section 5)

; A LISP procedure works wherever Smalltalk expects a block. This one ends in a
; tail call (to its helper); it still answers a plain value to Smalltalk.
(define (classify n) (describe-parity n))
(define (describe-parity n) (if (= (modulo n 2) 0) 'even 'odd))
(display (array->list [[1 to: 4] collect: classify]))
(newline)

; A loop written as LISP tail calls, called by Smalltalk for each element.
(define (count-down n acc) (if (= n 0) acc (count-down (- n 1) (+ acc 1))))
(display (array->list [[100000 to: 100002] collect: (lambda (n) (count-down n 0))]))
(newline)

; Smalltalk errors can be caught with a LISP handler: on:do: with LISP
; procedures as both the protected block and the handler.
(display [(lambda () (/ 1 0)) on: (smalltalk ZeroDivide) do: (lambda (e) "caught a division by zero")])
(newline)
(display [(lambda () [3 frobnicate]) on: (smalltalk MessageNotUnderstood)
                                      do: (lambda (e) [[e message] selector])])
(newline)

; ensure: runs its LISP block however the protected one ends.
(define log '())
[(lambda () (set! log (cons 'body log))) ensure: (lambda () (set! log (cons 'cleanup log)))]
(display (reverse log))
(newline)

; procedure->block makes a real BlockClosure, for code that needs one.
(define blk (procedure->block (lambda (a b) (* a b))))
(display (list [blk class] [blk numArgs] [blk value: 6 value: 7]))
(newline)

; Smalltalk can evaluate and call LISP through the CogLisp class.
(define (square x) (* x x))
(display [CogLisp call: "square" with: 12])
(newline)
(display [CogLisp eval: "(map square '(1 2 3))"])
(newline)
(display [[CogLisp at: "square"] value: 9])
(newline)
