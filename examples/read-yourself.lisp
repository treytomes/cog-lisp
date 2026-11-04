;;; read-yourself.lisp -- the reader written in cog-lisp reads this very file
;;; (Phase 8 step 8.2; lib/compiler/reader.lisp is part of the built image)

;; A short procedure, so there is something to find below.
(define (square x) (* x x))

;; Read every top-level form of this file with the LISP reader.
(define forms
  (call-with-input-file (current-load-path)
    (lambda (port)
      (let loop ((acc '()))
        (let ((d (read-datum port)))
          (if (eof-object? d) (reverse acc) (loop (cons d acc))))))))

(display "forms in this file: ") (write (length forms)) (newline)
;; each definition by name, and how many other forms there are
(define (defined-name f)
  (let ((target (car (cdr f))))
    (if (pair? target) (car target) target)))
(for-each (lambda (f)
            (when (eq? (car f) 'define)
              (display "  defines ") (write (defined-name f)) (newline)))
          forms)
(define (count-others fs)
  (cond ((null? fs) 0)
        ((eq? (car (car fs)) 'define) (count-others (cdr fs)))
        (else (+ 1 (count-others (cdr fs))))))
(display "  and ") (write (count-others forms)) (display " other forms") (newline)

;; The reader remembers the exact text of every list it read.
(define r (make-reader "(define (square x)   ; spacing and comments are kept\n  (* x x))"))
(define sq (reader-next r))
(display "read: ") (write sq) (newline)
(display "from: ") (display (reader-source-for r sq)) (newline)

;; Read errors say what went wrong, where, and whether more input would help.
(define (try s)
  (guard (e (#t (display "  ") (write s) (display " -> ")
                (display (error-object-message e))
                (display " at offset ") (write [e position])
                (when [e isIncomplete] (display " (incomplete)"))
                (newline)))
    (write (read-all s)) (newline)))

(display "errors:") (newline)
(try "(1 2")
(try "(1 2))")
(try "#(1 . 2)")
(try "[3 4]")
