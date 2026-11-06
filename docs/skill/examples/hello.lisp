;; hello.lisp -- define a procedure, build text, print it
(define (greet name)
  (string-append "Hello, " name "!"))

(display (greet "world"))
(newline)
(display (string-append "2 + 3 = " (number->string (+ 2 3))))
(newline)
(display "text")   ; display prints text as it is
(newline)
(write "text")     ; write prints it as code, quotes and all
(newline)
