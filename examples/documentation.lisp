;;; documentation.lisp -- documentation, kept with what it documents (Phase 10 step 10.1)
;;;
;;; Every built-in carries a documentation string: its call form on the first
;;; line, then what it does. (documentation 'name) reads it, for a procedure, a
;;; macro or a special form. Your own definitions keep theirs too: a body that
;;; starts with a string, with more after it, keeps the string as its
;;; documentation. The string is still an ordinary expression, so the definition
;;; means just what it would without it.

(display (documentation 'string-ref)) (newline)
(display (documentation 'if)) (newline)
(write (documentation-category 'string-ref)) (newline)

;; A documented procedure: the first line names its call, the rest says what it does.
(define (average . xs)
  "(average x ...)
The mean of the numbers, exact when they all are."
  (/ (apply + xs) (length xs)))

(display (documentation 'average)) (newline)
(write (average 1 2 3 4)) (newline)

;; A macro is documented the same way, with a string before its syntax-rules.
(define-syntax repeat
  "(repeat n body ...)
Runs the body n times."
  (syntax-rules ()
    ((_ n body ...) (let loop ((i 0)) (when (< i n) body ... (loop (+ i 1)))))))

(display (documentation 'repeat)) (newline)
(repeat 3 (display "hi "))
(newline)

;; A body that is only a string answers the string; it documents nothing.
(define (greeting) "hello")
(write (list (greeting) (documentation 'greeting))) (newline)
