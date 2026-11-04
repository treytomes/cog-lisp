; program/main.lisp -- a program in two files (Phase 7.9 section 5.3)
; Run it as: cog-lisp.bat examples\program\main.lisp alpha beta
; load finds lib/util.lisp beside this file, wherever the program is run from.

(load "lib/util.lisp")

(display (string-append "this file: " (file-name (current-load-path))))
(newline)
(display "arguments: ")
(write (cdr (command-line)))                       ; the program itself comes first
(newline)
(for-each (lambda (arg) (display (shout arg)) (newline))
          (cdr (command-line)))
