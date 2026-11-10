;;; Moved from ~/projects/lisp-expert (lib/test-test.lisp) with lib/cl.lisp and
;;; lib/test.lisp, whose copies it tested (specs/22-lisp-expert-libraries.md).
;;; Changed: its load lines; and since lib/test.lisp became a library
;;; (specs/27-namespaces.md), its private state is named in full: test:%pass.
;;; Tests for the Lisp test framework itself.
(load "../../lib/test.lisp")

(define (test-list-at items index)
  (if (= index 0) (car items) (test-list-at (cdr items) (- index 1))))

(define-test test-library-check-reports-a-match
  (let ((old-pass test:%pass)
        (old-total test:%total)
        (output (with-output-to-string
                  (lambda () (test:%check 'sample (lambda () 3) 3)))))
    (check (= test:%pass (+ old-pass 1)) #t)
    ;; This check and the previous assertion each increment the report count.
    (check (= test:%total (+ old-total 2)) #t)
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
  (let ((original test:%tests)
        (before (length test:%tests))
        (registered? #f))
    (define-test test-library-registration-probe 'registered)
    (set! registered?
          (and (= (length test:%tests) (+ before 1))
               (eq? (car (test-list-at test:%tests before)) 'test-library-registration-probe)))
    (set! test:%tests original)
    (check registered? #t)))

(define-test test-library-run-tests-report-isolated
  (let ((saved-tests test:%tests)
        (saved-pass test:%pass)
        (saved-total test:%total)
        (saved-current test:%current)
        (result #f)
        (output #f))
    (set! test:%tests (list (cons 'probe (lambda () (test:%report #t "probe" "")))))
    (set! test:%pass 0)
    (set! test:%total 0)
    (set! output (with-output-to-string (lambda () (set! result (run-tests/report)))))
    (set! test:%tests saved-tests)
    (set! test:%pass saved-pass)
    (set! test:%total saved-total)
    (set! test:%current saved-current)
    (check result '(1 1))
    (check-true (string-search output "1/1 checks passed"))))

(define-test test-library-run-tests-report-catches-errors
  (let ((saved-tests test:%tests)
        (saved-pass test:%pass)
        (saved-total test:%total)
        (saved-current test:%current)
        (result #f)
        (output #f))
    (set! test:%tests (list (cons 'probe (lambda () (error "probe failure")))))
    (set! test:%pass 0)
    (set! test:%total 0)
    (set! output (with-output-to-string (lambda () (set! result (run-tests/report)))))
    (set! test:%tests saved-tests)
    (set! test:%pass saved-pass)
    (set! test:%total saved-total)
    (set! test:%current saved-current)
    (check result '(0 1))
    (check-true (string-search output "unexpected error"))))

(run-tests)
