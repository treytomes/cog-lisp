;;; cl.lisp -- Common Lisp names for cog-lisp (specs/phase-7-macros.md section 8)
;;;
;;; Load with (require 'cl), from any folder (specs/library-path.md), for
;;; working through ANSI Common Lisp.
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
;;;   - remove takes an item, as in Common Lisp: it shadows cog-lisp's own remove,
;;;     which takes a test (SRFI 1), while this file is loaded.
;;;   - format is cog-lisp's own, built in, with Common Lisp's directives.
;;;   - Not provided: loop, keywords, Common Lisp's multiple values, &optional, &key.

(define t #t)
(define nil '())

;; (a b &rest r) -> (a b . r), for define and define-macro
(define (%cl-params ps)
  "(%cl-params ps)\nNormalizes a parameter list for Common Lisp style functions."
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

(define (first x)
  "(first x)\nReturns the first element of a list."
  (car x))
(define (second x)
  "(second x)\nReturns the second element of a list."
  (car (cdr x)))
(define (third x)
  "(third x)\nReturns the third element of a list."
  (car (cdr (cdr x))))
(define (rest x)
  "(rest x)\nReturns the list after its first element."
  (cdr x))
(define (nthcdr n lst)
  "(nthcdr n lst)\nReturns the tail reached after dropping n elements."
  (if (= n 0) lst (nthcdr (- n 1) (cdr lst))))
(define (nth n lst)
  "(nth n lst)\nReturns the element at zero-based index n."
  (car (nthcdr n lst)))
(define (last lst)
  "(last lst)\nReturns the final cons cell of a non-empty list."
  (if (null? (cdr lst)) lst (last (cdr lst))))   ; the last cons

;; the accessors' setters, for setf (specs/phase-9-language.md step 9.4b)
(set! (setter first) (lambda (x v) (set-car! x v)))
(set! (setter second) (lambda (x v) (set-car! (cdr x) v)))
(set! (setter third) (lambda (x v) (set-car! (cdr (cdr x)) v)))
(set! (setter rest) (lambda (x v) (set-cdr! x v)))
(set! (setter nth) (lambda (n lst v) (set-car! (nthcdr n lst) v)))

;; fourth to tenth, with their setters (specs/lisp-expert-libraries.md R-2)
(define (fourth x) "(fourth list)\nThe fourth element of list." (nth 3 x))
(define (fifth x) "(fifth list)\nThe fifth element of list." (nth 4 x))
(define (sixth x) "(sixth list)\nThe sixth element of list." (nth 5 x))
(define (seventh x) "(seventh list)\nThe seventh element of list." (nth 6 x))
(define (eighth x) "(eighth list)\nThe eighth element of list." (nth 7 x))
(define (ninth x) "(ninth list)\nThe ninth element of list." (nth 8 x))
(define (tenth x) "(tenth list)\nThe tenth element of list." (nth 9 x))
(set! (setter fourth) (lambda (x v) (set-car! (nthcdr 3 x) v)))
(set! (setter fifth) (lambda (x v) (set-car! (nthcdr 4 x) v)))
(set! (setter sixth) (lambda (x v) (set-car! (nthcdr 5 x) v)))
(set! (setter seventh) (lambda (x v) (set-car! (nthcdr 6 x) v)))
(set! (setter eighth) (lambda (x v) (set-car! (nthcdr 7 x) v)))
(set! (setter ninth) (lambda (x v) (set-car! (nthcdr 8 x) v)))
(set! (setter tenth) (lambda (x v) (set-car! (nthcdr 9 x) v)))

;; (boundp symbol): does the global environment bind it?
(define (boundp symbol)
  "(boundp symbol)
True if the global environment binds symbol; an error if it is not a symbol."
  (if (not (symbol? symbol)) (error (string-append "boundp: not a symbol: " (with-output-to-string (lambda () (write symbol))))))
  [[(smalltalk LispEnvironment) default] isBound: symbol])

;; Common Lisp's remove and delete take an item, not a test: they shadow SRFI 1's
;; remove (built in) while this file is loaded
(define (remove item lst)
  "(remove item list)
list without the elements eql to item (Common Lisp's; cog-lisp's own remove takes a test, as SRFI 1's does)."
  (filter (lambda (x) (not (eqv? x item))) lst))
(define (remove-if test lst)
  "(remove-if test list)
list without the elements for which test is true."
  (filter (lambda (x) (not (test x))) lst))
(define (remove-duplicates lst)
  "(remove-duplicates list)
list without its repeated elements (eql), the first of each kept."
  (delete-duplicates lst eqv?))

;; (string-capitalize string): each word capitalized, the rest lower case
(define (string-capitalize s)
  "(string-capitalize string)
string with each word capitalized and the rest of it in lower case."
  (let ((out (open-output-string)))
    (let loop ((i 0) (in-word #f))
      (if (< i (string-length s))
          (let ((c (string-ref s i)))
            (if (or (char-alphabetic? c) (char-numeric? c))
                (begin (write-char (if in-word (char-downcase c) (char-upcase c)) out) (loop (+ i 1) #t))
                (begin (write-char c out) (loop (+ i 1) #f))))
          (get-output-string out)))))

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
(define (consp x)
  "(consp x)\nTests whether a value is a pair."
  (pair? x))
(define (listp x)
  "(listp x)\nTests whether a value is a list."
  (or (pair? x) (null? x)))
(define (atom x)
  "(atom x)\nTests whether a value is not a pair."
  (not (pair? x)))
(define (null x)
  "(null x)\nTests whether a value is the empty list."
  (null? x))
(define (eql a b)
  "(eql a b)\nCompares values using eqv? semantics."
  (eqv? a b))
(define (eq a b)
  "(eq a b)\nCompares values using eq? semantics."
  (eq? a b))
(define (equal a b)
  "(equal a b)\nCompares values structurally."
  (equal? a b))
(define (numberp x)
  "(numberp x)\nTests whether a value is numeric."
  (number? x))
(define (symbolp x)
  "(symbolp x)\nTests whether a value is a symbol."
  (symbol? x))
(define (zerop x)
  "(zerop x)\nTests whether a number is zero."
  (= x 0))
(define (plusp x)
  "(plusp x)\nTests whether a number is positive."
  (> x 0))
(define (minusp x)
  "(minusp x)\nTests whether a number is negative."
  (< x 0))
(define (evenp x)
  "(evenp x)\nTests whether an integer is even."
  (= (modulo x 2) 0))
(define (oddp x)
  "(oddp x)\nTests whether an integer is odd."
  (= (modulo x 2) 1))
(define (1+ x)
  "(1+ x)\nReturns a number incremented by one."
  (+ x 1))
(define (1- x)
  "(1- x)\nReturns a number decremented by one."
  (- x 1))
(define (mapcar f lst)
  "(mapcar f lst)\nMaps a function over a list and returns the results."
  (map f lst))
(define (funcall f . args)
  "(funcall f args ...)\nCalls a function with the supplied arguments."
  (apply f args))

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
  "(%cl-type-match? type c)\nTests whether a value matches a Common Lisp type specifier."
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
