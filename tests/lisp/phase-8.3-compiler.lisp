;;; phase-8.3-compiler.lisp -- unit tests of the compiler written in LISP
;;; (lib/compiler/compiler.lisp; specs/phase-8-self-hosting.md step 8.3, AC-3).
;;; Until step 9.1, tests/phase-8.3-compiler.st also compared it byte for byte with
;;; the Smalltalk compiler, which retired then; these test the compiler on its own
;;; terms. The built image loads lib/compiler/.
(load "../../lib/test.lisp")

(define (run-form d) (opal-run (compile-form d)))

;; the compile error a form gives, or no-error
(define (compile-failure d)
  (guard (e (#t (error-object-message e)))
    (compile-form d)
    'no-error))

(define-test "AC-3 compile-form answers a CompiledMethod that runs"
  (check-true [(compile-form '(+ 1 2)) isKindOf: (smalltalk CompiledMethod)])
  (check (run-form '(+ 1 2)) 3)
  (check (run-form '(let ((x 2) (y 5)) (* x y))) 10)
  (check (run-form '((lambda (a . r) (list a r)) 1 2 3)) '(1 (2 3)))
  (check (run-form '(quasiquote (1 (unquote (+ 1 1)) (unquote-splicing (list 3 4))))) '(1 2 3 4))
  (check (run-form '[(smalltalk Array) with: 1 with: 2]) #(1 2)))

;; method-listing (lib/compiler/bootstrap.lisp): header, bytes and literals, blocks too
(define-test "AC-3 LispCompiler compile: is the LISP compiler"
  (for-each (lambda (d) (check (method-listing [[(smalltalk LispCompiler) new] compile: d])
                               (method-listing (compile-form d))))
            '((+ 1 2)
              (define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
              (lambda (x) (let loop ((i 0)) (if (< i x) (loop (+ i 1)) i)))
              (cond ((assq 'a '((a . 1))) => cdr) (else #f))
              (send (smalltalk OrderedCollection) new))))

(define-test "AC-3 lisp-eval defines, and procedures keep their source"
  (lisp-eval-string "(define (lc-test-square x)   ; a comment\n  (* x x))")
  (check (lc-test-square 7) 49)
  (check (procedure-source lc-test-square) "(define (lc-test-square x)   ; a comment\n  (* x x))"))

(define-test "AC-3 self tail calls run in constant space"
  (lisp-eval-string "(define (lc-test-count n acc) (if (= n 0) acc (lc-test-count (- n 1) (+ acc 1))))")
  (check (lc-test-count 200000 0) 200000))

(define-test "AC-3 macros: defined through lisp-eval, used at once"
  (lisp-eval-string "(define-macro (lc-test-twice e) `(begin ,e ,e)) (define lc-test-n 0) (lc-test-twice (set! lc-test-n (+ lc-test-n 1)))")
  (check lc-test-n 2))

(define-test "AC-3 compile errors, with the messages the Smalltalk compiler gave"
  (check (compile-failure '(if)) "if: bad syntax: (if)")
  (check (compile-failure '(lambda (x x) x)) "lambda: duplicate parameter in (x x)")
  (check (compile-failure '(let ((x 1) (x 2)) x)) "let: duplicate name: x")
  (check (compile-failure '(send x foo: 1 2)) "send: foo: takes 1 argument, got 2")
  (check (compile-failure '(smalltalk NoSuchGlobalAtAll)) "smalltalk: no Smalltalk global named NoSuchGlobalAtAll")
  (check (compile-failure '(lambda () (define-macro (m) 1))) "define-macro is allowed only at top level")
  (check (compile-failure '(lambda (x) (define y 1) x (define z 2))) "define after an expression in a body")
  (check-error-class (compile-form '(f . 1)) LispCompileError))

(define-test "AC-3 a new special form, added from LISP"
  ;; (lc-test-unless test body ...) compiled directly: if test then unspecified else body
  (define-special-form 'lc-test-unless
    (lambda (c form scope tail)
      (lc-translate c `(if ,(car (cdr form)) (if #f #f) (begin ,@(cdr (cdr form)))) scope tail)))
  (check (run-form '(lc-test-unless #f 1 2)) 2)
  (check (run-form '(lc-test-unless #t 1 2)) (if #f #f)))

(run-tests)
