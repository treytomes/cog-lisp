; cycles.lisp -- structures that point back at themselves (Phase 7.9 section 6)

; A circular list: its last pair points at its first.
(define (circular . items)
  (let ((l (apply list items)))
    (let loop ((p l))
      (if (pair? (cdr p)) (loop (cdr p)) (set-cdr! p l)))
    l))

(define days (circular 'mon 'tue 'wed))
(write days)                                       ; datum labels: no endless printing
(newline)
(display (list (car days) (car (cdr (cdr (cdr days))))))   ; round and round
(newline)

; A tiny graph with back pointers: each node is (name . neighbours).
(define a (list 'a))
(define b (list 'b))
(set-cdr! a (list b))
(set-cdr! b (list a))
(write a)
(newline)

; equal? compares cyclic structures without looping.
(display (list (equal? (circular 1 2) (circular 1 2))
               (equal? (circular 1 2) (circular 1 2 1 2))   ; the same infinite list
               (equal? (circular 1 2) (circular 2 1))))
(newline)

; Shared but not cyclic: write prints it plainly; write-shared shows the sharing.
(define tail (list 'x 'y))
(define two (list tail tail))
(write two)
(newline)
(write-shared two)
(newline)

; What write prints, read reads back as the same shape.
(define copy (read (open-input-string (with-output-to-string (lambda () (write days))))))
(display (list (equal? copy days) (eq? copy (cdr (cdr (cdr copy))))))
(newline)
