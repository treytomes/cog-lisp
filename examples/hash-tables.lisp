; hash-tables.lisp -- tables from keys to values (Phase 7.8 section 7, SRFI 69 names)
; Keys are compared with equal? unless you ask for eq? or eqv?, so strings and
; lists work as keys. Keys come back in the order they were first added.

; Counting words.
(define (word-counts words)
  (let ((counts (make-hash-table)))
    (for-each (lambda (w) (hash-table-update!/default counts w (lambda (n) (+ n 1)) 0))
              words)
    counts))
(define counts (word-counts (string-split "the cat and the hat and the bat" #\space)))
(display counts)
(newline)
(write (hash-table->alist counts))
(newline)
(display (list (hash-table-ref/default counts "the" 0) (hash-table-ref/default counts "dog" 0)))
(newline)

; Lists as keys: a table of coordinates.
(define grid (make-hash-table))
(hash-table-set! grid '(0 0) 'origin)
(hash-table-set! grid (list 2 3) 'treasure)
(display (list (hash-table-ref grid '(2 3)) (hash-table-contains? grid '(1 1))))
(newline)

; A missing key: a default, a procedure to compute one, or an error.
(display (hash-table-ref grid '(9 9) (lambda () 'nothing-here)))
(newline)
(display (guard (e ((error-object? e) (error-object-message e)))
  (hash-table-ref grid '(9 9))))
(newline)

; An eq? table for symbols, and walking a table.
(define ages (make-hash-table eq?))
(hash-table-set! ages 'lisp 1958)
(hash-table-set! ages 'smalltalk 1972)
(hash-table-set! ages 'scheme 1975)
(hash-table-walk ages (lambda (k v) (display k) (display ": ") (display v) (newline)))
(hash-table-delete! ages 'scheme)
(display (list (hash-table-count ages) (hash-table-keys ages) (hash-table-values ages)))
(newline)

; From an association list, and copying.
(define colors (alist->hash-table '((red . "#f00") (green . "#0f0")) eq?))
(define more (hash-table-copy colors))
(hash-table-set! more 'blue "#00f")
(display (list (hash-table-count colors) (hash-table-count more)))
(newline)
