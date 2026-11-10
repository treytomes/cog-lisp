;;; phase-9.3-derived-forms.lisp -- the derived forms are hygienic
;;; (specs/15-phase-9-language.md step 9.3b, AC-3; review C-14): lib/core.lisp
;;; defines them with syntax-rules, so the names they use mean the global ones,
;;; and the names they bind capture nothing. Their behavior is the same as the
;;; define-macro versions' (every older suite checks that).
(load "../../lib/test.lisp")

(define-test "AC-3 C-14: case calls the global memv, whatever memv means where it is used"
  (check (let ((memv (lambda (k l) #f))) (case 3 ((1 2 3) 'found) (else 'not-found))) 'found)
  (check (let ((memv 'not-a-procedure)) (case 'b ((a) 1) ((b c) 2) (else 3))) 2))

(define-test "AC-3 the derived forms are syntax-rules macros"
  (for-each (lambda (name)
              (check-true [[[(smalltalk LispEnvironment) default] lookup: name] isKindOf: (smalltalk LispSyntax)]))
            '(cond case and or when unless let* letrec letrec* do guard restart-case)))

(define-test "AC-3 cond, and, or, when, unless with if, let and begin bound locally"
  (check (let ((if list) (let 1) (begin 2)) (cond (#f 'a) ((> 2 1) 'b) (else 'c))) 'b)
  (check (let ((if list) (let 1)) (cond ((assv 2 '((1 . one) (2 . two))) => cdr) (else 'none))) 'two)
  (check (let ((if list) (let 1)) (cond (#f) (5))) 5)
  (check (let ((if list)) (and 1 2 3)) 3)
  (check (let ((if list) (let 1) (t 'program-t)) (or #f t)) 'program-t)
  (check (let ((if list) (begin 2)) (when #t 'w)) 'w)
  (check (let ((if list) (begin 2)) (unless #f 'u)) 'u))

(define-test "AC-3 let*, letrec, letrec* with define and lambda bound locally"
  (check (let ((define 'd) (lambda 'l)) (let* ((a 1) (b (+ a 1))) (list a b))) '(1 2))
  (check (let ((define 'd) (lambda 'l)) (letrec ((a 1) (b 2)) (+ a b))) 3)
  (check (let ((define 'd) (lambda 'l)) (letrec* ((x 2) (y (* x 3))) y)) 6))

(define-test "AC-3 do: its loop name captures nothing"
  (check (let ((loop 'mine)) (do ((i 0 (+ i 1))) ((= i 3) (list i loop)))) '(3 mine))
  (check (do ((i 0 (+ i 1)) (acc '() (cons i acc))) ((= i 4) acc)) '(3 2 1 0))
  (check (let ((x '(1 3 5 7 9))) (do ((x x (cdr x)) (sum 0 (+ sum (car x)))) ((null? x) sum))) 25))

(define-test "AC-3 case: else, =>, and no match"
  (check (case (* 2 3) ((2 3 5 7) 'prime) ((1 4 6 8 9) 'composite)) 'composite)
  (check (case 5 ((1) 'a) (else => (lambda (x) (* x 2)))) 10)
  (check (case 1 ((1) => (lambda (x) (list x 'one))) (else 'other)) '(1 one))
  (check (case 'z ((a) 1)) (if #f #f))
  (check (let ((k 'program-k)) (case 'a ((a) k))) 'program-k))

(define-test "AC-3 guard and restart-case"
  (check (guard (e ((symbol? e) (list 'caught e))) (raise 'boom)) '(caught boom))
  (check (guard (e (#f 'no) (else 'yes)) (raise 1)) 'yes)
  (check (guard (e ((string? e) e)) (guard (e2 ((number? e2) 'inner)) (raise "outer"))) "outer")
  (check (restart-case (invoke-restart 'use 5) (use (v) (* v 10))) 50))

(define-test "AC-3 a syntax-rules template can use the derived forms"
  (define-syntax my-max
    (syntax-rules () ((_ a b) (let ((x a) (y b)) (cond ((> x y) x) (else y))))))
  (check (let ((x 1) (y 2) (cond 'shadowed)) (my-max y x)) 2))

(define-test "AC-3 the test framework's own forms are hygienic"
  (let ((lambda 'l) (if 'i) (let 'x))
    (check (+ 1 2) 3)
    (check-true #t)
    (check-error (car 5) "not a pair")))

(run-tests)
