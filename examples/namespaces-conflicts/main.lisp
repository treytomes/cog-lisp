; namespaces-conflicts/main.lisp -- what is refused, instead of silently replaced
;
; With one namespace, the definition loaded last wins without a word. Here a
; clash is an error at the line that would cause it:
;   - two imports that bring the same name into one file, from different
;     libraries (left.lisp and right.lisp both export side);
;   - a file defining a name it imported;
;   - asking a library for a name it does not export.
; The way out is always the same: a prefix, a rename, or only. (Each error is
; caught here so the program can show it; eval makes the definition at run
; time, so that its error can be caught too.)
;
; One more case is a warning rather than an error, written to stderr: a program
; that defines a name cog-lisp itself defines, such as http-request. The
; program's own code then calls its definition, and cog-lisp's built-ins keep
; calling theirs, so http-get still works.

(require "left.lisp")

(define (attempt thunk)
  (display (guard (e (#t (error-object-message e))) (thunk)))
  (newline))

(attempt (lambda () (require "right.lisp")))
(attempt (lambda () (eval '(define (side) 'mine))))
(attempt (lambda () (require "right.lisp" 'only '(top))))

(require "right.lisp" 'rename '((side right-side)))
(display (list (side) (right-side))) (newline)
