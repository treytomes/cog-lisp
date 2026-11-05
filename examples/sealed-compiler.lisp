;;; sealed-compiler.lisp -- a program cannot break the compiler it runs on
;;; (Phase 8 step 8.5)
;;;
;;; eval, load, the REPL and the runner use the reader and compiler written in
;;; cog-lisp (lib/compiler/), the only ones since Phase 9 step 9.1. They are sealed
;;; when the image is built: each global they use is
;;; bound for them to the value it had then. So a program may define any name --
;;; even one the compiler itself uses -- and only the program sees its definition.

(display "the image has its LISP compiler: ")
(write [(smalltalk LispCompiler) hasLispCompiler])
(newline)

;; Redefine three things the compiler and reader use all the time.
(define (append . lists) 'my-append)
(define (cons a b) (list 'my-cons a b))
(define (make-reader text) 'my-reader)

;; The program sees its own definitions ...
(display "(append '(1) '(2)) = ") (write (append '(1) '(2))) (newline)
(display "(cons 1 2) = ") (write (cons 1 2)) (newline)

;; ... and the compiler goes on compiling: this definition uses quasiquote and
;; splicing, which the compiler builds with its own append and cons.
(define (wrap items) `(begin ,@items end))
(display "(wrap '(a b)) = ") (write (wrap '(a b))) (newline)

;; reading still works too
(display "read: ") (write (read (open-input-string "(x . y)"))) (newline)
