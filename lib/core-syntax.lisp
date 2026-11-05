;;; core-syntax.lisp -- the derived forms, hygienic (specs/phase-9-language.md
;;; step 9.3b)
;;;
;;; lib/core.lisp defines these as define-macro macros, because the seed compiles
;;; core.lisp, and these forms compile the compiler; a seed has syntax-rules only
;;; from the release after v0.1.2. The build loads this file once the new compiler
;;; is installed, and these definitions replace those for every program after.
;;; Written with syntax-rules, a name they bind cannot capture the program's, and
;;; a name they use (if, let, memv, ...) means the global one even where the
;;; program has bound it: (let ((memv ...)) (case x ...)) works (review C-14).
;;;
;;; let-values and let*-values stay define-macro (lib/core.lisp): they rename their
;;; bindings with gensyms already.

;; (cond (test e ...) ... (test => f) ... (else e ...)); an else ends the clauses
(define-syntax cond
  (syntax-rules (else =>)
    ((_) (if #f #f))
    ((_ (else e ...) . ignored) (begin e ...))
    ((_ (test => f) clause ...) (let ((t test)) (if t (f t) (cond clause ...))))
    ((_ (test) clause ...) (let ((t test)) (if t t (cond clause ...))))
    ((_ (test e ...) clause ...) (if test (begin e ...) (cond clause ...)))))

;; (and e ...) -- #t when empty; otherwise the first false value, or the last value
(define-syntax and
  (syntax-rules ()
    ((_) #t)
    ((_ e) e)
    ((_ e rest ...) (if e (and rest ...) #f))))

;; (or e ...) -- #f when empty; otherwise the first true value
(define-syntax or
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e rest ...) (let ((t e)) (if t t (or rest ...))))))

(define-syntax when
  (syntax-rules () ((_ test e ...) (if test (begin e ...)))))

(define-syntax unless
  (syntax-rules () ((_ test e ...) (if test (if #f #f) (begin e ...)))))

;; (let* ((v e) ...) body ...) -- each binding sees the ones before it
(define-syntax let*
  (syntax-rules ()
    ((_ () body ...) (let () body ...))
    ((_ (binding) body ...) (let (binding) body ...))
    ((_ (binding rest ...) body ...) (let (binding) (let* (rest ...) body ...)))))

;; (letrec* ((v e) ...) body ...) -- bindings in scope everywhere, assigned in order
(define-syntax letrec*
  (syntax-rules ()
    ((_ ((v e) ...) body ...) (let () (define v e) ... (let () body ...)))))

(define-syntax letrec
  (syntax-rules ()
    ((_ bindings body ...) (letrec* bindings body ...))))

;; (case key ((datum ...) e ...) ... (else e ...)) -- compares with eqv?, through
;; the global memv
(define-syntax case
  (syntax-rules (else =>)
    ((_ "clauses" k) (if #f #f))
    ((_ "clauses" k (else => f) . ignored) (f k))
    ((_ "clauses" k (else e ...) . ignored) (begin e ...))
    ((_ "clauses" k ((datum ...) => f) clause ...)
     (if (memv k '(datum ...)) (f k) (case "clauses" k clause ...)))
    ((_ "clauses" k ((datum ...) e ...) clause ...)
     (if (memv k '(datum ...)) (begin e ...) (case "clauses" k clause ...)))
    ((_ key clause ...) (let ((k key)) (case "clauses" k clause ...)))))

;; (do ((var init step) ...) (test result ...) body ...)
(define-syntax do
  (syntax-rules ()
    ((_ "step" var) var)
    ((_ "step" var step) step)
    ((_ ((var init step ...) ...) (test result ...) body ...)
     (let loop ((var init) ...)
       (if test
           (begin (if #f #f) result ...)
           (begin body ... (loop (do "step" var step ...) ...)))))))

;; (guard (var clause ...) body ...) -- cond-style clauses over what was raised;
;; with no matching clause it is raised again where it was first raised
(define-syntax guard
  (syntax-rules ()
    ((_ (var clause ...) body ...)
     (%guard (lambda () body ...)
             (lambda (var) (cond clause ... (else (%guard-no-match))))))))

;; (restart-case form (name (param ...) body ...) ...) -- form with named restarts
(define-syntax restart-case
  (syntax-rules ()
    ((_ form (name params body ...) ...)
     (%restart-case (lambda () form)
                    (list (cons 'name (lambda params body ...)) ...)))))
