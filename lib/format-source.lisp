;;; format-source.lisp -- lay out cog-lisp source (specs/formatter.md; issue #8)
;;;
;;;   (require 'format-source)
;;;   (format-source text)                    ; tabs
;;;   (format-source text 'spaces 2)          ; two spaces a level
;;;
;;; The layout is the one ~/projects/lisp-expert is written in:
;;;   - a form whose elements hold no list stays on one line: (+ a b);
;;;   - otherwise its head and its header arguments stay on the first line (if's
;;;     test, let's bindings, define's name: see format-source-headers), each
;;;     other argument goes on its own line one level deeper, and the closing
;;;     parenthesis on its own line, level with the form;
;;;   - comments keep their place: on a line of their own, or at the end of a
;;;     line; blank lines between top-level forms are kept (two at most), and
;;;     one blank line inside a form is kept.
;;;
;;; It works on the source's tokens, not on what the reader makes of them, so
;;; every comment, string and character literal comes out exactly as it went in.
;;; Only the whitespace between tokens changes: each run checks that, and
;;; answers an error rather than text that would differ. A Smalltalk send in
;;; [brackets] is copied exactly as written.

;;; ---------------------------------------------------------------------------
;;; Tokens: #(kind text newlines-before line), kind one of
;;;   open close atom string comment prefix

(define %fs-form-feed (integer->char 12))
(define (%fs-separator? c) (or (memv c '(#\space #\tab #\newline #\return)) (eqv? c %fs-form-feed)))
(define (%fs-delimiter? c)
  (or (%fs-separator? c) (memv c '(#\( #\) #\[ #\] #\" #\; #\' #\` #\,))))

(define (%fs-error message line)
  (error (string-append "format-source: " message " (line " (number->string line) ")")))

;; the tokens of text, in order
(define (%fs-tokens text)
  (let ((n (string-length text)) (tokens '()) (line 1))
    (define (at i) (string-ref text i))
    (define (add! kind start end newlines)
      (set! tokens (cons (vector kind (substring text start end) newlines line) tokens)))
    (define (count-lines start end)
      (let loop ((i start))
        (when (< i end)
          (when (eq? (at i) #\newline) (set! line (+ line 1)))
          (loop (+ i 1)))))
    ;; the end of the string that starts at i (at its quote)
    (define (string-end i)
      (let loop ((j (+ i 1)))
        (cond ((>= j n) (%fs-error "an unterminated string" line))
              ((eq? (at j) #\\) (loop (+ j 2)))
              ((eq? (at j) #\") (+ j 1))
              (else (loop (+ j 1))))))
    (define (block-comment-end i)
      (let loop ((j (+ i 2)) (depth 1))
        (cond ((= depth 0) j)
              ((>= (+ j 1) n) (%fs-error "an unterminated block comment" line))
              ((and (eq? (at j) #\#) (eq? (at (+ j 1)) #\|)) (loop (+ j 2) (+ depth 1)))
              ((and (eq? (at j) #\|) (eq? (at (+ j 1)) #\#)) (loop (+ j 2) (- depth 1)))
              (else (loop (+ j 1) depth)))))
    ;; the end of a Smalltalk send in brackets, nested brackets and parentheses,
    ;; strings and comments within it included
    (define (bracket-end i)
      (let loop ((j (+ i 1)) (depth 1))
        (cond ((= depth 0) j)
              ((>= j n) (%fs-error "an unclosed [" line))
              ((memv (at j) '(#\[ #\()) (loop (+ j 1) (+ depth 1)))
              ((memv (at j) '(#\] #\))) (loop (+ j 1) (- depth 1)))
              ((eq? (at j) #\") (loop (string-end j) depth))
              ((eq? (at j) #\;) (loop (line-end j) depth))
              ((and (eq? (at j) #\#) (< (+ j 1) n) (eq? (at (+ j 1)) #\\)) (loop (atom-end (+ j 3)) depth))
              (else (loop (+ j 1) depth)))))
    (define (line-end i)
      (let loop ((j i)) (if (or (>= j n) (eq? (at j) #\newline)) j (loop (+ j 1)))))
    (define (atom-end i)
      (let loop ((j i)) (if (or (>= j n) (%fs-delimiter? (at j))) j (loop (+ j 1)))))
    (let loop ((i 0) (newlines 0))
      (if (>= i n)
          (reverse tokens)
          (let ((c (at i)))
            (cond
              ((%fs-separator? c)
               (when (eq? c #\newline) (set! line (+ line 1)))
               (loop (+ i 1) (if (eq? c #\newline) (+ newlines 1) newlines)))
              ((eq? c #\;)
               (let ((e (line-end i))) (add! 'comment i e newlines) (loop e 0)))
              ((and (eq? c #\#) (< (+ i 1) n) (eq? (at (+ i 1)) #\|))
               (let ((e (block-comment-end i))) (add! 'comment i e newlines) (count-lines i e) (loop e 0)))
              ((memv c '(#\( #\))) (add! (if (eq? c #\() 'open 'close) i (+ i 1) newlines) (loop (+ i 1) 0))
              ((and (eq? c #\#) (< (+ i 1) n) (eq? (at (+ i 1)) #\())
               (add! 'open i (+ i 2) newlines) (loop (+ i 2) 0))
              ((eq? c #\[)
               (let ((e (bracket-end i))) (add! 'atom i e newlines) (count-lines i e) (loop e 0)))
              ((eq? c #\]) (%fs-error "a ] with no [" line))
              ((eq? c #\") (let ((e (string-end i))) (add! 'string i e newlines) (count-lines i e) (loop e 0)))
              ((memv c '(#\' #\`)) (add! 'prefix i (+ i 1) newlines) (loop (+ i 1) 0))
              ((eq? c #\,)
               (let ((e (if (and (< (+ i 1) n) (eq? (at (+ i 1)) #\@)) (+ i 2) (+ i 1))))
                 (add! 'prefix i e newlines) (loop e 0)))
              ;; a character literal: #\ and one character (a delimiter too), then
              ;; the rest of its name
              ((and (eq? c #\#) (< (+ i 2) n) (eq? (at (+ i 1)) #\\))
               (let ((e (atom-end (+ i 3)))) (add! 'atom i e newlines) (loop e 0)))
              (else (let ((e (atom-end i))) (add! 'atom i e newlines) (loop e 0)))))))))

(define (%fs-kind t) (vector-ref t 0))
(define (%fs-text t) (vector-ref t 1))
(define (%fs-newlines t) (vector-ref t 2))
(define (%fs-line t) (vector-ref t 3))

;;; ---------------------------------------------------------------------------
;;; Nodes: #(atom text prefix newlines), #(list open close children prefix newlines),
;;; #(comment text newlines). prefix is the quote marks before a datum, joined.

(define (%fs-node-kind x) (vector-ref x 0))
(define (%fs-atom? x) (eq? (%fs-node-kind x) 'atom))
(define (%fs-list? x) (eq? (%fs-node-kind x) 'list))
(define (%fs-comment? x) (eq? (%fs-node-kind x) 'comment))
(define (%fs-node-newlines x)
  (case (%fs-node-kind x) ((atom) (vector-ref x 3)) ((list) (vector-ref x 5)) (else (vector-ref x 2))))
(define (%fs-children x) (vector-ref x 3))
(define (%fs-prefix x) (if (%fs-atom? x) (vector-ref x 2) (vector-ref x 4)))

;; the nodes of a token list: answers (nodes . tokens-left), stopping at a close;
;; opener is the open token, or #f at the top level
(define (%fs-parse tokens opener)
  (let loop ((ts tokens) (nodes '()))
    (cond
      ((null? ts)
       (if opener
           (%fs-error (string-append "a " (%fs-text opener) " that is never closed") (%fs-line opener))
           (cons (reverse nodes) '())))
      ((eq? (%fs-kind (car ts)) 'close)
       (if opener (cons (reverse nodes) ts) (%fs-error "a ) with no (" (%fs-line (car ts)))))
      ((eq? (%fs-kind (car ts)) 'comment)
       (loop (cdr ts) (cons (vector 'comment (%fs-text (car ts)) (%fs-newlines (car ts))) nodes)))
      (else
       (let ((r (%fs-datum ts)))
         (loop (cdr r) (cons (car r) nodes)))))))

;; one datum and what follows it: (node . tokens-left)
(define (%fs-datum ts)
  (let prefixes ((ts ts) (prefix "") (newlines #f))
    (let* ((t (car ts))
           (nl (or newlines (%fs-newlines t))))
      (case (%fs-kind t)
        ((prefix)
         (if (or (null? (cdr ts)) (eq? (%fs-kind (cadr ts)) 'close))
             (%fs-error "a quote with nothing after it" (%fs-line t)))
         (prefixes (cdr ts) (string-append prefix (%fs-text t)) nl))
        ((open)
         (let ((r (%fs-parse (cdr ts) t)))
           (cons (vector 'list (%fs-text t) ")" (car r) prefix nl) (cdr (cdr r)))))
        ((comment) (%fs-error "a comment between a quote and its datum" (%fs-line t)))
        (else (cons (vector 'atom (%fs-text t) prefix nl) (cdr ts)))))))

;;; ---------------------------------------------------------------------------
;;; Layout

;; how many arguments after the head stay on a form's first line
(define format-source-headers
  '((define . 1) (define-macro . 1) (define-syntax . 1) (define-special-form . 1)
    (set! . 1) (lambda . 1) (let* . 1) (letrec . 1) (letrec* . 1)
    (let-values . 1) (let*-values . 1) (do . 2) (when . 1) (unless . 1) (if . 1)
    (case . 1) (guard . 1) (parameterize . 1) (syntax-rules . 1) (define-test . 1)
    (defun . 2) (defmacro . 2) (defvar . 1) (defparameter . 1) (defconstant . 1)
    (dolist . 1) (dotimes . 1) (flet . 1) (labels . 1) (handler-case . 1)
    (unwind-protect . 1) (restart-case . 1) (with-time . 1)))

;; the forms whose header argument (at that position) is a binding list
(define %fs-binding-forms '(let let* letrec letrec* let-values let*-values parameterize do flet labels))

;; the head's name, when it is a plain symbol
(define (%fs-head-name node)
  (let ((kids (filter (lambda (k) (not (%fs-comment? k))) (%fs-children node))))
    (and (pair? kids) (%fs-atom? (car kids)) (string=? (%fs-prefix (car kids)) "")
         (string->symbol (%fs-text (car kids))))))

(define (%fs-header-count node clause?)
  (let ((name (%fs-head-name node)))
    (cond ((not (string=? (%fs-prefix node) "")) 0)     ; data
          (clause? 0)                                     ; a clause's test is its head
          ((eq? name 'let)                                ; a named let keeps its name too
           (let ((kids (filter (lambda (k) (not (%fs-comment? k))) (%fs-children node))))
             (if (and (pair? (cdr kids)) (%fs-atom? (cadr kids))) 2 1)))
          ((and name (assq name format-source-headers)) => cdr)
          (else 0))))

(define (%fs-has-comment? node)
  (and (%fs-list? node)
       (any (lambda (k) (or (%fs-comment? k) (%fs-has-comment? k))) (%fs-children node))))

;; Forms with a body are always laid out over lines; so is a define of a
;; procedure. Every other form (a call, if, when, lambda, and, quoted data)
;; stays on one line unless it holds one of those, or a comment.
(define %fs-breaking
  '(define-macro define-syntax define-special-form defun defmacro let let* letrec
    letrec* let-values let*-values cond case do begin guard parameterize syntax-rules
    define-test flet labels handler-case restart-case unwind-protect dolist dotimes))

(define (%fs-data? node) (not (string=? (%fs-prefix node) "")))

(define (%fs-breaks? node)
  (and (%fs-list? node) (not (%fs-data? node))
       (let ((name (%fs-head-name node)))
         (or (and name (memq name %fs-breaking) #t)
             (and (eq? name 'define)
                  (let ((kids (filter (lambda (k) (not (%fs-comment? k))) (%fs-children node))))
                    (and (pair? (cdr kids)) (%fs-list? (cadr kids)))))))))

;; whether node or any form inside it must break (quoted data never does)
(define (%fs-holds-breaking? node)
  (and (%fs-list? node) (not (%fs-data? node))
       (or (%fs-breaks? node)
           (any %fs-holds-breaking? (filter %fs-list? (%fs-children node))))))

;; one line: an atom, or a list with no comment and nothing that must break
(define (%fs-one-line? node)
  (or (%fs-atom? node)
      (and (not (%fs-has-comment? node)) (not (%fs-holds-breaking? node)))))

(define (%fs-binding-simple? node) (%fs-one-line? node))

(define (%fs-flat node)
  (if (%fs-atom? node)
      (string-append (%fs-prefix node) (vector-ref node 1))
      (string-append (%fs-prefix node) (vector-ref node 1)
                     (string-join (map %fs-flat (%fs-children node)) " ")
                     (vector-ref node 2))))

;; the layout of node at level: its first line unindented, the others indented
(define (%fs-layout node level indent clause?)
  (cond
    ((%fs-atom? node) (%fs-flat node))
    ((%fs-one-line? node) (%fs-flat node))
    (else (%fs-layout-list node level indent clause?))))

(define (%fs-layout-list node level indent clause?)
  (let* ((out (open-output-string))
         (name (%fs-head-name node))
         (headers (%fs-header-count node clause?))
         (clauses? (and (memq name '(cond case)) (string=? (%fs-prefix node) "")))
         (deeper (indent (+ level 1))))
    (write-string (%fs-prefix node) out)
    (write-string (vector-ref node 1) out)
    ;; on-first-line: how many more items may join the first line (the head, then
    ;; the headers); a comment ends the first line
    (let loop ((kids (%fs-children node)) (position 0) (first-line? #t))
      (if (null? kids)
          (begin (newline out) (write-string (indent level) out) (write-string (vector-ref node 2) out))
          (let ((k (car kids)))
            (cond
              ((%fs-comment? k)
               (if (and (= (%fs-node-newlines k) 0) (> position 0))
                   (begin (write-string " " out) (write-string (vector-ref k 1) out))
                   (begin (newline out) (write-string deeper out) (write-string (vector-ref k 1) out)))
               (loop (cdr kids) position #f))
              ((and first-line? (<= position headers))
               (when (> position 0) (write-string " " out))
               (write-string (%fs-header-item node k position level indent) out)
               (loop (cdr kids) (+ position 1) #t))
              (else
               (newline out)
               (when (and (> position 0) (>= (%fs-node-newlines k) 2)) (newline out))
               (write-string deeper out)
               (write-string (%fs-layout k (+ level 1) indent (and clauses? (> position 0))) out)
               (loop (cdr kids) (+ position 1) #f))))))
    (get-output-string out)))

;; the head or a header argument, on the first line
(define (%fs-header-item node k position level indent)
  (let ((name (%fs-head-name node)))
    (cond
      ((= position 0) (%fs-layout k (+ level 1) indent #f))
      ((and (%fs-list? k) (memq name %fs-binding-forms) (string=? (%fs-prefix node) "")
            (= position (if (and (eq? name 'let) (= (%fs-header-count node #f) 2)) 2 1)))
       (%fs-layout-bindings k level indent))
      ((%fs-has-comment? k) (%fs-layout k (+ level 1) indent #f))
      (else (%fs-flat k)))))

;; a binding list: on one line when every binding is simple, else one a line
(define (%fs-layout-bindings node level indent)
  (if (and (not (%fs-has-comment? node)) (every %fs-binding-simple? (%fs-children node)))
      (%fs-flat node)
      (let ((out (open-output-string)))
        (write-string (vector-ref node 1) out)
        (for-each (lambda (k)
                    (if (and (%fs-comment? k) (= (%fs-node-newlines k) 0))
                        (begin (write-string " " out) (write-string (vector-ref k 1) out))
                        (begin (newline out) (write-string (indent (+ level 2)) out)
                               (write-string (if (%fs-comment? k)
                                                 (vector-ref k 1)
                                                 (%fs-layout-binding k (+ level 2) indent))
                                             out))))
                  (%fs-children node))
        (newline out)
        (write-string (indent (+ level 1)) out)
        (write-string (vector-ref node 2) out)
        (get-output-string out))))

;; one binding: (name value), with name as its header
(define (%fs-layout-binding node level indent)
  (if (%fs-binding-simple? node)
      (%fs-flat node)
      (%fs-layout-list (vector 'list (vector-ref node 1) (vector-ref node 2) (%fs-children node) "" 0)
                       level indent #t)))

;;; ---------------------------------------------------------------------------
;;; The whole text

(define (%fs-indenter style width)
  (let ((unit (if (eq? style 'spaces) (make-string width #\space) (string #\tab))))
    (lambda (level)
      (let loop ((i 0) (acc ""))
        (if (< i level) (loop (+ i 1) (string-append acc unit)) acc)))))

(define (format-source text . options)
  "(format-source text [style width])
text, cog-lisp source, laid out: a form whose elements hold no list on one line; otherwise its head and header arguments (if's test, let's bindings, define's name) on the first line, each other argument on a line of its own one level deeper, and the closing parenthesis on its own line. Comments, strings and every other token come out exactly as they went in; only whitespace changes. Indents with tabs, or with (format-source text 'spaces 2) that many spaces a level. Text that does not read is an error naming the line."
  (let* ((style (if (pair? options) (car options) 'tabs))
         (width (if (and (pair? options) (pair? (cdr options))) (cadr options) 4))
         (indent (%fs-indenter style width))
         (tokens (%fs-tokens text))
         (nodes (car (%fs-parse tokens #f)))
         (out (open-output-string)))
    (let loop ((ns nodes) (first? #t))
      (unless (null? ns)
        (let ((k (car ns)))
          (cond
            ((and (%fs-comment? k) (= (%fs-node-newlines k) 0) (not first?))
             (write-string " " out) (write-string (vector-ref k 1) out))
            (else
             (unless first?
               (newline out)
               (let loop2 ((extra (min 2 (- (%fs-node-newlines k) 1))))
                 (when (> extra 0) (newline out) (loop2 (- extra 1)))))
             (write-string (if (%fs-comment? k) (vector-ref k 1) (%fs-layout k 0 indent #f)) out)))
          (loop (cdr ns) #f))))
    (unless (null? nodes) (newline out))
    (let ((result (get-output-string out)))
      ;; only whitespace may have changed
      (unless (equal? (map %fs-text tokens) (map %fs-text (%fs-tokens result)))
        (error "format-source: the layout would change the code; the text is left as it was"))
      result)))
