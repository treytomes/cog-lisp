;; list-tools.lisp -- built in: list-ref, filter, remove, delete, fold, reduce, iota, sort
(display (list-ref (list "a" "b" "c") 1)) (newline)      ; from 0
(display (filter even? (iota 10))) (newline)            ; (iota 10) is 0 to 9
(display (remove even? (list 1 2 3 4))) (newline)       ; remove takes a test
(display (delete 'b (list 'a 'b 'c 'b))) (newline)      ; delete takes an item
(display (fold + 0 (list 1 2 3 4))) (newline)           ; (kons element acc)
(display (sort (list 3 1 4 1 5) <)) (newline)
(display (cadr (list 1 2 3))) (newline)                 ; second: cadr; third: caddr
