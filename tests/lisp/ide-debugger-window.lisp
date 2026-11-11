;;; ide-debugger-window.lisp -- errors in the windows, step 5 of
;;; specs/34-morphic-ide.md (R-25; AC-5), headless, in the UI process: a REPL
;;; window's error shows its LISP frames and offers Debug; the LISP pane for
;;; Pharo's debugger lists the same frames, each with its source and locals; a
;;; session whose process has ended is replaced. Pharo's debugger itself is not
;;; opened: closing it is a person's act.
(load "../../lib/test.lisp")
(require 'ide)

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
(define (has? text part) (if (string-search text part) #t #f))
(define (strings v) (map (lambda (s) [s asString]) (vector->list v)))

(define dir (temp "cog-lisp-debugger-window"))
(define file (write-raw! [dir / "dbg.lisp"] "(define (dbg-g x)\n  (vector-ref x 0))\n\n(define (dbg-f n)\n  (+ 1 (dbg-g (* n 2))))\n"))   ; not a tail call: a tail call leaves no frame
(ide-load-file file)

(define-test "R-25 a REPL window's error: its LISP frames below the report, and Debug"
  (let* ((r [(smalltalk LispReplPresenter) new]) (w (on-ui [r open])))
    (on-ui [r inputText: "(dbg-f 5)"] [r submit])
    (check-true [r waitUntilIdle: 20000])
    (let ((shown [r transcriptString]))
      (check-true (has? shown "error: vector-ref: not a vector: 10\n  in vector-ref\n  in dbg-g  dbg.lisp:1\n  in dbg-f  dbg.lisp:4\n  in the top-level form\n")))
    (let ((labels (strings (on-ui [r barLabels]))))
      (check-true (and (member "abort" labels) #t))
      (check (car (reverse labels)) "Debug"))
    (on-ui [r chooseRestart: "abort"])
    (check-true [r waitUntilIdle: 20000])
    (check (strings (on-ui [r barLabels])) '())                             ; no break, no Debug
    (on-ui [w close])))

(define-test "R-25 the LISP pane: the frames, each with its source and locals"
  (let* ((s (ide-session)))
    (ide-eval s "(dbg-f 5)")
    (let ((pane (on-ui [(smalltalk LispDebuggerPane) new])))
      (on-ui [pane showContext: [s errorContext]])
      (check (strings (on-ui [pane frameNames])) '("vector-ref" "dbg-g" "dbg-f" "top level"))
      (on-ui [pane selectFrame: 2])
      (check (on-ui [pane sourceText]) "(define (dbg-g x)\n  (vector-ref x 0))")
      (check-true (has? (on-ui [pane localsText]) "= 10"))                 ; its argument
      (on-ui [pane selectFrame: 4])
      (check (on-ui [pane sourceText]) "; a top-level form")
      (check-true (string-suffix? "dbg.lisp:4" (on-ui [pane labelFor: [[pane instVarNamed: "frames"] at: 3]]))))
    (ide-close s)))

(define-test "R-25 the pane is a debugger extension, shown in Pharo's debugger"
  (check-true [[[(smalltalk TStDebuggerExtension) users] asArray] includes: (smalltalk LispDebuggerPane)])
  (check-true [(smalltalk LispDebuggerPane) showInDebugger])
  (check [[[(smalltalk LispDebuggerPane) new] debuggerExtensionToolName] asString] "LISP"))

(define-test "Debug with no break opens nothing"
  (let ((s (ide-session)))
    (check-true (smalltalk-nil? [(smalltalk LispIde) debug: s]))
    (ide-close s)))

(define-test "a session whose process has ended is replaced at the next evaluation"
  (let* ((r [(smalltalk LispReplPresenter) new]) (w (on-ui [r open])))
    (on-ui [r inputText: "(+ 1 2)"] [r submit])
    (check-true [r waitUntilIdle: 20000])
    (let ((old (on-ui [r session])))
      [[old process] terminate]
      (on-ui [r inputText: "(+ 2 3)"] [r submit])
      (check-true [r waitUntilIdle: 20000])
      (check-true (has? [r transcriptString] "5\n"))
      (check-false (eq? old (on-ui [r session]))))
    (on-ui [w close])))

(run-tests)
[dir ensureDeleteAll]
