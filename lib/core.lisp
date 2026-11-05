;;; core.lisp -- cog-lisp's derived forms (specs/phase-7-macros.md section 7)
;;;
;;; Loaded into cog-lisp.image by the build. Each form is a macro written in
;;; cog-lisp itself, and keeps its source like any procedure. A macro defined
;;; here may use only the special forms and the macros defined above it.

;; x is the keyword name: a symbol, or an alias of one, as a syntax-rules template
;; passes it to a define-macro macro (specs/phase-9-language.md step 9.3)
(define (%keyword? x name)
  (if (eq? x name) #t (if [x isLispAlias] (eq? [x baseName] name) #f)))

;; (cond (test e ...) ... (test => f) ... (else e ...))
(define-macro (cond . clauses)
  (if (null? clauses)
      '(if #f #f)
      (let ((clause (car clauses))
            (rest (cdr clauses)))
        (if (%keyword? (car clause) 'else)
            `(begin ,@(cdr clause))
            (if (null? (cdr clause))
                (let ((t (gensym)))
                  `(let ((,t ,(car clause)))
                     (if ,t ,t (cond ,@rest))))
                (if (%keyword? (car (cdr clause)) '=>)
                    (let ((t (gensym)))
                      `(let ((,t ,(car clause)))
                         (if ,t (,(car (cdr (cdr clause))) ,t) (cond ,@rest))))
                    `(if ,(car clause)
                         (begin ,@(cdr clause))
                         (cond ,@rest))))))))

;; (and e ...) -- #t when empty; otherwise the first false value, or the last value
(define-macro (and . xs)
  (cond ((null? xs) #t)
        ((null? (cdr xs)) (car xs))
        (else `(if ,(car xs) (and ,@(cdr xs)) #f))))

;; (or e ...) -- #f when empty; otherwise the first true value
(define-macro (or . xs)
  (cond ((null? xs) #f)
        ((null? (cdr xs)) (car xs))
        (else (let ((t (gensym)))
                `(let ((,t ,(car xs)))
                   (if ,t ,t (or ,@(cdr xs))))))))

(define-macro (when test . body)
  `(if ,test (begin ,@body)))

(define-macro (unless test . body)
  `(if ,test (if #f #f) (begin ,@body)))

;; (let* ((v e) ...) body ...) -- each binding sees the ones before it
(define-macro (let* bindings . body)
  (if (null? bindings)
      `(let () ,@body)
      `(let (,(car bindings))
         (let* ,(cdr bindings) ,@body))))

;; (letrec* ((v e) ...) body ...) -- bindings in scope everywhere, assigned in order
(define-macro (letrec* bindings . body)
  `(let ()
     ,@(map (lambda (b) `(define ,(car b) ,(car (cdr b)))) bindings)
     (let () ,@body)))

(define-macro (letrec bindings . body)
  `(letrec* ,bindings ,@body))

;; (case key ((datum ...) e ...) ... (else e ...)) -- compares with eqv?
(define-macro (case key . clauses)
  (let ((k (gensym)))
    `(let ((,k ,key))
       (cond ,@(map (lambda (c)
                      (if (%keyword? (car c) 'else)
                          c
                          `((memv ,k ',(car c)) ,@(cdr c))))
                    clauses)))))

;; (do ((var init step) ...) (test result ...) body ...)
(define-macro (do specs test-clause . body)
  (let ((loop (gensym)))
    `(let ,loop ,(map (lambda (s) (list (car s) (car (cdr s)))) specs)
       (if ,(car test-clause)
           (begin (if #f #f) ,@(cdr test-clause))
           (begin
             ,@body
             (,loop ,@(map (lambda (s)
                             (if (null? (cdr (cdr s)))
                                 (car s)
                                 (car (cdr (cdr s)))))
                           specs)))))))

;;; Multiple values (specs/phase-9-language.md step 9.2; values and
;;; call-with-values are primitives)

;; formals with every name replaced by a fresh one, in the same shape:
;; (a b . c) -> (g1 g2 . g3), and the (name . fresh) pairs
(define (%values-formals formals)
  (cond ((null? formals) (cons '() '()))
        ((symbol? formals) (let ((g (gensym))) (cons g (list (cons formals g)))))
        (else (let ((g (gensym)) (rest (%values-formals (cdr formals))))
                (cons (cons g (car rest)) (cons (cons (car formals) g) (cdr rest)))))))

;; (let-values (((a b) e) ((c . d) f) (g h)) body ...) -- each init is evaluated
;; outside every binding, as let's are; let*-values sees the bindings before it
(define-macro (let-values bindings . body)
  (let loop ((bs bindings) (renames '()))
    (if (null? bs)
        `(let ,(map (lambda (r) (list (car r) (cdr r))) renames) ,@body)
        (let ((fresh (%values-formals (car (car bs)))))
          `(call-with-values (lambda () ,(car (cdr (car bs))))
             (lambda ,(car fresh)
               ,(loop (cdr bs) (append renames (cdr fresh)))))))))

(define-macro (let*-values bindings . body)
  (if (null? bindings)
      `(let () ,@body)
      `(let-values (,(car bindings))
         (let*-values ,(cdr bindings) ,@body))))

;;; Conditions and restarts (specs/phase-7.7-conditions-restarts.md)

;; (guard (var clause ...) body ...) -- cond-style clauses over what was raised;
;; with no matching clause it is raised again where it was first raised
(define-macro (guard spec . body)
  `(%guard (lambda () ,@body)
           (lambda (,(car spec))
             (cond ,@(cdr spec) (else (%guard-no-match))))))

;; (restart-case form (name (param ...) body ...) ...) -- form with named restarts
(define-macro (restart-case form . clauses)
  `(%restart-case
     (lambda () ,form)
     (list ,@(map (lambda (c)
                    `(cons ',(car c) (lambda ,(car (cdr c)) ,@(cdr (cdr c)))))
                  clauses))))
