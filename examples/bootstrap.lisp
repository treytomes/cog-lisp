;;; bootstrap.lisp -- cog-lisp's compiler compiles itself, to a fixpoint
;;; (Phase 8 step 8.4; lib/compiler/bootstrap.lisp is part of the built image)
;;;
;;; Stage 0, the Smalltalk compiler, built the LISP compiler the image runs: stage
;;; 1. Stage 1 compiles the compiler's own source; installing the result makes
;;; stage 2, which does it again, giving stage 3. If each stage makes the same
;;; methods as the one before, the compiler has reached a fixpoint: it compiles
;;; itself into itself.

(define compiler-dir
  [[[[[(current-load-path) asFileReference] parent] parent] / "lib"] / "compiler"])

(display "compiling ") (write compiler-sources) (newline)
(define b (bootstrap-compiler [compiler-dir fullName]))

(define (report i j)
  (display "  stage ") (write j) (display " vs stage ") (write i) (display ": ")
  (let ((diffs (bootstrap-differences b i j)))
    (if (null? diffs)
        (display "every method identical")
        (begin (display "different: ") (write diffs))))
  (newline))

(report 0 1)   ; the LISP compiler compiles itself as the Smalltalk compiler does
(report 1 2)   ; compiled by itself, it still compiles the same
(report 2 3)   ; the fixpoint
(display "fixpoint: ") (write (bootstrap-fixpoint? b)) (newline)

;; Stage 3 is now the compiler in the image, compiled by stage 2. It works:
(lisp-eval-string "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))")
(display "stage 3 compiled fib; (fib 20) = ") (write (fib 20)) (newline)
