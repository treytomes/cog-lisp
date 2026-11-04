; conditions-handlers.lisp -- handlers that run before unwinding (Phase 7.7 sections 4.2, 4.4)

; raise-continuable asks a handler for a value and carries on with it.
(define (lookup key table)
  (let ((entry (assq key table)))
    (if entry
        (cdr entry)
        (raise-continuable (list 'missing key)))))

(define table '((a . 1) (b . 2)))
(display (with-exception-handler
           (lambda (c) 0)                         ; a default for anything missing
           (lambda () (+ (lookup 'a table) (lookup 'b table) (lookup 'z table)))))
(newline)

; The handler sees the condition while the computation is still there: here it
; logs every missing key and supplies a different default each time.
(define seen '())
(display (with-exception-handler
           (lambda (c)
             (set! seen (cons (car (cdr c)) seen))
             (* 100 (length seen)))
           (lambda () (list (lookup 'x table) (lookup 'a table) (lookup 'y table)))))
(newline)
(display (reverse seen))
(newline)

; dynamic-wind's after runs however the thunk is left: normally, or by an error
; unwinding to a guard (after runs before the guard's clause).
(define trail '())
(define (note x) (set! trail (cons x trail)))
(define (guarded thunk)
  (guard (e (#t (note 'handled) 'recovered))
    (dynamic-wind
      (lambda () (note 'enter))
      thunk
      (lambda () (note 'exit)))))
(display (guarded (lambda () (note 'work) 'done)))
(newline)
(display (guarded (lambda () (note 'work) (error "failed"))))
(newline)
(display (reverse trail))
(newline)

; Returning from a handler of a plain raise is itself an error.
(display (guard (e ((error-object? e) (error-object-message e)))
  (with-exception-handler (lambda (c) 'ignored) (lambda () (raise 'stop)))))
(newline)
