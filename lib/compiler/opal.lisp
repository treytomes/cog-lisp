;;; opal.lisp -- building Opal's Smalltalk AST from cog-lisp
;;; (specs/phase-8-self-hosting.md section 3: the LISP-level interface to the Opal IR)
;;;
;;; The node-building helpers of LispCompiler (src/coglisp-compiler.st), over
;;; Phase 7.6 interop. Collections of nodes are vectors (Smalltalk Arrays), as Opal
;;; expects; selectors are strings or Smalltalk symbols.
;;;
;;;   (opal-send (opal-literal 3) "+" (vector (opal-literal 4)))   ; 3 + 4
;;;   (opal-method (opal-send ...))   -> a CompiledMethod: doIt ^ <expression>

(define (opal-literal x) [(smalltalk OCLiteralValueNode) value: x])
(define (opal-var name) [(smalltalk OCVariableNode) named: name])
(define (opal-assign name node) [(smalltalk OCAssignmentNode) variable: (opal-var name) value: node])

;; Message nodes are made by splicing a parsed skeleton, because Opal's
;; OCMessageNode constructors fail (CLAUDE.md). Each selector's skeleton is parsed
;; once and copied.
(define opal-templates [(smalltalk IdentityDictionary) new])

(define (opal-template-for sel)
  (cond ([sel isUnary] (string-append "0 " [sel asString]))
        ([sel isBinary] (string-append "0 " [sel asString] " 0"))
        (else
         (let loop ((kws (vector->list [sel keywords])) (acc "0"))
           (if (null? kws)
               acc
               (loop (cdr kws) (string-append acc " " [(car kws) asString] " 0")))))))

(define (opal-send receiver selector args)
  (let* ((sel [selector asSymbol])
         (m [[opal-templates at: sel
                ifAbsentPut: (lambda () [(smalltalk OCParser) parseExpression: (opal-template-for sel)])]
             copy]))
    [m receiver: receiver]
    [m arguments: args]
    m))

;; [:a ... | | t ... | s1. s2. ...]
(define (opal-block args temps statements)
  [(smalltalk OCBlockNode) arguments: args
     body: [(smalltalk OCSequenceNode) temporaries: temps statements: statements]])

;; [node], a block of one statement and no temporaries
(define (opal-thunk node)
  [(smalltalk OCBlockNode) arguments: (vector)
     body: [(smalltalk OCSequenceNode) statements: (vector node)]])

;; {e1. e2. ...}
(define (opal-brace elements)
  (let ((n [(smalltalk OCParser) parseExpression: "{0}"]))
    [n statements: elements]
    n))

;; doIt ^ node, compiled
(define (opal-method-node node)
  [(smalltalk OCMethodNode) selector: (smalltalk-symbol "doIt") arguments: (vector)
     body: [(smalltalk OCSequenceNode) statements: (vector [(smalltalk OCReturnNode) value: node])]])

(define (opal-generate method-node)
  [method-node doSemanticAnalysis]
  [method-node generateMethod])

;; Run a compiled doIt.
(define (opal-run method) [method valueWithReceiver: (smalltalk-nil) arguments: (vector)])
