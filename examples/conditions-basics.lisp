; conditions-basics.lisp -- signalling and catching errors (Phase 7.7 section 4)

; error makes a condition from a message and irritants; guard catches it.
(define (checked-sqrt x)
  (if (< x 0)
      (error "checked-sqrt: negative argument:" x)
      [x sqrt]))

(display (guard (e ((error-object? e)
                    (list (error-object-message e) (error-object-irritants e))))
  (checked-sqrt -4)))
(newline)
(display (guard (e ((error-object? e) (condition-report e)))
  (checked-sqrt -9)))
(newline)
(display (checked-sqrt 16))                       ; nothing raised: the body's value
(newline)

; Any value can be raised, and the clauses pick by what it is.
(define (classify-raise thunk)
  (guard (e ((symbol? e) (list 'symbol e))
            ((pair? e) (list 'list (car e)))
            ((string? e) (list 'string e))
            (else (list 'other e)))
    (thunk)))
(display (map classify-raise
              (list (lambda () (raise 'out-of-paper))
                    (lambda () (raise (list 'jammed 3)))
                    (lambda () (raise "on fire"))
                    (lambda () (raise 42)))))
(newline)

; Errors from primitives and from Smalltalk are conditions too.
(define (try thunk)
  (guard (e ((error-object? e) (error-object-message e)))
    (thunk)))
(display (try (lambda () (car 5))))
(newline)
(display (try (lambda () (/ 1 0))))
(newline)
(display (try (lambda () [42 frobnicate])))
(newline)

; With no matching clause, the condition goes on to an outer guard.
(display (guard (outer (#t (list 'outer-caught outer)))
  (guard (inner ((string? inner) 'inner-caught))
    (raise 'not-a-string))))
(newline)

; => passes the test's value to a procedure, as in cond.
(display (guard (e ((assq 'code (if (pair? e) e '())) => cdr))
  (raise (list (cons 'code 404) (cons 'reason "not found")))))
(newline)
