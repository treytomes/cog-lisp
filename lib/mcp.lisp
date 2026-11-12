;;; mcp.lisp -- cog-lisp's tools for agents, run by the image
;;; (specs/35-mcp-server.md)
;;;
;;;   mcp-server.bat [folder]     (./mcp-server.sh [folder]), which copies the
;;;                               image and runs this file on the copy (R-19);
;;;   cog-lisp.bat lib\mcp.lisp [folder]   runs it on the image itself.
;;;
;;; It speaks the Model Context Protocol on standard input and output: one
;;; JSON-RPC 2.0 message per line, the stdio transport of both revisions it
;;; answers. Its tools are the language server's answers, one for one, from
;;; editor-services: checks, hover, definitions, completions, macro expansion and
;;; formatting. It is the third adapter over that service layer, beside
;;; lib/lsp.lisp (for editors) and the image's own Morphic IDE.
;;;
;;; Two eras, one process (R-3). `initialize` opens the legacy era (2025-11-25)
;;; for the rest of the process; `server/discover`, or any request whose _meta
;;; names a revision, is answered in the modern era (2026-07-28), statelessly.
;;; The envelope differs; the six tools do not.
;;;
;;; The protocol is one procedure, mcp-handle, a message in and its reply out
;;; (R-20); mcp-serve-stdio is the only code here that reads or writes.
;;;
;;; Places are character offsets from 0, or a line and column from 1. UTF-16
;;; positions are the language server's problem, not this file's (R-9).

