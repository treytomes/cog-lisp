;;; phase-10.1-documentation.lisp -- documentation kept in the image
;;; (specs/16-phase-10-documentation-and-editor.md step 10.1, AC-1)
(load "../../lib/test.lisp")

;; every bound global, as (name . value)
(define (all-globals)
  (let ((acc '()))
    [[(smalltalk LispEnvironment) default]
     cellsDo: (lambda (c) (when [c isBound] (set! acc (cons (cons [c symbol] [c value]) acc))))]
    acc))

;; internal: %name, or a library's private lib:%name (specs/27-namespaces.md)
(define (internal-name? s)
  (let* ((n (symbol->string s)) (colon (string-index n #\:))
         (local (if colon (substring n (+ colon 1) (string-length n)) n)))
    (or (= (string-length local) 0) (char=? (string-ref local 0) #\%))))
(define (primitive? v) (and (procedure? v) (not (procedure-source v))))

;; the first line of a documentation string
(define (first-line doc)
  (let ((i (string-index doc #\newline))) (if i (substring doc 0 i) doc)))

;; the documentation's first line is a call form that names the thing
(define (names-itself? name doc)
  (let ((line (first-line doc)) (s (symbol->string name)))
    (and (> (string-length line) (string-length s))
         (string-search line (string-append "(" s)))))

(define-test "AC-1 every primitive is documented, and its first line is its call form"
  (let ((missing '()) (unnamed '()))
    (for-each (lambda (g)
                (when (and (primitive? (cdr g)) (not (internal-name? (car g))))
                  (let ((doc (procedure-documentation (cdr g))))
                    (cond ((not doc) (set! missing (cons (car g) missing)))
                          ((not (names-itself? (car g) doc)) (set! unnamed (cons (car g) unnamed)))))))
              (all-globals))
    (check missing '())
    (check unnamed '())))

(define-test "AC-1 every special form is documented"
  (check (length (special-form-names)) 16)
  (check (sr-filter (lambda (n) (not (documentation n))) (special-form-names)) '())
  (check (sr-filter (lambda (n) (not (names-itself? n (documentation n)))) (special-form-names)) '()))

(define-test "AC-1 every derived form of lib/core.lisp is documented (10.1b)"
  (let ((core (sr-filter (lambda (g) (and [(cdr g) isKindOf: (smalltalk LispSyntax)]
                                          (equal? (documentation-category (car g)) "Derived forms")))
                         (all-globals)))
        (forms '(cond and or when unless let* letrec* letrec case do let-values let*-values guard restart-case parameterize library)))
    (check (sr-filter (lambda (n) (not (documentation n))) forms) '())
    (check (sr-filter (lambda (n) (not (names-itself? n (documentation n)))) forms) '())
    (check (length core) (length forms))))

(define-test "AC-1 every primitive has a category"
  (check (sr-filter (lambda (g) (and (primitive? (cdr g)) (not (internal-name? (car g)))
                                      (not (documentation-category (car g)))))
                    (all-globals))
         '()))

(define-test "AC-1 documentation and its category, for each kind of built-in"
  (check (first-line (documentation 'string-ref)) "(string-ref string k)")
  (check (documentation-category 'string-ref) "Strings")
  (check (documentation-category 'car) "Lists")
  (check (documentation-category 'values) "Control")
  (check (documentation-category 'if) "Special forms")
  (check (first-line (documentation 'compile-form)) "(compile-form datum [reader [context]])")
  (check (documentation-category 'compile-form) "The compiler and reader")
  (check (documentation-category 'documentation) "The compiler and reader")
  (check (documentation 'no-such-name-at-all) #f)
  (check (procedure-documentation (lambda (x) x)) #f))

(define-test "AC-1 a define whose body starts with a string keeps it"
  (define (doc-test-square x)
    "(doc-test-square x)
x times x."
    (* x x))
  (check (doc-test-square 4) 16)
  (check (procedure-documentation doc-test-square) "(doc-test-square x)\nx times x.")
  (check (eval-all "(define (doc-test-global y) \"(doc-test-global y)\nIt answers y.\" y) (documentation 'doc-test-global)")
         "(doc-test-global y)\nIt answers y."))

(define-test "AC-1 a body that is only a string is a value, not documentation"
  (check (eval-all "(define (doc-test-only) \"just a value\") (list (doc-test-only) (documentation 'doc-test-only))")
         '("just a value" #f)))

(define-test "AC-1 define-syntax and define-macro keep their strings"
  (eval-all "(define-syntax doc-test-swap! \"(doc-test-swap! a b)\nExchanges a and b.\" (syntax-rules () ((_ a b) (let ((t a)) (set! a b) (set! b t)))))")
  (eval-all "(define-macro (doc-test-twice e) \"(doc-test-twice e)\nRuns e twice.\" `(begin ,e ,e))")
  (check (documentation 'doc-test-swap!) "(doc-test-swap! a b)\nExchanges a and b.")
  (check (documentation 'doc-test-twice) "(doc-test-twice e)\nRuns e twice.")
  (check (eval-all "(let ((p 1) (q 2)) (doc-test-swap! p q) (list p q))") '(2 1))
  (check (eval-all "(define-syntax doc-test-plain (syntax-rules () ((_) 'plain))) (list (doc-test-plain) (documentation 'doc-test-plain))")
         '(plain #f)))

(define-test "AC-1 a definition takes the category of the file it was loaded from"
  (check (documentation-category 'doc-test-global) "phase-10.1-documentation.lisp")
  (check (documentation-category 'when) "Derived forms"))

(define-test "AC-1 an old name has documentation of its own"
  (check (first-line (documentation 'hash-table-exists?)) "(hash-table-exists? table key)")
  (check (first-line (documentation 'hash-table-contains?)) "(hash-table-contains? table key)")
  (check (hash-table-exists? (alist->hash-table '((a . 1))) 'a) #t))

;; specs/27-namespaces.md AC-5, R-14: each shipped library exports what it documents,
;; and the reference lists them; a value (cl's t and nil) has no documentation
(define-test "every procedure and macro a shipped library exports is documented"
  (let ((env [(smalltalk LispEnvironment) default]) (missing '()))
    (for-each
     (lambda (library)
       ;; test is loaded already, and running: loading it again would reset it
       (when (smalltalk-nil? [(smalltalk LispUnit) libraryNamed: library])
         (require library 'only '()))
       (let ((unit [(smalltalk LispUnit) libraryNamed: library]))
         (for-each (lambda (name)
                     (let* ((full [unit qualify: name])
                            (value [env at: full ifAbsent: (lambda () #f)]))
                       (when (and (or (procedure? value) [value isKindOf: (smalltalk LispMacro)])
                                  (not (documentation full)))
                         (set! missing (cons full missing)))))
                   (vector->list [unit exports]))))
     '(cl test datetime pretty format-source))
    (check missing '())))

(run-tests)
