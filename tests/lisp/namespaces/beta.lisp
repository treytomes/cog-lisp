;; beta.lisp -- a fixture library: another rule, and more to import in pieces
(library beta (export rule area perimeter shared))

(define (rule n) (string-append "beta " (number->string n)))
(define (area w h) (* w h))
(define (perimeter w h) (* 2 (+ w h)))
(define (shared) 'beta)
