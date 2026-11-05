;;; syntax-rules.lisp -- hygienic macros (Phase 9 step 9.3)
;;;
;;; define-syntax with syntax-rules writes a macro as patterns and templates. The
;;; macros are hygienic: a name a template binds cannot capture the program's
;;; variables, and a name a template uses means what it meant where the macro was
;;; defined, whatever the program has bound since. (define-macro is still there,
;;; for macros that mean to capture.)

(define (show label x) (display label) (display " ") (write x) (newline))

;; swap! binds tmp. A program with its own tmp is safe from it.
(define-syntax swap!
  (syntax-rules ()
    ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))
(let ((tmp 'first) (other 'second))
  (swap! tmp other)
  (show "after (swap! tmp other):" (list tmp other)))

;; Patterns: literals, ellipses (repeated parts), nested ellipses.
(define-syntax my-cond
  (syntax-rules (else)
    ((_ (else e ...)) (begin e ...))
    ((_ (test e ...) clause ...) (if test (begin e ...) (my-cond clause ...)))))
(show "(my-cond (#f 1) ((= 1 1) 2) (else 3)) =" (my-cond (#f 1) ((= 1 1) 2) (else 3)))

(define-syntax my-let*
  (syntax-rules ()
    ((_ () body ...) (let () body ...))
    ((_ ((name value) more ...) body ...)
     (let ((name value)) (my-let* (more ...) body ...)))))
(show "my-let* =" (my-let* ((a 1) (b (+ a 1)) (c (* b 10))) (list a b c)))

(define-syntax table
  (syntax-rules ()
    ((_ (key value ...) ...) '((key value ...) ...))))
(show "table =" (table (fruit apple pear) (veg leek)))

;; A name the template uses keeps its meaning: here the program has bound list
;; and if locally, and the macro still means the global ones.
(define-syntax pair-up
  (syntax-rules () ((_ a b) (if #t (list a b) #f))))
(show "with local list and if:" (let ((list vector) (if 'not-a-keyword)) (pair-up 1 2)))

;; A special form's name is an ordinary name when the program binds it.
(show "((lambda (if) (if 1 2 3)) +) =" ((lambda (if) (if 1 2 3)) +))

;; let-syntax and letrec-syntax make local macros.
(show "letrec-syntax:"
      (letrec-syntax ((count-args (syntax-rules ()
                                    ((_) 0)
                                    ((_ x rest ...) (+ 1 (count-args rest ...))))))
        (count-args a b c d)))

;; syntax-error reports a misuse when the macro is expanded.
(define-syntax unary
  (syntax-rules ()
    ((_ x) (- x))
    ((_ x y ...) (syntax-error "unary takes one argument, not" x y ...))))
(show "(unary 5) =" (unary 5))
(show "(unary 1 2) is" (guard (e (#t (error-object-message e))) (eval '(unary 1 2))))
