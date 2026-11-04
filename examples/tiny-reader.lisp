; tiny-reader.lisp -- a reader for part of cog-lisp, written in cog-lisp (Phase 7.8)
; Phase 8 in miniature: it reads lists, symbols, integers, strings and quote
; from a string port, and its results are checked against the built-in read.

(define (delimiter? c)
  (or (eof-object? c) (char-whitespace? c) (memv c '(#\( #\) #\" #\'))))

(define (skip-space in)
  (let ((c (peek-char in)))
    (cond ((eof-object? c) c)
          ((char-whitespace? c) (read-char in) (skip-space in))
          ((char=? c #\;)                                  ; a comment, to the end of the line
           (read-line in) (skip-space in))
          (else c))))

(define (read-token in)
  (let ((out (open-output-string)))
    (let loop ()
      (unless (delimiter? (peek-char in))
        (write-char (read-char in) out)
        (loop)))
    (let ((text (get-output-string out)))
      (or (string->number text) (string->symbol text)))))

(define (read-string-literal in)
  (read-char in)                                           ; the opening quote
  (let ((out (open-output-string)))
    (let loop ()
      (let ((c (read-char in)))
        (cond ((eof-object? c) (error "tiny-read: unterminated string"))
              ((char=? c #\") (get-output-string out))
              ((char=? c #\\) (write-char (read-char in) out) (loop))
              (else (write-char c out) (loop)))))))

(define (read-list in)
  (read-char in)                                           ; the opening paren
  (let loop ((items '()))
    (let ((c (skip-space in)))
      (cond ((eof-object? c) (error "tiny-read: unterminated list"))
            ((char=? c #\)) (read-char in) (reverse items))
            (else (loop (cons (tiny-read in) items)))))))

(define (tiny-read in)
  (let ((c (skip-space in)))
    (cond ((eof-object? c) c)
          ((char=? c #\() (read-list in))
          ((char=? c #\)) (read-char in) (error "tiny-read: unexpected )"))
          ((char=? c #\") (read-string-literal in))
          ((char=? c #\') (read-char in) (list 'quote (tiny-read in)))
          (else (read-token in)))))

; Read every datum of a text with both readers, and compare.
(define (all-datums reader text)
  (let ((in (open-input-string text)))
    (let loop ((acc '()))
      (let ((d (reader in)))
        (if (eof-object? d) (reverse acc) (loop (cons d acc)))))))

(define sample "
  ; a small program
  (define (square x) (* x x))
  (display \"squares: \")
  (map square '(1 2 3 -4))
  42 hello \"a \\\"quoted\\\" word\"")

(define mine (all-datums tiny-read sample))
(for-each (lambda (d) (write d) (newline)) mine)
(display "same as the built-in reader: ")
(display (equal? mine (all-datums read sample)))
(newline)

; And what it reads, it can run.
(display (eval (car (all-datums tiny-read "(+ 1 (* 2 3))"))))
(newline)
(display (guard (e ((error-object? e) (error-object-message e)))
  (tiny-read (open-input-string "(1 2"))))
(newline)
