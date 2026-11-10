;; gamma.lisp -- a fixture library with imports of its own (cl's first), and a
;; name of its own (remove) that shadows a built-in in its file only. All of cl
;; would bring cl's remove too, which this library defines: so only first.
(library gamma (export head-of keep-odd))
(require 'cl 'only '(first))

(define (head-of l) (first l))
(define (remove x l) (filter (lambda (y) (not (equal? x y))) l))
(define (keep-odd l) (remove 2 (remove 4 l)))
