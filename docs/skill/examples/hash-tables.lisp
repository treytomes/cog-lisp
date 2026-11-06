;; hash-tables.lisp -- count words with a hash table
(define counts (make-hash-table))
(for-each (lambda (word)
            (hash-table-set! counts word (+ 1 (hash-table-ref/default counts word 0))))
          (string-split "the cat and the hat and the bat" #\space))
(for-each (lambda (word)
            (display word) (display ": ")
            (display (hash-table-ref/default counts word 0)) (newline))
          (list "the" "and" "cat" "dog"))
