; conditions-cl.lisp -- the same ideas in Common Lisp style (lib/cl.lisp; Phase 7.7)

(require 'cl)

; handler-case: unwind, then run the clause for the condition's type.
(defun safe-divide (a b)
  (handler-case (/ a b)
    (ZeroDivide (c) 'infinity)                ; a Smalltalk exception class
    (error (c) (list 'error (error-object-message c)))))
(display (list (safe-divide 10 2) (safe-divide 1 0) (safe-divide 1 'x)))
(newline)

; ignore-errors: nil instead of an error.
(display (list (ignore-errors (car 5)) (ignore-errors (+ 1 2))))
(newline)

; unwind-protect: the cleanup runs whether or not the body fails.
(defvar *log* nil)
(defun logged (thunk)
  (ignore-errors
    (unwind-protect (funcall thunk)
      (push 'cleaned-up *log*))))
(logged (lambda () 'fine))
(logged (lambda () (error "boom")))
(display *log*)
(newline)

; handler-bind: handlers run before unwinding; this one chooses a restart.
(defun parse-number (s)
  (let ((n [s asInteger]))
    (if (smalltalk-nil? n)
        (restart-case (error "not a number:" s)
          (use-value (v) v))
        n)))
(display (handler-bind ((error (lambda (c) (invoke-restart 'use-value -1))))
           (mapcar parse-number '("1" "two" "3"))))
(newline)
