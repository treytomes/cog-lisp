; echo.lisp -- reading stdin from a program (Phase 7.9 section 5.2)
; Try: echo hello | cog-lisp.bat examples\echo.lisp
; read-line, read-char and read with no port read the program's input.

(let loop ((n 1))
  (let ((line (read-line)))
    (unless (eof-object? line)
      (display n)
      (display ": ")
      (display (string-upcase line))
      (newline)
      (loop (+ n 1)))))
(display "end of input")
(newline)
