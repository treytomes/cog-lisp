;;; ide-backtrace.lisp -- LISP backtraces, step 5 of specs/34-morphic-ide.md (R-25,
;;; with 11.5's backtrace; AC-5): an error's frames as data in a session's result,
;;; each procedure with its file and line, a primitive as one, the top-level form
;;; last; (backtrace) at a session's break and at the console REPL's; and the
;;; frames of the current computation away from a break. No window is opened.
(load "../../lib/test.lisp")
(require 'ide)

(define (temp name)
  (let ((d [[[(smalltalk FileLocator) temp] / name] asFileReference]))
    [d ensureDeleteAll] [d ensureCreateDirectory] d))
(define (write-raw! f text)
  [f ensureDelete]
  [f writeStreamDo: (procedure->block (lambda (s) [s nextPutAll: text]))]
  [f fullName])
(define (has? text part) (if (string-search text part) #t #f))
(define (frame-summary fr)
  (list (vector-ref fr 0) (and (vector-ref fr 1) [[(vector-ref fr 1) asFileReference] basename]) (vector-ref fr 2)))

(define dir (temp "cog-lisp-backtrace"))
(define file
  (write-raw! [dir / "bt.lisp"]
              "(define (bt-g x)\n  (vector-ref x 0))\n\n(define (bt-f n)\n  (let ((y (* n 2)))\n    (+ 1 (bt-g y))))\n\n(define (bt-each l)\n  (for-each (lambda (x) (bt-g x)) l))\n"))
(ide-load-file file)

(define-test "R-25 an error's frames: each procedure with its file and line, the top-level form last"
  (let* ((s (ide-session)) (r (ide-eval s "(bt-f 5)")))
    (check (result-status r) 'error)
    (check (map frame-summary (result-backtrace r))
           '((vector-ref #f #f) (bt-g "bt.lisp" 1) (bt-f "bt.lisp" 4) (top-level #f #f)))
    (check-true (eq? (vector-ref (cadr (result-backtrace r)) 3) bt-g))      ; the procedure itself
    ;; the same frames, asked for while the session waits at the break
    (check (map frame-summary (ide-backtrace s)) (map frame-summary (result-backtrace r)))
    ;; none once it is back at the top
    (ide-eval s "(abort)")
    (check (ide-backtrace s) '())
    (check (result-backtrace (ide-eval s "(+ 1 2)")) '())
    (ide-close s)))

(define-test "R-25 a call inside a lambda: its procedure's frame, once"
  (let* ((s (ide-session)) (r (ide-eval s "(bt-each '(5))")))
    (check (map (lambda (fr) (vector-ref fr 0)) (result-backtrace r))
           '(vector-ref bt-g for-each bt-each top-level))
    (ide-close s)))

(define-test "(backtrace) at a session's break writes the failing frames"
  (let* ((s (ide-session)))
    (ide-eval s "(bt-f 5)")
    (check (result-output (ide-eval s "(backtrace)"))
           "  0: vector-ref\n  1: bt-g  bt.lisp:1\n  2: bt-f  bt.lisp:4\n  3: the top-level form\n")
    (ide-close s)))

(define-test "(backtrace) at the console REPL's break loop"
  (let* ((in [(smalltalk ReadStream) on: "(bt-f 5)\n(backtrace)\n(abort)\n"])
         (out [(smalltalk WriteStream) on: [(smalltalk String) new]])
         (err [(smalltalk WriteStream) on: [(smalltalk String) new]]))
    [[[(smalltalk LispRepl) in: in out: out err: err] interactive: #t] run]
    (let ((o [out contents]))
      (check-true (has? o "  0: vector-ref\n  1: bt-g  bt.lisp:1\n  2: bt-f  bt.lisp:4\n  3: the top-level form\n")))
    (check-true (has? [err contents] "not a vector"))))

(define-test "(backtrace) away from a break: the current computation"
  (let ((out (with-output-to-string (lambda () (backtrace)))))
    (check-true (has? out "the top-level form"))
    (check-false (has? out ": backtrace"))))                              ; not itself

(define-test "backtrace is built in, documented"
  (check (documentation-category 'backtrace) "Conditions and restarts")
  (check-true (string-prefix? "(backtrace)" (documentation 'backtrace))))

(run-tests)
[dir ensureDeleteAll]
