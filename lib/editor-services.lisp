;;; editor-services.lisp -- what an editor knows about cog-lisp source
;;; (specs/34-morphic-ide.md section 5.9, R-29). Load with (require 'editor-services).
;;;
;;; The language server (lib/lsp.lisp) and the image's own editor (the Morphic
;;; tools) both ask it: the definitions in a workspace's files, the name at a
;;; place, the problems compiling a text would meet, what a name means in a file,
;;; the names to complete, the macro call at a place, and the tokens to style.
;;;
;;; It speaks plain LISP data. A place in a text is a character offset from 0;
;;; the language server turns offsets into the protocol's UTF-16 positions, and
;;; the Morphic editor into its own. A file is named by its path; two spellings of
;;; one path (\ or /, a drive letter's case on Windows) are one file (editor-key).
;;;
;;; It reads the workspace's .lisp files but never runs them, except a text's
;;; top-level define-syntax, define-macro, require and library forms when it is
;;; checked, so later forms expand and resolve as they will when the file runs.
;;;
;;; Records are vectors, read with their accessors:
;;;   a definition  #(name path start end documentation source)
;;;   a problem     #(severity start end message), severity error or warning
;;;   a completion  #(label kind detail documentation), kind keyword, function
;;;                 or variable
;;;   a token       #(kind start end depth), kind comment string character
;;;                 number open close quote keyword symbol; depth is a
;;;                 parenthesis's nesting, else 0

(library editor-services
  (export editor-key
          editor-definitions editor-index-text! editor-index-file! editor-index-folder!
          editor-indexed-text editor-definitions-named
          definition-name definition-path definition-start definition-end
          definition-documentation definition-source
          editor-symbol-at
          editor-check editor-unit-of problem-severity problem-start problem-end problem-message
          editor-resolve editor-definitions-for
          editor-completions completion-label completion-kind completion-detail completion-documentation
          editor-macro-call-at
          editor-tokens token-kind token-start token-end token-depth))

;;; ---------------------------------------------------------------------------
;;; Files

(define %windows [[(smalltalk OSPlatform) current] isWindows])

(define (editor-key path)
  "(editor-key path)
The key a file is known by: its path with / for \\, and in lower case on Windows, so two spellings of one path are one file."
  (let ((p [path copyReplaceAll: "\\" with: "/"]))
    (if %windows (string-downcase p) p)))

(define (%head-is? d name) (and (pair? d) (eq? (car d) name)))

;;; ---------------------------------------------------------------------------
;;; Definitions, and the workspace index: key -> #(path text definitions)

(define (definition-name d) "(definition-name definition)\nA definition's name, a string." (vector-ref d 0))
(define (definition-path d) "(definition-path definition)\nThe path of the file a definition is in, or #f for a text that is no file." (vector-ref d 1))
(define (definition-start d) "(definition-start definition)\nWhere a definition's form starts in its text, a character offset from 0." (vector-ref d 2))
(define (definition-end d) "(definition-end definition)\nWhere a definition's form ends in its text: the offset after its last character." (vector-ref d 3))
(define (definition-documentation d) "(definition-documentation definition)\nA definition's documentation string, or #f." (vector-ref d 4))
(define (definition-source d) "(definition-source definition)\nThe text of a definition's whole form." (vector-ref d 5))

;; a top-level form's definition: (name . documentation), or #f
(define (%definition-of d)
  (cond ((not (and (pair? d) (pair? (cdr d)))) #f)
        ((or (%head-is? d 'define) (%head-is? d 'define-macro))
         (let ((target (car (cdr d))) (rest (cdr (cdr d))))
           (cond ((and (pair? target) (symbol? (car target)))
                  (cons (car target) (and (pair? rest) (string? (car rest)) (pair? (cdr rest)) (car rest))))
                 ((symbol? target)
                  (cons target (and (pair? rest) (pair? (car rest)) (eq? (car (car rest)) 'lambda)
                                    (let ((body (cdr (cdr (car rest)))))
                                      (and (pair? body) (string? (car body)) (pair? (cdr body)) (car body))))))
                 (else #f))))
        ((%head-is? d 'define-syntax)
         (let ((target (car (cdr d))) (rest (cdr (cdr d))))
           (and (symbol? target)
                (cons target (and (pair? rest) (string? (car rest)) (pair? (cdr rest)) (car rest))))))
        (else #f)))

(define (editor-definitions text . path)
  "(editor-definitions text [path])
The top-level definitions in text (define, define-macro, define-syntax), read but not run, up to the first form that does not read. Each records path, or #f."
  (let ((r (make-reader text)) (p (if (pair? path) (car path) #f)))
    (let loop ((acc '()))
      (let ((d (guard (e (#t (eof-object))) (reader-next r))))
        (if (eof-object? d)
            (reverse acc)
            (let ((def (%definition-of d)))
              (loop (if def
                        (let ((from (reader-datum-start r)) (to (reader-position r)))
                          (cons (vector (symbol->string (car def)) p from to (cdr def) (substring text from to)) acc))
                        acc))))))))

(define %index (make-hash-table equal?))
(define %skipped-folders '("pharo" "node_modules" ".vscode-test" ".git" "dist"))

(define (editor-index-text! path text)
  "(editor-index-text! path text)
Indexes text as the file at path holds it (an editor's unsaved text, say): its definitions replace the file's."
  (hash-table-set! %index (editor-key path) (vector path text (editor-definitions text path))))

(define (editor-index-file! path)
  "(editor-index-file! path)
Indexes the file at path as it is on disk; a file that cannot be read is left out."
  (let ((text (guard (e (#t #f)) [[[path asFileReference] contents] asString])))
    (when text (editor-index-text! path text))))

(define (editor-index-folder! folder)
  "(editor-index-folder! folder)
Indexes every .lisp file under folder (a path or a file reference), leaving out pharo, node_modules, .vscode-test, .git and dist."
  (let ((dir [folder asFileReference]))
    (for-each (lambda (entry)
                (let ((name [entry basename]))
                  (cond ([entry isDirectory]
                         (unless (member name %skipped-folders) (editor-index-folder! entry)))
                        ([name endsWith: ".lisp"]
                         (editor-index-file! [entry fullName])))))
              (vector->list [[dir children] asArray]))))

(define (editor-indexed-text path)
  "(editor-indexed-text path)
The text the index holds for the file at path, or #f."
  (let ((entry (hash-table-ref/default %index (editor-key path) #f)))
    (and entry (vector-ref entry 1))))

(define (%definitions-at-key key)
  (let ((entry (hash-table-ref/default %index key #f)))
    (if entry (vector-ref entry 2) '())))

(define (editor-definitions-named name)
  "(editor-definitions-named name)
Every definition in the index named name, a string."
  (let ((acc '()))
    (hash-table-walk %index
                     (lambda (key entry)
                       (for-each (lambda (d) (when (string=? (definition-name d) name) (set! acc (cons d acc))))
                                 (vector-ref entry 2))))
    (reverse acc)))

;;; ---------------------------------------------------------------------------
;;; What is at a place

(define %delimiters (string->list " \t\r\n()[]\";'`,"))
(define (%delimiter? c) (memv c %delimiters))

(define (editor-symbol-at text offset)
  "(editor-symbol-at text offset)
The name around offset in text, as (name start end), or #f between names."
  (let* ((n (string-length text))
         (start (let back ((s (min offset n))) (if (and (> s 0) (not (%delimiter? (string-ref text (- s 1))))) (back (- s 1)) s)))
         (end (let ahead ((e (min offset n))) (if (and (< e n) (not (%delimiter? (string-ref text e)))) (ahead (+ e 1)) e))))
    (and (< start end) (list (substring text start end) start end))))

;;; ---------------------------------------------------------------------------
;;; Problems: read the text, run its syntax definitions, compile (never run) every
;;; other top-level form, and place each error. Each text is compiled in a unit of
;;; its own (specs/27-namespaces.md R-13), kept for resolving its names.

(define (problem-severity p) "(problem-severity problem)\nerror or warning." (vector-ref p 0))
(define (problem-start p) "(problem-start problem)\nWhere a problem starts in its text, a character offset from 0." (vector-ref p 1))
(define (problem-end p) "(problem-end problem)\nWhere a problem ends in its text: the offset after its last character." (vector-ref p 2))
(define (problem-message p) "(problem-message problem)\nWhat the problem is, a string." (vector-ref p 3))

(define %units (make-hash-table equal?))

(define (editor-unit-of path)
  "(editor-unit-of path)
The unit the text at path was last checked in (editor-check), whose imports say what its names mean, or #f."
  (hash-table-ref/default %units (editor-key path) #f))

;; is path one of cog-lisp's own sources, whose definitions are the built-ins?
(define (%builtin-source? path)
  (let ((home (hash-table-ref/default *env* 'home #f)))
    (and home (string-prefix? (editor-key (string-append home "/lib/")) (editor-key path)))))

;; the warnings compiling a form made (a redefined built-in, specs/27-namespaces.md
;; R-10), as problems on that form
(define (%form-warnings from to)
  (let ((unit (%current-unit)))
    (if (not unit)
        '()
        (map (lambda (w) (vector 'warning from (max to from) w))
             (if (%builtin-source? [unit path]) (begin [unit takeWarnings] '()) (vector->list [unit takeWarnings]))))))

;; where a compile error goes: the innermost of its forms the reader read
(define (%error-place r e from to)
  (let ((forms (guard (x (#t #f)) (let ((fs [e forms])) (if (smalltalk-nil? fs) #f fs)))))
    (let loop ((fs (or forms '())))
      (cond ((null? fs) (cons from to))
            ((and (pair? (car fs)) (reader-range-of r (car fs)))
             => (lambda (range) (cons (- (car range) 1) (cdr range))))
            (else (loop (cdr fs)))))))

;; the forms a check runs: syntax definitions; require, whose library defines
;; macros later forms use and whose imports they compile with; and library, which
;; says whose definitions they are
(define (%syntax-definition? d)
  (or (%head-is? d 'define-syntax) (%head-is? d 'define-macro) (%head-is? d 'require) (%head-is? d 'library)))

;; the globals a compiled form names that nothing has defined: the unbound
;; cells in its method's literals, its blocks' too
(define (%unbound-cells method)
  (let walk ((m method) (acc '()))
    (fold (lambda (lit acc)
            (cond ([lit isKindOf: (smalltalk LispGlobal)] (if [lit isBound] acc (cons lit acc)))
                  ([lit isKindOf: (smalltalk CompiledBlock)] (walk lit acc))
                  ([lit isKindOf: (smalltalk BlockClosure)] (walk [lit compiledBlock] acc))
                  (else acc)))
          acc
          (vector->list [m literals]))))

;; the names a top-level form defines, its macro calls expanded: a define, or
;; the defines of a begin (define-record-type's, a user's defining macro's)
(define (%defined-names d)
  (let ((e (guard (x (#t d)) (macroexpand d))))
    (cond ((%head-is? e 'begin) (append-map %defined-names (cdr e)))
          ((%definition-of e) => (lambda (def) (list (car def))))
          (else '()))))

(define (%local-name name)
  (let ((colon (string-index name #\:)))
    (if colon (substring name (+ colon 1) (string-length name)) name)))

;; a warning for each place a form names a global nothing defines: not the text
;; (a name defined later in it is unbound while it is checked), not the image,
;; not another file of the index; a program may still define it at run time
(define (%unbound-problems text refs defined)
  (append-map
   (lambda (ref)
     (let* ((from (cadr ref)) (to (caddr ref)) (form-text (substring text from to)))
       (append-map
        (lambda (cell)
          (let* ((name (symbol->string [cell symbol])) (local (%local-name name)))
            (if (or [cell isBound]
                    (hash-table-contains? defined name) (hash-table-contains? defined local)
                    (pair? (editor-definitions-named local)))
                '()
                (filter-map (lambda (tok)
                              (and (eq? (token-kind tok) 'symbol)
                                   (let ((word (substring form-text (token-start tok) (token-end tok))))
                                     (and (or (string=? word name) (string=? word local))
                                          (vector 'warning (+ from (token-start tok)) (+ from (token-end tok))
                                                  (string-append "unbound variable: " word))))))
                            (editor-tokens form-text)))))
        (delete-duplicates (car ref) eq?))))
   (reverse refs)))

(define (%problems text)
  (let ((r (make-reader text)) (defined (make-hash-table equal?)) (refs '()))
    (define (finish acc)
      (sort (append (reverse acc) (%unbound-problems text refs defined))
            (lambda (a b) (< (problem-start a) (problem-start b)))))
    (let loop ((acc '()))
      (let ((d (guard (e ((read-error? e)
                          (let ((pos (let ((p [e position])) (if (smalltalk-nil? p) (reader-position r) p))))
                            (vector 'read-error pos (error-object-message e)))))
                 (reader-next r))))
        (cond ((eof-object? d) (finish acc))
              ((and (vector? d) (> (vector-length d) 0) (eq? (vector-ref d 0) 'read-error))
               (finish (cons (vector 'error (vector-ref d 1) (+ (vector-ref d 1) 1) (vector-ref d 2)) acc)))
              (else
               (for-each (lambda (n) (hash-table-set! defined (symbol->string n) #t)) (%defined-names d))
               (let* ((from (reader-datum-start r))
                      (to (reader-position r))
                      (warnings '())
                      (problem
                       (guard (e (#t (let ((place (%error-place r e from to)))
                                       (vector 'error (car place) (max (cdr place) (car place)) (condition-report e)))))
                         (if (%syntax-definition? d)
                             (lisp-eval d r)
                             (begin
                               (lisp-check d r)
                               (set! warnings (%form-warnings from to))
                               ;; compiled again, for the globals it names; its warnings are the check's again
                               (let ((cells (guard (x (#t '())) (%unbound-cells (compile-form d r)))))
                                 (%form-warnings from to)
                                 (when (pair? cells) (set! refs (cons (list cells from to) refs))))))
                         #f)))
                 (when (null? warnings) (set! warnings (%form-warnings from to)))
                 (loop (append (reverse warnings) (if problem (cons problem acc) acc))))))))))

(define (editor-check path text)
  "(editor-check path text)
The problems compiling text, the file at path, would meet: each read error, compile error and warning, placed on its form, and a warning on each use of a global nothing defines (not the text, the image, or a file of the index), in the order of the text. Runs only its define-syntax, define-macro, require and library forms. The unit it compiles in is kept (editor-unit-of)."
  (let ((unit [(smalltalk LispUnit) forFile: path inheriting: (smalltalk-nil)]))
    ;; its warnings are answered, not written to stderr
    [unit collectWarnings]
    (hash-table-set! %units (editor-key path) unit)
    [(smalltalk LispLoadPath) value: path
     during: (procedure->block
              (lambda ()
                [(smalltalk LispCurrentUnit) value: unit
                 during: (procedure->block (lambda () (%problems text)))]))]))

;;; ---------------------------------------------------------------------------
;;; What a name means in a file

(define (editor-resolve path name)
  "(editor-resolve path name)
The symbol name means in the file at path, as its last check (editor-check) imported it: a library's full name for an import, else name as a symbol."
  (let* ((sym (string->symbol name))
         (unit (editor-unit-of path))
         (target (and unit [unit importAt: sym])))
    (if (and target (not (smalltalk-nil? target))) target sym)))

(define (editor-definitions-for path name)
  "(editor-definitions-for path name)
The definitions name, in the file at path, leads to: a library's full name to that library's file, anything else to its name across the index."
  (let* ((target (symbol->string (editor-resolve path name)))
         (colon (string-index target #\:)))
    (if (not colon)
        (editor-definitions-named target)
        (let* ((library [(smalltalk LispUnit) libraryNamed: (string->symbol (substring target 0 colon))])
               (local (substring target (+ colon 1) (string-length target))))
          (if (smalltalk-nil? library)
              (editor-definitions-named target)
              (filter (lambda (d) (string=? (definition-name d) local))
                      (%definitions-at-key (editor-key [library path]))))))))

;;; ---------------------------------------------------------------------------
;;; Completion: the documented built-ins and the special forms, made once, the
;;; file's imports, and the names the index defines

(define (completion-label c) "(completion-label completion)\nThe name to insert, a string." (vector-ref c 0))
(define (completion-kind c) "(completion-kind completion)\nkeyword (a special form or a macro), function, or variable (a name the workspace defines)." (vector-ref c 1))
(define (completion-detail c) "(completion-detail completion)\nOne line about the name: its call, or its definition's first line." (vector-ref c 2))
(define (completion-documentation c) "(completion-documentation completion)\nThe rest of its documentation, or the empty string." (vector-ref c 3))

(define (%first-line s)
  (let ((i (string-index s #\newline))) (if i (substring s 0 i) s)))
(define (%after-first-line s)
  (let ((i (string-index s #\newline))) (if i (substring s (+ i 1)) "")))

(define (%builtin-completions)
  (let ((items '()))
    (for-each (lambda (name)
                (let ((doc (documentation name)))
                  (set! items (cons (vector (symbol->string name) 'keyword
                                            (if doc (%first-line doc) "special form")
                                            (if doc (%after-first-line doc) ""))
                                    items))))
              (special-form-names))
    [[(smalltalk LispEnvironment) default]
     cellsDo: (lambda (cell)
                (when [cell isBound]
                  (let* ((name [cell symbol]) (doc (documentation name)) (value [cell value]))
                    ;; a library's names come with the file's imports, not here
                    (when (and doc (not (memq name (special-form-names)))
                               (not (string-index (symbol->string name) #\:)))
                      (set! items (cons (vector (symbol->string name)
                                                (if [value isKindOf: (smalltalk LispMacro)] 'keyword 'function)
                                                (%first-line doc) (%after-first-line doc))
                                        items))))))]
    items))

(define %builtins #f)

(define (editor-completions path)
  "(editor-completions path)
The names to offer in the file at path: the documented built-ins and the special forms, the file's imports as it imported them (con:rule), and the names the index defines, each once."
  (unless %builtins (set! %builtins (%builtin-completions)))
  (let ((seen (make-hash-table equal?)) (items '()) (unit (editor-unit-of path)))
    (for-each (lambda (item) (hash-table-set! seen (completion-label item) #t) (set! items (cons item items))) %builtins)
    (when unit
      (for-each (lambda (a)
                  (let* ((label (symbol->string [a key])) (doc (documentation [a value])))
                    (unless (hash-table-contains? seen label)
                      (hash-table-set! seen label #t)
                      (set! items (cons (vector label 'function (if doc (%first-line doc) (symbol->string [a value])) "")
                                        items)))))
                (vector->list [[[unit imports] associations] asArray])))
    (hash-table-walk %index
                     (lambda (key entry)
                       (for-each (lambda (d)
                                   (unless (hash-table-contains? seen (definition-name d))
                                     (hash-table-set! seen (definition-name d) #t)
                                     (set! items (cons (vector (definition-name d) 'variable
                                                               (%first-line (or (definition-documentation d) (definition-source d)))
                                                               "")
                                                       items))))
                                 (vector-ref entry 2))))
    items))

;;; ---------------------------------------------------------------------------
;;; The macro call at a place

(define (%macro-call? d)
  (and (pair? d) (symbol? (car d))
       (guard (e (#t #f)) (not (eq? (macroexpand-1 d) d)))))

;; the innermost macro call among the lists the reader read that hold offset
(define (%macro-call-in r d offset)
  (let walk ((d d) (best #f))
    (if (not (pair? d))
        best
        (let ((range (reader-range-of r d)))
          (if (and range (not (and (<= (- (car range) 1) offset) (< offset (cdr range)))))
              best
              (let ((best (if (and range (%macro-call? d)) d best)))
                (let each ((x d) (best best))
                  (if (pair? x)
                      (each (cdr x) (walk (car x) best))
                      best))))))))

(define (editor-macro-call-at text offset)
  "(editor-macro-call-at text offset)
The innermost macro call holding offset in text, as (source . expansion), its text and its full expansion written; or #f."
  (let ((r (make-reader text)))
    (let loop ()
      (let ((d (guard (e (#t (eof-object))) (reader-next r))))
        (cond ((eof-object? d) #f)
              ((and (<= (reader-datum-start r) offset) (< offset (reader-position r)))
               (let ((call (%macro-call-in r d offset)))
                 (and call
                      (cons (reader-source-for r call)
                            (with-output-to-string (lambda () (write (macroexpand call))))))))
              (else (loop)))))))

;;; ---------------------------------------------------------------------------
;;; Tokens, for styling (specs/34-morphic-ide.md spike 2): tolerant of text being
;;; edited, so an unclosed string or list styles to the end of the text

(define (token-kind t) "(token-kind token)\ncomment, string, character, number, open, close, quote, keyword or symbol." (vector-ref t 0))
(define (token-start t) "(token-start token)\nWhere a token starts, a character offset from 0." (vector-ref t 1))
(define (token-end t) "(token-end token)\nThe offset after a token's last character." (vector-ref t 2))
(define (token-depth t) "(token-depth token)\nAn open or close parenthesis's nesting depth, from 0; 0 for any other token." (vector-ref t 3))

(define (%token-delimiter? c)
  (or (char-whitespace? c) (eq? c #\() (eq? c #\)) (eq? c #\[) (eq? c #\]) (eq? c #\") (eq? c #\;)))

;; the first index from i whose character answers pred, or n
(define (%scan text i n pred)
  (let loop ((i i)) (if (or (>= i n) (pred (string-ref text i))) i (loop (+ i 1)))))

;; the end of a string whose opening quote is at i: past its closing quote, or n
(define (%string-end text i n)
  (let loop ((j (+ i 1)))
    (cond ((>= j n) n)
          ((eq? (string-ref text j) #\\) (loop (+ j 2)))
          ((eq? (string-ref text j) #\") (min n (+ j 1)))
          (else (loop (+ j 1))))))

;; a word that could be a number: its first character a digit, or a sign or a
;; point (string->number, the reader's whole number syntax, is slow to say no)
(define (%number-start? c) (or (char-numeric? c) (eq? c #\-) (eq? c #\+) (eq? c #\.) (eq? c #\#)))

;; is name a special form, or bound to a macro? (the special forms are fixed once
;; the image is built; a macro may be defined at any time, so it is asked live)
(define %special-forms #f)
(define (%keyword? name)
  (unless %special-forms
    (set! %special-forms (make-hash-table eq?))
    (for-each (lambda (s) (hash-table-set! %special-forms s #t)) (special-form-names)))
  (let ((sym (string->symbol name)))
    (or (hash-table-contains? %special-forms sym)
        (let ((cell [[(smalltalk LispEnvironment) default] at: sym ifAbsent: (lambda () #f)]))
          (and cell [cell isKindOf: (smalltalk LispMacro)])))))

(define (editor-tokens text)
  "(editor-tokens text)
The tokens of text, for styling it: comments, strings, characters, numbers, parentheses (with their depth), quotes, keywords (special forms and macros) and other symbols. An unclosed string or comment runs to the end; text that does not read still has tokens."
  (let ((n (string-length text)) (out '()))
    (let loop ((i 0) (depth 0))
      (if (>= i n)
          (reverse out)
          (let ((c (string-ref text i)))
            (cond
              ((char-whitespace? c) (loop (+ i 1) depth))
              ((eq? c #\;)
               (let ((e (%scan text i n (lambda (ch) (eq? ch #\newline)))))
                 (set! out (cons (vector 'comment i e 0) out))
                 (loop e depth)))
              ((eq? c #\")
               (let ((e (%string-end text i n)))
                 (set! out (cons (vector 'string i e 0) out))
                 (loop e depth)))
              ((or (eq? c #\() (eq? c #\[))
               (set! out (cons (vector 'open i (+ i 1) depth) out))
               (loop (+ i 1) (+ depth 1)))
              ((or (eq? c #\)) (eq? c #\]))
               (let ((d (max 0 (- depth 1))))
                 (set! out (cons (vector 'close i (+ i 1) d) out))
                 (loop (+ i 1) d)))
              ((or (eq? c #\') (eq? c #\`) (eq? c #\,))
               (let ((e (if (and (eq? c #\,) (< (+ i 1) n) (eq? (string-ref text (+ i 1)) #\@)) (+ i 2) (+ i 1))))
                 (set! out (cons (vector 'quote i e 0) out))
                 (loop e depth)))
              ((and (eq? c #\#) (< (+ i 1) n) (eq? (string-ref text (+ i 1)) #\\))
               ;; a character: #\x, or a name such as #\space; at least one character after the backslash
               (let ((e (%scan text (min n (+ i 3)) n %token-delimiter?)))
                 (set! out (cons (vector 'character i e 0) out))
                 (loop e depth)))
              (else
               (let* ((e (max (+ i 1) (%scan text i n %token-delimiter?)))
                      (word (substring text i e)))
                 (set! out (cons (vector (cond ((and (%number-start? c) (string->number word)) 'number)
                                               ((%keyword? word) 'keyword)
                                               (else 'symbol))
                                         i e 0)
                                 out))
                 (loop e depth)))))))))
