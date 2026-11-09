;;; Moved from ~/projects/lisp-expert (lib/cl-test.lisp) with lib/cl.lisp and
;;; lib/test.lisp, whose copies it tested (specs/lisp-expert-libraries.md).
;;; Changed: its load lines only.
;;; Tests for the Common Lisp compatibility layer in cl.lisp.
(load "../../lib/test.lisp")
(require 'cl)

(defun cl-test-add (a b) (+ a b))
(defun cl-test-rest (head &rest tail) (cons head tail))
(defmacro cl-test-twice (form) `(+ ,form ,form))
(define cl-test-a 0)
(define cl-test-b 0)
(define cl-test-sum 0)
(define cl-test-count 0)
(define cl-test-stack '(b c))
(define cl-test-handler-ran #f)
(define cl-test-cleaned #f)

(define-test cl-defun-and-defmacro
  (check (cl-test-add 2 5) 7)
  (check (cl-test-rest 'a 'b 'c) '(a b c))
  (check (cl-test-twice 6) 12))

(define-test cl-defvar-and-defparameter
  (check (macroexpand '(defvar cl-test-var 1)) '(define cl-test-var 1))
  (check (macroexpand '(defvar cl-test-uninitialized))
         '(define cl-test-uninitialized (quote ())))
  (check (macroexpand '(defparameter cl-test-parameter 9))
         '(define cl-test-parameter 9)))

(define-test cl-setq-progn-and-prog1
  (setq cl-test-a 0 cl-test-b 0)
  (check (setq cl-test-a 3 cl-test-b 8) 8)
  (check (list cl-test-a cl-test-b) '(3 8))
  (check (progn 1 2 3) 3)
  (check (prog1 'first (setq cl-test-a 11) 'ignored) 'first)
  (check cl-test-a 11)
  (check (prog1 'only) 'only))

(define-test cl-labels-and-flet
  (check
   (labels ((cl-test-even? (n)
              (if (= n 0) #t (cl-test-odd? (- n 1))))
            (cl-test-odd? (n)
              (if (= n 0) #f (cl-test-even? (- n 1)))))
     (list (cl-test-even? 8) (cl-test-odd? 7)))
   '(#t #t))
  (check (flet ((cl-test-local-double (n) (* n 2)))
           (cl-test-local-double 6))
         12))

(define-test cl-dolist-and-dotimes
  (setq cl-test-sum 0)
  (check (dolist (n '(1 2 3 4) 'finished)
           (setq cl-test-sum (+ cl-test-sum n)))
         'finished)
  (check cl-test-sum 10)
  (setq cl-test-count 0)
  (check (dotimes (i 4 'complete)
           (setq cl-test-count (+ cl-test-count 1)))
         'complete)
  (check cl-test-count 4)
  (check (dotimes (i 0 'empty) i) 'empty))

(define-test cl-list-functions-and-predicates
  (check (first '(a b c)) 'a)
  (check (second '(a b c)) 'b)
  (check (third '(a b c)) 'c)
  (check (rest '(a b c)) '(b c))
  (check (nthcdr 2 '(a b c d)) '(c d))
  (check (nth 2 '(a b c d)) 'c)
  (check (last '(a b c)) '(c))
  (check (last '(one)) '(one))
  (check-true (consp '(a)))
  (check-false (consp '()))
  (check-true (listp '()))
  (check-true (listp '(a . b)))
  (check (atom 'symbol) #t)
  (check (atom '(a)) #f)
  (check (null '()) #t)
  (check (eql 2 2) #t)
  (check (eq 'a 'a) #t)
  (check (equal '(a b) '(a b)) #t))

(define-test cl-numeric-predicates-and-functions
  (check (numberp 3) #t)
  (check (numberp 'x) #f)
  (check (symbolp 'x) #t)
  (check (zerop 0) #t)
  (check (plusp 2) #t)
  (check (minusp -2) #t)
  (check (evenp 8) #t)
  (check (oddp 7) #t)
  (check (1+ 4) 5)
  (check (1- 4) 3)
  (check (mapcar (lambda (n) (* n n)) '(1 2 3)) '(1 4 9))
  (check (funcall + 1 2 3) 6))

(define-test cl-push-and-pop
  (setq cl-test-stack '(b c))
  (push 'a cl-test-stack)
  (check cl-test-stack '(a b c))
  (check (pop cl-test-stack) 'a)
  (check cl-test-stack '(b c)))

(define-test cl-handler-case-and-ignore-errors
  (check (handler-case (+ 2 3) (error (condition) 'caught)) 5)
  (check (handler-case (car) (error (condition) 'caught)) 'caught)
  (check (handler-case (car) (LispArityError (condition) 'arity)) 'arity)
  (check (ignore-errors (+ 4 5)) 9)
  (check (ignore-errors (car)) nil))

(define-test cl-handler-bind-and-unwind-protect
  (setq cl-test-handler-ran #f)
  (check
   (handler-case
       (handler-bind ((error (lambda (condition) (setq cl-test-handler-ran #t))))
         (error "handler-bind probe"))
     (error (condition) 'caught))
   'caught)
  (check cl-test-handler-ran #t)
  (setq cl-test-cleaned #f)
  (check
   (guard (condition (#t 'caught))
     (unwind-protect (error "cleanup probe") (setq cl-test-cleaned #t)))
   'caught)
  (check cl-test-cleaned #t))

(run-tests)
