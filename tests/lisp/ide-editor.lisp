;;; ide-editor.lisp -- the editor's procedures, step 3 of specs/34-morphic-ide.md
;;; (R-5 to R-9, R-32 to R-35; AC-3): the project's files, reading and saving a
;;; file in its own line endings, undoing a save, the top-level form at a place,
;;; and evaluating as part of a file, in its unit. No window is opened; the
;;; files are written in a temporary folder.
(load "../../lib/test.lisp")
(require 'ide)

(define here [[[[(smalltalk LispLoadPath) value] asFileReference] parent] fullName])
(define (temp name)
  (let ((d [[[(smalltalk FileLocator) temp] / name] asFileReference]))
    [d ensureDeleteAll] [d ensureCreateDirectory] d))
(define (write-raw! f text)
  [f ensureDelete]
  [f writeStreamDo: (procedure->block (lambda (s) [s nextPutAll: text]))]
  [f fullName])
(define (raw f) [[[f asFileReference] contents] asString])
(define crlf (string #\return #\newline))

(define-test "R-5 the project's files: the .lisp files under it, sorted, some folders left out"
  (let ((d (temp "cog-lisp-ide-files")))
    [[d / "sub"] ensureCreateDirectory]
    [[d / ".git"] ensureCreateDirectory]
    (write-raw! [d / "b.lisp"] "(define b 2)")
    (write-raw! [d / "a.lisp"] "(define a 1)")
    (write-raw! [[d / "sub"] / "c.lisp"] "(define c 3)")
    (write-raw! [[d / ".git"] / "x.lisp"] "")
    (write-raw! [d / "notes.txt"] "")
    (check (map (lambda (p) [[p asFileReference] basename]) (ide-project-files [d fullName]))
           '("a.lisp" "b.lisp" "c.lisp"))
    (check (ide-project-files [[d / "none"] fullName]) '())
    [d ensureDeleteAll]))

(define-test "R-8 a file is read with line feeds, and saved in its own line endings"
  (let* ((d (temp "cog-lisp-ide-save"))
         (windows (write-raw! [d / "w.lisp"] (string-append "(define x 1)" crlf "(define y 2)" crlf)))
         (unix (write-raw! [d / "u.lisp"] "(define x 1)\n")))
    (check (ide-read-file windows) (cons "(define x 1)\n(define y 2)\n" 'crlf))
    (check (ide-read-file unix) (cons "(define x 1)\n" 'lf))
    (ide-save-file windows "(define x 10)\n(define y 2)\n")
    (check (raw windows) (string-append "(define x 10)" crlf "(define y 2)" crlf))
    (ide-save-file unix "(define x 10)\n")
    (check (raw unix) "(define x 10)\n")
    ;; a new file: lf, or as asked
    (ide-save-file [[d / "new.lisp"] fullName] "a\nb\n")
    (check (raw [[d / "new.lisp"] fullName]) "a\nb\n")
    (ide-save-file [[d / "new2.lisp"] fullName] "a\n" 'ending 'crlf)
    (check (raw [[d / "new2.lisp"] fullName]) (string-append "a" crlf))
    ;; UTF-8
    (ide-save-file unix "(define g \"λ\")\n")
    (check (car (ide-read-file unix)) "(define g \"λ\")\n")
    [d ensureDeleteAll]))

(define-test "R-35 a save is recorded, with the text before, and undoes"
  (let* ((d (temp "cog-lisp-ide-undo"))
         (f (write-raw! [d / "f.lisp"] (string-append "(define v 1)" crlf))))
    (ide-save-file f "(define v 2)\n" 'session "the editor" 'maker 'agent)
    (let ((c (car (reverse (ide-changes)))))
      (check (change-kind c) 'save)
      (check (change-names c) (list f))
      (check (change-text c) "(define v 2)\n")
      (check (change-before c) "(define v 1)\n")
      (check (change-session c) "the editor")
      (check (change-maker c) 'agent)
      (ide-undo-change c)
      (check (raw f) (string-append "(define v 1)" crlf))      ; its line ending kept
      (check (change-kind (car (reverse (ide-changes)))) 'undo))
    (check-error (ide-undo-change (car (filter (lambda (c) (eq? (change-kind c) 'undo)) (ide-changes))))
                 "ide-undo-change: only a file saved can be undone")
    (check-false (change-before (vector "t" "s" 'person 'evaluate '() "x")))
    [d ensureDeleteAll]))

(define-test "R-9 the top-level form at a place, or the last one before it"
  (let ((text "(define a 1)\n\n(define (f x)\n  (* x 2))\n; a comment\n"))
    (check (ide-form-at text 0) '(0 . 12))
    (check (ide-form-at text 5) '(0 . 12))
    (check (ide-form-at text 20) '(14 . 38))                   ; inside f
    (check (ide-form-at text 13) '(0 . 12))                    ; between: the one before
    (check (ide-form-at text 45) '(14 . 38))                   ; in the comment after
    (check (substring text 14 38) "(define (f x)\n  (* x 2))")
    (check-false (ide-form-at "" 0))
    (check-false (ide-form-at "; only a comment" 3))
    (check (ide-form-at "  (g)" 0) '(2 . 5))))                 ; before the first: the first

(define-test "R-9 evaluating as part of a file: in its unit, loaded first"
  (let* ((d (temp "cog-lisp-ide-unit"))
         (f (write-raw! [d / "lib-e.lisp"] "(library ide-test-e (export twice))\n(define (%double x) (* 2 x))\n(define (twice x) (%double x))\n"))
         (s (ide-file-session f)))
    ;; loaded: its export answers
    (check (result-values (ide-eval s "(twice 4)")) '(8))
    ;; a define in the file's unit defines the library's own name, which sees its private one
    (ide-eval s "(define (thrice x) (+ x (%double x)))")
    (check (result-values (ide-eval (ide-session) "(ide-test-e:thrice 2)")) '(6))
    ;; the session is kept, whichever way the path is written
    (check-true (eq? (ide-file-session [f copyReplaceAll: "\\" with: "/"]) s))
    (check-true (and (find (lambda (e) (string=? (car e) f)) (ide-loaded-files)) #t))
    [d ensureDeleteAll]))

(define ide-program-ran #f)
(define-test "R-9 a program's file is not run to evaluate in it; a library's is loaded"
  (let* ((d (temp "cog-lisp-ide-program"))
         (f (write-raw! [d / "prog.lisp"] "(set! ide-program-ran #t)\n(read-line)\n"))
         (s (ide-file-session f)))
    (check-false ide-program-ran)
    (check (result-values (ide-eval s "(+ 1 2)")) '(3))
    [d ensureDeleteAll]))

(define-test "R-9 loading a file: its result, an error reported, not left at a break"
  (let* ((d (temp "cog-lisp-ide-load"))
         (good (write-raw! [d / "good.lisp"] "(define ide-loaded-value 41)\n(display \"loaded\")\n"))
         (bad (write-raw! [d / "bad.lisp"] "(car 5)\n")))
    (let ((r (ide-load-file good)))
      (check (result-status r) 'done)
      (check (result-output r) "loaded"))
    (check (eval 'ide-loaded-value) 41)
    (let ((r (ide-load-file bad)))
      (check (result-status r) 'error)
      (check-true (string? (result-report r))))
    [d ensureDeleteAll]))

(run-tests)
