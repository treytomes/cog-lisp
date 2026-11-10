;;; cl-common-names.lisp -- what lib/cl.lisp gained from lisp-expert's common.lisp
;;; (specs/22-lisp-expert-libraries.md R-2): fourth to tenth with setters, boundp,
;;; Common Lisp's remove and delete of an item, remove-duplicates and
;;; string-capitalize
(load "../../lib/test.lisp")
(require 'cl)

(define cl-names-bound 27)

(define-test "fourth to tenth, and setf of them"
  (let ((l (list 1 2 3 4 5 6 7 8 9 10)))
    (check (list (fourth l) (fifth l) (sixth l) (seventh l) (eighth l) (ninth l) (tenth l))
           '(4 5 6 7 8 9 10))
    (setf (fourth l) 'four (tenth l) 'ten)
    (check l '(1 2 3 four 5 6 7 8 9 ten))))

(define-test "boundp asks the global environment"
  (check (boundp 'cl-names-bound) #t)
  (check (boundp 'cl-names-never-defined) #f)
  (check (boundp 'car) #t)
  (check-error (boundp 27) "boundp: not a symbol: 27"))

(define-test "remove of an item, remove-if, remove-duplicates"
  (check (remove 'b '(a b c b)) '(a c))       ; Common Lisp's, shadowing SRFI 1's
  (check (remove-if even? '(1 2 3 4)) '(1 3))
  (check (remove-duplicates '(a b a c b)) '(a b c))
  (check (remove-duplicates '()) '()))

(define-test "string-capitalize, as Common Lisp's"
  (check (string-capitalize "hello wORLD") "Hello World")
  (check (string-capitalize "sample-person") "Sample-Person")
  (check (string-capitalize "") ""))

(run-tests)
