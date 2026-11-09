;;; Copied from ~/projects/lisp-expert/format-params-test.lisp (the owner's), to check that
;;; cog-lisp's built-in format passes it with lisp-expert's format.lisp not loaded
;;; (specs/format.md AC-2). Changed: the path to lib/test.lisp; no (load "format.lisp").
;;; format-params-test.lisp -- Task 2a: parameters and modifiers in the parser
;;;
;;; A directive is ~ [parameters] [modifiers] character, as in Common Lisp:
;;;   parameters: numbers (~5A) or 'c characters (~5,'0D), separated by commas,
;;;               any of them may be left out (~,3D)
;;;   modifiers:  @ and :, in either order (~:@A)
;;; These tests are about parsing only; padding comes in 2b and 2c.
;;;
;;; Written before the implementation, so on the first run these should FAIL.

(load "../../lib/test.lisp")

;; Summarizes parsed segments so these tests do not depend on how a directive is
;; represented: literal text stays a string, a directive becomes
;; (character parameters at? colon?).
(define (full-summary segments)
	(map
		(lambda (segment)
			(if
				(directive? segment)
				(list
					(directive-char segment)
					(directive-params segment)
					(directive-at? segment)
					(directive-colon? segment)
				)
				segment
			)
		)
		segments
	)
)

(define-test format-params-none
	(check (full-summary (format-parse "~A")) '((#\A () #f #f)))
	(check (full-summary (format-parse "~%")) '((#\% () #f #f)))
)

(define-test format-params-numbers
	(check (full-summary (format-parse "~5A")) '((#\A (5) #f #f)))
	(check (full-summary (format-parse "~123A")) '((#\A (123) #f #f)))
	(check (full-summary (format-parse "~0D")) '((#\D (0) #f #f)))
)

(define-test format-params-several
	(check (full-summary (format-parse "~5,3D")) '((#\D (5 3) #f #f)))
	(check (full-summary (format-parse "~1,2,3A")) '((#\A (1 2 3) #f #f)))
)

(define-test format-params-omitted
	(check (full-summary (format-parse "~,3D")) '((#\D (#f 3) #f #f)))
	(check (full-summary (format-parse "~5,D")) '((#\D (5 #f) #f #f)))
	(check (full-summary (format-parse "~,A")) '((#\A (#f #f) #f #f)))
)

(define-test format-params-characters
	(check (full-summary (format-parse "~5,'0D")) '((#\D (5 #\0) #f #f)))
	(check (full-summary (format-parse "~'*A")) '((#\A (#\*) #f #f)))
	;; The character parameter keeps its case; only the directive is upcased.
	(check (full-summary (format-parse "~'aa")) '((#\A (#\a) #f #f)))
)

(define-test format-params-modifiers
	(check (full-summary (format-parse "~@A")) '((#\A () #t #f)))
	(check (full-summary (format-parse "~:A")) '((#\A () #f #t)))
	(check (full-summary (format-parse "~:@A")) '((#\A () #t #t)))
	(check (full-summary (format-parse "~@:A")) '((#\A () #t #t)))
)

(define-test format-params-with-modifiers
	(check (full-summary (format-parse "~10@A")) '((#\A (10) #t #f)))
	(check (full-summary (format-parse "~5,'0@D")) '((#\D (5 #\0) #t #f)))
)

(define-test format-params-in-context
	(check
		(full-summary (format-parse "x~5Ay~%"))
		'("x" (#\A (5) #f #f) "y" (#\% () #f #f))
	)
	(check
		(full-summary (format-parse "~5A~3D"))
		'((#\A (5) #f #f) (#\D (3) #f #f))
	)
)

(define-test format-params-errors
	(check-error (format-parse "~5") "ends")
	(check-error (format-parse "~5,") "ends")
	(check-error (format-parse "~'") "ends")
	(check-error (format-parse "~@") "ends")
	(check-error (format-parse "abc~5") "ends")
)

(run-tests)