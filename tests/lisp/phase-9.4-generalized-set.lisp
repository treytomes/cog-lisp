;;; phase-9.4-generalized-set.lisp -- set! of a place, as SRFI 17 specifies, and
;;; Common Lisp's setf (specs/phase-9-language.md step 9.4, AC-4; issue #5)
(load "../../lib/test.lisp")

;;; 9.4a: generalized set!

(define-test "AC-4 issue #5: (set! (car x) 'n) sets the first element"
  (let ((x (list 'a 'b 'c)))
    (set! (car x) 'n)
    (check x '(n b c))))

(define-test "AC-4 each built-in getter has its setter"
  (let ((p (list 1 2 3)) (v (vector 1 2 3)) (s (string-copy "cat")) (h (make-hash-table)))
    (set! (cdr p) '(9))
    (check p '(1 9))
    (set! (vector-ref v 2) 'x)                   ; the issue's title: array assignment
    (check v (vector 1 2 'x))
    (set! (string-ref s 0) #\b)
    (check s "bat")
    (set! (hash-table-ref h "k") 1)
    (check (hash-table-ref h "k") 1)
    (set! (hash-table-ref/default h "n" 0) (+ 1 (hash-table-ref/default h "n" 0)))
    (set! (hash-table-ref/default h "n" 0) (+ 1 (hash-table-ref/default h "n" 0)))
    (check (hash-table-ref h "n") 2)
    (check (setter car) set-car!)
    (check (setter vector-ref) vector-set!)))

(define-test "AC-4 a program adds a setter with (set! (setter f) g)"
  (define (middle p) (car (cdr p)))
  (set! (setter middle) (lambda (p v) (set-car! (cdr p) v)))
  (let ((p (list 1 2 3)))
    (set! (middle p) 'm)
    (check p '(1 m 3))
    (check (middle p) 'm)))

(define-test "AC-4 the procedure, its arguments and the value are evaluated once each, in order"
  (let* ((log '())
         (note (lambda (what v) (set! log (cons what log)) v))
         (p (list 1 2)))
    (set! ((note 'proc car) (note 'arg p)) (note 'value 9))
    (check (reverse log) '(proc arg value))
    (check p '(9 2))))

(define-test "AC-4 the getter is evaluated where the set! is: a local car is that local procedure"
  (let ((q (list 1 2)))
    (let ((car cdr))                             ; so (setter car) here is set-cdr!
      (set! (car q) '(z)))
    (check q '(1 z))))

(define-test "AC-4 a local named setter does not change what set! does"
  (let ((q (list 1 2)))
    (let ((setter (lambda (proc) (lambda args 'captured))))
      (set! (car q) 5))
    (check q '(5 2))))

(define-syntax set-first!
  (syntax-rules () ((_ l v) (set! (car l) v))))

(define-test "AC-4 a syntax-rules macro that expands to set! of a place, hygienically"
  (let ((q (list 1 2)))
    (set-first! q 7)
    (check q '(7 2))
    (let ((car cdr))                             ; the macro's car is still the global car
      (set-first! q 8))
    (check q '(8 2))))

(define-test "AC-4 the errors: no setter, and a target that is not a variable or a call"
  (check-error (set! (length (list 1)) 3) "setter: no setter for")
  (check-error (setter length) "setter: no setter for")
  (check-error (eval '(set! 5 1)) "set!: bad name: 5")
  (check-error (eval '(set! "s" 1)) "set!: bad name")
  (check-error (eval '(set! (car) 1 2)) "set!"))

(define-test "AC-4 set! of a place answers nothing in particular, as set! of a name does"
  (let ((p (list 1)))
    (check-true (begin (set! (car p) 2) #t))
    (check p '(2))))

;;; 9.4a: setf, in lib/cl.lisp

(load "../../lib/cl.lisp")

(defparameter cl-x 0)
(defvar cl-a 0)
(defvar cl-b 0)

(define-test "AC-4 issue #5 as typed: defparameter, setf, then set! of (car x)"
  (setf cl-x (list 'a 'b 'c))
  (set! (car cl-x) 'n)
  (check cl-x '(n b c)))

(define-test "AC-4 setf assigns variables and places, in pairs, and answers the last value"
  (check (setf cl-a 1 cl-b 2) 2)
  (check (list cl-a cl-b) '(1 2))
  (let ((p (list 1 2)) (v (vector 0 0)))
    (check (setf (car p) 'x (vector-ref v 1) 'y) 'y)
    (check p '(x 2))
    (check v (vector 0 'y)))
  (check (setf) '()))

(define-test "AC-4 setf evaluates each value once, after its place's arguments"
  (let* ((log '())
         (note (lambda (what v) (set! log (cons what log)) v))
         (p (list 1 2)))
    (setf (car (note 'arg p)) (note 'value 5))
    (check (reverse log) '(arg value))
    (check p '(5 2))))

(define-test "AC-4 push and pop work on places"
  (let ((z (list (list 1))))
    (push 0 (car z))
    (check z '((0 1)))
    (check (pop (car z)) 0)
    (check z '((1)))))

(run-tests)
