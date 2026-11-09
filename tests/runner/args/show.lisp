;; show.lisp -- the arguments a program is given, one a line (specs/formatter.md, as built:
;; an argument that starts with a dash, or a colon, arrives as it was typed)
(for-each (lambda (a) (write a) (newline)) (cdr (command-line)))
