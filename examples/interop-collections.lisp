; interop-collections.lisp -- Smalltalk's collections, driven from LISP (Phase 7.6)

; An OrderedCollection, filled and queried.
(define langs [OrderedCollection new])
(for-each (lambda (s) [langs add: s]) '("Smalltalk" "Lisp" "Self" "Scheme" "Simula"))
(display [langs size])
(newline)

; LISP procedures are the blocks: select:, collect:, detect:ifNone:, inject:into:.
(display [langs select: (lambda (s) [s beginsWith: "S"])])
(newline)
(display [langs collect: (lambda (s) [s size])])
(newline)
(display [langs detect: (lambda (s) (> [s size] 6)) ifNone: (lambda () "none")])
(newline)
(display [langs inject: 0 into: (lambda (total s) (+ total [s size]))])
(newline)

; Sorting with a LISP comparison.
(display [langs asSortedCollection: (lambda (a b) (< [a size] [b size]))])
(newline)
(display [[langs collect: (lambda (s) [s asLowercase])] asSortedCollection])
(newline)

; A Dictionary used as a table, with a LISP procedure for the missing case.
(define ages [Dictionary new])
[ages at: "Smalltalk" put: 1972]
[ages at: "Lisp" put: 1958]
[ages at: "Scheme" put: 1975]
(display [ages at: "Lisp"])
(newline)
(display [ages at: "Rust" ifAbsent: (lambda () "unknown")])
(newline)
(display (array->list [[ages keys] asSortedCollection: (lambda (a b) (< [ages at: a] [ages at: b]))]))
(newline)

; Sets drop duplicates; intervals count.
(define seen [Set new])
[seen addAll: (list->array '(1 2 2 3 3 3))]
(display [seen size])
(newline)
(display (array->list [[1 to: 10 by: 3] asArray]))
(newline)
