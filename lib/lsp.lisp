;;; lsp.lisp -- cog-lisp's language server, served by the image itself
;;; (specs/phase-10-documentation-and-editor.md step 10.5)
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
;;; specs/formatter.md R-4). It reads the workspace's .lisp files
;;; but never runs them, except a document's top-level define-syntax,
;;; define-macro and require forms, so later forms expand as they will when the
;;; file runs (the owner's decision 4; require, specs/library-path.md AC-5).

;;; ---------------------------------------------------------------------------
;;; JSON

(require 'format-source)

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
(define (lsp-key path)
  (let ((p [path copyReplaceAll: "\\" with: "/"]))
    (if lsp-windows (string-downcase p) p)))

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
;;; The workspace index: the top-level definitions of every .lisp file, read but
;;; never run. key -> list of #(name uri range documentation source)

(define lsp-index (make-hash-table equal?))
(define lsp-skipped-folders '("pharo" "node_modules" ".vscode-test" ".git" "dist"))

(define (lsp-def-name e) (vector-ref e 0))
(define (lsp-def-uri e) (vector-ref e 1))
(define (lsp-def-range e) (vector-ref e 2))
(define (lsp-def-documentation e) (vector-ref e 3))
(define (lsp-def-source e) (vector-ref e 4))

(define (lsp-head-is? d name) (and (pair? d) (eq? (car d) name)))

;; a top-level form's definition: (name . documentation), or #f
(define (lsp-definition-of d)
  (cond ((not (and (pair? d) (pair? (cdr d)))) #f)
        ((or (lsp-head-is? d 'define) (lsp-head-is? d 'define-macro))
         (let ((target (car (cdr d))) (rest (cdr (cdr d))))
           (cond ((and (pair? target) (symbol? (car target)))
                  (cons (car target) (and (pair? rest) (string? (car rest)) (pair? (cdr rest)) (car rest))))
                 ((symbol? target)
                  (cons target (and (pair? rest) (pair? (car rest)) (eq? (car (car rest)) 'lambda)
                                    (let ((body (cdr (cdr (car rest)))))
                                      (and (pair? body) (string? (car body)) (pair? (cdr body)) (car body))))))
                 (else #f))))
        ((lsp-head-is? d 'define-syntax)
         (let ((target (car (cdr d))) (rest (cdr (cdr d))))
           (and (symbol? target)
                (cons target (and (pair? rest) (string? (car rest)) (pair? (cdr rest)) (car rest))))))
        (else #f)))

;; every top-level definition in text, until a read error
(define (lsp-definitions uri text)
  (let ((r (make-reader text)) (starts (lsp-line-starts text)))
    (let loop ((acc '()))
      (let ((d (guard (e (#t (eof-object))) (reader-next r))))
        (if (eof-object? d)
            (reverse acc)
            (let ((def (lsp-definition-of d)))
              (loop (if def
                        (let ((from (reader-datum-start r)) (to (reader-position r)))
                          (cons (vector (symbol->string (car def)) uri (lsp-range text starts from to) (cdr def)
                                        (substring text from to))
                                acc))
                        acc))))))))

(define (lsp-index-text! key uri text)
  (hash-table-set! lsp-index key (lsp-definitions uri text)))

(define (lsp-index-file! path)
  (let ((text (guard (e (#t #f)) [[[path asFileReference] contents] asString])))
    (when text (lsp-index-text! (lsp-key path) (lsp-path->uri path) text))))

(define (lsp-index-folder! folder)
  (for-each (lambda (entry)
              (let ((name [entry basename]))
                (cond ([entry isDirectory]
                       (unless (member name lsp-skipped-folders) (lsp-index-folder! entry)))
                      ([name endsWith: ".lisp"]
                       (lsp-index-file! [entry fullName])))))
            (vector->list [[folder children] asArray])))

(define (lsp-definitions-named name)
  (let ((acc '()))
    (hash-table-walk lsp-index
                     (lambda (key defs)
                       (for-each (lambda (d) (when (string=? (lsp-def-name d) name) (set! acc (cons d acc)))) defs)))
    (reverse acc)))

;;; ---------------------------------------------------------------------------
;;; What is under the cursor

(define lsp-delimiters (string->list " \t\r\n()[]\";'`,"))
(define (lsp-delimiter? c) (memv c lsp-delimiters))

;; the symbol around offset in text: (name start end), or #f
(define (lsp-symbol-at text offset)
  (let* ((n (string-length text))
         (start (let back ((s (min offset n))) (if (and (> s 0) (not (lsp-delimiter? (string-ref text (- s 1))))) (back (- s 1)) s)))
         (end (let ahead ((e (min offset n))) (if (and (< e n) (not (lsp-delimiter? (string-ref text e)))) (ahead (+ e 1)) e))))
    (and (< start end) (list (substring text start end) start end))))

;; the document and offset a request is about: #(text starts offset), or #f
(define (lsp-request-place params)
  (let ((doc (lsp-document (lsp-path params "textDocument" "uri"))))
    (and doc
         (let ((text (vector-ref doc 1)) (starts (vector-ref doc 2)))
           (vector text starts
                   (lsp-offset text starts (lsp-path params "position" "line") (lsp-path params "position" "character")))))))

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
   (if (lsp-def-documentation d) (string-append (lsp-markdown-documentation (lsp-def-documentation d)) "\n\n---\n\n") "")
   "```cog-lisp\n" (lsp-lines-up-to (lsp-def-source d) 20) "\n```"))

(define (lsp-hover params)
  (let* ((place (lsp-request-place params))
         (found (and place (lsp-symbol-at (vector-ref place 0) (vector-ref place 2)))))
    (if (not found)
        lsp-null
        (let* ((name (car found))
               (defs (lsp-definitions-named name))
               (doc (documentation (string->symbol name)))
               (value (cond ((pair? defs) (lsp-markdown-definition (car defs)))
                            (doc (lsp-markdown-documentation doc))
                            (else #f))))
          (if (not value)
              lsp-null
              (lsp-object "contents" (lsp-object "kind" "markdown" "value" value)
                          "range" (lsp-range (vector-ref place 0) (vector-ref place 1)
                                             (car (cdr found)) (car (cdr (cdr found))))))))))

;;; ---------------------------------------------------------------------------
;;; Completion: the documented built-ins and the special forms, made once, and
;;; the names the workspace defines

(define lsp-function-kind 3)
(define lsp-variable-kind 6)
(define lsp-keyword-kind 14)

(define (lsp-builtin-items)
  (let ((items '()))
    (for-each (lambda (name)
                (let ((doc (documentation name)))
                  (set! items (cons (lsp-object "label" (symbol->string name) "kind" lsp-keyword-kind
                                                "detail" (if doc (lsp-first-line doc) "special form")
                                                "documentation" (if doc (lsp-after-first-line doc) ""))
                                    items))))
              (special-form-names))
    [[(smalltalk LispEnvironment) default]
     cellsDo: (lambda (cell)
                (when [cell isBound]
                  (let* ((name [cell symbol]) (doc (documentation name)) (value [cell value]))
                    (when (and doc (not (memq name (special-form-names))))
                      (set! items (cons (lsp-object "label" (symbol->string name)
                                                    "kind" (if [value isKindOf: (smalltalk LispMacro)] lsp-keyword-kind lsp-function-kind)
                                                    "detail" (lsp-first-line doc)
                                                    "documentation" (lsp-after-first-line doc))
                                        items))))))]
    items))

(define lsp-builtins #f)

(define (lsp-completion params)
  (unless lsp-builtins (set! lsp-builtins (lsp-builtin-items)))
  (let ((seen (make-hash-table equal?)) (items '()))
    (for-each (lambda (item) (hash-table-set! seen [item at: "label"] #t) (set! items (cons item items))) lsp-builtins)
    (hash-table-walk lsp-index
                     (lambda (key defs)
                       (for-each (lambda (d)
                                   (unless (hash-table-contains? seen (lsp-def-name d))
                                     (hash-table-set! seen (lsp-def-name d) #t)
                                     (set! items (cons (lsp-object "label" (lsp-def-name d) "kind" lsp-variable-kind
                                                                   "detail" (lsp-first-line (or (lsp-def-documentation d) (lsp-def-source d))))
                                                       items))))
                                 defs)))
    (list->vector items)))

;;; ---------------------------------------------------------------------------
;;; Go to definition

(define (lsp-definition params)
  (let* ((place (lsp-request-place params))
         (found (and place (lsp-symbol-at (vector-ref place 0) (vector-ref place 2)))))
    (if (not found)
        lsp-null
        (list->vector (map (lambda (d) (lsp-object "uri" (lsp-def-uri d) "range" (lsp-def-range d)))
                           (lsp-definitions-named (car found)))))))

;;; ---------------------------------------------------------------------------
;;; Diagnostics: read the document, run its syntax definitions, compile (never
;;; run) every other top-level form, and place each error

(define lsp-error-severity 1)

(define (lsp-diagnostic text starts from to message)
  (lsp-object "range" (lsp-range text starts from (max to from)) "severity" lsp-error-severity
              "source" "cog-lisp" "message" message))

;; where a compile error goes: the innermost of its forms the reader read
(define (lsp-error-place r e from to)
  (let ((forms (guard (x (#t #f)) (let ((fs [e forms])) (if (smalltalk-nil? fs) #f fs)))))
    (let loop ((fs (or forms '())))
      (cond ((null? fs) (cons from to))
            ((and (pair? (car fs)) (reader-range-of r (car fs)))
             => (lambda (range) (cons (- (car range) 1) (cdr range))))
            (else (loop (cdr fs)))))))

;; the forms a document's diagnostics run: syntax definitions, and require, whose
;; library defines macros later forms use ((require 'cl) and defun, say)
(define (lsp-syntax-definition? d)
  (or (lsp-head-is? d 'define-syntax) (lsp-head-is? d 'define-macro) (lsp-head-is? d 'require)))

(define (lsp-diagnostics text)
  (let ((r (make-reader text)) (starts (lsp-line-starts text)))
    (let loop ((acc '()))
      (let ((d (guard (e ((read-error? e)
                          (let ((pos (let ((p [e position])) (if (smalltalk-nil? p) (reader-position r) p))))
                            (vector 'read-error pos (error-object-message e)))))
                 (reader-next r))))
        (cond ((eof-object? d) (reverse acc))
              ((and (vector? d) (> (vector-length d) 0) (eq? (vector-ref d 0) 'read-error))
               (reverse (cons (lsp-diagnostic text starts (vector-ref d 1) (+ (vector-ref d 1) 1) (vector-ref d 2)) acc)))
              (else
               (let* ((from (reader-datum-start r))
                      (to (reader-position r))
                      (problem
                       (guard (e (#t (let ((place (lsp-error-place r e from to)))
                                       (lsp-diagnostic text starts (car place) (cdr place) (condition-report e)))))
                         (if (lsp-syntax-definition? d) (lisp-eval d r) (compile-form d r))
                         #f)))
                 (loop (if problem (cons problem acc) acc)))))))))

(define (lsp-publish-diagnostics! uri)
  (let ((doc (lsp-document uri)))
    (when doc
      (lsp-notify! "textDocument/publishDiagnostics"
                   (lsp-object "uri" uri "diagnostics" (list->vector (lsp-diagnostics (vector-ref doc 1))))))))

;;; ---------------------------------------------------------------------------
;;; Expanding the macro call at the cursor (the cog-lisp/expand request)

(define (lsp-macro-call? d)
  (and (pair? d) (symbol? (car d))
       (guard (e (#t #f)) (not (eq? (macroexpand-1 d) d)))))

;; the innermost macro call among the lists the reader read that hold offset
(define (lsp-macro-call-at r d offset)
  (let walk ((d d) (best #f))
    (if (not (pair? d))
        best
        (let ((range (reader-range-of r d)))
          (if (and range (not (and (<= (- (car range) 1) offset) (< offset (cdr range)))))
              best
              (let ((best (if (and range (lsp-macro-call? d)) d best)))
                (let each ((x d) (best best))
                  (if (pair? x)
                      (each (cdr x) (walk (car x) best))
                      best))))))))

(define (lsp-expand params)
  (let ((place (lsp-request-place params)))
    (if (not place)
        lsp-null
        (let ((r (make-reader (vector-ref place 0))) (offset (vector-ref place 2)))
          (let loop ()
            (let ((d (guard (e (#t (eof-object))) (reader-next r))))
              (cond ((eof-object? d) lsp-null)
                    ((and (<= (reader-datum-start r) offset) (< offset (reader-position r)))
                     (let ((call (lsp-macro-call-at r d offset)))
                       (if (not call)
                           lsp-null
                           (lsp-object "form" (reader-source-for r call)
                                       "expansion" (with-output-to-string (lambda () (write (macroexpand call))))))))
                    (else (loop)))))))))

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
   "serverInfo" (lsp-object "name" "cog-lisp" "version" "0.2")))

(define lsp-roots '())

(define (lsp-index-workspace!)
  (for-each (lambda (root)
              (let ((dir [root asFileReference]))
                (when [dir isDirectory] (guard (e (#t #f)) (lsp-index-folder! dir)))))
            lsp-roots))

(define lsp-shutting-down #f)

(define (lsp-changed! uri text)
  (lsp-open! uri text)
  (lsp-index-text! (lsp-key (lsp-uri->path uri)) uri text)
  (lsp-publish-diagnostics! uri))

;; textDocument/formatting (specs/formatter.md R-4): one edit replacing the whole
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
