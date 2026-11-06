;;; phase-10.4-manual.lisp -- the manual is what the examples generate
;;; (specs/phase-10-documentation-and-editor.md step 10.4, AC-4). After changing an
;;; example or docs/manual/chapters.lisp, run ./cog-lisp.sh tools/generate-docs.lisp
;;; and commit what it writes.
(load "../../lib/test.lisp")
(load "../../tools/docs.lisp")

(define-test "AC-4 every example is in a chapter, and every chapter's examples exist"
  (check (manual-unlisted-examples) '())
  (check (manual-missing-examples) '())
  (check-true (> (length (docs-example-names)) 30)))

(define-test "AC-4 each committed page of the manual is what the examples generate"
  (for-each (lambda (f)
              (check (list (car f) (and (docs-file? (car f)) (string=? (cdr f) (docs-file-text (car f)))))
                     (list (car f) #t)))
            (manual-files)))

(define-test "AC-4 the manual has no page the generator does not write"
  (let ((generated (map car (manual-files)))
        (committed (map (lambda (f) (docs-relative [f fullName]))
                        (vector->list [[[(docs-path "docs/manual") asFileReference] files] asArray]))))
    (check (docs-filter (lambda (f) (and [f endsWith: ".md"]
                                         (not (string=? f "docs/manual/introduction.md"))
                                         (not (member f generated))))
                        committed)
           '())))

(define-test "AC-4 a chapter shows each example's explanation, code and checked output"
  (let ((text (cdr (assoc "docs/manual/06-input-and-output.md" (manual-files)))))
    (check-true (string-search text "## A program in two files"))
    (check-true (string-search text "`examples/program/lib/util.lisp`:"))
    (check-true (string-search text "Run with the arguments"))
    (check-true (string-search text "Its input:"))
    (check-true (string-search text "Its output:")))
  (check (docs-example-title "x.lisp -- what it shows (Phase 7.9 section 4)") "What it shows")
  (check (cdr (docs-split-example ";; a\n;; b\n\n(code)\n")) "(code)\n"))

(run-tests)
