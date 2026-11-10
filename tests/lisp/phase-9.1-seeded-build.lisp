;;; phase-9.1-seeded-build.lisp -- the image is built from a seed
;;; (specs/15-phase-9-language.md step 9.1, AC-1). The image records how it was
;;; built; and the bootstrap runs with any compiler's entry points as stage 0 --
;;; here the running one, standing in for a seed that makes the same code.
(load "../../lib/test.lisp")

(define info (image-build-info))
(define (info-ref key) (let ((p (assq key info))) (if p (cdr p) 'missing)))

(define-test "AC-1 the image was built from the pinned seed"
  (check (info-ref 'stage-0) 'seed)
  (check-true (string? (info-ref 'seed)))
  (check-true (char=? (string-ref (info-ref 'seed) 0) #\v))
  (check (string-length (info-ref 'seed-sha256)) 64))

(define-test "AC-1 the build's bootstrap reached a fixpoint"
  (check (info-ref 'fixpoint) #t)
  (check-true (> (info-ref 'forms) 150))
  (check-true (integer? (info-ref 'seed-differences))))

;; the sealed compiler's entry points, kept before the bootstrap below installs
;; stages whose globals replace these names
(define running-entries [(smalltalk LispCompiler) entries])
(define stage-1-compile-form compile-form)

(define b (bootstrap-compiler-from-seed "lib/compiler" running-entries))

(define-test "AC-1 a seed is stage 0: the bootstrap records it"
  (check (bootstrap-stage0 b) 'seed)
  (check-false (eq? compile-form stage-1-compile-form)))

(define-test "AC-1 stages 1, 2 and 3 make the same methods: the fixpoint"
  (check (bootstrap-differences b 1 2) '())
  (check (bootstrap-differences b 2 3) '())
  (check-true (bootstrap-fixpoint? b)))

(define-test "AC-1 a seed that makes the same code as the source differs nowhere"
  (check (length (vector-ref b 0)) (length (vector-ref b 1)))
  (check (bootstrap-differences b 0 1) '()))

(define-test "AC-1 the fixpoint ignores how the seed's code differs, not how the stages do"
  ;; a made-up result: stage 0 differs from stage 1; stages 1 to 3 agree
  (let ((m0 (list (cons "f 1" "old code")))
        (m1 (list (cons "f 1" "new code"))))
    (check-true (bootstrap-fixpoint? (vector m0 m1 m1 m1 'seed)))
    (check (bootstrap-differences (vector m0 m1 m1 m1 'seed) 0 1) '("f 1"))
    (check-false (bootstrap-fixpoint? (vector m0 m1 m1 m0 'seed)))))

(run-tests)
