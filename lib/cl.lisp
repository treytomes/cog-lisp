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
;;;     at run time; push and pop evaluate a place's arguments twice. defsetf
;;;     gives a function a setter; define-setf-expander is not provided.
;;;   - gethash answers only the value, not whether the key was there (use
;;;     hash-table-contains?); aref takes one index.
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

;; (defsetf access update) -- (setf (access arg ...) v) calls (update arg ... v)
;; (defsetf access (param ...) (store) body ...) -- runs body with the params bound
;; to the arguments and store to the value; params take &rest
;; Both define access's setter (specs/phase-9-language.md step 9.4b).
(define (%cl-last-of lst) (if (null? (cdr lst)) (car lst) (%cl-last-of (cdr lst))))
(define (%cl-all-but-last lst) (if (null? (cdr lst)) '() (cons (car lst) (%cl-all-but-last (cdr lst)))))

(define-macro (defsetf access . spec)
  "(defsetf access update), (defsetf access (param ...) (store) body ...)
Gives access a setter, so (setf (access arg ...) v) works: the short form calls (update arg ... v); the long form runs the body with each param bound to its argument and store to v. Answers the name access."
  (if (null? (cdr spec))
      `(begin (set! (setter ,access) ,(car spec)) ',access)
      (let ((params (car spec))
            (store (car (car (cdr spec))))
            (body (cdr (cdr spec)))
            (args (gensym)))
        `(begin
           (set! (setter ,access)
                 (lambda ,args
                   (let ((,store (%cl-last-of ,args)))
                     (apply (lambda ,(%cl-params params) ,@body) (%cl-all-but-last ,args)))))
           ',access))))

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

;; the accessors' setters, for setf (specs/phase-9-language.md step 9.4b)
(set! (setter first) (lambda (x v) (set-car! x v)))
(set! (setter second) (lambda (x v) (set-car! (cdr x) v)))
(set! (setter third) (lambda (x v) (set-car! (cdr (cdr x)) v)))
(set! (setter rest) (lambda (x v) (set-cdr! x v)))
(set! (setter nth) (lambda (n lst v) (set-car! (nthcdr n lst) v)))

;; (aref vector index): cog-lisp's vectors have one dimension
(define (aref v . indexes)
  (if (and (pair? indexes) (null? (cdr indexes)))
      (vector-ref v (car indexes))
      (error "aref: cog-lisp's vectors have one dimension: give one index")))
(set! (setter aref)
      (lambda (v . indexes-and-value)
        (if (= (length indexes-and-value) 2)
            (vector-set! v (car indexes-and-value) (car (cdr indexes-and-value)))
            (error "aref: cog-lisp's vectors have one dimension: give one index"))))

;; (gethash key table [default]): the value, or default (else nil). Only the value:
;; cog-lisp's multiple values do not shrink to one, so a second value would break
;; (+ 1 (gethash k h 0)). Test for a key with (hash-table-contains? table key).
(define (gethash key table . default)
  (hash-table-ref/default table key (if (null? default) '() (car default))))
(set! (setter gethash)
      (lambda (key table . default-and-value)
        (hash-table-set! table key (%cl-last-of default-and-value))))
(define (remhash key table)
  (let ((had (hash-table-contains? table key)))
    (hash-table-delete! table key)
    had))
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
