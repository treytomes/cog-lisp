; namespaces-private/main.lisp -- what a library keeps to itself
;
; counter.lisp exports next! and a macro, but not its state (count) or its
; helper (%label). An import never brings in a name that is not exported, so
; here count means nothing and the program cannot depend on it by accident.
; A private name still has a full name, counter:count, which works from
; anywhere: for a test, a debugger, or a macro that needs it. Privacy is about
; what an import brings in, not a lock.
;
; The library's macros show the two kinds. tally is hygienic (syntax-rules): its
; template calls the private %label, and the expansion means counter's %label
; even here, where %label is not imported. note is a define-macro, which is
; not hygienic: its expansion is plain symbols, read in the file where the
; macro is used, so it names the helper by its full name, counter:%label.

(require "counter.lisp")

(next!) (next!)
(display (next!)) (newline)                       ; 3: counter's count, through next!
(display (tally 'apples)) (newline)               ; hygienic: uses the private %label
(display (note 'pears)) (newline)                 ; define-macro: writes counter:%label

(display (guard (e (#t (error-object-message e))) count)) (newline)
(display counter:count) (newline)                 ; the full name reaches it
(display (counter:%label 'x)) (newline)
