;;; ide-window-console.lisp -- the console library in a window, step 2c of
;;; specs/34-morphic-ide.md (R-39): the REPL window's transcript is an emulated
;;; terminal the size of its pane, so tables draw with their borders, prompts
;;; redraw in place and read keys typed in the window, and the console there is
;;; a terminal, interactive. Driven headless, keys given as a terminal sends them.
(load "../../lib/test.lisp")
(require 'ide)
(require 'console)

(define esc (string (integer->char 27)))
(define cr (string (integer->char 13)))
(define down (string-append esc "[B"))

(define (repl) [(smalltalk LispReplPresenter) new])
(define (type! p text) [p inputText: text] [p submit])
(define (run! p text) (type! p text) [p waitUntilIdle: 10000])
(define (shown p) [p transcriptString])
(define (has? text part) (if (string-search text part) #t #f))
(define (sleep-ms n) [[(smalltalk Delay) forMilliseconds: n] wait])
;; waits until the program running in p reads keys
(define (await-keys p)
  (let loop ((waited 0))
    (cond ([p wantsKeys] #t)
          ((> waited 5000) #f)
          (else (sleep-ms 50) (loop (+ waited 50))))))
;; a form that reads keys, the keys typed once it does, and its result shown
(define (with-keys! p form keys)
  (type! p form)
  (check-true (await-keys p))
  [p typeKeys: keys]
  [p waitUntilIdle: 10000])

(define-test "R-39 keys in a window are what a terminal sends"
  (define (keys v c ctrl alt) [(smalltalk LispIde) keysForValue: v character: c control: ctrl alt: alt])
  (check (keys 30 (integer->char 30) #f #f) (string-append esc "[A"))
  (check (keys 31 (integer->char 31) #f #f) down)
  (check (keys 13 (integer->char 13) #f #f) cr)
  (check (keys 8 (integer->char 8) #f #f) (string (integer->char 127)))
  (check (keys 27 (integer->char 27) #f #f) esc)
  (check (keys 99 #\c #t #f) (string (integer->char 3)))          ; Ctrl+C
  (check (keys 120 #\x #f #t) (string-append esc "x"))            ; Alt+x
  (check (keys 97 #\a #f #f) "a")
  (check (keys 0 (integer->char 0) #f #f) ""))                    ; Control alone

(define-test "R-39 the console in a window is a terminal, interactive, the pane's size"
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (run! p "(list (console-width) (hash-table-ref (console-capabilities) 'interactive?) (hash-table-ref (console-capabilities) 'terminal?))")
    (check-true (has? (shown p) (string-append "(" (number->string [p columns]) " #t #t)")))
    [w close]))

(define-test "R-39 a table draws with its borders"
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (run! p "(render (table 'columns '(\"a\" \"b\") 'rows '((1 2))))")
    (check-true (has? (shown p) "┌───┬───┐\n│ a │ b │"))
    [w close]))

(define-test "R-39 choose reads the arrow keys and Enter, and redraws in place"
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (with-keys! p "(choose \"Pick\" '(red green blue))" (string-append down down cr))
    (check-true (has? (shown p) "Pick blue\nblue\n"))
    (check-false (has? (shown p) "> red"))                     ; the list went; only the answer stays
    [w close]))

(define-test "R-39 ask reads keys, with backspace; confirm reads one"
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (with-keys! p "(ask \"Name?\")" (string-append "ab" (string (integer->char 127)) "c" cr))
    (check-true (has? (shown p) "Name? ac\n\"ac\"\n"))
    (with-keys! p "(confirm \"Go?\")" "y")
    (check-true (has? (shown p) "Go? [y/n] y\n#t\n"))
    [w close]))

(define-test "R-39 Escape cancels a prompt in a window"
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (with-keys! p "(guard (e ((prompt-cancelled? e) 'cancelled)) (choose \"Pick\" '(a b)))" esc)
    (check-true (has? (shown p) "cancelled\n"))
    [w close]))

(define-test "R-39 Enter in the input, while a program reads keys, sends what was typed as keys"
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (type! p "(ask \"Name?\")")
    (check-true (await-keys p))
    (type! p "Ann")
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "\"Ann\"\n"))
    [w close]))

(define-test "R-39 output longer than the pane scrolls into the transcript, none lost"
  (let* ((p (repl)) (w [p open]))
    (run! p (string-append "(do ((i 0 (+ i 1))) ((= i " (number->string (+ [p rows] 20)) ")) (display i) (newline))"))
    (let ((s (shown p)))
      (check-true (has? s "> (do"))
      (check-true (has? s "\n0\n1\n2\n"))
      (check-true (has? s (string-append "\n" (number->string (+ [p rows] 19)) "\n"))))
    [w close]))

(run-tests)
