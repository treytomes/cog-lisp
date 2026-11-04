;;; bootstrap.lisp -- the compiler compiles itself, to a fixpoint
;;; (specs/phase-8-self-hosting.md step 8.4)
;;;
;;; Stage 0 is the Smalltalk compiler (LispCompiler). Compiling the compiler's
;;; source (compiler-sources, in lib/compiler/) with it gives the methods M0, which
;;; the image build runs: that is stage 1, the LISP compiler running as compiled
;;; code. Stage 1 compiles the same source, read by the LISP reader, to M1;
;;; installing M1 makes stage 2, which compiles it to M2; installing M2 makes stage
;;; 3, which compiles it to M3. The fixpoint: M0 = M1 = M2 = M3, form by form,
;;; compared by fingerprint (each method's header, bytecode bytes and literals,
;;; blocks recursively), as tests/phase-8.3-compiler.st compares methods.
;;;
;;;   (define b (bootstrap-compiler "lib/compiler"))   ; leaves stage 3 installed
;;;   (bootstrap-fixpoint? b)                          ; -> #t
;;;   (bootstrap-differences b 2 3)                    ; -> labels of forms that differ
;;;
;;; This file is not among the sources it compiles, so installing a stage never
;;; replaces the procedures running the bootstrap.

(define compiler-sources '("reader.lisp" "opal.lisp" "compiler.lisp"))

;;; Source

(define (bootstrap-file-text path) [[path asFileReference] contents])

(define (bootstrap-path dir name) (string-append dir "/" name))

;; A source: (next-datum-thunk . source-map), over a file's text
(define (smalltalk-source text)
  (let ((r [(smalltalk LispReader) basicOn: text]))     ; the Smalltalk reader itself
    (cons (lambda () [r next]) r)))

(define (lisp-source text)
  (let ((r (make-reader text)))
    (cons (lambda () (reader-next r)) r)))

(define (bootstrap-source-for map datum)
  (if (vector? map)
      (reader-source-for map datum)
      (let ((s [map sourceFor: datum])) (if (smalltalk-nil? s) #f s))))

;;; Compilers: (datum source-map context) -> CompiledMethod

(define (smalltalk-compile datum map context)
  (let ((c [(smalltalk LispCompiler) new]))
    [c instVarNamed: "sourceMap" put: map]
    [c smalltalkCompile: datum context: (or context (smalltalk-nil))]))   ; not the one in use

(define (lisp-compile datum map context)              ; whichever stage is installed
  (compile-form datum map context))

;;; Stages

(define bootstrap-gensym-key (smalltalk-symbol "GensymCounter"))
(define (gensym-counter)                     ; nil until the first gensym: 0
  (let ((n [[(smalltalk LispPrimitives) classPool] at: bootstrap-gensym-key]))
    (if (smalltalk-nil? n) 0 n)))
(define (gensym-counter! n) [[(smalltalk LispPrimitives) classPool] at: bootstrap-gensym-key put: n])

;; every top-level form of the sources, as eval sees one (a begin's forms and a
;; macro call's expansion are top-level forms), compiled with compile: a list of
;; (label . method), in order. Each top-level datum starts from the same gensym
;; counter in every stage, so macro expansions agree.
(define (stage-compile compile open dir gensym-base)
  (let files ((names compiler-sources) (acc '()))
    (if (null? names)
        (reverse acc)
        (let* ((name (car names))
               (source (open (bootstrap-file-text (bootstrap-path dir name))))
               (next (car source))
               (map (cdr source)))
          (let forms ((k 1) (acc acc))
            (let ((d (next)))
              (if (eof-object? d)
                  (files (cdr names) acc)
                  (begin
                    (gensym-counter! gensym-base)
                    (forms (+ k 1)
                           (stage-visit compile d map #f
                                        (string-append name " form " (number->string k))
                                        acc))))))))))

(define (stage-visit compile datum map context label acc)
  (cond ((and (pair? datum) (eq? (car datum) 'begin))
         (let loop ((ds (cdr datum)) (acc acc))
           (if (null? ds) acc (loop (cdr ds) (stage-visit compile (car ds) map context label acc)))))
        ((and (pair? datum) (lc-macro-for (car datum) (scope-new)))
         => (lambda (m)
              (stage-visit compile (lc-expand datum m) map
                           (or (bootstrap-source-for map datum) context) label acc)))
        (else (cons (cons label (compile datum map context)) acc))))

;; run a stage's methods: their definitions replace the running compiler's
(define (stage-install methods)
  (for-each (lambda (lm) (opal-run (cdr lm))) methods))

;;; Listings

(define (method-listing m)
  (with-output-to-string (lambda () (listing-into m))))

;; A method's fingerprint: its header, its bytecode bytes, and every literal,
;; blocks recursively. Not the symbolic listing: printing a nested block makes
;; Pharo look up the block's source node, which fails for many of these methods.
(define (listing-into code)
  (display "code header ") (display [code header]) (display " bytes")
  (let ((last [code endPC]))
    (let loop ((i [code initialPC]))
      (when (<= i last)
        (display " ") (display [code at: i])
        (loop (+ i 1)))))
  (newline)
  (vector-for-each
   (lambda (lit)
     (cond ([lit isKindOf: (smalltalk CompiledBlock)] (listing-into lit))
           ([lit isKindOf: (smalltalk BlockClosure)]
            (display "closure ") (display [lit numArgs]) (newline)
            (listing-into [lit compiledBlock]))
           (else (display "lit ") (display [[[lit class] name] asString]) (display " ")
                 (display [lit printStringLimitedTo: 2000]) (newline))))
   [code literals]))

(define (stage-listings methods)
  (map (lambda (lm) (cons (car lm) (method-listing (cdr lm)))) methods))

;;; The bootstrap

;; answers a vector of the four stages' listings, each a list of (label . text);
;; stage 3 is left installed
(define (bootstrap-compiler dir)
  (let* ((base (gensym-counter))
         (m0 (stage-compile smalltalk-compile smalltalk-source dir base))
         (m1 (stage-compile lisp-compile lisp-source dir base)))
    (stage-install m1)                                  ; stage 2
    (let ((m2 (stage-compile lisp-compile lisp-source dir base)))
      (stage-install m2)                                ; stage 3
      (let ((m3 (stage-compile lisp-compile lisp-source dir base)))
        (gensym-counter! (+ (gensym-counter) 1))
        (vector (stage-listings m0) (stage-listings m1) (stage-listings m2) (stage-listings m3))))))

;; the labels of the forms whose methods differ between stages i and j
(define (bootstrap-differences b i j)
  (let loop ((a (vector-ref b i)) (c (vector-ref b j)) (acc '()))
    (cond ((and (null? a) (null? c)) (reverse acc))
          ((or (null? a) (null? c)) (reverse (cons "different numbers of forms" acc)))
          ((string=? (cdr (car a)) (cdr (car c))) (loop (cdr a) (cdr c) acc))
          (else (loop (cdr a) (cdr c) (cons (car (car a)) acc))))))

(define (bootstrap-fixpoint? b)
  (and (null? (bootstrap-differences b 0 1))
       (null? (bootstrap-differences b 1 2))
       (null? (bootstrap-differences b 2 3))))
