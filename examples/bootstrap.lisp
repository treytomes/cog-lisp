;;; bootstrap.lisp -- cog-lisp's compiler compiles itself, to a fixpoint
;;; (Phase 8 steps 8.4 and 8.6; lib/compiler/bootstrap.lisp is part of the built image)
;;;
;;; Stage 0, the Smalltalk compiler, built the LISP compiler the image runs: stage
;;; 1. Stage 1 compiles the compiler's own source; installing the result makes
;;; stage 2, which does it again, giving stage 3. If each stage makes the same
;;; methods as the one before, the compiler has reached a fixpoint: it compiles
;;; itself into itself.
;;;
;;; The LISP compiler writes bytecode itself (step 8.6), so its code differs from
;;; the Smalltalk compiler's; through Opal (set-code-generator! 'opal) it makes the
;;; very same methods. Both bootstraps are run here.

(define compiler-dir
  [[[[[(current-load-path) asFileReference] parent] parent] / "lib"] / "compiler"])
(define sealed-set-generator set-code-generator!)   ; the installed compiler's switch

(define (report b i j)
  (display "  stage ") (write j) (display " vs stage ") (write i) (display ": ")
  (let ((diffs (bootstrap-differences b i j)))
    (if (null? diffs)
        (display "every method identical")
        (begin (write (length diffs)) (display " methods differ"))))
  (newline))

(display "compiling ") (write compiler-sources) (newline)

(display "through Opal:") (newline)
(set-code-generator! 'opal)
(define bo (bootstrap-compiler [compiler-dir fullName]))
(report bo 0 1)   ; the LISP compiler compiles itself as the Smalltalk compiler does
(report bo 1 2)
(report bo 2 3)
(display "  fixpoint: ") (write (bootstrap-fixpoint? bo)) (newline)

(display "writing bytecode itself:") (newline)
(set-code-generator! 'direct)
(define bd (bootstrap-compiler [compiler-dir fullName]))
(display "  stage 1 vs stage 0: different code, as expected") (newline)
(report bd 1 2)   ; compiled by itself, it still compiles the same
(report bd 2 3)   ; the fixpoint
(display "  fixpoint: ") (write (bootstrap-fixpoint? bd)) (newline)
(sealed-set-generator 'direct)

;; Stage 3 is now the compiler the globals name, compiled by stage 2. It works:
(lisp-eval-string "(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))")
(display "stage 3 compiled fib; (fib 20) = ") (write (fib 20)) (newline)
