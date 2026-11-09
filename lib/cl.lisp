;;; cl.lisp -- Common Lisp names for cog-lisp (specs/phase-7-macros.md section 8)
;;;
;;; Load with (load "lib/cl.lisp"), for working through ANSI Common Lisp.
;;; cog-lisp stays a Scheme-like LISP underneath; this file adds CL names as
;;; macros and procedures on top of it.
;;;
;;; Known gaps -- things that work differently from Common Lisp:
;;;   - nil and () are TRUE here; only #f is false. Test a list for emptiness with
;;;     (null x) or (consp x), never with plain (if x ...).
;;;   - t is a variable bound to #t, and nil one bound to (). (cond (t ...)) works.
;;;   - One namespace: a variable and a function cannot share a name, and there
;;;     is no #'f (just write f) and no funcall requirement (funcall is provided).
;;;   - Parameter lists support &rest only: no &optional, &key, or &aux.
;;;   - defvar always assigns (no "only if unbound" rule).
;;;   - setq on a name that was never defined is an error; defvar it first.
;;;   - setf assigns variables and places through set!'s setters (SRFI 17), found
;;;     at run time; push and pop evaluate a place's arguments twice.
;;;   - Not provided: loop, format, keywords, multiple values, &optional, &key.

(define t #t)
(define nil '())

;; (a b &rest r) -> (a b . r), for define and define-macro
(define (%cl-params ps)
  (cond ((null? ps) '())
        ((eq? (car ps) '&rest) (car (cdr ps)))
        (else (cons (car ps) (%cl-params (cdr ps))))))

;;; definitions

(define-macro (defun name params . body)
  `(define (,name . ,(%cl-params params)) ,@body))

(define-macro (defmacro name params . body)
  `(define-macro (,name . ,(%cl-params params)) ,@body))

(define-macro (defvar name . value)
  `(define ,name ,(if (null? value) ''() (car value))))

(define-macro (defparameter name value)
  `(define ,name ,value))

;;; assignment and sequencing

;; (setq a 1 b 2) sets each in turn and returns the last value
(define-macro (setq . pairs)
  (cond ((null? pairs) ''())
        ((null? (cdr (cdr pairs)))
         `(begin (set! ,(car pairs) ,(car (cdr pairs))) ,(car pairs)))
        (else
         `(begin (set! ,(car pairs) ,(car (cdr pairs)))
                 (setq ,@(cdr (cdr pairs)))))))

;; (setf place value ...) -- each place a variable or a call such as (car x),
;; assigned with the generalized set! (specs/phase-9-language.md step 9.4); the
;; place's arguments are evaluated before its value, each once, and setf
;; answers the last value
(define-macro (setf . pairs)
  "(setf place value ...)
Assigns each value to its place, in turn: a variable, or a call such as (car x) or (vector-ref v i), which goes through its setter. Answers the last value."
  (if (null? pairs)
      ''()
      (let ((g (gensym)))
        `(let ((,g #f))
           (set! ,(car pairs) (begin (set! ,g ,(car (cdr pairs))) ,g))
           ,(if (null? (cdr (cdr pairs))) g `(setf ,@(cdr (cdr pairs))))))))

(define-macro (progn . body)
  `(begin ,@body))

(define-macro (prog1 first . rest)
  (let ((g (gensym)))
    `(let ((,g ,first)) ,@rest ,g)))

;;; local functions

;; (labels ((f (x) ...) ...) body ...) -- may call each other
(define-macro (labels defs . body)
  `(let ()
     ,@(map (lambda (d)
              `(define (,(car d) . ,(%cl-params (car (cdr d)))) ,@(cdr (cdr d))))
            defs)
     (let () ,@body)))

;; (flet ((f (x) ...) ...) body ...) -- not visible to each other
(define-macro (flet defs . body)
  `(let ,(map (lambda (d)
                `(,(car d) (lambda ,(%cl-params (car (cdr d))) ,@(cdr (cdr d)))))
              defs)
     ,@body))

;;; iteration

