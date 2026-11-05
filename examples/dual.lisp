;;; dual.lisp -- dual numbers, a new kind of number added from outside the core
;;; (Phase 9 step 9.2; loaded by examples/new-number-type.lisp and its test)
;;;
;;; A dual number is a + b*eps, where eps*eps = 0. Computing f(x + eps) gives
;;; f(x) + f'(x)*eps: the derivative comes out exactly, with no symbolic algebra
;;; and no rounding (automatic differentiation).
;;;
;;; cog-lisp numbers are Smalltalk numbers, so a new kind is a subclass of
;;; Smalltalk's Number. It joins the arithmetic through Smalltalk's coercion
;;; protocol (adaptToInteger:andSend: and its siblings, which (+ 1 d) uses when 1
;;; does not know d), and the predicates and the printer through cog-lisp's number
;;; protocol (lispIsExact, lispIsReal, lispWriteOn:base:). The class and its
;;; methods are made through interop; nothing in cog-lisp changes.

(define Dual
  [[[[(smalltalk Number) << (smalltalk-symbol "Dual")]
     slots: (vector (smalltalk-symbol "re") (smalltalk-symbol "eps"))]
    package: "CogLisp-Example-Dual"]
   install])

(define (dual-method! class source) [class compile: source classified: "dual"])

(dual-method! [Dual class] "re: a eps: b
	^ self basicNew setRe: a eps: b")
(dual-method! [Dual class] "from: x
	^ (x isKindOf: self) ifTrue: [x] ifFalse: [self re: x eps: 0]")
(dual-method! Dual "setRe: a eps: b
	re := a. eps := b")
(dual-method! Dual "re
	^ re")
(dual-method! Dual "eps
	^ eps")

;; arithmetic: the other operand may be any number
(dual-method! Dual "+ x
	| d | d := self class from: x.
	^ self class re: re + d re eps: eps + d eps")
(dual-method! Dual "- x
	| d | d := self class from: x.
	^ self class re: re - d re eps: eps - d eps")
(dual-method! Dual "* x
	| d | d := self class from: x.
	^ self class re: re * d re eps: (re * d eps) + (eps * d re)")
(dual-method! Dual "/ x
	| d | d := self class from: x.
	^ self class re: re / d re eps: ((eps * d re) - (re * d eps)) / (d re * d re)")
(dual-method! Dual "negated
	^ self class re: re negated eps: eps negated")
(dual-method! Dual "= x
	| d |
	x isNumber ifFalse: [^ false].
	d := self class from: x.
	^ re = d re and: [eps = d eps]")
(dual-method! Dual "hash
	^ re hash bitXor: eps hash")
;; ordered by the real part, so (< 1 d) and (max ...) work
(dual-method! Dual "< x
	^ re < (self class from: x) re")

;; when 1 + d finds that 1 does not know d, Smalltalk asks d to adapt 1
(for-each (lambda (kind)
            (dual-method! Dual (string-append "adaptTo" kind ": n andSend: selector
	^ (self class from: n) perform: selector with: self")))
          '("Integer" "Fraction" "Float"))

;; cog-lisp's number protocol: what the predicates and the printer ask
(dual-method! Dual "lispIsExact
	^ re lispIsExact and: [eps lispIsExact]")
(dual-method! Dual "lispIsReal
	^ false")
(dual-method! Dual "lispWriteOn: aStream base: radix
	re lispWriteOn: aStream base: radix.
	eps = 1 ifTrue: [^ aStream nextPutAll: '+eps'].
	eps = -1 ifTrue: [^ aStream nextPutAll: '-eps'].
	(eps lispIsReal and: [eps < 0]) ifFalse: [aStream nextPut: $+].
	eps lispWriteOn: aStream base: radix.
	aStream nextPutAll: 'eps'")

;; the LISP side
(define (dual re eps) [Dual re: re eps: eps])
(define (dual? x) [x isKindOf: Dual])
(define (dual-re d) [d re])
(define (dual-eps d) [d eps])

;; the derivative of f at x, exactly
(define (derivative f x) (dual-eps (f (dual x 1))))

;; read syntax: 3+2eps, 1/2-eps, -1.5+0.25eps (a real part, a sign, an optional
;; coefficient, then eps), registered with the reader
(define (dual-text? s)
  (let ((n (string-length s)))
    (and (> n 3) (string=? (substring s (- n 3) n) "eps"))))
(define (dual-parse s)
  (let loop ((i (- (string-length s) 4)))
    (cond ((<= i 0) #f)
          ((memv (string-ref s i) '(#\+ #\-))
           (let ((re (string->number (substring s 0 i)))
                 (eps-text (substring s i (- (string-length s) 3))))
             (and re
                  (let ((eps (cond ((string=? eps-text "+") 1)
                                   ((string=? eps-text "-") -1)
                                   (else (string->number eps-text)))))
                    (and eps (dual re eps))))))
          (else (loop (- i 1))))))
(define-number-syntax dual-text? dual-parse)
