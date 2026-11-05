;;; bootstrap.lisp -- cog-lisp's compiler compiles itself, to a fixpoint
;;; (Phase 8 steps 8.4 and 8.6, Phase 9 step 9.1; lib/compiler/bootstrap.lisp is
;;; part of the built image)
;;;
;;; The image was built from a seed, an earlier cog-lisp, whose compiler compiled
;;; this one's source. Here the running compiler plays the seed: it is stage 0.
;;; Stage 0 compiles the compiler's own source; installing the result makes stage
;;; 1, which does it again, giving stage 2, and so on. If each stage makes the
;;; same methods as the one before, the compiler has reached a fixpoint: it
;;; compiles itself into itself.

(define compiler-dir
  [[[[[(current-load-path) asFileReference] parent] parent] / "lib"] / "compiler"])

(define (report b i j)
  (display "  stage ") (write j) (display " vs stage ") (write i) (display ": ")
  (let ((diffs (bootstrap-differences b i j)))
    (if (null? diffs)
        (display "every method identical")
        (begin (write (length diffs)) (display " methods differ"))))
  (newline))

(display "compiling ") (write compiler-sources) (newline)
(define b (bootstrap-compiler [compiler-dir fullName]))
(report b 0 1)   ; the running compiler, built from this source, makes what stage 1 makes
(report b 1 2)   ; compiled by itself, it still compiles the same
(report b 2 3)   ; the fixpoint
(display "  fixpoint: ") (write (bootstrap-fixpoint? b)) (newline)

;; Stage 3 is now the compiler the globals name, compiled by stage 2. It works:
(lisp-eval-string "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))")
(display "stage 3 compiled fib; (fib 20) = ") (write (fib 20)) (newline)
