;; no-inherit.lisp -- a fixture library that uses a name its loader imported but
;; it did not: a library starts with no imports, so area is its own, undefined
(library no-inherit (export try-area))

(define (try-area) (area 2 3))
