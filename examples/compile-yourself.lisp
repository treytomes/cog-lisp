;;; compile-yourself.lisp -- the compiler written in cog-lisp, at work
;;; (Phase 8 step 8.3; lib/compiler/ is part of the built image)

;; Compile a form with the LISP compiler: the result is a Smalltalk CompiledMethod.
(define method (compile-form '(lambda (x) (* x x))))
(display "compiled: a ") (display [[[method class] name] asString]) (newline)

;; Running it answers the procedure the lambda makes.
(define square (opal-run method))
(display "(square 12) = ") (write (square 12)) (newline)

;; Its bytecode, as the Smalltalk tools list it.
(display "bytecode of the method:") (newline)
(vector-for-each (lambda (line) (display "  ") (display line) (newline))
                 [[method symbolic] lines])

;; It writes that bytecode itself (Phase 8 step 8.6), and it is the compiler
;; everything uses: LispCompiler, the Smalltalk side, compiles with it too
;; (method-listing shows a method's header, bytecode bytes and literals, and its
;; blocks'). Until Phase 9 a second compiler, written in Smalltalk, built this one.
(define (same-code? form)
  (equal? (method-listing (compile-form form))
          (method-listing [[(smalltalk LispCompiler) new] compile: form])))
(define forms '((lambda (x) (* x x))
                (define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
                (let loop ((i 0)) (if (< i 10) (loop (+ i 1)) i))))
(display "LispCompiler compiles with it: ")
(write (map same-code? forms)) (newline)

;; lisp-eval-string reads with the LISP reader and compiles with the LISP compiler.
(lisp-eval-string "(define (cube x) (* x x x))")
(display "(cube 3) = ") (write (cube 3)) (newline)

;; The compiler is ordinary cog-lisp: every procedure in it keeps its source.
(display "how the compiler translates if:") (newline)
(display (procedure-source lc-translate-if)) (newline)
