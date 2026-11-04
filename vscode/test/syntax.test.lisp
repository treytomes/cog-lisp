; SYNTAX TEST "source.cog-lisp" "cog-lisp grammar"

(define (square x) (* x x))
;^^^^^^ keyword.control.definition.cog-lisp
;        ^^^^^^ entity.name.function.cog-lisp
;               ^ variable.other.cog-lisp

(define-macro (swap! a b) `(set! ,a ,b))
;^^^^^^^^^^^^ keyword.control.definition.cog-lisp
;              ^^^^^ entity.name.function.cog-lisp
;                         ^ keyword.operator.quote.cog-lisp
;                           ^^^^ keyword.control.special-form.cog-lisp
;                                ^ keyword.operator.quote.cog-lisp

(if (lambda (n) n) 'yes "a \"str\" (x)")
;^^ keyword.control.special-form.cog-lisp
;    ^^^^^^ keyword.control.special-form.cog-lisp
;                  ^ keyword.operator.quote.cog-lisp
;                       ^^^^^^^^^^^^^^^ string.quoted.double.cog-lisp
;                          ^^ constant.character.escape.cog-lisp

(cond ((> n 0) #t) (else #f))
;^^^^ keyword.control.macro.cog-lisp
;              ^^ constant.language.boolean.cog-lisp
;                   ^^^^ keyword.control.macro.cog-lisp

(list 42 -1.5e3 .5 x1 1+ #\a #\space #\x41)
;     ^^ constant.numeric.cog-lisp
;        ^^^^^^ constant.numeric.cog-lisp
;               ^^ constant.numeric.cog-lisp
;                  ^^ variable.other.cog-lisp
;                     ^^ variable.other.cog-lisp
;                        ^^^ constant.character.cog-lisp
;                            ^^^^^^^ constant.character.cog-lisp
;                                    ^^^^^ constant.character.cog-lisp

#| a block comment #| nested |# still comment |# (defun f () 1)
;^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ comment.block.cog-lisp
;                                                 ^^^^^ keyword.control.definition.cog-lisp
;                                                       ^ entity.name.function.cog-lisp

(let* ((v 1)) v) ; a comment (not code)
;^^^^ keyword.control.macro.cog-lisp
;                ^^^^^^^^^^^^^^^^^^^^^^ comment.line.semicolon.cog-lisp

(define c [OrderedCollection new])
;         ^ punctuation.section.brackets.begin.cog-lisp
;          ^^^^^^^^^^^^^^^^^ entity.name.type.class.cog-lisp
;                               ^ punctuation.section.brackets.end.cog-lisp

[d at: 1 put: "x"]
;  ^^^ entity.name.function.selector.cog-lisp
;      ^ constant.numeric.cog-lisp
;        ^^^^ entity.name.function.selector.cog-lisp

(send d at:put: k v) (smalltalk Set)
;^^^^ keyword.control.special-form.cog-lisp
;       ^^^^^^^ entity.name.function.selector.cog-lisp
;                     ^^^^^^^^^ keyword.control.special-form.cog-lisp
;                               ^^^ entity.name.type.class.cog-lisp

(guard (e (#t 0)) (restart-case (f) (use-value (v) v)))
;^^^^^ keyword.control.macro.cog-lisp
;                  ^^^^^^^^^^^^ keyword.control.macro.cog-lisp

(define v #(1 2))
;         ^^ punctuation.section.vector.begin.cog-lisp
;           ^ constant.numeric.cog-lisp
