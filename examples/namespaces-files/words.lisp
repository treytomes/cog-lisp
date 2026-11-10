; words.lisp -- a library that requires a library of its own
(library words (export first-word))
(require 'cl)                              ; this library's import, not its loader's

(define (first-word s) (first (string-split s #\space)))
