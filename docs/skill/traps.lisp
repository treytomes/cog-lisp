;;; traps.lisp -- what a model used to other Lisps gets wrong in cog-lisp
;;; (specs/phase-10-documentation-and-editor.md step 10.7). Each trap is
;;;   (trap "what goes wrong" "the wrong code" outcome "the right code")
;;; where outcome is (error "text of the error") or (answers "what it prints").
;;; tests/lisp/phase-10.7-skill.lisp runs every wrong and every right piece of
;;; code, and checks the outcome; tools/generate-docs.lisp writes them into
;;; SKILL.md. The right code may be #f when an example shows it instead.

(trap "Common Lisp's defun does not exist: define makes procedures"
      "(defun square (x) (* x x))" (error "unbound variable: defun")
      "(define (square x) (* x x))")

(trap "There is no nil: the empty list is '() and false is #f"
      "(display nil)" (error "unbound variable: nil")
      "(display '())")

(trap "The empty list counts as true; only #f is false: test with null?"
      "(display (if '() \"yes\" \"no\"))" (answers "yes")
      "(display (if (null? '()) \"empty\" \"not empty\"))")

(trap "There is no format: build text with string-append and number->string"
      "(display (format #f \"~a\" 42))" (error "unbound variable: format")
      "(display (string-append \"n = \" (number->string 42)))")

(trap "map takes one list (not several)"
      "(display (map + (list 1 2) (list 10 20)))" (error "map: expected 2 arguments, got 3")
      "(display (map (lambda (n) (* n 10)) (list 1 2)))")

(trap "for-each takes one list (not several)"
      "(for-each (lambda (a b) (display (+ a b))) (list 1 2) (list 3 4))" (error "for-each: expected 2 arguments, got 3")
      "(for-each (lambda (a) (display a)) (list 1 2))")

(trap "There is no list-ref, filter, fold, reduce, iota or sort: define them (the helpers example)"
      "(display (list-ref (list 1 2 3) 1))" (error "unbound variable: list-ref")
      #f)

(trap "A string literal cannot be changed: change a copy"
      "(define s \"cat\") (string-set! s 0 #\\b)" (error "string-set!: string is immutable (a literal); copy it first")
      "(define s (string-copy \"cat\")) (string-set! s 0 #\\b)")

(trap "A Smalltalk message is written in brackets, the selector bare (no quote)"
      "(display (send 3 '+ 4))" (error "send: bad selector: (quote +)")
      "(display [3 + 4])")
