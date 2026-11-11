;;; lsp.lisp -- cog-lisp's language server, served by the image itself
;;; (specs/16-phase-10-documentation-and-editor.md step 10.5)
;;;
;;;   ./cog-lisp.sh lib/lsp.lisp       (cog-lisp.bat lib\lsp.lisp on Windows)
;;;
;;; It speaks the Language Server Protocol on standard input and output: each
;;; message a JSON text framed with a Content-Length header (read-framed-message,
;;; write-framed-message). JSON is Pharo's STONJSON, so a message is a Smalltalk
;;; Dictionary, reached through interop, and a JSON array is a vector.
;;;
;;; It serves hover, completion, go to definition, diagnostics, macro
;;; expansion (the cog-lisp/expand request) and formatting (format-source,
;;; specs/26-formatter.md R-4). What it knows about the source is
;;; editor-services' (specs/34-morphic-ide.md R-29), which the image's own
;;; editor asks too: this file is the protocol, its JSON, its framing, and its
;;; positions, counted in UTF-16 units where the services count characters.

;;; ---------------------------------------------------------------------------
;;; JSON

(require 'format-source)
(require 'editor-services)

(define (lsp-parse text) [(smalltalk STONJSON) fromString: text])
(define (lsp-text object) [(smalltalk STONJSON) toString: object])

;; d[key], or #f when it has none (a JSON null is #f too)
(define (lsp-get d key)
  (if [d isKindOf: (smalltalk Dictionary)]
      (let ((v [d at: key ifAbsent: (lambda () #f)]))
        (if (smalltalk-nil? v) #f v))
      #f))

;; d[k1][k2]...
(define (lsp-path d . keys)
  (let loop ((d d) (keys keys))
    (cond ((null? keys) d)
          ((not d) #f)
          (else (loop (lsp-get d (car keys)) (cdr keys))))))

;; a JSON object of the keys and values: (lsp-object "a" 1 "b" #t)
(define (lsp-object . pairs)
  (let ((d [(smalltalk Dictionary) new]))
    (let loop ((ps pairs))
      (when (pair? ps)
        [d at: (car ps) put: (car (cdr ps))]
        (loop (cdr (cdr ps)))))
    d))

(define lsp-null (smalltalk-nil))

(define (lsp-filter pred l)
  (cond ((null? l) '())
        ((pred (car l)) (cons (car l) (lsp-filter pred (cdr l))))
        (else (lsp-filter pred (cdr l)))))

;;; ---------------------------------------------------------------------------
;;; Messages

(define (lsp-send! object) (write-framed-message (lsp-text object)))

(define (lsp-respond! id result)
  (lsp-send! (lsp-object "jsonrpc" "2.0" "id" id "result" result)))

(define (lsp-respond-error! id code message)
  (lsp-send! (lsp-object "jsonrpc" "2.0" "id" id "error" (lsp-object "code" code "message" message))))

(define (lsp-notify! method params)
  (lsp-send! (lsp-object "jsonrpc" "2.0" "method" method "params" params)))

;;; ---------------------------------------------------------------------------
;;; Positions. The protocol counts a line's characters in UTF-16 units; a
;;; cog-lisp string counts characters, and one outside the Basic Multilingual
;;; Plane is two units. A text's lines are kept as a vector of their start offsets.

(define (lsp-line-starts text)
  (let ((n (string-length text)))
    (let loop ((i 0) (starts (list 0)))
      (cond ((= i n) (list->vector (reverse starts)))
            ((eq? (string-ref text i) #\newline) (loop (+ i 1) (cons (+ i 1) starts)))
            (else (loop (+ i 1) starts))))))

(define (lsp-units c) (if (> (char->integer c) 65535) 2 1))

;; the line holding offset, by binary search
(define (lsp-line-of starts offset)
  (let loop ((lo 0) (hi (- (vector-length starts) 1)))
    (if (>= lo hi)
        lo
        (let ((mid (quotient (+ lo hi 1) 2)))
          (if (<= (vector-ref starts mid) offset) (loop mid hi) (loop lo (- mid 1)))))))

;; an offset in text as a protocol position
(define (lsp-position text starts offset)
  (let* ((line (lsp-line-of starts offset))
         (start (vector-ref starts line)))
    (let loop ((i start) (units 0))
      (if (>= i offset)
          (lsp-object "line" line "character" units)
          (loop (+ i 1) (+ units (lsp-units (string-ref text i))))))))

(define (lsp-range text starts from to)
  (lsp-object "start" (lsp-position text starts from) "end" (lsp-position text starts to)))

;; a protocol position as an offset in text
(define (lsp-offset text starts line character)
  (if (>= line (vector-length starts))
      (string-length text)
      (let ((n (string-length text)))
        (let loop ((i (vector-ref starts line)) (units 0))
          (if (or (>= units character) (>= i n) (eq? (string-ref text i) #\newline))
              i
              (loop (+ i 1) (+ units (lsp-units (string-ref text i)))))))))

;;; ---------------------------------------------------------------------------
;;; URIs and paths

(define lsp-windows [[(smalltalk OSPlatform) current] isWindows])

(define (lsp-hex-value c) (string-index "0123456789abcdef" (char-downcase c)))

(define (lsp-percent-decode s)
  (let ((n (string-length s)))
    (let loop ((i 0) (chars '()))
      (cond ((= i n) (list->string (reverse chars)))
            ((and (eq? (string-ref s i) #\%) (< (+ i 2) n)
                  (lsp-hex-value (string-ref s (+ i 1))) (lsp-hex-value (string-ref s (+ i 2))))
             (loop (+ i 3) (cons (integer->char (+ (* 16 (lsp-hex-value (string-ref s (+ i 1))))
                                                   (lsp-hex-value (string-ref s (+ i 2)))))
                                 chars)))
            (else (loop (+ i 1) (cons (string-ref s i) chars)))))))

;; file:///c%3A/x/y.lisp -> c:/x/y.lisp (Windows), file:///x/y.lisp -> /x/y.lisp
(define (lsp-uri->path uri)
  (let* ((p (lsp-percent-decode (if [uri beginsWith: "file://"] (substring uri 7) uri))))
    (if (and lsp-windows (> (string-length p) 2) (eq? (string-ref p 0) #\/) (eq? (string-ref p 2) #\:))
        (substring p 1)
        p)))

;; a key for a file, the same whichever way its path or URI was written
(define (lsp-key path) (editor-key path))

(define (lsp-path->uri path)
  (let* ((p [path copyReplaceAll: "\\" with: "/"])
         (p [p copyReplaceAll: "%" with: "%25"])
         (p [p copyReplaceAll: " " with: "%20"])
         (p [p copyReplaceAll: "#" with: "%23"]))
    (if (and (> (string-length p) 0) (eq? (string-ref p 0) #\/))
        (string-append "file://" p)
        (string-append "file:///" p))))

;;; ---------------------------------------------------------------------------
;;; Documents the editor has open: key -> #(uri text line-starts)

(define lsp-documents (make-hash-table equal?))

(define (lsp-open! uri text)
  (hash-table-set! lsp-documents (lsp-key (lsp-uri->path uri)) (vector uri text (lsp-line-starts text))))

(define (lsp-document uri) (hash-table-ref/default lsp-documents (lsp-key (lsp-uri->path uri)) #f))

;;; ---------------------------------------------------------------------------
;;; The workspace index is editor-services'. A definition's place goes back to the
;;; editor as the URI it sent for that file, or one made from its path, and a
;;; range in its text's lines.

;; key -> the URI the editor named a file by
(define lsp-uris (make-hash-table equal?))

(define (lsp-index-text! uri text)
  (let ((path (lsp-uri->path uri)))
    (hash-table-set! lsp-uris (lsp-key path) uri)
    (editor-index-text! path text)))

(define (lsp-index-file! path) (editor-index-file! path))

(define (lsp-def-uri d)
  (let ((path (definition-path d)))
    (hash-table-ref/default lsp-uris (lsp-key path) (lsp-path->uri path))))

;; key -> (text . its line starts), made again when the indexed text changes
(define lsp-starts-cache (make-hash-table equal?))
(define (lsp-starts-of path text)
  (let* ((key (lsp-key path)) (cached (hash-table-ref/default lsp-starts-cache key #f)))
    (if (and cached (eq? (car cached) text))
        (cdr cached)
        (let ((starts (lsp-line-starts text)))
          (hash-table-set! lsp-starts-cache key (cons text starts))
          starts))))

(define (lsp-def-range d)
  (let* ((path (definition-path d)) (text (editor-indexed-text path)))
    (lsp-range text (lsp-starts-of path text) (definition-start d) (definition-end d))))

;;; ---------------------------------------------------------------------------
;;; What is under the cursor

;; the document and offset a request is about: #(text starts offset), or #f
(define (lsp-request-place params)
  (let ((doc (lsp-document (lsp-path params "textDocument" "uri"))))
    (and doc
         (let ((text (vector-ref doc 1)) (starts (vector-ref doc 2)))
           (vector text starts
                   (lsp-offset text starts (lsp-path params "position" "line") (lsp-path params "position" "character")))))))

(define (lsp-request-path params) (lsp-uri->path (lsp-path params "textDocument" "uri")))

;;; ---------------------------------------------------------------------------
;;; Hover

(define (lsp-first-line s)
  (let ((i (string-index s #\newline))) (if i (substring s 0 i) s)))
(define (lsp-after-first-line s)
  (let ((i (string-index s #\newline))) (if i (substring s (+ i 1)) "")))

;; at most n lines of text
(define (lsp-lines-up-to text n)
  (let loop ((lines (string-split text #\newline)) (k 0) (acc '()))
    (cond ((null? lines) (string-join (reverse acc) "\n"))
          ((= k n) (string-append (string-join (reverse acc) "\n") "\n..."))
          (else (loop (cdr lines) (+ k 1) (cons (car lines) acc))))))

(define (lsp-markdown-documentation doc)
  (string-append "```cog-lisp\n" (lsp-first-line doc) "\n```"
                 (let ((rest (lsp-after-first-line doc))) (if (string=? rest "") "" (string-append "\n\n" rest)))))

;; a definition in the workspace: its documentation if it has some, and its source
(define (lsp-markdown-definition d)
  (string-append
   (if (definition-documentation d) (string-append (lsp-markdown-documentation (definition-documentation d)) "\n\n---\n\n") "")
   "```cog-lisp\n" (lsp-lines-up-to (definition-source d) 20) "\n```"))

;;; Namespaces (specs/27-namespaces.md R-13): each document is checked in a unit of
;;; its own (editor-check), so a name means what it means in that document: an
;;; import (con:rule as engine:rule), or a library's full name.

(define (lsp-hover params)
  (let* ((place (lsp-request-place params))
         (path (lsp-request-path params))
         (found (and place (editor-symbol-at (vector-ref place 0) (vector-ref place 2)))))
    (if (not found)
        lsp-null
        (let* ((name (car found))
               (defs (editor-definitions-for path name))
               (doc (documentation (editor-resolve path name)))
               (value (cond ((pair? defs) (lsp-markdown-definition (car defs)))
                            (doc (lsp-markdown-documentation doc))
                            (else #f))))
          (if (not value)
              lsp-null
              (lsp-object "contents" (lsp-object "kind" "markdown" "value" value)
                          "range" (lsp-range (vector-ref place 0) (vector-ref place 1)
                                             (car (cdr found)) (car (cdr (cdr found))))))))))

;;; ---------------------------------------------------------------------------
;;; Completion: editor-services' names, as the protocol's items. A built-in's item
;;; is the same record each time, so its JSON is made once.

(define lsp-function-kind 3)
(define lsp-variable-kind 6)
(define lsp-keyword-kind 14)

(define lsp-items (make-hash-table eq?))

(define (lsp-completion-item c)
  (or (hash-table-ref/default lsp-items c #f)
      (let ((item (lsp-object "label" (completion-label c)
                              "kind" (case (completion-kind c)
                                       ((keyword) lsp-keyword-kind)
                                       ((function) lsp-function-kind)
                                       (else lsp-variable-kind))
                              "detail" (completion-detail c))))
        (unless (string=? (completion-documentation c) "")
          [item at: "documentation" put: (completion-documentation c)])
        (hash-table-set! lsp-items c item)
        item)))

(define (lsp-completion params)
  (list->vector (map lsp-completion-item (editor-completions (lsp-request-path params)))))

;;; ---------------------------------------------------------------------------
;;; Go to definition

(define (lsp-definition params)
  (let* ((place (lsp-request-place params))
         (found (and place (editor-symbol-at (vector-ref place 0) (vector-ref place 2)))))
    (if (not found)
        lsp-null
        (list->vector (map (lambda (d) (lsp-object "uri" (lsp-def-uri d) "range" (lsp-def-range d)))
                           (editor-definitions-for (lsp-request-path params) (car found)))))))

;;; ---------------------------------------------------------------------------
;;; Diagnostics: editor-services' problems, placed in the document's lines

(define lsp-error-severity 1)
(define lsp-warning-severity 2)

(define (lsp-diagnostics-in uri text)
  (let ((starts (lsp-line-starts text)))
    (map (lambda (p)
           (lsp-object "range" (lsp-range text starts (problem-start p) (problem-end p))
                       "severity" (if (eq? (problem-severity p) 'warning) lsp-warning-severity lsp-error-severity)
                       "source" "cog-lisp" "message" (problem-message p)))
         (editor-check (lsp-uri->path uri) text))))

(define (lsp-publish-diagnostics! uri)
  (let ((doc (lsp-document uri)))
    (when doc
      (lsp-notify! "textDocument/publishDiagnostics"
                   (lsp-object "uri" uri "diagnostics" (list->vector (lsp-diagnostics-in uri (vector-ref doc 1))))))))

;;; ---------------------------------------------------------------------------
;;; Expanding the macro call at the cursor (the cog-lisp/expand request)

(define (lsp-expand params)
  (let* ((place (lsp-request-place params))
         (found (and place (editor-macro-call-at (vector-ref place 0) (vector-ref place 2)))))
    (if (not found)
        lsp-null
        (lsp-object "form" (car found) "expansion" (cdr found)))))

;;; ---------------------------------------------------------------------------
;;; The protocol

(define (lsp-initialize params)
  (let ((folders (lsp-get params "workspaceFolders")))
    (set! lsp-roots
          (cond ((and folders (> [folders size] 0))
                 (map (lambda (f) (lsp-uri->path (lsp-get f "uri"))) (vector->list [folders asArray])))
                ((lsp-get params "rootUri") (list (lsp-uri->path (lsp-get params "rootUri"))))
                (else '()))))
  (lsp-object
   "capabilities" (lsp-object "textDocumentSync" 1
                              "hoverProvider" #t
                              "completionProvider" (lsp-object "resolveProvider" #f)
                              "definitionProvider" #t
                              "documentFormattingProvider" #t)
   ;; the image's version, which the extension compares with its own
   ;; (specs/28-versioning.md R-11)
   "serverInfo" (lsp-object "name" "cog-lisp" "version" (hash-table-ref/default *env* 'version "dev"))))

(define lsp-roots '())

(define (lsp-index-workspace!)
  (for-each (lambda (root)
              (let ((dir [root asFileReference]))
                (when [dir isDirectory] (guard (e (#t #f)) (editor-index-folder! dir)))))
            lsp-roots))

(define lsp-shutting-down #f)

(define (lsp-changed! uri text)
  (lsp-open! uri text)
  (lsp-index-text! uri text)
  (lsp-publish-diagnostics! uri))

;; textDocument/formatting (specs/26-formatter.md R-4): one edit replacing the whole
;; document, indented as the request's options say; none if nothing changes. Text
;; that does not read is an error, answered as one, and the document is untouched.
(define (lsp-formatting params)
  (let ((doc (lsp-document (lsp-path params "textDocument" "uri"))))
    (if (not doc)
        (vector)
        (let* ((text (vector-ref doc 1))
               (spaces? (eq? (lsp-path params "options" "insertSpaces") #t))
               (size (let ((n (lsp-path params "options" "tabSize"))) (if (number? n) n 4)))
               (formatted (if spaces? (format-source text 'spaces size) (format-source text))))
          (if (string=? formatted text)
              (vector)
              (vector (lsp-object "range" (lsp-range text (vector-ref doc 2) 0 (string-length text))
                                  "newText" formatted)))))))

;; one message: a request (it has an id) gets a response; a notification none
(define (lsp-handle! message)
  (let ((id (lsp-get message "id"))
        (method (lsp-get message "method"))
        (params (lsp-get message "params")))
    (cond ((not method) #f)                                   ; a response to us: none expected
          ((string=? method "initialize") (lsp-respond! id (lsp-initialize params)))
          ((string=? method "initialized") (lsp-index-workspace!))
          ((string=? method "textDocument/didOpen")
           (lsp-changed! (lsp-path params "textDocument" "uri") (lsp-path params "textDocument" "text")))
          ((string=? method "textDocument/didChange")
           (let ((changes (lsp-get params "contentChanges")))
             (when (and changes (> [changes size] 0))
               (lsp-changed! (lsp-path params "textDocument" "uri") (lsp-get [changes last] "text")))))
          ((string=? method "textDocument/didClose")
           (let ((uri (lsp-path params "textDocument" "uri")))
             (hash-table-delete! lsp-documents (lsp-key (lsp-uri->path uri)))
             ;; the index keeps the file as it is on disk
             (lsp-index-file! (lsp-uri->path uri))
             (lsp-notify! "textDocument/publishDiagnostics" (lsp-object "uri" uri "diagnostics" (vector)))))
          ((string=? method "textDocument/hover") (lsp-respond! id (lsp-hover params)))
          ((string=? method "textDocument/completion") (lsp-respond! id (lsp-completion params)))
          ((string=? method "textDocument/definition") (lsp-respond! id (lsp-definition params)))
          ((string=? method "cog-lisp/expand") (lsp-respond! id (lsp-expand params)))
          ((string=? method "textDocument/formatting") (lsp-respond! id (lsp-formatting params)))
          ((string=? method "shutdown") (set! lsp-shutting-down #t) (lsp-respond! id lsp-null))
          ((string=? method "exit") (exit (if lsp-shutting-down 0 1)))
          (id (lsp-respond-error! id -32601 (string-append "cog-lisp does not handle " method)))
          (else #f))))                                        ; an unknown notification

;; serve until the input ends; an error in one message is answered, not fatal
(define (lsp-serve)
  (let loop ()
    (let ((text (read-framed-message)))
      (unless (eof-object? text)
        (let ((message (guard (e (#t #f)) (lsp-parse text))))
          (when message
            (guard (e (#t (let ((id (lsp-get message "id")))
                            (when id (lsp-respond-error! id -32603 (condition-report e))))))
              (lsp-handle! message))))
        (loop)))))

(lsp-serve)
