;;; docs.lisp -- the documentation the image holds, as the files generated from it
;;; (specs/16-phase-10-documentation-and-editor.md steps 10.2 and 10.3)
;;;
;;; (builtins-markdown) is docs/builtins.md and (builtins-json) is
;;; vscode/builtins.json, each as a string. tools/generate-docs.lisp writes them;
;;; the suites compare them with the committed files, so the files cannot drift
;;; from the image. Only the built-in categories below are included, in this
;;; order, so a program's own documented definitions never are.

(define docs-categories
  '("Special forms" "Derived forms" "Equality and types" "Numbers" "Lists"
    "Characters" "Strings" "Vectors" "Hash tables" "Control"
    "Conditions and restarts" "Evaluation and macros" "Output" "Ports" "Files" "Network"
    "The system" "Smalltalk interop" "Language server" "The compiler and reader"))

;; an entry: #(name kind category call description)
(define (docs-entry-name e) (vector-ref e 0))
(define (docs-entry-kind e) (vector-ref e 1))
(define (docs-entry-category e) (vector-ref e 2))
(define (docs-entry-call e) (vector-ref e 3))
(define (docs-entry-description e) (vector-ref e 4))

;; the first line of a documentation string, and the rest as one line
(define (docs-split doc)
  (let ((i (string-index doc #\newline)))
    (if i
        (cons (substring doc 0 i) (docs-one-line (substring doc (+ i 1))))
        (cons doc ""))))
(define (docs-one-line s) (string-join (string-split s #\newline) " "))

(define (docs-make-entry name kind)
  (let ((doc (documentation name)) (category (documentation-category name)))
    (and doc category (member category docs-categories)
         (let ((parts (docs-split doc)))
           (vector (symbol->string name) kind category (car parts) (cdr parts))))))

(define (docs-kind value)
  (cond ([value isKindOf: (smalltalk LispMacro)] "macro")
        ((procedure? value) "procedure")
        (else "value")))

(define (docs-sort-strings strings)
  (vector->list [[[(list->vector strings) asSortedCollection] asArray] copy]))

;; every public, documented built-in, by category in docs-categories' order, then
;; by name
(define (builtin-entries)
  (let ((entries '()))
    (for-each (lambda (name)
                (let ((e (docs-make-entry name "special form")))
                  (when e (set! entries (cons e entries)))))
              (special-form-names))
    [[(smalltalk LispEnvironment) default]
     cellsDo: (lambda (cell)
                (when [cell isBound]
                  (let* ((name [cell symbol])
                         (s (symbol->string name)))
                    (unless (or (char=? (string-ref s 0) #\%)
                                (string-index s #\:)          ; a library's (specs/27-namespaces.md)
                                (and (documentation-category name)
                                     (string=? (documentation-category name) "Special forms")))
                      (let ((e (docs-make-entry name (docs-kind [cell value]))))
                        (when e (set! entries (cons e entries))))))))]
    (let ((by-name (make-hash-table equal?)))
      (for-each (lambda (e) (hash-table-set! by-name (docs-entry-name e) e)) entries)
      (let loop ((cats docs-categories) (acc '()))
        (if (null? cats)
            (reverse acc)
            (loop (cdr cats)
                  (append (reverse (map (lambda (n) (hash-table-ref by-name n))
                                        (docs-sort-strings
                                         (map docs-entry-name
                                              (docs-filter (lambda (e) (string=? (docs-entry-category e) (car cats)))
                                                           entries)))))
                          acc)))))))

;;; The libraries cog-lisp ships, which a program requires (specs/27-namespaces.md
;;; R-14): each export, documented, under the library's name as its category

(define docs-libraries '(cl test datetime pretty format-source))

;; a value with no documentation (cl's t and nil): what it holds, when short
(define (docs-value-description value)
  (let ((text (with-output-to-string (lambda () (write value)))))
    (if (<= (string-length text) 24)
        (string-append "The value " text ".")
        "A value (a list): see the library's source.")))

(define (library-entries library)
  (require library 'only '())                     ; loads it, imports nothing
  (let ((unit [(smalltalk LispUnit) libraryNamed: library])
        (env [(smalltalk LispEnvironment) default])
        (category (symbol->string library)))
    (map (lambda (name)
           (let* ((full [unit qualify: (string->symbol name)])
                  (doc (documentation full))
                  (value [env at: full ifAbsent: (lambda () #f)]))
             (if doc
                 (let ((parts (docs-split doc)))
                   (vector name (docs-kind value) category (car parts) (cdr parts)))
                 (vector name "value" category name (docs-value-description value)))))
         (docs-sort-strings (map symbol->string (vector->list [unit exports]))))))

(define (docs-filter pred l)
  (cond ((null? l) '())
        ((pred (car l)) (cons (car l) (docs-filter pred (cdr l))))
        (else (docs-filter pred (cdr l)))))

(define (docs-in-category entries category)
  (docs-filter (lambda (e) (string=? (docs-entry-category e) category)) entries))

;;; docs/builtins.md

;; GitHub's anchor for a heading
(define (docs-anchor title)
  (list->string (map (lambda (c) (if (char=? c #\space) #\- (char-downcase c))) (string->list title))))

;; text for a Markdown table cell: a | would end the cell
(define (docs-cell s)
  (string-join (string-split s #\|) "\\|"))

;; a table cell's text as code. Text holding a backtick (quasiquote's `template)
;; would end a one-backtick code span early, and Jekyll's kramdown then gives up
;; on the whole table; a two-backtick span with a space inside each end holds it,
;; for kramdown and for GitHub's own Markdown alike.
(define (docs-code-cell s)
  (if (string-search s "`")
      (string-append "`` " (docs-cell s) " ``")
      (string-append "`" (docs-cell s) "`")))

(define (builtins-markdown)
  (let ((entries (builtin-entries)))
    (with-output-to-string
      (lambda ()
        (display "# The built-ins of cog-lisp\n\n")
        (display "Every special form, derived form and built-in procedure, with its call form\n")
        (display "and what it does. Generated from the documentation kept in the image\n")
        (display "(specs/16-phase-10-documentation-and-editor.md, step 10.2): do not edit by hand.\n")
        (display "After changing documentation, rebuild the image and run\n")
        (display "`./cog-lisp.sh tools/generate-docs.lisp` (or `cog-lisp.bat`).\n\n")
        (display "In a call form, `[x]` is optional and `x ...` is any number of them.\n")
        (display "`(documentation 'name)` answers the same text at the REPL.\n\n")
        (for-each (lambda (cat)
                    (let ((n (length (docs-in-category entries cat))))
                      (when (> n 0)
                        (display "- [") (display cat) (display "](#") (display (docs-anchor cat))
                        (display ") (") (display n) (display ")\n"))))
                  docs-categories)
        (display "- [Libraries](#libraries): ")
        (display (string-join (map symbol->string docs-libraries) ", "))
        (newline)
        (for-each (lambda (cat)
                    (let ((es (docs-in-category entries cat)))
                      (when (pair? es)
                        (display "\n## ") (display cat) (display "\n\n")
                        (docs-markdown-table es))))
                  docs-categories)
        (display "\n## Libraries\n\n")
        (display "Not built in: a program loads one with `(require 'name)`, which brings in\n")
        (display "the names below; `(require 'name 'prefix 'p:)` brings them in as `p:x`, and\n")
        (display "`name:x` names each one from anywhere (specs/27-namespaces.md).\n")
        (for-each (lambda (library)
                    (display "\n### ") (display library) (display "\n\n")
                    (display "`(require '") (display library) (display ")`\n\n")
                    (docs-markdown-table (library-entries library)))
                  docs-libraries)))))

(define (docs-markdown-table es)
  (display "| Name | Call | Kind | What it does |\n")
  (display "|---|---|---|---|\n")
  (for-each (lambda (e)
              (display "| ") (display (docs-code-cell (docs-entry-name e)))
              (display " | ") (display (docs-code-cell (docs-entry-call e)))
              (display " | ") (display (docs-entry-kind e))
              (display " | ") (display (docs-cell (docs-entry-description e)))
              (display " |\n"))
            es))

;;; vscode/builtins.json: what the editor shows on hover, and completes

(define (docs-json-string s)
  (with-output-to-string
    (lambda ()
      (display "\"")
      (for-each (lambda (c)
                  (cond ((char=? c #\") (display "\\\""))
                        ((char=? c #\\) (display "\\\\"))
                        ((char=? c #\newline) (display "\\n"))
                        ((char=? c #\tab) (display "\\t"))
                        ((< (char->integer c) 32) (display "\\u") (display (docs-hex4 (char->integer c))))
                        (else (write-char c))))
                (string->list s))
      (display "\""))))

(define (docs-hex4 n)
  (let ((h (number->string n 16)))
    (string-append (make-string (- 4 (string-length h)) #\0) h)))

;; one entry per line, sorted by name, so the file diffs well
(define (builtins-json)
  (let* ((entries (builtin-entries))
         (by-name (make-hash-table equal?)))
    (for-each (lambda (e) (hash-table-set! by-name (docs-entry-name e) e)) entries)
    (with-output-to-string
      (lambda ()
        (display "{\n")
        (let loop ((names (docs-sort-strings (map docs-entry-name entries))))
          (when (pair? names)
            (let ((e (hash-table-ref by-name (car names))))
              (display "  ") (display (docs-json-string (docs-entry-name e)))
              (display ": {\"call\": ") (display (docs-json-string (docs-entry-call e)))
              (display ", \"kind\": ") (display (docs-json-string (docs-entry-kind e)))
              (display ", \"category\": ") (display (docs-json-string (docs-entry-category e)))
              (display ", \"description\": ") (display (docs-json-string (docs-entry-description e)))
              (display (if (pair? (cdr names)) "},\n" "}\n")))
            (loop (cdr names))))
        (display "}\n")))))

;;; docs/manual/: the user manual, from the examples (step 10.4)

;; the repository's root: this file is tools/docs.lisp
(define docs-root [[[[(current-load-path) asFileReference] parent] parent] fullName])
(define (docs-path relative) (string-append docs-root "/" relative))
(define (docs-file-text relative) [[[(docs-path relative) asFileReference] contents] asString])
(define (docs-file? relative) [[(docs-path relative) asFileReference] isFile])
(define (docs-directory? relative) [[(docs-path relative) asFileReference] isDirectory])

;; the chapters: #(slug title introduction (example ...)), from docs/manual/chapters.lisp
(define (manual-chapters)
  (map (lambda (form) (vector (car (cdr form)) (car (cdr (cdr form))) (car (cdr (cdr (cdr form))))
                              (cdr (cdr (cdr (cdr form))))))
       (read-all (docs-file-text "docs/manual/chapters.lisp"))))

(define (docs-lines text) (string-split text #\newline))
(define (docs-starts? s prefix)
  (and (>= (string-length s) (string-length prefix)) (string=? (substring s 0 (string-length prefix)) prefix)))

;; a comment line without its semicolons and the one space after them
(define (docs-uncomment line)
  (let loop ((i 0))
    (if (and (< i (string-length line)) (char=? (string-ref line i) #\;))
        (loop (+ i 1))
        (substring line (if (and (< i (string-length line)) (char=? (string-ref line i) #\space)) (+ i 1) i)))))

;; an example's text split into its opening comment (a list of lines) and its code
(define (docs-split-example text)
  (let loop ((lines (docs-lines text)) (comment '()))
    (if (and (pair? lines) (docs-starts? (car lines) ";"))
        (loop (cdr lines) (cons (docs-uncomment (car lines)) comment))
        (cons (reverse comment)
              (string-join (docs-drop-blank lines) "\n")))))

(define (docs-drop-blank lines)
  (if (and (pair? lines) (string=? (string-trim (car lines)) "")) (docs-drop-blank (cdr lines)) lines))

;; "name.lisp -- what it shows (Phase 7.9 section 4)" -> "what it shows": the
;; first line's title, without its reference to the spec
(define (docs-example-title line)
  (let* ((dash (string-search line " -- "))
         (title (if dash (substring line (+ dash 4)) line))
         (ref (string-search title " (Phase"))
         (plain (if ref (substring title 0 ref) title)))
    (if (string=? plain "")
        plain
        (string-append (string (char-upcase (string-ref plain 0))) (substring plain 1)))))

;; the comment's prose: what follows the title line, less any line that only
;; refers to the spec
(define (docs-example-prose comment-lines)
  (let ((rest (docs-filter (lambda (l) (not (or (docs-starts? (string-trim l) "(Phase")
                                                  (docs-starts? (string-trim l) "(specs/"))))
                           (if (pair? comment-lines) (cdr comment-lines) '()))))
    (string-trim (string-join rest "\n"))))

(define (docs-slashes path) [path copyReplaceAll: "\\" with: "/"])

;; a path relative to the repository's root
(define (docs-relative path)
  (substring (docs-slashes path) (+ (string-length (docs-slashes docs-root)) 1)))

;; the other .lisp files of a folder example, sorted (main.lisp is shown first)
(define (docs-folder-others name)
  (docs-sort-strings
   (docs-filter (lambda (f) (and [f endsWith: ".lisp"] (not [f endsWith: "/main.lisp"])))
                (map (lambda (f) (docs-relative [f fullName]))
                     (vector->list [[[(docs-path (string-append "examples/" name)) asFileReference] allFiles] asArray])))))

(define (docs-fence language text)
  (string-append "```" language "\n" text (if [text endsWith: "\n"] "" "\n") "```\n"))

(define (docs-listing path code)
  (string-append "`" path "`:\n\n" (docs-fence "scheme" code) "\n"))

;; one example, as a section of a chapter
(define (docs-example-section name)
  (let* ((folder (docs-directory? (string-append "examples/" name)))
         (main (if folder (string-append "examples/" name "/main") (string-append "examples/" name)))
         (parts (docs-split-example (docs-file-text (string-append main ".lisp"))))
         (comment (car parts)))
    (with-output-to-string
      (lambda ()
        (display "## ") (display (docs-example-title (if (pair? comment) (car comment) name))) (newline) (newline)
        (let ((prose (docs-example-prose comment)))
          (unless (string=? prose "") (display prose) (newline) (newline)))
        (display (docs-listing (string-append main ".lisp") (cdr parts)))
        (when folder
          (for-each (lambda (f) (display (docs-listing f (cdr (docs-split-example (docs-file-text f))))))
                    (docs-folder-others name)))
        (when (docs-file? (string-append main ".args"))
          (display "Run with the arguments `") (display (string-trim (docs-file-text (string-append main ".args"))))
          (display "`.") (newline) (newline))
        (when (docs-file? (string-append main ".input"))
          (display "Its input:") (newline) (newline)
          (display (docs-fence "text" (docs-file-text (string-append main ".input")))) (newline))
        (if (docs-file? (string-append main ".expected"))
            (begin
              (display "Its output:") (newline) (newline)
              (display (docs-fence "text" (docs-file-text (string-append main ".expected")))) (newline))
            (begin (display "A library, which the next example loads.") (newline) (newline)))))))

(define (docs-two-digits n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))
(define (docs-nth l i) (if (= i 0) (car l) (docs-nth (cdr l) (- i 1))))

;; the file name of chapter n (from 1)
(define (docs-chapter-name n chapters)
  (string-append (docs-two-digits n) "-" (vector-ref (docs-nth chapters (- n 1)) 0) ".md"))

(define (docs-chapter-links n chapters)
  (string-append
   (if (> n 1)
       (string-append "Previous: [" (vector-ref (docs-nth chapters (- n 2)) 1) "](" (docs-chapter-name (- n 1) chapters) ") · ")
       "")
   "[Contents](README.md)"
   (if (< n (length chapters))
       (string-append " · Next: [" (vector-ref (docs-nth chapters n) 1) "](" (docs-chapter-name (+ n 1) chapters) ")")
       "")))

(define docs-generated-note
  "<!-- Generated by tools/generate-docs.lisp from docs/manual/chapters.lisp,\n     docs/manual/introduction.md and the examples: do not edit by hand. -->\n\n")

(define (docs-chapter-text n chapter chapters)
  (with-output-to-string
    (lambda ()
      (display "# ") (display n) (display ". ") (display (vector-ref chapter 1)) (newline) (newline)
      (display docs-generated-note)
      (display (vector-ref chapter 2)) (newline) (newline)
      (for-each (lambda (name) (display (docs-example-section name))) (vector-ref chapter 3))
      (display "---") (newline) (newline)
      (display (docs-chapter-links n chapters)) (newline))))

(define (docs-manual-index chapters)
  (with-output-to-string
    (lambda ()
      (display "# The cog-lisp manual") (newline) (newline)
      (display docs-generated-note)
      (display (docs-file-text "docs/manual/introduction.md"))
      (newline) (display "## Contents") (newline) (newline)
      (let loop ((cs chapters) (n 1))
        (when (pair? cs)
          (display n) (display ". [") (display (vector-ref (car cs) 1)) (display "](")
          (display (docs-chapter-name n chapters)) (display ")") (newline)
          (loop (cdr cs) (+ n 1))))
      (newline) (display "And the [reference of the built-ins](../builtins.md).") (newline))))

;; every generated file of the manual: (relative-path . text)
(define (manual-files)
  (let ((chapters (manual-chapters)))
    (cons (cons "docs/manual/README.md" (docs-manual-index chapters))
          (let loop ((cs chapters) (n 1))
            (if (null? cs)
                '()
                (cons (cons (string-append "docs/manual/" (docs-chapter-name n chapters))
                            (docs-chapter-text n (car cs) chapters))
                      (loop (cdr cs) (+ n 1))))))))

;;; docs/index.md: the home page of the site on GitHub Pages (step 10.6)

(define docs-repository "https://github.com/treytomes/cog-lisp")

;; the introduction's opening paragraph
(define (docs-introduction-opening)
  (let* ((text (docs-file-text "docs/manual/introduction.md"))
         (end (string-search text "\n\n")))
    (string-trim (if end (substring text 0 end) text))))

(define (site-index)
  (with-output-to-string
    (lambda ()
      (display "# cog-lisp") (newline) (newline)
      (display "<!-- Generated by tools/generate-docs.lisp from docs/manual/introduction.md:\n     do not edit by hand. -->\n\n")
      (display (docs-introduction-opening)) (newline) (newline)
      (display "- [The manual](manual/README.md): the language chapter by chapter, through worked and checked examples.") (newline)
      (display "- [The built-ins](builtins.md): every special form, derived form and procedure, with its call form and what it does.") (newline)
      (display (string-append "- [Releases](" docs-repository "/releases): bundles for Linux and Windows, and the VS Code extension."))
      (newline)
      (display (string-append "- [The source](" docs-repository "): the repository, its specs and its tests."))
      (newline))))

;; every generated file of the site that is not the manual or the reference
(define (site-files) (list (cons "docs/index.md" (site-index))))

;; every Markdown page of docs/, as committed (the site's pages)
(define (docs-site-pages)
  (docs-filter (lambda (f) [f endsWith: ".md"])
               (map (lambda (f) (docs-relative [f fullName]))
                    (vector->list [[[(docs-path "docs") asFileReference] allFiles] asArray]))))

;; the pages that hold Liquid syntax, which Jekyll would run
(define (docs-liquid-pages)
  (docs-filter (lambda (f) (let ((text (docs-file-text f)))
                             (or (string-search text "{{") (string-search text "{%"))))
               (docs-site-pages)))

;;; .agents/skills/cog-lisp/: the skill for agents (step 10.7), from docs/skill/

(define skill-folder ".agents/skills/cog-lisp")

;; the traps: #(title wrong outcome right), outcome (error "text") or (answers "text")
(define (skill-traps)
  (map (lambda (form) (list->vector (cdr form)))
       (read-all (docs-file-text "docs/skill/traps.lisp"))))

(define (skill-trap-text trap)
  (let ((outcome (vector-ref trap 2)))
    (string-append
     "- **" (vector-ref trap 0) "**\n"
     "  - Wrong: `" (vector-ref trap 1) "` "
     (if (eq? (car outcome) 'error)
         (string-append "stops with `error: " (car (cdr outcome)) "`")
         (string-append "prints `" (car (cdr outcome)) "`"))
     "\n"
     (if (vector-ref trap 3)
         (string-append "  - Right: `" (vector-ref trap 3) "`\n")
         ""))))

;; the examples, by name: docs/skill/examples/NAME.lisp
(define (skill-example-path name extension) (string-append "docs/skill/examples/" name extension))

(define (skill-example-names)
  (docs-sort-strings
   (map (lambda (f) (let ((base [f basename])) (substring base 0 (- (string-length base) 5))))
        (docs-filter (lambda (f) [[f basename] endsWith: ".lisp"])
                     (vector->list [[[(docs-path "docs/skill/examples") asFileReference] files] asArray])))))

(define (skill-example-text name)
  (let* ((parts (docs-split-example (docs-file-text (skill-example-path name ".lisp"))))
         (comment (car parts))
         (failing (docs-file? (skill-example-path name ".stderr"))))
    (string-append
     "### " (docs-example-title (if (pair? comment) (car comment) name)) "\n\n"
     "`" name ".lisp`:\n\n"
     ;; a failing example is shown whole, comment included, so the line its error
     ;; names is the line shown
     (docs-fence "scheme" (if failing (docs-file-text (skill-example-path name ".lisp")) (cdr parts))) "\n"
     "It prints:\n\n"
     (docs-fence "text" (docs-file-text (skill-example-path name ".expected"))) "\n"
     (if failing
         (string-append "and stops with exit code "
                        (string-trim (docs-file-text (skill-example-path name ".exitcode")))
                        " and this line:\n\n"
                        (docs-fence "text" (docs-file-text (skill-example-path name ".stderr"))) "\n")
         ""))))

;; the names the source's example markers name, in order
(define (skill-marked-examples)
  (let loop ((lines (docs-lines (docs-file-text "docs/skill/skill.md"))) (acc '()))
    (cond ((null? lines) (reverse acc))
          ((docs-starts? (car lines) "<!-- example: ")
           (let* ((line (string-trim (car lines)))
                  (name (string-trim (substring line 14 (- (string-length line) 3)))))
             (loop (cdr lines) (cons name acc))))
          (else (loop (cdr lines) acc)))))

(define skill-generated-note
  "<!-- Generated by tools/generate-docs.lisp from docs/skill/: do not edit by hand. -->")

;; SKILL.md: the source, its markers replaced, and the note after the front matter
(define (skill-markdown)
  (let loop ((lines (docs-lines (docs-file-text "docs/skill/skill.md"))) (dashes 0) (out '()))
    (if (null? lines)
        (string-join (reverse out) "\n")
        (let ((line (car lines)))
          (cond ((and (< dashes 2) (string=? (string-trim line) "---"))
                 (loop (cdr lines) (+ dashes 1)
                       (if (= dashes 1) (cons skill-generated-note (cons line out)) (cons line out))))
                ((string=? (string-trim line) "<!-- traps -->")
                 (loop (cdr lines) dashes
                       (cons (string-trim (apply string-append (map skill-trap-text (skill-traps)))) out)))
                ((docs-starts? line "<!-- example: ")
                 (let* ((l (string-trim line)) (name (string-trim (substring l 14 (- (string-length l) 3)))))
                   (loop (cdr lines) dashes (cons (string-append (string-trim (skill-example-text name)) "
") out))))
                (else (loop (cdr lines) dashes (cons line out))))))))

;; reference.md: every built-in, its call form and what it does, a line each.
;; Text as code: two backticks when it holds one (quasiquote's `template).
(define (docs-code s)
  (if (string-search s "`") (string-append "`` " s " ``") (string-append "`" s "`")))

(define (skill-reference)
  (let ((entries (builtin-entries)))
    (with-output-to-string
      (lambda ()
        (display "# The built-ins of cog-lisp\n\n")
        (display "<!-- Generated by tools/generate-docs.lisp from the image: do not edit by hand. -->\n\n")
        (display "Only these names exist. `[x]` is optional; `x ...` is any number of them.\n")
        (for-each (lambda (cat)
                    (let ((es (docs-in-category entries cat)))
                      (when (pair? es)
                        (display "\n## ") (display cat) (display "\n\n")
                        (skill-reference-lines es))))
                  docs-categories)
        (display "\n## Libraries\n\n")
        (display "These exist only in a file that requires their library: `(require 'cl)`\n")
        (display "brings in the names under cl. `cl:name` reaches one from anywhere.\n")
        (for-each (lambda (library)
                    (display "\n### ") (display library) (display ": `(require '")
                    (display library) (display ")`\n\n")
                    (skill-reference-lines (library-entries library)))
                  docs-libraries)))))

(define (skill-reference-lines es)
  (for-each (lambda (e)
              (display "- ") (display (docs-code (docs-entry-call e))) (display ": ")
              (display (docs-one-line (docs-entry-description e))) (newline))
            es))

;; every generated file of the skill: (relative-path . text)
(define (skill-files)
  (list (cons (string-append skill-folder "/SKILL.md") (skill-markdown))
        (cons (string-append skill-folder "/reference.md") (skill-reference))))

;; every example: a .lisp file of examples/, or a folder with a main.lisp
(define (docs-example-names)
  (docs-sort-strings
   (apply append
          (map (lambda (e)
                 (let ((base [e basename]))
                   (cond ([e isDirectory] (if [[e / "main.lisp"] exists] (list base) '()))
                         ([base endsWith: ".lisp"] (list (substring base 0 (- (string-length base) 5))))
                         (else '()))))
               (vector->list [[[(docs-path "examples") asFileReference] children] asArray])))))

;; the examples no chapter names, and the names no example has
(define (manual-unlisted-examples)
  (let ((listed (apply append (map (lambda (c) (vector-ref c 3)) (manual-chapters)))))
    (docs-filter (lambda (name) (not (member name listed))) (docs-example-names))))
(define (manual-missing-examples)
  (let ((names (docs-example-names)))
    (docs-filter (lambda (name) (not (member name names)))
                 (apply append (map (lambda (c) (vector-ref c 3)) (manual-chapters))))))

;;; The spell checker's word list (specs/25-vscode-spelling.md R-1): the names of
;;; the built-ins and of the libraries a program requires, split as cSpell
;;; splits them, into runs of letters; a run of one or two letters is left out.
;;; The libraries' names are read from their files, not by requiring them, so
;;; that a library's names (cl's remove, say) never change the built-ins'.

(define spelling-libraries '("cl" "test" "datetime" "pretty" "format-source"))

;; the names a library file defines at its top level, as strings
(define (library-defined-names library)
  (call-with-input-file (docs-path (string-append "lib/" library ".lisp"))
    (lambda (port)
      (let loop ((names '()))
        (let ((form (read port)))
          (if (eof-object? form)
              names
              (loop (if (and (pair? form) (memq (car form) '(define define-macro define-syntax))
                             (pair? (cdr form)))
                        (let ((target (car (cdr form))))
                          (cond ((symbol? target) (cons (symbol->string target) names))
                                ((and (pair? target) (symbol? (car target)))
                                 (cons (symbol->string (car target)) names))
                                (else names)))
                        names))))))))

;; the runs of letters in s, lower case, of three letters or more
(define (spelling-runs s)
  (let loop ((cs (string->list s)) (run '()) (runs '()))
    (let ((done (lambda () (if (>= (length run) 3) (cons (list->string (reverse run)) runs) runs))))
      (cond ((null? cs) (done))
            ((char-alphabetic? (car cs)) (loop (cdr cs) (cons (char-downcase (car cs)) run) runs))
            (else (loop (cdr cs) '() (done)))))))

(define (spelling-words)
  (let ((names (append (map docs-entry-name (builtin-entries))
                       (apply append (map library-defined-names spelling-libraries))))
        (seen (make-hash-table equal?)))
    (for-each (lambda (name)
                (unless (char=? (string-ref name 0) #\%)
                  (for-each (lambda (w) (hash-table-set! seen w #t)) (spelling-runs name))))
              names)
    (apply string-append
           (map (lambda (w) (string-append w (string #\newline)))
                (docs-sort-strings (hash-table-keys seen))))))

(define spelling-words-file "vscode/cspell/cog-lisp-words.txt")
