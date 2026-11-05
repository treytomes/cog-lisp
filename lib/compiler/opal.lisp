;;; opal.lisp -- the nodes the compiler builds, and how they are compiled
;;; (specs/phase-8-self-hosting.md steps 8.3 and 8.6; specs/phase-9-language.md 9.1)
;;;
;;; The translator (compiler.lisp) describes each form as a small Smalltalk-shaped
;;; tree, built here as light LISP vectors rather than Opal's AST:
;;;
;;;   #(lit x)  #(var name)  #(assign name node)  #(send receiver selector args)
;;;   #(block args temps statements)  #(brace elements)  #(method node)
;;;
;;; (selectors are Smalltalk symbols; args, temps, statements and elements are
;;; vectors; args and temps hold names). opal-generate compiles a method tree:
;;; lib/compiler/codegen.lisp emits its bytecode (8.6). The name is history: until
;;; step 9.1 a second generator turned the tree into Opal's AST, which compiled to
;;; the same bytes as the Smalltalk compiler; that check has done its work and
;;; retired with the Smalltalk compiler.
;;;
;;;   (opal-send (opal-literal 3) "+" (vector (opal-literal 4)))   ; 3 + 4
;;;   (opal-generate (opal-method-node ...))   -> a CompiledMethod: doIt ^ <expression>

(define (opal-literal x) (vector 'lit x))
(define (opal-var name) (vector 'var name))
(define (opal-assign name node) (vector 'assign name node))
;; selectors are cached by the selector string itself (the translator's are
;; literal strings), so a selector is interned once, not per node
(define opal-selectors [(smalltalk IdentityDictionary) new])
(define (opal-send receiver selector args)
  (vector 'send receiver
          [opal-selectors at: selector ifAbsent: (lambda () [opal-selectors at: selector put: [selector asSymbol]])]
          args))

;; [:a ... | | t ... | s1. s2. ...] -- args and temps given as var nodes
(define (opal-block args temps statements)
  (vector 'block (vector-map opal-node-name args) (vector-map opal-node-name temps) statements))
(define (opal-node-name n) (vector-ref n 1))

;; [node], a block of one statement and no temporaries
(define (opal-thunk node) (vector 'block (vector) (vector) (vector node)))

;; {e1. e2. ...}
(define (opal-brace elements) (vector 'brace elements))

;; doIt ^ node
(define (opal-method-node node) (vector 'method node))

(define (opal-generate method-node) (codegen-method method-node))

;; Run a compiled doIt.
(define (opal-run method) [method valueWithReceiver: (smalltalk-nil) arguments: (vector)])
