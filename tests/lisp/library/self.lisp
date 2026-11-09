;; self.lisp -- requires itself, which must not loop
(require 'self)
(define (self-loaded) #t)
