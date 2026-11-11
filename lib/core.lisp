;;; core.lisp -- cog-lisp's derived forms (specs/06-phase-7-macros.md section 7;
;;; hygienic since specs/15-phase-9-language.md step 9.3)
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

;;; Multiple values (specs/15-phase-9-language.md step 9.2; values and
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

;;; Conditions and restarts (specs/10-phase-7.7-conditions-restarts.md)

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

;;; Generalized set! (SRFI 17; specs/15-phase-9-language.md step 9.4)
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

;;; The environment, and require (specs/18-library-path.md)
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

(define (require name . options)
  "(require 'name [option value] ...), (require \"file.lisp\" [option value] ...)
Loads a library once and brings its exported names into this file (or this REPL session): name.lisp from the first folder of (hash-table-ref *env* 'library-path) that has it, or a file named by a string, beside this file. Answers the file's full path. With no options every export comes in unqualified; 'prefix p brings them in as p followed by the name ((require 'console 'prefix 'con:) gives con:rule), 'only, 'except and 'rename '((old new) ...) choose. A library's full names (console:rule) work whether or not they are imported. (require 'cl) loads the Common Lisp names, (require 'test) the test library."
  (let* ((file (%require-file name))
         (key (if (symbol? name) name file))
         (seen (assoc key (hash-table-ref *env* 'libraries))))
    (unless seen
      ;; recorded before it loads, so a library that requires itself does not loop
      (hash-table-set! *env* 'libraries (cons (cons key file) (hash-table-ref *env* 'libraries)))
      (%load-library file))
    (let ((unit (%unit-at file)) (here (%current-unit)))
      (if (and unit here [unit isLibrary])
          (%require-import here unit options)
          (if (pair? options)
              (error (string-append "require: " file " is not a library, so it has nothing to import")))))
    file))
[require category: "Files"]

;; the full path of the library require names
(define (%require-file name)
  (cond ((symbol? name)
         (let ((file (require-path name)))
           (if (not file)
               (error (string-append "require: no library named " (symbol->string name) " in "
                                     (with-output-to-string
                                       (lambda () (display (hash-table-ref/default *env* 'library-path '())))))))
           file))
        ((string? name)
         (let ((ref [(smalltalk LispCompiler) resolveInput: name]))
           (if (not [ref exists]) (error (string-append "require: no such file: " name)))
           [ref fullName]))
        (else (error (string-append "require: not a symbol or a file name: "
                                    (with-output-to-string (lambda () (write name))))))))

;; bring library's exports into unit, as options say: only, then except, then
;; rename, then prefix (specs/27-namespaces.md R-5)
(define (%require-import unit library options)
  (let ((exports (vector->list [library exports]))
        (lib-name (symbol->string [library library])))
    (define (check-exported names what)
      (for-each (lambda (n)
                  (unless (memq n exports)
                    (error (string-append "require: " lib-name " does not export " (symbol->string n)
                                          " (in " what ")"))))
                names))
    (let loop ((os options) (only #f) (except '()) (rename '()) (prefix #f))
      (cond
        ((pair? os)
         (unless (pair? (cdr os))
           (error (string-append "require: the option " (with-output-to-string (lambda () (write (car os)))) " has no value")))
         (let ((o (car os)) (v (cadr os)))
           (cond ((eq? o 'only) (check-exported v "only") (loop (cddr os) v except rename prefix))
                 ((eq? o 'except) (check-exported v "except") (loop (cddr os) only v rename prefix))
                 ((eq? o 'rename)
                  (check-exported (map car v) "rename")
                  (loop (cddr os) only except v prefix))
                 ((eq? o 'prefix)
                  (unless (symbol? v) (error "require: a prefix is a symbol, such as con:"))
                  (loop (cddr os) only except rename v))
                 (else (error (string-append "require: unknown option "
                                             (with-output-to-string (lambda () (write o)))
                                             "; the options are only, except, rename and prefix"))))))
        (else
         ;; all or nothing: every conflict is found before any name is imported
         [unit importAll:
               (list->vector
                (map (lambda (e)
                       (let* ((renamed (let ((r (assq e rename))) (if r (cadr r) e)))
                              (local (if prefix
                                         (string->symbol (string-append (symbol->string prefix) (symbol->string renamed)))
                                         renamed)))
                         [local -> [library qualify: e]]))
                     (filter (lambda (e) (and (or (not only) (memq e only)) (not (memq e except)))) exports)))])))))

(define-syntax library
  "(library name (export name ...))
The first form of a library's file: the file's top-level definitions belong to the library name, and only the names exported are brought in by (require 'name). Each definition is also reachable by its full name, name:definition, from anywhere."
  (syntax-rules (export)
    ((_ name (export id ...)) (%library 'name '(id ...)))))

(define (%library name exports)
  (let ((unit (%current-unit)) (path (current-load-path)))
    (if (or (not unit) (not path) (not [unit isAtFirstForm]))
        (error "library: only as the first form of a file that is being loaded"))
    (if (not (symbol? name)) (error "library: the name is a symbol"))
    (for-each (lambda (e) (if (not (symbol? e)) (error "library: an export is a symbol"))) exports)
    [unit beLibrary: name exports: (list->vector exports) owned: (list->vector (%library-own-names path))]
    name))

;; the names a file defines at its top level (in begin forms too): read, not run
(define (%library-own-names path)
  (define (names-of form acc)
    (cond ((not (pair? form)) acc)
          ((eq? (car form) 'begin) (fold names-of acc (cdr form)))
          ((and (memq (car form) '(define define-macro define-syntax)) (pair? (cdr form)))
           (let ((target (cadr form)))
             (cond ((symbol? target) (cons target acc))
                   ((and (pair? target) (symbol? (car target))) (cons (car target) acc))
                   (else acc))))
          (else acc)))
  (call-with-input-file path
    (lambda (port)
      (let loop ((acc '()))
        (let ((form (read port)))
          (if (eof-object? form) acc (loop (names-of form acc))))))))

(define (imports)
  "(imports)
What this file, or this REPL session, has imported: a list of (name . full-name), sorted by name."
  (let ((unit (%current-unit)))
    (if (not unit)
        '()
        (sort (map (lambda (a) (cons [a key] [a value])) (vector->list [[[unit imports] associations] asArray]))
              (lambda (a b) (string<? (symbol->string (car a)) (symbol->string (car b))))))))
[imports category: "Files"]

;;; Lists: R7RS's list-ref, list-tail and c[ad]r names, and SRFI 1's filter,
;;; remove, delete, delete-duplicates, fold, reduce and iota, with sort
;;; (specs/22-lisp-expert-libraries.md). Compiled by the seed, so plain code.

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

;;; More of SRFI 1: any, every, find, filter-map, append-map and alist-delete
;;; (specs/23-lisp-expert-review.md R-1). Each takes one list, as map does.

(define (%not-a-list who x)
  (error (string-append who ": not a list: " (with-output-to-string (lambda () (write x))))))

(define (any pred lst)
  "(any pred list)
The first true value (pred element) answers, trying the elements in order, or #f if there is none: (any (lambda (n) (and (even? n) (* n n))) (list 1 2 3)) is 4."
  (let loop ((l lst))
    (cond ((null? l) #f)
          ((pair? l) (or (pred (car l)) (loop (cdr l))))
          (else (%not-a-list "any" lst)))))

(define (every pred lst)
  "(every pred list)
#t for an empty list; otherwise #f as soon as (pred element) is false, else the value pred answered for the last element."
  (let loop ((l lst) (last #t))
    (cond ((null? l) last)
          ((pair? l) (let ((v (pred (car l)))) (if v (loop (cdr l) v) #f)))
          (else (%not-a-list "every" lst)))))

(define (find pred lst)
  "(find pred list)
The first element of list for which (pred element) is true, or #f if there is none."
  (let loop ((l lst))
    (cond ((null? l) #f)
          ((pair? l) (if (pred (car l)) (car l) (loop (cdr l))))
          (else (%not-a-list "find" lst)))))

(define (filter-map f lst)
  "(filter-map f list)
The true values of (f element), in order: map, keeping only what is not #f."
  (let loop ((l lst) (acc '()))
    (cond ((null? l) (reverse acc))
          ((pair? l) (let ((v (f (car l)))) (loop (cdr l) (if v (cons v acc) acc))))
          (else (%not-a-list "filter-map" lst)))))

(define (append-map f lst)
  "(append-map f list)
The lists (f element) answers, appended in order: (apply append (map f list)) in one step."
  (let loop ((l lst) (acc '()))
    (cond ((null? l) (apply append (reverse acc)))
          ((pair? l) (loop (cdr l) (cons (f (car l)) acc)))
          (else (%not-a-list "append-map" lst)))))

(define (alist-delete key alist . same?)
  "(alist-delete key alist [=])
A new alist without the entries whose key is key, compared as (= key entry-key) with = (equal? by default); alist itself is unchanged."
  (let ((same (if (pair? same?) (car same?) equal?)))
    (filter (lambda (entry) (not (same key (car entry)))) alist)))

(for-each (lambda (p) [p category: "Lists"])
          (list any every find filter-map append-map alist-delete))

;;; String prefixes and suffixes (SRFI 13's argument order; R-2)

(define (string-prefix? prefix s)
  "(string-prefix? prefix string)
#t if string begins with prefix."
  (let ((n (string-length prefix)))
    (and (<= n (string-length s)) (string=? prefix (substring s 0 n)))))

(define (string-suffix? suffix s)
  "(string-suffix? suffix string)
#t if string ends with suffix."
  (let ((n (string-length suffix)) (m (string-length s)))
    (and (<= n m) (string=? suffix (substring s (- m n) m)))))

(for-each (lambda (p) [p category: "Strings"]) (list string-prefix? string-suffix?))

;;; Parameters (R7RS 4.2.6; R-3). A parameter is a procedure answering its
;;; value; called with the private token it sets the value (one argument) or
;;; answers its converter (none). parameterize evaluates every parameter and
;;; value first, then swaps the values in and out with dynamic-wind, so they come
;;; back however the body is left. One binding per image, not per process.

(define %parameter-token (list 'parameter))

(define (make-parameter value . converter)
  "(make-parameter value [converter])
A parameter: a procedure that answers its current value when called with no arguments. A converter is applied to value and to each value parameterize gives it."
  (let* ((convert (if (pair? converter) (car converter) (lambda (x) x)))
         (current (convert value)))
    (lambda args
      (cond ((null? args) current)
            ((and (eq? (car args) %parameter-token) (pair? (cdr args)))
             (set! current (car (cdr args)))
             current)
            ((eq? (car args) %parameter-token) convert)
            (else (error "parameter: a parameter takes no arguments"))))))

(define (%parameterize params vals thunk)
  (let ((news (let loop ((ps params) (vs vals) (acc '()))
                (if (null? ps)
                    (reverse acc)
                    (loop (cdr ps) (cdr vs) (cons (((car ps) %parameter-token) (car vs)) acc)))))
        (swap! (lambda (ps vals)
                 (let loop ((ps ps) (vs vals) (olds '()))
                   (if (null? ps)
                       (reverse olds)
                       (let ((old ((car ps))))
                         ((car ps) %parameter-token (car vs))
                         (loop (cdr ps) (cdr vs) (cons old olds))))))))
    (dynamic-wind
      (lambda () (set! news (swap! params news)))
      thunk
      (lambda () (set! news (swap! params news))))))

(define-syntax parameterize
  "(parameterize ((param value) ...) body ...)
Evaluates the body with each param giving value (after its converter), and gives the old values back however the body is left: by returning, an error or a restart."
  (syntax-rules ()
    ((_ ((param value) ...) body ...)
     (%parameterize (list param ...) (list value ...) (lambda () body ...)))))

[make-parameter category: "Control"]

(define (documentation-categories)
  "(documentation-categories)
The sections of the reference of the built-ins, in its order: the ones documentation-category answers."
  '("Special forms" "Derived forms" "Equality and types" "Numbers" "Lists"
    "Characters" "Strings" "Vectors" "Hash tables" "Control"
    "Conditions and restarts" "Evaluation and macros" "Output" "Ports" "Files" "Network"
    "The system" "Smalltalk interop" "Language server" "The compiler and reader"))
[documentation-categories category: "Evaluation and macros"]

(for-each (lambda (p) [p category: "Lists"])
          (list list-tail list-ref filter remove delete delete-duplicates fold reduce iota sort
                caar cadr cdar cddr caaar caadr cadar caddr cdaar cdadr cddar cdddr
                caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
                cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr))
