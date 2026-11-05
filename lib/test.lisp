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

; The framework keeps its own references to the procedures it uses, so a test
; that redefines one (+, display, ...) cannot break the reporting. Its forms are
; syntax-rules macros (Phase 9 step 9.3), so a test may also bind lambda, if or
; let locally around a check.
(define %+ +) (define %= =) (define %> >) (define %display display) (define %newline newline)
(define %string-append string-append) (define %equal? equal?) (define %not not)
(define %write write) (define %number->string number->string)

(define %tests '())          ; (name . thunk) in the order they were defined
(define %pass 0)
(define %total 0)
(define %current "")

;; (define-test name body ...) -- registers a test; running it runs the body.
;; The body is compiled when the test runs, not when the file loads, so a test
;; can use a macro or a library that an earlier test defined or loaded.
(define-syntax define-test
  (syntax-rules ()
    ((_ name body ...)
     (set! %tests (append %tests (list (cons 'name (lambda () (eval '(let () body ...))))))))))

(define (%text x) (with-output-to-string (lambda () (%write x))))

(define (%name x) (if (symbol? x) (symbol->string x) x))

(define (%message e)
  (if (condition? e) (condition-report e) (%string-append "uncaught raise: " (%text e))))

(define (%report ok label detail)
  (set! %total (%+ %total 1))
  (%display (if ok "  PASS  " "  FAIL  "))
  (%display (%string-append %current ": " label))
  (unless ok (%display detail))
  (%newline)
  (when ok (set! %pass (%+ %pass 1))))

;; (check expr expected) -- passes when (%equal? expr expected)
(define-syntax check
  (syntax-rules ()
    ((_ expr expected) (%check 'expr (lambda () expr) expected))))

(define (%check expr thunk expected)
  (let ((actual (thunk)))
    (%report (%equal? actual expected) (%text expr)
             (%string-append "  got=" (%text actual) "  want=" (%text expected)))))

;; (check-true expr), (check-false expr)
(define-syntax check-true
  (syntax-rules ()
    ((_ expr) (let ((v expr)) (%report (if v #t #f) (%text 'expr) "  got=#f")))))

(define-syntax check-false
  (syntax-rules ()
    ((_ expr) (let ((v expr)) (%report (%not v) (%text 'expr) (%string-append "  got=" (%text v)))))))

;; (check-error expr), (check-error expr "text") -- passes when expr signals an
;; error (whose message contains text)
(define-syntax check-error
  (syntax-rules ()
    ((_ expr) (%check-error 'expr (lambda () expr) #f))
    ((_ expr text) (%check-error 'expr (lambda () expr) text))))

(define (%check-error expr thunk text)
  (let ((outcome (guard (e (#t (list 'raised (%message e))))
                   (list 'value (thunk)))))
    (cond ((eq? (car outcome) 'value)
           (%report #f (%text expr)
                    (%string-append "  no error; got=" (%text (car (cdr outcome))))))
          ((and text (not (string-search (car (cdr outcome)) text)))
           (%report #f (%text expr)
                    (%string-append "  message=" (%text (car (cdr outcome))) "  want text " (%text text))))
          (else (%report #t (%text expr) "")))))

;; (run-tests/report) -- runs every test; answers (passed total), no exit
(define (run-tests/report)
  (for-each
    (lambda (t)
      (set! %current (%name (car t)))
      (guard (e (#t (%report #f "unexpected error" (%string-append "  " (%message e)))))
        ((cdr t))))
    %tests)
  (%newline)
  (%display (%string-append "== RESULT: " (%number->string %pass) "/" (%number->string %total)
                          " checks passed =="))
  (%newline)
  (list %pass %total))

;; (run-tests) -- runs every test, then exits 0 if all checks passed, else 1
(define (run-tests)
  (let ((r (run-tests/report)))
    (exit (if (and (%> (car (cdr r)) 0) (%= (car r) (car (cdr r)))) 0 1))))

;;; Helpers for tests moved from the Smalltalk suites (Phase 8 step 8.1)

;; (eval-all "source") -- evaluates every form of a string at top level, in
;; order, as the Smalltalk suites' evalAll: did, so procedures keep their source
;; text; answers the last value
(define (eval-all source)
  [[(smalltalk LispCompiler) new] evalAll: source])

;; (check-written expr "text") -- passes when write prints expr's value as text
(define-syntax check-written
  (syntax-rules ()
    ((_ expr text) (%check-written 'expr (lambda () expr) text))))

(define (%check-written expr thunk text)
  (let ((actual (%text (thunk))))
    (%report (%equal? actual text) (%text expr)
             (%string-append "  got=" actual "  want=" text))))

;; (check-error-class expr ClassName) -- passes when expr signals an error of that
;; Smalltalk class (LispArityError, LispUnboundError, ...)
(define-syntax check-error-class
  (syntax-rules ()
    ((_ expr class) (%check-error-class 'expr (lambda () expr) 'class))))

(define (%check-error-class expr thunk class)
  (let ((outcome (guard (e (#t (list 'raised e))) (list 'value (thunk)))))
    (cond ((eq? (car outcome) 'value)
           (%report #f (%text expr) (%string-append "  no error; got=" (%text (car (cdr outcome))))))
          ((and (condition? (car (cdr outcome)))
                [(car (cdr outcome)) isKindOf: (smalltalk-global class)])
           (%report #t (%text expr) ""))
          (else (%report #f (%text expr)
                         (%string-append "  wrong error: " (%message (car (cdr outcome)))))))))
