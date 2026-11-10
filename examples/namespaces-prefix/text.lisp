; text.lisp -- a library whose rule draws a line
(library text (export rule))

(define (rule n) (make-string n #\-))
