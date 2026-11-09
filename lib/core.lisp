;;; core.lisp -- cog-lisp's derived forms (specs/phase-7-macros.md section 7;
;;; hygienic since specs/phase-9-language.md step 9.3)
;;;
;;; Loaded into cog-lisp.image by the build, which compiles it with the seed's
;;; compiler (a seed has syntax-rules from v0.1.3). Each form is a syntax-rules
;;; macro: a name it binds cannot capture the program's, and a name it uses (if,
;;; let, memv, ...) means the global one even where the program has bound it, so
;;; (let ((memv ...)) (case x ...)) works (review C-14). They compile the compiler
;;; too. A form may use the special forms and the forms defined in this file.

;; (cond (test e ...) ... (test => f) ... (else e ...)); an else ends the clauses
(define-syntax cond
  "(cond (test e ...) ... (test => proc) ... (else e ...))
The body of the first clause whose test is true; with =>, proc called with the test value; else matches anything."
  (syntax-rules (else =>)
    ((_) (if #f #f))
    ((_ (else e ...) . ignored) (begin e ...))
    ((_ (test => f) clause ...) (let ((t test)) (if t (f t) (cond clause ...))))
    ((_ (test) clause ...) (let ((t test)) (if t t (cond clause ...))))
    ((_ (test e ...) clause ...) (if test (begin e ...) (cond clause ...)))))

;; (and e ...) -- #t when empty; otherwise the first false value, or the last value
(define-syntax and
  "(and e ...)
The first false value, or the last value; #t for none. Evaluation stops at the first false value."
  (syntax-rules ()
    ((_) #t)
    ((_ e) e)
    ((_ e rest ...) (if e (and rest ...) #f))))

;; (or e ...) -- #f when empty; otherwise the first true value
(define-syntax or
  "(or e ...)
The first true value, or #f; evaluation stops there."
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e rest ...) (let ((t e)) (if t t (or rest ...))))))

(define-syntax when
  "(when test body ...)
Evaluates the body when test is true."
  (syntax-rules () ((_ test e ...) (if test (begin e ...)))))

(define-syntax unless
  "(unless test body ...)
Evaluates the body when test is false."
  (syntax-rules () ((_ test e ...) (if test (if #f #f) (begin e ...)))))

;; (let* ((v e) ...) body ...) -- each binding sees the ones before it
(define-syntax let*
  "(let* ((name init) ...) body ...)
As let, but each init sees the bindings before it."
  (syntax-rules ()
    ((_ () body ...) (let () body ...))
    ((_ (binding) body ...) (let (binding) body ...))
    ((_ (binding rest ...) body ...) (let (binding) (let* (rest ...) body ...)))))

;; (letrec* ((v e) ...) body ...) -- bindings in scope everywhere, assigned in order
(define-syntax letrec*
  "(letrec* ((name init) ...) body ...)
Bindings visible to every init and the body, assigned in order: for procedures that call each other."
  (syntax-rules ()
    ((_ ((v e) ...) body ...) (let () (define v e) ... (let () body ...)))))

(define-syntax letrec
  "(letrec ((name init) ...) body ...)
As letrec*: bindings visible to every init and the body."
  (syntax-rules ()
    ((_ bindings body ...) (letrec* bindings body ...))))

;; (case key ((datum ...) e ...) ... (else e ...)) -- compares with eqv?, through
;; the global memv
(define-syntax case
  "(case key ((datum ...) e ...) ... (else e ...))
The body of the first clause with a datum eqv? to key; a clause may use => proc, called with key."
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
  "(do ((var init step) ...) (test result ...) body ...)
A loop: binds each var to its init, then until test is true runs the body and steps each var; answers the results."
  (syntax-rules ()
    ((_ "step" var) var)
    ((_ "step" var step) step)
    ((_ ((var init step ...) ...) (test result ...) body ...)
     (let loop ((var init) ...)
       (if test
           (begin (if #f #f) result ...)
           (begin body ... (loop (do "step" var step ...) ...)))))))

;;; Multiple values (specs/phase-9-language.md step 9.2; values and
;;; call-with-values are primitives)

;; (let-values (((a b) e) ((c . d) f) (g h)) body ...) -- each init is evaluated
;; outside every binding, as let's are. Each formal is first bound to a fresh
;; name (x, made anew by each expansion), and the formals to those at the end.
;; (The R7RS reference definition.)
(define-syntax let-values
  "(let-values ((formals expr) ...) body ...)
Binds the values of each expr to its formals, as lambda parameters, evaluated outside the bindings."
  (syntax-rules ()
    ((_ (binding ...) body0 body ...)
     (let-values "bind" (binding ...) () (begin body0 body ...)))
    ((_ "bind" () tmps body)
     (let tmps body))
    ((_ "bind" ((formals init) binding ...) tmps body)
     (let-values "mktmp" formals init () (binding ...) tmps body))
    ((_ "mktmp" () init args bindings tmps body)
     (call-with-values (lambda () init)
       (lambda args (let-values "bind" bindings tmps body))))
    ((_ "mktmp" (a . b) init (arg ...) bindings (tmp ...) body)
     (let-values "mktmp" b init (arg ... x) bindings (tmp ... (a x)) body))
    ((_ "mktmp" a init (arg ...) bindings (tmp ...) body)
     (call-with-values (lambda () init)
       (lambda (arg ... . x) (let-values "bind" bindings (tmp ... (a x)) body))))))

;; (let*-values (((a b) e) ...) body ...) -- each init sees the bindings before it
(define-syntax let*-values
  "(let*-values ((formals expr) ...) body ...)
As let-values, but each expr sees the bindings before it."
  (syntax-rules ()
    ((_ () body ...) (let () body ...))
    ((_ (binding rest ...) body ...) (let-values (binding) (let*-values (rest ...) body ...)))))

;;; Conditions and restarts (specs/phase-7.7-conditions-restarts.md)

;; (guard (var clause ...) body ...) -- cond-style clauses over what was raised;
;; with no matching clause it is raised again where it was first raised
(define-syntax guard
  "(guard (var clause ...) body ...)
Evaluates the body; if it raises, binds var to what was raised and tries the cond clauses, raising again if none matches."
  (syntax-rules ()
    ((_ (var clause ...) body ...)
     (%guard (lambda () body ...)
             (lambda (var) (cond clause ... (else (%guard-no-match))))))))

;; (restart-case form (name (param ...) body ...) ...) -- form with named restarts
(define-syntax restart-case
  "(restart-case form (name (param ...) body ...) ...)
Evaluates form with named restarts; invoking one leaves form and evaluates its body with the arguments."
  (syntax-rules ()
    ((_ form (name params body ...) ...)
     (%restart-case (lambda () form)
                    (list (cons 'name (lambda params body ...)) ...)))))

;;; Generalized set! (SRFI 17; specs/phase-9-language.md step 9.4)
;;;
;;; (set! (proc arg ...) value) compiles to ((setter proc) arg ... value). This is
;;; compiled by the seed, which has no generalized set!, so it is plain code: a
;;; table from each getter to its setter, keyed by the procedure itself.

(define %setters (make-hash-table eq?))
;; the built-in getters and their setters: the compiler calls these directly when
;; the getter is still the built-in one (step 9.4b), so they cannot be changed
(define %builtin-setters (make-hash-table eq?))

(define (setter proc)
  "(setter proc)
The procedure (set! (proc arg ...) value) calls, as (s arg ... value): set-car! for car, set-cdr! for cdr, vector-set! for vector-ref, string-set! for string-ref, hash-table-set! for hash-table-ref and for hash-table-ref/default, and any a program adds with (set! (setter proc) s). Signals an error if proc has none. The setters of the built-in getters cannot be changed."
  (let ((s (hash-table-ref/default %setters proc #f)))
    (if s
        s
        (error (string-append "setter: no setter for "
                              (with-output-to-string (lambda () (display proc))))))))
[setter category: "Control"]

(define (%builtin-setter! get set)
  (hash-table-set! %setters get set)
  (hash-table-set! %builtin-setters get set))
(%builtin-setter! car set-car!)
(%builtin-setter! cdr set-cdr!)
(%builtin-setter! vector-ref vector-set!)
(%builtin-setter! string-ref string-set!)
(%builtin-setter! hash-table-ref hash-table-set!)
(%builtin-setter! hash-table-ref/default
                  (lambda (table key default value) (hash-table-set! table key value)))
;; (set! (setter proc) s) is generalized set! too: setter's own setter adds one
(hash-table-set! %setters setter
                 (lambda (proc s)
                   (if (hash-table-contains? %builtin-setters proc)
                       (error (string-append "setter: the setter of " [proc name] " is built in"))
                       (hash-table-set! %setters proc s))))

(define (getter-with-setter get set)
  "(getter-with-setter get set)
A procedure that does what get does and whose setter is set, as SRFI 17 specifies: (set! ((getter-with-setter get set) x) v) calls (set x v). get itself is left as it is."
  (let ((proc (lambda args (apply get args))))
    [proc documentation: [get lispDocumentation]]
    (hash-table-set! %setters proc set)
    proc))
[getter-with-setter category: "Control"]

;;; The environment, and require (specs/library-path.md)
;;;
;;; *env* holds what the running world knows about itself: cog-lisp's folder, the
;;; library path, the libraries required so far, the platform and the version.
;;; The build sets version (from COGLISP_VERSION, else "dev"); the shell command
;;; calls %env-start! at the start of every run, which reads the rest from that
;;; run's environment, since one image serves every platform and every folder.

(define *env* (make-hash-table eq?))
(hash-table-set! *env* 'version
                 (let ((v (get-environment-variable "COGLISP_VERSION"))) (if v v "dev")))
(hash-table-set! *env* 'libraries '())

;; the non-empty parts of s between the separator character
(define (%env-parts s separator)
  (let loop ((parts (string-split s separator)) (acc '()))
    (cond ((null? parts) (reverse acc))
          ((string=? (car parts) "") (loop (cdr parts) acc))
          (else (loop (cdr parts) (cons (car parts) acc))))))

(define (%env-start!)
  (let* ((windows [[(smalltalk OSPlatform) current] isWindows])
         (given (get-environment-variable "COGLISP_HOME"))
         (home (if (and given (not (string=? given "")))
                   [[given asFileReference] fullName]
                   [[[(smalltalk Smalltalk) imageDirectory] parent] fullName]))
         (path (get-environment-variable "COGLISP_PATH")))
    (hash-table-set! *env* 'home home)
    (hash-table-set! *env* 'platform (if windows 'windows 'linux))
    (hash-table-set! *env* 'library-path
                     (append (if path (%env-parts path (if windows #\; #\:)) '())
                             (list [[[home asFileReference] / "lib"] fullName])))))

;; the full path of name.lisp in the first folder of the library path that has it, or #f
(define (require-path name)
  "(require-path 'name)
The full path of the file (require 'name) would load: name.lisp in the first folder of (hash-table-ref *env* 'library-path) that has it, or #f. Loads nothing."
  (let ((relative (string-append (symbol->string name) ".lisp")))
    (let loop ((folders (hash-table-ref/default *env* 'library-path '())))
      (if (null? folders)
          #f
          (let ((file [[(car folders) asFileReference] resolveString: relative]))
            (if [file exists] [file fullName] (loop (cdr folders))))))))
[require-path category: "Files"]

(define (require name)
  "(require 'name)
Loads the library name.lisp from the first folder of (hash-table-ref *env* 'library-path) that has it, once, and answers its full path; a name with slashes names a subfolder. The library path is the folders of COGLISP_PATH, then cog-lisp's own lib folder: (require 'cl) loads the Common Lisp names, (require 'test) the test library."
  (if (not (symbol? name))
      (error (string-append "require: not a symbol: " (with-output-to-string (lambda () (write name))))))
  (let ((seen (assq name (hash-table-ref *env* 'libraries))))
    (if seen
        (cdr seen)
        (let ((file (require-path name)))
          (if (not file)
              (error (string-append "require: no library named " (symbol->string name) " in "
                                    (with-output-to-string
                                      (lambda () (display (hash-table-ref/default *env* 'library-path '())))))))
          ;; recorded before it loads, so a library that requires itself does not loop
          (hash-table-set! *env* 'libraries (cons (cons name file) (hash-table-ref *env* 'libraries)))
          (load file)
          file))))
[require category: "Files"]

;;; Lists: R7RS's list-ref, list-tail and c[ad]r names, and SRFI 1's filter,
;;; remove, delete, delete-duplicates, fold, reduce and iota, with sort
;;; (specs/lisp-expert-libraries.md). Compiled by the seed, so plain code.

(define (list-tail lst k)
  "(list-tail list k)
The list after its first k elements, sharing its structure."
  (let loop ((l lst) (i k))
    (cond ((= i 0) l)
          ((pair? l) (loop (cdr l) (- i 1)))
          (else (error (string-append "list-tail: index out of range: " (number->string k)))))))

(define (list-ref lst k)
  "(list-ref list k)
Element k of list, counting from 0."
  (let ((tail (list-tail lst k)))
    (if (pair? tail)
        (car tail)
        (error (string-append "list-ref: index out of range: " (number->string k))))))

(define (caar x) "(caar pair)\nThe car of the car of pair." (car (car x)))
(define (cadr x) "(cadr pair)\nThe car of the cdr of pair: the second element of a list." (car (cdr x)))
(define (cdar x) "(cdar pair)\nThe cdr of the car of pair." (cdr (car x)))
(define (cddr x) "(cddr pair)\nThe cdr of the cdr of pair: a list without its first two elements." (cdr (cdr x)))
(define (caaar x) "(caaar pair)\nThe car of the car of the car of pair." (car (car (car x))))
(define (caadr x) "(caadr pair)\nThe car of the car of the cdr of pair." (car (car (cdr x))))
(define (cadar x) "(cadar pair)\nThe car of the cdr of the car of pair." (car (cdr (car x))))
(define (caddr x) "(caddr pair)\nThe car of the cdr of the cdr of pair: the third element of a list." (car (cdr (cdr x))))
(define (cdaar x) "(cdaar pair)\nThe cdr of the car of the car of pair." (cdr (car (car x))))
(define (cdadr x) "(cdadr pair)\nThe cdr of the car of the cdr of pair." (cdr (car (cdr x))))
(define (cddar x) "(cddar pair)\nThe cdr of the cdr of the car of pair." (cdr (cdr (car x))))
(define (cdddr x) "(cdddr pair)\nThe cdr of the cdr of the cdr of pair." (cdr (cdr (cdr x))))
(define (caaaar x) "(caaaar pair)\nThe car of the car of the car of the car of pair." (car (car (car (car x)))))
(define (caaadr x) "(caaadr pair)\nThe car of the car of the car of the cdr of pair." (car (car (car (cdr x)))))
(define (caadar x) "(caadar pair)\nThe car of the car of the cdr of the car of pair." (car (car (cdr (car x)))))
(define (caaddr x) "(caaddr pair)\nThe car of the car of the cdr of the cdr of pair." (car (car (cdr (cdr x)))))
(define (cadaar x) "(cadaar pair)\nThe car of the cdr of the car of the car of pair." (car (cdr (car (car x)))))
(define (cadadr x) "(cadadr pair)\nThe car of the cdr of the car of the cdr of pair." (car (cdr (car (cdr x)))))
(define (caddar x) "(caddar pair)\nThe car of the cdr of the cdr of the car of pair." (car (cdr (cdr (car x)))))
(define (cadddr x) "(cadddr pair)\nThe car of the cdr of the cdr of the cdr of pair: the fourth element of a list." (car (cdr (cdr (cdr x)))))
(define (cdaaar x) "(cdaaar pair)\nThe cdr of the car of the car of the car of pair." (cdr (car (car (car x)))))
(define (cdaadr x) "(cdaadr pair)\nThe cdr of the car of the car of the cdr of pair." (cdr (car (car (cdr x)))))
(define (cdadar x) "(cdadar pair)\nThe cdr of the car of the cdr of the car of pair." (cdr (car (cdr (car x)))))
(define (cdaddr x) "(cdaddr pair)\nThe cdr of the car of the cdr of the cdr of pair." (cdr (car (cdr (cdr x)))))
(define (cddaar x) "(cddaar pair)\nThe cdr of the cdr of the car of the car of pair." (cdr (cdr (car (car x)))))
(define (cddadr x) "(cddadr pair)\nThe cdr of the cdr of the car of the cdr of pair." (cdr (cdr (car (cdr x)))))
(define (cdddar x) "(cdddar pair)\nThe cdr of the cdr of the cdr of the car of pair." (cdr (cdr (cdr (car x)))))
(define (cddddr x) "(cddddr pair)\nThe cdr of the cdr of the cdr of the cdr of pair." (cdr (cdr (cdr (cdr x)))))

(define (filter keep? lst)
  "(filter pred list)
The elements of list for which (pred element) is true, in order."
  (let loop ((l lst) (acc '()))
    (cond ((null? l) (reverse acc))
          ((keep? (car l)) (loop (cdr l) (cons (car l) acc)))
          (else (loop (cdr l) acc)))))

(define (remove drop? lst)
  "(remove pred list)
The elements of list for which (pred element) is false, in order: filter with the test turned around (SRFI 1)."
  (filter (lambda (x) (not (drop? x))) lst))

(define (delete item lst . same?)
  "(delete x list [=])
The elements of list that are not x, compared with = (equal? by default), in order."
  (let ((same (if (pair? same?) (car same?) equal?)))
    (filter (lambda (y) (not (same item y))) lst)))

(define (delete-duplicates lst . same?)
  "(delete-duplicates list [=])
list without its repeated elements, compared with = (equal? by default): the first of each is kept, in order."
  (let ((same (if (pair? same?) (car same?) equal?)))
    (let loop ((l lst) (kept '()))
      (cond ((null? l) (reverse kept))
            ((let seen ((k kept)) (and (pair? k) (or (same (car k) (car l)) (seen (cdr k)))))
             (loop (cdr l) kept))
            (else (loop (cdr l) (cons (car l) kept)))))))

(define (fold kons knil lst)
  "(fold kons knil list)
Combines the elements of list from the left: (kons element accumulator), starting from knil. (fold + 0 list) sums a list; (fold cons '() list) reverses it."
  (let loop ((l lst) (acc knil))
    (if (null? l) acc (loop (cdr l) (kons (car l) acc)))))

(define (reduce f ridentity lst)
  "(reduce f ridentity list)
As fold with the first element as the start: (reduce + 0 list) sums a list, and an empty list answers ridentity."
  (if (null? lst) ridentity (fold f (car lst) (cdr lst))))

(define (iota count . start-step)
  "(iota count [start [step]])
A list of count numbers: start (0 by default), then each step (1 by default) more. (iota 5) is (0 1 2 3 4); (iota 5 1) is (1 2 3 4 5)."
  (let ((start (if (pair? start-step) (car start-step) 0))
        (step (if (and (pair? start-step) (pair? (cdr start-step))) (car (cdr start-step)) 1)))
    (let loop ((i (- count 1)) (acc '()))
      (if (< i 0) acc (loop (- i 1) (cons (+ start (* i step)) acc))))))

;; a stable merge of two sorted lists
(define (%sort-merge a b less?)
  (let loop ((a a) (b b) (acc '()))
    (cond ((null? a) (append (reverse acc) b))
          ((null? b) (append (reverse acc) a))
          ((less? (car b) (car a)) (loop a (cdr b) (cons (car b) acc)))
          (else (loop (cdr a) b (cons (car a) acc))))))

(define (%sort-list lst less?)
  (let ((n (length lst)))
    (if (< n 2)
        lst
        (let split ((front '()) (back lst) (i (quotient n 2)))
          (if (= i 0)
              (%sort-merge (%sort-list (reverse front) less?) (%sort-list back less?) less?)
              (split (cons (car back) front) (cdr back) (- i 1)))))))

(define (sort sequence less?)
  "(sort sequence less?)
A new list (or vector, for a vector) of the elements of sequence in order by less?, stable: equal elements keep their order. (sort (list 3 1 2) <) is (1 2 3)."
  (if (vector? sequence)
      (list->vector (%sort-list (vector->list sequence) less?))
      (%sort-list sequence less?)))

(for-each (lambda (p) [p category: "Lists"])
          (list list-tail list-ref filter remove delete delete-duplicates fold reduce iota sort
                caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
                caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
                cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr))