;; (dolist (x list [result]) body ...)
(define-macro (dolist spec . body)
  (let ((loop (gensym))
        (rest (gensym)))
    `(let ,loop ((,rest ,(car (cdr spec))))
       (if (null? ,rest)
           ,(if (null? (cdr (cdr spec))) ''() (car (cdr (cdr spec))))
           (let ((,(car spec) (car ,rest)))
             ,@body
             (,loop (cdr ,rest)))))))

;; (dotimes (i n [result]) body ...) -- i runs from 0 below n
(define-macro (dotimes spec . body)
  (let ((loop (gensym))
        (limit (gensym)))
    `(let ((,limit ,(car (cdr spec))))
       (let ,loop ((,(car spec) 0))
         (if (>= ,(car spec) ,limit)
             ,(if (null? (cdr (cdr spec))) ''() (car (cdr (cdr spec))))
             (begin ,@body
                    (,loop (+ ,(car spec) 1))))))))

;;; lists and predicates

(define (first x) (car x))
(define (second x) (car (cdr x)))
(define (third x) (car (cdr (cdr x))))
(define (rest x) (cdr x))
(define (nthcdr n lst) (if (= n 0) lst (nthcdr (- n 1) (cdr lst))))
(define (nth n lst) (car (nthcdr n lst)))
(define (last lst) (if (null? (cdr lst)) lst (last (cdr lst))))   ; the last cons
(define (consp x) (pair? x))
(define (listp x) (or (pair? x) (null? x)))
(define (atom x) (not (pair? x)))
(define (null x) (null? x))
(define (eql a b) (eqv? a b))
(define (eq a b) (eq? a b))
(define (equal a b) (equal? a b))
(define (numberp x) (number? x))
(define (symbolp x) (symbol? x))
(define (zerop x) (= x 0))
(define (plusp x) (> x 0))
(define (minusp x) (< x 0))
(define (evenp x) (= (modulo x 2) 0))
(define (oddp x) (= (modulo x 2) 1))
(define (1+ x) (+ x 1))
(define (1- x) (- x 1))
(define (mapcar f lst) (map f lst))
(define (funcall f . args) (apply f args))

(define-macro (push x place)
  `(set! ,place (cons ,x ,place)))

(define-macro (pop place)
  (let ((g (gensym)))
    `(let ((,g (car ,place)))
       (set! ,place (cdr ,place))
       ,g)))

;;; conditions (specs/phase-7.7-conditions-restarts.md section 2)
;;; A condition type is error, condition or t, or the name of a Smalltalk
;;; exception class such as ZeroDivide. restart-case and invoke-restart are core.

(define (%cl-type-match? type c)
  (cond ((memq type '(t condition)) #t)
        ((eq? type 'error) (error-object? c))
        (else (let ((cls (smalltalk-global type)))
                (and cls (condition? c) [c isKindOf: cls])))))

;; (handler-case form (type (var) body ...) ...) -- unwinds, then runs the clause
(define-macro (handler-case form . clauses)
  (let ((c (gensym)))
    `(guard (,c ,@(map (lambda (cl)
                         `((%cl-type-match? ',(car cl) ,c)
                           (let ,(if (null? (car (cdr cl))) '() `((,(car (car (cdr cl))) ,c)))
                             ,@(cdr (cdr cl)))))
                       clauses))
       ,form)))

;; (handler-bind ((type handler) ...) body ...) -- handlers run before unwinding;
;; one that returns declines, and the search goes on
(define-macro (handler-bind bindings . body)
  (if (null? bindings)
      `(progn ,@body)
      (let ((c (gensym)))
        `(%handler-bind
           (lambda (,c) (when (%cl-type-match? ',(car (car bindings)) ,c)
                          (,(car (cdr (car bindings))) ,c)))
           (lambda () (handler-bind ,(cdr bindings) ,@body))))))

;; (ignore-errors form ...) -- nil when an error is signalled
(define-macro (ignore-errors . body)
  (let ((c (gensym)))
    `(guard (,c ((error-object? ,c) nil)) ,@body)))

;; (unwind-protect protected cleanup ...)
(define-macro (unwind-protect protected . cleanup)
  `(dynamic-wind (lambda () #f) (lambda () ,protected) (lambda () ,@cleanup)))
