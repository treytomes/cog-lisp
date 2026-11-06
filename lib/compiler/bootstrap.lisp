;;; bootstrap.lisp -- the compiler compiles itself, to a fixpoint
;;; (specs/phase-8-self-hosting.md step 8.4; specs/phase-9-language.md step 9.1)
;;;
;;; Stage 0 is the compiler that builds this one: a seed's, an earlier cog-lisp
;;; image's, reached through its entry points (LispCompiler entries). Compiling the
;;; compiler's source (compiler-sources, in lib/compiler/) with it gives the
;;; methods M0; the image build runs the same compilation, which defines stage 1,
;;; this source running as compiled code. Stage 1 compiles the source, read by the
;;; new reader, to M1; installing M1 makes stage 2, which compiles it to M2;
;;; installing M2 makes stage 3, which compiles it to M3. The fixpoint: M1 = M2 =
;;; M3, form by form, compared by fingerprint (each method's header, bytecode bytes
;;; and literals, blocks recursively). Stage 1 already has this source's meaning,
;;; whatever compiled it, so its output must be final. M0 = M1 holds only when the
;;; seed generates code as this source does; that is reported, not required.
;;;
;;;   (define b (bootstrap-compiler "lib/compiler"))   ; the running compiler as the seed
;;;   (bootstrap-fixpoint? b)                          ; -> #t
;;;   (bootstrap-differences b 2 3)                    ; -> labels of forms that differ
;;;
;;; The image build passes the seed's entry points:
;;;   (bootstrap-compiler-from-seed "lib/compiler" entries)
;;;
;;; Either leaves stage 3 installed. This file is not among the sources it
;;; compiles, so installing a stage never replaces the procedures running the
;;; bootstrap. (Until step 9.1, stage 0 could also be the Smalltalk compiler.)

(define compiler-sources '("reader.lisp" "opal.lisp" "codegen.lisp" "compiler.lisp" "syntax-rules.lisp"))

;;; Source

(define (bootstrap-file-text path) [[path asFileReference] contents])

(define (bootstrap-path dir name) (string-append dir "/" name))

;; A source, over a file's text: (next-datum-thunk source-map source-for), where
;; (source-for datum) is the text the reader read datum from, or #f. Each reader
;; answers that for itself.

(define (lisp-source text)
  (let ((r (make-reader text)))
    (list (lambda () (reader-next r)) r (lambda (datum) (reader-source-for r datum)))))

;;; Compilers: (datum source-map context) -> CompiledMethod

(define (lisp-compile datum map context)              ; whichever stage is installed
  (compile-form datum map context))

;; The seed's reader and compiler, through its entry points (LispCompiler entries,
;; a Smalltalk Dictionary of procedures): sealed, so a new definition of
;; make-reader or compile-form does not change them.
(define (seed-entry entries name) [entries at: (smalltalk-symbol name)])

(define (seed-source entries)
  (let ((make (seed-entry entries "makeReader"))
        (next (seed-entry entries "next"))
        (source-for (seed-entry entries "sourceFor")))
    (lambda (text)
      (let ((r (make text)))
        (list (lambda () (next r)) r (lambda (datum) (source-for r datum)))))))

