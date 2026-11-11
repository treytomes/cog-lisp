;;; ide-editor-window.lisp -- the editor window, step 3 of specs/34-morphic-ide.md
;;; (R-5 to R-11; AC-3), opened headless and driven through its presenter: the
;;; project's files in the tree, a tab for each file, unsaved edits marked, saving
;;; in the file's own line endings, Do it, Print it and Load file as part of the
;;; file in the tab's REPL, Run in a REPL window of its own, the toolbar and the
;;; status line, formatting, and the LISP styling. The files are in a temporary
;;; folder.
;;; Every change to a window is made in the UI process (on-ui), as a key or a
;;; click makes it: from another process it can land in the middle of a layout.
(load "../../lib/test.lisp")
(require 'ide)
(require 'format-source)

(define-syntax on-ui
  (syntax-rules ()
    ((_ e ...) [(smalltalk LispIde) onUi: (procedure->block (lambda () e ...))])))

(define (temp name)
  (let ((d [[[(smalltalk FileLocator) temp] / name] asFileReference]))
    [d ensureDeleteAll] [d ensureCreateDirectory] d))
(define (write-raw! f text)
  [f ensureDelete]
  [f writeStreamDo: (procedure->block (lambda (s) [s nextPutAll: text]))]
  [f fullName])
(define (raw f) [[[f asFileReference] contents] asString])
(define crlf (string #\return #\newline))
(define (has? text part) (if (string-search text part) #t #f))
(define (editor) [(smalltalk LispEditorPresenter) new])
(define (open! e) (on-ui [e open]))
(define (close! w) (on-ui [w close]))
(define (open-file! e path) (on-ui [e openFile: path]))
(define (text p) (on-ui [p text]))
(define (set-text! p s) (on-ui [p text: s]))
(define (cursor! p n) (on-ui [[p code] selectionInterval: [n to: (- n 1)]]))  ; a cursor: an empty selection
(define (caret! p offset) (cursor! p (+ offset 1)))                         ; before the character at offset
(define (select! p from to) (on-ui [[p code] selectionInterval: [from to: to]]))
(define (run! p action)                    ; a key's action, then its evaluation waited for
  (on-ui (action))
  [p waitUntilIdle: 30000])
(define (status e) (on-ui [e statusText]))                 ; what the last action did
(define (shown p) (on-ui [[p repl] transcriptString]))    ; the tab's REPL
(define (names refs) (map (lambda (r) [r basename]) (vector->list [refs asArray])))

(define-test "R-5 the tree shows the folder's .lisp files and the folders holding them"
  (let ((d (temp "cog-lisp-editor-tree")) (e (editor)))
    [[d / "sub"] ensureCreateDirectory]
    [[d / "empty"] ensureCreateDirectory]
    [[d / "node_modules"] ensureCreateDirectory]
    (write-raw! [d / "b.lisp"] "(define b 2)\n")
    (write-raw! [d / "a.lisp"] "(define a 1)\n")
    (write-raw! [d / "notes.txt"] "")
    (write-raw! [[d / "sub"] / "c.lisp"] "(define c 3)\n")
    (write-raw! [[d / "node_modules"] / "x.lisp"] "")
    [e folder: [d fullName]]
    (check (names [e childrenOf: d]) '("sub" "a.lisp" "b.lisp"))
    (check (names [e childrenOf: [d / "sub"]]) '("c.lisp"))
    [d ensureDeleteAll]))

(define-test "R-5 a file opens in a tab of its own, once"
  (let* ((d (temp "cog-lisp-editor-tabs"))
         (a (write-raw! [d / "a.lisp"] "(define a 1)\n"))
         (b (write-raw! [d / "b.lisp"] "(define b 2)\n"))
         (e (editor)) (w (open! e)))
    (let ((pa (open-file! e a)) (pb (open-file! e b)))
      (check (text pa) "(define a 1)\n")
      (check (text pb) "(define b 2)\n")
      (check-true (eq? (open-file! e [a copyReplaceAll: "\\" with: "/"]) pa))
      (check [[e pages] size] 2))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-8 an edit marks the tab; saving writes the file in its line endings"
  (let* ((d (temp "cog-lisp-editor-save"))
         (f (write-raw! [d / "w.lisp"] (string-append "(define x 1)" crlf)))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (check (text p) "(define x 1)\n")                    ; read with line feeds
    (check-false (on-ui [p isDirty]))
    (check (on-ui [p title]) "w.lisp")
    (set-text! p "(define x 2)\n")
    (check-true (on-ui [p isDirty]))
    (check (on-ui [p title]) "w.lisp *")
    (on-ui [p save])
    (check-false (on-ui [p isDirty]))
    (check (raw f) (string-append "(define x 2)" crlf))  ; written as it was
    (check-true (has? (status e) "saved w.lisp"))
    (check (change-kind (car (reverse (ide-changes)))) 'save)
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-9 Do it evaluates the form at the cursor as part of the file"
  (let* ((d (temp "cog-lisp-editor-doit"))
         (f (write-raw! [d / "lib-w.lisp"]
                        "(library ide-window-w (export w-twice))\n(define (%w-double x) (* 2 x))\n(define (w-twice x) (%w-double x))\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (set-text! p (string-append (text p) "(w-twice 21)\n"))
    (cursor! p (- (string-length (text p)) 3))
    (check-true (run! p (lambda () [p doIt])))
    (check-true (has? (shown p) "> (w-twice 21)\n42\n"))     ; its form, then its value
    ;; a selection is evaluated instead, in the file's unit: its private name is seen
    (let ((before (text p)))
      (set-text! p (string-append before "(%w-double 5)\n"))
      (select! p (+ (string-length before) 1) (+ (string-length before) 13)))
    (check-true (run! p (lambda () [p doIt])))
    (check-true (has? (shown p) "(%w-double 5)\n10\n"))
    ;; an error is reported, and the session is not left at a break
    (set-text! p (string-append (text p) "(car 5)\n"))
    (let ((n (string-length (text p)))) (select! p (- n 7) (- n 1)))
    (check-true (run! p (lambda () [p doIt])))
    (check-true (has? (shown p) "error: "))
    (check-true (member "abort" (vector->list [[p repl] restartNames])))   ; at a break, as a REPL is
    (on-ui [[p repl] chooseRestart: "abort"])
    (check-true [p waitUntilIdle: 20000])
    (check (result-values (ide-eval [p session] "(w-twice 1)")) '(2))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-9 Print it writes the value after the form"
  (let* ((d (temp "cog-lisp-editor-print"))
         (f (write-raw! [d / "p.lisp"] "(+ 1 2)\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (cursor! p 2)
    (check-true (run! p (lambda () [p printIt])))
    (check (text p) "(+ 1 2)\n;; => 3\n")
    (check-true (on-ui [p isDirty]))
    (check (raw f) "(+ 1 2)\n")                          ; not saved by it
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-9 Load file evaluates the whole text as part of the file"
  (let* ((d (temp "cog-lisp-editor-load"))
         (f (write-raw! [d / "l.lisp"] "(define editor-window-loaded 1)\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (set-text! p "(define editor-window-loaded 2)\n(display \"hello\")\n")
    (check-true (run! p (lambda () [p loadFile])))
    (check (eval 'editor-window-loaded) 2)
    (check-true (has? (shown p) "; load l.lisp\nhello"))      ; the label, not the whole text
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-9 one evaluation at a time: another while one runs is refused"
  (let* ((d (temp "cog-lisp-editor-busy"))
         (f (write-raw! [d / "b.lisp"] "(define (spin n) (if (> n 0) (spin (- n 1)) 'spun))\n(spin 3000000)\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (on-ui [p loadFile] [p doIt])
    (check-true [p waitUntilIdle: 60000])
    (check-true (has? (status e) "busy: an evaluation is running"))
    (check-false [p isBusy])
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-9 Do it in a program that reads its input: the program is not run first"
  (let* ((d (temp "cog-lisp-editor-program"))
         (f (write-raw! [d / "echo.lisp"]
                        "(let loop ((line (read-line)))\n  (unless (eof-object? line) (loop (read-line))))\n(display \"end of input\")\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (let ((n (string-length (text p))))
      (select! p (- n 24) (- n 1)))
    (check (on-ui [[p text] copyFrom: (- (string-length (text p)) 24) to: (- (string-length (text p)) 1)])
           "(display \"end of input\")")
    (check-true (run! p (lambda () [p doIt])))
    (check-true (has? (shown p) "end of input"))
    (check-false [p isBusy])
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-15 Interrupt stops an evaluation; the page evaluates again after"
  (let* ((d (temp "cog-lisp-editor-interrupt"))
         (f (write-raw! [d / "loop.lisp"] "(let loop () (loop))\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (on-ui [p loadFile])
    (check-false [p waitUntilIdle: 500])                 ; still running
    (check-true [p isBusy])
    (on-ui [p interrupt])
    (check-true [p waitUntilIdle: 20000])
    (check-true (has? (shown p) "error: "))
    (check-false [p isBusy])
    (on-ui [[p repl] chooseRestart: "abort"])
    (check-true [p waitUntilIdle: 20000])
    (set-text! p "(+ 40 2)\n")
    (cursor! p 1)
    (check-true (run! p (lambda () [p doIt])))
    (check-true (has? (shown p) "42"))
    (on-ui [p interrupt])
    (check-true (has? (status e) "nothing to interrupt"))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-44 the tab's REPL: a program reads what is typed there; its prompt evaluates in the file"
  (let* ((d (temp "cog-lisp-editor-pane"))
         (f (write-raw! [d / "lib-pane.lisp"]
                        "(library ide-window-pane (export greet))\n(define (%who) \"pane\")\n(define (greet) (string-append \"hello, \" (read-line)))\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f))
         (r [p repl]))
    (check-true (smalltalk-nil? [r instVarNamed: "session"]))   ; no session until it evaluates
    (set-text! p (string-append (text p) "(greet)\n"))
    (cursor! p (- (string-length (text p)) 3))
    (on-ui [p doIt])
    (check-false [p waitUntilIdle: 500])                 ; waiting for its line
    (on-ui [r inputText: "world"] [r submit])
    (check-true [p waitUntilIdle: 20000])
    (check-true (has? (shown p) "\"hello, world\""))
    ;; typed at the prompt: part of the file, its private name seen
    (on-ui [r inputText: "(%who)"] [r submit])
    (check-true [r waitUntilIdle: 20000])
    (check-true (has? (shown p) "(%who)\n\"pane\""))
    ;; closing the window leaves the file's session open
    (close! w)
    (check-true (and (memq [p session] (ide-sessions)) #t))
    [d ensureDeleteAll]))

(define-test "R-43 Run: the file as saved, in a REPL window of its own, reading what is typed there"
  (let* ((d (temp "cog-lisp-editor-run"))
         (f (write-raw! [d / "echo.lisp"]
                        "(display (string-upcase (read-line)))\n(newline)\n(display \"end of input\")\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (set-text! p "(display \"not saved\")\n")
    (let ((run (on-ui [p run])))
      (check-true (has? (status e) "running echo.lisp as saved: its unsaved edits are not in it"))
      (check-true (eq? run [e lastRun]))
      (check-false [run waitUntilIdle: 500])           ; reading its line
      (on-ui [run inputText: "hello"] [run submit])
      (check-true [run waitUntilIdle: 20000])
      (check-true (has? [run transcriptString] "HELLO\nend of input"))
      (check-false (has? [run transcriptString] "not saved"))
      (on-ui [[run window] close]))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-42 the toolbar acts on the tab chosen; the status line says what it did"
  (let* ((d (temp "cog-lisp-editor-toolbar"))
         (a (write-raw! [d / "a.lisp"] "(define toolbar-a 1)\n"))
         (b (write-raw! [d / "b.lisp"] "(define toolbar-b 2)\n"))
         (e (editor)) (w (open! e))
         (items (vector->list [[[e toolbar] items] asArray]))
         (button (lambda (label) (find (lambda (i) (string=? [[i label] asString] label)) items))))
    (check (map (lambda (i) [[i label] asString]) items) '("Run" "Load" "Save" "Format" "Interrupt"))
    (on-ui [(button "Save") click])
    (check-true (has? (status e) "no file is open"))
    (let* ((pa (open-file! e a)) (pb (open-file! e b)))
      (check-true (eq? (on-ui [e selectedPage]) pb))
      (on-ui [(button "Load") click])
      (check-true [pb waitUntilIdle: 20000])
      (check (eval 'toolbar-b) 2)
      (open-file! e a)                                   ; its tab chosen again
      (set-text! pa "(define toolbar-a 10)\n")
      (on-ui [(button "Save") click])
      (check (raw a) "(define toolbar-a 10)\n")
      (check-true (has? (status e) "saved a.lisp"))
      (on-ui [(button "Interrupt") click])
      (check-true (has? (status e) "nothing to interrupt")))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-11 Format lays the text out as format-source does"
  (let* ((d (temp "cog-lisp-editor-format"))
         (f (write-raw! [d / "f.lisp"] "(define (f x)   (* x\n 2))\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (on-ui [p format])
    (check (text p) (format-source:format-source "(define (f x)   (* x\n 2))\n" 'spaces 1))  ; as the file indents
    (set-text! p "(define (f x)\n\t(* x\n 2))\n")
    (on-ui [p format])
    (check (text p) "(define (f x)\n\t(* x 2)\n)\n")                           ; tabs, kept
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-10 problems: underlined in the text, listed beside the REPL, gone once fixed"
  (let* ((d (temp "cog-lisp-editor-problems"))
         (f (write-raw! [d / "prob.lisp"] "(define (f x) (frobnicate x))\n(if)\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (on-ui [p checkNow])
    (check (map (lambda (pr) [[pr at: 4] asString]) (vector->list (on-ui [p problems])))
           '("unbound variable: frobnicate" "if: bad syntax: (if)"))
    (check (on-ui [[[[p bottom] pages] at: 2] title]) "Problems (2)")
    (check (on-ui [[[p bottom] pages] size]) 2)
    (check (map (lambda (i) (on-ui [p describeProblem: i])) (vector->list (on-ui [p problems])))
           '("line 1: warning: unbound variable: frobnicate" "line 2: error: if: bad syntax: (if)"))
    ;; underlined in the text, the error in red too
    (let* ((styled (on-ui [[[[[p code] adapter] widget] textArea] text]))
           (underline [[(smalltalk TextEmphasis) underlined] printString])
           (underlined? (lambda (i) (has? [[[styled attributesAt: i] asArray] printString] underline))))
      (check-true (underlined? 18))                                ; frobnicate
      (check-false (underlined? 3))                                ; define
      (check-true (underlined? 33)))                               ; (if)
    ;; a problem chosen selects it
    (on-ui [p selectFrom: 15 to: 25])
    (check (on-ui [[[p code] selectionInterval] printString]) "(16 to: 25)")
    ;; a check styles again, and leaves the selection where it was
    (on-ui [p checkNow])
    (check (on-ui [[[p code] selectionInterval] printString]) "(16 to: 25)")
    ;; fixed: none
    (set-text! p "(define (f x) (car x))\n")
    (on-ui [p checkNow])
    (check (vector->list (on-ui [p problems])) '())
    (check (on-ui [[[[p bottom] pages] at: 2] title]) "Problems")
    ;; and checked by itself once the text has rested
    (set-text! p "(define (g x) (zork x))\n")
    [[(smalltalk Delay) forMilliseconds: 1500] wait]
    (check (on-ui [[p problems] size]) 1)
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-10 the documentation of the name at the cursor, in the status line"
  (let* ((d (temp "cog-lisp-editor-describe"))
         (f (write-raw! [d / "doc.lisp"] "(string-append \"a\" \"b\")\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (cursor! p 4)
    (check-true (string-prefix? "(string-append" (status e)))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-10 completion: one name inserted, several offered"
  (let* ((d (temp "cog-lisp-editor-complete"))
         (f (write-raw! [d / "c.lisp"] "(string- \"a\")\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (caret! p 8)
    (check-true (and (member "string-append" (vector->list (on-ui [p completions]))) #t))
    (on-ui [p complete])
    (let ((offered (vector->list (on-ui [p choices]))))
      (check-true (> (length offered) 3))
      (check-true (and (member "string-append" offered) #t))
      (check-true (every (lambda (l) (string-prefix? "string-" l)) offered)))
    (on-ui [p choose: "string-append"])
    (check (text p) "(string-append \"a\")\n")
    (check (on-ui [p cursorOffset]) 14)                            ; after the name
    ;; a name only one completion fits is completed at once
    (set-text! p "(call-with-val 1)\n")
    (caret! p 14)
    (on-ui [p complete])
    (check (text p) "(call-with-values 1)\n")
    (caret! p 0)
    (on-ui [p complete])
    (check (status e) "nothing to complete here")
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-10 go to definition: the file opened, the definition selected; a built-in, its documentation"
  (let* ((d (temp "cog-lisp-editor-goto"))
         (defs (write-raw! [d / "defs.lisp"] (string-append "; the definitions" crlf crlf "(define (goto-target x)" crlf "  x)" crlf)))
         (use (write-raw! [d / "use.lisp"] "(goto-target 1)\n(car '(1))\n"))
         (e (editor)) (w (open! e)))
    [e folder: [d fullName]]
    (let ((p (open-file! e use)))
      (cursor! p 3)
      (on-ui [p goToDefinition])
      (let ((target (on-ui [e selectedPage])))
        (check (on-ui [target name]) "defs.lisp")
        (let* ((sel (on-ui [[target code] selectionInterval]))
               (t (text target)))
          (check (substring t (- [sel first] 1) [sel last]) "(define (goto-target x)\n  x)")))  ; found in a CRLF file
      (on-ui [e openFile: use])
      (cursor! p 18)
      (on-ui [p goToDefinition])
      (check-true (string-prefix? "defined in the image, with no file here: (car" (status e))))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-7 Enter indents the new line as the file does"
  (let* ((d (temp "cog-lisp-editor-enter"))
         (f (write-raw! [d / "i.lisp"] "(define (f x)\n    (let ((a 1))"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (caret! p (string-length (text p)))
    (on-ui [p newlineAndIndent])
    (check (text p) "(define (f x)\n    (let ((a 1))\n        ")      ; four spaces a level, as the file
    (caret! p 13)
    (on-ui [p newlineAndIndent])
    (check (substring (text p) 0 18) "(define (f x)\n    ")
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-8 a file changed on disk: reloaded; with unsaved edits, reported and both kept"
  (let* ((d (temp "cog-lisp-editor-disk"))
         (f (write-raw! [d / "disk.lisp"] "(define v 1)\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (check-true [e isWatching])                                    ; while the window is open
    (write-raw! [f asFileReference] "(define v 2)\n")
    (on-ui [e checkFilesOnDisk])
    (check (text p) "(define v 2)\n")
    (check-false (on-ui [p isDirty]))
    (check-true (has? (status e) "reloaded disk.lisp: it changed on disk"))
    ;; edited here, then changed there: these edits kept, the change reported
    (set-text! p "(define v 3)\n")
    (write-raw! [f asFileReference] "(define v 4)\n")
    (on-ui [e checkFilesOnDisk])
    (check (text p) "(define v 3)\n")
    (check-true (on-ui [p hasDiskConflict]))
    (check (on-ui [p title]) "disk.lisp * (changed on disk)")
    (check-true (has? (status e) "changed on disk while it has unsaved edits"))
    ;; Reload from disk takes the file's
    (on-ui [p reloadFromDisk])
    (check (text p) "(define v 4)\n")
    (check-false (on-ui [p hasDiskConflict]))
    (check (on-ui [p title]) "disk.lisp")
    ;; or Save keeps these
    (set-text! p "(define v 5)\n")
    (write-raw! [f asFileReference] "(define v 6)\n")
    (on-ui [e checkFilesOnDisk])
    (on-ui [p save])
    (check (raw f) "(define v 5)\n")
    (check-false (on-ui [p hasDiskConflict]))
    (close! w)
    (check-false [e isWatching])
    [d ensureDeleteAll]))

(define-test "R-6 the styler styles LISP: comments, strings, keywords, parentheses"
  (let* ((s [(smalltalk LispStyler) new])
         (styled [s privateStyle: [(smalltalk Text) fromString: "(define x \"s\") ; c"]]))
    (check [[s styleFor: (vector 'comment 0 1)] asString] "lispComment")
    (check [[s styleFor: (vector 'string 0 1)] asString] "lispString")
    (check [[s styleFor: (vector 'keyword 0 1)] asString] "lispKeyword")
    (check [[s styleFor: (vector 'open 0 1 0)] asString] "lispParen1")
    (check [[s styleFor: (vector 'open 0 1 2)] asString] "lispParen3")
    (check [[s styleFor: (vector 'close 0 1 3)] asString] "lispParen1")      ; three colors, round
    (check [[s styleFor: (vector 'symbol 0 1)] asString] "lispDefault")
    ;; cog-lisp's own colors, Dark+ on a dark theme
    (let ((dark [(smalltalk LispStyler) paletteForDark: #t]))
      (check [[[[[dark at: ["lispString" asSymbol]] first] color] asHexString] asUppercase] "CE9178")
      (check [[[dark at: ["lispComment" asSymbol]] size] printString] "2"))  ; and italic
    (check [[[[[[(smalltalk LispStyler) paletteForDark: #f] at: ["lispString" asSymbol]] first] color] asHexString] asUppercase] "A31515")
    ;; the comment and the string are styled differently from a name
    (check-false (equal? [[styled attributesAt: 4] printString] [[styled attributesAt: 17] printString]))
    (check-false (equal? [[styled attributesAt: 11] printString] [[styled attributesAt: 9] printString]))))

(define-test "R-11 the page's actions: its menu, each with its key, the typed key too"
  (let* ((p [(smalltalk LispEditorPage) new])
         (entries (vector->list [[[[p code] actions] entries] asArray]))
         (shown (filter (lambda (a) [a isVisible]) entries)))
    (check (map (lambda (a) [[a name] asString]) shown)
           '("Run" "Do it" "Print it" "Inspect it" "Load file" "Interrupt" "Save" "Format"
             "Complete" "Go to definition" "Reload from disk" "Cut" "Copy" "Paste"))
    (check (map (lambda (a) [[a name] asString]) (remove (lambda (a) [a isVisible]) entries))
           '("run-typed" "do-it-typed" "print-it-typed" "inspect-it-typed" "load-file-typed" "save-typed" "format-typed"
             "complete-typed" "go-to-definition-typed" "newline" "newline-typed"))       ; Enter: a key only
    (check (length (filter (lambda (a) [a hasShortcutKey]) entries)) 20)))  ; Rubric's own keys cut, copy, paste

(define-test "R-11 a right click builds the menu: the page's actions only"
  (let* ((d (temp "cog-lisp-editor-menu"))
         (f (write-raw! [d / "m.lisp"] "(+ 1 2)\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f))
         (menu (on-ui [[[p code] adapter] codePaneMenu: #f shifted: #f])))
    (check (map (lambda (i) [[i contents] asString]) (vector->list [[menu items] asArray]))
           '("Run" "Do it" "Print it" "Inspect it" "Load file" "Interrupt" "Save" "Format"
             "Complete" "Go to definition" "Reload from disk" "Cut" "Copy" "Paste"))
    (close! w)
    [d ensureDeleteAll]))

(define-test "the cog-lisp menu opens the editor"
  (check-true [[(smalltalk LispEditorPresenter) class] includesSelector: ["open" asSymbol]])
  (check-true (has? [[[(smalltalk LispIde) class] >> ["menuCommandOn:" asSymbol]] sourceCode] "LispEditorPresenter open")))

(run-tests)
