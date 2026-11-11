;;; ide-inspector-window.lisp -- the inspector window, step 4b of
;;; specs/34-morphic-ide.md (R-22 to R-24; AC-4), opened headless and driven
;;; through its presenter in the UI process: a value's views as tabs, a nested
;;; list as a tree, diving into a part and back, the LISP evaluator with it, the
;;; LISP tab in Pharo's own inspector, Inspect it in the editor, Inspect in the
;;; REPL, and what browse opens (called directly: headless, browse only writes).
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
(define (inspector-on v) (on-ui [(smalltalk LispInspectorPresenter) openOn: v]))
(define (close! p) (on-ui [[p window] close]))
(define (row-texts p title)
  (map (lambda (r) (list [[r at: 1] asString] [[r at: 2] asString])) (vector->list (on-ui [p rowsOf: title]))))

(define-test "R-22 a value's views, each a tab; its title"
  (let ((p (inspector-on '(1 (2 3) "x"))))
    (check (strings (on-ui [p viewTitles])) '("List" "Value"))
    (check (row-texts p "List") '(("1" "1") ("2" "(2 3)") ("3" "\"x\"")))
    (check-true (has? (on-ui [p titleText]) "(1 (2 3) \"x\")   (LispCons)"))
    (check (on-ui [[[p instVarNamed: "notebook"] pages] size]) 2)
    (close! p)))

(define-test "R-22 a nested list unfolds as a tree"
  (let* ((p (inspector-on '(1 (2 3) "x")))
         (rows (on-ui [p rowsOf: "List"])))
    (check (map (lambda (r) [[r at: 2] asString]) (vector->list (on-ui [p childRowsOf: [[rows at: 2] at: 3]])))
           '("2" "3"))
    (check (vector->list (on-ui [p childRowsOf: [[rows at: 1] at: 3]])) '())    ; a number has no parts
    (check (vector->list (on-ui [p childRowsOf: "x"])) '())                        ; nor, here, a string
    (close! p)))

(define-test "R-22 diving into a part, and back"
  (let ((p (inspector-on '(1 (2 3) "x"))))
    (on-ui [p dive: '(2 3)])
    (check (on-ui [p object]) '(2 3))
    (check (on-ui [p historySize]) 1)
    (on-ui [p goBack])
    (check (on-ui [p object]) '(1 (2 3) "x"))
    (check (on-ui [p historySize]) 0)
    (close! p)))

(define-test "R-23 the evaluator is LISP, with it bound to the value"
  (let ((p (inspector-on '(1 2 3))))
    (on-ui [p evaluatorText: "(car (cdr it))"])
    (check (on-ui [p evaluate]) 2)
    (check (on-ui [p statusText]) "=> 2")
    (on-ui [p evaluatorText: "(cdr it)"])
    (on-ui [p inspectResult])
    (check (on-ui [p object]) '(2 3))
    (on-ui [p evaluatorText: "(car 5)"])
    (on-ui [p evaluate])
    (check-true (string-prefix? "error: " (on-ui [p statusText])))
    (close! p)))

(define-test "R-22 Pharo's inspector has a LISP tab first, on LISP's kinds of value"
  (let ((m [[(smalltalk LispCons) lookupSelector: ["inspectionLisp" asSymbol]] pragmas]))
    (check [[[m first] selector] asString] "inspectorPresentationOrder:title:")
    (check [[m first] argumentAt: 1] -10))
  (check-true [(smalltalk LispProcedure) includesSelector: ["inspectionLisp" asSymbol]])
  (check-false [(smalltalk Object) includesSelector: ["inspectionLisp" asSymbol]])   ; not every object's
  (let ((tab ['(1 2) inspectionLisp]))
    (check [[[tab class] name] asString] "LispInspectorPresenter")
    (check [tab object] '(1 2))))

(define-test "Inspect it in the editor, Inspect in the REPL"
  (let* ((d (temp "cog-lisp-inspector-ways"))
         (f (write-raw! [d / "i.lisp"] "(list 1 2)\n"))
         (e [(smalltalk LispEditorPresenter) new])
         (w (on-ui [e open]))
         (p (on-ui [e openFile: f])))
    (on-ui [[p code] selectionInterval: [2 to: 1]])
    (on-ui [p inspectIt])
    (check-true [p waitUntilIdle: 20000])
    (let ((i (on-ui [p lastInspector])))
      (check (on-ui [i object]) '(1 2))
      (close! i))
    (close! w)
    [d ensureDeleteAll])
  (let* ((r [(smalltalk LispReplPresenter) new])
         (w (on-ui [r open])))
    (check-true (smalltalk-nil? (on-ui [r inspectLastValue])))                   ; nothing yet
    (on-ui [r inputText: "(vector 'a 'b)"] [r submit])
    (check-true [r waitUntilIdle: 20000])
    (let ((i (on-ui [r inspectLastValue])))
      (check (on-ui [i object]) (vector 'a 'b))
      (check (strings (on-ui [i viewTitles])) '("Vector" "Value"))
      (close! i))
    (on-ui [w close])))

(define-test "what browse opens: the editor at the definition, Pharo's browser on the Smalltalk"
  (let* ((place (let ((v #f)) (with-output-to-string (lambda () (set! v (browse 'filter)))) v))
         (page (on-ui [(smalltalk LispIde) openEditorOn: (car place) from: (cadr place) to: (caddr place)])))
    (check (on-ui [page name]) "core.lisp")
    (let ((sel (on-ui [[page code] selectionInterval])))
      (check (substring (on-ui [page text]) (- [sel first] 1) (+ (- [sel first] 1) 15)) "(define (filter"))
    (on-ui [[[page instVarNamed: "editor"] window] close]))
  (let ((m [(smalltalk LispIde) smalltalkMethodOf: "LispPrimitives class" selector: "installListsInto:"]))
    (check [[m selector] asString] "installListsInto:")
    (check-true (has? [[m sourceCode] asString] "[:p | p car]"))))

(run-tests)
