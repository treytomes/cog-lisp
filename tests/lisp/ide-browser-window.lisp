;;; ide-browser-window.lisp -- the browser window, step 4a of
;;; specs/34-morphic-ide.md (R-17 to R-21; AC-4), opened headless and driven
;;; through its presenter in the UI process: the groups, a library's
;;; definitions, a definition's source, documentation, callers, callees and
;;; disassembly, search, browsing by name, saving a definition back into its
;;; file, a stale one opened in the editor, and the editor's way in.
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

(define dir (temp "cog-lisp-browser-window"))
(define lib-file
  (write-raw! [dir / "bwlib.lisp"]
              "(library bw-lib (export bw-twice))\n\n(define (%bw-double x)\n  \"(%bw-double x)\nx and x.\"\n  (* 2 x))\n\n(define (bw-twice x) (%bw-double x))\n"))
(ide-load-file lib-file)

(define (browser) [(smalltalk LispBrowserPresenter) new])
(define (open! b) (on-ui [b open]))
(define (close! w) (on-ui [w close]))

(define-test "R-17 the groups, and a library's definitions: exports first"
  (let* ((b (browser)) (w (open! b)))
    (let ((groups (strings (on-ui [b groupNames]))))
      (check (car groups) "Special forms")
      (check-true (and (member "bw-lib" groups) (member "Lists" groups) #t)))
    (on-ui [b selectGroupNamed: "bw-lib"])
    (check (strings (on-ui [b definitionNames])) '("bw-lib:bw-twice" "bw-lib:%bw-double"))
    (check (on-ui [b definitionLabel: [[[b instVarNamed: "definitions"] items] first]]) "bw-twice   procedure")
    (close! w)))

(define-test "R-17 a definition: its header, source, documentation, callers, callees, disassembly"
  (let* ((b (browser)) (w (open! b)))
    (on-ui [b browse: 'bw-lib:%bw-double])
    (check-true (has? (on-ui [b headerText]) "bw-lib:%bw-double -- procedure   bwlib.lisp:3"))
    (check (on-ui [b sourceText]) "(define (%bw-double x)\n  \"(%bw-double x)\nx and x.\"\n  (* 2 x))")
    (check (on-ui [b documentationText]) "(%bw-double x)\nx and x.")
    (check (strings (on-ui [b callerNames])) '("bw-lib:bw-twice"))
    (check-true (and (member "*" (strings (on-ui [b calleeNames]))) #t))
    (check-true (has? (on-ui [b disassemblyText]) "; the procedure"))
    ;; a primitive: no source, no file
    (on-ui [b browse: 'car])
    (check-true (has? (on-ui [b headerText]) "car -- primitive"))
    (check-true (has? (on-ui [b sourceText]) "with no source in the image"))
    (check-true (string-prefix? "(car" (on-ui [b documentationText])))
    ;; a built-in from cog-lisp's own sources: its text from the file
    (on-ui [b browse: 'filter])
    (check-true (has? (on-ui [b headerText]) "core.lisp:"))
    (check-true (string-prefix? "(define (filter" (on-ui [b sourceText])))
    (close! w)))

(define-test "R-19 search, and browsing what it found"
  (let* ((b (browser)) (w (open! b)))
    (on-ui [b search: "bw-tw"])
    (check (strings (on-ui [b definitionNames])) '("bw-lib:bw-twice"))
    (check-true (has? (on-ui [b statusText]) "1 found"))
    (on-ui [b selectDefinition: 'bw-lib:bw-twice])
    (check-true (has? (on-ui [b headerText]) "bw-lib:bw-twice"))
    (close! w)))

(define-test "R-20 Save writes the definition back, saves and evaluates it"
  (let* ((b (browser)) (w (open! b)))
    (on-ui [b browse: 'bw-lib:%bw-double])
    (on-ui [b sourceText: "(define (%bw-double x)\n  \"(%bw-double x)\nx and x.\"\n  (+ x x 1))"])
    (on-ui [b saveDefinition])
    (check-true (has? (on-ui [b statusText]) "saved to bwlib.lisp and evaluated"))
    (check (bw-lib:bw-twice 2) 5)
    (check-true (has? (car (ide-read-file lib-file)) "(+ x x 1))\n\n(define (bw-twice x)"))
    (close! w)))

(define-test "R-20 a stale definition is opened in the editor, not written"
  (let* ((f (write-raw! [dir / "bwstale.lisp"] "(define (bw-stale) 1)\n"))
         (b (browser)) (w (open! b)))
    (ide-load-file f)
    (write-raw! [f asFileReference] "; moved\n(define (bw-stale) 2)\n")
    (on-ui [b browse: 'bw-stale])
    (check-true (has? (on-ui [b headerText]) "stale"))
    (on-ui [b saveDefinition])
    (check-true (has? (on-ui [b statusText]) "opened in the editor, not written"))
    (let* ((e (on-ui [b lastEditor])) (p (on-ui [e selectedPage])))
      (check (on-ui [p name]) "bwstale.lisp")
      (check (car (ide-read-file f)) "; moved\n(define (bw-stale) 2)\n")
      (on-ui [[e window] close]))
    (close! w)))

(define-test "R-10 the editor's go to definition on a built-in opens the browser on it"
  (let* ((f (write-raw! [dir / "bwuse.lisp"] "(car '(1))\n"))
         (e [(smalltalk LispEditorPresenter) new])
         (w (on-ui [e open]))
         (p (on-ui [e openFile: f])))
    (on-ui [[p code] selectionInterval: [3 to: 2]])
    (on-ui [p goToDefinition])
    (let ((b (on-ui [e lastBrowser])))
      (check-true (has? (on-ui [b headerText]) "car -- primitive"))
      (on-ui [[b window] close]))
    (close! w)))

(define-test "the cog-lisp menu opens the browser"
  (check-true (has? [[[[(smalltalk LispIde) class] >> ["menuCommandOn:" asSymbol]] sourceCode] asString] "LispBrowserPresenter open")))

(run-tests)
[dir ensureDeleteAll]
