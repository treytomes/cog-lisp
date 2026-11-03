; interop-send.lisp -- sending messages to Smalltalk objects (Phase 7.6 section 4)

; send compiles to a real Smalltalk message send. The selector is written as in
; Smalltalk: unary, binary, or keyword.
(display (send "cog-lisp" size))                 ; unary: 8
(newline)
(display (send 3 + 4))                           ; binary: 7
(newline)
(display (send 7 between:and: 1 10))             ; keyword: #t
(newline)

; Brackets read as send, one message per pair, and read like Smalltalk.
(display ["hello" asUppercase])
(newline)
(display ["cog-lisp" reversed])
(newline)
(display [[3 @ 4] + 1])                          ; a Point
(newline)

; LISP strings and numbers are Smalltalk strings and numbers: nothing is converted.
(define greeting "Hello, Smalltalk")
(display [greeting copyReplaceAll: "Smalltalk" with: "cog-lisp"])
(newline)
(display [[2 raisedTo: 100] printStringBase: 16])    ; a big integer, in hex
(newline)

; Smalltalk globals: (smalltalk Name), or a capitalized receiver in brackets.
(define coll [OrderedCollection new])
[coll add: 3]
[coll add: 1]
[coll add: 2]
(display coll)
(newline)
(display [coll inject: 0 into: +])               ; a LISP procedure as the block
(newline)
(display (send (smalltalk Character) value: 955))
(newline)

; Dynamic sends, for selectors computed while the program runs.
(define pick (smalltalk-selector "copyFrom:to:"))
(display (smalltalk-send "interop" pick 1 5))
(newline)
(display (smalltalk-send 12 'gcd: 18))
(newline)
