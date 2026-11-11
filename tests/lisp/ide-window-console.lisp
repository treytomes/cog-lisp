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

;;; --- typing at the cursor (R-40) --------------------------------------------------

;; a key as the pane takes it: its Morphic key value, character, Ctrl, Alt
(define (press! p v c . mods)
  [p pressKey: v character: c control: (if (memq 'ctrl mods) #t #f) alt: (if (memq 'alt mods) #t #f)])
(define (press-text! p text) (for-each (lambda (c) (press! p (char->integer c) c)) (string->list text)))
(define (press-enter! p) (press! p 13 (integer->char 13)))
(define (sleep-ms n) [[(smalltalk Delay) forMilliseconds: n] wait])

(define-test "R-40 typing goes to the line at the prompt; Enter evaluates it"
  (let* ((p (repl)) (w [p open]))
    (press-text! p "(+ 1 2")
    (check [p inputText] "(+ 1 2")
    (check-true (string-suffix? "> (+ 1 2" (shown p)))         ; drawn at the cursor
    (press-text! p ")")
    (press-enter! p)
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "> (+ 1 2)\n3\n> "))
    [w close]))

(define-test "R-40 editing: the arrows, Home, End, Backspace and Delete"
  (let* ((p (repl)) (w [p open]))
    (press-text! p "(+ 1 2)")
    (press! p 28 (integer->char 28))                           ; left
    (press! p 8 (integer->char 8))                             ; backspace: the 2
    (press-text! p "40")
    (check [p inputText] "(+ 1 40)")
    (press! p 1 (integer->char 1))                             ; Home
    (press! p 127 (integer->char 127))                         ; Delete: the (
    (press-text! p "[")
    (press! p 4 (integer->char 4))                             ; End
    (press! p 8 (integer->char 8))
    (press-text! p "]")
    (check [p inputText] "[+ 1 40]")
    [w close]))

(define-test "R-40 a key that types no character comes as a key down, mapped to its key value"
  (define (value-of name) [(smalltalk LispTerminalView) keyValueFor: [(smalltalk KeyboardKey) perform: [name asSymbol]]])
  (check (map value-of '("left" "right" "up" "down" "home" "end" "backspace" "delete" "escape" "enter" "keypadEnter" "tab"))
         '(28 29 30 31 1 4 8 127 27 13 13 9))
  (check-true (smalltalk-nil? (value-of "space")))
  ;; Ctrl with a letter key: its letter
  (check [(smalltalk LispTerminalView) letterOf: [(smalltalk KeyboardKey) named: "C"]] #\c)   ; a letter key is named by its capital
  (check-true (smalltalk-nil? [(smalltalk LispTerminalView) letterOf: [(smalltalk KeyboardKey) left]])))

;; a key event as the GUI makes it: type (keyDown or keystroke), Morphic key value, key
(define (key-event type value key)
  (let ((e [[(smalltalk KeyboardEvent) new]
            setType: [type asSymbol] buttons: 0 position: [0 @ 0] keyValue: value charCode: value
            hand: [(smalltalk World) activeHand] stamp: 0]))
    [e key: key]
    e))

(define-test "R-40 keys go through the pane's own event handling, as in the GUI"
  (let* ((p (repl)) (w [p open]) (v [p terminalView]))
    ;; Enter as a key down, its key the one Pharo names
    [p inputText: "(+ 40 2)"]
    [v handleKeyDown: (key-event "keyDown" 13 [(smalltalk KeyboardKey) enter])]
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "> (+ 40 2)\n42\n"))
    ;; a key down whose key the table does not know, with Morphic's code for Enter
    [p inputText: "(* 6 7)"]
    [v handleKeyDown: (key-event "keyDown" 13 [(smalltalk KeyboardKey) named: "F13"])]
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "> (* 6 7)\n42\n"))
    ;; Backspace as a key down; a typed character as a key press
    [p inputText: "ab"]
    [v handleKeyDown: (key-event "keyDown" 8 [(smalltalk KeyboardKey) backspace])]
    (check [p inputText] "a")
    [v handleKeystroke: (key-event "keystroke" 122 [(smalltalk KeyboardKey) named: "Z"])]
    (check [p inputText] "az")
    ;; a key press of Enter, if one comes too, adds nothing
    [v handleKeystroke: (key-event "keystroke" 13 [(smalltalk KeyboardKey) enter])]
    (check [p inputText] "az")
    [w close]))

(define-test "R-40 Ctrl+Left and Ctrl+Right move a word"
  (let* ((p (repl)) (w [p open]))
    (press-text! p "(define long-name 42)")
    (press! p 28 (integer->char 28) 'ctrl)                    ; before 42
    (press! p 28 (integer->char 28) 'ctrl)                    ; before name
    (press-text! p "X")
    (check [p inputText] "(define long-Xname 42)")
    (press! p 29 (integer->char 29) 'ctrl)                    ; after name
    (press-text! p "Y")
    (check [p inputText] "(define long-XnameY 42)")
    [w close]))

(define-test "R-40 Up and Down go through the history when idle"
  (let* ((p (repl)) (w [p open]))
    (run! p "(+ 1 1)")
    (run! p "(+ 2 2)")
    (press! p 30 (integer->char 30))
    (check [p inputText] "(+ 2 2)")
    (press! p 30 (integer->char 30))
    (check [p inputText] "(+ 1 1)")
    (press! p 31 (integer->char 31))
    (check [p inputText] "(+ 2 2)")
    [w close]))

(define-test "R-40 while a program reads keys, Up and Down are its, not the history's"
  (let* ((p (repl)) (w [p open]))
    (run! p "(require 'console)")
    (run! p "(+ 1 1)")                                         ; a history to not go through
    (type! p "(choose \"Pick\" '(red green blue))")
    (check-true (await-keys p))
    (press! p 31 (integer->char 31))                           ; down
    (press! p 31 (integer->char 31))
    (press! p 30 (integer->char 30))                           ; up
    (press-enter! p)
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "Pick green\ngreen\n"))
    (check [p inputText] "")
    [w close]))

(define-test "R-40 Ctrl+C interrupts a running evaluation; paste types its text"
  (let* ((p (repl)) (w [p open]))
    (type! p "(let loop () (loop))")
    (sleep-ms 300)
    (press! p 99 #\c 'ctrl)
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "interrupted"))
    [p chooseRestart: "abort"]
    [p waitUntilIdle: 10000]
    [p paste: "(* 6 7)"]
    (check [p inputText] "(* 6 7)")
    (press-enter! p)
    (check-true [p waitUntilIdle: 10000])
    (check-true (has? (shown p) "42\n"))
    [w close]))

;;; --- finding the tools and the files (R-41) ------------------------------------------

(require "editor-services/geometry.lisp")

(define-test "R-41 ide-loaded-files: every file loaded, with its library"
  (let ((files (ide-loaded-files)))
    (check-true (and (find (lambda (e) (and (string-suffix? "geometry.lisp" (car e)) (eq? (cdr e) 'es-geometry))) files) #t))
    (check-true (and (find (lambda (e) (and (string-suffix? "ide-window-console.lisp" (car e)) (not (cdr e)))) files) #t))
    (check (map car files) (sort (map car files) string<?))))

(define-test "R-41 the loaded-files window lists them, shows one, and runs it in a new REPL"
  (let* ((f [(smalltalk LispFilesPresenter) new]) (w [f open])
         (items (vector->list [f items]))
         (geometry (find (lambda (e) (string-suffix? "geometry.lisp" (vector-ref e 0))) items)))
    (check-true (and geometry #t))
    (check (vector-ref geometry 1) "library es-geometry")
    [[f list] selectItem: geometry]
    (check-true (has? [[[f source] text] asString] "(define (area r)"))
    (let ((repl [f runSelected]))
      (check-true [repl waitUntilIdle: 10000])
      (check-true (has? [repl transcriptString] "(load "))
      [[repl window] close])
    [w close]))

(define-test "R-41 one cog-lisp menu: New REPL, Loaded files, Update"
  (let* ((spec [[(smalltalk PragmaMenuBuilder) pragmaKeyword: ["worldMenu" asSymbol] model: (smalltalk-nil)] menuSpec])
         (item [[spec items] detect: (lambda (i) [[i label] = "cog-lisp"]) ifNone: (lambda () #f)]))
    (check-true (and item #t))
    (check (map (lambda (i) [[i label] asString]) (vector->list [[[item subMenu] items] asArray]))
           '("New REPL" "Loaded files" "Update the image from the checkout"))))

(run-tests)
