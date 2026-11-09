;;; format.lisp -- lay out a cog-lisp source file (specs/formatter.md R-6)
;;;
;;;   ./cog-lisp.sh tools/format.lisp FILE                 the formatted text on stdout
;;;   ./cog-lisp.sh tools/format.lisp FILE --write         FILE rewritten in place
;;;   ./cog-lisp.sh tools/format.lisp FILE --spaces 2      indented with spaces, not tabs
;;;
;;; Only whitespace changes (format-source checks it). A file that does not read
;;; is an error naming the line, and is left as it was.

(require 'format-source)

(define (usage)
  (display "usage: tools/format.lisp FILE [--write] [--spaces N]" (current-error-port))
  (newline (current-error-port))
  (exit 2))

(define arguments (cdr (command-line)))

(define file #f)
(define write? #f)
(define spaces #f)

(let loop ((as arguments))
  (cond ((null? as) #t)
        ((string=? (car as) "--write") (set! write? #t) (loop (cdr as)))
        ((string=? (car as) "--spaces")
         (if (or (null? (cdr as)) (not (string->number (cadr as)))) (usage))
         (set! spaces (string->number (cadr as)))
         (loop (cddr as)))
        ((string-prefix? "--" (car as)) (usage))
        (file (usage))
        (else (set! file (car as)) (loop (cdr as)))))

(if (not file) (usage))
(if (not (file-exists? file))
    (begin (display (string-append "tools/format.lisp: no such file: " file) (current-error-port))
           (newline (current-error-port))
           (exit 1)))

(define text (call-with-input-file file (lambda (port) (let loop ((acc '()))
                                                       (let ((c (read-char port)))
                                                         (if (eof-object? c)
                                                             (list->string (reverse acc))
                                                             (loop (cons c acc))))))))

(define formatted
  (guard (e ((error-object? e)
             (display (error-object-message e) (current-error-port))
             (newline (current-error-port))
             (exit 1)))
    (if spaces (format-source text 'spaces spaces) (format-source text))))

(if write?
    (unless (string=? formatted text)
      (with-output-to-file file (lambda () (display formatted))))
    (display formatted))
