; places.lisp -- assigning to a place: set! of a list's element, a vector's slot, a table's entry
;
; set! takes a variable, or a call that names a place: (set! (car x) v) sets
; the first element of x. This is SRFI 17's generalized set!: it calls
; ((setter car) x v), and car's setter is set-car!. The built-in getters
; (car, cdr, vector-ref, string-ref, hash-table-ref, hash-table-ref/default)
; have setters, and a program gives its own procedure one with
; (set! (setter f) g).

(define x (list 'a 'b 'c))
(set! (car x) 'n)
(display x) (newline)

(define board (vector '- '- '-))
(set! (vector-ref board 1) 'x)
(display board) (newline)

; a counter: hash-table-ref/default's setter ignores the default
(define seen (make-hash-table))
(for-each (lambda (word)
            (set! (hash-table-ref/default seen word 0)
                  (+ 1 (hash-table-ref/default seen word 0))))
          '("to" "be" "or" "not" "to" "be"))
(display (list (hash-table-ref seen "to") (hash-table-ref seen "or"))) (newline)

; a getter of our own, with its setter
(define (middle triple) (car (cdr triple)))
(set! (setter middle) (lambda (triple value) (set-car! (cdr triple) value)))
(define t3 (list 1 2 3))
(set! (middle t3) 'two)
(display t3) (newline)
