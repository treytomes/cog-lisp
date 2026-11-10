;;; coverage.lisp -- which procedures and branches a run reached (specs/20-coverage.md
;;; AC-1 to AC-4). The code under test is compiled inside each test, from a string,
;;; while a session runs; its lines are the string's.
(load "../../lib/test.lisp")

;; the counts for the code in source, after running it with run (a thunk)
(define (covered source run)
  (coverage-start)
  (eval-all source)
  (run)
  (coverage-stop))

(define (count-of counts kind line)
  (let loop ((cs counts))
    (cond ((null? cs) 'no-probe)
          ((and (eq? (vector-ref (car cs) 3) kind) (eqv? (vector-ref (car cs) 1) line)) (vector-ref (car cs) 4))
          (else (loop (cdr cs))))))

(define-test "AC-1 a called procedure is counted; one never called is reported, with its line"
  (let ((counts (covered "(define (used x) (* x 2))\n(define (unused x) x)\n" (lambda () (used 1) (used 2)))))
    (check (count-of counts 'procedure 1) 2)
    (check (count-of counts 'procedure 2) 0)
    (let ((report (with-output-to-string (lambda () (coverage-report counts)))))
      (check-true (string-search report "coverage: 1 of 2 probes reached"))
      (check-true (string-search report "2:1: never called: (define (unused x) x)"))
      (check-false (string-search report "(define (used x)")))))

(define-test "AC-2 both sides of if, cond and case, nested, are counted apart"
  (let ((counts (covered "(define (f n)\n  (if (> n 0)\n      (cond ((= n 1) 'one)\n            (else (case n ((2) 'two) (else 'many))))\n      'none))\n"
                         (lambda () (f 1) (f 2) (f 2)))))
    (check (count-of counts 'true 2) 3)               ; (> n 0)
    (check (count-of counts 'false 2) 0)
    (check (count-of counts 'true 3) 1)               ; (= n 1)
    (check (count-of counts 'false 3) 2)
    (let ((report (with-output-to-string (lambda () (coverage-report counts)))))
      (check-true (string-search report "2:7: never taken, the false side of: (> n 0)")))))

(define-syntax my-unless
  (syntax-rules () ((_ test body) (if test #f body))))

(define-test "AC-3 a macro's expansion counts at its use; a closure's body at its lambda"
  (let ((counts (covered "(define (g x)\n  (my-unless (> x 5)\n    'small))\n(define make-adder (lambda (n) (lambda (m) (+ n m))))\n"
                         (lambda () (g 1) ((make-adder 1) 2)))))
    (check (count-of counts 'false 2) 1)              ; the if my-unless made, at (> x 5)
    (check (count-of counts 'true 2) 0)
    (check (count-of counts 'procedure 4) 1)          ; make-adder, and the closure it made
    (check (length (let loop ((cs counts) (acc '()))
                     (cond ((null? cs) acc)
                           ((and (eq? (vector-ref (car cs) 3) 'procedure) (eqv? (vector-ref (car cs) 1) 4))
                            (loop (cdr cs) (cons (car cs) acc)))
                           (else (loop (cdr cs) acc)))))
           2)))

(define-test "AC-4 coverage keeps tail calls: a loop of a million runs in constant space"
  (let ((counts (covered "(define (spin n) (if (= n 0) 'done (spin (- n 1))))\n" (lambda () (check (spin 1000000) 'done)))))
    (check (count-of counts 'procedure 1) 1)          ; a self-call is a loop, not a new entry
    (check (count-of counts 'true 1) 1)
    (check (count-of counts 'false 1) 1000000)))

(define-test "without a session nothing is probed, and coverage-stop answers ()"
  (check (coverage-stop) '())
  (eval-all "(define (later) 1)")
  (coverage-start)
  (check (later) 1)
  (check (coverage-stop) '()))

(define-test "cog-lisp's own lib folder is not instrumented (R-7)"
  (coverage-start)
  (require 'cl)
  (check (coverage-stop) '()))

(define-test "coverage-start with files covers only those"
  (coverage-start (list "elsewhere.lisp"))
  (eval-all "(define (not-listed) 1)")
  (check (coverage-stop) '()))

;;; across runs (specs/20-coverage.md section 8)

;; a scratch file of LISP code, removed after
(define (with-scratch-file text proc)
  (let ((path [[[(smalltalk FileLocator) temp] / (string-append "coverage-scratch-" (number->string [(smalltalk Time) millisecondClockValue]) ".lisp")] fullName]))
    (call-with-output-file path (lambda (port) (display text port)))
    (dynamic-wind (lambda () #f) (lambda () (proc path)) (lambda () [[path asFileReference] ensureDelete]))))

(define (places counts kind line)
  (length (filter (lambda (c) (and (eq? (vector-ref c 3) kind) (eqv? (vector-ref c 1) line))) counts)))

(define-test "R-8 a file loaded twice counts once per place, its copies added up"
  (with-scratch-file "(define (twice-loaded x) (if (> x 0) 'up 'down))\n"
    (lambda (path)
      (coverage-start)
      (load path)
      (eval '(twice-loaded 1))
      (load path)
      (eval '(twice-loaded -1))
      (let ((counts (coverage-stop)))
        (check (places counts 'procedure 1) 1)
        (check (count-of counts 'procedure 1) 2)
        (check (count-of counts 'true 1) 1)
        (check (count-of counts 'false 1) 1)))))

(define-test "R-9 a record names its file by its full, canonical path"
  (with-scratch-file "(define (pathed) 1)\n"
    (lambda (path)
      (let* ((file [[path asFileReference] basename])
             (roundabout (string-append [[[[path asFileReference] parent] fullName] asString] "/../"
                                        [[[[path asFileReference] parent] basename] asString] "/" file)))
        (coverage-start)
        (load roundabout)
        (let ((counts (coverage-stop)))
          (check (vector-ref (car counts) 0) [[[path asFileReference] canonicalize] fullName]))))))

(define-test "R-10 counts written and read back are the same data"
  (let* ((counts (covered "(define (w x) (if x 1 2))\n" (lambda () (w #t))))
         (text (with-output-to-string (lambda () (for-each (lambda (c) (write c) (newline)) counts))))
         (back (read-all text)))
    (check back counts)))

(define-test "R-11 coverage-merge adds up runs by place, in the order first seen"
  (let* ((one (covered "(define (m x) (if x 1 2))\n" (lambda () (m #t))))
         (two (covered "(define (m x) (if x 1 2))\n" (lambda () (m #f) (m #f))))
         (both (coverage-merge one two)))
    (check (length both) (length one))
    (check (count-of both 'procedure 1) 3)
    (check (count-of both 'true 1) 1)
    (check (count-of both 'false 1) 2)
    (let ((report (with-output-to-string (lambda () (coverage-report both)))))
      (check-true (string-search report "coverage: 3 of 3 probes reached")))))

(define-test "R-12 an if on a constant has no probes: unless and a cond with no else count only their own branches"
  (let ((counts (covered "(define (u x)\n  (unless x\n    'body))\n(define (k x)\n  (cond ((= x 1) 'one)))\n"
                         (lambda () (u #t) (u #f) (k 1) (k 2)))))
    ;; each: an entry, and the two sides of its own test; no side "never taken"
    (check (length counts) 6)
    (check (filter (lambda (c) (= (vector-ref c 4) 0)) counts) '())))

(run-tests)
