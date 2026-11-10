; palette.lisp -- a library of colors, to import in pieces
(library palette (export red green blue mix all))

(define (red) "#ff0000")
(define (green) "#00ff00")
(define (blue) "#0000ff")
(define (mix a b) (list 'mix a b))
(define (all) '(red green blue))
