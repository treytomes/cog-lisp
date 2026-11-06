;; strings.lisp -- strings and characters
(define s "Hello world")
(display (string-length s)) (newline)
(display (substring s 0 5)) (newline)       ; from 0, up to (not including) 5
(display (string-upcase s)) (newline)
(display (string-ref s 1)) (newline)        ; a character
(display (string-split s #\space)) (newline)
(display (string-join (list "a" "b" "c") "-")) (newline)
(display (list->string (reverse (string->list "abc")))) (newline)
(display (string->number "42")) (newline)
(define buffer (string-copy "cat"))         ; a literal cannot be changed: copy it
(string-set! buffer 0 #\b)
(display buffer) (newline)
