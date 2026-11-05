;;; compiler.lisp -- cog-lisp's compiler, written in cog-lisp
;;; (specs/phase-8-self-hosting.md step 8.3)
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
  (vector 0 #f [[(smalltalk LispCompiler) defaultOptions] copy] #f 0 #f #f #f 0 0 #f))

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

;;; Identifiers (specs/phase-9-language.md step 9.3): a symbol, or an alias that a
;;; syntax-rules expansion made. A scope maps an identifier to its binding: a temp
;;; name (a string) or a local macro.

(define (lc-identifier? x) (or (symbol? x) [x isLispAlias]))

;; the symbol an identifier is spelled with
(define (lc-id-symbol x) (if (symbol? x) x [x baseName]))

;; is x the identifier spelled name? (for keywords that are not bindings)
(define (lc-id-is? x name) (or (eq? x name) (and [x isLispAlias] (eq? [x baseName] name))))

;; what id means in scope: a temp name (a string), a local macro, or the symbol of
;; a global (a special form, a global macro or a variable). An alias not bound
;; here means what its name means where its macro was defined.
(define (lc-binding id scope)
  (let ((b (scope-ref scope id)))
    (cond (b b)
          ((symbol? id) id)
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
  (lc-global-define-symbol c (lc-id-symbol id) node))
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
        (lc-global-read c (loop-name loop)))))

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
                     (let* ((fn (lc-global-read c op))) (lc-tail-call-node c fn (lc-map arg-node (lc-iota 1 n))))
                     (let* ((fn (lc-global-read c op))) (lc-call-node c fn (lc-map arg-node (lc-iota 1 n))))))
           (guard0 (opal-send (lc-global-read c op) "==" (vector (opal-literal prim))))
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
(define (define-special-form name translator) (hash-table-set! lc-special-forms name translator))

(define-special-form 'quote
  (lambda (c form scope tail) (lc-check form 1 1) (lc-quote-node c (car (cdr form)))))
(define-special-form 'if
  (lambda (c form scope tail) (lc-check form 2 3) (lc-translate-if c form scope tail)))
(define-special-form 'begin
  (lambda (c form scope tail) (lc-translate-begin c (lc-items (cdr form)) scope tail)))
(define-special-form 'lambda
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-lambda c form scope (lc-source-of c form) #f #f)))
(define-special-form 'let
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-let c form scope tail)))
(define-special-form 'define
  (lambda (c form scope tail) (lc-check-define form) (lc-translate-define c form scope)))
(define-special-form 'set!
  (lambda (c form scope tail)
    (lc-check form 2 2)
    (unless (lc-identifier? (car (cdr form)))
      (lc-error (string-append "set!: bad name: " (lc-show (car (cdr form))))))
    (lc-translate-set c form scope)))
(define-special-form 'quasiquote
  (lambda (c form scope tail) (lc-check form 1 1) (lc-qq-node c (car (cdr form)) 0 scope)))
(define-special-form 'define-macro
  (lambda (c form scope tail) (lc-check form 2 #f) (lc-translate-define-macro c form scope)))
(define-special-form 'send
  (lambda (c form scope tail) (lc-translate-send c form scope)))
(define-special-form 'smalltalk
  (lambda (c form scope tail) (lc-translate-smalltalk-global form)))
;; hygienic macros (step 9.3); internal define-syntax is a body's (lc-translate-scoped-body)
(define-special-form 'define-syntax
  (lambda (c form scope tail) (lc-check form 2 2) (lc-translate-define-syntax c form scope)))
(define-special-form 'let-syntax
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-let-syntax c form scope tail #f)))
(define-special-form 'letrec-syntax
  (lambda (c form scope tail) (lc-check form 1 #f) (lc-translate-let-syntax c form scope tail #t)))
(define-special-form 'syntax-rules
  (lambda (c form scope tail) (lc-error "syntax-rules is used only in define-syntax, let-syntax and letrec-syntax")))
(define-special-form 'syntax-error
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
  (let ((name (car (cdr form))))
    (unless (lc-identifier? name) (lc-error (string-append "define-syntax: bad name: " (lc-show name))))
    (lc-and-unspecified
     (lc-global-define c name (opal-literal (lc-make-syntax c (car (cdr (cdr form))) scope scope name (lc-source-of c form)))))))

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
                 (lc-check datum 2 2)
                 (let ((name (car (cdr datum))))
                   (unless (lc-identifier? name) (lc-error (string-append "define-syntax: bad name: " (lc-show name))))
                   (scope-set! child-scope name (lc-make-syntax c (car (cdr (cdr datum))) child-scope child-scope name (lc-source-of c datum)))
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

(define (lc-translate-if c form scope tail)
  (let ((args (lc-items (cdr form))))
    (when (< (length args) 2) (lc-error "if needs a test and a then-branch"))
    (let* ((test-node (lc-translate c (car args) scope #f))
           (then-node (lc-translate c (car (cdr args)) scope tail))
           (else-node (if (>= (length args) 3)
                          (lc-translate c (car (cdr (cdr args))) scope tail)
                          (lc-unspecified-node)))
           (truthy (opal-send (opal-var "LispCore") "isTruthy:" (vector test-node))))
      (opal-send truthy "ifTrue:ifFalse:" (vector (opal-thunk then-node) (opal-thunk else-node))))))

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
    (let* ((body (lc-ensure (lambda () (lc-translate-scoped-body c (cdr parts) child-scope tail))
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
                            (list->vector (append init-nodes iter-inits body-nodes)))))
           (proc-node0 (opal-send (opal-var "LispProcedure")
                                  (if rest-sym "variadic:required:source:" "fixed:arity:source:")
                                  (vector block (opal-literal (length fixed)) (opal-literal source-text))))
           (proc-node (if packed (opal-send proc-node0 "packed" (vector)) proc-node0)))
      (if (not looping)
          proc-node
          (let ((proc-name (loop-proc loop)))
            (opal-send (opal-block (vector) (vector (opal-var proc-name))
                                   (vector (opal-assign proc-name proc-node) (opal-var proc-name)))
                       "value" (vector)))))))

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
  (let* ((expr-node
          ;; a host error while translating is malformed input the checks did not catch
          (lc-on-error (lambda () (lc-translate c datum (scope-new) #f))
                       (lambda (e)
                         (if [e isKindOf: (smalltalk LispCompileError)]
                             [e pass]
                             (lc-error (string-append "bad syntax: " (lc-show datum)))))))
         (method (opal-method-node expr-node)))
    (lc-on-error (lambda () (opal-generate method))
                 (lambda (e) (lc-error (string-append (lc-describe-back-end-error e) ": " (lc-show datum)))))))

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
  (let ((c (make-lisp-compiler)))
    (when (pair? options) (c-source-map! c (car options)))
    (lc-compile c datum (if (and (pair? options) (pair? (cdr options))) (car (cdr options)) #f))))

(define (lisp-eval datum . source-map)
  (let ((c (make-lisp-compiler)))
    (when (pair? source-map) (c-source-map! c (car source-map)))
    (lc-eval c datum #f 0)))

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

;; every datum of a string, read by the LISP reader so procedures keep their text
(define (lisp-eval-string s)
  (let ((r (make-reader s)))
    (let loop ((result (if #f #f)))
      (let ((d (reader-next r)))
        (if (eof-object? d) result (loop (lisp-eval d r)))))))
