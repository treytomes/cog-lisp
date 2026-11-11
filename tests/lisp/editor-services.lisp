;;; editor-services.lisp -- what an editor knows about cog-lisp source
;;; (specs/34-morphic-ide.md R-29, AC-1): definitions and the index, the name at
;;; a place, problems, names resolved through a file's imports, completion, the
;;; macro call at a place, and the tokens to style; every place a character
;;; offset, a character outside the BMP counting one. The fixture files are in
;;; editor-services/.
(load "../../lib/test.lisp")
(require 'editor-services)

(define here [[[[(smalltalk LispLoadPath) value] asFileReference] parent] fullName])
(define (fixture name) (string-append here "/editor-services/" name))
(define (read-file path) [[[path asFileReference] contents] asString])
(define windows [[(smalltalk OSPlatform) current] isWindows])

;;; --- files ------------------------------------------------------------------------

(define-test "editor-key: one key for two spellings of a path"
  (check (editor-key "a\\b/c.lisp") "a/b/c.lisp")
  (check (editor-key "C:\\X\\y.lisp") (if windows "c:/x/y.lisp" "C:/X/y.lisp")))

;;; --- definitions and the index ----------------------------------------------------

(define-test "editor-definitions: each top-level definition, its place, documentation and source"
  (let* ((text "(define x 1)\n(define (f a)\n  \"(f a)\nDoubles.\"\n  (* 2 a))\n(define-macro (m) 1)\n(display x)\n")
         (defs (editor-definitions text)))
    (check (map definition-name defs) '("x" "f" "m"))
    (check (definition-start (cadr defs)) 13)
    (check (definition-end (cadr defs)) (+ 13 (string-length "(define (f a)\n  \"(f a)\nDoubles.\"\n  (* 2 a))")))
    (check (definition-documentation (cadr defs)) "(f a)\nDoubles.")
    (check-false (definition-documentation (car defs)))
    (check (definition-source (car defs)) "(define x 1)")
    (check-false (definition-path (car defs)))
    (check (definition-path (car (editor-definitions text "here.lisp"))) "here.lisp"))
  ;; up to the first form that does not read
  (check (map definition-name (editor-definitions "(define a 1)\n(define (b\n(define c 3)")) '("a")))

(define-test "the index: a file, a folder, an editor's text, and names across them"
  (editor-index-folder! (string-append here "/editor-services"))
  (let ((areas (editor-definitions-named "area")))
    (check (length areas) 1)
    (check-true (string-suffix? "geometry.lisp" (definition-path (car areas))))
    (check (definition-documentation (car areas)) "(area r)\nThe area of a circle of radius r."))
  (check (editor-indexed-text (fixture "geometry.lisp")) (read-file (fixture "geometry.lisp")))
  ;; an editor's unsaved text replaces the file's
  (editor-index-text! (fixture "wide.lisp") "(define (wave2) 1)\n")
  (check (editor-definitions-named "wave") '())
  (check (length (editor-definitions-named "wave2")) 1)
  (editor-index-file! (fixture "wide.lisp"))
  (check (length (editor-definitions-named "wave")) 1)
  (check-false (editor-indexed-text (fixture "no-such-file.lisp"))))

(define-test "places are character offsets: a character outside the BMP counts one"
  (let* ((text (read-file (fixture "wide.lisp")))
         (wave (car (filter (lambda (d) (string=? (definition-name d) "wave")) (editor-definitions text)))))
    (check (definition-start wave) (string-search text "(define (wave)"))
    (check (substring text (definition-start wave) (definition-end wave)) "(define (wave) greeting)")
    (check (editor-symbol-at text (+ (string-search text "greeting)") 2))
           (list "greeting" (string-search text "greeting)") (+ (string-search text "greeting)") 8)))))

;;; --- the name at a place -----------------------------------------------------------

(define-test "editor-symbol-at: the name around an offset, or #f between names"
  (check (editor-symbol-at "(geo:area r)" 3) '("geo:area" 1 9))
  (check (editor-symbol-at "(geo:area r)" 9) '("geo:area" 1 9))     ; just after it
  (check (editor-symbol-at "(a b)" 0) #f)
  (check (editor-symbol-at "x" 5) '("x" 0 1)))                    ; past the end

;;; --- problems ------------------------------------------------------------------------

(define-test "editor-check: read errors, compile errors and warnings, placed on their forms"
  (check (editor-check "clean.lisp" "(define (f x) (+ x 1))\n") '())
  (let ((p (car (editor-check "unread.lisp" "(define a 1)\n(display \"open"))))
    (check (problem-severity p) 'error)
    (check-true (>= (problem-start p) 13)))
  (let* ((text "(define a 1)\n(if)\n")
         (p (car (editor-check "bad.lisp" text))))
    (check (problem-severity p) 'error)
    (check (substring text (problem-start p) (problem-end p)) "(if)"))
  (let ((ws (editor-check "redefines.lisp" "(define (car x) x)\n")))
    (check (map problem-severity ws) '(warning))
    (check-true (string-search (problem-message (car ws)) "car"))))

;;; --- names through a file's imports -----------------------------------------------------

(define-test "editor-resolve and editor-definitions-for: a prefixed import leads to its library's file"
  (editor-index-folder! (string-append here "/editor-services"))
  (let ((path (fixture "uses-geometry.lisp")))
    (check (editor-check path (read-file path)) '())
    (check-true [(editor-unit-of path) isKindOf: (smalltalk LispUnit)])
    (check (editor-resolve path "geo:area") 'es-geometry:area)
    (check (editor-resolve path "ring") 'ring)
    (let ((defs (editor-definitions-for path "geo:area")))
      (check (map definition-name defs) '("area"))
      (check-true (string-suffix? "geometry.lisp" (definition-path (car defs)))))
    (check (map definition-name (editor-definitions-for path "ring")) '("ring")))
  (check-false (editor-unit-of "never-checked.lisp")))

;;; --- completion ----------------------------------------------------------------------------

(define-test "editor-completions: built-ins, special forms, the file's imports and the index's names, once each"
  (let* ((path (fixture "uses-geometry.lisp"))
         (items (begin (editor-check path (read-file path)) (editor-completions path)))
         (find (lambda (label) (let ((m (filter (lambda (c) (string=? (completion-label c) label)) items)))
                                 (and (pair? m) (car m))))))
    (check (completion-kind (find "string-append")) 'function)
    (check (completion-detail (find "string-ref")) "(string-ref string k)")
    (check (completion-kind (find "if")) 'keyword)
    (check (completion-kind (find "geo:area")) 'function)
    (check (completion-detail (find "geo:area")) "(area r)")
    (check (completion-kind (find "ring")) 'variable)
    (check (length (filter (lambda (c) (string=? (completion-label c) "ring")) items)) 1)))

;;; --- the macro call at a place -------------------------------------------------------------

(define-test "editor-macro-call-at: the innermost macro call holding the place, and its expansion"
  (let* ((text "(define (f x) (when x (unless x 1)))")
         (inner (editor-macro-call-at text (string-search text "unless")))
         (outer (editor-macro-call-at text (string-search text "when"))))
    (check (car inner) "(unless x 1)")
    (check-true (string-search (cdr inner) "if"))
    (check (car outer) "(when x (unless x 1))"))
  (check-false (editor-macro-call-at "(f 1)" 1)))

;;; --- tokens ---------------------------------------------------------------------------------

(define-test "editor-tokens: each kind, with places and parenthesis depth"
  (let ((ts (editor-tokens "(define s \"a;b\") ; c\n#\\x 12 'q [k]")))
    (check (map token-kind ts) '(open keyword symbol string close comment character number quote symbol open symbol close))
    (check (map (lambda (t) (list (token-start t) (token-end t))) (list-tail ts 3))
           '((10 15) (15 16) (17 20) (21 24) (25 27) (28 29) (29 30) (31 32) (32 33) (33 34)))
    (check (map token-depth (filter (lambda (t) (memq (token-kind t) '(open close))) ts)) '(0 0 0 0)))
  (check (map token-depth (filter (lambda (t) (eq? (token-kind t) 'open)) (editor-tokens "(a (b (c)))"))) '(0 1 2))
  ;; text being edited: an unclosed string, a stray close, a bare #
  (check (map token-kind (editor-tokens "(f \"open")) '(open symbol string))
  (check (token-end (caddr (editor-tokens "(f \"open"))) 8)
  (check (map token-depth (editor-tokens ")")) '(0))
  (check (map token-kind (editor-tokens "-1 +x 1/2 #t #f")) '(number symbol number symbol symbol))
  (check (map token-kind (editor-tokens "(when x)")) '(open keyword symbol close))
  (check (editor-tokens "") '()))

(run-tests)
