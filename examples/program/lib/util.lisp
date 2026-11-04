; program/lib/util.lisp -- helpers loaded by program/main.lisp

; The last part of a path, on Windows or Linux:
; "C:\a\b\main.lisp" or "/a/b/main.lisp" -> "main.lisp"
(define (file-name path)
  (let loop ((i (- (string-length path) 1)))
    (cond ((< i 0) path)
          ((memv (string-ref path i) '(#\/ #\\)) (substring path (+ i 1) (string-length path)))
          (else (loop (- i 1))))))

(define (shout s) (string-append (string-upcase s) "!"))

(display (string-append "loaded " (file-name (current-load-path))))
(newline)
