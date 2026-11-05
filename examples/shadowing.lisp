;;; shadowing.lisp -- a program's names are its own (Phase 9 step 9.3; review C-14)
;;;
;;; Before Phase 9, two things went wrong: a local variable could not be named as
;;; a special form, and the derived forms (case, cond, do, ...) used whatever
;;; their helper names meant where they were used. Both are fixed: a binding
;;; always wins over a special form's name, and the derived forms are hygienic
;;; macros, whose names mean the global ones.

(define (show label x) (display label) (display " ") (write x) (newline))

;; A local named if is a variable like any other.
(show "((lambda (if) (if 1 2 3)) +) =" ((lambda (if) (if 1 2 3)) +))
(show "(let ((list vector)) (list 1 2)) =" (let ((list vector)) (list 1 2)))

;; case compares with the global memv, whatever memv means here.
(show "case with a local memv:"
      (let ((memv (lambda (key keys) #f)))
        (case 3 ((1 2 3) 'found) (else 'not-found))))

;; cond's expansion uses if, let and begin: local ones do not disturb it.
(show "cond with local if, let and begin:"
      (let ((if list) (let 1) (begin 2))
        (cond (#f 'first) ((> 2 1) 'second) (else 'third))))

;; do's loop has a name of its own, which a program's loop cannot be.
(show "do beside a variable named loop:"
      (let ((loop 'mine))
        (do ((i 0 (+ i 1)) (acc '() (cons i acc)))
            ((= i 3) (list acc loop)))))
