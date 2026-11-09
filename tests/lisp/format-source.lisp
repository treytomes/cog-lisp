;;; format-source.lisp -- the source formatter (specs/formatter.md AC-1, AC-2)
(load "../../lib/test.lisp")
(require 'format-source)

(define (lines . ls) (apply string-append (map (lambda (l) (string-append l "\n")) ls)))
(define T "\t")
(define (tabs n) (if (= n 0) "" (string-append T (tabs (- n 1)))))

(define-test "a form with nothing that must break stays on one line"
  (check (format-source "(+   a\n  b)") (lines "(+ a b)"))
  (check (format-source "(f (g x) (h (i y)))") (lines "(f (g x) (h (i y)))"))
  (check (format-source "(if (null? x) 0 (car x))") (lines "(if (null? x) 0 (car x))"))
  (check (format-source "(map (lambda (x) (* x x)) xs)") (lines "(map (lambda (x) (* x x)) xs)"))
  (check (format-source "(define x (make-hash-table))") (lines "(define x (make-hash-table))")))

(define-test "a define of a procedure breaks: header on the first line, ) on its own"
  (check (format-source "(define (square x) (* x x))")
         (lines "(define (square x)" (string-append T "(* x x)") ")"))
  (check (format-source "(define (f x) \"Doc.\" (g x))")
         (lines "(define (f x)" (string-append T "\"Doc.\"") (string-append T "(g x)") ")")))

(define-test "a form holding a body form breaks; its own simple parts stay whole"
  (check (format-source "(if ok (let ((y 1)) y) 0)")
         (lines "(if ok"
                (string-append T "(let ((y 1))") (string-append (tabs 2) "y") (string-append T ")")
                (string-append T "0")
                ")")))

(define-test "cond: one clause a line; a clause that breaks keeps its test on its first line"
  (check (format-source "(cond ((null? l) 0) (else (+ 1 (f (cdr l)))))")
         (lines "(cond" (string-append T "((null? l) 0)") (string-append T "(else (+ 1 (f (cdr l))))") ")"))
  (check (format-source "(cond (a (let ((x 1)) x)))")
         (lines "(cond"
                (string-append T "(a")
                (string-append (tabs 2) "(let ((x 1))") (string-append (tabs 3) "x") (string-append (tabs 2) ")")
                (string-append T ")")
                ")")))

(define-test "let's bindings: one line when each is, else one a line"
  (check (format-source "(let* ((a (car x)) (b (f (g a)))) (list a b))")
         (lines "(let* ((a (car x)) (b (f (g a))))" (string-append T "(list a b)") ")"))
  (check (format-source "(let ((f (lambda (x) (let ((y x)) y))) (n 1)) (f n))")
         (lines "(let ("
                (string-append (tabs 2) "(f")
                (string-append (tabs 3) "(lambda (x)")
                (string-append (tabs 4) "(let ((y x))") (string-append (tabs 5) "y") (string-append (tabs 4) ")")
                (string-append (tabs 3) ")")
                (string-append (tabs 2) ")")
                (string-append (tabs 2) "(n 1)")
                (string-append T ")")
                (string-append T "(f n)")
                ")")))

(define-test "a named let keeps its name and bindings on the first line"
  (check (format-source "(let loop ((i 0)) (when (< i 3) (loop (+ i 1))))")
         (lines "(let loop ((i 0))" (string-append T "(when (< i 3) (loop (+ i 1)))") ")")))

(define-test "comments keep their place: on a line of their own, or at a line's end"
  (check (format-source "; top\n(define x 1) ; trailing\n(define (f)\n  ;; inside\n  1)")
         (lines "; top" "(define x 1) ; trailing" "(define (f)" (string-append T ";; inside") (string-append T "1") ")"))
  (check (format-source "#| a\n block |# (f x)") (lines "#| a\n block |#" "(f x)"))
  (check (format-source "(define (f) ; why\n  1)") (lines "(define (f) ; why" (string-append T "1") ")")))

(define-test "blank lines: two at most between top-level forms, one inside a form"
  (check (format-source "(a)\n\n\n\n\n(b)") (lines "(a)" "" "" "(b)"))
  (check (format-source "(a)\n(b)") (lines "(a)" "(b)"))
  (check (format-source "(define (f)\n  (g)\n\n\n  (h))")
         (lines "(define (f)" (string-append T "(g)") "" (string-append T "(h)") ")")))

(define-test "tokens come out as they went in: strings, characters, brackets, quotes"
  (check (format-source "(display \"a ; (b) \\\" c\")") (lines "(display \"a ; (b) \\\" c\")"))
  (check (format-source "(list #\\( #\\) #\\space #\\;)") (lines "(list #\\( #\\) #\\space #\\;)"))
  (check (format-source "(display [obj   at: (car  x)  put: 3])") (lines "(display [obj   at: (car  x)  put: 3])"))
  (check (format-source "(define v '(a  (b c) #(1 2)  `(d ,e ,@f)))") (lines "(define v '(a (b c) #(1 2) `(d ,e ,@f)))")))

(define-test "spaces instead of tabs"
  (check (format-source "(define (f) 1)" 'spaces 2) (lines "(define (f)" "  1" ")"))
  (check (format-source "(define (f) (let ((x 1)) x))" 'spaces 3)
         (lines "(define (f)" "   (let ((x 1))" "      x" "   )" ")")))

(define-test "formatting its own output changes nothing"
  (let ((once (format-source "(define (f x) ; c\n (cond ((a) (let ((y 1)) y)) (else 2)))\n\n\n\n(g)")))
    (check (format-source once) once)))

(define-test "text that does not read is an error naming the line, and nothing is answered"
  (check-error (format-source "(define (f x)\n  (g x)") "format-source: a ( that is never closed (line 1)")
  (check-error (format-source "(a)\n(b))") "format-source: a ) with no ( (line 2)")
  (check-error (format-source "(a \"unclosed)") "format-source: an unterminated string")
  (check-error (format-source "(a ')") "format-source: a quote with nothing after it"))

(define-test "documented"
  (check-true (string? (documentation 'format-source))))

;; AC-2: every .lisp file in this repository keeps its tokens (format-source
;; checks that itself), is idempotent, and reads back the same forms.
(define root [[[[(current-load-path) asFileReference] parent] parent] parent])
(define (written-forms text)
  (let ((port (open-input-string text)))
    (with-output-to-string
      (lambda ()
        (let loop ()
          (let ((d (guard (e (#t (list 'unreadable (error-object-message e)))) (read port))))
            (unless (eof-object? d) (write d) (newline) (if (pair? d) (if (eq? (car d) 'unreadable) #f (loop)) (loop)))))))))
(define-test "every .lisp file of lib/, examples/, tests/ and tools/: tokens, forms and idempotence (AC-2)"
  (for-each
   (lambda (dir)
     (for-each
      (lambda (ref)
        (let* ((text [ref contents])
               (once (format-source text)))
          (check-true (and (string=? (format-source once) once) [ref basename]))
          (check-true (and (string=? (written-forms text) (written-forms once)) [ref basename]))))
      (vector->list [[root / dir] allChildrenMatching: "*.lisp"])))
   '("lib" "examples" "tests" "tools")))

(run-tests)
