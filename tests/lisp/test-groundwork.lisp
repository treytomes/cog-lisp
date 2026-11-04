;;; Unit tests, in cog-lisp, for Phase 7.9: cycles, escapes, files, big code.
(load "../../lib/test.lisp")

(define (circular . xs) (let ((l (apply list xs))) (set-cdr! (last-pair l) l) l))
(define (last-pair l) (if (pair? (cdr l)) (last-pair (cdr l)) l))

(define-test cycles
  (check-true (equal? (circular 1 2) (circular 1 2)))
  (check-false (equal? (circular 1 2) (circular 1 3)))
  (check (with-output-to-string (lambda () (write (circular 1 2)))) "#0=(1 2 . #0#)")
  (let ((back (read (open-input-string "#0=(a b . #0#)"))))
    (check (car back) 'a)
    (check-true (eq? back (cdr (cdr back))))))

(define-test escapes
  (check (string-length "\x3bb;") 1)
  (check (char->integer (string-ref "\x3bb;" 0)) 955)
  (check (with-output-to-string (lambda () (write (string (integer->char 1))))) "\"\\x1;\""))

(define-test files
  (call-with-output-file "unit-test.tmp" (lambda (p) (write '(1 "two") p) (newline p)))
  (check-true (file-exists? "unit-test.tmp"))
  (check (call-with-input-file "unit-test.tmp" read) '(1 "two"))
  (delete-file "unit-test.tmp")
  (check-false (file-exists? "unit-test.tmp"))
  (check-error (open-input-file "no-such-file.txt") "file not found"))

(define-test big-code
  (define (twenty a b c d e f g h i j k l m n o p q r s t) (+ a t))
  (check (twenty 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20) 21)
  (check (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 (+ 1 0))))))))))))))))))))))))) 25))

(define-test loading
  (check-true (string? (current-load-path)))
  (check-true (pair? (command-line))))

(run-tests)
