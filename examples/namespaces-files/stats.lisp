; stats.lisp -- a library with one export
(library stats (export mean))

(define (mean xs) (/ (apply + xs) (length xs)))
