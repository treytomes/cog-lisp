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

(trap "map takes one list (not several)"
      "(display (map + (list 1 2) (list 10 20)))" (error "map: expected 2 arguments, got 3")
      "(display (map (lambda (n) (* n 10)) (list 1 2)))")

(trap "for-each takes one list (not several)"
      "(for-each (lambda (a b) (display (+ a b))) (list 1 2) (list 3 4))" (error "for-each: expected 2 arguments, got 3")
      "(for-each (lambda (a) (display a)) (list 1 2))")

(trap "There is no first, second or last: use car, cadr, caddr or list-ref"
      "(display (second (list 1 2 3)))" (error "unbound variable: second")
      "(display (cadr (list 1 2 3)))")

(trap "A string literal cannot be changed: change a copy"
      "(define s \"cat\") (string-set! s 0 #\\b)" (error "string-set!: string is immutable (a literal); copy it first")
      "(define s (string-copy \"cat\")) (string-set! s 0 #\\b)")

(trap "A Smalltalk message is written in brackets, the selector bare (no quote)"
      "(display (send 3 '+ 4))" (error "send: bad selector: (quote +)")
      "(display [3 + 4])")

(trap "A program must print its result with display: a value alone prints nothing"
      "20" (answers "")
      "(display 20)")

(trap "A list written as code is a call: build it with list (or quote it)"
      "(display (1 2 3))" (error "object is not applicable: 1")
      "(display (list 1 2 3))")

(trap "cons in a loop builds a list backwards: use map, or reverse at the end"
      "(define r '()) (for-each (lambda (n) (set! r (cons (* n n) r))) (list 1 2 3)) (display r)" (answers "(9 4 1)")
      "(display (map (lambda (n) (* n n)) (list 1 2 3)))")
