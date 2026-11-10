;;; pretty.lisp -- (pretty-string value [indent]) from lib/pretty.lisp
;;; (specs/22-lisp-expert-libraries.md R-4, AC-1): lists, dotted pairs, hash tables,
;;; vectors, strings, numbers, booleans and ()
(load "../../lib/test.lisp")
(require 'pretty)

(define-test "atoms"
  (check (pretty-string 42) "42")
  (check (pretty-string 2.5) "2.5")
  (check (pretty-string "s") "\"s\"")
  (check (pretty-string 'sym) "sym")
  (check (pretty-string #t) "#t")
  (check (pretty-string #f) "#f")
  (check (pretty-string '()) "()")
  (check (pretty-string #\a) "a"))

(define-test "lists, one element a line, and dotted pairs"
  (check (pretty-string '(1 2)) "(\n  1,\n  2\n)")
  (check (pretty-string '(a (b c))) "(\n  a,\n  (\n    b,\n    c\n  )\n)")
  (check (pretty-string '(a . b)) "(a . b)"))

(define-test "hash tables, keys sorted, nested ones indented"
  (let ((h (make-hash-table)))
    (hash-table-set! h "b" 2)
    (hash-table-set! h "a" '(1))
    (check (pretty-string h) "#hash(\n  \"a\": (\n    1\n  ),\n  \"b\": 2\n)"))
  (check (pretty-string (make-hash-table)) "#hash()"))

(define-test "vectors, and a starting indent"
  (check (pretty-string (vector 1 2)) "#(\n  1,\n  2\n)")
  (check (pretty-string (vector)) "#()")
  (check (pretty-string '(1) 4) "(\n      1\n    )"))

(define-test "JSON data from json-read prints readably, null as ()"
  (let ((v (json-read "{\"n\":null,\"xs\":[1,true]}")))
    (check (pretty-string v) "#hash(\n  \"n\": (),\n  \"xs\": #(\n    1,\n    #t\n  )\n)")))

(run-tests)
