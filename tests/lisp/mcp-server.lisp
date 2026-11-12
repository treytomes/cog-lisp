;;; mcp-server.lisp -- the MCP server's handlers, its tool table and its protocol
;;; procedure, in the image, with no process around them (specs/35-mcp-server.md
;;; R-15): the four forms of a tool's source (R-8) and the index left as it was,
;;; both forms of a place (R-9), the tools against editor-services (R-7, AC-5),
;;; both eras' envelopes (R-3 to R-5, R-10, R-11, AC-2, AC-8), and mcp-handle as
;;; the whole protocol (R-20, AC-12). vscode/test/mcp.test.js drives the real
;;; server through its launcher.
(load "../../lib/test.lisp")
(load "../../lib/mcp.lisp")
(require 'editor-services)

;;; --- a workspace of its own: a library, a program that uses it, a broken file ---

(define workspace
  (let ((dir [[(smalltalk FileLocator) temp] / (string-append "cog-lisp-mcp-suite-" (number->string [(smalltalk Time) millisecondClockValue]))]))
    [dir ensureCreateDirectory]
    [dir fullName]))

(define (file name) (string-append workspace "/" name))
(define (write-file! name text)
  (call-with-output-file (file name) (lambda (port) (write-string text port))))

(define library-text
  "(define (area w h)\n  \"(area w h)\nThe area of a w by h rectangle.\"\n  (* w h))\n\n(define-syntax swap!\n  \"(swap! a b)\nExchanges a and b.\"\n  (syntax-rules () ((_ a b) (let ((t a)) (set! a b) (set! b t)))))\n")
(define program-text
  "(define-syntax twice (syntax-rules () ((_ e) (begin e e))))\n(display (area 2 3))\n(twice (display \"x\"))\n")
(write-file! "shapes.lisp" library-text)
(write-file! "main.lisp" program-text)
(write-file! "broken.lisp" "(define ok 1)\n(display \"unterminated\n")
(write-file! "messy.lisp" "(define (f x)\n(* x x))\n")

(mcp-set-folder! workspace)

;;; --- helpers: a request through mcp-handle, and its answer's parts --------------

(define next-id 0)
(define (request method params)
  (set! next-id (+ next-id 1))
  (mcp-handle (mcp-object "jsonrpc" "2.0" "id" next-id "method" method "params" params)))

(define (modern-meta) (mcp-object mcp-meta-version "2026-07-28" mcp-meta-capabilities (mcp-object)))

;; tools/call, legacy: the result
(define (call tool . pairs)
  (mcp-get (request "tools/call" (mcp-object "name" tool "arguments" (apply mcp-object pairs))) "result"))

(define (text-of result) (mcp-get (vector-ref (mcp-get result "content") 0) "text"))
(define (json-of result) (json-read (text-of result)))
(define (error? result) (eq? (mcp-get result "isError") #t))
(define (contains? text part) [text includesSubstring: part])

;;; --- the catalog (R-7, R-13, R-14, AC-4) -------------------------------------------

(define-test "tools/list: the language server's six, and no others"
  (let ((tools (mcp-get (mcp-get (request "tools/list" (mcp-object)) "result") "tools")))
    (check (map (lambda (t) (mcp-get t "name")) (vector->list tools))
           '("lisp_check" "lisp_hover" "lisp_definition" "lisp_completion" "lisp_expand_macro" "lisp_format"))
    (for-each (lambda (t)
                (let ((schema (mcp-get t "inputSchema")) (notes (mcp-get t "annotations")))
                  (check (mcp-get schema "type") "object")
                  (check (hash-table-ref schema "additionalProperties") #f)
                  (check-true (hash-table? (mcp-get schema "properties")))
                  (check (mcp-get notes "readOnlyHint") #t)
                  (check (hash-table-ref notes "openWorldHint") #f)
                  (check-true (string? (mcp-get t "title")))
                  (check-true (string? (mcp-get t "description")))))
              (vector->list tools))
    (check-true (hash-table? (mcp-get (vector-ref tools 0) "outputSchema")))
    (check-false (mcp-has? (vector-ref tools 1) "outputSchema"))
    ;; R-14: nothing that runs source
    (check-false (any (lambda (t) (member (mcp-get t "name") '("eval" "run" "run_file" "load")))
                      (vector->list tools)))))

(define-test "tools/call: an unknown tool or argument is -32602"
  (let ((answer (request "tools/call" (mcp-object "name" "nope" "arguments" (mcp-object)))))
    (check (mcp-get (mcp-get answer "error") "code") -32602))
  (let ((answer (request "tools/call" (mcp-object "name" "lisp_check" "arguments" (mcp-object "file" "x")))))
    (check (mcp-get (mcp-get answer "error") "code") -32602)))

;;; --- R-8: path, text, or both ---------------------------------------------------------

(define-test "lisp_check: path, text, both, and neither"
  (let ((by-path (call "lisp_check" "path" (file "broken.lisp"))))
    (check-false (error? by-path))
    (check (map (lambda (p) (mcp-get p "message")) (vector->list (mcp-get (mcp-get by-path "structuredContent") "problems")))
           '("unterminated string"))
    ;; the text is the structured content, as JSON
    (check (mcp-get (vector-ref (mcp-get (json-of by-path) "problems") 0) "line") 2))
  (check (vector-length (mcp-get (json-of (call "lisp_check" "path" (file "main.lisp"))) "problems")) 0)
  ;; text alone: no file
  (let ((problems (mcp-get (json-of (call "lisp_check" "text" "(define (f x) (if))")) "problems")))
    (check (mcp-get (vector-ref problems 0) "message") "if: bad syntax: (if)")
    (check (mcp-get (vector-ref problems 0) "column") 15))
  ;; both: the unsaved text of that file
  (check (vector-length (mcp-get (json-of (call "lisp_check" "path" (file "broken.lisp") "text" "(define ok 1)\n")) "problems")) 0)
  (check-true (error? (call "lisp_check")))
  (check-true (error? (call "lisp_check" "path" (file "no-such-file.lisp"))))
  ;; a relative path is the workspace's
  (check (vector-length (mcp-get (json-of (call "lisp_check" "path" "main.lisp")) "problems")) 0))

;; a tool's answer for main.lisp as path, and as path with its text
(define (same tool . pairs)
  (check (text-of (apply call (append (list tool "path" (file "main.lisp")) pairs)))
         (text-of (apply call (append (list tool "path" (file "main.lisp") "text" program-text) pairs)))))

(define-test "the same source as path and as path with text answers the same (AC-6)"
  (same "lisp_check")
  (same "lisp_hover" "line" 2 "column" 11)
  (same "lisp_definition" "line" 2 "column" 11)
  (same "lisp_completion" "prefix" "are")
  (same "lisp_expand_macro" "line" 3 "column" 2)
  (same "lisp_format"))

(define-test "a request's text leaves the index as it found it (R-5, R-8)"
  (mcp-refresh-index!)
  (check (length (editor-definitions-named "area")) 1)
  ;; the library's unsaved text defines volume and no area
  (let ((answer (json-of (call "lisp_definition" "path" (file "shapes.lisp")
                               "text" "(define (volume w h d) (* w h d))\n" "name" "volume"))))
    (check (vector-length (mcp-get answer "definitions")) 1))
  (check (length (editor-definitions-named "volume")) 0)
  (check (length (editor-definitions-named "area")) 1)
  (check (editor-indexed-text (file "shapes.lisp")) library-text)
  ;; text alone is no file of the index afterwards either
  (call "lisp_check" "text" "(define (only-here) 1)")
  (check (length (editor-definitions-named "only-here")) 0))

(define-test "the index follows the disk: an edited, a new and a removed file"
  (write-file! "extra.lisp" "(define (extra) 1)\n")
  (check (vector-length (mcp-get (json-of (call "lisp_definition" "name" "extra")) "definitions")) 1)
  (write-file! "extra.lisp" "(define (extra2) 2)\n")
  (check (vector-length (mcp-get (json-of (call "lisp_definition" "name" "extra")) "definitions")) 0)
  (check (vector-length (mcp-get (json-of (call "lisp_definition" "name" "extra2")) "definitions")) 1)
  (delete-file (file "extra.lisp"))
  (check (vector-length (mcp-get (json-of (call "lisp_definition" "name" "extra2")) "definitions")) 0))

;;; --- R-9: places ----------------------------------------------------------------------

(define-test "a place as line and column, or as offset, answers the same (AC-7)"
  ;; area in (display (area 2 3)), line 2: offset of line 2's start + 10
  (let ((offset (+ (string-length "(define-syntax twice (syntax-rules () ((_ e) (begin e e))))\n") 10)))
    (check (text-of (call "lisp_hover" "path" (file "main.lisp") "line" 2 "column" 11))
           (text-of (call "lisp_hover" "path" (file "main.lisp") "offset" offset))))
  (check-true (error? (call "lisp_hover" "path" (file "main.lisp") "line" 2 "column" 11 "offset" 3)))
  (check-true (error? (call "lisp_hover" "path" (file "main.lisp") "line" 99 "column" 1)))
  (check-true (error? (call "lisp_hover" "path" (file "main.lisp") "line" 2 "column" 999)))
  (check-true (error? (call "lisp_hover" "path" (file "main.lisp") "line" 2)))
  (check-true (error? (call "lisp_hover" "path" (file "main.lisp") "offset" 9999)))
  (check-true (error? (call "lisp_hover" "path" (file "main.lisp"))))
  (check (mcp-place "ab\ncd" (mcp-object "line" 2 "column" 3)) (vector 'ok 5)))

;;; --- the tools (AC-5) -------------------------------------------------------------------

(define-test "lisp_hover: a workspace definition, and a built-in's documentation"
  (let ((text (text-of (call "lisp_hover" "path" (file "main.lisp") "line" 2 "column" 11))))
    (check-true (contains? text "The area of a w by h rectangle."))
    (check-true (contains? text "shapes.lisp")))
  (check-true (contains? (text-of (call "lisp_hover" "path" (file "main.lisp") "line" 2 "column" 3))
                               "(display x [port])"))
  (check-true (error? (call "lisp_hover" "text" "(nothing-defines-this)" "offset" 2))))

(define-test "lisp_definition: by place and by name, with path, line and column"
  (let ((d (vector-ref (mcp-get (json-of (call "lisp_definition" "path" (file "main.lisp") "line" 2 "column" 11)) "definitions") 0)))
    (check (mcp-get d "name") "area")
    (check (editor-key (mcp-get d "path")) (editor-key (file "shapes.lisp")))
    (check (mcp-get d "line") 1)
    (check (mcp-get d "column") 1)
    (check (mcp-get d "documentation") "(area w h)\nThe area of a w by h rectangle."))
  (check (vector-length (mcp-get (json-of (call "lisp_definition" "name" "swap!")) "definitions")) 1)
  (check-true (error? (call "lisp_definition" "name" "area" "line" 1 "column" 1)))
  (check-false (mcp-has? (json-of (call "lisp_definition" "name" "area")) "note")))

(define-test "lisp_completion: a prefix, a limit, and the word at a place"
  (let ((answer (json-of (call "lisp_completion" "prefix" "string-"  "limit" 3))))
    (check (vector-length (mcp-get answer "completions")) 3)
    (check-true (> (mcp-get answer "more") 0))
    (check-true (string-prefix? "string-" (mcp-get (vector-ref (mcp-get answer "completions") 0) "label"))))
  ;; the workspace's names too
  (check-true (any (lambda (c) (string=? (mcp-get c "label") "area"))
                   (vector->list (mcp-get (json-of (call "lisp_completion" "prefix" "are")) "completions"))))
  ;; the word before the place: "(ar" completes to area
  (let ((answer (json-of (call "lisp_completion" "text" "(ar" "line" 1 "column" 4))))
    (check (mcp-get answer "prefix") "ar"))
  ;; a file's imports complete in that file, and not in a later request with no file
  (let ((labels (lambda (answer) (map (lambda (c) (mcp-get c "label")) (vector->list (mcp-get answer "completions"))))))
    (check-true (member "defun" (labels (json-of (call "lisp_completion" "text" "(require 'cl)\n(defu" "line" 2 "column" 6)))))
    (check-false (member "defun" (labels (json-of (call "lisp_completion" "prefix" "defu"))))))
  (check-true (error? (call "lisp_completion")))
  (check-true (error? (call "lisp_completion" "prefix" "a" "limit" 0))))

(define-test "lisp_expand_macro: the file's own macro, and none at a place"
  (let ((answer (json-of (call "lisp_expand_macro" "path" (file "main.lisp") "line" 3 "column" 2))))
    (check (mcp-get answer "form") "(twice (display \"x\"))")
    (check (mcp-get answer "expansion") "(begin (display \"x\") (display \"x\"))"))
  (check-true (error? (call "lisp_expand_macro" "text" "(car x)" "offset" 1))))

(define-test "lisp_format: reindents, with tabs or spaces"
  (check (text-of (call "lisp_format" "path" (file "messy.lisp"))) "(define (f x)\n\t(* x x)\n)\n")
  (check (text-of (call "lisp_format" "text" "(define (f x)\n(* x x))\n" "insertSpaces" #t "tabSize" 2))
         "(define (f x)\n  (* x x)\n)\n")
  (check-true (error? (call "lisp_format" "text" "(define (f x)"))))

(define-test "with no workspace, a tool says so (R-6, AC-10)"
  (mcp-set-folder! #f)
  (let ((answer (json-of (call "lisp_definition" "name" "area"))))
    (check (vector-length (mcp-get answer "definitions")) 0)
    (check-true (string? (mcp-get answer "note"))))
  (check (length (editor-definitions-named "area")) 0)
  (mcp-set-folder! (file "no-such-folder"))
  (check-false mcp-folder)
  (mcp-set-folder! workspace))

;;; --- the eras (R-3 to R-5, R-10, R-11) --------------------------------------------------

(define-test "legacy: initialize, ping, and no modern envelope"
  (let ((result (mcp-get (request "initialize" (mcp-object "protocolVersion" "2025-06-18" "capabilities" (mcp-object))) "result")))
    (check (mcp-get result "protocolVersion") "2025-06-18")
    (check-true (hash-table? (mcp-get (mcp-get result "capabilities") "tools")))
    (check (mcp-get (mcp-get result "serverInfo") "name") "cog-lisp")
    (check (mcp-get (mcp-get result "serverInfo") "version") (hash-table-ref/default *env* 'version "dev"))
    (check-true (string? (mcp-get result "instructions"))))
  (check (mcp-get (mcp-get (request "initialize" (mcp-object "protocolVersion" "1999-01-01")) "result") "protocolVersion")
         "2025-11-25")
  (check (hash-table-count (mcp-get (request "ping" (mcp-object)) "result")) 0)
  (let ((result (mcp-get (request "tools/list" (mcp-object)) "result")))
    (check-false (mcp-has? result "resultType"))
    (check-false (mcp-has? result "ttlMs"))
    (check-false (mcp-has? result "_meta"))))

(define-test "modern: server/discover and tools/list, with their envelope and cache hints"
  (let ((result (mcp-get (request "server/discover" (mcp-object "_meta" (modern-meta))) "result")))
    (check (mcp-get result "resultType") "complete")
    (check (mcp-get result "supportedVersions") (vector "2026-07-28"))
    (check-true (hash-table? (mcp-get (mcp-get result "capabilities") "tools")))
    (check-true (string? (mcp-get result "instructions")))
    (check (mcp-get (mcp-get (mcp-get result "_meta") mcp-meta-server) "name") "cog-lisp")
    (check (mcp-get result "ttlMs") 0)
    (check (mcp-get result "cacheScope") "public"))
  (let ((result (mcp-get (request "tools/list" (mcp-object "_meta" (modern-meta))) "result")))
    (check (vector-length (mcp-get result "tools")) 6)
    (check (mcp-get result "resultType") "complete")
    (check (mcp-get result "ttlMs") 0))
  ;; a tool call: the envelope, and no cache hints
  (let ((result (mcp-get (request "tools/call" (mcp-object "_meta" (modern-meta) "name" "lisp_check"
                                                           "arguments" (mcp-object "text" "(car 1)")))
                         "result")))
    (check (mcp-get result "resultType") "complete")
    (check-true (mcp-has? (mcp-get result "_meta") mcp-meta-server))
    (check-false (mcp-has? result "ttlMs"))))

(define-test "modern: a request without clientCapabilities, or of another revision, is refused"
  (let ((err (mcp-get (request "tools/list" (mcp-object "_meta" (mcp-object mcp-meta-version "2026-07-28"))) "error")))
    (check (mcp-get err "code") -32602))
  (let ((err (mcp-get (request "tools/list" (mcp-object "_meta" (mcp-object mcp-meta-version "1900-01-01"
                                                                          mcp-meta-capabilities (mcp-object))))
                      "error")))
    (check (mcp-get err "code") -32022)
    (check (mcp-get (mcp-get err "data") "supported") (vector "2026-07-28" "2025-11-25"))
    (check (mcp-get (mcp-get err "data") "requested") "1900-01-01")))

(define-test "errors: an unknown method in both eras; notifications and responses get nothing (R-11, R-12)"
  (check (mcp-get (mcp-get (request "shutdown" (mcp-object)) "error") "code") -32601)
  (check (mcp-get (mcp-get (request "resources/list" (mcp-object "_meta" (modern-meta))) "error") "code") -32601)
  (check-false (mcp-handle (mcp-object "jsonrpc" "2.0" "method" "notifications/initialized")))
  (check-false (mcp-handle (mcp-object "jsonrpc" "2.0" "id" 5 "result" (mcp-object))))
  (check (mcp-get (mcp-get (mcp-handle (vector 1 2)) "error") "code") -32600)
  ;; an id of 0 is an id
  (check (mcp-get (mcp-handle (mcp-object "jsonrpc" "2.0" "id" 0 "method" "ping")) "id") 0))

;; run-tests, with the workspace removed before the exit
(let ((r (run-tests/report)))
  (mcp-set-folder! #f)
  [[workspace asFileReference] deleteAll]
  (exit (if (and (> (cadr r) 0) (= (car r) (cadr r))) 0 1)))
