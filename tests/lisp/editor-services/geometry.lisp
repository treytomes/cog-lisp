;; geometry.lisp -- a fixture library (tests/lisp/editor-services.lisp): an
;; exported procedure with documentation, a private helper, a macro
(library es-geometry (export area perimeter with-unit))

(define (%square x) (* x x))

(define (area r)
  "(area r)
The area of a circle of radius r."
  (* 3 (%square r)))

(define (perimeter r) (* 6 r))

(define-syntax with-unit
  "(with-unit u e)
e, said in unit u."
  (syntax-rules () ((_ u e) (list e 'u))))
