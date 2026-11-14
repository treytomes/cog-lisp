;;; An Enter typed after a key answer (specs/36-console-driver.md L-36.2): the
;;; confirm takes the y, and the Enter that came with it is an empty line for
;;; the next read-line, on Windows and on Linux alike, not a carriage return
;;; at the start of the line after it. Each line is shown as its character
;;; codes, so a carriage return cannot hide. Driven by confirm-enter.txt.

(require 'console)

(display (if (confirm "Go on?") "answered yes" "answered no"))
(newline)
(define (show-line)
  (let ((line (read-line)))
    (display "codes: ")
    (display (if (eof-object? line) "eof" (map char->integer (string->list line))))
    (newline)))
(show-line)
(show-line)
