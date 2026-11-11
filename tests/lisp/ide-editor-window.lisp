;;; ide-editor-window.lisp -- the editor window, step 3 of specs/34-morphic-ide.md
;;; (R-5 to R-11; AC-3), opened headless and driven through its presenter: the
;;; project's files in the tree, a tab for each file, unsaved edits marked, saving
;;; in the file's own line endings, Do it, Print it and Load file as part of the
;;; file, formatting, and the LISP styling. The files are in a temporary folder.
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
(define (select! p from to) (on-ui [[p code] selectionInterval: [from to: to]]))
(define (run! p action)                    ; a key's action, then its evaluation waited for
  (on-ui (action))
  [p waitUntilIdle: 30000])
(define (output e) (on-ui [e outputText]))
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
    (check-true (has? (output e) "saved w.lisp"))
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
    (check-true (has? (output e) "42"))
    ;; a selection is evaluated instead, in the file's unit: its private name is seen
    (let ((before (text p)))
      (set-text! p (string-append before "(%w-double 5)\n"))
      (select! p (+ (string-length before) 1) (+ (string-length before) 13)))
    (check-true (run! p (lambda () [p doIt])))
    (check-true (has? (output e) "10"))
    ;; an error is reported, and the session is not left at a break
    (set-text! p (string-append (text p) "(car 5)\n"))
    (let ((n (string-length (text p)))) (select! p (- n 7) (- n 1)))
    (check-true (run! p (lambda () [p doIt])))
    (check-true (has? (output e) "error: "))
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
    (check-true (has? (output e) "hello"))
    (check-true (has? (output e) "loaded l.lisp"))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-9 one evaluation at a time: another while one runs is refused"
  (let* ((d (temp "cog-lisp-editor-busy"))
         (f (write-raw! [d / "b.lisp"] "(define (spin n) (if (> n 0) (spin (- n 1)) 'spun))\n(spin 3000000)\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (on-ui [p loadFile] [p doIt])
    (check-true [p waitUntilIdle: 60000])
    (check-true (has? (output e) "busy: an evaluation is running"))
    (check-false [p isBusy])
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-11 Format lays the text out as format-source does"
  (let* ((d (temp "cog-lisp-editor-format"))
         (f (write-raw! [d / "f.lisp"] "(define (f x)   (* x\n 2))\n"))
         (e (editor)) (w (open! e))
         (p (open-file! e f)))
    (on-ui [p format])
    (check (text p) (format-source:format-source "(define (f x)   (* x\n 2))\n"))
    (close! w)
    [d ensureDeleteAll]))

(define-test "R-6 the styler styles LISP: comments, strings, keywords, parentheses"
  (let* ((s [(smalltalk LispStyler) new])
         (styled [s privateStyle: [(smalltalk Text) fromString: "(define x \"s\") ; c"]]))
    (check [[s styleFor: (vector 'comment 0 1)] asString] "comment")
    (check [[s styleFor: (vector 'string 0 1)] asString] "string")
    (check [[s styleFor: (vector 'keyword 0 1)] asString] "self")
    (check [[s styleFor: (vector 'open 0 1 0)] asString] "parenthesis")
    (check [[s styleFor: (vector 'open 0 1 2)] asString] "parenthesis2")
    (check [[s styleFor: (vector 'symbol 0 1)] asString] "default")
    ;; the comment and the string are styled differently from a name
    (check-false (equal? [[styled attributesAt: 4] printString] [[styled attributesAt: 17] printString]))
    (check-false (equal? [[styled attributesAt: 11] printString] [[styled attributesAt: 9] printString]))))

(define-test "R-11 the page's keys, each bound as a real key and as a typed one; its menu"
  (let* ((p [(smalltalk LispEditorPage) new])
         (entries (vector->list [[[[p code] actions] entries] asArray])))
    (check (map (lambda (a) [[a name] asString]) entries)
           '("save" "save-char" "do-it" "do-it-char" "print-it" "print-it-char"
             "load-file" "load-file-char" "format" "format-char"))
    (check-true (every (lambda (a) (not (smalltalk-nil? [a shortcutKey]))) entries))   ; each has its key
    (check (map (lambda (i) [[i name] asString])
                (append-map (lambda (g) (vector->list [[g menuItems] asArray]))
                            (vector->list [[[p contextMenu] menuGroups] asArray])))
           '("Do it" "Print it" "Load file" "Save" "Format" "Cut" "Copy" "Paste"))))

(define-test "the cog-lisp menu opens the editor"
  (check-true [[(smalltalk LispEditorPresenter) class] includesSelector: ["open" asSymbol]])
  (check-true (has? [[[(smalltalk LispIde) class] >> ["menuCommandOn:" asSymbol]] sourceCode] "LispEditorPresenter open")))

(run-tests)
