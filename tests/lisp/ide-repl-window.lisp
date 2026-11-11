;;; ide-repl-window.lisp -- the REPL window, step 2 of specs/34-morphic-ide.md
;;; (R-12 to R-16; AC-2), opened headless and driven through its presenter:
;;; Enter on a whole form and on an unfinished one, output as it is written,
;;; an error's restarts, interrupting, a line typed for a program that reads,
;;; the history, the console's colors, two windows at once. It evaluates through
;;; lib/ide.lisp's sessions, so its evaluations are recorded (R-35).
(load "../../lib/test.lisp")
(require 'ide)

(define (repl) [(smalltalk LispReplPresenter) new])
(define (type! p text) [p inputText: text] [p submit])
(define (run! p text) (type! p text) [p waitUntilIdle: 10000])
(define (shown p) [p transcriptString])
(define (sleep-ms n) [[(smalltalk Delay) forMilliseconds: n] wait])
(define (has? text part) (if (string-search text part) #t #f))

(define-test "R-12 Enter on a whole form evaluates it; its value is shown after it"
  (let* ((p (repl)) (w [p open]))
    (check-true (run! p "(+ 1 2)"))
    (check (shown p) "> (+ 1 2)\n3\n> ")                  ; and the prompt again
    (check [p inputText] "")
    (check-true (run! p "(define (sq x) (* x x)) (sq 5)"))
    (check-true (has? (shown p) "> (define (sq x) (* x x)) (sq 5)\n25\n"))
    [w close]))

(define-test "R-12 Enter on an unfinished form starts a new line instead"
  (let* ((p (repl)) (w [p open]))
    (type! p "(+ 1")
    (check [p inputText] "(+ 1\n")
    (check (shown p) "> (+ 1\n")                          ; typed at the prompt, not evaluated
    (check-true (run! p "(+ 1\n 2)"))
    (check-true (has? (shown p) "3\n"))
    [w close]))

(define-test "R-13 output appears as it is written, before the value"
  (let* ((p (repl)) (w [p open]))
    (check-true (run! p "(display \"hi there\") (newline) 42"))
    (check (shown p) "> (display \"hi there\") (newline) 42\nhi there\n42\n> ")
    [w close]))

(define-test "R-14 an error shows its report and its restarts; abort comes back"
  (let* ((p (repl)) (w [p open]))
    (check-true (run! p "(car 5)"))
    (check-true (has? (shown p) "error: "))
    (check [p level] 1)
    (check-true (member "abort" (vector->list [p restartNames])))
    [p chooseRestart: "abort"]
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "aborted\n"))
    (check [p level] 0)
    (check (vector->list [p restartNames]) '())
    [w close]))

(define-test "R-14 a restart that takes a value is put in the input to finish"
  (let* ((p (repl)) (w [p open]))
    (run! p "(+ 1 nope-not-bound)")
    (check-true (member "use-value" (vector->list [p restartNames])))
    [p chooseRestart: "use-value"]
    (check [p inputText] "(use-value )")
    (check-true (run! p "(use-value 5)"))
    (check-true (has? (shown p) "1> (use-value 5)\n6\n"))
    (check [p level] 0)
    [w close]))

(define-test "R-15 a runaway evaluation is interrupted; the window keeps working"
  (let* ((p (repl)) (w [p open]))
    (type! p "(let loop () (loop))")
    (sleep-ms 300)
    (check-true [p isBusy])
    [p interrupt]
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "interrupted"))
    [p chooseRestart: "abort"]
    [p waitUntilIdle: 10000]
    (check-true (run! p "(* 6 7)"))
    (check-true (has? (shown p) "42\n"))
    [w close]))

(define-test "a line typed while a program runs is for the program to read"
  (let* ((p (repl)) (w [p open]))
    (type! p "(read-line)")
    (sleep-ms 200)
    (check-true [p isBusy])
    (type! p "hello")
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "hello\n\"hello\"\n"))
    [w close]))

(define-test "the history: Up and Down go through the forms evaluated"
  (let* ((p (repl)) (w [p open]))
    (run! p "(+ 1 1)")
    (run! p "(+ 2 2)")
    [p historyBack]
    (check [p inputText] "(+ 2 2)")
    [p historyBack]
    (check [p inputText] "(+ 1 1)")
    [p historyForward]
    (check [p inputText] "(+ 2 2)")
    [p historyForward]
    (check [p inputText] "")
    [w close]))

(define-test "R-16 the console library's colors show, its other escapes are dropped"
  (let* ((esc (string (integer->char 27)))
         (text [(smalltalk LispIde) textFromTerminal: (string-append esc "[1;31mA" esc "[0mB" esc "[2J" esc "[3;1HC")]))
    (check [text asString] "ABC")
    (check-true [[[text attributesAt: 1] detect: (lambda (a) [a isKindOf: (smalltalk TextColor)]) ifNone: (lambda () #f)] notNil])
    (check-true [[text attributesAt: 1] includes: [(smalltalk TextEmphasis) bold]])
    (check [[text attributesAt: 2] size] 0))
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (run! p "(print-markup \"[red]warm[/] and plain\")")
    (let* ((s (shown p)) (i (string-search s "warm")))
      (check-true (has? s "warm and plain"))
      (check-true [[[[p transcriptText] attributesAt: (+ i 1)] detect: (lambda (a) [a isKindOf: (smalltalk TextColor)]) ifNone: (lambda () #f)] notNil])
      (check [[[p transcriptText] attributesAt: (+ i 6)] size] 0))
    [w close]))

(define-test "R-31 two windows at once keep their outputs apart"
  (let* ((p1 (repl)) (p2 (repl)) (w1 [p1 open]) (w2 [p2 open]))
    (type! p1 "(display \"one\") [[(smalltalk Delay) forMilliseconds: 400] wait] (display \"two\")")
    (sleep-ms 100)
    (check-true (run! p2 "(display \"x\")"))
    (check-true [p1 waitUntilIdle: 10000])
    (check-true (has? (shown p1) "onetwo"))
    (check-false (has? (shown p1) "x"))
    (check-true (has? (shown p2) "x"))
    (check-false (has? (shown p2) "one"))
    [w1 close]
    [w2 close]))

(define-test "R-35 what the window defines is recorded, as made by a person in the REPL"
  (let* ((p (repl)) (w [p open]))
    (run! p "(define (from-the-window) 1)")
    (let ((c (car (reverse (ide-changes)))))
      (check (change-names c) '("from-the-window"))
      (check (change-session c) "REPL")
      (check (change-maker c) 'person))
    [w close]))

(define-test "closing the window ends its session"
  (let* ((p (repl)) (w [p open]) (s [p session]))
    (check-true (memq s (ide-sessions)))
    [w close]
    (check-false (memq s (ide-sessions)))))

(run-tests)
