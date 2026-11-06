;;; phase-10.2-reference.lisp -- the files generated from the image's documentation
;;; match it (specs/phase-10-documentation-and-editor.md steps 10.2 and 10.3,
;;; AC-2 and AC-3). After changing documentation: rebuild the image, then run
;;; ./cog-lisp.sh tools/generate-docs.lisp and commit what it writes.
(load "../../lib/test.lisp")
(load "../../tools/docs.lisp")

(define root [[[[[(current-load-path) asFileReference] parent] parent] parent] fullName])
(define (committed relative) [[[(string-append root "/" relative) asFileReference] contents] asString])

(define-test "AC-2 docs/builtins.md is what the image's documentation generates"
  (check-true (string=? (builtins-markdown) (committed "docs/builtins.md"))))

(define-test "AC-3 vscode/builtins.json is what the image's documentation generates"
  (check-true (string=? (builtins-json) (committed "vscode/builtins.json"))))

(define-test "AC-2 the reference lists every public built-in, once"
  (let ((names (map docs-entry-name (builtin-entries))))
    (check-true (> (length names) 280))
    (check (length names) (length (docs-sort-strings names)))
    (check-true (member "string-ref" names))
    (check-true (member "if" names))
    (check-true (member "compile-form" names))
    (check-false (member "%guard" names))
    (check-false (member "lc-translate" names))))

(define-test "AC-2 a definition of a program's own is not a built-in"
  (define (docs-test-mine x) "(docs-test-mine x)\nMine." x)
  (check-false (member "docs-test-mine" (map docs-entry-name (builtin-entries)))))

(define-test "AC-3 the editor's data is JSON a reader can parse"
  (let ((parsed [(smalltalk STONJSON) fromString: (builtins-json)]))
    (check [parsed size] (length (builtin-entries)))
    (check [[parsed at: "string-ref"] at: "call"] "(string-ref string k)")
    (check [[parsed at: "if"] at: "kind"] "special form")))

(run-tests)
