;;; reader.lisp -- cog-lisp's reader, written in cog-lisp
;;; (specs/phase-8-self-hosting.md step 8.2)
;;;
;;; Written as a function-for-function counterpart of the reader written in
;;; Smalltalk (LispReader in src/coglisp-reader.st up to release v0.1.2; it
;;; retired in Phase 9 step 9.1, and this is now cog-lisp's only reader): the same
;;; datums, the same source ranges for lists, the same read errors with the same
;;; messages, positions and incomplete flags. It reads a string; offsets are
;;; 0-based. LispReader on: is how Smalltalk code reaches it.
;;;
;;;   (define r (make-reader "(a b) 42"))
;;;   (reader-next r)            -> (a b), then 42, then the eof object
;;;   (reader-source-for r lst)  -> "(a b)": the text a list was read from
;;;   (read-all s)               -> every datum, as a list
;;;   (read-datum port)          -> the next datum from a string or file port

;;; ---------------------------------------------------------------------------
;;; The reader's state: a vector, with an accessor and a setter per field.
;;; The ones every character goes through are macros over Smalltalk sends (at:,
;;; asInteger), which the VM runs as primitives, rather than calls of vector-ref
;;; and string-ref with their checks; characters are compared with eq? (they are
;;; immediate objects), which compiles to ==, not with the variadic char=? (step
;;; 8.5: the reader in use reads every file). rd-pos! and rd-at-end? stay
;;; procedures too: LispReaderInLisp calls them.

(define (make-reader source)
  (vector source 0 (string-length source) (make-hash-table eq?) #f 0))

(define-macro (rd-source r) `[,r at: 1])
(define-macro (rd-pos r) `[,r at: 2])
(define-macro (rd-set-pos! r n) `[,r at: 2 put: ,n])
(define (rd-pos! r n) (rd-set-pos! r n))
(define-macro (rd-len r) `[,r at: 3])
(define (rd-ranges r) (vector-ref r 3))
(define (rd-labels r)                       ; made when first needed
  (or (vector-ref r 4)
      (begin (vector-set! r 4 (make-hash-table eqv?)) (vector-ref r 4))))
(define (reader-datum-start r) (vector-ref r 5))
(define (reader-position r) (rd-pos r))

(define-macro (rd-end? r) `(>= [,r at: 2] [,r at: 3]))
(define (rd-at-end? r) (rd-end? r))
(define-macro (rd-peek r)
  `(let ((%rd-p [,r at: 2]))
     (if (>= %rd-p [,r at: 3]) #f [[,r at: 1] at: (+ %rd-p 1)])))
(define-macro (rd-next! r)
  `(let ((%rd-p [,r at: 2]))
     [,r at: 2 put: (+ %rd-p 1)]
     [[,r at: 1] at: (+ %rd-p 1)]))
(define-macro (rd-peek-is? r ch)
  `(eq? (rd-peek ,r) ,ch))

;;; ---------------------------------------------------------------------------
;;; Errors: a LispReadError, as the Smalltalk reader signals it.

(define (rd-error-at msg pos incomplete)
  (let ((e [(smalltalk LispReadError) new]))
    [e position: pos]
    [e incomplete: incomplete]
    [e signal: msg]))

(define (rd-error r msg) (rd-error-at msg (rd-pos r) #f))
(define (rd-incomplete msg pos) (rd-error-at msg pos #t))

;;; ---------------------------------------------------------------------------
;;; Characters

;; The class of each ASCII character: 1 a separator (as Smalltalk's isSeparator:
;; space, tab, lf, cr, form feed), 2 another delimiter, 0 neither. Every other
;; character is 0. The tests take a character, never #f.
(define rd-classes
  (let ((v (make-vector 128 0)))
    (for-each (lambda (k) (vector-set! v k 1)) '(32 9 10 13 12))
    (for-each (lambda (c) (vector-set! v (char->integer c) 2))
              '(#\( #\) #\[ #\] #\" #\; #\' #\` #\,))
    v))

(define-macro (rd-class c)
  `(let ((%rd-k [,c asInteger])) (if (< %rd-k 128) [rd-classes at: (+ %rd-k 1)] 0)))
(define-macro (rd-separator? c) `(= (rd-class ,c) 1))
(define-macro (rd-delimiter? c) `(> (rd-class ,c) 0))

;;; ---------------------------------------------------------------------------
;;; Whitespace and comments

(define (rd-skip-intertoken! r)
  (let loop ()
    (let ((c (rd-peek r)))
      (cond ((not c) #f)
            ((rd-separator? c) (rd-next! r) (loop))
            ((eq? c #\;) (rd-skip-line-comment! r) (loop))
            ((and (eq? c #\#) (rd-block-comment-ahead? r)) (rd-skip-block-comment! r) (loop))
            (else #f)))))

(define (rd-block-comment-ahead? r)
  (let ((p (+ (rd-pos r) 1)))
    (and (< p (rd-len r)) (eq? (string-ref (rd-source r) p) #\|))))

(define (rd-skip-line-comment! r)
  (let loop ()
    (let ((c (rd-peek r)))
      (cond ((not c) #f)
            ((eq? c #\newline) (rd-next! r))
            (else (rd-next! r) (loop))))))

(define (rd-try-consume! r a b)
  (let ((p (rd-pos r)) (src (rd-source r)))
    (if (and (< (+ p 1) (rd-len r))
             (eq? (string-ref src p) a)
             (eq? (string-ref src (+ p 1)) b))
        (begin (rd-set-pos! r (+ p 2)) #t)
        #f)))

(define (rd-skip-block-comment! r)
  (let ((start (rd-pos r)))
    (rd-set-pos! r (+ start 2))
    (let loop ((depth 1))
      (when (> depth 0)
        (when (rd-end? r) (rd-incomplete "unterminated block comment" start))
        (cond ((rd-try-consume! r #\# #\|) (loop (+ depth 1)))
              ((rd-try-consume! r #\| #\#) (loop (- depth 1)))
              (else (rd-next! r) (loop depth)))))))

;;; ---------------------------------------------------------------------------
;;; Datums

(define (reader-next r)
  (rd-skip-intertoken! r)
  (if (rd-end? r)
      (eof-object)
      (begin (vector-set! r 5 (rd-pos r))
             (rd-datum r))))

(define (rd-next-datum r)
  (rd-skip-intertoken! r)
  (when (rd-end? r) (rd-incomplete "unexpected end of input" (rd-pos r)))
  (rd-datum r))

(define (rd-datum r)
  (let ((c (rd-peek r)))
    (cond ((eq? c #\() (rd-list r))
          ((eq? c #\)) (rd-error r "unexpected )"))
          ((eq? c #\[) (rd-bracket r))
          ((eq? c #\]) (rd-error r "unexpected ]"))
          ((eq? c #\') (rd-next! r) (rd-abbreviation r 'quote))
          ((eq? c #\`) (rd-next! r) (rd-abbreviation r 'quasiquote))
          ((eq? c #\,)
           (rd-next! r)
           (if (rd-peek-is? r #\@)
               (begin (rd-next! r) (rd-abbreviation r 'unquote-splicing))
               (rd-abbreviation r 'unquote)))
          ((eq? c #\") (rd-string r))
          ((eq? c #\#) (rd-hash r))
          (else (rd-token r)))))

(define (rd-abbreviation r name)
  (list name (rd-next-datum r)))

;;; Lists, with source ranges: the 1-based first and last character of the text

(define (rd-list r)
  (let* ((start (rd-pos r))
         (result (rd-list-body r start)))
    (when (pair? result)
      (hash-table-set! (rd-ranges r) result (cons (+ start 1) (rd-pos r))))
    result))

(define (rd-list-body r start)
  (rd-next! r)                                  ; the (
  (let loop ((items '()))
    (rd-skip-intertoken! r)
    (when (rd-end? r) (rd-incomplete "unterminated list" start))
    (cond ((rd-peek-is? r #\))
           (rd-next! r)
           (reverse items))
          ((rd-dot-marker? r)
           (when (null? items) (rd-error r "bad dotted pair"))
           (rd-next! r)
           (let ((tail (rd-next-datum r)))
             (rd-skip-intertoken! r)
             (when (rd-end? r) (rd-incomplete "unterminated list" start))
             (unless (rd-peek-is? r #\)) (rd-error r "bad dotted pair"))
             (rd-next! r)
             (append (reverse items) tail)))
          (else (loop (cons (rd-datum r) items))))))

(define (rd-dot-marker? r)
  (and (rd-peek-is? r #\.)
       (let ((p (+ (rd-pos r) 1)))
         (or (>= p (rd-len r)) (rd-delimiter? (string-ref (rd-source r) p))))))

;;; Brackets: [receiver message ...] reads as (send receiver selector arg ...)

(define (rd-bracket r)
  (let ((start (rd-pos r)))
    (rd-next! r)                                ; the [
    (let loop ((parts '()))
      (rd-skip-intertoken! r)
      (when (rd-end? r) (rd-incomplete "unterminated [" start))
      (if (rd-peek-is? r #\])
          (begin
            (rd-next! r)
            (let ((result (rd-send-form (reverse parts) start r)))
              (hash-table-set! (rd-ranges r) result (cons (+ start 1) (rd-pos r)))
              result))
          (loop (cons (rd-datum r) parts))))))

(define (rd-identifier? s) [s matchesRegex: "[a-zA-Z_][a-zA-Z0-9_]*"])
(define (rd-keyword? s) [s matchesRegex: "[a-zA-Z_][a-zA-Z0-9_]*\\:"])
(define (rd-binary? s)
  (and (> (string-length s) 0)
       (let loop ((i 0))
         (or (= i (string-length s))
             (and (string-index "+-*/\\<>=~@%|&?" (string-ref s i))
                  (loop (+ i 1)))))))

(define (rd-bad-send start)
  (rd-error-at "bad message send: brackets are Smalltalk sends; use ( ) for grouping" start #f))

(define (rd-send-form parts start r)
  (when (< (length parts) 2) (rd-bad-send start))
  (let* ((recv0 (car parts))
         (recv (if (and (symbol? recv0) (char-upper-case? (string-ref (symbol->string recv0) 0)))
                   (list 'smalltalk recv0)
                   recv0))
         (rest (cdr parts)))
    (cond ((and (= (length rest) 1) (symbol? (car rest)) (rd-identifier? (symbol->string (car rest))))
           (list 'send recv (car rest)))
          ((and (= (length rest) 2) (symbol? (car rest)) (rd-binary? (symbol->string (car rest))))
           (list 'send recv (car rest) (car (cdr rest))))
          ((and (= (modulo (length rest) 2) 0) (rd-keyword-pairs? rest))
           (cons 'send (cons recv (cons (rd-selector-of rest) (rd-every-second rest)))))
          (else (rd-bad-send start)))))

(define (rd-keyword-pairs? rest)
  (or (null? rest)
      (and (symbol? (car rest))
           (rd-keyword? (symbol->string (car rest)))
           (rd-keyword-pairs? (cdr (cdr rest))))))

(define (rd-selector-of rest)
  (let loop ((xs rest) (parts '()))
    (if (null? xs)
        (string->symbol (apply string-append (reverse parts)))
        (loop (cdr (cdr xs)) (cons (symbol->string (car xs)) parts)))))

(define (rd-every-second rest)
  (if (null? rest) '() (cons (car (cdr rest)) (rd-every-second (cdr (cdr rest))))))

;;; Strings

(define (rd-string r)
  (let ((start (rd-pos r))
        (out (open-output-string)))
    (rd-next! r)                                ; the opening "
    (let loop ()
      (when (rd-end? r) (rd-incomplete "unterminated string" start))
      (let ((c (rd-next! r)))
        (cond ((eq? c #\") (get-output-string out))
              ((eq? c #\\) (write-char (rd-escape r start) out) (loop))
              (else (write-char c out) (loop)))))))

(define (rd-escape r start)
  (when (rd-end? r) (rd-incomplete "unterminated string" start))
  (let ((c (rd-next! r)))
    (cond ((eq? c #\") #\")
          ((eq? c #\\) #\\)
          ((eq? c #\n) #\newline)
          ((eq? c #\t) #\tab)
          ((eq? c #\r) #\return)
          ((eq? c #\0) (integer->char 0))
          ((eq? c #\a) (integer->char 7))
          ((eq? c #\b) (integer->char 8))
          ((eq? c #\x) (rd-hex-escape r start))
          (else (rd-error r "unknown string escape")))))

(define (rd-hex-digit? c) (and (string-index "0123456789abcdefABCDEF" c) #t))

(define (rd-hex-escape r start)
  (let loop ((digits '()))
    (when (rd-end? r) (rd-incomplete "unterminated string" start))
    (let ((c (rd-next! r)))
      (cond ((eq? c #\;)
             (when (null? digits) (rd-error r "bad \\x escape: expected hex digits and ;"))
             (let ((code (string->number (list->string (reverse digits)) 16)))
               (when (> code 1114111) (rd-error r "bad \\x escape: no such character"))
               (integer->char code)))
            ((rd-hex-digit? c) (loop (cons c digits)))
            (else (rd-error r "bad \\x escape: expected hex digits and ;"))))))

;;; Tokens: numbers and symbols

(define (rd-token r)
  (let ((start (rd-pos r)))
    (let loop ()
      (let ((c (rd-peek r)))
        (unless (or (not c) (rd-delimiter? c) (and (eq? c #\#) (rd-block-comment-ahead? r)))
          (rd-next! r)
          (loop))))
    (let ((s (substring (rd-source r) start (rd-pos r))))
      (cond ((= (string-length s) 0) (rd-error r "unexpected character"))
            ((string=? s ".") (rd-error-at "unexpected dot" (- (rd-pos r) 1) #f))
            (else (rd-classify s))))))

(define (rd-classify s)
  (cond ((rd-integer-text? s) (rd-parse-integer s))
        ((rd-float-text? s) (rd-parse-float s))
        (else (string->symbol s))))

(define (rd-sign? c) (or (eq? c #\+) (eq? c #\-)))

(define (rd-integer-text? s)
  (let* ((n (string-length s))
         (i (if (and (> n 0) (rd-sign? (string-ref s 0))) 1 0)))
    (and (< i n)
         (let loop ((k i))
           (or (= k n) (and (char-numeric? (string-ref s k)) (loop (+ k 1))))))))

(define (rd-parse-integer s)
  (let* ((neg (eq? (string-ref s 0) #\-))
         (i (if (rd-sign? (string-ref s 0)) 1 0)))
    (let loop ((k i) (v 0))
      (if (= k (string-length s))
          (if neg (- v) v)
          (loop (+ k 1) (+ (* v 10) (digit-value (string-ref s k))))))))

;; count the digits starting at i: answers the index after them
(define (rd-skip-digits s i)
  (if (and (< i (string-length s)) (char-numeric? (string-ref s i))) (rd-skip-digits s (+ i 1)) i))

(define (rd-float-text? s)
  (let* ((n (string-length s))
         (i0 (if (and (> n 0) (rd-sign? (string-ref s 0))) 1 0))
         (i1 (rd-skip-digits s i0))
         (has-dot (and (< i1 n) (eq? (string-ref s i1) #\.)))
         (i2 (if has-dot (+ i1 1) i1))
         (i3 (rd-skip-digits s i2)))
    (and (> (+ (- i1 i0) (- i3 i2)) 0)
         (let ((has-exp (and (< i3 n) (memv (string-ref s i3) '(#\e #\E)) #t)))
           (if has-exp
               (let* ((j0 (+ i3 1))
                      (j1 (if (and (< j0 n) (rd-sign? (string-ref s j0))) (+ j0 1) j0))
                      (j2 (rd-skip-digits s j1)))
                 (and (> j2 j1) (= j2 n)))
               (and has-dot (= i3 n)))))))

(define (rd-power-of-ten k) [10 raisedTo: k])

(define (rd-digits-value s from to)
  (let loop ((k from) (v 0))
    (if (= k to) v (loop (+ k 1) (+ (* v 10) (digit-value (string-ref s k)))))))

(define (rd-parse-float s)
  (let* ((n (string-length s))
         (sign (if (eq? (string-ref s 0) #\-) -1 1))
         (i0 (if (rd-sign? (string-ref s 0)) 1 0))
         (i1 (rd-skip-digits s i0))
         (int-part (rd-digits-value s i0 i1))
         (has-dot (and (< i1 n) (eq? (string-ref s i1) #\.)))
         (i2 (if has-dot (+ i1 1) i1))
         (i3 (rd-skip-digits s i2))
         (frac-part (rd-digits-value s i2 i3))
         (frac-len (- i3 i2))
         (exponent
          (if (< i3 n)
              (let* ((j0 (+ i3 1))
                     (neg (eq? (string-ref s j0) #\-))
                     (j1 (if (rd-sign? (string-ref s j0)) (+ j0 1) j0))
                     (e (rd-digits-value s j1 n)))
                (if neg (- e) e))
              0))
         (mantissa (+ (* int-part (rd-power-of-ten frac-len)) frac-part))
         (value (* (/ (* sign mantissa) (rd-power-of-ten frac-len)) (rd-power-of-ten exponent))))
    (if (and (= value 0) (= sign -1))
        [(smalltalk Float) negativeZero]           ; -0.0 keeps its sign
        [value asFloat])))

;;; # syntax: characters, vectors, booleans, datum labels

(define (rd-hash r)
  (rd-next! r)                                  ; the #
  (when (rd-end? r) (rd-incomplete "unexpected # at end of input" (- (rd-pos r) 1)))
  (let ((c (rd-peek r)))
    (cond ((eq? c #\\) (rd-next! r) (rd-character r))
          ((eq? c #\() (rd-vector r))
          ((char-numeric? c) (rd-label-start r))
          (else
           (let ((word (rd-hash-word r)))
             (cond ((or (string=? word "t") (string=? word "true")) #t)
                   ((or (string=? word "f") (string=? word "false")) #f)
                   (else (rd-error r (string-append "unknown # syntax: #" word)))))))))

(define (rd-hash-word r)
  (let ((start (rd-pos r)))
    (let loop ()
      (unless (or (rd-end? r) (rd-delimiter? (rd-peek r)))
        (rd-next! r)
        (loop)))
    (substring (rd-source r) start (rd-pos r))))

(define (rd-vector r)
  (let* ((start (rd-pos r))
         (items (rd-list-body r start)))
    (unless (list? items)
      (rd-error-at "bad vector: a dotted tail" (- start 1) #f))
    (let ((v (list->vector items)))
      [v beReadOnlyObject]
      v)))

(define (rd-label-start r)
  (let loop ((n 0))
    (if (and (rd-peek r) (char-numeric? (rd-peek r)))
        (loop (+ (* n 10) (digit-value (rd-next! r))))
        (if (or (rd-peek-is? r #\=) (rd-peek-is? r #\#))
            (rd-label r n (rd-next! r))
            (rd-error r (string-append "bad datum label: expected = or # after #" (number->string n)))))))

(define (rd-label r n kind)
  (let ((labels (rd-labels r)))
    (if (eq? kind #\#)
        (hash-table-ref labels n
          (lambda () (rd-error r (string-append "unknown datum label #" (number->string n) "#"))))
        (let ((hole [(smalltalk LispLabelHole) new]))
          (hash-table-set! labels n hole)
          (let ((datum (rd-next-datum r)))
            (hash-table-set! labels n datum)
            (rd-fill! hole datum datum (make-hash-table eq?))
            datum)))))

;; replace hole by datum everywhere inside x (x may be cyclic already)
(define (rd-fill! hole datum x seen)
  (let loop ((cur x))
    (when (and (or (pair? cur) (vector? cur)) (not (hash-table-contains? seen cur)))
      (hash-table-set! seen cur #t)
      (if (vector? cur)
          (let ((ro [cur isReadOnlyObject]))
            (when ro [cur beWritableObject])
            (let each ((i 0))
              (when (< i (vector-length cur))
                (if (eq? (vector-ref cur i) hole)
                    [cur at: (+ i 1) put: datum]
                    (rd-fill! hole datum (vector-ref cur i) seen))
                (each (+ i 1))))
            (when ro [cur beReadOnlyObject]))
          (begin
            (if (eq? (car cur) hole) (set-car! cur datum) (rd-fill! hole datum (car cur) seen))
            (when (eq? (cdr cur) hole) (set-cdr! cur datum))
            (loop (cdr cur)))))))

(define (rd-character r)
  (when (rd-end? r) (rd-incomplete "unterminated character literal" (- (rd-pos r) 2)))
  (let ((start (rd-pos r)))
    (rd-next! r)
    (let loop ()
      (unless (or (rd-end? r) (rd-delimiter? (rd-peek r)))
        (rd-next! r)
        (loop)))
    (rd-decode-character r (substring (rd-source r) start (rd-pos r)))))

(define (rd-decode-character r name)
  (cond ((= (string-length name) 1) (string-ref name 0))
        ((string=? name "space") #\space)
        ((string=? name "newline") #\newline)
        ((string=? name "tab") #\tab)
        ((string=? name "return") #\return)
        ((string=? name "null") (integer->char 0))
        ((and (memv (string-ref name 0) '(#\x #\X)) (> (string-length name) 1))
         (let ((digits (substring name 1)))
           (unless (let all ((i 0)) (or (= i (string-length digits)) (and (rd-hex-digit? (string-ref digits i)) (all (+ i 1)))))
             (rd-error r (string-append "bad character code: #\\" name)))
           (let ((code (string->number digits 16)))
             (when (> code 1114111) (rd-error r (string-append "bad character code: #\\" name)))
             (integer->char code))))
        (else (rd-error r "unknown character name"))))

;;; ---------------------------------------------------------------------------
;;; Source text and conveniences

(define (reader-source-for r lst)
  (let ((range (hash-table-ref/default (rd-ranges r) lst #f)))
    (if range (substring (rd-source r) (- (car range) 1) (cdr range)) #f)))

(define (reader-range-of r lst) (hash-table-ref/default (rd-ranges r) lst #f))

;; One datum from an input port over text (a string or file port), leaving the
;; port just after it, as the read primitive does. Other ports (stdin) are read
;; by the Smalltalk reader.
(define (read-datum port)
  (let ((stream [port stream]))
    (if [stream isKindOf: (smalltalk ReadStream)]
        (let ((r (make-reader [stream originalContents])))
          (rd-pos! r [stream position])
          (let ((d (reader-next r)))
            [stream position: (rd-pos r)]
            d))
        (read port))))

(define (read-all s) (read-all-from-string s))

(define (read-all-from-string s)
  (let ((r (make-reader s)))
    (let loop ((acc '()))
      (let ((d (reader-next r)))
        (if (eof-object? d) (reverse acc) (loop (cons d acc)))))))

(define (read-from-string s)
  (let* ((r (make-reader s))
         (d (reader-next r)))
    (when (eof-object? d)
      (let ((e [(smalltalk LispReadError) new])) [e incomplete: #t] [e signal: "read: empty input"]))
    (unless (eof-object? (reader-next r))
      [[(smalltalk LispReadError) new] signal: "read: more than one datum"])
    d))
