; shapes.lisp -- a small library: its first form names it and lists its exports
(library shapes (export area perimeter))

(define (area w h) (* w h))
(define (perimeter w h) (* 2 (+ w h)))
