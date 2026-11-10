;; console-prompts.lisp -- asking, confirming and choosing
;;
;; ask reads an answer, with a default, a check (validate) and secret typing;
;; confirm a yes or no; choose one item from a list with the arrow keys and
;; Enter, and choose-many several, Space marking each. On a terminal they read
;; keys; Ctrl+C or Escape cancels, a condition prompt-cancelled? tells, and the
;; terminal is always left as it was.
;;
;; Without a terminal, when the input is piped or a file, each reads a line
;; instead: the answer, or an item's number or name. So a program that asks can
;; be run from a script. Here a test console stands in for both: once with keys,
;; once with lines of input, and its screen shows what the person would see.
(require 'console)

;; with keys: a, b, backspace, c, Enter; then down, down, Enter
(define answers '())
(define screen
  (with-test-console '(width 40 events ("ab" backspace "c" enter down down enter))
    (lambda ()
      (set! answers (list (ask "Your name?") (choose "Favorite color" '(red green blue)))))))
(write answers) (newline)
(display (screen-text screen)) (newline) (newline)

;; with lines of input, as from a pipe: a number is the item at that place
(define piped
  (with-test-console '(width 40 input "\nAnn\nyes\n2\n")
    (lambda ()
      (set! answers (list (ask "Your name?" 'default "Bo")
                          (ask "Your name?")
                          (confirm "Continue?")
                          (choose "Size" '(small medium large)))))))
(write answers) (newline)
(display (screen-text piped)) (newline)
