;;; cl-issues.lisp -- GitHub issues #1, #2, #3, #4 and #6, each against its own
;;; example (specs/24-cl-issues.md AC-1)
(load "../../lib/test.lisp")
(require 'cl)

(define-test "#6 boundp"
  (eval '(defvar *bound-here* 1))
  (check (boundp '*bound-here*) #t)
  (check (boundp 'no-such-name-anywhere) #f)
  (check-error (boundp 42) "boundp: not a symbol"))

(define-test "#2 format, with t and with nil (which is () here)"
  (check (with-output-to-string (lambda () (format t "~A plus ~A equals ~A.~%" 2 3 (+ 2 3))))
         "2 plus 3 equals 5.\n")
  (check (format nil "~A plus ~A equals ~A." 2 3 (+ 2 3)) "2 plus 3 equals 5.")
  (check (format '() "~D" 7) "7")
  (check (format #f "~D" 7) "7"))

(define-test "#3 defun, defmacro, defvar and defparameter answer the name"
  (check (eval '(defparameter *glob* 99)) '*glob*)
  (check *glob* 99)
  (check (eval '(defvar *v*)) '*v*)
  (check *v* '())
  (check (eval '(defun twice (x) (* 2 x))) 'twice)
  (check (twice 21) 42)
  (check (eval '(defmacro swap-args (f a b) (list f b a))) 'swap-args)
  (check (eval '(swap-args - 1 10)) 9))

(define-test "#4 defconstant defines the name and answers it"
  (check (eval '(defparameter *glob2* 1)) '*glob2*)
  (check (eval '(defconstant limit (+ *glob2* 1))) 'limit)
  (check limit 2))

(define-test "definitions still work inside a body"
  (let ()
    (defun inner (x) (+ x 1))
    (check (inner 1) 2)))

(define-test "#1 (deferred): nil is (), and () is true"
  (check nil '())
  (check (if nil 'true 'false) 'true)
  (check (null nil) #t)
  (check (if (null nil) 'empty 'not-empty) 'empty))

(run-tests)
