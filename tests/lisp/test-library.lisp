;;; Moved from ~/projects/lisp-expert (lib/test-test.lisp) with lib/cl.lisp and
;;; lib/test.lisp, whose copies it tested (specs/lisp-expert-libraries.md).
;;; Changed: its load lines only.
;;; Tests for the Lisp test framework itself.
(load "../../lib/test.lisp")

(define (test-list-at items index)
  (if (= index 0) (car items) (test-list-at (cdr items) (- index 1))))

(define-test test-library-check-reports-a-match
  (let ((old-pass %pass)
        (old-total %total)
        (output (with-output-to-string
                  (lambda () (%check 'sample (lambda () 3) 3)))))
    (check (= %pass (+ old-pass 1)) #t)
    ;; This check and the previous assertion each increment the report count.
    (check (= %total (+ old-total 2)) #t)
    (check-true (string-search output "PASS"))))

(define-test test-library-check-error-matches-message
  (check-error (error "expected test error") "expected test error"))

(define-test test-library-check-boolean-assertions
  (check-true #t)
  (check-false #f))

(define-test test-library-check-error-class
  (check-error-class (car) LispArityError))

(define-test test-library-written-value
  (check-written '(a b) "(a b)"))

(define-test test-library-define-test-registers
  (let ((original %tests)
        (before (length %tests))
        (registered? #f))
    (define-test test-library-registration-probe 'registered)
    (set! registered?
          (and (= (length %tests) (+ before 1))
               (eq? (car (test-list-at %tests before)) 'test-library-registration-probe)))
    (set! %tests original)
    (check registered? #t)))

(define-test test-library-run-tests-report-isolated
  (let ((saved-tests %tests)
        (saved-pass %pass)
        (saved-total %total)
        (saved-current %current)
        (result #f)
        (output #f))
    (set! %tests (list (cons 'probe (lambda () (%report #t "probe" "")))))
    (set! %pass 0)
    (set! %total 0)
    (set! output (with-output-to-string (lambda () (set! result (run-tests/report)))))
    (set! %tests saved-tests)
    (set! %pass saved-pass)
    (set! %total saved-total)
    (set! %current saved-current)
    (check result '(1 1))
    (check-true (string-search output "1/1 checks passed"))))

(define-test test-library-run-tests-report-catches-errors
  (let ((saved-tests %tests)
        (saved-pass %pass)
        (saved-total %total)
        (saved-current %current)
        (result #f)
        (output #f))
    (set! %tests (list (cons 'probe (lambda () (error "probe failure")))))
    (set! %pass 0)
    (set! %total 0)
    (set! output (with-output-to-string (lambda () (set! result (run-tests/report)))))
    (set! %tests saved-tests)
    (set! %pass saved-pass)
    (set! %total saved-total)
    (set! %current saved-current)
    (check result '(0 1))
    (check-true (string-search output "unexpected error"))))

(run-tests)
