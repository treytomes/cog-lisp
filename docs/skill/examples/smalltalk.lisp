;; smalltalk.lisp -- send Smalltalk messages: [receiver selector argument ...]
(display [3 + 4]) (newline)
(display ["hello" asUppercase]) (newline)
(display ["hello world" copyReplaceAll: "world" with: "there"]) (newline)
(define coll [OrderedCollection new])
[coll add: 3]
[coll add: 5]
(display [coll size]) (newline)
(display [coll inject: 0 into: +]) (newline)   ; a LISP procedure as the block
