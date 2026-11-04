;;; extend-the-compiler.lisp -- a new special form, added to the running compiler
;;; (Phase 8 step 8.3)
;;;
;;; Special forms are a table from name to translator. A translator takes the
;;; compiler's state, the form, the scope and whether the form is in tail
;;; position, and answers Opal nodes -- here, by translating an equivalent form.
;;; The code that uses the new forms goes through lisp-eval-string, the LISP
;;; compiler whichever is in use: with COGLISP_COMPILER=smalltalk, eval and load
;;; use the Smalltalk compiler, which has no table to extend.

;; (repeat n body ...) runs body n times, compiled directly as a loop: no macro,
;; no procedure call per iteration.
(define-special-form 'repeat
  (lambda (c form scope tail)
    (let ((n (car (cdr form)))
          (body (cdr (cdr form)))
          (i (gensym)))
      (lc-translate c
        `(let loop ((,i 0))
           (if (< ,i ,n) (begin ,@body (loop (+ ,i 1))) ,n))
        scope tail))))

(lisp-eval-string "
  (define total 0)
  (repeat 5 (set! total (+ total 10)))
  (display \"total after (repeat 5 ...): \") (write total) (newline)")

;; A special form is not a value, and it checks nothing it is not told to: a
;; translator can also reject bad syntax with a compile error.
(define-special-form 'twice
  (lambda (c form scope tail)
    (unless (= (length form) 2)
      (lc-error (string-append "twice: bad syntax: " (lc-show form))))
    (lc-translate c `(begin ,(car (cdr form)) ,(car (cdr form))) scope tail)))

(lisp-eval-string "(twice (display \"hello \")) (newline)")

(display "error: ")
(display (guard (e (#t (error-object-message e)))
  (lisp-eval-string "(twice 1 2)")))
(newline)
