;;; phase-8.2-reader.lisp -- unit tests of the reader written in LISP
;;; (lib/compiler/reader.lisp; specs/phase-8-self-hosting.md step 8.2, AC-2).
;;; The comparison with the Smalltalk reader on the corpus and on every .lisp
;;; file is tests/phase-8.2-reader.st; these test the reader on its own terms.
;;; The built image loads lib/compiler/reader.lisp.
(load "../../lib/test.lisp")

(define (read1 s) (read-from-string s))

;; the error a read raises, as (message position incomplete?)
(define (read-failure s)
  (guard (e (#t (list (error-object-message e) [e position] [e isIncomplete])))
    (read-all s)
    'no-error))

(define-test "AC-2 numbers"
  (check (read-all "42 -3 +7 0 12345678901234567890") '(42 -3 7 0 12345678901234567890))
  (check (read-all "3.14 .5 2. -1e9 1.5e-3") '(3.14 0.5 2.0 -1.0e9 0.0015))
  (check [(read1 "-0.0") signBit] 1)
  (check-true (symbol? (read1 "1e")))
  (check-true (symbol? (read1 "1+"))))

(define-test "AC-2 symbols are interned and case-sensitive"
  (check-true (eq? (read1 "foo") 'foo))
  (check-false (eq? (read1 "Foo") 'foo))
  (check (map symbol->string (read-all "+ - ... ->x set!")) '("+" "-" "..." "->x" "set!")))

(define-test "AC-2 strings and escapes"
  (check (read1 "\"a\\nb\"") "a\nb")
  (check (map char->integer (string->list (read1 "\"\\t\\r\\0\\a\\b\\\\\\\"\""))) '(9 13 0 7 8 92 34))
  (check (read1 "\"\\x41;\\x3bb;\"") "A\x3bb;"))

(define-test "AC-2 characters and booleans"
  (check (read-all "#\\a #\\space #\\newline #\\tab #\\x41 #\\(") (list #\a #\space #\newline #\tab #\A #\())
  (check (char->integer (read1 "#\\null")) 0)
  (check (read-all "#t #true #f #false") '(#t #t #f #f)))

(define-test "AC-2 lists, dotted pairs, abbreviations"
  (check (read1 "(1 (2 3) . 4)") '(1 (2 3) . 4))
  (check-true (null? (read1 "()")))
  (check (read1 "'x") ''x)
  (check (read1 "`(a ,b ,@c)") '(quasiquote (a (unquote b) (unquote-splicing c)))))

(define-test "AC-2 vectors are read-only Arrays"
  (let ((v (read1 "#(1 #(2) \"s\")")))
    (check v #(1 #(2) "s"))
    (check-true (vector? v))
    (check-true [v isReadOnlyObject])))

(define-test "AC-2 brackets read as sends"
  (check (read1 "[a foo]") '(send a foo))
  (check (read1 "[x + 1]") '(send x + 1))
  (check (read1 "[Foo at: 1 put: 2]") '(send (smalltalk Foo) at:put: 1 2)))

(define-test "AC-2 comments"
  (check (read-all "; line\n1 #| a #| nested |# b |# 2 a#|x|#b") '(1 2 a b)))

(define-test "AC-2 datum labels make cycles and sharing"
  (let ((c (read1 "#0=(a b . #0#)")))
    (check (car c) 'a)
    (check-true (eq? c (cdr (cdr c)))))
  (let ((l (read1 "(#0=(1) #0#)")))
    (check-true (eq? (car l) (car (cdr l)))))
  (let ((v (read1 "#0=#(x #0#)")))
    (check-true (eq? v (vector-ref v 1)))
    (check-true [v isReadOnlyObject])))

(define-test "AC-2 source ranges for lists"
  (let* ((r (make-reader "  (define (f x)\n    [x + 1])  'z"))
         (d (reader-next r)))
    (check (reader-source-for r d) "(define (f x)\n    [x + 1])")
    (check (reader-source-for r (car (cdr d))) "(f x)")
    (check (reader-source-for r (car (cdr (cdr d)))) "[x + 1]")
    (check (reader-range-of r d) '(3 . 28))
    (check (reader-datum-start r) 2)
    (check (reader-next r) ''z)
    (check-false (reader-source-for r '(not read here)))
    (check-true (eof-object? (reader-next r)))))

(define-test "AC-2 errors: message, position, incomplete"
  (check (read-failure "(1 2") '("unterminated list" 0 #t))
  (check (read-failure "  \"abc") '("unterminated string" 2 #t))
  (check (read-failure "1)") '("unexpected )" 1 #f))
  (check (read-failure "( . a)") '("bad dotted pair" 2 #f))
  (check (read-failure "#q") '("unknown # syntax: #q" 2 #f))
  (check (read-failure "#|") '("unterminated block comment" 0 #t))
  (check (read-failure "'") '("unexpected end of input" 1 #t))
  (check (read-failure "[a 1]") '("bad message send: brackets are Smalltalk sends; use ( ) for grouping" 0 #f))
  (check (read-failure "#1#") '("unknown datum label #1#" 3 #f))
  (check (read-failure "\"\\q\"") '("unknown string escape" 3 #f))
  (check-error-class (read-all "(") LispReadError))

(define-test "AC-2 read-datum reads one datum from a port and leaves it after"
  (let ((p (open-input-string "(a b) 42 rest")))
    (check (read-datum p) '(a b))
    (check (read-datum p) 42)
    (check (read p) 'rest)
    (check-true (eof-object? (read-datum p)))))

(define-test "AC-2 read-from-string wants exactly one datum"
  (check (read-failure-of (lambda () (read-from-string "   "))) '("read: empty input" #t))
  (check (read-failure-of (lambda () (read-from-string "1 2"))) '("read: more than one datum" #f)))

(define (read-failure-of thunk)
  (guard (e (#t (list (error-object-message e) [e isIncomplete])))
    (thunk)
    'no-error))

(define-test "AC-2 the reader reads its own source"
  (let ((forms (call-with-input-file "lib/compiler/reader.lisp"
                 (lambda (p) (let loop ((acc '()))
                               (let ((d (read-datum p)))
                                 (if (eof-object? d) (reverse acc) (loop (cons d acc)))))))))
    (check-true (> (length forms) 50))
    (check (car (car forms)) 'define)))

(run-tests)
