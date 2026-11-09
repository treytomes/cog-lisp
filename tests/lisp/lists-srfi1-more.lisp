;;; lists-srfi1-more.lisp -- SRFI 1's any, every, find, filter-map, append-map and
;;; alist-delete (specs/lisp-expert-review.md R-1, AC-1)
(load "../../lib/test.lisp")

(define-test "any answers the predicate's value, not just #t"
  (check (any (lambda (n) (and (even? n) (* n n))) '(1 3 4 6)) 16)
  (check (any even? '(1 3 5)) #f)
  (check (any even? '()) #f)
  (check (any (lambda (x) (assq x '((b . 2)))) '(a b)) '(b . 2))
  (let ((calls 0))                                     ; stops at the first true value
    (any (lambda (n) (set! calls (+ calls 1)) (> n 1)) '(1 2 3 4))
    (check calls 2))
  (check-error (any even? 5) "any: not a list: 5"))

(define-test "every: #t for (), else the last value or #f"
  (check (every even? '()) #t)
  (check (every even? '(2 4)) #t)
  (check (every (lambda (n) (and (even? n) n)) '(2 4 6)) 6)
  (check (every even? '(2 3 4)) #f)
  (let ((calls 0))                                     ; stops at the first false one
    (every (lambda (n) (set! calls (+ calls 1)) (< n 2)) '(1 2 3 4))
    (check calls 2))
  (check-error (every even? 'x) "every: not a list: x"))

(define-test "find"
  (check (find even? '(1 4 5 6)) 4)
  (check (find even? '(1 3)) #f)
  (check (find symbol? '()) #f)
  (check-error (find even? "abc") "find: not a list: \"abc\""))

(define-test "filter-map keeps the true values, in order"
  (check (filter-map (lambda (n) (and (even? n) (* n 10))) '(1 2 3 4)) '(20 40))
  (check (filter-map (lambda (x) x) '(#f #f)) '())
  (check (filter-map car '()) '())
  (check-error (filter-map car 7) "filter-map: not a list: 7"))

(define-test "append-map appends f's lists, in order"
  (check (append-map (lambda (n) (list n n)) '(1 2 3)) '(1 1 2 2 3 3))
  (check (append-map (lambda (n) '()) '(1 2)) '())
  (check (append-map list '()) '())
  (check-error (append-map list 'y) "append-map: not a list: y"))

(define-test "alist-delete, with equal? or a given test, leaving its argument alone"
  (let ((al (list (cons 'a 1) (cons 'b 2) (cons 'a 3) (cons "s" 4))))
    (check (alist-delete 'a al) '((b . 2) ("s" . 4)))
    (check (alist-delete "s" al) '((a . 1) (b . 2) (a . 3)))    ; equal? by default
    (check (alist-delete "s" al eq?) al)                        ; a new string: not eq?
    (check (alist-delete 2 (list (cons 1 'x) (cons 3 'y)) (lambda (k e) (< k e))) '((1 . x)))
    (check (length al) 4)                                        ; unchanged
    (check (alist-delete '(s p o) (list (cons (list 's 'p 'o) 1) (cons (list 'x 'y 'z) 2)))
           '(((x y z) . 2)))))

(define-test "documented, under Lists"
  (for-each (lambda (n) (check-true (string? (documentation n))))
            '(any every find filter-map append-map alist-delete)))

(run-tests)
