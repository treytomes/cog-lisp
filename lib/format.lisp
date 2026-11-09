;;; format.lisp -- format, with Common Lisp's directives (specs/format.md)
;;;
;;; Begun in ~/projects/lisp-expert (its format.lisp, the owner's, written with
;;; Claude on the web): the parser and the directive records are kept, under
;;; their names there, so its tests run here unchanged. Finished here: every
;;; parameter and flag takes effect, and the directives with structure exist.
;;;
;;; Loaded by the build after lib/core.lisp and compiled by the seed, so it is
;;; plain code: no generalized set!, nothing from lib/cl.lisp.

;;; --- Directive records ------------------------------------------------------
;;; A directive is a vector, so it can never be mistaken for literal text, which
;;; is always a string. Everything else goes through these accessors.

(define (make-directive char params at? colon? . position)
  "(make-directive char params at? colon? [position])
A parsed format directive: its character, its parameters (numbers, characters, v, # or #f for one left out), its @ and : flags, and where it starts in the control string."
  (vector 'directive char params at? colon? (if (pair? position) (car position) #f)))

(define (directive? x)
  "(directive? x)
True if x is a parsed format directive."
  (and (vector? x) (> (vector-length x) 0) (eq? (vector-ref x 0) 'directive)))

(define (directive-char d) "(directive-char d)\nThe directive character, upper case." (vector-ref d 1))
(define (directive-params d) "(directive-params d)\nThe directive parameters, a list." (vector-ref d 2))
(define (directive-at? d) "(directive-at? d)\nTrue if the directive has the @ flag." (vector-ref d 3))
(define (directive-colon? d) "(directive-colon? d)\nTrue if the directive has the : flag." (vector-ref d 4))
(define (directive-position d) (vector-ref d 5))

;;; --- Errors -------------------------------------------------------------------

;; format: <message> [at position n] in "<control>"
(define (format-error message control position)
  (error (string-append "format: " message
                        (if position (string-append " at position " (number->string position)) "")
                        " in " (with-output-to-string (lambda () (write control))))))

(define (format-ends-inside-directive control)
  (format-error "control string ends inside a directive" control #f))

;;; --- Parsing: the control string into segments ---------------------------------

;; The number that starts at i. Answers (number . index just after it).
(define (format-read-number control i)
  (let ((end (string-length control)))
    (let loop ((i i) (n 0))
      (if (and (< i end) (char-numeric? (string-ref control i)))
          (loop (+ i 1) (+ (* n 10) (digit-value (string-ref control i))))
          (cons n i)))))

;; The parameter that starts at i: a number (with a sign), 'c for a character, v
;; (the next argument), # (the number of arguments left), or nothing. Answers
;; (value . index just after it); the value is #f and the index is i when there
;; is no parameter there.
(define (format-read-parameter control i)
  (let ((end (string-length control)))
    (if (>= i end)
        (format-ends-inside-directive control)
        (let ((c (string-ref control i)))
          (cond ((char-numeric? c) (format-read-number control i))
                ((and (or (eq? c #\-) (eq? c #\+)) (< (+ i 1) end) (char-numeric? (string-ref control (+ i 1))))
                 (let ((n (format-read-number control (+ i 1))))
                   (cons (if (eq? c #\-) (- (car n)) (car n)) (cdr n))))
                ((eq? c #\')
                 (if (>= (+ i 1) end) (format-ends-inside-directive control))
                 (cons (string-ref control (+ i 1)) (+ i 2)))
                ((or (eq? c #\v) (eq? c #\V)) (cons 'v (+ i 1)))
                ((eq? c #\#) (cons 'count (+ i 1)))
                (else (cons #f i)))))))

;; The modifiers and the character of a directive, once its parameters are read.
;; Answers (directive . index just after it).
(define (format-parse-modifiers control i params start)
  (let ((end (string-length control)))
    (let loop ((i i) (at? #f) (colon? #f))
      (if (>= i end)
          (format-ends-inside-directive control)
          (let ((c (string-ref control i)))
            (cond ((eq? c #\@) (loop (+ i 1) #t colon?))
                  ((eq? c #\:) (loop (+ i 1) at? #t))
                  (else (cons (make-directive (char-upcase c) params at? colon? start) (+ i 1)))))))))

;; The directive whose ~ is at start. Answers (directive . index just after it).
(define (format-parse-directive control start)
  (let ((end (string-length control)))
    ;; comma? is #t just after a comma, when one more parameter is due
    (let loop ((i (+ start 1)) (params '()) (comma? #f))
      (let* ((parameter (format-read-parameter control i))
             (value (car parameter))
             (next (cdr parameter)))
        (cond ((and (< next end) (eq? (string-ref control next) #\,))
               (loop (+ next 1) (cons value params) #t))
              ;; the last parameter, written or left out after a comma
              ((or (> next i) comma?)
               (format-parse-modifiers control next (reverse (cons value params)) start))
              (else (format-parse-modifiers control next (reverse params) start)))))))

;; Adds the literal text of control from start up to end, if there is any.
(define (format-add-literal control start end segments)
  (if (< start end) (cons (substring control start end) segments) segments))

(define (format-parse control)
  "(format-parse control)
The segments of a format control string, in order: each stretch of literal text is a string, each ~ directive a directive record."
  (let ((end (string-length control)))
    ;; start is where the literal text that is not yet a segment begins
    (let loop ((i 0) (start 0) (segments '()))
      (cond ((>= i end) (reverse (format-add-literal control start i segments)))
            ((eq? (string-ref control i) #\~)
             (if (= (+ i 1) end) (format-error "control string ends in a lone ~" control i))
             (let ((parsed (format-parse-directive control i)))
               (loop (cdr parsed) (cdr parsed) (cons (car parsed) (format-add-literal control start i segments)))))
            (else (loop (+ i 1) start segments))))))

;;; --- The tree: ~{ ~}, ~[ ~; ~] and ~( ~) grouped with their contents -------------
;;; A node is literal text, a directive, or one of:
;;;   #(iteration directive body closing-directive)
;;;   #(choice directive (clause ...) default-index-or-#f)
;;;   #(case directive body)

(define (format-closer? d) (memv (directive-char d) '(#\} #\] #\) #\;)))

;; The nodes up to a directive whose character is in closers. Answers
;; #(nodes the-closing-directive the-segments-after-it); the closer is #f at the end.
(define (format-group segments closers control)
  (let loop ((segs segments) (acc '()))
    (cond ((null? segs) (vector (reverse acc) #f '()))
          ((string? (car segs)) (loop (cdr segs) (cons (car segs) acc)))
          (else
           (let* ((d (car segs)) (c (directive-char d)))
             (cond ((memv c closers) (vector (reverse acc) d (cdr segs)))
                   ((format-closer? d)
                    (format-error (string-append "~" (string c) " without its opening directive") control (directive-position d)))
                   ((eq? c #\{)
                    (let ((g (format-group-closed (cdr segs) #\} d control)))
                      (loop (vector-ref g 2) (cons (vector 'iteration d (vector-ref g 0) (vector-ref g 1)) acc))))
                   ((eq? c #\()
                    (let ((g (format-group-closed (cdr segs) #\) d control)))
                      (loop (vector-ref g 2) (cons (vector 'case d (vector-ref g 0)) acc))))
                   ((eq? c #\[)
                    (let ((r (format-choice-clauses (cdr segs) d control)))
                      (loop (cdr r) (cons (car r) acc))))
                   (else (loop (cdr segs) (cons d acc)))))))))

;; As format-group, for a closer that must be there: open is the opening directive.
(define (format-group-closed segments closer open control)
  (let ((g (format-group segments (list closer) control)))
    (if (vector-ref g 1)
        g
        (format-error (string-append "~" (string (directive-char open)) " without its closing ~" (string closer))
                      control (directive-position open)))))

;; The clauses of ~[ ... ~; ... ~]. Answers (choice-node . segments after ~]).
;; A clause after ~:; is the default.
(define (format-choice-clauses segments open control)
  (let loop ((segs segments) (clauses '()) (default #f))
    (let ((g (format-group segs '(#\; #\]) control)))
      (if (not (vector-ref g 1))
          (format-error "~[ without its closing ~]" control (directive-position open))
          (let* ((clauses (cons (vector-ref g 0) clauses))
                 (stop (vector-ref g 1)))
            (if (eq? (directive-char stop) #\])
                (cons (vector 'choice open (reverse clauses) default) (vector-ref g 2))
                (loop (vector-ref g 2) clauses (if (directive-colon? stop) (length clauses) default))))))))

(define (format-tree control)
  (let ((g (format-group (format-parse control) '() control)))
    (vector-ref g 0)))

;;; --- Arguments: a vector and a position, for ~* to move in --------------------

(define (format-args lst) (vector (list->vector lst) 0))
(define (format-args-left st) (- (vector-length (vector-ref st 0)) (vector-ref st 1)))
(define (format-next st control d)
  (if (<= (format-args-left st) 0)
      (format-error "too few arguments" control (and d (directive-position d)))
      (let ((x (vector-ref (vector-ref st 0) (vector-ref st 1))))
        (vector-set! st 1 (+ (vector-ref st 1) 1))
        x)))
(define (format-move st n control d)
  (let ((to (+ (vector-ref st 1) n)))
    (if (or (< to 0) (> to (vector-length (vector-ref st 0))))
        (format-error "~* moves past the arguments" control (directive-position d)))
    (vector-set! st 1 to)))
(define (format-rest st)
  (let loop ((i (- (vector-length (vector-ref st 0)) 1)) (acc '()))
    (if (< i (vector-ref st 1)) acc (loop (- i 1) (cons (vector-ref (vector-ref st 0) i) acc)))))

;; Parameter k of d (from 0), or default: v takes the next argument, # the
;; number left; #f (left out) or an argument of #f gives the default.
(define (format-param d k default st control)
  (let loop ((ps (directive-params d)) (k k))
    (if (null? ps)
        default
        (if (> k 0)
            (loop (cdr ps) (- k 1))
            (let ((p (car ps)))
              (cond ((eq? p 'v) (let ((x (format-next st control d))) (if x x default)))
                    ((eq? p 'count) (format-args-left st))
                    (p p)
                    (else default)))))))

;;; --- Output: the port, and whether it is at the start of a line ---------------
;;; ~& needs the column. It is known for what this format writes; when a call
;;; starts, the port counts as at the start of a line.

(define (format-out port) (vector port #t))
(define (format-emit out s)
  (if (> (string-length s) 0)
      (begin
        (write-string s (vector-ref out 0))
        (vector-set! out 1 (eq? (string-ref s (- (string-length s) 1)) #\newline)))))
(define (format-emit-char out c) (format-emit out (string c)))

(define (format-repeat-string s n)
  (let loop ((n n) (acc ""))
    (if (<= n 0) acc (loop (- n 1) (string-append acc s)))))

;; text padded to mincol: minpad padchars, then colinc more at a time; left? pads
;; on the left
(define (format-pad text mincol colinc minpad padchar left?)
  (let loop ((pad minpad))
    (if (< (+ (string-length text) pad) mincol)
        (loop (+ pad (max colinc 1)))
        (let ((fill (make-string pad padchar)))
          (if left? (string-append fill text) (string-append text fill))))))

(define (format-display-string x) (with-output-to-string (lambda () (display x))))
(define (format-write-string x) (with-output-to-string (lambda () (write x))))

;; the digits of integer n in radix, grouped by commachar every interval digits
;; when group?, with a sign when sign? or n is negative
(define (format-integer-string n radix group? commachar interval sign?)
  (let* ((digits (string-upcase (number->string (abs n) radix)))
         (grouped
          (if group?
              (let loop ((i (string-length digits)) (acc ""))
                (if (<= i interval)
                    (string-append (substring digits 0 i) acc)
                    (loop (- i interval)
                          (string-append (string commachar) (substring digits (- i interval) i) acc))))
              digits)))
    (cond ((< n 0) (string-append "-" grouped))
          (sign? (string-append "+" grouped))
          (else grouped))))

;; ~mincol,padchar,commachar,comma-interval D (and B, O, X, nR). The parameters
;; come first: a v among them takes its argument before the directive does.
(define (format-number-directive out d radix first-param st control)
  (let* ((mincol (format-param d first-param 0 st control))
         (padchar (format-param d (+ first-param 1) #\space st control))
         (commachar (format-param d (+ first-param 2) #\, st control))
         (interval (format-param d (+ first-param 3) 3 st control))
         (x (format-next st control d)))
    (format-emit out
                 (format-pad (if (exact-integer? x)
                                 (format-integer-string x radix (directive-colon? d) commachar interval (directive-at? d))
                                 (format-display-string x))   ; like Common Lisp: a non-integer prints as ~A
                             mincol 1 0 padchar #t))))

;; ~w,d,k,overflowchar,padchar F
(define (format-fixed-string x digits)
  (let* ((scaled (round (* (exact (abs x)) (expt 10 digits))))
         (s (number->string scaled))
         (s (if (<= (string-length s) digits)
                (string-append (make-string (- (+ digits 1) (string-length s)) #\0) s)
                s))
         (point (- (string-length s) digits)))
    (string-append (substring s 0 point) "." (substring s point (string-length s)))))

(define (format-float-directive out d st control)
  (let* ((w (format-param d 0 #f st control))
         (digits (format-param d 1 #f st control))
         (k (format-param d 2 0 st control))
         (overflow (format-param d 3 #f st control))
         (padchar (format-param d 4 #\space st control))
         (x (format-next st control d)))
    (if (not (real? x))
        (format-emit out (format-display-string x))
        (let* ((x (* x (expt 10 k)))
               (body (if digits
                         (format-fixed-string x digits)
                         (let ((s (number->string (exact->inexact (abs x)))))
                           (if (eq? (string-ref s 0) #\.) (string-append "0" s) s))))
               (signed (cond ((< x 0) (string-append "-" body))
                             ((directive-at? d) (string-append "+" body))
                             (else body))))
          (format-emit out
                       (cond ((not w) signed)
                             ((and overflow (> (string-length signed) w)) (make-string w overflow))
                             (else (format-pad signed w 1 0 padchar #t))))))))

;; case conversion for ~( ~)
(define (format-capitalize s all-words?)
  (let ((out (open-output-string)))
    (let loop ((i 0) (in-word #f) (first-done #f))
      (if (< i (string-length s))
          (let ((c (string-ref s i)))
            (if (or (char-alphabetic? c) (char-numeric? c))
                (begin
                  (write-char (if (and (not in-word) (or all-words? (not first-done))) (char-upcase c) (char-downcase c)) out)
                  (loop (+ i 1) #t #t))
                (begin (write-char c out) (loop (+ i 1) #f first-done))))
          (get-output-string out)))))

(define (format-convert-case d s)
  (cond ((and (directive-colon? d) (directive-at? d)) (string-upcase s))
        ((directive-colon? d) (format-capitalize s #t))
        ((directive-at? d) (format-capitalize s #f))
        (else (string-downcase s))))

;;; --- Running the tree ------------------------------------------------------------
;;; format-run-nodes answers #f, or escape when ~^ ended the iteration it is in
;;; (all when ~:^ ended an iteration over sublists altogether).

(define (format-run-nodes out nodes st control)
  (let loop ((nodes nodes) (trim #f))
    (if (null? nodes)
        #f
        (let ((node (car nodes)))
          (cond ((string? node)
                 (format-emit out (if trim (format-trim-left node) node))
                 (loop (cdr nodes) #f))
                ((directive? node)
                 (let ((r (format-run-directive out node st control)))
                   (cond ((memq r '(escape all)) r)
                         ((eq? r 'trim) (loop (cdr nodes) #t))
                         (else (loop (cdr nodes) #f)))))
                (else
                 (let ((r (format-run-compound out node st control)))
                   (if (eq? r 'all) r (loop (cdr nodes) #f)))))))))

(define (format-trim-left s)
  (let loop ((i 0))
    (if (and (< i (string-length s)) (memv (string-ref s i) '(#\space #\tab)))
        (loop (+ i 1))
        (substring s i (string-length s)))))

;; one directive; answers #f, escape, all, or trim (the next text loses its
;; leading blanks)
(define (format-run-directive out d st control)
  (let ((c (directive-char d)))
    (case c
      ((#\A #\S)
       (let* ((mincol (format-param d 0 0 st control))
              (colinc (format-param d 1 1 st control))
              (minpad (format-param d 2 0 st control))
              (padchar (format-param d 3 #\space st control))
              (x (format-next st control d))
              (text (if (eq? c #\A) (format-display-string x) (format-write-string x))))
         (format-emit out (format-pad text mincol colinc minpad padchar (directive-at? d)))
         #f))
      ((#\D) (format-number-directive out d 10 0 st control) #f)
      ((#\B) (format-number-directive out d 2 0 st control) #f)
      ((#\O) (format-number-directive out d 8 0 st control) #f)
      ((#\X) (format-number-directive out d 16 0 st control) #f)
      ((#\R)
       (let ((radix (format-param d 0 #f st control)))
         (if (not radix) (format-error "~R in words is not supported yet; give a radix, as in ~16R" control (directive-position d)))
         (format-number-directive out d radix 1 st control)
         #f))
      ((#\C)
       (let ((x (format-next st control d)))
         (if (not (char? x)) (format-error "~C needs a character" control (directive-position d)))
         (format-emit out (if (directive-at? d) (format-write-string x) (string x)))
         #f))
      ((#\F) (format-float-directive out d st control) #f)
      ((#\%) (format-emit out (make-string (format-param d 0 1 st control) #\newline)) #f)
      ((#\&)
       (let ((n (format-param d 0 1 st control)))
         (if (> n 0)
             (begin
               (if (not (vector-ref out 1)) (format-emit-char out #\newline))
               (format-emit out (make-string (- n 1) #\newline))))
         #f))
      ((#\~) (format-emit out (make-string (format-param d 0 1 st control) #\~)) #f)
      ((#\P)
       (if (directive-colon? d) (format-move st -1 control d))
       (let ((one (eqv? (format-next st control d) 1)))
         (format-emit out (if (directive-at? d) (if one "y" "ies") (if one "" "s")))
         #f))
      ((#\*)
       (cond ((directive-at? d) (format-move st (- (format-param d 0 0 st control) (vector-ref st 1)) control d))
             ((directive-colon? d) (format-move st (- (format-param d 0 1 st control)) control d))
             (else (format-move st (format-param d 0 1 st control) control d)))
       #f)
      ((#\?)
       (let ((sub (format-next st control d)))
         (if (not (string? sub)) (format-error "~? needs a control string" control (directive-position d)))
         (if (directive-at? d)
             (format-run-nodes out (format-tree sub) st sub)
             (let ((sub-args (format-next st control d)))
               (if (not (list? sub-args)) (format-error "~? needs a list of arguments" control (directive-position d)))
               (format-run-nodes out (format-tree sub) (format-args sub-args) sub)))
         #f))
      ((#\^)
       (if (= (format-args-left st) 0) (if (directive-colon? d) 'all 'escape) #f))
      ((#\newline)
       ;; ~ at the end of a line: the newline and the next line's leading blanks
       ;; are left out; ~:newline keeps the blanks, ~@newline keeps the newline
       (if (directive-at? d) (format-emit-char out #\newline))
       (if (directive-colon? d) #f 'trim))
      (else (format-error (string-append "unknown directive ~" (string c)) control (directive-position d))))))

(define (format-run-compound out node st control)
  (case (vector-ref node 0)
    ((iteration) (format-run-iteration out node st control))
    ((choice) (format-run-choice out node st control))
    ((case)
     (let* ((d (vector-ref node 1))
            (inner (format-out (open-output-string)))
            (r (format-run-nodes inner (vector-ref node 2) st control)))
       (format-emit out (format-convert-case d (get-output-string (vector-ref inner 0))))
       r))))

;; ~[ ... ~]: by an integer (the parameter, else the next argument); ~:[ by false
;; or true; ~@[ runs its clause, without using the argument, when it is true
(define (format-run-choice out node st control)
  (let* ((d (vector-ref node 1))
         (clauses (vector-ref node 2))
         (default (vector-ref node 3))
         (run (lambda (clause) (format-run-nodes out clause st control))))
    (cond ((directive-colon? d)
           (let ((x (format-next st control d)))
             (if (not (= (length clauses) 2)) (format-error "~:[ needs two clauses" control (directive-position d)))
             (run (if x (car (cdr clauses)) (car clauses)))))
          ((directive-at? d)
           (let ((x (format-next st control d)))
             (if x (begin (format-move st -1 control d) (run (car clauses))) #f)))
          (else
           (let ((n (format-param d 0 #f st control)))
             (let ((n (if n n (format-next st control d))))
               (if (not (exact-integer? n)) (format-error "~[ needs an integer" control (directive-position d)))
               (cond ((and (>= n 0) (< n (length clauses)) (not (eqv? n default)))
                      (run (format-nth clauses n)))
                     (default (run (format-nth clauses default)))
                     (else #f))))))))

(define (format-nth l n) (if (= n 0) (car l) (format-nth (cdr l) (- n 1))))

;; ~{ ... ~}: over a list argument; ~:{ over a list of sublists, ~@{ over the
;; arguments left, ~:@{ over the arguments left, each a sublist. ~n{ at most n
;; times; ~:} at least once. An empty body takes its control string from the
;; next argument.
(define (format-run-iteration out node st control)
  (let* ((d (vector-ref node 1))
         (closing (vector-ref node 3))
         (body-nodes (vector-ref node 2))
         (limit (format-param d 0 #f st control))
         (body (if (null? body-nodes)
                   (let ((sub (format-next st control d)))
                     (if (not (string? sub)) (format-error "~{~} needs a control string" control (directive-position d)))
                     (format-tree sub))
                   body-nodes))
         (at-least-once (directive-colon? closing))
         (sublists? (directive-colon? d))
         (source (if (directive-at? d)
                     st
                     (let ((x (format-next st control d)))
                       (if (not (list? x)) (format-error "~{ needs a list" control (directive-position d)))
                       (format-args x)))))
    (let loop ((count 0))
      (if (and (or (not limit) (< count limit))
               (or (> (format-args-left source) 0) (and at-least-once (= count 0))))
          (if sublists?
              (let ((sub (if (> (format-args-left source) 0) (format-next source control d) '())))
                (if (not (list? sub)) (format-error "~:{ needs a list of lists" control (directive-position d)))
                (let ((r (format-run-nodes out body (format-args sub) control)))
                  (if (eq? r 'all) #f (loop (+ count 1)))))
              (let ((r (format-run-nodes out body source control)))
                (if (memq r '(escape all)) #f (loop (+ count 1)))))
          #f))))

;;; --- format ------------------------------------------------------------------------

;; the whole control string is checked before anything is written
(define (format-run port control args)
  (let ((nodes (format-tree control)))
    (format-run-nodes (format-out port) nodes (format-args args) control)
    #f))

(define (format destination . rest)
  "(format destination control arg ...), (format control arg ...)
Writes control with its ~ directives filled in from the arguments. destination is #f (answer a string), #t (the current output) or a port; with a control string first, as SRFI 28, the answer is a string. Directives, with Common Lisp parameters and flags: ~A display, ~S write (~mincol,colinc,minpad,padcharA; @ pads on the left); ~D ~B ~O ~X and ~nR integers (~mincol,padchar,commachar,intervalD; : groups digits, @ shows the sign); ~w,dF floats; ~C a character (~@C as #\\c); ~% newline, ~& fresh line, ~~ tilde (each takes a count); ~P plural (~:P the previous argument, ~@P y or ies); ~* skip, ~:* back, ~n@* go to argument n; ~{ ~} iteration (~:{ sublists, ~@{ the arguments left, ~^ leaves); ~[ ~; ~] choice (~:; default, ~:[ false and true, ~@[ when true); ~( ~) case (~:( words, ~@( first word, ~:@( upper); ~? a control string and its arguments. v as a parameter takes it from the arguments, # is the number of arguments left."
  (cond ((string? destination)
         (let ((port (open-output-string)))
           (format-run port destination rest)
           (get-output-string port)))
        ((null? rest) (error "format: no control string"))
        ((eq? destination #f)
         (let ((port (open-output-string)))
           (format-run port (car rest) (cdr rest))
           (get-output-string port)))
        ((eq? destination #t)
         (format-run (current-output-port) (car rest) (cdr rest)))
        (else (format-run destination (car rest) (cdr rest)))))
[format category: "Output"]
