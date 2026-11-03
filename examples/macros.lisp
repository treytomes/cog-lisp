; macros.lisp -- extending the language with define-macro

; (while test body ...) -- a loop that cog-lisp does not have built in.
; The loop's own name comes from gensym, so it can never clash with a
; variable in the code the macro is used on.
(define-macro (while test . body)
  (let ((loop (gensym)))
    `(let ,loop ()
       (when ,test
         ,@body
         (,loop)))))

(define i 0)
(define total 0)
(while (< i 5)
  (set! total (+ total i))
  (set! i (+ i 1)))
(display "sum of 0..4 is ")
(display total)
(newline)

; a user variable named loop is not captured by the macro's loop
(define loop 3)
(while (> loop 0)
  (display loop)
  (display " ")
  (set! loop (- loop 1)))
(newline)

; macroexpand shows the code a macro call becomes
(display (macroexpand '(when (> x 0) (display x) x)))
(newline)

; quasiquote builds code and data alike
(define (make-adder-form n) `(lambda (x) (+ x ,n)))
(display (make-adder-form 10))
(newline)
(display ((eval (make-adder-form 10)) 5))
(newline)

; the derived forms are macros too, written in cog-lisp itself
(define (classify n)
  (cond ((< n 0) 'negative)
        ((= n 0) 'zero)
        (else (case (modulo n 2)
                ((0) 'even)
                (else 'odd)))))
(display (map classify '(-2 0 3 8)))
(newline)
