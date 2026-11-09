;;; generate-docs.lisp -- write every file generated from the image's documentation
;;; and the examples (specs/phase-10-documentation-and-editor.md, steps 10.2 to 10.4,
;;; and the site's home page, 10.6)
;;;
;;;   ./cog-lisp.sh tools/generate-docs.lisp      (cog-lisp.bat on Windows)
;;;
;;; Run it after changing documentation (and rebuilding the image), an example or
;;; the manual's chapters. The suites check that the committed files match what
;;; it writes.

(load "docs.lisp")

(define (docs-write! relative text)
  [[[(docs-path relative) asFileReference] parent] ensureCreateDirectory]
  (with-output-to-file (docs-path relative) (lambda () (display text)))
  (display "wrote ") (display relative) (newline))

(unless (and (null? (manual-unlisted-examples)) (null? (manual-missing-examples)))
  (display "docs/manual/chapters.lisp does not match examples/: in no chapter ")
  (write (manual-unlisted-examples))
  (display ", no such example ")
  (write (manual-missing-examples))
  (newline)
  (exit 1))

(docs-write! "docs/builtins.md" (builtins-markdown))
(docs-write! "vscode/builtins.json" (builtins-json))
(docs-write! spelling-words-file (spelling-words))
(for-each (lambda (f) (docs-write! (car f) (cdr f))) (manual-files))
(for-each (lambda (f) (docs-write! (car f) (cdr f))) (site-files))
(for-each (lambda (f) (docs-write! (car f) (cdr f))) (skill-files))