(require 'editor-services)
(require 'format-source)

;;; ---------------------------------------------------------------------------
;;; JSON. Objects are hash tables with string keys, arrays are vectors, true and
;;; false are #t and #f, and null is (), as lib/json.lisp says.

(define (mcp-object . pairs)
  (let ((table (make-hash-table)))
    (let loop ((ps pairs))
      (when (pair? ps)
        (hash-table-set! table (car ps) (car (cdr ps)))
        (loop (cdr (cdr ps)))))
    table))

(define (mcp-put! table . pairs)
  (let loop ((ps pairs))
    (when (pair? ps)
      (hash-table-set! table (car ps) (car (cdr ps)))
      (loop (cdr (cdr ps)))))
  table)

;; object[key], or #f when it is absent or null
(define (mcp-get object key)
  (if (hash-table? object)
      (let ((v (hash-table-ref/default object key #f)))
        (if (null? v) #f v))
      #f))

(define (mcp-has? object key)
  (and (hash-table? object) (hash-table-contains? object key)))

(define (mcp-json-text value)
  (with-output-to-string (lambda () (json-write value))))

;; a line on stderr, never stdout: stdout is the wire (R-2)
(define (mcp-log! text)
  (let ((err (current-error-port)))
    (write-string "cog-lisp mcp: " err)
    (write-string text err)
    (newline err)))

;;; ---------------------------------------------------------------------------
;;; The revisions and the image (R-4, R-5, R-18)

(define mcp-modern-version "2026-07-28")
(define mcp-legacy-version "2025-11-25")
(define mcp-legacy-versions '("2025-11-25" "2025-06-18" "2025-03-26" "2024-11-05"))
(define mcp-meta-version "io.modelcontextprotocol/protocolVersion")
(define mcp-meta-capabilities "io.modelcontextprotocol/clientCapabilities")
(define mcp-meta-server "io.modelcontextprotocol/serverInfo")

(define mcp-instructions
  "Tools for cog-lisp, a Scheme that runs in a Pharo image: lisp_check a file before running it and after each edit, lisp_hover or lisp_definition a name before using it, lisp_completion to find a name, lisp_expand_macro a misbehaving macro call, and lisp_format after editing. They never run code.")

(define (mcp-image-version)
  (hash-table-ref/default *env* 'version "dev"))

(define (mcp-server-info)
  (mcp-object "name" "cog-lisp" "version" (mcp-image-version)))

;;; ---------------------------------------------------------------------------
;;; Places: an offset from 0, or a line and column from 1 (R-9)

(define (mcp-line-starts text)
  (let ((n (string-length text)))
    (let loop ((i 0) (starts (list 0)))
      (cond ((= i n) (list->vector (reverse starts)))
            ((eq? (string-ref text i) #\newline) (loop (+ i 1) (cons (+ i 1) starts)))
            (else (loop (+ i 1) starts))))))

;; the line (from 0) holding offset, by binary search
(define (mcp-line-of starts offset)
  (let loop ((lo 0) (hi (- (vector-length starts) 1)))
    (if (>= lo hi)
        lo
        (let ((mid (quotient (+ lo hi 1) 2)))
          (if (<= (vector-ref starts mid) offset) (loop mid hi) (loop lo (- mid 1)))))))

;; (line . column), both from 1
(define (mcp-line-column starts offset)
  (let ((line (mcp-line-of starts offset)))
    (cons (+ line 1) (+ (- offset (vector-ref starts line)) 1))))

;; a range as a result gives it: its offsets and its lines and columns
(define (mcp-range starts from to)
  (let ((a (mcp-line-column starts from)) (b (mcp-line-column starts to)))
    (mcp-object "start" from "end" to
                "line" (car a) "column" (cdr a)
                "endLine" (car b) "endColumn" (cdr b))))

(define (mcp-integer? x) (and (number? x) (exact-integer? x)))

;; the offset of the place args name in text: #(ok offset), #(none), or
;; #(error message)
(define (mcp-place text args)
  (let ((offset (mcp-get args "offset")) (line (mcp-get args "line")) (column (mcp-get args "column"))
        (n (string-length text)))
    (cond ((and offset (or line column))
           (vector 'error "give a place as line and column, or as offset, not both"))
          (offset
           (if (and (mcp-integer? offset) (<= 0 offset n))
               (vector 'ok offset)
               (vector 'error (string-append "offset must be a whole number from 0 to " (number->string n)))))
          ((or line column)
           (let* ((starts (mcp-line-starts text)) (lines (vector-length starts)))
             (cond ((not (and (mcp-integer? line) (mcp-integer? column)))
                    (vector 'error "give line and column together, both whole numbers from 1"))
                   ((not (<= 1 line lines))
                    (vector 'error (string-append "line must be from 1 to " (number->string lines))))
                   (else
                    (let* ((start (vector-ref starts (- line 1)))
                           (end (if (< line lines) (- (vector-ref starts line) 1) n))
                           (width (+ (- end start) 1)))
                      (if (<= 1 column width)
                          (vector 'ok (+ start (- column 1)))
                          (vector 'error (string-append "column must be from 1 to " (number->string width)
                                                        " on line " (number->string line)))))))))
          (else (vector 'none)))))

;;; ---------------------------------------------------------------------------
;;; The workspace: the folder after the script, and nothing else (R-6). The index
;;; is a cache of its files on disk: built before the first answer that needs it,
;;; and brought up to date with the disk before each such answer, so a file an
;;; agent edited answers as it is now.

(define mcp-folder #f)              ; a full path, or #f: no workspace
(define mcp-times (make-hash-table equal?))   ; key -> (modification time . path)

(define (mcp-set-folder! folder)
  "Makes folder (a path, or #f) the workspace, its index empty until needed."
  (hash-table-walk mcp-times (lambda (key entry) (editor-unindex! (cdr entry))))
  (set! mcp-times (make-hash-table equal?))
  (set! mcp-folder
        (and folder
             (let ((dir [folder asFileReference]))
               (and [dir isDirectory] [dir fullName])))))

(define (mcp-skipped? name) (member name editor-services:%skipped-folders))

;; every .lisp file under dir, as (path seconds size): its modification time,
;; which the file system gives to the second, and its size
(define (mcp-lisp-files dir)
  (let walk ((dir dir) (acc '()))
    (fold (lambda (entry acc)
            (let ((name [entry basename]))
              (cond ([entry isDirectory] (if (mcp-skipped? name) acc (walk entry acc)))
                    ([name endsWith: ".lisp"]
                     (cons (list [entry fullName] [[entry modificationTime] asUnixTime] [entry size]) acc))
                    (else acc))))
          acc
          (guard (e (#t '())) (vector->list [[dir children] asArray])))))

;; Brings the index up to date with the folder: a file new, changed (another
;; time or size) or changed in the last two seconds (an edit within the second
;; of the last look keeps its time and maybe its size) is read again; a file
;; gone is taken out.
(define (mcp-refresh-index!)
  (when mcp-folder
    (let ((seen (make-hash-table equal?))
          (recent (- [[(smalltalk DateAndTime) now] asUnixTime] 2)))
      (for-each (lambda (file)
                  (let* ((path (car file)) (time (cdr file)) (key (editor-key path))
                         (known (hash-table-ref/default mcp-times key #f)))
                    (hash-table-set! seen key #t)
                    (unless (and known (equal? (car known) time) (< (car time) recent))
                      (editor-index-file! path)
                      (hash-table-set! mcp-times key (cons time path)))))
                (mcp-lisp-files [mcp-folder asFileReference]))
      (for-each (lambda (key)
                  (unless (hash-table-contains? seen key)
                    (editor-unindex! (cdr (hash-table-ref mcp-times key)))
                    (hash-table-delete! mcp-times key)))
                (hash-table-keys mcp-times)))))

(define (mcp-no-workspace-note)
  "no workspace folder: the server was started without one, so only the given source was searched")

;;; ---------------------------------------------------------------------------
;;; A tool's source (R-8): path, text, or both. The source is put in the index
;;; under its path and checked (so its imports and macros are known), the tool
;;; answers, and the index entry is put back as it was, so the next request sees
;;; what it would have seen anyway (R-5).

;; the file of text given alone: no library, no imports, no file on disk
(define mcp-text-path "<text>")

(define (mcp-full-path path)
  (let ((base (if mcp-folder [mcp-folder asFileReference] [(smalltalk FileSystem) workingDirectory])))
    [[base resolveString: path] fullName]))

(define (mcp-read-file path)
  (guard (e (#t #f))
    (let ((file [path asFileReference]))
      (and [file isFile] [[file contents] asString]))))

;; #(ok text path) or #(error message)
(define (mcp-source args)
  (let ((text (mcp-get args "text")) (path (mcp-get args "path")))
    (cond ((and text (not (string? text))) (vector 'error "text must be a string"))
          ((and path (not (string? path))) (vector 'error "path must be a string"))
          ((and text path) (vector 'ok text (mcp-full-path path)))
          (text (vector 'ok text mcp-text-path))
          (path
           (let* ((full (mcp-full-path path)) (contents (mcp-read-file full)))
             (if contents
                 (vector 'ok contents full)
                 (vector 'error (string-append "cannot read the file " full)))))
          (else (vector 'error "give path (a file), text (the source), or both")))))

;; (proc text path), with the source indexed and checked; or the error result.
;; A check's problems are kept for lisp_check, which would only make them again.
(define mcp-last-problems '())

(define (mcp-with-source args proc)
  (let ((source (mcp-source args)))
    (if (eq? (vector-ref source 0) 'error)
        (mcp-error-result (vector-ref source 1))
        (let ((text (vector-ref source 1)) (path (vector-ref source 2)))
          (mcp-refresh-index!)
          (let ((before (editor-indexed-text path)))
            (dynamic-wind
             (lambda () (editor-index-text! path text))
             (lambda ()
               (set! mcp-last-problems (editor-check path text))
               (proc text path))
             (lambda ()
               (if before (editor-index-text! path before) (editor-unindex! path)))))))))

;; (proc text path offset) for a tool that needs a place
(define (mcp-with-place args proc)
  (mcp-with-source args
    (lambda (text path)
      (let ((place (mcp-place text args)))
        (case (vector-ref place 0)
          ((error) (mcp-error-result (vector-ref place 1)))
          ((none) (mcp-error-result "give the place: line and column (from 1), or offset (from 0)"))
          (else (proc text path (vector-ref place 1))))))))

;; a path as a result names it: text given alone has none
(define (mcp-out-path path)
  (if (and (string? path) (string=? path mcp-text-path)) '() path))

;;; ---------------------------------------------------------------------------
;;; Results

(define (mcp-text-result text)
  (mcp-object "content" (vector (mcp-object "type" "text" "text" text))))

(define (mcp-json-result value)
  (mcp-text-result (mcp-json-text value)))

(define (mcp-error-result text)
  (mcp-put! (mcp-text-result text) "isError" #t))

;;; ---------------------------------------------------------------------------
;;; Documentation, written as markdown (the language server's shape)

(define (mcp-first-line s)
  (let ((i (string-index s #\newline))) (if i (substring s 0 i) s)))
(define (mcp-after-first-line s)
  (let ((i (string-index s #\newline))) (if i (substring s (+ i 1) (string-length s)) "")))

(define (mcp-lines-up-to text n)
  (let loop ((lines (string-split text #\newline)) (k 0) (acc '()))
    (cond ((null? lines) (string-join (reverse acc) "\n"))
          ((= k n) (string-append (string-join (reverse acc) "\n") "\n..."))
          (else (loop (cdr lines) (+ k 1) (cons (car lines) acc))))))

(define (mcp-markdown-documentation doc)
  (string-append "```cog-lisp\n" (mcp-first-line doc) "\n```"
                 (let ((rest (mcp-after-first-line doc))) (if (string=? rest "") "" (string-append "\n\n" rest)))))

(define (mcp-markdown-definition d)
  (string-append
   (if (definition-documentation d)
       (string-append (mcp-markdown-documentation (definition-documentation d)) "\n\n---\n\n")
       "")
   (let ((path (mcp-out-path (definition-path d))))
     (if (string? path) (string-append "Defined in " path ":\n\n") ""))
   "```cog-lisp\n" (mcp-lines-up-to (definition-source d) 20) "\n```"))

;;; ---------------------------------------------------------------------------
;;; The six tools (R-7)

;; --- lisp_check -------------------------------------------------------------

(define (mcp-problem-object starts p)
  (mcp-put! (mcp-range starts (problem-start p) (problem-end p))
            "severity" (symbol->string (problem-severity p))
            "message" (problem-message p)))

(define (mcp-check args)
  (mcp-with-source args
    (lambda (text path)
      (let* ((starts (mcp-line-starts text))
             (problems (mcp-object "problems"
                                   (list->vector (map (lambda (p) (mcp-problem-object starts p))
                                                      mcp-last-problems)))))
        (mcp-put! (mcp-json-result problems) "structuredContent" problems)))))

;; --- lisp_hover -------------------------------------------------------------

(define (mcp-hover args)
  (mcp-with-place args
    (lambda (text path offset)
      (let ((found (editor-symbol-at text offset)))
        (if (not found)
            (mcp-error-result "no name at that place")
            (let* ((name (car found))
                   (defs (editor-definitions-for path name))
                   (doc (documentation (editor-resolve path name))))
              (cond ((pair? defs) (mcp-text-result (mcp-markdown-definition (car defs))))
                    (doc (mcp-text-result (mcp-markdown-documentation doc)))
                    (else (mcp-error-result
                           (string-append name " is not a built-in, and "
                                          (if mcp-folder
                                              "no file of the workspace defines it"
                                              (mcp-no-workspace-note))))))))))))

;; --- lisp_definition --------------------------------------------------------

(define (mcp-definition-object d)
  (let* ((path (definition-path d))
         (text (and (string? path) (editor-indexed-text path)))
         (table (if text
                    (mcp-range (mcp-line-starts text) (definition-start d) (definition-end d))
                    (mcp-object "start" (definition-start d) "end" (definition-end d)))))
    (mcp-put! table
              "name" (definition-name d)
              "path" (mcp-out-path path)
              "documentation" (or (definition-documentation d) '())
              "source" (definition-source d))))

(define (mcp-definitions-result defs)
  (let ((answer (mcp-object "definitions" (list->vector (map mcp-definition-object defs)))))
    (unless mcp-folder (hash-table-set! answer "note" (mcp-no-workspace-note)))
    (mcp-json-result answer)))

(define (mcp-definition args)
  (let ((name (mcp-get args "name")))
    (cond ((and name (not (string? name))) (mcp-error-result "name must be a string"))
          ((and name (or (mcp-has? args "offset") (mcp-has? args "line") (mcp-has? args "column")))
           (mcp-error-result "give a name or a place, not both"))
          ((and name (not (mcp-has? args "path")) (not (mcp-has? args "text")))
           (mcp-refresh-index!)
           (mcp-definitions-result (editor-definitions-named name)))
          (name
           (mcp-with-source args (lambda (text path) (mcp-definitions-result (editor-definitions-for path name)))))
          (else
           (mcp-with-place args
             (lambda (text path offset)
               (let ((found (editor-symbol-at text offset)))
                 (if (not found)
                     (mcp-error-result "no name at that place")
                     (mcp-definitions-result (editor-definitions-for path (car found)))))))))))

;; --- lisp_completion --------------------------------------------------------

(define mcp-completion-limit 50)

(define (mcp-completion-object c)
  (mcp-object "label" (completion-label c)
              "kind" (symbol->string (completion-kind c))
              "detail" (completion-detail c)))

;; the first n of a list
(define (mcp-first-n items n)
  (let loop ((items items) (n n) (acc '()))
    (if (or (null? items) (<= n 0)) (reverse acc) (loop (cdr items) (- n 1) (cons (car items) acc)))))

(define (mcp-complete text path prefix limit)
  (let* ((matching (sort (filter (lambda (c) (string-prefix? prefix (completion-label c)))
                                 (editor-completions path))
                         (lambda (a b) (string<? (completion-label a) (completion-label b)))))
         (shown (mcp-first-n matching limit))
         (answer (mcp-object "prefix" prefix
                             "completions" (list->vector (map mcp-completion-object shown))
                             "more" (- (length matching) (length shown)))))
    (unless mcp-folder (hash-table-set! answer "note" (mcp-no-workspace-note)))
    (mcp-json-result answer)))

(define (mcp-completion args)
  (let ((prefix (mcp-get args "prefix")) (limit (mcp-get args "limit")))
    (cond ((and prefix (not (string? prefix))) (mcp-error-result "prefix must be a string"))
          ((and limit (not (and (mcp-integer? limit) (> limit 0))))
           (mcp-error-result "limit must be a whole number from 1"))
          ((and (not (mcp-has? args "path")) (not (mcp-has? args "text")))
           ;; no source: a path never checked, so no earlier request's imports
           (if prefix
               (begin (mcp-refresh-index!)
                      (mcp-complete "" "<no source>" prefix (or limit mcp-completion-limit)))
               (mcp-error-result "give a prefix, or path or text with a place")))
          (else
           (mcp-with-source args
             (lambda (text path)
               (let ((place (mcp-place text args)))
                 (cond ((eq? (vector-ref place 0) 'error) (mcp-error-result (vector-ref place 1)))
                       (prefix (mcp-complete text path prefix (or limit mcp-completion-limit)))
                       ((eq? (vector-ref place 0) 'none)
                        (mcp-error-result "give a prefix, or the place of the word to complete"))
                       (else
                        (let* ((offset (vector-ref place 1))
                               (found (editor-symbol-at text offset))
                               (word (if found (substring text (cadr found) (min offset (caddr found))) "")))
                          (mcp-complete text path word (or limit mcp-completion-limit))))))))))))

;; --- lisp_expand_macro ------------------------------------------------------

(define (mcp-expand-macro args)
  (mcp-with-place args
    (lambda (text path offset)
      (let ((call (editor-macro-call-at text offset)))
        (if (not call)
            (mcp-error-result "no macro call holds that place")
            (mcp-json-result (mcp-object "form" (car call) "expansion" (cdr call))))))))

;; --- lisp_format ------------------------------------------------------------

(define (mcp-format args)
  (let ((spaces (mcp-get args "insertSpaces")) (size (mcp-get args "tabSize"))
        (source (mcp-source args)))
    (cond ((eq? (vector-ref source 0) 'error) (mcp-error-result (vector-ref source 1)))
          ((and size (not (and (mcp-integer? size) (> size 0))))
           (mcp-error-result "tabSize must be a whole number from 1"))
          (else
           (let ((text (vector-ref source 1)))
             (guard (e (#t (mcp-error-result (string-append "cannot format: " (condition-report e)))))
               (mcp-text-result
                (if (eq? spaces #t) (format-source text 'spaces (or size 4)) (format-source text)))))))))

;;; ---------------------------------------------------------------------------
;;; The catalog: one list, read by tools/list and tools/call both (R-13)

(define (mcp-property type description)
  (mcp-object "type" type "description" description))

(define (mcp-schema . pairs)
  (mcp-object "type" "object"
              "additionalProperties" #f
              "properties" (apply mcp-object pairs)))

(define mcp-path-property
  (mcp-property "string" "The file, a path (absolute, or relative to the workspace folder). With text too, it names the file whose unsaved contents text is."))
(define mcp-text-property
  (mcp-property "string" "The source itself. With path, the unsaved contents of that file; alone, source with no file."))
(define mcp-line-property (mcp-property "integer" "The line of the place, from 1."))
(define mcp-column-property (mcp-property "integer" "The column of the place, in characters, from 1."))
(define mcp-offset-property (mcp-property "integer" "The place as a character offset from 0, instead of line and column."))

(define mcp-range-properties
  (mcp-object "start" (mcp-property "integer" "Offset of the first character, from 0.")
              "end" (mcp-property "integer" "Offset after the last character.")
              "line" (mcp-property "integer" "Line of the start, from 1.")
              "column" (mcp-property "integer" "Column of the start, from 1.")
              "endLine" (mcp-property "integer" "Line of the end, from 1.")
              "endColumn" (mcp-property "integer" "Column of the end, from 1.")))

(define mcp-check-output-schema
  (mcp-object
   "type" "object"
   "properties"
   (mcp-object
    "problems"
    (mcp-object "type" "array"
                "items" (mcp-object "type" "object"
                                    "properties" (mcp-put! (hash-table-copy mcp-range-properties)
                                                           "severity" (mcp-object "type" "string" "enum" (vector "error" "warning"))
                                                           "message" (mcp-property "string" "What is wrong."))
                                    "required" (vector "severity" "message" "start" "end" "line" "column"))))
   "required" (vector "problems")))

;; #(name title description input-schema output-schema-or-#f handler)
(define mcp-tools
  (list
   (vector "lisp_check" "Check cog-lisp source"
           "Use before running a cog-lisp file, and again after every edit. Lists the problems compiling it would meet, without running it: read errors, compile errors, and warnings such as a name nothing defines. Each has its severity, message, line and column. An empty list means it compiles. Give path, or path and text for unsaved source."
           (mcp-schema "path" mcp-path-property "text" mcp-text-property)
           mcp-check-output-schema
           mcp-check)
   (vector "lisp_hover" "What a name means"
           "Use before calling a name you are not sure of. Answers its call form and documentation: a built-in's, or, for a name the project defines, its documentation and source. Give the source (path, text or both) and the place of the name: line and column, or offset."
           (mcp-schema "path" mcp-path-property "text" mcp-text-property
                       "line" mcp-line-property "column" mcp-column-property "offset" mcp-offset-property)
           #f
           mcp-hover)
   (vector "lisp_definition" "Where a name is defined"
           "Finds where a name is defined in the project's files: give name, or the source and the place of a name in it (line and column, or offset). Each definition gives its path, line, column, documentation and source. Built-ins have none: use lisp_hover for them."
           (mcp-schema "name" (mcp-property "string" "The name to find, instead of a place.")
                       "path" mcp-path-property "text" mcp-text-property
                       "line" mcp-line-property "column" mcp-column-property "offset" mcp-offset-property)
           #f
           mcp-definition)
   (vector "lisp_completion" "Find a name"
           "Use to find the right name: the built-ins, the file's imports and the project's names that start with prefix, sorted, at most limit of them (50 by default), and how many more there were. Give prefix, or the source and the place of a word to complete (line and column, or offset)."
           (mcp-schema "prefix" (mcp-property "string" "The start of the name.")
                       "limit" (mcp-property "integer" "At most this many names; 50 by default.")
                       "path" mcp-path-property "text" mcp-text-property
                       "line" mcp-line-property "column" mcp-column-property "offset" mcp-offset-property)
           #f
           mcp-completion)
   (vector "lisp_expand_macro" "Expand a macro call"
           "Use when a macro call does not do what you expect. Answers the innermost macro call holding the place, and its full expansion: the code that actually runs. Give the source and the place (line and column, or offset)."
           (mcp-schema "path" mcp-path-property "text" mcp-text-property
                       "line" mcp-line-property "column" mcp-column-property "offset" mcp-offset-property)
           #f
           mcp-expand-macro)
   (vector "lisp_format" "Format cog-lisp source"
           "Use after editing a file. Answers the source laid out as cog-lisp lays it out (indentation and line breaks); write it back to the file. It changes no file itself. Indents with tabs unless insertSpaces is true."
           (mcp-schema "path" mcp-path-property "text" mcp-text-property
                       "insertSpaces" (mcp-property "boolean" "Indent with spaces instead of tabs.")
                       "tabSize" (mcp-property "integer" "Spaces in one step of indentation, with insertSpaces; 4 by default."))
           #f
           mcp-format)))

(define (mcp-tool-name tool) (vector-ref tool 0))
(define (mcp-tool-handler tool) (vector-ref tool 5))

(define (mcp-tool-named name)
  (find (lambda (tool) (string=? (mcp-tool-name tool) name)) mcp-tools))

(define (mcp-tool-object tool)
  (let ((object (mcp-object "name" (vector-ref tool 0)
                            "title" (vector-ref tool 1)
                            "description" (vector-ref tool 2)
                            "inputSchema" (vector-ref tool 3)
                            "annotations" (mcp-object "title" (vector-ref tool 1)
                                                      "readOnlyHint" #t
                                                      "openWorldHint" #f))))
    (when (vector-ref tool 4) (hash-table-set! object "outputSchema" (vector-ref tool 4)))
    object))

;; the arguments a tool's schema does not name, which it refuses (additionalProperties)
(define (mcp-unknown-arguments tool arguments)
  (let ((known (mcp-get (vector-ref tool 3) "properties")))
    (filter (lambda (key) (not (hash-table-contains? known key))) (hash-table-keys arguments))))

;;; ---------------------------------------------------------------------------
;;; The protocol (R-3 to R-5, R-10 to R-12): mcp-handle, a message in, its reply
;;; out (R-20). An answer inside is #(ok result) or #(error code message data).

(define (mcp-ok result) (vector 'ok result))
(define (mcp-fail code message . data) (vector 'error code message (if (pair? data) (car data) #f)))

(define (mcp-tools-call params)
  (let* ((name (mcp-get params "name"))
         (arguments (let ((a (mcp-get params "arguments"))) (if (hash-table? a) a (mcp-object))))
         (tool (and (string? name) (mcp-tool-named name))))
    (cond ((not tool)
           (mcp-fail -32602 (string-append "unknown tool: " (if (string? name) name "(none given)"))))
          ((pair? (mcp-unknown-arguments tool arguments))
           (mcp-fail -32602 (string-append name " takes no argument "
                                           (string-join (mcp-unknown-arguments tool arguments) ", "))))
          (else
           (mcp-ok (guard (e (#t (mcp-error-result (string-append "cog-lisp: " (condition-report e)))))
                     ((mcp-tool-handler tool) arguments)))))))

(define (mcp-tools-list) (mcp-object "tools" (list->vector (map mcp-tool-object mcp-tools))))

(define (mcp-with-cache-hints result)
  (mcp-put! result "ttlMs" 0 "cacheScope" "public"))

;; what both eras answer the same
(define (mcp-common method params)
  (cond ((string=? method "ping") (mcp-ok (mcp-object)))
        ((string=? method "tools/list") (mcp-ok (mcp-tools-list)))
        ((string=? method "tools/call") (mcp-tools-call params))
        (else (mcp-fail -32601 (string-append "cog-lisp does not handle " method)))))

(define (mcp-legacy method params)
  (if (string=? method "initialize")
      (let ((requested (mcp-get params "protocolVersion")))
        (mcp-ok (mcp-object "protocolVersion" (if (member requested mcp-legacy-versions) requested mcp-legacy-version)
                            "capabilities" (mcp-object "tools" (mcp-object))
                            "serverInfo" (mcp-server-info)
                            "instructions" mcp-instructions)))
      (mcp-common method params)))

(define (mcp-modern method params)
  (let* ((meta (mcp-get params "_meta"))
         (version (mcp-get meta mcp-meta-version)))
    (cond ((not (and (string? version) (string=? version mcp-modern-version)))
           (mcp-fail -32022 "Unsupported protocol version"
                     (mcp-object "supported" (vector mcp-modern-version mcp-legacy-version)
                                 "requested" (if (string? version) version '()))))
          ((not (mcp-has? meta mcp-meta-capabilities))
           (mcp-fail -32602 (string-append "_meta must carry " mcp-meta-capabilities)))
          (else
           (let ((answer (if (string=? method "server/discover")
                             (mcp-ok (mcp-object "supportedVersions" (vector mcp-modern-version)
                                                 "capabilities" (mcp-object "tools" (mcp-object))
                                                 "instructions" mcp-instructions))
                             (mcp-common method params))))
             (when (eq? (vector-ref answer 0) 'ok)
               (let ((result (vector-ref answer 1)))
                 (when (member method '("server/discover" "tools/list")) (mcp-with-cache-hints result))
                 (mcp-put! result "resultType" "complete"
                           "_meta" (mcp-object mcp-meta-server (mcp-server-info)))))
             answer)))))

;; is a request modern, from its own contents? (R-3)
(define (mcp-modern? method params)
  (or (string=? method "server/discover")
      (mcp-has? (mcp-get params "_meta") mcp-meta-version)))

(define (mcp-response id answer)
  (if (eq? (vector-ref answer 0) 'ok)
      (mcp-object "jsonrpc" "2.0" "id" id "result" (vector-ref answer 1))
      (let ((error (mcp-object "code" (vector-ref answer 1) "message" (vector-ref answer 2))))
        (when (vector-ref answer 3) (hash-table-set! error "data" (vector-ref answer 3)))
        (mcp-object "jsonrpc" "2.0" "id" id "error" error))))

(define (mcp-handle message)
  "(mcp-handle message)
The reply to one parsed message (a hash table), or #f for a notification or a response."
  (if (not (hash-table? message))
      (mcp-response '() (mcp-fail -32600 "a message is a JSON object"))
      (let ((id (if (mcp-has? message "id") (hash-table-ref message "id") #f))
            (method (mcp-get message "method"))
            (params (let ((p (mcp-get message "params"))) (if (hash-table? p) p (mcp-object)))))
        (cond ((not (string? method))
               (and id (not (mcp-has? message "result")) (not (mcp-has? message "error"))
                    (mcp-response id (mcp-fail -32600 "a request names its method"))))
              ((not id) #f)                         ; a notification: nothing to answer
              (else
               (mcp-response id
                             (guard (e (#t (mcp-fail -32603 (condition-report e))))
                               (if (mcp-modern? method params)
                                   (mcp-modern method params)
                                   (mcp-legacy method params)))))))))

;;; ---------------------------------------------------------------------------
;;; The stdio transport (R-2, R-12): a line is a message; a line that is not
;;; JSON is answered, not fatal; the end of input is the end.

(define (mcp-strip-cr line)
  (let ((n (string-length line)))
    (if (and (> n 0) (eq? (string-ref line (- n 1)) #\return))
        (substring line 0 (- n 1))
        line)))

(define (mcp-send! reply)
  (json-write reply)
  (newline))

(define (mcp-serve-stdio)
  (let loop ()
    (let ((line (read-line)))
      (unless (eof-object? line)
        (let ((text (mcp-strip-cr line)))
          (unless (string=? text "")
            (let ((message (guard (e (#t (mcp-log! (string-append "not JSON: " (condition-report e)))
                                         'unreadable))
                             (json-read text))))
              (if (eq? message 'unreadable)
                  (mcp-send! (mcp-response '() (mcp-fail -32700 "Parse error: not JSON")))
                  (let ((reply (guard (e (#t (mcp-log! (condition-report e)) #f)) (mcp-handle message))))
                    (when reply (mcp-send! reply)))))))
        (loop)))))

;;; ---------------------------------------------------------------------------
;;; Run as a program (not loaded by a test): the folder after the script, then
;;; serve until the input ends.

(define (mcp-program?)
  (let ((line (command-line)))
    (and (pair? line) (string? (car line))
         [[(car line) copyReplaceAll: "\\" with: "/"] endsWith: "/mcp.lisp"]
         [[[[(car line) asFileReference] parent] basename] = "lib"])))

(when (mcp-program?)
  (let ((args (cdr (command-line))))
    (when (pair? args)
      (mcp-set-folder! (car args))
      (unless mcp-folder (mcp-log! (string-append "no such folder: " (car args) "; serving with no workspace")))))
  (mcp-serve-stdio))
