;; uses-geometry.lisp -- a fixture program that imports es-geometry under a prefix
(require "geometry.lisp" 'prefix 'geo:)

(define (ring r) (- (geo:area r) (geo:area (/ r 2))))
(display (geo:with-unit cm (ring 2)))
