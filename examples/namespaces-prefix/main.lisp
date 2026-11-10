; namespaces-prefix/main.lisp -- two libraries with the same name in them
;
; text.lisp and engine.lisp both export a rule: text's draws a line, engine's
; makes an inference rule. Without namespaces the one loaded last would replace
; the other for everyone. Here each is its library's own (text:rule and
; engine:rule), and this file chooses how to see them: text's unqualified, and
; engine's through a prefix, (require "engine.lisp" 'prefix 'en:), which brings
; every export in as en: followed by its name. The prefix is this file's choice;
; another file can pick another, or none.
;
; This program then defines a rule of its own, under another name it chose.
; Defining rule itself would be an error, since this file imported text's rule
; under that name (see namespaces-conflicts).

(require "text.lisp")
(require "engine.lisp" 'prefix 'en:)

(display (rule 10)) (newline)                          ; text:rule
(display (en:rule '(mortal ?x) '(man ?x))) (newline)   ; engine:rule
(display (text:rule 3)) (newline)                      ; full names work too
(display (engine:rule '(a) '(b))) (newline)

(define (house-rule n) (string-append "house " (number->string n)))
(display (house-rule 1)) (newline)
