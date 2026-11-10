;; alpha.lisp -- a fixture library (tests/lisp/namespaces.lisp): a rule, private
;; state and a private helper, a hygienic macro using the helper, and a
;; define-macro naming it in full, and a macro with a literal keyword (otherwise)
(library alpha (export rule bump! wrap note shared either))

(define hidden 7)
(define (%box s) (string-append "[" s "]"))
(define counter 0)
(define (bump!) (set! counter (+ counter 1)) counter)
(define (rule n) (string-append "alpha " (number->string n)))
(define (shared) 'alpha)

(define-syntax wrap
  (syntax-rules () ((_ s) (%box s))))

(define-syntax either
  (syntax-rules (otherwise)
    ((_ otherwise e) e)
    ((_ x e) x)))

(define-macro (note s)
  `(string-append "note " (alpha:%box ,s)))
