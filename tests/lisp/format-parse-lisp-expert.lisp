;;; Copied from ~/projects/lisp-expert/format-parse-test.lisp (the owner's), to check that
;;; cog-lisp's built-in format passes it with lisp-expert's format.lisp not loaded
;;; (specs/19-format.md AC-2). Changed: the path to lib/test.lisp; no (load "format.lisp").
;;; format-parse-test.lisp -- Task 1: parse the control string, then interpret it
;;;
;;; Written before the implementation, so on the first run these should FAIL.
;;; Adjust the load path as for format-test.lisp.

(load "../../lib/test.lisp")

;; Summarizes parsed segments so these tests do not depend on how a directive
;; is represented: literal text stays a string, a directive becomes its character.
(define (parse-summary segments)
	(map
		(lambda (segment)
			(if
				(directive? segment)
				(directive-char segment)
				segment
			)
		)
		segments
	)
)

(define-test format-parse-literals
	(check (parse-summary (format-parse "")) '())
	(check (parse-summary (format-parse "hello")) '("hello"))
	(check (parse-summary (format-parse "hello world")) '("hello world"))
)

(define-test format-parse-directives
	(check (parse-summary (format-parse "~A")) '(#\A))
	(check (parse-summary (format-parse "~%")) '(#\%))
	(check (parse-summary (format-parse "~~")) '(#\~))
	(check (parse-summary (format-parse "~D~X")) '(#\D #\X))
)

(define-test format-parse-mixed
	(check (parse-summary (format-parse "a~Ab")) '("a" #\A "b"))
	(check (parse-summary (format-parse "~A and ~S")) '(#\A " and " #\S))
	(check (parse-summary (format-parse "x~%y~%")) '("x" #\% "y" #\%))
	(check (parse-summary (format-parse "a~~b")) '("a" #\~ "b"))
	(check (parse-summary (format-parse "100~~ sure")) '("100" #\~ " sure"))
)

(define-test format-parse-normalizes-case
	(check (parse-summary (format-parse "~a~x")) '(#\A #\X))
)

(define-test format-parse-directive-records
	(check-true (directive? (car (format-parse "~A"))))
	(check-false (directive? "text"))
	(check-false (directive? '()))
	(check (directive-char (make-directive #\S '() #f #f)) #\S)
)

(define-test format-parse-errors
	(check-error (format-parse "abc ~") "lone")
)

;; Parsing happens before any output, so a bad control string writes nothing.
(define-test format-lone-tilde-writes-nothing
	(check
		(let
			((port (open-output-string)))
			(guard
				(e (#t #f))
				(format port "abc ~")
			)
			(get-output-string port)
		)
		""
	)
)

(run-tests)
