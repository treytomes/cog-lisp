;;; ide.lisp -- the image's tools as LISP procedures (specs/34-morphic-ide.md
;;; section 5.10). Load with (require 'ide).
;;;
;;; Every tool is a procedure here before it is a window (R-32): the REPL window
;;; calls these, and so will the model's doorway (R-36). They answer plain data
;;; (R-33), and every change they make to the image or a file is recorded (R-35).
;;;
;;; Step 2 (sessions and the record of changes):
;;;   - a session evaluates in a process of its own, with its own unit and ports
;;;     (R-12, R-13, R-31); an error leaves it waiting at a break, on the failing
;;;     computation's stack, where a restart continues it (R-14); a running
;;;     evaluation can be interrupted (R-15), and a program it runs reads the
;;;     lines typed for it;
;;;   - an evaluation that defines names is recorded: when, which session, made
;;;     by a person or an agent, the names, and the text.
;;;
;;; Records are vectors, read with their accessors:
;;;   a result  #(status values written output report restarts level)
;;;   a change  #(time session maker kind names text)

(library ide
  (export ide-session ide-sessions ide-session-name ide-session-maker ide-session-busy? ide-session-output
          ide-eval ide-wait ide-type ide-interrupt ide-close
          result-status result-values result-written result-output result-report result-restarts result-level
          ide-changes ide-log-to!
          change-time change-session change-maker change-kind change-names change-text))
(require 'editor-services)

;; an option's value in (name value ...), or default
(define (%option options name default)
  (let ((m (memq name options))) (if (and m (pair? (cdr m))) (cadr m) default)))

(define (%symbol x) (string->symbol [x asString]))

;;; ---------------------------------------------------------------------------
;;; Sessions

(define %count 0)

(define (ide-session . options)
  "(ide-session option ...)
A new session: evaluations in a process of their own, with their own unit and output and input ports. Options: name (a string; session 1, 2, ...), maker (person or agent: who its changes are recorded as made by; person), unit (the unit to evaluate in, such as a file's; a session unit of its own), wrapper (a procedure given a thunk, run around every evaluation: (lambda (thunk) (with-console '(colors none) thunk)))."
  (set! %count (+ %count 1))
  (let* ((name (%option options 'name (string-append "session " (number->string %count))))
         (unit (%option options 'unit #f))
         (s [(smalltalk LispSession) named: name
                                     unit: (if unit unit (smalltalk-nil))
                                     maker: [(symbol->string (%option options 'maker 'person)) asSymbol]])
         (wrapper (%option options 'wrapper #f)))
    (if wrapper [s wrapper: wrapper])
    s))

(define (ide-sessions)
  "(ide-sessions)
The sessions open in the image."
  (vector->list [[[(smalltalk LispSession) all] copy] asArray]))

(define (ide-session-name s) "(ide-session-name session)\nIts name, a string." [s name])
(define (ide-session-maker s) "(ide-session-maker session)\nperson or agent: who its changes are recorded as made by." (%symbol [s maker]))
(define (ide-session-busy? s) "(ide-session-busy? session)\n#t while it evaluates; at a break, waiting for a restart or another form, #f." [s isBusy])
(define (ide-session-output s) "(ide-session-output session)\nEverything the session has written to its output port, a string." [s output])

;;; ---------------------------------------------------------------------------
;;; Results

(define %unspecified [(smalltalk LispUnspecified) default])

(define (%written v) (with-output-to-string (lambda () (write v))))

(define (%result r)
  (if (string=? [[r status] asString] "running")
      #f
      (let ((values (filter (lambda (v) (not (eq? v %unspecified))) (vector->list [r values]))))
        (vector (%symbol [r status])
                values
                (map %written values)
                [r output]
                (let ((rep [r report])) (if (smalltalk-nil? rep) #f rep))
                (map (lambda (n) n) (vector->list [r restarts]))
                [r level]))))

(define %running (vector 'running '() '() "" #f '() 0))

(define (result-status r) "(result-status result)\ndone; error (the session waits at a break); aborted (an abort restart came back to the top); or running (not finished in the time asked for: ide-wait answers it later)." (vector-ref r 0))
(define (result-values r) "(result-values result)\nThe values of the forms evaluated, as a list, leaving out the unspecified value." (vector-ref r 1))
(define (result-written r) "(result-written result)\nThe values, each as write writes it." (vector-ref r 2))
(define (result-output r) "(result-output result)\nWhat the evaluation wrote to the output port, a string." (vector-ref r 3))
(define (result-report r) "(result-report result)\nAn error's report, a string; or #f." (vector-ref r 4))
(define (result-restarts r) "(result-restarts result)\nAt an error, the names of the restarts active, strings: evaluating (name args ...) in the session invokes one." (vector-ref r 5))
(define (result-level r) "(result-level result)\nHow many breaks deep the session is: 0 at the top." (vector-ref r 6))

;;; ---------------------------------------------------------------------------
;;; Evaluating

;; the texts sent to each session and not yet answered, oldest first
(define %sent (make-hash-table eq?))

(define (ide-eval s text . options)
  "(ide-eval session text option ...)
Evaluates text's forms in session and answers the result. Options: timeout (milliseconds to wait; as long as it takes if not given): a result still running then has status running, and ide-wait answers it. An evaluation that defines names is recorded (ide-changes)."
  (hash-table-set! %sent s (append (hash-table-ref/default %sent s '()) (list text)))
  [s evaluate: text]
  (ide-wait s (%option options 'timeout #f)))

(define (ide-wait s . timeout)
  "(ide-wait session [milliseconds])
The result of the oldest evaluation not yet answered, waiting at most milliseconds (as long as it takes if not given); a result with status running if it has not come."
  (let ((r [s waitFor: (if (and (pair? timeout) (car timeout)) (car timeout) (smalltalk-nil))]))
    (or (let ((result (%result r)))
          (and result
               (let* ((sent (hash-table-ref/default %sent s '()))
                      (text (if (pair? sent) (car sent) "")))
                 (hash-table-set! %sent s (if (pair? sent) (cdr sent) '()))
                 (unless (eq? (result-status result) 'aborted) (%record-evaluation! s text))
                 result)))
        %running)))

(define (ide-type s line)
  "(ide-type session line)
Gives the program session runs a line to read: read-line answers it, and read reads from it."
  [s type: line])

(define (ide-interrupt s)
  "(ide-interrupt session)
Stops the evaluation session is running: it waits at a break, with its restarts (abort among them), and the evaluation's result has status error."
  [s interrupt])

(define (ide-close s)
  "(ide-close session)
Ends session and its process."
  [s close])

;;; ---------------------------------------------------------------------------
;;; The record of changes (R-35)

(define %changes '())             ; newest first
(define %log-path #f)

(define (change-time c) "(change-time change)\nWhen it was made, a date and time as text." (vector-ref c 0))
(define (change-session c) "(change-session change)\nThe name of the session that made it." (vector-ref c 1))
(define (change-maker c) "(change-maker change)\nperson or agent." (vector-ref c 2))
(define (change-kind c) "(change-kind change)\nevaluate: an evaluation that defined names." (vector-ref c 3))
(define (change-names c) "(change-names change)\nThe names it defined, strings." (vector-ref c 4))
(define (change-text c) "(change-text change)\nThe text evaluated." (vector-ref c 5))

(define (%record! change)
  (set! %changes (cons change %changes))
  (when %log-path
    (with-output-to-file %log-path
      (lambda () (for-each (lambda (c) (write c) (newline)) (reverse %changes))))))

(define (%record-evaluation! s text)
  (let ((names (map definition-name (guard (e (#t '())) (editor-definitions text)))))
    (unless (null? names)
      (%record! (vector [[[(smalltalk DateAndTime) now] printString] asString]
                        [s name] (ide-session-maker s) 'evaluate names text)))))

(define (ide-changes)
  "(ide-changes)
The changes made through these tools, oldest first: each evaluation that defined names, with when, its session, who made it (person or agent), the names and the text."
  (reverse %changes))

(define (ide-log-to! path)
  "(ide-log-to! path)
From now on the changes are also kept in the file at path, one written record a line, rewritten at each change, so the record outlives a crash. #f stops it."
  (set! %log-path path)
  (when path (%record! (vector [[[(smalltalk DateAndTime) now] printString] asString] "" 'person 'log '() path)))
  path)
