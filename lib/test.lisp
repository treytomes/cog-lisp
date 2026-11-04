;;; test.lisp -- unit tests written in cog-lisp (specs/phase-7.9-self-hosting-groundwork.md section 8a)
;;;
;;;   (load "lib/test.lisp")
;;;   (define-test arithmetic
;;;     (check (+ 1 2) 3)
;;;     (check-true (< 1 2))
;;;     (check-error (car 5) "not a pair"))
;;;   (run-tests)
;;;
;;; Output matches the Smalltalk suites: PASS/FAIL per check, then
;;; "== RESULT: n/n checks passed ==", and run-tests exits 0 only if all passed,
;;; so tests\run-all.bat counts a LISP test file like any suite.

(define %tests '())          ; (name . thunk) in the order they were defined
(define %pass 0)
(define %total 0)
(define %current "")

;; (define-test name body ...) -- registers a test; running it runs the body
(define-macro (define-test name . body)
  `(set! %tests (append %tests (list (cons ',name (lambda () ,@body))))))

(define (%text x) (with-output-to-string (lambda () (write x))))

(define (%name x) (if (symbol? x) (symbol->string x) x))

(define (%message e)
  (if (condition? e) (condition-report e) (string-append "raised " (%text e))))

(define (%report ok label detail)
  (set! %total (+ %total 1))
  (display (if ok "  PASS  " "  FAIL  "))
  (display (string-append %current ": " label))
  (unless ok (display detail))
  (newline)
  (when ok (set! %pass (+ %pass 1))))

;; (check expr expected) -- passes when (equal? expr expected)
(define-macro (check expr expected)
  `(%check ',expr (lambda () ,expr) ,expected))

(define (%check expr thunk expected)
  (let ((actual (thunk)))
    (%report (equal? actual expected) (%text expr)
             (string-append "  got=" (%text actual) "  want=" (%text expected)))))

;; (check-true expr), (check-false expr)
(define-macro (check-true expr)
  `(let ((v ,expr)) (%report (if v #t #f) ,(%text expr) "  got=#f")))

(define-macro (check-false expr)
  `(let ((v ,expr)) (%report (not v) ,(%text expr) (string-append "  got=" (%text v)))))

;; (check-error expr), (check-error expr "text") -- passes when expr signals an
;; error (whose message contains text)
(define-macro (check-error expr . text)
  `(%check-error ',expr (lambda () ,expr) ,(if (null? text) #f (car text))))

(define (%check-error expr thunk text)
  (let ((outcome (guard (e (#t (list 'raised (%message e))))
                   (list 'value (thunk)))))
    (cond ((eq? (car outcome) 'value)
           (%report #f (%text expr)
                    (string-append "  no error; got=" (%text (car (cdr outcome))))))
          ((and text (not (string-search (car (cdr outcome)) text)))
           (%report #f (%text expr)
                    (string-append "  message=" (%text (car (cdr outcome))) "  want text " (%text text))))
          (else (%report #t (%text expr) "")))))

;; (run-tests/report) -- runs every test; answers (passed total), no exit
(define (run-tests/report)
  (for-each
    (lambda (t)
      (set! %current (%name (car t)))
      (guard (e (#t (%report #f "unexpected error" (string-append "  " (%message e)))))
        ((cdr t))))
    %tests)
  (newline)
  (display (string-append "== RESULT: " (number->string %pass) "/" (number->string %total)
                          " checks passed =="))
  (newline)
  (list %pass %total))

;; (run-tests) -- runs every test, then exits 0 if all checks passed, else 1
(define (run-tests)
  (let ((r (run-tests/report)))
    (exit (if (and (> (car (cdr r)) 0) (= (car r) (car (cdr r)))) 0 1))))
