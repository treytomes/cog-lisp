; hold.lisp -- keeps the image for six seconds, while beside.lisp runs on it too
; (specs/17-startup-anywhere.md AC-2)
(display "holding")
(newline)
[[(smalltalk Delay) forSeconds: 6] wait]
(display "held")
(newline)
