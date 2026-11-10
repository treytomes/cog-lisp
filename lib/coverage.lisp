;;; coverage.lisp -- which procedures and branches a run reached (specs/20-coverage.md)
;;;
;;; With the compiler's coverage option on, each procedure entry and each side of
;;; an if gets a probe: a record made here, by %coverage-register, as the form is
;;; compiled, and counted by the compiled code. (coverage-start) turns the option
;;; on for code compiled from then on; (coverage-stop) turns it off and answers
;;; the counts; (coverage-report counts) writes what never ran, by file and line.
;;; COGLISP_COVERAGE=1 does all three for a whole run, the report to stderr.
;;;
;;; Loaded by the build after lib/format.lisp, before the compiler, which calls
;;; %coverage-register; compiled by the seed, so it is plain code.

;; the session, or #f: #(records files), records newest first
(define %coverage #f)
;; called by the runtime just before the process ends (runAtExit), when set
(define %at-exit #f)

;; a probe record, counted by the compiled code at slot 0:
;;   #(count kind file source start end text)
(define (%coverage-record kind file source start end text)
  (vector 0 kind file source start end text))

(define (%coverage-same-file? a b)
  (if [[(smalltalk OSPlatform) current] isWindows]
      (string=? (string-downcase a) (string-downcase b))
      (string=? a b)))

;; is file to be instrumented: a session runs, the file is in its list (if it
;; has one), and it is not cog-lisp's own lib folder
(define (%coverage-file? file)
  (and %coverage
       (let ((files (vector-ref %coverage 1)))
         (if (pair? files)
             (and file (let loop ((fs files)) (and (pair? fs) (or (%coverage-same-file? (car fs) file) (loop (cdr fs))))))
             (not (and file
                       (let ((lib [[[(hash-table-ref/default *env* 'home "") asFileReference] / "lib"] fullName]))
                         (and (>= (string-length file) (string-length lib))
                              (%coverage-same-file? (substring file 0 (string-length lib)) lib)))))))))

(define (%coverage-register kind file source start end text)
  (if (%coverage-file? file)
      (let ((rec (%coverage-record kind file source start end text)))
        (vector-set! %coverage 0 (cons rec (vector-ref %coverage 0)))
        rec)
      #f))

(define (%coverage-option on?)
  (let ((options [(smalltalk LispCompiler) defaultOptions])
        (name (smalltalk-symbol "coverage")))
    (if on? [options add: name] [options remove: name ifAbsent: #f])))

(define (coverage-start . files)
  "(coverage-start [files])
Starts a coverage session: code compiled from now on counts each procedure entry and each side of every if, so start before loading the program. files, a list of paths, limits it to those files; by default every file but cog-lisp's own lib folder. Answers #t."
  (set! %coverage
        (vector '()
                (if (pair? files)
                    (map (lambda (f) [[(smalltalk LispCompiler) resolve: f] fullName]) (car files))
                    '())))
  (%coverage-option #t)
  #t)
[coverage-start category: "Evaluation and macros"]

;; the line and column (both from 1) of a 1-based offset in source
(define (%coverage-line-column source offset)
  (let loop ((i 0) (line 1) (column 1))
    (if (>= i (- offset 1))
        (cons line column)
        (if (eq? (string-ref source i) #\newline)
            (loop (+ i 1) (+ line 1) 1)
            (loop (+ i 1) line (+ column 1))))))

;; the text of a record's form, first line only, shortened
(define (%coverage-text rec)
  (let* ((source (vector-ref rec 3))
         (text (if source
                   (substring source (- (vector-ref rec 4) 1) (vector-ref rec 5))
                   (vector-ref rec 6)))
         (line (car (string-split text #\newline))))
    (if (> (string-length line) 60) (string-append (substring line 0 57) "...") line)))

(define (coverage-stop)
  "(coverage-stop)
Ends the coverage session, and answers its counts: a list, in the order the code was compiled, of #(file line column kind count text). kind is procedure (an entry), true or false (a side of an if); file is #f for a form typed at the REPL, and line and column #f where no position is known."
  (if (not %coverage)
      '()
      (let ((records (reverse (vector-ref %coverage 0))))
        (set! %coverage #f)
        (%coverage-option #f)
        (map (lambda (rec)
               (let ((position (and (vector-ref rec 3) (%coverage-line-column (vector-ref rec 3) (vector-ref rec 4)))))
                 (vector (vector-ref rec 2)
                         (and position (car position))
                         (and position (cdr position))
                         (vector-ref rec 1)
                         (vector-ref rec 0)
                         (%coverage-text rec))))
             records))))
[coverage-stop category: "Evaluation and macros"]

(define (%coverage-describe kind)
  (cond ((eq? kind 'procedure) "never called: ")
        ((eq? kind 'true) "never taken, the true side of: ")
        (else "never taken, the false side of: ")))

(define (coverage-report counts . port)
  "(coverage-report counts [port])
Writes what counts (from coverage-stop) never reached, by file and line: the procedures never called and the sides of an if never taken, after a summary line. Writes to port, or the current output."
  (let ((out (if (pair? port) (car port) (current-output-port)))
        (missed (let loop ((cs counts) (acc '()))
                  (cond ((null? cs) (reverse acc))
                        ((= (vector-ref (car cs) 4) 0) (loop (cdr cs) (cons (car cs) acc)))
                        (else (loop (cdr cs) acc))))))
    (display "coverage: " out)
    (display (- (length counts) (length missed)) out)
    (display " of " out)
    (display (length counts) out)
    (display " probes reached" out)
    (newline out)
    (let loop ((ms missed) (file 'none))
      (if (pair? ms)
          (let* ((m (car ms)) (f (vector-ref m 0)))
            (if (not (equal? f file))
                (begin (display (if f f "(typed at the REPL)") out) (newline out)))
            (display "  " out)
            (if (vector-ref m 1)
                (begin (display (vector-ref m 1) out) (display ":" out) (display (vector-ref m 2) out) (display ": " out)))
            (display (%coverage-describe (vector-ref m 3)) out)
            (display (vector-ref m 5) out)
            (newline out)
            (loop (cdr ms) f))))))
[coverage-report category: "Evaluation and macros"]

;; COGLISP_COVERAGE: a session for the whole run, its report to stderr at the end
(define (%coverage-from-environment)
  (let ((v (get-environment-variable "COGLISP_COVERAGE")))
    (if (and v (not (string=? v "")) (not (string=? v "0")))
        (begin
          (coverage-start)
          (set! %at-exit (lambda () (coverage-report (coverage-stop) (current-error-port))))))))