(define (seed-compiler entries)
  (let ((compile (seed-entry entries "compile")))
    (lambda (datum map context) (compile datum map (or context #f)))))

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
        (files (cdr names)
               (stage-compile-file compile open (bootstrap-path dir (car names)) (car names) gensym-base acc)))))

;; one source file's forms, compiled as if the file were being loaded, so what a
;; definition records about its file (its documentation's category) is the same
;; in every stage as in a load (Phase 10 step 10.1)
(define (stage-compile-file compile open path name gensym-base acc)
  [(smalltalk LispLoadPath) value: [[path asFileReference] fullName]
     during: (lambda ()
               (let* ((source (open (bootstrap-file-text path)))
                      (next (car source))
                      (map (car (cdr source)))
                      (source-for (car (cdr (cdr source)))))
                 (let forms ((k 1) (acc acc))
                   (let ((d (next)))
                     (if (eof-object? d)
                         acc
                         (begin
                           (gensym-counter! gensym-base)
                           (forms (+ k 1)
                                  (stage-visit compile d map source-for #f
                                               (string-append name " form " (number->string k))
                                               acc))))))))])

(define (stage-visit compile datum map source-for context label acc)
  (cond ((and (pair? datum) (eq? (car datum) 'begin))
         (let loop ((ds (cdr datum)) (acc acc))
           (if (null? ds) acc (loop (cdr ds) (stage-visit compile (car ds) map source-for context label acc)))))
        ((and (pair? datum) (lc-macro-for (car datum) (scope-new)))
         => (lambda (m)
              (stage-visit compile (lc-expand datum m) map source-for
                           (or (source-for datum) context) label acc)))
        (else (cons (cons label (compile datum map context)) acc))))

;; run a stage's methods: their definitions replace the running compiler's
(define (stage-install methods)
  (for-each (lambda (lm) (opal-run (cdr lm))) methods))

;;; Listings

(define (method-listing m)
  "(method-listing method)
A fingerprint of a CompiledMethod: its header, its bytecode bytes and its literals, blocks included, to compare two compilations."
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

;; the running compiler as the seed: stages 1 to 3 then rebuild it from its source
(define (bootstrap-compiler dir)
  "(bootstrap-compiler directory)
Compiles the compiler source in directory with the running compiler, then with each new stage in turn, three times; answers the stages, for bootstrap-fixpoint? and bootstrap-differences. The last stage is left installed."
  (bootstrap-compiler-from-seed dir [(smalltalk LispCompiler) entries]))

;; the image build: the seed is stage 0 (step 9.1)
(define (bootstrap-compiler-from-seed dir entries)
  "(bootstrap-compiler-from-seed directory entries)
As bootstrap-compiler, with a seed compiler (its entry points) as stage 0, as the image build does."
  (bootstrap-stages dir (seed-compiler entries) (seed-source entries)))

;; answers a vector of the four stages' listings, each a list of (label . text),
;; and what stage 0 was (the symbol seed); stage 3 is left installed
(define (bootstrap-stages dir compile0 open0)
  (let* ((base (gensym-counter))
         (m0 (stage-compile compile0 open0 dir base))
         (m1 (stage-compile lisp-compile lisp-source dir base)))
    (stage-install m1)                                  ; stage 2
    (let ((m2 (stage-compile lisp-compile lisp-source dir base)))
      (stage-install m2)                                ; stage 3
      (let ((m3 (stage-compile lisp-compile lisp-source dir base)))
        (gensym-counter! (+ (gensym-counter) 1))
        (vector (stage-listings m0) (stage-listings m1) (stage-listings m2) (stage-listings m3) 'seed)))))

(define (bootstrap-stage0 b)
  "(bootstrap-stage0 stages)
What stage 0 of a bootstrap was: the symbol seed."
  (vector-ref b 4))

;; the labels of the forms whose methods differ between stages i and j
(define (bootstrap-differences b i j)
  "(bootstrap-differences stages i j)
The labels of the forms whose methods differ between stages i and j."
  (let loop ((a (vector-ref b i)) (c (vector-ref b j)) (acc '()))
    (cond ((and (null? a) (null? c)) (reverse acc))
          ((or (null? a) (null? c)) (reverse (cons "different numbers of forms" acc)))
          ((string=? (cdr (car a)) (cdr (car c))) (loop (cdr a) (cdr c) acc))
          (else (loop (cdr a) (cdr c) (cons (car (car a)) acc))))))

;; Stages 1, 2 and 3 make the same methods. Stage 0, the seed, is not compared: it
;; generates code as its own, older source did.
(define (bootstrap-fixpoint? b)
  "(bootstrap-fixpoint? stages)
True if stages 1, 2 and 3 of a bootstrap made the same methods: the compiler compiles itself into itself."
  (and (null? (bootstrap-differences b 1 2))
       (null? (bootstrap-differences b 2 3))))
