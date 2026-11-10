;;; pretty.lisp -- data as a readable, indented string: (pretty-string value [indent])
;;;
;;; Load with (require 'pretty). From ~/projects/lisp-expert's pretty.lisp, where
;;; it was lisp-pretty (specs/22-lisp-expert-libraries.md R-4). Changed: the name;
;;; its own string-join and ->string are gone (string-join is built in, with the
;;; same arguments); a hash table's keys are printed sorted, so the same table
;;; always prints the same way; and a vector is printed too.
;;;
;;; A list prints one element a line, indented, between ( and ); a hash table as
;;; #hash( key: value, ... ); a dotted pair as (a . b); strings as written, with
;;; their quotes; () as (); #t and #f as themselves.

;;; A library (specs/27-namespaces.md): (require 'pretty) brings these names in; each
;;; is also pretty:name everywhere, and the names not exported are private.

(library pretty
  (export pretty-string))

(define (%pretty-atom x)
  (cond ((string? x) (with-output-to-string (lambda () (write x))))
        ((eq? x #t) "#t")
        ((eq? x #f) "#f")
        ((smalltalk-nil? x) "#<null>")
        (else (with-output-to-string (lambda () (display x))))))

(define (%pretty-key k)
  (if (string? k) (with-output-to-string (lambda () (write k))) (%pretty-atom k)))

;; the items, each on a line indented by indent + 2, between open and close
(define (%pretty-block open items close indent)
  (let ((pad (make-string indent #\space))
        (inner (make-string (+ indent 2) #\space)))
    (string-append open "\n"
                   (string-join (map (lambda (item) (string-append inner item)) items) ",\n")
                   "\n" pad close)))

(define (%pretty value indent)
  (cond ((and (pair? value) (not (list? value)))
         (string-append "(" (%pretty (car value) indent) " . " (%pretty (cdr value) indent) ")"))
        ((null? value) "()")
        ((list? value)
         (%pretty-block "(" (map (lambda (x) (%pretty x (+ indent 2))) value) ")" indent))
        ((vector? value)
         (if (= (vector-length value) 0)
             "#()"
             (%pretty-block "#(" (map (lambda (x) (%pretty x (+ indent 2))) (vector->list value)) ")" indent)))
        ((hash-table? value)
         (let ((keys (sort (hash-table-keys value) (lambda (a b) (string<? (%pretty-key a) (%pretty-key b))))))
           (if (null? keys)
               "#hash()"
               (%pretty-block "#hash("
                              (map (lambda (k) (string-append (%pretty-key k) ": " (%pretty (hash-table-ref value k) (+ indent 2))))
                                   keys)
                              ")" indent))))
        (else (%pretty-atom value))))

(define (pretty-string value . indent)
  "(pretty-string value [indent])
value as a readable string: a list one element a line, a hash table as #hash( key: value, ... ) with its keys sorted, nested ones indented, the rest as display shows them (strings as write does). indent, 0 by default, is the column the value starts at."
  (%pretty value (if (pair? indent) (car indent) 0)))
