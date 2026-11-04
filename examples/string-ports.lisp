; string-ports.lisp -- reading and writing strings as streams (Phase 7.8 section 8)

; Reading characters one at a time: a tiny tokenizer for arithmetic.
(define (tokenize text)
  (let ((in (open-input-string text)))
    (let loop ((tokens '()))
      (let ((c (peek-char in)))
        (cond ((eof-object? c) (reverse tokens))
              ((char-whitespace? c) (read-char in) (loop tokens))
              ((char-numeric? c)
               (let digits ((n 0))
                 (let ((d (peek-char in)))
                   (if (and (not (eof-object? d)) (char-numeric? d))
                       (begin (read-char in) (digits (+ (* n 10) (digit-value d))))
                       (loop (cons n tokens))))))
              (else (read-char in) (loop (cons (string->symbol (string c)) tokens))))))))
(write (tokenize "12 + 3*(45 - 6)"))
(newline)

; read takes whole datums from a port, then the end-of-file object.
(define data (open-input-string "(name \"Ada\") (born 1815) 42"))
(let loop ((x (read data)))
  (unless (eof-object? x)
    (write x)
    (newline)
    (loop (read data))))

; Lines.
(define lines (open-input-string "first line\nsecond line\n"))
(write (list (read-line lines) (read-line lines) (eof-object? (read-line lines))))
(newline)

; Writing to a string.
(define out (open-output-string))
(write-string "total: " out)
(write (+ 1 2 3) out)
(write-char #\! out)
(write (get-output-string out))
(newline)
(write (with-output-to-string (lambda () (display "captured ") (display '(a b)))))
(newline)
