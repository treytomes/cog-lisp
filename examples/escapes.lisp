; escapes.lisp -- writing any character in a string (Phase 7.9 section 7)

(define greek "\x3bb; is lambda, \x3c0; is pi")
(display greek)
(newline)
(display (string-length "\x3bb;"))
(newline)

; Escapes for the usual control characters.
(write (map char->integer (string->list "\t\n\r\a\b")))
(newline)

; write shows control characters so they cannot hide; display prints them as they are.
(define bell (string #\a (integer->char 7) #\b))
(write bell)
(newline)
(write (string (integer->char 1) (integer->char 27)))
(newline)

; Whatever write prints reads back as the same string.
(define tricky (string #\" #\\ (integer->char 0) (integer->char 31) #\x))
(display (equal? tricky (read (open-input-string (with-output-to-string (lambda () (write tricky)))))))
(newline)
