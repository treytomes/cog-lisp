;;; json.lisp -- json-read and json-write (specs/https-and-json.md R-3, AC-2):
;;; the table of R-3 both ways, null kept apart from false and from an empty array,
;;; nesting, Unicode, numbers, and the errors.
(load "../../lib/test.lisp")

(define (round-trip text) (with-output-to-string (lambda () (json-write (json-read text)))))

(define-test "R-3 reading: objects, arrays, strings, numbers, true, false, null"
  (let ((v (json-read "{\"s\":\"x\",\"n\":42,\"f\":2.5,\"t\":true,\"no\":false,\"z\":null,\"a\":[1,[2]],\"e\":[],\"o\":{}}")))
    (check-true (hash-table? v))
    (check (hash-table-ref v "s") "x")
    (check (hash-table-ref v "n") 42)
    (check (hash-table-ref v "f") 2.5)
    (check (hash-table-ref v "t") #t)
    (check (hash-table-ref v "no") #f)
    (check (hash-table-ref v "z") '())
    (check (hash-table-ref v "a") (vector 1 (vector 2)))
    (check (hash-table-ref v "e") (vector))
    (check-true (hash-table? (hash-table-ref v "o")))
    (check (hash-table-count (hash-table-ref v "o")) 0)))

(define-test "null, false and an empty array stay apart"
  (let ((v (json-read "[null,false,[]]")))
    (check-true (null? (vector-ref v 0)))
    (check (vector-ref v 1) #f)
    (check-false (null? (vector-ref v 2)))
    (check (vector-ref v 2) (vector))))

(define-test "R-3 writing, keys sorted"
  (let ((t (make-hash-table)))
    (hash-table-set! t "b" (vector 1 2.5 '() #t #f))
    (hash-table-set! t "a" "x")
    (check (with-output-to-string (lambda () (json-write t))) "{\"a\":\"x\",\"b\":[1,2.5,null,true,false]}"))
  (check (with-output-to-string (lambda () (json-write (vector)))) "[]")
  (check (with-output-to-string (lambda () (json-write 1/2))) "0.5")
  (check (let ((p (open-output-string))) (json-write '() p) (get-output-string p)) "null"))

(define-test "strings: escapes and Unicode, both ways"
  (check (with-output-to-string (lambda () (json-write "q\"b\\s\nn\tt")))
         "\"q\\\"b\\\\s\\nn\\tt\"")
  (check (with-output-to-string (lambda () (json-write (string (integer->char 1)))))
         "\"\\u0001\"")
  (check (json-read "\"caf\\u00e9 \\\"q\\\"\"") "café \"q\"")
  (check (json-read "\"λ\"") "λ"))

(define-test "AC-2 a round trip writes back the same text, nesting included"
  (check (round-trip "{\"a\":[1,{\"b\":null}],\"c\":\"é\",\"d\":false,\"e\":-3,\"f\":0.25}")
         "{\"a\":[1,{\"b\":null}],\"c\":\"é\",\"d\":false,\"e\":-3,\"f\":0.25}"))

(define-test "the errors"
  (check-error (json-read "{bad") "json-read:")
  (check-error (json-read 5) "json-read: not a string")
  (check-error (json-write (list 1 2)) "json-write: no JSON for")
  (check-error (json-write 'sym) "json-write: no JSON for")
  (check-error (json-write +inf.0) "not a JSON number")
  (let ((t (make-hash-table)))
    (hash-table-set! t 1 2)
    (check-error (json-write t) "an object key is not a string")
    ;; an error writes nothing
    (check (let ((p (open-output-string)))
             (guard (e (#t #f)) (json-write (vector 1 (list 2)) p))
             (get-output-string p))
           "")))

(define-test "json-read and json-write are documented"
  (check-true (string? (documentation 'json-read)))
  (check-true (string? (documentation 'json-write))))

(run-tests)
