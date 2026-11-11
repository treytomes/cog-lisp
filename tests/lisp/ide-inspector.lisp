;;; ide-inspector.lisp -- looking into a value, step 4b of specs/34-morphic-ide.md
;;; (R-22 to R-24, R-32, R-33; AC-4): each kind of value's views as data, the
;;; evaluator with it bound, and the built-ins inspect and browse with no world to
;;; open windows in (they write instead). No window is opened.
(load "../../lib/test.lisp")
(require 'ide)

(define (titles v) (map (lambda (view) (vector-ref view 0)) (ide-views v)))
(define (rows v title)
  (vector-ref (find (lambda (view) (string=? (vector-ref view 0) title)) (ide-views v)) 1))
(define (labels v title) (map (lambda (r) (vector-ref r 0)) (rows v title)))
(define (row v title label) (find (lambda (r) (string=? (vector-ref r 0) label)) (rows v title)))
(define (written v title label) (vector-ref (row v title label) 1))
(define (part v title label) (vector-ref (row v title label) 2))
(define (has? text part) (if (string-search text part) #t #f))
(define (quietly thunk)                       ; thunk's value, what it writes kept from the output
  (let ((v #f)) (with-output-to-string (lambda () (set! v (thunk)))) v))

(define-test "R-22 a list: its elements numbered and written, each itself; an improper one's rest"
  (let ((l '(1 (2 3) "x")))
    (check (titles l) '("List" "Value"))
    (check (labels l "List") '("1" "2" "3"))
    (check (map (lambda (r) (vector-ref r 1)) (rows l "List")) '("1" "(2 3)" "\"x\""))
    (check-true (eq? (part l "List" "2") (cadr l))))                 ; the part itself, to inspect
  (check (labels '(1 2 . 3) "List") '("1" "2" "rest"))
  (check (written '(1 2 . 3) "List" "rest") "3"))

(define-test "R-22 a vector and a string: their parts from 0"
  (check (labels (vector 'a 'b) "Vector") '("0" "1"))
  (check (written (vector 'a "b") "Vector" "1") "\"b\"")
  (check (labels "hi" "String") '("length" "0" "1"))
  (check (written "hi" "String" "1") "#\\i"))

(define-test "R-22 a symbol: its name, kind, value and documentation"
  (check (labels 'car "Symbol") '("name" "kind" "value" "documentation"))
  (check (part 'car "Symbol" "kind") 'primitive)
  (check-true (eq? (part 'car "Symbol" "value") car))
  (check (labels 'no-such-name-here "Symbol") '("name" "kind"))
  (check (part 'no-such-name-here "Symbol" "kind") 'unbound)
  (check (labels 'if "Symbol") '("name" "kind" "documentation")))

(define-test "R-22 a procedure: its name, documentation, source, file and callers"
  (check (labels ide:ide-close "Procedure") '("name" "documentation" "source" "file" "callers" "kind"))
  (check (part ide:ide-close "Procedure" "name") 'ide:ide-close)
  (check-true (has? (part ide:ide-close "Procedure" "file") "ide.lisp"))
  (check-true (and (memq 'ide:ide-load-file (part ide:ide-close "Procedure" "callers")) #t))
  (check (part car "Procedure" "kind") 'primitive)
  (check (car (labels (lambda (x) x) "Procedure")) "name"))

(define-test "R-22 a macro, a hash table, a unit, a condition, a number"
  (check (car (titles (%value-of-macro))) "Macro")
  (let ((h (make-hash-table equal?)))
    (hash-table-set! h "b" 2)
    (hash-table-set! h "a" 1)
    (check (labels h "Hash table") '("\"a\"" "\"b\""))
    (check (part h "Hash table" "\"b\"") 2))
  (let ((u [(smalltalk LispUnit) libraryNamed: 'ide]))
    (check (labels u "Unit") '("library" "path" "exports" "imports"))
    (check (part u "Unit" "library") 'ide)
    (check-true (and (memq 'ide-views (part u "Unit" "exports")) #t)))
  (let ((c (guard (e (#t e)) (error "it broke" 1 2))))
    (check (labels c "Condition") '("report" "message" "irritants"))
    (check (part c "Condition" "message") "it broke")
    (check (part c "Condition" "irritants") '(1 2)))
  (check (titles 42) '("Value"))
  (check (written 42 "Value" "class") "SmallInteger"))

(define (%value-of-macro) [[(smalltalk LispEnvironment) default] lookup: 'unless])

(define-test "R-23 the evaluator: LISP, it bound to the value"
  (check (ide-evaluate-with-it '(1 2 3) "(car (cdr it))") 2)
  (check (ide-evaluate-with-it 5 "(define y (* it 2)) (+ y 1)") 11)
  (check-error (ide-evaluate-with-it 5 "(car it)") "car"))

(define-test "R-24 inspect with no world: the views written, the value answered"
  (let* ((answer #f)
         (out (with-output-to-string (lambda () (set! answer (inspect '(a b)))))))
    (check answer '(a b))
    (check out "List\n  1: a\n  2: b\nValue\n  written: (a b)\n  class: LispCons\n")))

(define-test "browse: the original source's place, opened or (with no world) written"
  (let* ((answer #f)
         (out (with-output-to-string (lambda () (set! answer (browse car))))))
    (check answer '(smalltalk "LispPrimitives class" "installListsInto:"))
    (check-true (has? out "car: a primitive, written in Smalltalk, in LispPrimitives class>>installListsInto:\n[:p | p car]")))
  (let* ((answer #f)
         (out (with-output-to-string (lambda () (set! answer (browse 'filter))))))
    (check-true (string-suffix? "core.lisp" (car answer)))
    (check (substring (car (ide-read-file (car answer))) (cadr answer) (+ (cadr answer) 15)) "(define (filter")
    (check-true (has? out "core.lisp:")))
  (check-true (string-suffix? "compiler.lisp" (car (quietly (lambda () (browse 'if))))))   ; a special form
  (check (quietly (lambda () (browse filter))) (quietly (lambda () (browse 'filter))))    ; by its value, as by its name
  (check-false (browse 'no-such-name-here)))

(define-test "inspect and browse are built in, documented under The system"
  (check (documentation-category 'inspect) "The system")
  (check (documentation-category 'browse) "The system")
  (check-true (string-prefix? "(browse name-or-value)" (documentation 'browse))))

(run-tests)
