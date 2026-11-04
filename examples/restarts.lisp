; restarts.lisp -- recovering without unwinding first (Phase 7.7 section 5)

; A low-level parser finds bad input and offers ways to go on; it does not decide.
(define (parse-entry s)
  (let ((n [s asInteger]))
    (if (smalltalk-nil? n)
        (restart-case (error "not a number:" s)
          (use-value (v) v)                         ; use this value instead
          (skip () 'skip))                          ; leave the entry out
        n)))

(define (parse-all strings)
  (let loop ((ss strings) (acc '()))
    (if (null? ss)
        (reverse acc)
        (let ((v (parse-entry (car ss))))
          (loop (cdr ss) (if (eq? v 'skip) acc (cons v acc)))))))

(define input '("10" "twenty" "30" "forty"))

; Callers higher up choose the recovery, from a handler, before anything unwinds.
(display (with-exception-handler (lambda (c) (invoke-restart 'skip))
           (lambda () (parse-all input))))
(newline)
(display (with-exception-handler (lambda (c) (use-value 0))
           (lambda () (parse-all input))))
(newline)
(display (with-exception-handler
           (lambda (c) (use-value [(car (error-object-irritants c)) size]))
           (lambda () (parse-all input))))             ; the length of the bad text
(newline)

; Handlers can look at what is on offer.
(display (with-exception-handler
           (lambda (c) (use-value (map restart-name (compute-restarts))))
           (lambda () (parse-entry "x"))))
(newline)

; An unbound variable offers use-value and store-value.
(display (with-exception-handler (lambda (c) (use-value 1))
           (lambda () (+ not-yet-defined 41))))
(newline)
(display (with-exception-handler (lambda (c) (store-value 100))
           (lambda () (* not-yet-defined-either 2))))
(newline)
(display not-yet-defined-either)                       ; store-value defined it
(newline)

; Invoking a restart that is not active is an error.
(display (guard (e ((error-object? e) (error-object-message e)))
  (invoke-restart 'skip)))
(newline)
