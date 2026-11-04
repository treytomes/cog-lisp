;;; phase-8.4-bootstrap.lisp -- the compiler compiles itself to a fixpoint
;;; (lib/compiler/bootstrap.lisp; specs/phase-8-self-hosting.md steps 8.4 and 8.6,
;;; AC-4 and AC-8). Two bootstraps: through Opal, where every stage makes the
;;; methods the Smalltalk compiler makes (8.4); and with the direct generator,
;;; where stages 1, 2 and 3 make the same methods as each other (8.6).
(load "../../lib/test.lisp")

;; the installed (sealed) compiler's own switch, put back at the end: a bootstrap
;; installs stages whose globals replace these names
(define sealed-set-generator set-code-generator!)
(define stage-1-compile-form compile-form)
(define stage-1-translate-if lc-translate-if)

(set-code-generator! 'opal)
(define bo (bootstrap-compiler "lib/compiler"))
(set-code-generator! 'direct)
(define bd (bootstrap-compiler "lib/compiler"))
(sealed-set-generator 'direct)

(define-test "AC-4 the stages replaced the running compiler"
  (check-false (eq? compile-form stage-1-compile-form))
  (check-false (eq? lc-translate-if stage-1-translate-if)))

(define-test "AC-4 every stage compiles the same forms"
  (check-true (> (length (vector-ref bo 0)) 150))
  (check (map length (list (vector-ref bo 1) (vector-ref bo 2) (vector-ref bo 3)
                           (vector-ref bd 1) (vector-ref bd 2) (vector-ref bd 3)))
         (let ((n (length (vector-ref bo 0)))) (list n n n n n n))))

(define-test "AC-4 through Opal, stage 1 = stage 0: the LISP compiler compiles itself as the Smalltalk one does"
  (check (bootstrap-generator bo) 'opal)
  (check (bootstrap-differences bo 0 1) '()))

(define-test "AC-4 through Opal, stage 3 = stage 2 = stage 1"
  (check (bootstrap-differences bo 1 2) '())
  (check (bootstrap-differences bo 2 3) '())
  (check-true (bootstrap-fixpoint? bo)))

(define-test "AC-8 with the direct generator, stage 3 = stage 2 = stage 1: the fixpoint"
  (check (bootstrap-generator bd) 'direct)
  (check (bootstrap-differences bd 1 2) '())
  (check (bootstrap-differences bd 2 3) '())
  (check-true (bootstrap-fixpoint? bd)))

(define-test "AC-8 the direct generator makes different code from Opal's"
  (check-false (null? (bootstrap-differences bd 0 1))))

(define-test "AC-4 the comparison sees a difference"
  ;; stage 2's first method replaced: the difference is reported by its label
  (let ((changed (vector (vector-ref bd 0) (vector-ref bd 1)
                         (cons (cons "changed" "x") (cdr (vector-ref bd 2)))
                         (vector-ref bd 3) 'direct)))
    (check (bootstrap-differences changed 1 2) (list (car (car (vector-ref bd 1)))))
    (check-false (bootstrap-fixpoint? changed))))

;; stage 3 of the direct bootstrap is now the compiler the globals name
(define-test "AC-8 stage 3 works: it compiles, reads and runs programs"
  (check (opal-run (compile-form '(let loop ((i 0) (acc '())) (if (= i 3) acc (loop (+ i 1) (cons i acc))))))
         '(2 1 0))
  (check (opal-run (compile-form '`(1 ,(+ 1 1) ,@(list 3)))) '(1 2 3))
  (check (lisp-eval-string "(define (stage3-sq x) (* x x)) (stage3-sq 9)") 81)
  (check (read-all "(a . b) #(1 2)") '((a . b) #(1 2)))
  (check (procedure-source stage3-sq) "(define (stage3-sq x) (* x x))"))

(define-test "AC-4 stage 3's own procedures keep their source"
  (check-true (string? (procedure-source lc-translate-if)))
  (check (substring (procedure-source lc-translate-if) 0 26) "(define (lc-translate-if c"))

(run-tests)
