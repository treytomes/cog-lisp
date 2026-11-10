; engine.lisp -- a library whose rule makes an inference rule
(library engine (export rule))

(define (rule head . body) (list 'if body 'then head))
