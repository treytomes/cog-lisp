;;; json.lisp -- json-read and json-write, in LISP terms (specs/https-and-json.md R-3)
;;;
;;;   JSON           cog-lisp
;;;   object         hash table, string keys
;;;   array          vector
;;;   string         string
;;;   number         number
;;;   true, false    #t, #f
;;;   null           (), the empty list (Common Lisp's nil)
;;;
;;; JSON has no lists, so () cannot be mistaken for anything when reading: an
;;; empty array reads as #(). In cog-lisp only #f is false, so () is true: test a
;;; null with null?, never with a plain if.
;;;
;;; Reading: Pharo's STONJSON parses, and the result is turned into LISP data,
;;; as ~/projects/lisp-expert's weather/json.lisp (json->lisp) does; arrays are
;;; vectors and null is () here, as the spec's table says. Writing is LISP: an
;;; object's keys are written sorted, so the same table always writes the same
;;; text. Loaded by the build and compiled by the seed, so it is plain code.

;; a STONJSON value as LISP data
(define (%json->lisp v)
  (cond ((smalltalk-nil? v) '())
        ([v isKindOf: (smalltalk Dictionary)]
         (let ((table (make-hash-table)))
           (vector-for-each (lambda (k) (hash-table-set! table k (%json->lisp [v at: k])))
                            [[v keys] asArray])
           table))
        ((vector? v)
         (let ((out (make-vector (vector-length v))))
           (let loop ((i 0))
             (if (< i (vector-length v))
                 (begin (vector-set! out i (%json->lisp (vector-ref v i))) (loop (+ i 1)))
                 out))))
        (else v)))

(define (json-read text)
  "(json-read string)
The value of the JSON text in string: an object is a hash table with string keys, an array a vector, true and false are #t and #f, and null is (), the empty list. Signals an error naming the place for text that is not JSON."
  (if (not (string? text)) (error "json-read: not a string" text))
  (%json->lisp
   (guard (e (#t (error (string-append "json-read: " (error-object-message e)))))
     [(smalltalk STONJSON) fromString: text])))
[json-read category: "Ports"]

;; writing
(define (%json-hex4 n)
  (let ((s (number->string n 16)))
    (string-append (make-string (- 4 (string-length s)) #\0) s)))

(define (%json-write-string s port)
  (write-char #\" port)
  (let loop ((i 0))
    (if (< i (string-length s))
        (let* ((c (string-ref s i)) (code (char->integer c)))
          (cond ((eq? c #\") (write-string "\\\"" port))
                ((eq? c #\\) (write-string "\\\\" port))
                ((eq? c #\newline) (write-string "\\n" port))
                ((eq? c #\return) (write-string "\\r" port))
                ((eq? c #\tab) (write-string "\\t" port))
                ((< code 32) (write-string (string-append "\\u" (%json-hex4 code)) port))
                (else (write-char c port)))
          (loop (+ i 1)))))
  (write-char #\" port))

(define (%json-sorted-keys table)
  (let ((keys (hash-table-keys table)))
    (let insert-all ((ks keys) (sorted '()))
      (if (null? ks)
          sorted
          (insert-all (cdr ks)
                      (let insert ((k (car ks)) (l sorted))
                        (cond ((null? l) (list k))
                              ((string<? k (car l)) (cons k l))
                              (else (cons (car l) (insert k (cdr l)))))))))))

(define (%json-write v port)
  (cond ((null? v) (write-string "null" port))
        ((eq? v #t) (write-string "true" port))
        ((eq? v #f) (write-string "false" port))
        ((string? v) (%json-write-string v port))
        ((exact-integer? v) (write-string (number->string v) port))
        ((real? v)
         (if (or (nan? v) (infinite? v)) (error "json-write: not a JSON number" v))
         (write-string (number->string (exact->inexact v)) port))
        ((vector? v)
         (write-char #\[ port)
         (let loop ((i 0))
           (if (< i (vector-length v))
               (begin (if (> i 0) (write-char #\, port))
                      (%json-write (vector-ref v i) port)
                      (loop (+ i 1)))))
         (write-char #\] port))
        ((hash-table? v)
         (write-char #\{ port)
         (let loop ((ks (%json-sorted-keys v)) (first #t))
           (if (pair? ks)
               (begin
                 (if (not (string? (car ks))) (error "json-write: an object key is not a string" (car ks)))
                 (if (not first) (write-char #\, port))
                 (%json-write-string (car ks) port)
                 (write-char #\: port)
                 (%json-write (hash-table-ref v (car ks)) port)
                 (loop (cdr ks) #f))))
         (write-char #\} port))
        (else (error "json-write: no JSON for" v))))

(define (json-write value . port)
  "(json-write value [port])
Writes value as JSON text, to port or the current output: a hash table with string keys as an object (its keys sorted), a vector as an array, a string, a real number, #t and #f, and () as null. Signals an error for anything else, such as a list or a symbol."
  ;; written to a string first, so a value with no JSON writes nothing at all
  (let ((text (open-output-string)))
    (%json-write value text)
    (write-string (get-output-string text) (if (pair? port) (car port) (current-output-port)))))
[json-write category: "Ports"]
