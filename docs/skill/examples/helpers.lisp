;; helpers.lisp -- filter, fold, iota, list-ref and sort do not exist: copy these
(define (filter keep? lst)
  (cond ((null? lst) '())
        ((keep? (car lst)) (cons (car lst) (filter keep? (cdr lst))))
        (else (filter keep? (cdr lst)))))

(define (fold f acc lst)            ; (f acc element), left to right
  (if (null? lst) acc (fold f (f acc (car lst)) (cdr lst))))

(define (iota count . start)        ; (iota 5) is (0 1 2 3 4); (iota 5 1) is (1 2 3 4 5)
  (let ((from (if (null? start) 0 (car start))))
    (let loop ((i (- count 1)) (acc '()))
      (if (< i 0) acc (loop (- i 1) (cons (+ from i) acc))))))

(define (list-ref lst k)
  (if (= k 0) (car lst) (list-ref (cdr lst) (- k 1))))

(define (insert x sorted less?)
  (cond ((null? sorted) (list x))
        ((less? x (car sorted)) (cons x sorted))
        (else (cons (car sorted) (insert x (cdr sorted) less?)))))
(define (sort lst less?)
  (fold (lambda (acc x) (insert x acc less?)) '() lst))

(display (filter even? (iota 10))) (newline)
(display (iota 5 1)) (newline)
(display (fold + 0 (list 1 2 3 4))) (newline)
(display (list-ref (list "a" "b" "c") 1)) (newline)
(display (sort (list 3 1 4 1 5) <)) (newline)
