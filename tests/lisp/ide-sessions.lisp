;;; ide-sessions.lisp -- sessions and the record of changes, step 2 of
;;; specs/34-morphic-ide.md (R-12 to R-15, R-31 to R-35; AC-2, AC-7): an
;;; evaluation in a process of its own, with its own unit and ports, a break
;;; loop on the failing computation's stack, interrupting, reading typed lines,
;;; two sessions at once, and every evaluation that defines recorded. No window
;;; is opened.
(load "../../lib/test.lisp")
(require 'ide)
(require 'console)
(require "editor-services/geometry.lisp")

(define (sleep-ms n) [[(smalltalk Delay) forMilliseconds: n] wait])

;;; --- evaluating ---------------------------------------------------------------------

(define-test "R-13 a session evaluates its forms: the values, written, and the output"
  (let* ((s (ide-session 'name "basics"))
         (r (ide-eval s "(display \"hi\") (+ 1 2) (list 1 \"two\" 'three)")))
    (check (result-status r) 'done)
    (check (result-values r) '(3 (1 "two" three)))
    (check (result-written r) '("3" "(1 \"two\" three)"))
    (check (result-output r) "hi")
    (check (result-level r) 0)
    (check-false (result-report r))
    ;; a definition answers no value; the session remembers it
    (check (result-values (ide-eval s "(define (sq x) (* x x))")) '())
    (check (result-values (ide-eval s "(sq 7)")) '(49))
    (check (ide-session-output s) "hi")
    (check (ide-session-name s) "basics")
    (check (ide-session-maker s) 'person)
    (check-true (memq s (ide-sessions)))
    (ide-close s)
    (check-false (memq s (ide-sessions)))))

;;; --- the break loop (R-14) ----------------------------------------------------------

(define-test "R-14 an error waits at a break; a restart continues the computation"
  (let* ((s (ide-session))
         (r (ide-eval s "(+ 1 no-such-variable-here)")))
    (check (result-status r) 'error)
    (check-true (string-search (result-report r) "no-such-variable-here"))
    (check-true (member "use-value" (result-restarts r)))
    (check-true (member "abort" (result-restarts r)))
    (check (result-level r) 1)
    (check-false (ide-session-busy? s))
    ;; at the break, a form evaluates there
    (let ((r2 (ide-eval s "(* 2 3)")))
      (check (result-values r2) '(6))
      (check (result-level r2) 1))
    ;; the restart: the variable is 5, and the sum goes on
    (let ((r3 (ide-eval s "(use-value 5)")))
      (check (result-status r3) 'done)
      (check (result-values r3) '(6))
      (check (result-level r3) 0))
    (ide-close s)))

(define-test "R-14 abort comes back to the top, from any depth"
  (let ((s (ide-session)))
    (check (result-status (ide-eval s "(car 5)")) 'error)
    (check (result-level (ide-eval s "(vector-ref (vector) 3)")) 2)     ; an error at the break
    (let ((r (ide-eval s "(abort)")))
      (check (result-status r) 'aborted)
      (check (result-level r) 0))
    (check (result-values (ide-eval s "(+ 2 2)")) '(4))
    (ide-close s)))

;;; --- interrupting (R-15) and reading --------------------------------------------------

(define-test "R-15 a runaway evaluation is interrupted, into a break"
  (let* ((s (ide-session))
         (r (ide-eval s "(let loop () (loop))" 'timeout 200)))
    (check (result-status r) 'running)
    (check-true (ide-session-busy? s))
    (ide-interrupt s)
    (let ((r2 (ide-wait s 5000)))
      (check (result-status r2) 'error)
      (check-true (string-search (result-report r2) "interrupted")))
    (check (result-status (ide-eval s "(abort)")) 'aborted)
    (check (result-values (ide-eval s "(* 6 7)")) '(42))
    (ide-close s)))

(define-test "a program in a session reads the lines typed for it"
  (let* ((s (ide-session))
         (r (ide-eval s "(list (read-line) (read))" 'timeout 200)))
    (check (result-status r) 'running)
    (ide-type s "hello there")
    (ide-type s "(a b)")
    (check (result-values (ide-wait s 5000)) '(("hello there" (a b))))
    (ide-close s)))

;;; --- two at once (R-31) ------------------------------------------------------------------

(define-test "R-31 two sessions at once write to their own ports"
  (let ((s1 (ide-session)) (s2 (ide-session)))
    (check (result-status
            (ide-eval s1 "(display \"one\") [[(smalltalk Delay) forMilliseconds: 400] wait] (display \"two\")" 'timeout 100))
           'running)
    (check (result-output (ide-eval s2 "(display \"x\")")) "x")
    (check (result-output (ide-wait s1 5000)) "onetwo")
    ;; and neither wrote to this program's output
    (check (with-output-to-string (lambda () (ide-eval s2 "(display \"y\")"))) "")
    (ide-close s1)
    (ide-close s2)))

(define-test "R-31 the console's capabilities are bound per process"
  (let ((s (ide-session)) (here (console-width)))
    (ide-eval s "(require 'console)")
    (check (result-status
            (ide-eval s "(with-console '(width 33) (lambda () [[(smalltalk Delay) forMilliseconds: 400] wait] (console-width)))"
                      'timeout 100))
           'running)
    (check (console-width) here)                 ; not 33, while the session runs inside with-console
    (check (result-values (ide-wait s 5000)) '(33))
    (ide-close s)))

;;; --- a unit, and a wrapper ---------------------------------------------------------------

(define-test "a session in a library's unit defines the library's names"
  (let* ((unit [(smalltalk LispUnit) libraryNamed: 'es-geometry])
         (s (ide-session 'unit unit))
         (other (ide-session)))
    (check (result-status (ide-eval s "(define (twice r) (* 2 (%square r)))")) 'done)
    (check (result-values (ide-eval other "(es-geometry:twice 3)")) '(18))
    (ide-close s)
    (ide-close other)))

(define-test "a wrapper runs around every evaluation"
  (let ((s (ide-session 'wrapper (lambda (thunk) (display "<") (thunk) (display ">")))))
    (check (result-output (ide-eval s "(display \"hi\") 1")) "<hi>")
    (check (result-values (ide-eval s "(+ 1 1)")) '(2))
    (ide-close s)))

;;; --- the record of changes (R-35) -----------------------------------------------------------

(define-test "R-35 an evaluation that defines is recorded: when, which session, who, the names, the text"
  (let* ((s (ide-session 'name "recorder"))
         (agent (ide-session 'name "the model" 'maker 'agent))
         (before (length (ide-changes))))
    (ide-eval s "(define (area2 r) (* r r)) (define k 2)")
    (let ((c (car (reverse (ide-changes)))))
      (check (change-session c) "recorder")
      (check (change-maker c) 'person)
      (check (change-kind c) 'evaluate)
      (check (change-names c) '("area2" "k"))
      (check (change-text c) "(define (area2 r) (* r r)) (define k 2)")
      (check-true (string? (change-time c))))
    ;; an evaluation that defines nothing is no change
    (ide-eval s "(+ 1 2)")
    (check (length (ide-changes)) (+ before 1))
    (ide-eval agent "(define (by-the-model) 1)")
    (check (change-maker (car (reverse (ide-changes)))) 'agent)
    ;; a running evaluation is recorded when it is answered
    (ide-eval s "[[(smalltalk Delay) forMilliseconds: 300] wait] (define late 1)" 'timeout 50)
    (check (length (ide-changes)) (+ before 2))
    (ide-wait s 5000)
    (check (change-names (car (reverse (ide-changes)))) '("late"))
    (ide-close s)
    (ide-close agent)))

(define-test "R-35 the record is kept in a file too"
  (let ((path (string-append [[(smalltalk FileLocator) temp] fullName] "/cog-lisp-ide-changes.log"))
        (s (ide-session 'name "logged")))
    (ide-log-to! path)
    (ide-eval s "(define (logged-one) 1)")
    (let ((text [[[path asFileReference] contents] asString]))
      (check-true (string-search text "logged-one"))
      (check-true (string-search text "\"logged\"")))
    (ide-log-to! #f)
    [[path asFileReference] ensureDelete]
    (ide-close s)))

(run-tests)
