;;; lists-r7rs-srfi1.lisp -- R7RS's list-ref, list-tail and c[ad]r names, SRFI 1's
;;; filter, remove, delete, delete-duplicates, fold, reduce and iota, and sort
;;; (specs/lisp-expert-libraries.md AC-2)
(load "../../lib/test.lisp")

(define-test "list-ref and list-tail (R7RS)"
  (check (list-ref '(a b c d) 0) 'a)
  (check (list-ref '(a b c d) 2) 'c)
  (check (list-tail '(a b c d) 0) '(a b c d))
  (check (list-tail '(a b c d) 2) '(c d))
  (check (list-tail '(a b c d) 4) '())
  (let ((l (list 1 2 3)))
    (check-true (eq? (list-tail l 1) (cdr l))))         ; shares its structure
  (check-error (list-ref '(a b) 2) "list-ref: index out of range: 2")
  (check-error (list-tail '(a b) 3) "list-tail: index out of range: 3"))

(define-test "the c[ad]r names (R7RS base and (scheme cxr))"
  (let ((t '((1 2) (3 4) 5 6 7)))
    (check (caar t) 1)
    (check (cadr t) '(3 4))
    (check (cdar t) '(2))
    (check (cddr t) '(5 6 7))
    (check (caddr t) 5)
    (check (cdddr t) '(6 7))
    (check (cadddr t) 6)
    (check (cddddr t) '(7))
    (check (caadr t) 3)
    (check (cdadr t) '(4))
    (check (cadar t) 2)
    (check (cddar t) '()))
  (check (caaar '(((x)))) 'x)
  (check (caaaar '((((y))))) 'y)
  (check-error (cadr '(a)) "not a pair"))

(define-test "filter, remove, delete and delete-duplicates (SRFI 1)"
  (check (filter even? '(1 2 3 4 6)) '(2 4 6))
  (check (filter even? '()) '())
  (check (remove even? '(1 2 3 4)) '(1 3))                ; remove takes a test
  (check (delete 'b '(a b c b)) '(a c))                    ; delete takes an item
  (check (delete "b" (list "a" "b")) '("a"))               ; equal? by default
  (check (delete 2 '(1 2 3) (lambda (x y) (< x y))) '(1 2)) ; = is called (= x element)
  (check (delete-duplicates '(a b a c b)) '(a b c))
  (check (delete-duplicates '()) '())
  (check (delete-duplicates '(1 2 1.0) =) '(1 2)))

(define-test "fold, reduce and iota (SRFI 1)"
  (check (fold + 0 '(1 2 3 4)) 10)
  (check (fold cons '() '(1 2 3)) '(3 2 1))               ; (kons element accumulator)
  (check (reduce + 0 '(1 2 3)) 6)
  (check (reduce + 0 '()) 0)
  (check (reduce max 0 '(3 9 2)) 9)
  (check (iota 5) '(0 1 2 3 4))
  (check (iota 5 1) '(1 2 3 4 5))
  (check (iota 3 0 2) '(0 2 4))
  (check (iota 0) '()))

(define-test "sort: lists and vectors, stable"
  (check (sort (list 3 1 4 1 5 9 2 6) <) '(1 1 2 3 4 5 6 9))
  (check (sort '() <) '())
  (check (sort (vector 3 1 2) <) (vector 1 2 3))
  (check (sort (list "pear" "apple" "fig") string<?) '("apple" "fig" "pear"))
  ;; stable: (2 . a) stays before (2 . b)
  (check (sort (list '(2 . a) '(1 . x) '(2 . b)) (lambda (p q) (< (car p) (car q))))
         '((1 . x) (2 . a) (2 . b)))
  (let ((l (list 2 1)))
    (sort l <)
    (check l '(2 1))))                                    ; a new list: the argument is unchanged

(define-test "each is documented, under Lists"
  (for-each (lambda (name)
              (check (list name (documentation-category name)) (list name "Lists")))
            '(list-ref list-tail filter remove delete delete-duplicates fold reduce iota sort caar cddddr)))

(run-tests)
