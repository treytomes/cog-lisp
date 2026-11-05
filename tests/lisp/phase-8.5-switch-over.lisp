;;; phase-8.5-switch-over.lisp -- the LISP reader and compiler are the ones in use
;;; (specs/phase-8-self-hosting.md step 8.5, AC-5 and AC-6). Since step 9.1 they
;;; are the only ones: the Smalltalk ones, and COGLISP_COMPILER, retired.
(load "../../lib/test.lisp")

(define-test "AC-5 the image has the LISP reader and compiler installed"
  (check-true [(smalltalk LispCompiler) hasLispCompiler])
  (check-true (procedure? [[(smalltalk LispCompiler) entries] at: (smalltalk-symbol "compile")])))

(define-test "AC-5 eval, load and read use it"
  (check (eval '(let loop ((i 0)) (if (< i 5) (loop (+ i 1)) i))) 5)
  (check (eval-all "(define (sw-sq x) (* x x)) (sw-sq 12)") 144)
  (check (read (open-input-string "(a . b)")) '(a . b))
  (check (string->number "-1.5e2") -150.0))

(define-test "AC-5 read leaves a port just after the datum"
  (let ((p (open-input-string "(1 2) x")))
    (check (read p) '(1 2))
    (check (read-char p) #\space)
    (check (read p) 'x)
    (check-true (eof-object? (read p)))))

(define-test "AC-5 the compiler is sealed: redefining what it uses changes only the program"
  (let ((saved-append append) (saved-cons cons) (saved-reader make-reader))
    (set! append (lambda xs 'mine))
    (set! cons (lambda (a b) 'my-cons))
    (set! make-reader (lambda (s) 'my-reader))
    (let ((result (eval-all "(define (sw-q x) `(1 ,@x 2)) (sw-q (list 'a))"))
          (read-back (read (open-input-string "(r e a d)")))
          (mine (cons 1 2)))
      (set! append saved-append)
      (set! cons saved-cons)
      (set! make-reader saved-reader)
      (check result '(1 a 2))
      (check read-back '(r e a d))
      (check mine 'my-cons))))

(define-test "AC-5 a compile error has the same message"
  (check-error (eval-all "(lambda (x x) x)") "lambda: duplicate parameter in (x x)")
  (check-error (eval-all "(let ((a 1) (a 2)) a)") "let: duplicate name: a"))

(define-test "AC-6 procedure-source works on the compiler's own procedures"
  (check (substring (procedure-source lc-translate-if) 0 25) "(define (lc-translate-if ")
  (check (substring (procedure-source reader-next) 0 22) "(define (reader-next r"))

(run-tests)
