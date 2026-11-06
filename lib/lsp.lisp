;;; lsp.lisp -- cog-lisp's language server, served by the image itself
;;; (specs/phase-10-documentation-and-editor.md step 10.5; the spike)
;;;
;;;   ./cog-lisp.sh lib/lsp.lisp       (cog-lisp.bat lib\lsp.lisp on Windows)
;;;
;;; It speaks the Language Server Protocol on standard input and output: each
;;; message a JSON text framed with a Content-Length header
;;; (read-framed-message, write-framed-message). JSON is Pharo's STONJSON, so a
;;; message is a Smalltalk Dictionary, reached through interop. The spike answers
;;; hover from the documentation in the image; the rest of the step builds on it.

;;; JSON

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

;;; Messages

(define (lsp-send! object) (write-framed-message (lsp-text object)))

(define (lsp-respond! id result)
  (lsp-send! (lsp-object "jsonrpc" "2.0" "id" id "result" result)))

(define (lsp-respond-error! id code message)
  (lsp-send! (lsp-object "jsonrpc" "2.0" "id" id "error" (lsp-object "code" code "message" message))))

;;; Documents the editor has open: uri -> text

(define lsp-documents (make-hash-table equal?))

;; line n of uri's text (from 0), without its line ending, or ""
(define (lsp-line uri n)
  (let ((text (hash-table-ref/default lsp-documents uri "")))
    (let loop ((lines (string-split text #\newline)) (i 0))
      (cond ((null? lines) "")
            ((= i n) (let ((l (car lines)))
                       (if (and (> (string-length l) 0) (char=? (string-ref l (- (string-length l) 1)) #\return))
                           (substring l 0 (- (string-length l) 1))
                           l)))
            (else (loop (cdr lines) (+ i 1)))))))

;; what ends a symbol, as the reader sees it
(define lsp-delimiters (string->list " \t\r\n()[]\";'`,"))
(define (lsp-delimiter? c) (memv c lsp-delimiters))

;; the symbol of line around index i: (name start end), or #f
(define (lsp-symbol-at line i)
  (let* ((n (string-length line))
         (start (let back ((s (min i n))) (if (and (> s 0) (not (lsp-delimiter? (string-ref line (- s 1))))) (back (- s 1)) s)))
         (end (let ahead ((e (min i n))) (if (and (< e n) (not (lsp-delimiter? (string-ref line e)))) (ahead (+ e 1)) e))))
    (and (< start end) (list (substring line start end) start end))))

;;; Requests and notifications

(define (lsp-initialize params)
  (lsp-object
   "capabilities" (lsp-object "textDocumentSync" 1 "hoverProvider" #t)
   "serverInfo" (lsp-object "name" "cog-lisp" "version" "0.2")))

(define (lsp-hover params)
  (let* ((uri (lsp-path params "textDocument" "uri"))
         (line-number (lsp-path params "position" "line"))
         (character (lsp-path params "position" "character"))
         (found (and uri line-number (lsp-symbol-at (lsp-line uri line-number) character)))
         (doc (and found (documentation (string->symbol (car found))))))
    (if (not doc)
        lsp-null
        (let ((i (string-index doc #\newline)))
          (lsp-object
           "contents" (lsp-object "kind" "markdown"
                                  "value" (if i
                                              (string-append "```cog-lisp\n" (substring doc 0 i) "\n```\n\n" (substring doc (+ i 1)))
                                              (string-append "```cog-lisp\n" doc "\n```")))
           "range" (lsp-object "start" (lsp-object "line" line-number "character" (car (cdr found)))
                               "end" (lsp-object "line" line-number "character" (car (cdr (cdr found))))))))))

(define lsp-shutting-down #f)

;; one message: a request (it has an id) gets a response; a notification none
(define (lsp-handle! message)
  (let ((id (lsp-get message "id"))
        (method (lsp-get message "method"))
        (params (lsp-get message "params")))
    (cond ((not method) #f)                                   ; a response to us: none expected
          ((string=? method "initialize") (lsp-respond! id (lsp-initialize params)))
          ((string=? method "initialized") #f)
          ((string=? method "textDocument/didOpen")
           (hash-table-set! lsp-documents (lsp-path params "textDocument" "uri") (lsp-path params "textDocument" "text")))
          ((string=? method "textDocument/didChange")
           (let ((changes (lsp-get params "contentChanges")))
             (when (and changes (> [changes size] 0))
               (hash-table-set! lsp-documents (lsp-path params "textDocument" "uri") (lsp-get [changes last] "text")))))
          ((string=? method "textDocument/didClose")
           (hash-table-delete! lsp-documents (lsp-path params "textDocument" "uri")))
          ((string=? method "textDocument/hover") (lsp-respond! id (lsp-hover params)))
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
