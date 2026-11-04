; files.lisp -- reading and writing files with ports (Phase 7.9 section 5.1)
; A relative path names a file beside this program, wherever it is run from.

(define scores '(("ada" 98) ("grace" 95) ("alan" 87)))

; Write a small CSV file: one line per row.
(call-with-output-file "scores.csv"
  (lambda (out)
    (for-each (lambda (row)
                (write-string (car row) out)
                (write-char #\, out)
                (write (car (cdr row)) out)
                (newline out))
              scores)))
(display (file-exists? "scores.csv"))
(newline)

; Read it back a line at a time, until the end-of-file object.
(define (read-rows port)
  (let loop ((rows '()))
    (let ((line (read-line port)))
      (if (eof-object? line)
          (reverse rows)
          (let ((fields (string-split line #\,)))
            (loop (cons (list (car fields) (string->number (car (cdr fields)))) rows)))))))
(define rows (call-with-input-file "scores.csv" read-rows))
(write rows)
(newline)
(display (equal? rows scores))
(newline)

; with-output-to-file sends display and write to the file.
(with-output-to-file "scores.csv"
  (lambda () (write '(total 280)) (newline)))
(write (call-with-input-file "scores.csv" read))      ; read a datum back
(newline)

(delete-file "scores.csv")
(display (file-exists? "scores.csv"))
(newline)
(display (guard (e ((file-error? e) (error-object-message e)))
  (open-input-file "no-such-file.txt")))
(newline)
