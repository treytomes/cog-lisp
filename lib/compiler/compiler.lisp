;;; compiler.lisp -- cog-lisp's compiler, written in cog-lisp
;;; (specs/13-phase-8-self-hosting.md step 8.3)
;;;
;;; Written as a procedure-for-procedure counterpart of the compiler written in
;;; Smalltalk (LispCompiler in src/coglisp-compiler.st up to release v0.1.2; it
;;; retired in Phase 9 step 9.1, and this is now cog-lisp's only compiler). It
;;; built the same nodes, so through Opal it compiled every form to the same
;;; CompiledMethod, byte for byte. Each procedure names the Smalltalk method it
;;; mirrored when the names differ; those names refer to that history. Every call
;;; that makes a temporary name or translates a form happens in that method's
;;; order, since the names l1, l2, ... are part of the generated code.
;;;
;;;   (compile-form '(+ 1 2))           -> a CompiledMethod
;;;   (lisp-eval '(define (f x) x))     -> evaluates as eval does
;;;   (lisp-eval-string "(f 3)")        -> 3
;;;
;;; The compiler's state (LispCompiler's instance variables) is a vector, passed as
;;; the first argument c where the Smalltalk has self. A scope is a Smalltalk
;;; IdentityDictionary from LISP symbol to temporary name, as there.

(define lc-nesting-budget 10)      ; LispCompiler class>>nestingBudget
(define lc-max-expansions 10000)   ; LispCompiler class>>maxExpansions

;;; ---------------------------------------------------------------------------
;;; State

(define (make-lisp-compiler)
  ;; counter source-map options self-loop inline-temps top-form source-context
  ;; in-body expansion-depth expr-depth
  (vector 0 #f [[(smalltalk LispCompiler) defaultOptions] copy] #f 0 #f #f #f 0 0 #f '()))

(define (c-counter c) (vector-ref c 0))
(define (c-counter! c v) (vector-set! c 0 v))
(define (c-source-map c) (vector-ref c 1))
(define (c-source-map! c v) (vector-set! c 1 v))
(define (c-options c) (vector-ref c 2))
(define (c-self-loop c) (vector-ref c 3))
(define (c-self-loop! c v) (vector-set! c 3 v))
(define (c-inline-temps c) (vector-ref c 4))
(define (c-inline-temps! c v) (vector-set! c 4 v))
(define (c-top-form c) (vector-ref c 5))
(define (c-top-form! c v) (vector-set! c 5 v))
(define (c-source-context c) (vector-ref c 6))
(define (c-source-context! c v) (vector-set! c 6 v))
(define (c-in-body c) (vector-ref c 7))
(define (c-in-body! c v) (vector-set! c 7 v))
(define (c-expansion-depth c) (vector-ref c 8))
(define (c-expansion-depth! c v) (vector-set! c 8 v))
(define (c-expr-depth c) (vector-ref c 9))
(define (c-expr-depth! c v) (vector-set! c 9 v))
;; true once this compilation expanded a syntax-rules macro, which makes aliases
(define (c-hygienic c) (vector-ref c 10))
(define (c-hygienic! c v) (vector-set! c 10 v))
;; the forms being translated, innermost first: a compile error records them, so
;; an editor can place it (Phase 10 step 10.5; review C-18)
(define (c-forms c) (vector-ref c 11))
(define (c-forms! c v) (vector-set! c 11 v))

;; A self loop (translateLambda:...): name local params proc again result temps used scratch
(define (make-loop name local params proc again result)
  (vector name local params proc again result '() #f #f))
(define (loop-name l) (vector-ref l 0))
(define (loop-local l) (vector-ref l 1))
(define (loop-params l) (vector-ref l 2))
(define (loop-proc l) (vector-ref l 3))
(define (loop-again l) (vector-ref l 4))
(define (loop-result l) (vector-ref l 5))
(define (loop-temps l) (vector-ref l 6))
(define (loop-add-temp! l nm) (vector-set! l 6 (append (vector-ref l 6) (list nm))))
(define (loop-used? l) (vector-ref l 7))
(define (loop-used! l) (vector-set! l 7 #t))
(define (loop-scratch l) (vector-ref l 8))
(define (loop-scratch! l v) (vector-set! l 8 v))

;;; Scopes
(define (scope-new) [(smalltalk IdentityDictionary) new])
(define (scope-copy s) [s copy])
(define (scope-ref s k) [s at: k ifAbsent: (lambda () #f)])
(define (scope-has? s k) [s includesKey: k])
(define (scope-set! s k v) [s at: k put: v])

;;; Identifiers (specs/15-phase-9-language.md step 9.3): a symbol, or an alias that a
;;; syntax-rules expansion made. A scope maps an identifier to its binding: a temp
;;; name (a string) or a local macro.

(define (lc-identifier? x) (or (symbol? x) [x isLispAlias]))

;; the symbol an identifier is spelled with
(define (lc-id-symbol x) (if (symbol? x) x [x baseName]))

;; is x the identifier spelled name? (for keywords that are not bindings)
(define (lc-id-is? x name) (or (eq? x name) (and [x isLispAlias] (eq? [x baseName] name))))

;;; Units (specs/27-namespaces.md): what is being compiled, a file or the REPL
;;; session (LispUnit, src/coglisp-compiler.st). A free name means, in order:
;;; the library's own definition (when the unit is a library), the unit's import,
;;; or the global of that name. A library's own names are global cells under full
;;; names (console:rule), and a full name always means itself. A define-syntax
;;; stamps its scope with its unit, so its expansions mean what they meant where
;;; the macro was defined.

(define lc-unit-key (smalltalk-symbol "lispUnit"))
(define (lc-current-unit) [(smalltalk LispCurrentUnit) value])
(define (lc-scope-unit scope)
  (let ((u (scope-ref scope lc-unit-key)))
    (if u u (lc-current-unit))))

;; scope, stamped with the current unit if it is not already
(define (lc-scope-with-unit scope)
  (let ((unit (lc-current-unit)))
    (if (or (smalltalk-nil? unit) (scope-has? scope lc-unit-key))
        scope
        (let ((s (scope-copy scope)))
          (scope-set! s lc-unit-key unit)
          s))))

;; a full name, such as console:rule, means itself everywhere
(define (lc-qualified? sym) [[sym name] includes: #\:])

;; the global symbol a free name means in unit. An import is looked at first,
;; since a prefixed name (con:rule) is spelled like a full name.
(define (lc-resolve-global sym unit)
  (if (smalltalk-nil? unit)
      sym
      (let ((target [unit importAt: sym])
            (library? [unit isLibrary]))
        (cond ((not (smalltalk-nil? target)) target)
              ((lc-qualified? sym) sym)
              ((and library? [unit owns: sym]) [unit qualify: sym])
              ((not library?) sym)
              ((hash-table-ref/default lc-special-forms sym #f) sym)
              ([[(smalltalk LispEnvironment) default] isBound: sym] sym)
              ;; in a library, a name nothing else binds is the library's own,
              ;; defined later in its file
              (else [unit qualify: sym])))))

;; the global symbol a top-level definition of id defines: a library's own full
;; name; an error for a name the file imported (R-8); and a warning when a
;; program redefines a built-in (R-10)
(define (lc-define-target id)
  (let* ((sym (lc-id-symbol id))
         (unit (if (symbol? id) (lc-current-unit) (lc-scope-unit [id env]))))
    (cond ((or (smalltalk-nil? unit) (lc-qualified? sym)) sym)
          ((not (smalltalk-nil? [unit importAt: sym]))
           (lc-error (string-append (symbol->string sym) " is imported (as "
                                    [[unit importAt: sym] name]
                                    "): choose another name, or import it with a prefix or under another name")))
          ([unit isLibrary] [unit addOwned: sym] [unit qualify: sym])
          (else
           (when [(smalltalk LispUnit) isBuiltin: sym]
             [unit warn: (string-append "define replaces the built-in " (symbol->string sym))])
           sym))))

;; what id means in scope: a temp name (a string), a local macro, or the symbol of
;; a global (a special form, a global macro or a variable). An alias not bound
;; here means what its name means where its macro was defined.
(define (lc-binding id scope)
  (let ((b (scope-ref scope id)))
    (cond (b b)
          ((symbol? id) (lc-resolve-global id (lc-scope-unit scope)))
          (else (lc-binding [id name] [id env])))))

;; the special form x names in scope, or #f
(define (lc-special x scope)
  (and (lc-identifier? x)
       (let ((b (lc-binding x scope)))
         (and (symbol? b) (hash-table-ref/default lc-special-forms b #f) b))))

;; the global macro named sym, or #f
(define (lc-global-macro sym)
  (let ((value (lc-global-value sym)))
    (and (not (eq? value lc-unbound)) [value isKindOf: (smalltalk LispMacro)] value)))

;; identifiers the compiler itself puts into code it makes up: they mean the
;; global special forms whatever the program binds locally
(define lc-core-env (scope-new))
(define (lc-core name) [(smalltalk LispAlias) name: name env: lc-core-env])
(define lc-core-define (lc-core 'define))
(define lc-core-lambda (lc-core 'lambda))
(define lc-core-let (lc-core 'let))

;; d with every alias turned back into its symbol (inside quote); cycles kept
(define (lc-strip d) (lc-strip* d (make-hash-table eq?)))
(define (lc-strip* d seen)
  (cond ([d isLispAlias] [d baseName])
        ((pair? d)
         (if (hash-table-contains? seen d)
             d
             (begin
               (hash-table-set! seen d #t)
               (let ((a (lc-strip* (car d) seen)) (b (lc-strip* (cdr d) seen)))
                 (if (and (eq? a (car d)) (eq? b (cdr d))) d (cons a b))))))
        ((vector? d)
         (if (hash-table-contains? seen d)
             d
             (begin
               (hash-table-set! seen d #t)
               (let* ((items (vector->list d))
                      (stripped (lc-map (lambda (x) (lc-strip* x seen)) items)))
                 (if (lc-all-eq? items stripped)
                     d
                     (let ((v (list->vector stripped))) [v beReadOnlyObject] v))))))
        (else d)))
(define (lc-all-eq? a b) (or (null? a) (and (eq? (car a) (car b)) (lc-all-eq? (cdr a) (cdr b)))))

;;; Smalltalk control, so unwinding behaves exactly as in the Smalltalk compiler
(define (lc-ensure thunk after) [thunk ensure: after])
(define (lc-if-curtailed thunk after) [thunk ifCurtailed: after])
(define (lc-on-error thunk handler) [thunk on: (smalltalk Error) do: handler])

;;; Lists, strictly left to right
(define (lc-map f l)
  (if (null? l) '() (let* ((x (f (car l))) (rest (lc-map f (cdr l)))) (cons x rest))))
(define (lc-vmap f l) (list->vector (lc-map f l)))
(define (lc-iota from to)                           ; from .. to inclusive
  (if (> from to) '() (cons from (lc-iota (+ from 1) to))))
(define (lc-last l) (if (null? (cdr l)) (car l) (lc-last (cdr l))))
(define (lc-all-but-last l) (if (null? (cdr l)) '() (cons (car l) (lc-all-but-last (cdr l)))))
(define (lc-count pred l) (if (null? l) 0 (+ (if (pred (car l)) 1 0) (lc-count pred (cdr l)))))
(define (lc-any? pred l) (and (pair? l) (or (pred (car l)) (lc-any? pred (cdr l)))))
(define (lc-ref l i) (if (= i 0) (car l) (lc-ref (cdr l) (- i 1))))   ; 0-based
(define (lc-list-ref1 l i) (lc-ref l (- i 1)))    ; 1-based, as the Smalltalk at:

;;; ---------------------------------------------------------------------------
;;; Options

(define (lc-uses? c option) [(c-options c) includes: (smalltalk-symbol option)])

;;; ---------------------------------------------------------------------------
;;; Node-building helpers

(define (lc-next-name c)
  (c-counter! c (+ (c-counter c) 1))
  (string-append "l" (number->string (c-counter c))))

(define (lc-error msg) [[(smalltalk LispCompileError) new] signal: msg])

(define (lc-value-selector n)                       ; valueSelectorFor:
  (if (= n 0)
      "value"
      (let loop ((i 0) (s "")) (if (= i n) s (loop (+ i 1) (string-append s "value:"))))))

(define (lc-unspecified-node)
  (opal-send (opal-var "LispUnspecified") "default" (vector)))

(define (lc-and-unspecified node)
  (opal-send (opal-literal #t) "ifTrue:"
             (vector (opal-block (vector) (vector) (vector node (lc-unspecified-node))))))

(define (lc-recorded-source-of c form)
  (let ((sm (c-source-map c)))
    (cond ((not sm) #f)
          ((vector? sm) (reader-source-for sm form))     ; the LISP reader
          (else (let ((s [sm sourceFor: form])) (if (smalltalk-nil? s) #f s))))))

(define (lc-source-of c form)
  (or (lc-recorded-source-of c form)
      (c-source-context c)
      [(smalltalk LispPrinter) writeString: form]))

;; arrayNode: {e1. e2. ...}; a long one is filled an element at a time
(define (lc-array-node c elements)                  ; elements: a list of nodes
  (let ((n (length elements)))
    (if (> n 16)
        (let ((t (lc-next-name c)))
          (opal-send (opal-literal #t) "ifTrue:"
            (vector
             (opal-block (vector) (vector (opal-var t))
               (list->vector
                (append
                 (list (opal-assign t (opal-send (opal-var "Array") "new:" (vector (opal-literal n)))))
                 (lc-map (lambda (i)
                           (opal-send (opal-var t) "at:put:" (vector (opal-literal i) (lc-list-ref1 elements i))))
                         (lc-iota 1 n))
                 (list (opal-var t))))))))
        (opal-brace (list->vector elements)))))

(define (lc-empty-list-node) (opal-send (opal-var "LispEmptyList") "default" (vector)))

(define (lc-symbol-node sym)
  (opal-send (opal-var "LispSymbol") "named:" (vector (opal-literal (symbol->string sym)))))

;; listToArray: the elements of a proper list in code; anything else is bad syntax
(define (lc-items lst)
  (cond ((null? lst) '())
        ((not (pair? lst)) (lc-error (string-append "bad syntax: expected a list: " (lc-show lst))))
        ((not (list? lst)) (lc-error (string-append "bad syntax: improper list: " (lc-show lst))))
        (else lst)))

;;; Syntax checks

(define (lc-show datum) [(smalltalk LispPrinter) writeString: datum limitedTo: 60])

(define (lc-syntax-error name form)
  (lc-error (string-append name ": bad syntax: " (lc-show form))))

(define (lc-check form min max)                     ; check:operands:to: (max #f: no limit)
  (let ((n (length (lc-items (cdr form)))))
    (when (or (< n min) (and max (> n max)))
      (lc-syntax-error (symbol->string (lc-id-symbol (car form))) form))))

(define (lc-check-define form)
  (let ((parts (lc-items (cdr form))))
    (when (null? parts) (lc-syntax-error "define" form))
    (let ((target (car parts)))
      (if (pair? target)
          (unless (lc-identifier? (car target))
            (lc-error (string-append "define: bad name: " (lc-show (car target)))))
          (begin
            (unless (lc-identifier? target) (lc-error (string-append "define: bad name: " (lc-show target))))
            (unless (= (length parts) 2) (lc-syntax-error "define" form)))))))

;; ((name expr) ...), each name a symbol, none twice: the bindings as 2-lists
(define (lc-check-bindings data)
  (let loop ((bs (lc-items data)) (seen '()) (acc '()))
    (if (null? bs)
        (reverse acc)
        (let* ((b (car bs))
               (pair (if (pair? b) (lc-items b) '())))
          (unless (and (= (length pair) 2) (lc-identifier? (car pair)))
            (lc-error (string-append "let: bad binding: " (lc-show b))))
          (when (memq (car pair) seen)
            (lc-error (string-append "let: duplicate name: " (symbol->string (lc-id-symbol (car pair))))))
          (loop (cdr bs) (cons (car pair) seen) (cons pair acc))))))

;;; ---------------------------------------------------------------------------
;;; Globals: cells or environment lookups

(define (lc-global-env-node) (opal-send (opal-var "LispEnvironment") "default" (vector)))
(define (lc-cell sym) [[(smalltalk LispEnvironment) default] cellFor: sym])

(define (lc-global-read c id)
  (lc-global-read-symbol c (lc-id-symbol id)))
(define (lc-global-read-symbol c sym)
  (if (lc-uses? c "globalCells")
      (opal-send (opal-literal (lc-cell sym)) "value" (vector))
      (opal-send (lc-global-env-node) "lookup:" (vector (lc-symbol-node sym)))))

(define (lc-global-define c id node)
  (lc-global-define-symbol c (lc-define-target id) node))
(define (lc-global-define-symbol c sym node)
  (if (lc-uses? c "globalCells")
      (opal-send (opal-literal (lc-cell sym)) "define:" (vector node))
      (opal-send (lc-global-env-node) "define:value:" (vector (lc-symbol-node sym) node))))

(define (lc-global-assign c id node)
  (lc-global-assign-symbol c (lc-id-symbol id) node))
(define (lc-global-assign-symbol c sym node)
  (if (lc-uses? c "globalCells")
      (opal-send (opal-literal (lc-cell sym)) "assign:" (vector node))
      (opal-send (lc-global-env-node) "set:value:" (vector (lc-symbol-node sym) node))))

;;; ---------------------------------------------------------------------------
;;; Calls

(define (lc-with-selector head n)
  (let loop ((i 0) (s head)) (if (= i n) s (loop (+ i 1) (string-append s "with:")))))

(define (lc-call-node c fn args)                    ; args: a list of nodes
  (let ((n (length args)))
    (if (and (lc-uses? c "fastCalls") (<= n 4))
        (opal-send (opal-var "LispProcedure") (lc-with-selector "call:" n) (list->vector (cons fn args)))
        (opal-send (opal-var "LispProcedure") "apply:to:" (vector fn (lc-array-node c args))))))

(define (lc-tail-call-node c fn args)
  (let ((n (length args)))
    (if (and (lc-uses? c "fastCalls") (<= n 4))
        (opal-send (opal-var "LispProcedure") (lc-with-selector "tailCall:" n) (list->vector (cons fn args)))
        (opal-send (opal-var "LispProcedure") "tailCall:to:" (vector fn (lc-array-node c args))))))

(define (lc-self-tail-call? c op args scope)
  (let ((loop (c-self-loop c)))
    (and loop
         (eq? op (loop-name loop))
         (if (loop-local loop)
             (equal? (scope-ref scope op) (loop-local loop))
             (not (scope-has? scope op)))
         (= (length args) (vector-length (loop-params loop))))))

(define (lc-self-loop-read c)
  (let ((loop (c-self-loop c)))
    (if (loop-local loop)
        (opal-var (loop-local loop))
        ;; the procedure's own global, resolved as any name is (a library's own)
        (lc-global-read-symbol c (lc-binding (loop-name loop) (scope-new))))))

(define (lc-translate-self-tail-call c args scope)
  (let ((loop (c-self-loop c)))
    (loop-used! loop)
    (unless (loop-scratch loop)
      (loop-scratch! loop (lc-map (lambda (d) (let ((nm (lc-next-name c))) (loop-add-temp! loop nm) nm)) args)))
    (let* ((scratch (loop-scratch loop))
           (statements (lc-map2 (lambda (t d) (opal-assign t (lc-translate c d scope #f))) scratch args))
           (then-statements
            (append (lc-map2 (lambda (p t) (opal-assign p (opal-var t))) (vector->list (loop-params loop)) scratch)
                    (list (opal-assign (loop-again loop) (opal-literal #t))
                          (opal-literal (smalltalk-nil)))))
           (check (opal-send (lc-self-loop-read c) "==" (vector (opal-var (loop-proc loop)))))
           (else-node (lc-tail-call-node c (lc-self-loop-read c) (lc-map opal-var scratch))))
      (opal-send (opal-literal #t) "ifTrue:"
        (vector (opal-block (vector) (vector)
                  (list->vector
                   (append statements
                           (list (opal-send check "ifTrue:ifFalse:"
                                   (vector (opal-block (vector) (vector) (list->vector then-statements))
                                           (opal-thunk else-node))))))))))))

(define (lc-map2 f a b)
  (if (or (null? a) (null? b)) '()
      (let* ((x (f (car a) (car b))) (rest (lc-map2 f (cdr a) (cdr b)))) (cons x rest))))

(define (lc-translate-application c form scope tail)
  (let* ((items (lc-items form))
         (op (car items))
         (args (cdr items)))
    (cond ((and tail (lc-self-tail-call? c op args scope))
           (lc-translate-self-tail-call c args scope))
          ((lc-inlinable-primitive c op args scope)
           => (lambda (prim) (lc-translate-inline c prim op args scope tail)))
          (else
           (let* ((fn (lc-translate c op scope #f))
                  (arg-nodes (lc-map (lambda (d) (lc-translate c d scope #f)) args)))
             (if (and tail (lc-uses? c "tailCalls"))
                 (lc-tail-call-node c fn arg-nodes)
                 (lc-call-node c fn arg-nodes)))))))

;;; ---------------------------------------------------------------------------
;;; Guarded inlining of primitives

(define lc-unbound (list 'unbound))                 ; what valueIfUnbound: answers here

(define (lc-global-value sym)                       ; the value, or lc-unbound
  [(lc-cell sym) valueIfUnbound: (lambda () lc-unbound)])

(define (lc-inlinable-primitive c op args scope)
  (and (lc-uses? c "inlinePrimitives")
       (lc-identifier? op)
       (symbol? (lc-binding op scope))
       (let ((prim (lc-global-value (lc-binding op scope))))
         (and (not (eq? prim lc-unbound))
              [prim respondsTo: (smalltalk-symbol "inlineSpec")]
              (let ((spec [prim inlineSpec]))
                (and (not (smalltalk-nil? spec))
                     (= (vector-ref spec 0) (length args))
                     (<= (+ (c-inline-temps c) (lc-count (lambda (d) (not (lc-simple-arg? d))) args)) 12)
                     prim))))))

(define (lc-simple-arg? d)
  (or (not (pair? d)) (eq? (car d) 'quote)))

(define (lc-translate-inline c prim op args scope tail)
  (let* ((spec [prim inlineSpec])
         (temps-and-statements
          (let loop ((ds args) (temps '()) (statements '()))
            (cond ((null? ds) (cons (reverse temps) (reverse statements)))
                  ((lc-simple-arg? (car ds)) (loop (cdr ds) temps statements))
                  (else
                   (let* ((nm (lc-next-name c))
                          (st (opal-assign nm (lc-translate c (car ds) scope #f))))
                     (loop (cdr ds) (cons nm temps) (cons st statements)))))))
         (temps (car temps-and-statements))
         (statements (cdr temps-and-statements))
         (n (length args)))
    (c-inline-temps! c (+ (c-inline-temps c) (length temps)))
    (let* ((arg-node
            (lambda (i)
              (let ((d (lc-list-ref1 args i)))
                (if (lc-simple-arg? d)
                    (lc-translate c d scope #f)
                    (opal-var (lc-list-ref1 temps
                                (lc-count (lambda (k) (not (lc-simple-arg? (lc-list-ref1 args k)))) (lc-iota 1 i))))))))
           (fast (if (eq? (vector-ref spec 1) (smalltalk-symbol "identity"))
                     (opal-send (arg-node 1) "==" (vector (opal-literal (vector-ref spec 2))))
                     (let* ((receiver (arg-node 1))
                            (rest (lc-vmap arg-node (lc-iota 2 n))))
                       (opal-send receiver (vector-ref spec 2) rest))))
           (slow (if (and tail (lc-uses? c "tailCalls"))
                     (let* ((fn (lc-global-read-symbol c (lc-binding op scope)))) (lc-tail-call-node c fn (lc-map arg-node (lc-iota 1 n))))
                     (let* ((fn (lc-global-read-symbol c (lc-binding op scope)))) (lc-call-node c fn (lc-map arg-node (lc-iota 1 n))))))
           (guard0 (opal-send (lc-global-read-symbol c (lc-binding op scope)) "==" (vector (opal-literal prim))))
           (guard (opal-send guard0 "ifTrue:ifFalse:" (vector (opal-thunk fast) (opal-thunk slow)))))
      (if (null? temps)
          guard
          (opal-send (opal-literal #t) "ifTrue:"
            (vector (opal-block (vector) (lc-vmap opal-var temps)
                      (list->vector (append statements (list guard))))))))))

;;; ---------------------------------------------------------------------------
;;; Core dispatch

(define (lc-translate c datum scope tail)
  (cond ((pair? datum) (lc-translate-nested c datum scope tail))
        ((symbol? datum) (lc-translate-variable c datum scope))
        ((null? datum) (lc-empty-list-node))
        ([datum isLispAlias] (lc-translate-variable c datum scope))
        (else (opal-literal datum))))

;; Past a depth budget, a form not in tail position is compiled in a block of its
;; own, [form] value, which starts a fresh frame
(define (lc-translate-nested c form scope tail)
  (let* ((outer (c-forms c))
         (node (begin (c-forms! c (cons form outer))
                      (lc-translate-nested* c form scope tail))))
    ;; popped only on a normal return: after an error the stack still says where
    (c-forms! c outer)
    node))

(define (lc-translate-nested* c form scope tail)
  (c-expr-depth! c (+ (c-expr-depth c) 1))
  (lc-ensure
   (lambda ()
     (if (and (not tail) (> (c-expr-depth c) lc-nesting-budget))
         (let ((saved (c-expr-depth c)))
           (c-expr-depth! c 0)
           (let ((node (lc-ensure (lambda () (lc-translate-form c form scope #f))
                                  (lambda () (c-expr-depth! c saved)))))
             (opal-send (opal-block (vector) (vector) (vector node)) "value" (vector))))
         (lc-translate-form c form scope tail)))
   (lambda () (c-expr-depth! c (- (c-expr-depth c) 1)))))

(define (lc-translate-variable c id scope)
  (let ((b (lc-binding id scope)))
    (cond ((string? b) (opal-var b))
          ((or (not (symbol? b)) (lc-global-macro b))
           (lc-error (string-append "macro used as a value: " (symbol->string (lc-id-symbol id)))))
          (else (lc-global-read-symbol c b)))))

;; the operator decides, through its binding: a local variable is called even if
;; its name is a special form's (review C-14)
(define (lc-translate-form c form scope tail)
  (let* ((op (car form))
         (b (and (lc-identifier? op) (lc-binding op scope)))
         (special (and (symbol? b) (hash-table-ref/default lc-special-forms b #f))))
    (if special
        (special c form scope tail)
        (let ((m (and b (not (string? b)) (if (symbol? b) (lc-global-macro b) b))))
          (if m
              (lc-translate-macro-call c form m scope tail)
              (lc-translate-application c form scope tail))))))

;;; ---------------------------------------------------------------------------
;;; Special forms: a table from name to translator, as LispCompiler class>>specialForms

(define lc-special-forms (make-hash-table eq?))
(define (define-special-form name . rest)
  "(define-special-form name [documentation] translator)
Makes name a special form of the running compiler: translator, called with the
compiler's state, the form, the scope and whether the form is in tail position,
answers its code. The documentation is what (documentation name) answers."
  (let ((translator (if (pair? (cdr rest)) (car (cdr rest)) (car rest))))
    (when (pair? (cdr rest))
      [translator documentation: (car rest)]
      [translator category: "Special forms"])
    (hash-table-set! lc-special-forms name translator)))

(define-special-form 'quote
  "(quote datum), 'datum
The datum itself, not evaluated."
  (lambda (c form scope tail) (lc-check form 1 1) (lc-quote-node c (car (cdr form)))))
(define-special-form 'if
  "(if test then [else])
Evaluates then if test is true (anything but #f), else else."
  (lambda (c form scope tail) (lc-check form 2 3) (lc-translate-if c form scope tail)))
(define-special-form 'begin
  "(begin form ...)
Evaluates the forms in order and answers the last; at top level each is a top-level form."
  (lambda (c form scope tail) (lc-translate-begin c (lc-items (cdr form)) scope tail)))
(define-special-form 'lambda
  "(lambda params body ...)
A procedure. params is (a b), (a b . rest) or rest; a body may start with internal definitions, and with a documentation string."
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-lambda c form scope (lc-source-of c form) #f #f)))
(define-special-form 'let
  "(let ((name init) ...) body ...), (let loop ((name init) ...) body ...)
Binds each name to its init, evaluated outside the bindings; the named form also binds loop to the body as a procedure."
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-let c form scope tail)))
(define-special-form 'define
  "(define name value), (define (name . params) body ...)
Defines name, globally at top level or locally at the start of a body. A body that starts with a string keeps it as its documentation."
  (lambda (c form scope tail) (lc-check-define form) (lc-translate-define c form scope)))
(define-special-form 'set!
  "(set! name value), (set! (proc arg ...) value)
Assigns value to the variable name, local or global. With a call as its target it assigns through the setter of proc, as SRFI 17 specifies: ((setter proc) arg ... value), so (set! (car x) v) sets the first element of x and (set! (vector-ref v i) x) a slot of v."
  (lambda (c form scope tail)
    (lc-check form 2 2)
    (let ((target (car (cdr form))))
      (cond ((lc-identifier? target) (lc-translate-set c form scope))
            ((and (pair? target) (list? target)) (lc-translate-set-place c form scope))
            (else (lc-error (string-append "set!: bad name: " (lc-show target))))))))
(define-special-form 'quasiquote
  "(quasiquote template), `template
The template as data, with (unquote x) and (unquote-splicing x), written ,x and ,@x, filled in."
  (lambda (c form scope tail) (lc-check form 1 1) (lc-qq-node c (car (cdr form)) 0 scope)))
(define-special-form 'define-macro
  "(define-macro (name . params) body ...)
A macro that is not hygienic: its expander gets the operands and answers code, whose names mean what they mean where it is used."
  (lambda (c form scope tail) (lc-check form 2 #f) (lc-translate-define-macro c form scope)))
(define-special-form 'send
  "(send receiver selector arg ...), [receiver selector arg ...]
Sends a Smalltalk message; the selector is spelled as in Smalltalk (at:put:)."
  (lambda (c form scope tail) (lc-translate-send c form scope)))
(define-special-form 'smalltalk
  "(smalltalk Name)
The Smalltalk global Name, such as a class."
  (lambda (c form scope tail) (lc-translate-smalltalk-global form)))
;; hygienic macros (step 9.3); internal define-syntax is a body's (lc-translate-scoped-body)
(define-special-form 'define-syntax
  "(define-syntax name [documentation] (syntax-rules ...))
A hygienic macro, at top level or local to a body."
  (lambda (c form scope tail) (lc-check form 2 3) (lc-translate-define-syntax c form scope)))
(define-special-form 'let-syntax
  "(let-syntax ((name (syntax-rules ...)) ...) body ...)
Local macros, defined in the enclosing scope, for the body."
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-let-syntax c form scope tail #f)))
(define-special-form 'letrec-syntax
  "(letrec-syntax ((name (syntax-rules ...)) ...) body ...)
Local macros that can use each other, for the body."
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-let-syntax c form scope tail #t)))
(define-special-form 'syntax-rules
  "(syntax-rules [ellipsis] (literal ...) (pattern template) ...)
The transformer of a hygienic macro: the first pattern a use matches gives its template, filled in."
  (lambda (c form scope tail) (lc-error "syntax-rules is used only in define-syntax, let-syntax and letrec-syntax")))
(define-special-form 'syntax-error
  "(syntax-error message form ...)
Stops compilation with message and the forms, for a macro to report a misuse."
  (lambda (c form scope tail)
    (let ((parts (lc-items (cdr form))))
      (lc-error (if (and (pair? parts) (string? (car parts)))
                    (lc-join-shown (car parts) (cdr parts))
                    (lc-join-shown "syntax-error" parts))))))

;;; ---------------------------------------------------------------------------
;;; Macros

(define (lc-macro-for op scope)
  (and (lc-identifier? op)
       (let ((b (lc-binding op scope)))
         (cond ((string? b) #f)
               ((symbol? b) (lc-global-macro b))
               (else b)))))

;; (lc-expand form macro [scope [c]]): a syntax-rules macro is given the whole
;; form and the scope of its use; a define-macro one, the operands
(define (lc-expand form macro . opts)
  (let ((name (if (lc-identifier? (car form)) (symbol->string (lc-id-symbol (car form))) "?"))
        (scope (if (pair? opts) (car opts) (scope-new))))
    (when (and (pair? opts) (pair? (cdr opts)) [macro isKindOf: (smalltalk LispSyntax)])
      (c-hygienic! (car (cdr opts)) #t))
    (lc-on-error
     (lambda ()
       (if [macro isKindOf: (smalltalk LispSyntax)]
           [(smalltalk LispProcedure) apply: [macro expander] to: (vector form scope)]
           [(smalltalk LispProcedure) apply: [macro expander] to: (list->vector (lc-items (cdr form)))]))
     (lambda (e)
       (let ((text [e messageText]))
         ;; a syntax-rules macro's own errors (no match, syntax-error) say so already
         (if [e isKindOf: (smalltalk LispCompileError)]
             [e pass]
             (lc-error (string-append "error expanding " name ": "
                                      (if (or (smalltalk-nil? text) [text isEmpty])
                                          [[[e class] name] asString]
                                          text)))))))))

(define (lc-translate-macro-call c form macro scope tail)
  (c-expansion-depth! c (+ (c-expansion-depth c) 1))
  (when (> (c-expansion-depth c) lc-max-expansions)
    (c-expansion-depth! c 0)
    (lc-expansion-too-deep form))
  (let* ((expansion (lc-if-curtailed (lambda () (lc-expand form macro scope c))
                                     (lambda () (c-expansion-depth! c (- (c-expansion-depth c) 1)))))
         (text (lc-recorded-source-of c form))
         (saved-context (c-source-context c))
         (saved-top (c-top-form c)))
    (when text (c-source-context! c text))
    (when (eq? form (c-top-form c)) (c-top-form! c expansion))
    (lc-ensure (lambda () (lc-translate c expansion scope tail))
               (lambda ()
                 (c-source-context! c saved-context)
                 (c-top-form! c saved-top)
                 (c-expansion-depth! c (- (c-expansion-depth c) 1))))))

(define (lc-expansion-too-deep form)
  (lc-error (string-append "macro expansion too deep (more than " (number->string lc-max-expansions)
                           " steps): " (if (lc-identifier? (car form)) (symbol->string (lc-id-symbol (car form))) (lc-show form)))))

(define (lc-translate-define-macro c form scope)
  (unless (eq? form (c-top-form c)) (lc-error "define-macro is allowed only at top level"))
  (let ((parts (lc-items (cdr form))))
    (when (null? parts) (lc-error "define-macro needs a name"))
    (let* ((target (car parts))
           (name-sym (lc-id-symbol (if (pair? target) (car target) target)))
           (value-node
            (if (pair? target)
                (lc-translate-lambda c (lc-make-lambda (cdr target) (cdr parts)) scope (lc-source-of c form) #f #f)
                (lc-translate c (car (cdr parts)) scope #f))))
      (lc-and-unspecified
       (lc-global-define c name-sym (opal-send (opal-var "LispMacro") "expander:" (vector value-node)))))))

;; (define-syntax name (syntax-rules ...)) at top level: a global macro, made now
;; and defined when the form runs (in a body: lc-translate-scoped-body)
(define (lc-translate-define-syntax c form scope)
  (unless (eq? form (c-top-form c))
    (lc-error "define-syntax is allowed only at top level or at the start of a body"))
  (let ((name (car (cdr form)))
        (scope (lc-scope-with-unit scope)))
    (unless (lc-identifier? name) (lc-error (string-append "define-syntax: bad name: " (lc-show name))))
    (lc-and-unspecified
     (lc-global-define c name (opal-literal (lc-documented-syntax (lc-make-syntax c (lc-syntax-spec form) scope scope name (lc-source-of c form))
                                                                   form))))))

;; (define-syntax name [documentation] spec): the spec, and the documentation or #f
(define (lc-syntax-spec form)
  (let ((rest (cdr (cdr form))))
    (if (and (string? (car rest)) (pair? (cdr rest))) (car (cdr rest)) (car rest))))
(define (lc-syntax-documentation form)
  (let ((rest (cdr (cdr form))))
    (and (string? (car rest)) (pair? (cdr rest)) (car rest))))
(define (lc-documented-syntax m form)
  (let ((doc (lc-syntax-documentation form)))
    (when doc [m documentation: doc] [m category: (lc-category)])
    m))

;; (let-syntax ((name (syntax-rules ...)) ...) body ...): the macros' scope is the
;; enclosing one, or for letrec-syntax the new one, so they can use each other
(define (lc-translate-let-syntax c form scope tail rec)
  (let* ((parts (lc-items (cdr form)))
         (bindings (lc-check-bindings (car parts)))
         (child (scope-copy scope)))
    (for-each (lambda (b)
                (scope-set! child (car b) (lc-make-syntax c (car (cdr b)) scope (if rec child scope) (car b) (lc-recorded-source-of c b))))
              bindings)
    ;; the body is a body, as let's is
    (lc-translate c (cons lc-core-let (cons '() (cdr parts))) child tail)))

;; a transformer spec, (syntax-rules ...), in scope: the macro, defined in env.
;; Its expander keeps the text that defined it, as a define-macro's does.
(define (lc-make-syntax c spec scope env name text)
  (unless (and (pair? spec) (eq? (lc-special (car spec) scope) 'syntax-rules))
    (lc-error (string-append "define-syntax: " (symbol->string (lc-id-symbol name))
                             ": the transformer must be syntax-rules, not " (lc-show spec))))
  (let ((m (sr-make spec env (lc-id-symbol name))))
    (when text [[m expander] source: text])
    m))

;; message, then each argument as write shows it
(define (lc-join-shown message args)
  (let loop ((text message) (args args))
    (if (null? args) text (loop (string-append text " " (lc-show (lc-strip (car args)))) (cdr args)))))

;;; ---------------------------------------------------------------------------
;;; Quasiquote

(define (lc-tagged? datum name)                     ; isTagged:as:
  (and (pair? datum) (lc-id-is? (car datum) name) (pair? (cdr datum)) (null? (cdr (cdr datum)))))

(define (lc-qq-constant? t n)
  (cond ((vector? t) (let loop ((i 0)) (or (= i (vector-length t)) (and (lc-qq-constant? (vector-ref t i) n) (loop (+ i 1))))))
        ((not (pair? t)) #t)
        ((or (lc-tagged? t 'unquote) (lc-tagged? t 'unquote-splicing))
         (and (not (= n 0)) (lc-qq-constant? (car (cdr t)) (- n 1))))
        ((lc-tagged? t 'quasiquote) (lc-qq-constant? (car (cdr t)) (+ n 1)))
        (else (and (lc-qq-constant? (car t) n) (lc-qq-constant? (cdr t) n)))))

(define (lc-qq-tagged name node)
  (opal-send (opal-var "LispCons") "car:cdr:"
    (vector (opal-literal name)
            (opal-send (opal-var "LispCons") "car:cdr:" (vector node (lc-empty-list-node))))))

(define (lc-qq-node c t n scope)
  (cond ((lc-qq-constant? t n) (lc-quote-node c t))
        ((vector? t) (opal-send (lc-qq-node c (vector->list t) n scope) "asArray" (vector)))
        ((lc-tagged? t 'unquote)
         (if (= n 0)
             (lc-translate c (car (cdr t)) scope #f)
             (lc-qq-tagged 'unquote (lc-qq-node c (car (cdr t)) (- n 1) scope))))
        ((lc-tagged? t 'unquote-splicing)
         (if (= n 0)
             (lc-error "unquote-splicing outside a list")
             (lc-qq-tagged 'unquote-splicing (lc-qq-node c (car (cdr t)) (- n 1) scope))))
        ((lc-tagged? t 'quasiquote)
         (lc-qq-tagged 'quasiquote (lc-qq-node c (car (cdr t)) (+ n 1) scope)))
        (else (lc-qq-list-node c t n scope))))

(define (lc-level-zero-splice? d n) (and (= n 0) (lc-tagged? d 'unquote-splicing)))

(define (lc-qq-list-node c t n scope)
  (let loop ((cur t) (elements '()))
    (if (and (pair? cur)
             (not (lc-tagged? cur 'unquote))
             (not (lc-tagged? cur 'unquote-splicing))
             (not (lc-tagged? cur 'quasiquote))
             (not (lc-level-zero-splice? (car cur) n)))
        (loop (cdr cur) (cons (lc-qq-node c (car cur) n scope) elements))
        (let ((tail-node
               (if (and (pair? cur) (lc-level-zero-splice? (car cur) n))
                   (let* ((spliced (lc-translate c (car (cdr (car cur))) scope #f))
                          (rest (lc-qq-node c (cdr cur) n scope)))
                     (opal-send (opal-var "LispCons") "qqAppend:to:" (vector spliced rest)))
                   (lc-qq-node c cur n scope))))
          (if (null? elements)
              tail-node
              (let ((array (lc-array-node c (reverse elements))))
                (opal-send (opal-var "LispCons") "fromArray:tail:" (vector array tail-node))))))))

;;; ---------------------------------------------------------------------------
;;; Bodies with internal define (letrec* semantics), as translateScopedBody:

(define (lc-define-form? d scope) (and (pair? d) (eq? (lc-special (car d) scope) 'define)))
(define (lc-define-syntax-form? d scope) (and (pair? d) (eq? (lc-special (car d) scope) 'define-syntax)))

;; answers (temp-names . statement-nodes), both lists
(define (lc-translate-scoped-body c data child-scope tail)
  (let scan ((pending (lc-map (lambda (d) (cons d (c-source-context c))) data))
             (defs '())                               ; reversed: (datum context name)
             (steps 0))
    (if (or (null? pending)
            (let* ((item (car pending)) (datum (car item)))
              (and (not (and (pair? datum) (lc-macro-for (car datum) child-scope)))
                   (not (lc-define-form? datum child-scope))
                   (not (lc-define-syntax-form? datum child-scope))
                   (not (and (pair? datum) (eq? (lc-special (car datum) child-scope) 'begin))))))
        (lc-scoped-body-rest c (reverse defs) pending child-scope tail)
        (let* ((item (car pending))
               (datum (car item))
               (m (and (pair? datum) (lc-macro-for (car datum) child-scope))))
          (cond (m
                 (when (> (+ steps 1) lc-max-expansions) (lc-expansion-too-deep datum))
                 (let* ((expansion (lc-expand datum m child-scope c))
                        (context (or (lc-recorded-source-of c datum) (cdr item))))
                   (scan (cons (cons expansion context) (cdr pending)) defs (+ steps 1))))
                ((lc-define-syntax-form? datum child-scope)
                 ;; a local macro, for the whole body: its scope is the body's
                 (lc-check datum 2 3)
                 (let ((name (car (cdr datum))))
                   (unless (lc-identifier? name) (lc-error (string-append "define-syntax: bad name: " (lc-show name))))
                   (scope-set! child-scope name (lc-documented-syntax (lc-make-syntax c (lc-syntax-spec datum) child-scope child-scope name (lc-source-of c datum)) datum))
                   (scan (cdr pending) defs steps)))
                ((lc-define-form? datum child-scope)
                 (lc-check-define datum)
                 (let* ((target (car (lc-items (cdr datum))))
                        (nm (lc-next-name c)))
                   (scope-set! child-scope (if (pair? target) (car target) target) nm)
                   (scan (cdr pending) (cons (list datum (cdr item) nm) defs) steps)))
                (else                                ; a begin: splice its forms in
                 (scan (append (lc-map (lambda (d) (cons d (cdr item))) (lc-items (cdr datum))) (cdr pending))
                       defs steps)))))))

(define (lc-scoped-body-rest c defs rest child-scope tail)
  (when (lc-any? (lambda (it) (lc-define-form? (car it) child-scope)) rest)
    (lc-error "define after an expression in a body"))
  (let ((temps (lc-map (lambda (d) (lc-ref d 2)) defs))
        (inits (lc-map (lambda (d) (opal-assign (lc-ref d 2) (lc-unspecified-node))) defs))
        (saved-context (c-source-context c))
        (saved-in-body (c-in-body c)))
    (c-in-body! c #t)
    (lc-ensure
     (lambda ()
       (let* ((def-statements
               (lc-map (lambda (d)
                         (c-source-context! c (lc-ref d 1))
                         (let* ((form (lc-ref d 0))
                                (nm (lc-ref d 2))
                                (parts (lc-items (cdr form)))
                                (target (car parts)))
                           (opal-assign nm
                             (if (pair? target)
                                 (lc-named (lc-translate-lambda c (lc-make-lambda (cdr target) (cdr parts)) child-scope
                                                                (lc-source-of c form) (car target) nm)
                                           (car target))
                                 (let ((value-data (car (cdr parts))))
                                   (if (lc-lambda-form? value-data child-scope)
                                       (lc-named (lc-translate-lambda c value-data child-scope (lc-source-of c value-data) target nm)
                                                 target)
                                       (lc-translate c value-data child-scope #f)))))))
                       defs))
              (empty (if (null? rest) (list (lc-unspecified-node)) '()))
              (count (length rest))
              (rest-statements
               (let loop ((its rest) (i 1))
                 (if (null? its)
                     '()
                     (begin
                       (c-source-context! c (cdr (car its)))
                       (let* ((node (lc-translate c (car (car its)) child-scope (and tail (= i count))))
                              (more (loop (cdr its) (+ i 1))))
                         (cons node more)))))))
         (cons temps (append inits def-statements empty rest-statements))))
     (lambda () (c-source-context! c saved-context) (c-in-body! c saved-in-body)))))

(define (lc-translate-body c data scope tail)          ; statements, a list
  (if (null? data)
      (list (lc-unspecified-node))
      (let ((count (length data)))
        (let loop ((ds data) (i 1))
          (if (null? ds) '()
              (let* ((node (lc-translate c (car ds) scope (and tail (= i count))))
                     (more (loop (cdr ds) (+ i 1))))
                (cons node more)))))))

;;; ---------------------------------------------------------------------------
;;; Quote, if, begin

(define (lc-quote-node c datum0)
  (let ((datum (if (c-hygienic c) (lc-strip datum0) datum0)))
    (if (lc-uses? c "literalQuote") (opal-literal datum) (lc-reconstruct datum))))

(define (lc-reconstruct datum)
  (cond ((pair? datum)
         (let* ((a (lc-reconstruct (car datum))) (d (lc-reconstruct (cdr datum))))
           (opal-send (opal-var "LispCons") "car:cdr:" (vector a d))))
        ((symbol? datum)
         (if [(smalltalk LispSymbol) isInterned: datum] (lc-symbol-node datum) (opal-literal datum)))
        ((null? datum) (lc-empty-list-node))
        (else (opal-literal datum))))

;; With coverage on, each side of an if is counted (specs/20-coverage.md), and placed
;; at the test, which keeps its place in the source even when a macro (cond,
;; case, and, or) made the if.
(define (lc-translate-if c form scope tail)
  (let ((args (lc-items (cdr form))))
    (when (< (length args) 2) (lc-error "if needs a test and a then-branch"))
    (let* ((test-node (lc-translate c (car args) scope #f))
           (then-node (lc-translate c (car (cdr args)) scope tail))
           (else-node (if (>= (length args) 3)
                          (lc-translate c (car (cdr (cdr args))) scope tail)
                          (lc-unspecified-node)))
           (truthy (opal-send (opal-var "LispCore") "isTruthy:" (vector test-node))))
      (opal-send truthy "ifTrue:ifFalse:"
                 (vector (lc-if-branch c 'true args form then-node)
                         (lc-if-branch c 'false args form else-node))))))

;; one side of an if, probed unless the test is the constant #t or #f: then one
;; side can never run, and the if is a macro's way to an unspecified value
;; (unless, a cond with no else), not a branch of the program's
;; (specs/20-coverage.md R-12)
(define (lc-if-branch c kind args form node)
  (if (boolean? (car args))
      (opal-thunk node)
      (lc-probed-thunk c kind (list (car args) form) node)))

;;; ---------------------------------------------------------------------------
;;; Coverage (specs/20-coverage.md): with the coverage option on, each procedure
;;; entry and each side of an if counts into a record that lib/coverage.lisp's
;;; %coverage-register makes as the form is compiled. Off, nothing changes.

;; the record for a probe of kind, or #f: placed at the first of forms, then of
;; the forms being compiled, that the reader has a range for (so a macro's
;; expansion counts at the macro's use)
(define (lc-probe-record c kind forms)
  (and (lc-uses? c "coverage")
       (let* ((sm (c-source-map c))
              (source (and (vector? sm) [sm at: 1]))
              (file (let ((p [(smalltalk LispLoadPath) value])) (if (smalltalk-nil? p) #f [p asString]))))
         (let loop ((candidates (append forms (c-forms c))))
           (if (null? candidates)
               (%coverage-register kind file #f #f #f (lc-show (car forms)))
               (let ((range (and source (pair? (car candidates)) (reader-range-of sm (car candidates)))))
                 (if range
                     (%coverage-register kind file source (car range) (cdr range) #f)
                     (loop (cdr candidates)))))))))

;; the statement that counts a probe: rec[1] := rec[1] + 1
(define (lc-probe-node rec)
  (opal-send (opal-literal rec) "at:put:"
             (vector (opal-literal 1)
                     (opal-send (opal-send (opal-literal rec) "at:" (vector (opal-literal 1))) "+" (vector (opal-literal 1))))))

;; the probes to run first, as a list of statements: none, or one
(define (lc-probe-statements c kind forms)
  (let ((rec (lc-probe-record c kind forms)))
    (if rec (list (lc-probe-node rec)) '())))

;; a branch of an if, counted when it is taken
(define (lc-probed-thunk c kind forms node)
  (let ((probes (lc-probe-statements c kind forms)))
    (if (null? probes)
        (opal-thunk node)
        (opal-block (vector) (vector) (list->vector (append probes (list node)))))))

(define (lc-translate-begin c data scope tail)
  (cond ((null? data) (lc-unspecified-node))
        ((null? (cdr data)) (lc-translate c (car data) scope tail))
        (else (opal-send (opal-literal #t) "ifTrue:"
                (vector (opal-block (vector) (vector) (list->vector (lc-translate-body c data scope tail))))))))

;;; ---------------------------------------------------------------------------
;;; Lambda

;; (a b . rest), (a b) or rest: answers (fixed-list . rest-symbol-or-#f)
(define (lc-parse-params spec)
  (define (bad) (lc-error (string-append "lambda: bad parameter list: " (lc-show spec))))
  (if (lc-identifier? spec)
      (cons '() spec)
      (let loop ((cur spec) (fixed '()))
        (cond ((pair? cur)
               (unless (lc-identifier? (car cur)) (bad))
               (loop (cdr cur) (cons (car cur) fixed)))
              ((or (lc-identifier? cur) (null? cur))
               (let* ((fixed (reverse fixed))
                      (all (if (lc-identifier? cur) (append fixed (list cur)) fixed)))
                 (when (lc-duplicates? all)
                   (lc-error (string-append "lambda: duplicate parameter in " (lc-show spec))))
                 (cons fixed (if (lc-identifier? cur) cur #f))))
              (else (bad))))))

(define (lc-duplicates? l)
  (and (pair? l) (or (memq (car l) (cdr l)) (lc-duplicates? (cdr l)))))

;; Block arguments are read-only, so each LISP variable is a temporary initialized
;; from its argument. Answers (arg-nodes temp-nodes init-nodes temp-names), lists.
(define (lc-bind-params c params child-scope)
  (let loop ((ps params) (args '()) (temps '()) (inits '()) (names '()))
    (if (null? ps)
        (list (reverse args) (reverse temps) (reverse inits) (reverse names))
        (let* ((arg-nm (lc-next-name c))
               (temp-nm (lc-next-name c)))
          (scope-set! child-scope (car ps) temp-nm)
          (loop (cdr ps)
                (cons (opal-var arg-nm) args)
                (cons (opal-var temp-nm) temps)
                (cons (opal-assign temp-nm (opal-var arg-nm)) inits)
                (cons temp-nm names))))))

;; name-sym: the name this lambda is defined as, or #f; local: the temp that holds
;; it, for an internal define or named let, or #f
(define (lc-translate-lambda c form scope source-text name-sym local)
  (let* ((parts (lc-items (cdr form)))
         (parsed (lc-parse-params (car parts)))
         (fixed (car parsed))
         (rest-sym (cdr parsed))
         (all-params (if rest-sym (append fixed (list rest-sym)) fixed))
         (child-scope (scope-copy scope))
         (bound0 (lc-bind-params c all-params child-scope))
         (packed (> (length all-params) 15))
         (bound (if packed
                    (let* ((pk (lc-next-name c))
                           (names (lc-ref bound0 3)))
                      (list (list (opal-var pk))
                            (lc-ref bound0 1)
                            (lc-map (lambda (i)
                                      (opal-assign (lc-list-ref1 names i)
                                                   (opal-send (opal-var pk) "at:" (vector (opal-literal i)))))
                                    (lc-iota 1 (length names)))
                            names))
                    bound0))
         (arg-nodes (lc-ref bound 0))
         (temp-nodes (lc-ref bound 1))
         (init-nodes (lc-ref bound 2))
         (names (lc-ref bound 3))
         (tail (lc-uses? c "tailCalls"))
         (loop (and tail name-sym (not rest-sym) (not packed)
                    (let* ((proc (lc-next-name c))
                           (again (lc-next-name c))
                           (result (lc-next-name c)))
                      (make-loop name-sym local (list->vector names) proc again result))))
         (iter-names (if loop
                         (lc-map (lambda (p) (let ((q (lc-next-name c))) (scope-set! child-scope p q) q)) all-params)
                         '()))
         (iter-inits (lc-map2 (lambda (q nm) (opal-assign q (opal-var nm))) iter-names (if loop names '())))
         (saved-loop (c-self-loop c))
         (saved-inline-temps (c-inline-temps c))
         (saved-depth (c-expr-depth c)))
    (c-self-loop! c loop)
    (c-inline-temps! c 0)
    (c-expr-depth! c 0)
    (let* ((entry-probes (lc-probe-statements c 'procedure (list form)))
           (body (lc-ensure (lambda () (lc-translate-scoped-body c (cdr parts) child-scope tail))
                            (lambda ()
                              (c-self-loop! c saved-loop)
                              (c-inline-temps! c saved-inline-temps)
                              (c-expr-depth! c saved-depth))))
           (body-nodes (cdr body))
           (local-nodes (lc-map opal-var (append iter-names (car body))))
           (looping (and loop (loop-used? loop)))
           (block
            (if looping
                (let* ((again (loop-again loop))
                       (statements
                        (append init-nodes
                                entry-probes
                                (list (opal-assign again (opal-literal #t))
                                      (opal-send (opal-thunk (opal-var again)) "whileTrue:"
                                        (vector (opal-block (vector) (list->vector local-nodes)
                                                  (list->vector
                                                   (append (list (opal-assign again (opal-literal #f)))
                                                           iter-inits
                                                           (lc-all-but-last body-nodes)
                                                           (list (opal-assign (loop-result loop) (lc-last body-nodes))))))))
                                      (opal-var (loop-result loop)))))
                       (temps (append temp-nodes
                                      (lc-map opal-var (append (list again (loop-result loop)) (loop-temps loop))))))
                  (opal-block (list->vector arg-nodes) (list->vector temps) (list->vector statements)))
                (opal-block (list->vector arg-nodes)
                            (list->vector (append temp-nodes local-nodes))
                            (list->vector (append init-nodes iter-inits entry-probes body-nodes)))))
           (proc-node0 (opal-send (opal-var "LispProcedure")
                                  (if rest-sym "variadic:required:source:" "fixed:arity:source:")
                                  (vector block (opal-literal (length fixed)) (opal-literal source-text))))
           (proc-node1 (if packed (opal-send proc-node0 "packed" (vector)) proc-node0))
           (proc-node (lc-documented-node c proc-node1 (cdr parts))))
      (if (not looping)
          proc-node
          (let ((proc-name (loop-proc loop)))
            (opal-send (opal-block (vector) (vector (opal-var proc-name))
                                   (vector (opal-assign proc-name proc-node) (opal-var proc-name)))
                       "value" (vector)))))))

;; A body that starts with a string and has more after it keeps the string as the
;; procedure's documentation (Phase 10 step 10.1), with the category of the file
;; being loaded. The string is still evaluated, so the body means what it did.
(define (lc-documented-node c proc-node body)
  (if (and (pair? body) (string? (car body)) (pair? (cdr body)))
      (opal-send (opal-send proc-node "documentation:" (vector (opal-literal (car body))))
                 "category:" (vector (opal-literal (lc-category))))
      proc-node))

;; the section of the reference a definition belongs in: from the file being loaded
(define (lc-category)
  (let ((path [(smalltalk LispLoadPath) value]))
    (if (smalltalk-nil? path)
        "Definitions"
        (let ((p [[path asString] copyReplaceAll: "\\" with: "/"]))
          (cond ([p endsWith: "/lib/core.lisp"] "Derived forms")
                ([p includesSubstring: "/lib/compiler/"] "The compiler and reader")
                (else [[path asFileReference] basename]))))))

;;; ---------------------------------------------------------------------------
;;; Let

(define (lc-translate-let c form scope tail)
  (let ((parts (lc-items (cdr form))))
    (if (and (pair? parts) (lc-identifier? (car parts)))
        (lc-with-source-of c form (lambda () (lc-translate-named-let c parts scope tail)))
        (let* ((bindings (lc-check-bindings (car parts)))
               (body-data (cdr parts))
               (params (lc-map car bindings))
               (value-data (lc-map (lambda (b) (car (cdr b))) bindings)))
          (cond ((not (lc-uses? c "directLet"))
                 (lc-with-source-of c form
                   (lambda () (lc-translate c (cons (lc-make-lambda params body-data) value-data) scope tail))))
                ((> (length params) 15) (lc-translate-large-let c params value-data body-data scope tail))
                (else
                 (let* ((child-scope (scope-copy scope))
                        (bound (lc-bind-params c params child-scope))
                        (body (lc-translate-scoped-body c body-data child-scope tail))
                        (block (opal-block (list->vector (lc-ref bound 0))
                                           (list->vector (append (lc-ref bound 1) (lc-map opal-var (car body))))
                                           (list->vector (append (lc-ref bound 2) (cdr body))))))
                   (if (> (length params) 4)
                       (opal-send block "valueWithArguments:"
                                  (vector (lc-array-node c (lc-map (lambda (d) (lc-translate c d scope #f)) value-data))))
                       (opal-send block (lc-value-selector (length params))
                                  (lc-vmap (lambda (d) (lc-translate c d scope #f)) value-data))))))))))

;; translate code made up from form so that its lambdas keep form's source text
(define (lc-with-source-of c form thunk)
  (let ((text (lc-recorded-source-of c form)))
    (if (not text)
        (thunk)
        (let ((saved (c-source-context c)))
          (c-source-context! c text)
          (lc-ensure thunk (lambda () (c-source-context! c saved)))))))

(define (lc-translate-large-let c params value-data body-data scope tail)
  (let* ((names (lc-map (lambda (p) (lc-next-name c)) params))
         (assigns (lc-map2 (lambda (t d) (opal-assign t (lc-translate c d scope #f))) names value-data))
         (child-scope (scope-copy scope)))
    (lc-map2 (lambda (p t) (scope-set! child-scope p t)) params names)
    (let ((body (lc-translate-scoped-body c body-data child-scope tail)))
      (opal-send (opal-block (vector)
                             (lc-vmap opal-var (append names (car body)))
                             (list->vector (append assigns (cdr body))))
                 "value" (vector)))))

;; (let name ((v e) ...) body ...) is ((let () (define (name v ...) body ...) name) e ...)
(define (lc-translate-named-let c parts scope tail)
  (let ((name (car parts)))
    (when (< (length parts) 2)
      (lc-error (string-append "let: bad syntax: named let " (symbol->string (lc-id-symbol name)) " has no bindings")))
    (let* ((bindings (lc-check-bindings (car (cdr parts))))
           (vars (lc-map car bindings))
           (inits (lc-map (lambda (b) (car (cdr b))) bindings))
           (define-form (cons lc-core-define (cons (cons name vars) (cdr (cdr parts))))))
      (lc-translate c (cons (list lc-core-let '() define-form name) inits) scope tail))))

;;; ---------------------------------------------------------------------------
;;; Interop: send and smalltalk

;; the number of arguments of a Smalltalk selector spelled s, or #f
(define (lc-selector-arity s)
  (cond ((and (> (string-length s) 0)
              (let loop ((i 0))
                (or (= i (string-length s))
                    (and (string-index "+-*/\\<>=~@%|&?," (string-ref s i)) (loop (+ i 1))))))
         1)
        ([s matchesRegex: "[a-zA-Z_][a-zA-Z0-9_]*"] 0)
        ([s matchesRegex: "([a-zA-Z_][a-zA-Z0-9_]*\\:)+"] [s occurrencesOf: #\:])
        (else #f)))

;; the messages Opal compiles inline instead of sending (LispCompiler class>>inlinedSelectors)
(define lc-inlined-selectors
  '("ifTrue:" "ifFalse:" "ifTrue:ifFalse:" "ifFalse:ifTrue:" "and:" "or:" "and:and:" "or:or:"
    "whileTrue:" "whileFalse:" "whileTrue" "whileFalse" "to:do:" "to:by:do:" "timesRepeat:" "repeat"
    "ifNil:" "ifNotNil:" "ifNil:ifNotNil:" "ifNotNil:ifNil:"
    "ifEmpty:" "ifNotEmpty:" "ifEmpty:ifNotEmpty:" "ifNotEmpty:ifEmpty:"))

(define (lc-translate-send c form scope)
  (lc-check form 2 #f)
  (let* ((parts (lc-items (cdr form)))
         (sel (car (cdr parts))))
    (unless (lc-identifier? sel) (lc-error (string-append "send: bad selector: " (lc-show sel))))
    (let* ((name (symbol->string (lc-id-symbol sel)))
           (arity (lc-selector-arity name))
           (args (cdr (cdr parts))))
      (unless arity (lc-error (string-append "send: not a Smalltalk selector: " name)))
      (unless (= (length args) arity)
        (lc-error (string-append "send: " name " takes " (number->string arity)
                                 (if (= arity 1) " argument" " arguments")
                                 ", got " (number->string (length args)))))
      (if (member name lc-inlined-selectors)
          (let* ((receiver (lc-translate c (car parts) scope #f))
                 (arg-nodes (lc-map (lambda (d) (lc-translate c d scope #f)) args)))
            (opal-send receiver "perform:withArguments:"
                       (vector (opal-literal (smalltalk-symbol name)) (lc-array-node c arg-nodes))))
          (let* ((receiver (lc-translate c (car parts) scope #f))
                 (arg-nodes (lc-vmap (lambda (d) (lc-translate c d scope #f)) args)))
            (opal-send receiver name arg-nodes))))))

(define (lc-translate-smalltalk-global form)
  (lc-check form 1 1)
  (let ((name (lc-id-symbol (car (cdr form)))))
    (unless (symbol? name) (lc-error (string-append "smalltalk: bad name: " (lc-show name))))
    (unless [[(smalltalk Smalltalk) globals] includesKey: (smalltalk-symbol (symbol->string name))]
      (lc-error (string-append "smalltalk: no Smalltalk global named " (symbol->string name))))
    (opal-var (symbol->string name))))

;;; ---------------------------------------------------------------------------
;;; Define and set!

(define (lc-lambda-form? d scope) (and (pair? d) (eq? (lc-special (car d) scope) 'lambda)))

(define (lc-translate-define c form scope)
  (when (eq? (c-in-body c) #t)
    (lc-error "define is allowed only at top level or at the start of a body"))
  (let* ((parts (lc-items (cdr form)))
         (target (car parts)))
    (if (pair? target)
        (let* ((name-sym (car target))
               (value-node (lc-named (lc-translate-lambda c (lc-make-lambda (cdr target) (cdr parts)) scope
                                                          (lc-source-of c form) name-sym #f)
                                     name-sym)))
          (lc-and-unspecified (lc-global-define c name-sym value-node)))
        (let* ((value-data (car (cdr parts)))
               (value-node (if (lc-lambda-form? value-data scope)
                               (lc-named (lc-translate-lambda c value-data scope (lc-source-of c value-data) target #f) target)
                               (lc-translate c value-data scope #f))))
          (lc-and-unspecified (lc-global-define c target value-node))))))

;; the procedure knows its name
(define (lc-named proc-node sym)
  (opal-send proc-node "named:" (vector (opal-literal (symbol->string (lc-id-symbol sym))))))

(define (lc-make-lambda params body) (cons lc-core-lambda (cons params body)))

(define (lc-translate-set c form scope)
  (let* ((parts (lc-items (cdr form)))
         (sym (car parts))
         (value-node (lc-translate c (car (cdr parts)) scope #f))
         (b (lc-binding sym scope)))
    (cond ((string? b) (lc-and-unspecified (opal-assign b value-node)))
          ((symbol? b) (lc-and-unspecified (lc-global-assign-symbol c b value-node)))
          (else (lc-error (string-append "set!: not a variable: " (symbol->string (lc-id-symbol sym))))))))

;; (set! (proc arg ...) value): ((setter proc) arg ... value), SRFI 17 (Phase 9
;; step 9.4). The setter is the global one, read from its cell, so a local named
;; setter cannot capture it; proc, the arguments and the value are evaluated in
;; order, in the scope of the set!.
;;
;; The shortcut (step 9.4b; bench/results.md measured (setter car) at 20x the
;; cost of set-car!): when the getter is a global name whose value, as this form
;; is compiled, is a built-in getter (lib/core.lisp's %builtin-setters), the
;; setter is chosen by an identity test instead of a lookup:
;;   [car == <the built-in car>] ifTrue: [<set-car!>] ifFalse: [(setter car)]
;; A program that redefines car still reaches its own setter, and the built-in
;; getters' setters cannot be changed, so the test is all that is needed.

;; the built-in getter object head names here, or #f
(define (lc-builtin-getter head scope)
  (let ((b (and (lc-identifier? head) (lc-binding head scope))))
    (and (symbol? b)
         (let ((table (lc-cell '%builtin-setters)) (cell (lc-cell b)))
           (and [table isBound] [cell isBound]
                (let ((v [cell value]))
                  (and (hash-table-contains? [table value] v) v)))))))

(define (lc-setter-node c head scope)
  (let ((builtin (lc-builtin-getter head scope)))
    (if builtin
        (let ((current (lc-global-read-symbol c (lc-binding head scope))))
          (opal-send (opal-send current "==" (vector (opal-literal builtin)))
                     "ifTrue:ifFalse:"
                     (vector (opal-thunk (opal-literal (hash-table-ref [(lc-cell '%builtin-setters) value] builtin)))
                             (opal-thunk (lc-call-node c (lc-global-read-symbol c 'setter)
                                                       (list (lc-global-read-symbol c (lc-binding head scope))))))))
        (lc-call-node c (lc-global-read-symbol c 'setter) (list (lc-translate c head scope #f))))))

(define (lc-translate-set-place c form scope)
  (let* ((target (car (cdr form)))
         (setter-node (lc-setter-node c (car target) scope))
         (arg-nodes (lc-map (lambda (a) (lc-translate c a scope #f)) (cdr target)))
         (value-node (lc-translate c (car (cdr (cdr form))) scope #f)))
    (lc-and-unspecified (lc-call-node c setter-node (append arg-nodes (list value-node))))))

;;; ---------------------------------------------------------------------------
;;; Entry points

;; compile:context: -- a top-level form, not in tail position
(define (lc-compile c datum text)
  (c-counter! c 0)
  (c-self-loop! c #f)
  (c-top-form! c datum)
  (c-source-context! c text)
  (c-in-body! c #f)
  (c-inline-temps! c 0)
  (c-expansion-depth! c 0)
  (c-forms! c '())
  (let* ((expr-node
          ;; a host error while translating is malformed input the checks did not catch
          (lc-on-error (lambda () (lc-translate c datum (scope-new) #f))
                       (lambda (e)
                         (if [e isKindOf: (smalltalk LispCompileError)]
                             (begin (lc-note-forms e (c-forms c) datum) [e pass])
                             (lc-error-at-forms (string-append "bad syntax: " (lc-show datum)) (c-forms c) datum)))))
         (method (opal-method-node expr-node)))
    (lc-on-error (lambda () (opal-generate method))
                 (lambda (e) (lc-error-at-forms (string-append (lc-describe-back-end-error e) ": " (lc-show datum))
                                                '() datum)))))

;; a compile error knows the forms it happened in, innermost first, ending with
;; the top-level form (review C-18); the innermost record wins
(define (lc-note-forms e forms datum)
  (when (smalltalk-nil? [e forms])
    [e forms: (lc-forms-to-top forms datum)]))
(define (lc-forms-to-top forms datum)
  (if (and (pair? forms) (eq? (lc-last forms) datum)) forms (append forms (list datum))))
(define (lc-error-at-forms msg forms datum)
  (let ((e [(smalltalk LispCompileError) new]))
    [e forms: (lc-forms-to-top forms datum)]
    [e signal: msg]))

(define (lc-describe-back-end-error e)
  (let ((text (let ((t [e messageText])) (if (smalltalk-nil? t) "" t))))
    (cond ((or [text includesSubstring: "too deep"] [text includesSubstring: "out of range"])
           "too large or too deeply nested to compile")
          ([text includesSubstring: "Too many arguments"]
           "too many parameters or let bindings (at most 15)")
          (else (string-append "cannot compile (" [[[e class] name] asString] " " text ")")))))

;; eval:context:steps: -- the forms of a top-level begin and the expansion of a
;; top-level macro call are themselves top-level forms
(define (lc-eval c datum text n)
  (when (> n lc-max-expansions) (lc-expansion-too-deep datum))
  (if (and (pair? datum) (eq? (lc-special (car datum) (scope-new)) 'begin))
      (let loop ((forms (lc-items (cdr datum))) (result (if #f #f)))
        (if (null? forms) result (loop (cdr forms) (lc-eval c (car forms) text n))))
      (let ((m (and (pair? datum) (lc-macro-for (car datum) (scope-new)))))
        (if m
            (lc-eval c (lc-expand datum m (scope-new) c) (or (lc-recorded-source-of c datum) text) (+ n 1))
            (opal-run (lc-compile c datum text))))))

;;; The interface

;; (compile-form datum [source-map [context]]): a CompiledMethod, as compile:
;; source-map is a reader (LISP or Smalltalk) that read datum, or #f
(define (compile-form datum . options)
  "(compile-form datum [reader [context]])
The Smalltalk CompiledMethod that runs datum, made by the compiler in use. reader is the LISP reader that read datum, so its procedures keep their text."
  (let ((c (make-lisp-compiler)))
    (when (pair? options) (c-source-map! c (car options)))
    (lc-compile c datum (if (and (pair? options) (pair? (cdr options))) (car (cdr options)) #f))))

(define (lisp-eval datum . source-map)
  "(lisp-eval datum [reader])
Compiles and runs datum with the compiler in use, as eval does."
  (let ((c (make-lisp-compiler)))
    (when (pair? source-map) (c-source-map! c (car source-map)))
    (lc-eval c datum #f 0)))

;; lc-check-top: what eval does with a top-level form, short of running it, for the
;; language server's diagnostics. The forms of a top-level begin and the
;; expansion of a top-level macro call are top-level forms, as in lc-eval, so
;; cl's defmacro (a begin around a define-macro) is one; each is compiled, and
;; only a define-macro or define-syntax runs, so the forms after it can use it.
(define (lc-check-top c datum text n)
  (when (> n lc-max-expansions) (lc-expansion-too-deep datum))
  (if (and (pair? datum) (eq? (lc-special (car datum) (scope-new)) 'begin))
      (let loop ((forms (lc-items (cdr datum))))
        (if (pair? forms) (begin (lc-check-top c (car forms) text n) (loop (cdr forms)))))
      (let ((m (and (pair? datum) (lc-macro-for (car datum) (scope-new)))))
        (if m
            (lc-check-top c (lc-expand datum m (scope-new) c) (or (lc-recorded-source-of c datum) text) (+ n 1))
            (let ((method (lc-compile c datum text))
                  (head (and (pair? datum) (lc-special (car datum) (scope-new)))))
              (if (or (eq? head 'define-macro) (eq? head 'define-syntax)) (opal-run method))
              method)))))

(define (lisp-check datum . source-map)
  "(lisp-check datum [reader])
Compiles datum as eval would, signalling the error eval would, but runs only the macro definitions in it (define-macro, define-syntax, also inside a top-level begin or a macro's expansion), so the forms after it can use them. For checking a file without running it."
  (let ((c (make-lisp-compiler)))
    (when (pair? source-map) (c-source-map! c (car source-map)))
    (lc-check-top c datum #f 0)
    #t))

;; What LispCompiler>>compile:context: and eval:context:steps: call (step 8.5; the
;; entry points in LispCompiler entries): map is a reader or #f, text a string or #f.
(define (lisp-compile-from datum map text)
  (let ((c (make-lisp-compiler)))
    (c-source-map! c map)
    (lc-compile c datum text)))

(define (lisp-eval-from datum map text steps)
  (let ((c (make-lisp-compiler)))
    (c-source-map! c map)
    (lc-eval c datum text steps)))

;; What the primitives macroexpand-1 and macroexpand call (step 9.1; until then
;; they used the Smalltalk compiler's): expand a call of a global macro once, or
;; until the form is no longer one. They are for reading an expansion, so the
;; answer is plain data: a syntax-rules expansion's aliases become their symbols
;; (step 9.3), which drops what hygiene would have kept apart.
(define (lisp-macroexpand-1 form)
  (lc-strip (lc-macroexpand-1 form)))

(define (lc-macroexpand-1 form)
  (let ((m (and (pair? form) (lc-macro-for (car form) (scope-new)))))
    (if m (lc-expand form m (scope-new)) form)))

(define (lisp-macroexpand form)
  (let loop ((current form) (steps 1))
    (let ((next (lc-macroexpand-1 current)))
      (cond ((eq? next current) (lc-strip current))
            ((> steps lc-max-expansions) (lc-expansion-too-deep form))
            (else (loop next (+ steps 1)))))))

;;; Documentation (Phase 10 step 10.1)

;; what holds name's documentation: its special form, else the value of what the
;; name means here (an import, specs/27-namespaces.md R-14), or #f
(define (lc-documented name)
  (or (hash-table-ref/default lc-special-forms name #f)
      (let ((v (lc-global-value (lc-resolve-global name (lc-current-unit)))))
        (if (eq? v lc-unbound) #f v))))

(define (documentation name)
  "(documentation name)
The documentation of what the symbol name means: a special form, a macro or a
procedure; #f if it has none. Its first line is the call form."
  (let ((holder (lc-documented name)))
    (and holder (let ((d [holder lispDocumentation])) (if (smalltalk-nil? d) #f d)))))

(define (documentation-category name)
  "(documentation-category name)
The section of the reference of the built-ins that name belongs in, or #f."
  (let ((holder (lc-documented name)))
    (and holder (let ((d [holder lispCategory])) (if (smalltalk-nil? d) #f d)))))

(define (special-form-names)
  "(special-form-names)
The names of the special forms, sorted."
  (map string->symbol
       (vector->list [[[(list->vector (map symbol->string (hash-table-keys lc-special-forms))) asSortedCollection] asArray] copy])))

;; every datum of a string, read by the LISP reader so procedures keep their text
(define (lisp-eval-string s)
  "(lisp-eval-string string)
Reads and evaluates every datum of string in turn, so procedures keep their text; answers the last value."
  (let ((r (make-reader s)))
    (let loop ((result (if #f #f)))
      (let ((d (reader-next r)))
        (if (eof-object? d) result (loop (lisp-eval d r)))))))
