;;; opal.lisp -- the nodes the compiler builds, and the two ways to compile them
;;; (specs/phase-8-self-hosting.md steps 8.3 and 8.6)
;;;
;;; The translator (compiler.lisp) describes each form as a small Smalltalk-shaped
;;; tree, built here as light LISP vectors rather than Opal's AST:
;;;
;;;   #(lit x)  #(var name)  #(assign name node)  #(send receiver selector args)
;;;   #(block args temps statements)  #(brace elements)  #(method node)
;;;
;;; (selectors are Smalltalk symbols; args, temps, statements and elements are
;;; vectors; args and temps hold names). opal-generate compiles a method tree:
;;;
;;;   direct  lib/compiler/codegen.lisp emits bytecode itself (the default, 8.6)
;;;   opal    the tree becomes Opal's AST, which Opal compiles, as in 8.3: the
;;;           same bytes as the Smalltalk compiler (tests/phase-8.3-compiler.st)
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

;; Which code generator opal-generate uses: a box, so that it can be changed in a
;; sealed compiler (set-code-generator! 'opal or 'direct).
(define opal-settings (vector 'direct))
(define (code-generator) (vector-ref opal-settings 0))
(define (set-code-generator! which) (vector-set! opal-settings 0 which))

(define (opal-generate method-node)
  (if (eq? (vector-ref opal-settings 0) 'direct)
      (codegen-method method-node)
      (let ((m (opal-ast method-node)))
        [m doSemanticAnalysis]
        [m generateMethod])))

;; Run a compiled doIt.
(define (opal-run method) [method valueWithReceiver: (smalltalk-nil) arguments: (vector)])

;;; ---------------------------------------------------------------------------
;;; The Opal AST of a tree: exactly the nodes the 8.3 compiler built.
;;; Message nodes are made by splicing a parsed skeleton, because Opal's
;;; OCMessageNode constructors fail (CLAUDE.md); each skeleton is parsed once.

(define opal-templates [(smalltalk IdentityDictionary) new])

(define (opal-template-for sel)
  (cond ([sel isUnary] (string-append "0 " [sel asString]))
        ([sel isBinary] (string-append "0 " [sel asString] " 0"))
        (else
         (let loop ((kws (vector->list [sel keywords])) (acc "0"))
           (if (null? kws)
               acc
               (loop (cdr kws) (string-append acc " " [(car kws) asString] " 0")))))))

(define (opal-ast-var name) [(smalltalk OCVariableNode) named: name])

(define (opal-ast n)
  (let ((tag (vector-ref n 0)))
    (cond ((eq? tag 'lit) [(smalltalk OCLiteralValueNode) value: (vector-ref n 1)])
          ((eq? tag 'var) (opal-ast-var (vector-ref n 1)))
          ((eq? tag 'assign)
           (let ((value (opal-ast (vector-ref n 2))))
             [(smalltalk OCAssignmentNode) variable: (opal-ast-var (vector-ref n 1)) value: value]))
          ((eq? tag 'send)
           (let* ((sel (vector-ref n 2))
                  (receiver (opal-ast (vector-ref n 1)))
                  (args (vector-map opal-ast (vector-ref n 3)))
                  (m [[opal-templates at: sel
                         ifAbsentPut: (lambda () [(smalltalk OCParser) parseExpression: (opal-template-for sel)])]
                      copy]))
             [m receiver: receiver]
             [m arguments: args]
             m))
          ((eq? tag 'block)
           (let ((args (vector-map opal-ast-var (vector-ref n 1)))
                 (temps (vector-map opal-ast-var (vector-ref n 2)))
                 (statements (vector-map opal-ast (vector-ref n 3))))
             ;; a thunk was made with statements: alone, as in 8.3
             (if (and (= (vector-length args) 0) (= (vector-length temps) 0) (= (vector-length statements) 1))
                 [(smalltalk OCBlockNode) arguments: args body: [(smalltalk OCSequenceNode) statements: statements]]
                 [(smalltalk OCBlockNode) arguments: args
                    body: [(smalltalk OCSequenceNode) temporaries: temps statements: statements]])))
          ((eq? tag 'brace)
           (let ((elements (vector-map opal-ast (vector-ref n 1)))
                 (b [(smalltalk OCParser) parseExpression: "{0}"]))
             [b statements: elements]
             b))
          ((eq? tag 'method)
           [(smalltalk OCMethodNode) selector: (smalltalk-symbol "doIt") arguments: (vector)
              body: [(smalltalk OCSequenceNode) statements: (vector [(smalltalk OCReturnNode) value: (opal-ast (vector-ref n 1))])]])
          (else (error "opal-ast: not a node" n)))))
