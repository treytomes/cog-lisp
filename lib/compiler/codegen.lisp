;;; codegen.lisp -- bytecode straight from the compiler's trees
;;; (specs/13-phase-8-self-hosting.md step 8.6)
;;;
;;; Compiles a method tree of opal.lisp (#(method node)) to a CompiledMethod
;;; without Opal: no AST, no semantic analysis, no IR. It does Opal's work for the
;;; trees the translator builds, and writes the bytes with Pharo's own encoder
;;; (EncoderForSistaV1), so the encoding is Pharo's.
;;;
;;;   1. Analysis, in evaluation order. A frame is the method or a block that is a
;;;      real closure; the blocks of ifTrue:, ifTrue:ifFalse: and whileTrue: are
;;;      inlined into their frame, as Opal inlines them. A variable another frame
;;;      reads is copied into that frame's closure when made; one that is written
;;;      after a closure has captured it, or written by another frame, lives in a
;;;      temp vector instead, made when its scope is entered (so a loop's body has
;;;      a fresh one each time round). Temporary names are unique in a compile
;;;      (l1, l2, ...), so a name is one variable; any other name is a Smalltalk
;;;      global.
;;;   2. Layout: a frame's slots are its arguments, then what it copies, then its
;;;      temporaries and temp vectors.
;;;   3. Emission. Each branch of a conditional or loop is emitted on its own
;;;      first, so that every jump's distance is known when it is written.
;;;
;;; Two things Opal does not do: (LispCore isTruthy: x) ifTrue: ... tests x == false
;;; inline, and true ifTrue: [...] (how the translator sequences statements) is
;;; just its statements. A block that captures nothing is made once, at compile
;;; time, as Opal does (a CleanBlockClosure, or a ConstantBlockClosure when it
;;; only answers a literal).

;;; ---------------------------------------------------------------------------
;;; Records

;; Every record and node is a vector (an Array): read and written with at: and
;; at:put: sends, which the VM runs as primitives, not with the checked calls
;; vector-ref and vector-set! (8.6: the generator's own speed). A constant index
;; is converted to Smalltalk's 1-based one when the macro expands.
(define-macro (cg-ref v i)
  (if (number? i) `[,v at: ,(+ i 1)] `[,v at: (+ ,i 1)]))
(define-macro (cg-set! v i x)
  (if (number? i) `[,v at: ,(+ i 1) put: ,x] `[,v at: (+ ,i 1) put: ,x]))
(define-macro (cg-size v) `[,v size])

;; a variable: name frame scope captured? vector? slot arg?
(define (cg-make-var name frame scope arg) (vector name frame scope #f #f #f arg))
(define-macro (cg-var-frame d) `(cg-ref ,d 1))
(define-macro (cg-var-scope d) `(cg-ref ,d 2))
(define-macro (cg-var-captured? d) `(cg-ref ,d 3))
(define-macro (cg-var-vector? d) `(cg-ref ,d 4))
(define-macro (cg-var-index d) `(cg-ref ,d 5))       ; its place in the temp vector

;; a scope (a frame's own, or an inlined block's): frame vars(reversed) vector-size
(define (cg-make-scope frame) (vector frame '() 0))
(define-macro (cg-scope-frame s) `(cg-ref ,s 0))
(define-macro (cg-scope-vars s) `(cg-ref ,s 1))

;; a frame: parent args(list) outer-refs(reversed) scopes(reversed) slots copied
;;          literals literal-index depth max-depth encoder node children stream
(define (cg-make-frame parent node)
  (vector parent '() '() '() [(smalltalk IdentityDictionary) new] '()
          [(smalltalk OrderedCollection) new] [(smalltalk IdentityDictionary) new]
          0 0 #f node '() #f))
(define-macro (cg-frame-parent f) `(cg-ref ,f 0))
(define-macro (cg-frame-slots f) `(cg-ref ,f 4))
(define-macro (cg-frame-literals f) `(cg-ref ,f 6))
(define-macro (cg-frame-enc f) `(cg-ref ,f 10))

;; the analysis's state: variables by name, and the frame or scope of each block node
(define (cg-make-state)
  (vector [(smalltalk Dictionary) new] [(smalltalk IdentityDictionary) new]))
(define-macro (cg-state-vars st) `(cg-ref ,st 0))
(define-macro (cg-state-blocks st) `(cg-ref ,st 1))

(define (cg-lookup st name) [(cg-state-vars st) at: name ifAbsent: (lambda () #f)])

(define (cg-declare st frame scope name arg)
  (let ((d (cg-make-var name frame scope arg)))
    [(cg-state-vars st) at: name put: d]
    (cg-set! scope 1 (cons d (cg-scope-vars scope)))
    d))

;;; ---------------------------------------------------------------------------
;;; 1. Analysis

;; the blocks Opal inlines: (receiver-is-block? . argument count that are blocks)
(define cg-if-true (smalltalk-symbol "ifTrue:"))
(define cg-if-true-if-false (smalltalk-symbol "ifTrue:ifFalse:"))
(define cg-while-true (smalltalk-symbol "whileTrue:"))
(define cg-is-truthy (smalltalk-symbol "isTruthy:"))
(define cg-value (smalltalk-symbol "value"))
(define (cg-bound-cell? x) (and [x isKindOf: (smalltalk LispGlobal)] [x isBound]))

(define (cg-block? n) (eq? (cg-ref n 0) 'block))
(define (cg-plain-block? n)                    ; a block of no arguments, for inlining
  (and (cg-block? n) (= (cg-size (cg-ref n 1)) 0)))

(define (cg-inline-kind n)                     ; 'if 'if-else 'while or #f, for a send
  (let ((sel (cg-ref n 2)) (args (cg-ref n 3)))
    (cond ((and (eq? sel cg-if-true) (cg-plain-block? (cg-ref args 0))) 'if)
          ((and (eq? sel cg-if-true-if-false)
                (cg-plain-block? (cg-ref args 0)) (cg-plain-block? (cg-ref args 1)))
           'if-else)
          ((and (eq? sel cg-while-true) (cg-plain-block? (cg-ref n 1)) (cg-plain-block? (cg-ref args 0)))
           'while)
          (else #f))))

(define (cg-analyze st n frame scope)
  (let ((tag (cg-ref n 0)))
    (cond ((eq? tag 'lit) #f)
          ((eq? tag 'var) (cg-reference st frame (cg-ref n 1)))
          ((eq? tag 'assign)
           (cg-analyze st (cg-ref n 2) frame scope)
           (cg-write st frame (cg-ref n 1)))
          ((eq? tag 'send)
           (let ((kind (cg-inline-kind n)) (args (cg-ref n 3)))
             (cond ((eq? kind 'if)
                    (cg-analyze st (cg-ref n 1) frame scope)
                    (cg-analyze-inlined st (cg-ref args 0) frame scope))
                   ((eq? kind 'if-else)
                    (cg-analyze st (cg-ref n 1) frame scope)
                    (cg-analyze-inlined st (cg-ref args 0) frame scope)
                    (cg-analyze-inlined st (cg-ref args 1) frame scope))
                   ((eq? kind 'while)
                    ;; twice: a write in one pass comes after a capture in the pass
                    ;; before, as in the loop's next iteration. A variable declared
                    ;; in the loop is new each iteration, so it starts uncaptured.
                    (cg-analyze-inlined st (cg-ref n 1) frame scope)
                    (cg-analyze-inlined st (cg-ref args 0) frame scope)
                    (cg-uncapture-scope st (cg-ref n 1))
                    (cg-uncapture-scope st (cg-ref args 0))
                    (cg-analyze-inlined st (cg-ref n 1) frame scope)
                    (cg-analyze-inlined st (cg-ref args 0) frame scope))
                   (else
                    (cg-analyze st (cg-ref n 1) frame scope)
                    (cg-analyze-each st args frame scope)))))
          ((eq? tag 'block)
           (let ((seen [(cg-state-blocks st) at: n ifAbsent: (lambda () #f)]))
             (if seen
                 ;; met again, in a loop's second pass: the same frame and variables,
                 ;; its statements analyzed again; each call has new variables, so
                 ;; they start uncaptured
                 (begin
                   (for-each (lambda (s) (for-each (lambda (d) (cg-set! d 3 #f)) (cg-scope-vars s)))
                             (cg-ref seen 3))
                   (cg-analyze-each st (cg-ref n 3) seen (car (reverse (cg-ref seen 3)))))
                 (let* ((f (cg-make-frame frame n))
                        (s (cg-make-scope f)))
                   [(cg-state-blocks st) at: n put: f]
                   (cg-set! f 3 (list s))
                   (cg-set! f 1 (let loop ((names (vector->list (cg-ref n 1))) (acc '()))   ; in order
                                      (if (null? names)
                                          (reverse acc)
                                          (loop (cdr names) (cons (cg-declare st f s (car names) #t) acc)))))
                   (vector-for-each (lambda (name) (cg-declare st f s name #f)) (cg-ref n 2))
                   (cg-analyze-each st (cg-ref n 3) f s)))))
          ((eq? tag 'brace) (cg-analyze-each st (cg-ref n 1) frame scope))
          (else (error "codegen: not a node" n)))))

(define (cg-analyze-each st v frame scope)
  (let loop ((i 0))
    (when (< i (cg-size v))
      (cg-analyze st (cg-ref v i) frame scope)
      (loop (+ i 1)))))

;; an inlined block: its own scope (made once) in the enclosing frame
(define (cg-analyze-inlined st b frame scope)
  (let ((s [(cg-state-blocks st) at: b ifAbsent: (lambda () #f)]))
    (unless s
      (set! s (cg-make-scope frame))
      [(cg-state-blocks st) at: b put: s]
      (cg-set! frame 3 (cons s (cg-ref frame 3)))
      (vector-for-each (lambda (name) (cg-declare st frame s name #f)) (cg-ref b 2)))
    (cg-analyze-each st (cg-ref b 3) frame s)))

(define (cg-uncapture-scope st b)
  (let ((s [(cg-state-blocks st) at: b ifAbsent: (lambda () #f)]))
    (when s (for-each (lambda (d) (cg-set! d 3 #f)) (cg-scope-vars s)))))

;; a read of name in frame: one from another frame is captured, and every frame
;; between needs it copied in
(define (cg-reference st frame name)
  (let ((d (cg-lookup st name)))
    (when (and d (not (eq? (cg-var-frame d) frame)))
      (cg-set! d 3 #t)
      (let up ((f frame))
        (unless (eq? f (cg-var-frame d))
          (unless (memq d (cg-ref f 2)) (cg-set! f 2 (cons d (cg-ref f 2))))
          (up (cg-frame-parent f)))))))

(define (cg-write st frame name)
  (let ((d (cg-lookup st name)))
    (unless d (error "codegen: assignment to an undeclared variable" name))
    (cond ((not (eq? (cg-var-frame d) frame))
           (cg-set! d 4 #t)
           (cg-reference st frame name))
          ((cg-var-captured? d) (cg-set! d 4 #t)))))

;;; ---------------------------------------------------------------------------
;;; 2. Layout

;; slots: arguments, then copied items (a variable, or a scope standing for its
;; temp vector), then temporaries and temp vectors
(define (cg-layout f)
  (let ((slots (cg-frame-slots f))
        (n 0))
    (define (take! key) [slots at: key put: n] (set! n (+ n 1)))
    (for-each (lambda (d)
                (when (cg-var-vector? d) (error "codegen: an argument in a temp vector" (cg-ref d 0)))
                (take! d))
              (cg-ref f 1))
    (let ((copied
           (let loop ((refs (reverse (cg-ref f 2))) (acc '()))
             (if (null? refs)
                 (reverse acc)
                 (let* ((d (car refs))
                        (item (if (cg-var-vector? d) (cg-var-scope d) d)))
                   (loop (cdr refs) (if (memq item acc) acc (cons item acc))))))))
      (cg-set! f 5 copied)
      (for-each take! copied))
    (for-each (lambda (s)
                (let ((k 0))
                  (for-each (lambda (d)
                              (cond ((cg-ref d 6) #f)            ; an argument: placed already
                                    ((cg-var-vector? d) (cg-set! d 5 k) (set! k (+ k 1)))
                                    (else (take! d))))
                            (reverse (cg-scope-vars s)))
                  (cg-set! s 2 k)
                  (when (> k 0) (take! s))))
              (reverse (cg-ref f 3)))
    n))

;;; ---------------------------------------------------------------------------
;;; 3. Emission

(define-macro (cg-push f)
  `(let ((%cg-d (+ (cg-ref ,f 8) 1)))
     (cg-set! ,f 8 %cg-d)
     (when (> %cg-d (cg-ref ,f 9)) (cg-set! ,f 9 %cg-d))))
(define-macro (cg-pop f n) `(cg-set! ,f 8 (- (cg-ref ,f 8) ,n)))

(define (cg-literal-index f x)
  [(cg-ref f 7) at: x
     ifAbsent: (lambda ()
                 [(cg-frame-literals f) add: x]
                 [(cg-ref f 7) at: x put: (- [(cg-frame-literals f) size] 1)])])

;; the selectors with a bytecode of their own, by index
(define cg-special-selectors
  (let ((d [(smalltalk IdentityDictionary) new])
        (sels [(smalltalk EncoderForSistaV1) specialSelectors]))
    (let loop ((i 1))
      (when (<= i (cg-size sels))
        (let ((s (cg-ref sels (- i 1))))
          (unless (smalltalk-nil? s) [d at: s put: i]))
        (loop (+ i 1))))
    d))

(define (cg-push-literal f x)
  (let ((enc (cg-frame-enc f)))
    (cg-push f)
    (cond ((or (eq? x #t) (eq? x #f) (smalltalk-nil? x)) [enc genPushSpecialLiteral: x])
          ((and [x isInteger] (>= x -32768) (<= x 32767)) [enc genPushInteger: x])
          ((and (char? x) (<= (char->integer x) 65535)) [enc genPushCharacter: x])
          (else
           ;; string literals are read-only, as Opal makes them
           (when (and [x isString] (not [x isSymbol]) (not [x isReadOnlyObject])) [x beReadOnlyObject])
           [enc genPushLiteral: (cg-literal-index f x)]))))

;; cached by the name string itself: the translator's names are literal strings
(define cg-bindings [(smalltalk IdentityDictionary) new])
(define (cg-global-binding name)
  [cg-bindings at: name
     ifAbsent: (lambda ()
                 [cg-bindings at: name put: [[(smalltalk Smalltalk) globals] associationAt: (smalltalk-symbol name)]])])

(define (cg-slot f key) [(cg-frame-slots f) at: key])

;; the slot that holds a temp vector (the scope's own, or copied into f)
(define (cg-vector-slot f scope) (cg-slot f scope))

(define (cg-read st f name)
  (let ((d (cg-lookup st name)) (enc (cg-frame-enc f)))
    (cg-push f)
    (cond ((not d) [enc genPushLiteralVar: (cg-literal-index f (cg-global-binding name))])
          ((cg-var-vector? d) [enc genPushRemoteTemp: (cg-var-index d) inVectorAt: (cg-vector-slot f (cg-var-scope d))])
          (else [enc genPushTemp: (cg-slot f d)]))))

(define (cg-store st f name pop)
  (let ((d (cg-lookup st name)) (enc (cg-frame-enc f)))
    (unless d (error "codegen: store into an undeclared variable" name))
    (when pop (cg-pop f 1))
    (if (cg-var-vector? d)
        (let ((i (cg-var-index d)) (v (cg-vector-slot f (cg-var-scope d))))
          (if pop [enc genStorePopRemoteTemp: i inVectorAt: v] [enc genStoreRemoteTemp: i inVectorAt: v]))
        (let ((slot (cg-slot f d)))
          (if pop [enc genStorePopTemp: slot] [enc genStoreTemp: slot])))))

;; emit thunk's code on its own, answering its bytes
;; (the encoder has no getter for its stream: the frame keeps it)
(define (cg-segment f thunk)
  (let ((enc (cg-frame-enc f))
        (ws [(smalltalk WriteStream) on: [(smalltalk ByteArray) new: 32]])
        (saved (cg-ref f 13)))
    [enc stream: ws]
    (cg-set! f 13 ws)
    (thunk)
    [enc stream: saved]
    (cg-set! f 13 saved)
    [ws contents]))

(define (cg-put-bytes f bytes) [(cg-ref f 13) nextPutAll: bytes])

(define (cg-jump-size d)                        ; a forward jump or branch over d bytes
  (cond ((and (> d 0) (< d 9)) 1)
        ((<= d 255) 2)
        (else 4)))

;; push n's value
(define (cg-gen st n f)
  (let ((tag (cg-ref n 0)))
    (cond ((eq? tag 'lit) (cg-push-literal f (cg-ref n 1)))
          ((eq? tag 'var) (cg-read st f (cg-ref n 1)))
          ((eq? tag 'assign)
           (cg-gen st (cg-ref n 2) f)
           (cg-store st f (cg-ref n 1) #f))
          ((eq? tag 'send) (cg-gen-send st n f #f))
          ((eq? tag 'block) (cg-closure st n f))
          ((eq? tag 'brace)
           (let ((elements (cg-ref n 1)))
             (vector-for-each (lambda (e) (cg-gen st e f)) elements)
             (cg-pop f (cg-size elements))
             (cg-push f)
             [(cg-frame-enc f) genPushConsArray: (cg-size elements)]))
          (else (error "codegen: not a node" n)))))

;; n for its effect: nothing is left on the stack
(define (cg-effect st n f)
  (let ((tag (cg-ref n 0)))
    (cond ((eq? tag 'assign)
           (cg-gen st (cg-ref n 2) f)
           (cg-store st f (cg-ref n 1) #t))
          ((eq? tag 'send) (cg-gen-send st n f #t))
          ((or (eq? tag 'lit) (eq? tag 'var)) #f)
          (else (cg-gen st n f) (cg-pop f 1) [(cg-frame-enc f) genPop]))))

(define (cg-gen-send st n f effect)
  (let ((kind (cg-inline-kind n)) (args (cg-ref n 3)) (receiver (cg-ref n 1)))
    (cond ((and (eq? kind 'if) (eq? (cg-ref receiver 0) 'lit) (eq? (cg-ref receiver 1) #t))
           ;; true ifTrue: [...], the translator's sequence: just the statements
           (cg-inlined st (cg-ref args 0) f effect))
          ((eq? kind 'if) (cg-if st f receiver (cg-ref args 0) #f effect))
          ((eq? kind 'if-else) (cg-if st f receiver (cg-ref args 0) (cg-ref args 1) effect))
          ((eq? kind 'while) (cg-while st f receiver (cg-ref args 0) effect))
          ((and (eq? (cg-ref n 2) cg-value) (= (cg-size args) 0)
                (eq? (cg-ref receiver 0) 'lit) (cg-bound-cell? (cg-ref receiver 1)))
           ;; reading a global that is bound: a LispGlobal's value is its second
           ;; slot, where pushLiteralVariable reads a binding's value -- a load, not
           ;; a send. A cell is never unbound again, so the check (LispGlobal>>value)
           ;; is needed only for one unbound now, a forward reference.
           (cg-push f)
           [(cg-frame-enc f) genPushLiteralVar: (cg-literal-index f (cg-ref receiver 1))]
           (when effect (cg-pop f 1) [(cg-frame-enc f) genPop]))
          (else
           (cg-gen st receiver f)
           (vector-for-each (lambda (a) (cg-gen st a f)) args)
           (let* ((sel (cg-ref n 2))
                  (nargs (cg-size args))
                  (special [cg-special-selectors at: sel ifAbsent: (lambda () #f)])
                  (enc (cg-frame-enc f)))
             (cg-pop f nargs)
             (if special
                 [enc genSendSpecial: special numArgs: nargs]
                 [enc genSend: (cg-literal-index f sel) numArgs: nargs]))
           (when effect (cg-pop f 1) [(cg-frame-enc f) genPop])))))

;; an inlined block: its temp vector made on entry, then its statements
(define (cg-inlined st b f effect)
  (let ((s [(cg-state-blocks st) at: b]))
    (cg-enter-scope f s)
    (cg-statements st (cg-ref b 3) f effect)))

(define (cg-enter-scope f s)
  (when (> (cg-ref s 2) 0)
    (let ((enc (cg-frame-enc f)))
      [enc genPushNewArray: (cg-ref s 2)]
      (cg-push f)
      (cg-pop f 1)
      [enc genStorePopTemp: (cg-vector-slot f s)])))

;; statements, the last one's value pushed unless for effect
(define (cg-statements st stmts f effect)
  (let ((n (cg-size stmts)))
    (if (= n 0)
        (unless effect (cg-push-literal f (smalltalk-nil)))
        (let loop ((i 0))
          (if (= i (- n 1))
              (if effect (cg-effect st (cg-ref stmts i) f) (cg-gen st (cg-ref stmts i) f))
              (begin (cg-effect st (cg-ref stmts i) f) (loop (+ i 1))))))))

;; test ifTrue: then [ifFalse: else]
(define (cg-if st f test then else effect)
  (let ((enc (cg-frame-enc f))
        (on-false #t))                          ; branch to else when the test is false
    (if (and (eq? (cg-ref test 0) 'send) (eq? (cg-ref test 2) cg-is-truthy)
             (eq? (cg-ref (cg-ref test 1) 0) 'var)
             (equal? (cg-ref (cg-ref test 1) 1) "LispCore")
             (not (cg-lookup st "LispCore")))
        ;; (LispCore isTruthy: x) is x ~~ false: branch to else when x == false
        (begin
          (cg-gen st (cg-ref (cg-ref test 3) 0) f)
          (cg-push-literal f #f)
          (cg-pop f 1)
          [enc genSendSpecial: [cg-special-selectors at: (smalltalk-symbol "==")] numArgs: 1]
          (set! on-false #f))
        (cg-gen st test f))
    (cg-pop f 1)                                ; the branch takes the test
    (let* ((depth (cg-ref f 8))
           (then-bytes (cg-segment f (lambda () (cg-inlined st then f effect))))
           (else-bytes (cg-segment f (lambda ()
                                       (cg-set! f 8 depth)
                                       (if else
                                           (cg-inlined st else f effect)
                                           (unless effect (cg-push-literal f (smalltalk-nil)))))))
           (else-size [else-bytes size])
           (jump-size (if (= else-size 0) 0 (cg-jump-size else-size)))
           (distance (+ [then-bytes size] jump-size)))
      (if on-false [enc genBranchPopFalse: distance] [enc genBranchPopTrue: distance])
      (cg-put-bytes f then-bytes)
      (when (> else-size 0) [enc genJump: else-size])
      (cg-put-bytes f else-bytes))))

;; [cond] whileTrue: [body]
(define (cg-while st f cond body effect)
  (let* ((enc (cg-frame-enc f))
         (cond-bytes (cg-segment f (lambda () (cg-inlined st cond f #f))))
         (body-bytes (begin (cg-pop f 1) (cg-segment f (lambda () (cg-inlined st body f #t)))))
         (exit-distance (+ [body-bytes size] 4))     ; over the body and the jump back
         (branch-size (cg-jump-size exit-distance)))
    (cg-put-bytes f cond-bytes)
    [enc genBranchPopFalse: exit-distance]
    (cg-put-bytes f body-bytes)
    [enc genJumpLong: (- 0 (+ [cond-bytes size] branch-size [body-bytes size] 4))]
    (unless effect (cg-push-literal f (smalltalk-nil)))))

;; a real block: compiled now; made at run time, or once now if it captures nothing
(define (cg-closure st b f)
  (let* ((bf [(cg-state-blocks st) at: b])
         (cb (cg-compile-frame st bf #f))
         (copied (cg-ref bf 5))
         (enc (cg-frame-enc f)))
    (cg-set! f 12 (cons cb (cg-ref f 12)))
    (if (null? copied)
        (let ((stmts (cg-ref b 3)))
          (cg-push f)
          [enc genPushLiteral:
               (cg-literal-index f
                 (if (and (= (cg-size (cg-ref b 2)) 0) (< (cg-size (cg-ref b 1)) 4)
                          (= (cg-size stmts) 1) (eq? (cg-ref (cg-ref stmts 0) 0) 'lit))
                     (let ((k [(smalltalk ConstantBlockClosure) numArgs: (cg-size (cg-ref b 1))
                                 literal: (cg-ref (cg-ref stmts 0) 1)]))
                       [k compiledBlock: cb]
                       k)
                     [(smalltalk CleanBlockClosure) compiledBlock: cb]))])
        (begin
          (for-each (lambda (item) (cg-push f) [enc genPushTemp: (cg-slot f item)]) copied)
          (cg-pop f (length copied))
          (cg-push f)
          [enc genPushFullClosure: (cg-literal-index f cb) numCopied: (length copied)
               receiverOnStack: #f outerContextNeeded: #t]))))

;;; ---------------------------------------------------------------------------
;;; Frames to compiled code

(define cg-header-flag [(smalltalk CompiledMethod) headerFlagForEncoder: (smalltalk EncoderForSistaV1)])

(define (cg-compile-frame st f method?)
  (let* ((nslots (cg-layout f))
         (enc [(smalltalk EncoderForSistaV1) new])
         (ws [(smalltalk WriteStream) on: [(smalltalk ByteArray) new: 64]])
         (node (cg-ref f 11))
         (nargs (length (cg-ref f 1))))
    (when (> nargs 15) (error "Too many arguments"))
    [enc stream: ws]
    (cg-set! f 10 enc)
    (cg-set! f 13 ws)
    (cg-enter-scope f (car (reverse (cg-ref f 3))))
    (if method?
        (begin (cg-gen st (cg-ref node 1) f) [enc genReturnTop])
        (begin (cg-statements st (cg-ref node 3) f #f) [enc genReturnTopToCaller]))
    (let* ((bytes [ws contents])
           (lits (cg-frame-literals f))
           (nlits (+ [lits size] (if method? 2 1)))
           (header (+ cg-header-flag [nargs bitShift: 24] [nslots bitShift: 18] nlits))
           (code (if method?
                     [(smalltalk CompiledMethod) basicNew: (+ [bytes size] [(smalltalk CompiledMethod) trailerSize]) header: header]
                     [(smalltalk CompiledBlock) basicNew: [bytes size] header: header]))
           (out [(smalltalk WriteStream) with: code]))
      [out position: (- [code initialPC] 1)]
      [out nextPutAll: bytes]
      (let loop ((i 1))
        (when (<= i [lits size])
          [code literalAt: i put: [lits at: i]]
          (loop (+ i 1))))
      (when method?
        [code literalAt: (- nlits 1) put: (smalltalk-symbol "doIt")]
        [code literalAt: nlits put: [(smalltalk UndefinedObject) binding]])
      [code needsFrameSize: (cg-ref f 9)]
      (for-each (lambda (cb) [cb outerCode: code]) (cg-ref f 12))
      code)))

;; the entry point: a method tree (opal.lisp) to a CompiledMethod
(define (codegen-method m)
  (let* ((st (cg-make-state))
         (f (cg-make-frame #f m))
         (s (cg-make-scope f)))
    (cg-set! f 3 (list s))
    (cg-analyze st (cg-ref m 1) f s)
    (cg-compile-frame st f #t)))
