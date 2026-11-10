;;; phase-9.4-generalized-set.lisp -- set! of a place, as SRFI 17 specifies, and
;;; Common Lisp's setf (specs/15-phase-9-language.md step 9.4, AC-4; issue #5)
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

;;; 9.4b: getter-with-setter, defsetf, the Common Lisp accessors' setters

(define-test "AC-4 getter-with-setter: a getter that has a setter, the getter itself untouched"
  (let* ((cell (list 1))
         (get (lambda (c) (car c)))
         (both (getter-with-setter get (lambda (c v) (set-car! c v)))))
    (check (both cell) 1)
    (set! (both cell) 2)
    (check cell '(2))
    (check-error (setter get) "setter: no setter for")
    (check (procedure-documentation (getter-with-setter car set-car!)) (procedure-documentation car))))

(define (pair-x p) (car p))
(define (set-pair-x! p v) (set-car! p v))
(defsetf pair-x set-pair-x!)
(define (grid-at g row col) (vector-ref (vector-ref g row) col))
(defsetf grid-at (g row col) (new) (vector-set! (vector-ref g row) col new) new)
(define (sum-at v . is) (apply + (map (lambda (i) (vector-ref v i)) is)))
(defsetf sum-at (v &rest is) (new) (for-each (lambda (i) (vector-set! v i new)) is))

(define-test "AC-4 defsetf: the short form, and the long form with and without &rest"
  (let ((p (list 1 2)))
    (setf (pair-x p) 'x)
    (check p '(x 2)))
  (let ((g (vector (vector 0 0) (vector 0 0))))
    (check (setf (grid-at g 1 0) 7) 7)
    (check (grid-at g 1 0) 7)
    (check g (vector (vector 0 0) (vector 7 0))))
  (let ((v (vector 0 0 0)))
    (setf (sum-at v 0 2) 5)
    (check v (vector 5 0 5))
    (check (sum-at v 0 1 2) 10))
  (check (defsetf pair-x set-pair-x!) 'pair-x))

(define-test "AC-4 setf of first, second, third, rest and nth"
  (let ((l (list 1 2 3 4)))
    (setf (first l) 'a (second l) 'b (third l) 'c)
    (check l '(a b c 4))
    (setf (nth 3 l) 'd)
    (check l '(a b c d))
    (setf (rest l) '(z))
    (check l '(a z))))

(define-test "AC-4 aref, with one index, and its setf"
  (let ((v (vector 1 2 3)))
    (check (aref v 1) 2)
    (setf (aref v 1) 'two)
    (check v (vector 1 'two 3))
    (check-error (aref v 0 0) "one dimension")
    (check-error (setf (aref v 0 0) 1) "one dimension")))

(define-test "AC-4 gethash, remhash, and setf of gethash, in Common Lisp's argument order"
  (let ((h (make-hash-table)))
    (check (gethash "k" h) '())
    (check (gethash "k" h 0) 0)
    (setf (gethash "k" h) 1)
    (check (gethash "k" h) 1)
    (setf (gethash "n" h 0) (+ 1 (gethash "n" h 0)))      ; a counter: one value, so + works
    (setf (gethash "n" h 0) (+ 1 (gethash "n" h 0)))
    (check (gethash "n" h) 2)
    (check (remhash "k" h) #t)
    (check (remhash "k" h) #f)
    (check (hash-table-contains? h "k") #f)))

;;; 9.4b: the compile-time shortcut for the built-in getters

(define (shortcut-set-car q v) (set! (car q) v))   ; compiled while car is the built-in car

(define-test "AC-4 the shortcut: a set! compiled for the built-in car follows a redefined car"
  (let ((q (list 1 2)) (built-in-car car))
    (shortcut-set-car q 'a)
    (check q '(a 2))
    (set! car (getter-with-setter (lambda (p) (built-in-car p)) (lambda (p v) (set-cdr! p (list v)))))
    (shortcut-set-car q 'b)                          ; now car's setter is the program's
    (set! car built-in-car)
    (check q '(a b))
    (shortcut-set-car q 'c)
    (check q '(c b))))

(define-test "AC-4 the shortcut's cost: a built-in getter's setter cannot be changed"
  (check-error (set! (setter car) (lambda (p v) #f)) "setter: the setter of car is built in")
  (check-error (set! (setter vector-ref) (lambda (v i x) #f)) "is built in")
  (let ((p (list 1)))
    (set! (car p) 2)
    (check p '(2))))

(run-tests)
