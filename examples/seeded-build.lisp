;;; seeded-build.lisp -- how this image was built, read back from the image itself
;;; (specs/15-phase-9-language.md step 9.1)
;;;
;;; A cog-lisp image is built from an earlier one, the seed: a release pinned in
;;; pharo.pins by its tag and checksum. The seed's compiler compiles the new
;;; compiler's source; the new compiler then compiles itself until two rounds
;;; make the same methods (a fixpoint). The image remembers how that went.

(define info (image-build-info))
(define (info-ref key) (cdr (assq key info)))

(display "built from the seed: ") (display (info-ref 'seed)) (newline)
(display "the seed's checksum is pinned: ")
(display (= (string-length (info-ref 'seed-sha256)) 64)) (newline)
(display "stage 0 of the bootstrap was the ") (display (info-ref 'stage-0)) (newline)
(display "the compiler compiled its own source, form by form: ")
(display (> (info-ref 'forms) 150)) (newline)
(display "and reached a fixpoint: ") (display (info-ref 'fixpoint)) (newline)
