;;; Unit tests, in cog-lisp, for the Phase 7.8 data types (lib/test.lisp).
(load "../../lib/test.lisp")

(define-test strings
  (check (string-append "cog" "-" "lisp") "cog-lisp")
  (check (substring "hello" 1 3) "el")
  (check (string-split "a,b,,c" #\,) '("a" "b" "" "c"))
  (check (string->number "ff" 16) 255)
  (check-false (string->number "nope"))
  (check-error (string-ref "abc" 9) "out of range")
  (check-error (string-set! "literal" 0 #\x) "immutable"))

(define-test characters
  (check (char->integer #\A) 65)
  (check (char-upcase #\q) #\Q)
  (check-true (char-alphabetic? #\z))
  (check (digit-value #\7) 7))

(define-test vectors
  (check (vector-map (lambda (x) (* x x)) #(1 2 3)) #(1 4 9))
  (check (vector->list #(1 2 3 4) 1 3) '(2 3))
  (check `#(0 ,(+ 1 1) ,@(list 3 4)) #(0 2 3 4))
  (check-error (vector-set! #(1 2) 0 9) "immutable"))

(define-test hash-tables
  (let ((t (make-hash-table)))
    (hash-table-set! t "k" 1)
    (hash-table-set! t '(a b) 2)
    (hash-table-update!/default t "k" (lambda (v) (+ v 10)) 0)
    (check (hash-table-ref t "k") 11)
    (check (hash-table-ref t (list 'a 'b)) 2)
    (check (hash-table-keys t) '("k" (a b)))
    (check-error (hash-table-ref t 'missing) "no key")))

(define-test string-ports
  (let ((p (open-input-string "(1 2) foo")))
    (check (read p) '(1 2))
    (check (read p) 'foo)
    (check-true (eof-object? (read p))))
  (check (with-output-to-string (lambda () (display "x") (write "y"))) "x\"y\""))

(run-tests)
