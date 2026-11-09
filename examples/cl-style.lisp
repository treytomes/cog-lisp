; cl-style.lisp -- Common Lisp style, with lib/cl.lisp loaded.
; In the manner of an introductory CL text's early chapters; written for
; cog-lisp. Remember: nil is true here, so test lists with null or consp.

(require 'cl)

(defun our-length (lst)
  (if (null lst)
      0
      (+ (our-length (cdr lst)) 1)))

(defun our-member (obj lst)
  (cond ((null lst) nil)
        ((eql (car lst) obj) lst)
        (t (our-member obj (cdr lst)))))

(defun show-squares (start end)
  (dotimes (k (- (+ end 1) start))
    (let ((i (+ start k)))
      (display (list i (* i i)))
      (display " ")))
  (newline))

(defvar *items* '(a b c d))

(display (our-length *items*))
(newline)
(display (our-member 'c *items*))
(newline)
(show-squares 2 5)

; iteration over a list, accumulating with push
(let ((acc nil))
  (dolist (x *items*)
    (push x acc))
  (display acc)
  (newline))

; local functions with labels, and functions as values with funcall
(defun count-leaves (tree)
  (labels ((walk (x)
             (cond ((null x) 0)
                   ((atom x) 1)
                   (t (+ (walk (car x)) (walk (cdr x)))))))
    (walk tree)))
(display (count-leaves '((a b) (c (d e)) f)))
(newline)
(display (funcall (lambda (x y) (* x y)) 6 7))
(newline)
(display (mapcar (lambda (x) (* 10 x)) '(1 2 3)))
(newline)

; a macro with defmacro and &rest
(defmacro my-unless (test &rest body)
  `(if ,test nil (progn ,@body)))
(display (my-unless (> 1 2) 'ran))
(newline)

; setf of places: a list's elements, and a hash table used as a counter
(let ((cells (list 'a 'b 'c))
      (counts (make-hash-table)))
  (setf (second cells) 'x
        (nth 2 cells) 'y)
  (dolist (w '(to be or not to be))
    (setf (gethash w counts) (+ 1 (gethash w counts 0))))
  (display (list cells (gethash 'to counts) (gethash 'or counts)))
  (newline))

; the procedure keeps the text it was written as
(display (procedure-source our-length))
(newline)
