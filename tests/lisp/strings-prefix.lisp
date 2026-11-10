;;; strings-prefix.lisp -- string-prefix? and string-suffix?, SRFI 13's argument
;;; order (specs/23-lisp-expert-review.md R-2, AC-1)
(load "../../lib/test.lisp")

(define-test "string-prefix?"
  (check (string-prefix? "has-" "has-temperature") #t)
  (check (string-prefix? "has-" "ha") #f)
  (check (string-prefix? "" "anything") #t)
  (check (string-prefix? "x" "") #f)
  (check (string-prefix? "abc" "abc") #t)
  (check (string-prefix? "λ" "λx") #t))

(define-test "string-suffix?"
  (check (string-suffix? ".lisp" "main.lisp") #t)
  (check (string-suffix? ".lisp" "lisp") #f)
  (check (string-suffix? "" "x") #t)
  (check (string-suffix? "abc" "abc") #t)
  (check (string-suffix? "b" "ab") #t))

(define-test "documented"
  (check-true (string? (documentation 'string-prefix?)))
  (check-true (string? (documentation 'string-suffix?))))

(run-tests)
