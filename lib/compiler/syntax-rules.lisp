;;; syntax-rules.lisp -- hygienic macros, by renaming (specs/phase-9-language.md
;;; step 9.3; R7RS 4.3.2)
;;;
;;; (sr-make spec env name) turns (syntax-rules [ellipsis] (literal ...) rule ...)
;;; into a LispSyntax macro defined in env, a compile-time scope. Expanding a use:
;;;   1. match the form against each rule's pattern, in order; the first match
;;;      binds the pattern variables to parts of the form;
;;;   2. instantiate that rule's template: a pattern variable becomes what it
;;;      matched; any other identifier becomes an alias, made once per expansion,
;;;      that remembers env (lib/compiler/compiler.lisp resolves aliases).
;;; A literal matches an input identifier that means what the literal means where
;;; the macro was defined (both bound alike, or both free with the same name).
;;;
;;; A binding of a pattern variable under an ellipsis is a sequence: (sr-seq . items).

(define sr-seq (list 'sequence))
(define (sr-seq? v) (and (pair? v) (eq? (car v) sr-seq)))

;; the state of one macro: #(literals ellipsis env use-scope name)
(define (sr-literals st) (vector-ref st 0))
(define (sr-ellipsis st) (vector-ref st 1))
(define (sr-env st) (vector-ref st 2))
(define (sr-use-scope st) (vector-ref st 3))
(define (sr-name st) (vector-ref st 4))
(define (sr-without-ellipsis st)
  (vector (sr-literals st) #f (sr-env st) (sr-use-scope st) (sr-name st)))

(define (sr-error st text) (lc-error (string-append (symbol->string (sr-name st)) ": " text)))

(define (sr-make spec env name)
  (let* ((parts (lc-items (cdr spec)))
         (custom (and (pair? parts) (lc-identifier? (car parts))))
         (ellipsis (if custom (car parts) '...))
         (parts (if custom (cdr parts) parts)))
    (when (null? parts) (lc-error (string-append "syntax-rules: " (symbol->string name) ": no list of literals")))
    (let ((literals (car parts))
          (rules (cdr parts)))
      (unless (and (list? literals) (lc-all? lc-identifier? literals))
        (lc-error (string-append "syntax-rules: " (symbol->string name) ": bad list of literals: " (lc-show literals))))
      (for-each (lambda (rule)
                  (unless (and (list? rule) (= (length rule) 2) (pair? (car rule)))
                    (lc-error (string-append "syntax-rules: " (symbol->string name) ": bad rule: " (lc-show rule)))))
                rules)
      [(smalltalk LispSyntax) name: name
         expander: (lambda (form use-scope)
                     (sr-expand form (vector literals ellipsis env use-scope name) rules))])))

(define (lc-all? pred l) (or (null? l) (and (pred (car l)) (lc-all? pred (cdr l)))))

(define (sr-expand form st rules)
  (let loop ((rs rules))
    (if (null? rs)
        (sr-error st (string-append "no syntax-rules pattern matches " (lc-show (lc-strip form))))
        (let* ((rule (car rs))
               ;; the pattern's first element is the macro's keyword: not matched
               (bindings (sr-match (cdr (car rule)) (cdr form) st)))
          (if bindings
              (sr-instantiate (car (cdr rule)) (cdr bindings) st (make-hash-table eq?))
              (loop (cdr rs)))))))

;;; Matching. A match answers (#t . bindings), bindings an association list of
;;; pattern variable and what it matched, or #f.

(define (sr-literal? p st) (memq p (sr-literals st)))
(define (sr-underscore? p) (lc-id-is? p '_))
(define (sr-ellipsis? x st)
  (let ((e (sr-ellipsis st)))
    (and e (lc-identifier? x) (eq? (lc-id-symbol x) (lc-id-symbol e)) (not (sr-literal? x st)))))

;; the input identifier f means what the literal p means where the macro was defined:
;; the same binding, or (R7RS's free-identifier=?) both unbound and spelled alike.
;; In a library an unbound name resolves to the library's own (test:else), so
;; cond's else, used in a library, needs the second case (specs/namespaces.md).
(define (sr-same-binding? f p st)
  (let ((bf (lc-binding f (sr-use-scope st))) (bp (lc-binding p (sr-env st))))
    (or (eq? bf bp)
        (and (symbol? bf) (symbol? bp)
             (eq? (lc-id-symbol f) (lc-id-symbol p))
             (sr-unbound? bf) (sr-unbound? bp)))))

(define (sr-unbound? sym) (not [[(smalltalk LispEnvironment) default] isBound: sym]))

(define (sr-match p f st)
  (let ((m (sr-match* p f st)))
    (and m (cons #t m))))


(define (sr-match* p f st)
  (cond ((lc-identifier? p)
         (cond ((sr-literal? p st) (and (lc-identifier? f) (sr-same-binding? f p st) '()))
               ((sr-underscore? p) '())
               (else (list (cons p f)))))
        ((pair? p)
         (if (and (pair? (cdr p)) (sr-ellipsis? (car (cdr p)) st))
             (sr-match-ellipsis (car p) (cdr (cdr p)) f st)
             (and (pair? f)
                  (let ((a (sr-match* (car p) (car f) st)))
                    (and a
                         (let ((d (sr-match* (cdr p) (cdr f) st)))
                           (and d (append a d))))))))
        ((null? p) (and (null? f) '()))
        ((vector? p) (and (vector? f) (sr-match* (vector->list p) (vector->list f) st)))
        (else (and (equal? p f) '()))))

(define (sr-pairs l) (if (pair? l) (+ 1 (sr-pairs (cdr l))) 0))

;; (sub ellipsis . rest) against f: as many fs as leave enough for rest
(define (sr-match-ellipsis sub rest f st)
  (let ((spare (- (sr-pairs f) (sr-pairs rest))))
    (and (>= spare 0)
         (let loop ((k spare) (f f) (matches '()))
           (if (= k 0)
               (let ((r (sr-match* rest f st)))
                 (and r (append (sr-sequences sub (reverse matches) st) r)))
               (let ((m (sr-match* sub (car f) st)))
                 (and m (loop (- k 1) (cdr f) (cons m matches)))))))))

;; each variable of sub bound to the sequence of what it matched in each match
(define (sr-sequences sub matches st)
  (lc-map (lambda (v) (cons v (cons sr-seq (lc-map (lambda (m) (cdr (assq v m))) matches))))
          (sr-pattern-vars sub st)))

(define (sr-pattern-vars p st)
  (cond ((lc-identifier? p)
         (if (or (sr-literal? p st) (sr-underscore? p) (sr-ellipsis? p st)) '() (list p)))
        ((pair? p) (append (sr-pattern-vars (car p) st) (sr-pattern-vars (cdr p) st)))
        ((vector? p) (sr-pattern-vars (vector->list p) st))
        (else '())))

;;; Instantiation

(define (sr-instantiate t b st renames)
  (cond ((lc-identifier? t)
         (let ((pb (assq t b)))
           (cond ((not pb) (sr-rename t st renames))
                 ((sr-seq? (cdr pb))
                  (sr-error st (string-append "pattern variable " (symbol->string (lc-id-symbol t))
                                              " used without its ellipsis")))
                 (else (cdr pb)))))
        ((pair? t)
         (cond ((and (sr-ellipsis? (car t) st) (pair? (cdr t)))
                ;; (... template): the template, with ... taken literally
                (sr-instantiate (car (cdr t)) b (sr-without-ellipsis st) renames))
               ((and (pair? (cdr t)) (sr-ellipsis? (car (cdr t)) st))
                (let count ((rest (cdr t)) (depth 0))
                  (if (and (pair? rest) (sr-ellipsis? (car rest) st))
                      (count (cdr rest) (+ depth 1))
                      (append (sr-repeat (car t) depth b st renames)
                              (sr-instantiate rest b st renames)))))
               (else
                (let* ((a (sr-instantiate (car t) b st renames))
                       (d (sr-instantiate (cdr t) b st renames)))
                  (cons a d)))))
        ((vector? t) (list->vector (sr-instantiate (vector->list t) b st renames)))
        (else t)))

;; one alias per identifier per expansion, defined in the macro's scope
(define (sr-rename id st renames)
  (hash-table-ref renames id
    (lambda ()
      (let ((a [(smalltalk LispAlias) name: id env: (sr-env st)]))
        (hash-table-set! renames id a)
        a))))

;; sub followed by depth ellipses: a list, once for each element of the sequences
;; its variables are bound to (all of the same length)
(define (sr-repeat sub depth b st renames)
  (let ((vars (sr-filter (lambda (v) (sr-seq? (cdr (assq v b)))) (sr-template-vars sub b st))))
    (when (null? vars) (sr-error st (string-append "no pattern variable to repeat in " (lc-show (lc-strip sub)))))
    (let* ((seqs (lc-map (lambda (v) (cdr (cdr (assq v b)))) vars))
           (n (length (car seqs))))
      (unless (lc-all? (lambda (s) (= (length s) n)) seqs)
        (sr-error st "pattern variables under one ellipsis matched different numbers of forms"))
      (let loop ((seqs seqs) (acc '()))
        (if (null? (car seqs))
            acc
            (let ((b2 (append (lc-map2 (lambda (v s) (cons v (car s))) vars seqs) b)))
              (loop (lc-map cdr seqs)
                    (append acc
                            (if (= depth 1)
                                (list (sr-instantiate sub b2 st renames))
                                (sr-repeat sub (- depth 1) b2 st renames))))))))))

(define (sr-template-vars t b st)
  (cond ((lc-identifier? t) (if (assq t b) (list t) '()))
        ((pair? t) (append (sr-template-vars (car t) b st) (sr-template-vars (cdr t) b st)))
        ((vector? t) (sr-template-vars (vector->list t) b st))
        (else '())))

(define (sr-filter pred l)
  (cond ((null? l) '())
        ((pred (car l)) (cons (car l) (sr-filter pred (cdr l))))
        (else (sr-filter pred (cdr l)))))
