; namespaces-files/main.lisp -- an import belongs to the file that makes it
;
; Each file has its own imports, as each C# file has its own using lines.
;   - report.lisp is a program file that this one loads with load: it starts
;     with this file's imports, as if its text were written here, so it can use
;     the stats library's mean without requiring it again.
;   - words.lisp is a library: a library starts with no imports at all, so it
;     requires what it needs itself, here Common Lisp's names (cl), for first.
;     Its import is its own: this file did not require cl, so first means
;     nothing here, and words.lisp's import did not leak out.

(require "stats.lisp")
(load "report.lisp")
(require "words.lisp")

(display (mean '(1 2 3 6))) (newline)
(display (report '(2 4))) (newline)          ; report.lisp used this file's mean
(display (first-word "namespaces keep names apart")) (newline)
(display (guard (e (#t (error-object-message e))) (first '(a b)))) (newline)
