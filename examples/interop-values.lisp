; interop-values.lisp -- the values the two languages see differently (Phase 7.6 section 4.5)

; Smalltalk methods often answer nil for "nothing". It reaches LISP as itself,
; prints as #<nil>, and -- like everything but #f -- counts as true.
(define table [Dictionary new])
[table at: 'one put: 1]
(define missing [table at: 'two ifAbsent: smalltalk-nil])
(display missing)
(newline)
(display (smalltalk-nil? missing))
(newline)
(display (if missing "nil is true in LISP" "nil is false"))
(newline)

; LISP symbols and Smalltalk symbols are different objects.
(define st-sym (smalltalk-symbol 'hello))
(display st-sym)
(newline)
(display (list (symbol? st-sym) (string? st-sym) (symbol? (lisp-symbol st-sym))))
(newline)
(display (eq? 'hello (lisp-symbol st-sym)))
(newline)

; Lists and Smalltalk collections convert explicitly.
(define arr (list->array '(3 1 2)))
(display arr)
(newline)
(display [arr asSortedCollection])
(newline)
(display (array->list [arr reversed]))
(newline)
(display (array->list [[1 to: 5] collect: (lambda (n) (* n n))]))
(newline)

; Any other Smalltalk object prints as #<...>, so it is never mistaken for LISP data.
(display (list (smalltalk OrderedCollection) [3 @ 4] (smalltalk-nil) 'lisp-symbol "a string"))
(newline)
(display (map smalltalk-object? (list [Set new] 42 "s" 'x car (smalltalk-nil))))
(newline)
