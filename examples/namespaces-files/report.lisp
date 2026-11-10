; report.lisp -- a program file, loaded by main.lisp: it sees main.lisp's imports
(define (report xs) (string-append "mean " (number->string (mean xs))))
