;;; terminal-check.lisp -- the console library on a real Unix terminal
;;; (specs/29-console.md AC-4, AC-5), run by tests/console/linux-check.sh inside
;;; script(1), which pipes in: down, x, Ctrl+Left, then (after a pause) Escape,
;;; then Enter; then a, b, backspace, c, Enter; down, Enter; Ctrl+C. Its own output is the terminal, so it writes its checks to the
;;; file CHECK_LOG names.
(require 'console)

(define check-log (open-output-file (get-environment-variable "CHECK_LOG")))
(define pass 0)
(define total 0)
(define (check name ok)
  (set! total (+ total 1))
  (if (eq? ok #t) (set! pass (+ pass 1)))
  (display (if (eq? ok #t) "  PASS  " "  FAIL  ") check-log) (display name check-log) (newline check-log))

(display "== cog-lisp : the console library on a Unix terminal (specs/29-console.md AC-4, AC-5) ==" check-log)
(newline check-log)
(define caps (console-capabilities))
(check "R-1 a console: a terminal, interactive, its size"
       (and (hash-table-ref caps 'terminal?) (hash-table-ref caps 'interactive?)
            (= (hash-table-ref caps 'width) 100) (= (hash-table-ref caps 'height) 30)))
(check "R-2 its colors from TERM and COLORTERM (xterm-256color)" (eq? (hash-table-ref caps 'colors) '256))
(print-markup-line "[red]RED[/]")
(check "R-19 down arrives as down" (key-event? (read-event 5000) 'down))
(check "R-19 x arrives as x" (key-event? (read-event 2000) #\x))
(check "R-19 Ctrl+Left arrives as left with ctrl" (key-event? (read-event 2000) 'left 'ctrl))
(check "R-19 Escape alone arrives as escape" (key-event? (read-event 5000) 'escape))
(check "R-19 Enter arrives as enter" (key-event? (read-event 5000) 'enter))
(check "R-20 with nothing typed, read-event answers #f after its timeout" (not (read-event 100)))
(check "AC-5 raw mode is left after read-event" (not (%terminal-raw?)))
(guard (e (#t #f)) (with-raw-mode (lambda () (with-raw-mode (lambda () (error "stop"))))))
(check "AC-5 and after an error in nested raw mode" (not (%terminal-raw?)))
;; step 3, the prompts: a, b, backspace, c, Enter; down, Enter; Ctrl+C
(check "R-10 ask answers what was typed, with a backspace" (equal? (ask "Name?") "ac"))
(check "R-10 choose answers the item the arrows reached" (eq? (choose "Pick" '(red green blue)) 'green))
(check "R-12 Ctrl+C in a prompt is a condition" (guard (e ((prompt-cancelled? e) #t)) (ask "Again?") #f))
(check "AC-5 raw mode is left after the prompts, Ctrl+C included" (not (%terminal-raw?)))
(display "== RESULT: " check-log) (display pass check-log) (display "/" check-log) (display total check-log) (display " checks passed ==" check-log)
(newline check-log)
(close-port check-log)
