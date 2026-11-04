; program/lib/util.lisp -- helpers loaded by program/main.lisp

; The last part of a path: "C:\a\b\main.lisp" -> "main.lisp"
(define (file-name path)
  (let loop ((parts (string-split path #\\)))
    (if (null? (cdr parts)) (car parts) (loop (cdr parts)))))

(define (shout s) (string-append (string-upcase s) "!"))

(display (string-append "loaded " (file-name (current-load-path))))
(newline)
