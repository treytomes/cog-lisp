;; macros.lisp -- a hygienic macro with define-syntax and syntax-rules
(define-syntax swap!
  (syntax-rules ()
    ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))

(define x 1)
(define y 2)
(swap! x y)
(display (list x y)) (newline)
