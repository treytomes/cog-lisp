;;; console-prompts.lisp -- the console library's prompts, step 3 of
;;; specs/29-console.md (R-10 to R-12): on a test console's keys, and without a
;;; console, reading lines as from piped input (R-11).
(load "../../lib/test.lisp")
(require 'console)

;; (answer . screen text), with the keys or the input lines given
(define (with-keys keys thunk . options)
  (let* ((answer #f)
         (s (with-test-console (append (list 'events keys 'width 40 'height 20) options)
                               (lambda () (set! answer (thunk))))))
    (cons answer (screen-text s))))
(define (with-lines text thunk)
  (let* ((answer #f) (s (with-test-console (list 'input text 'width 40) (lambda () (set! answer (thunk))))))
    (cons answer (screen-text s))))
(define (lines . ls) (string-join ls (string #\newline)))

;;; --- ask -------------------------------------------------------------------

(define-test "R-10 ask: what is typed, with backspace"
  (check (with-keys '("ab" backspace "c" enter) (lambda () (ask "Name?"))) '("ac" . "Name? ac"))
  (check (car (with-keys '(backspace "x" enter) (lambda () (ask "Name?")))) "x")      ; nothing to delete
  ;; a key with a modifier types nothing
  (check (car (with-keys (list (list 'alt #\a) "b" 'enter) (lambda () (ask "Name?")))) "b"))

(define-test "R-10 ask: a default, shown, for an empty answer"
  (check (with-keys '(enter) (lambda () (ask "Name?" 'default "Ann"))) '("Ann" . "Name? (Ann)"))
  (check (car (with-keys '("Bo" enter) (lambda () (ask "Name?" 'default "Ann")))) "Bo")
  (check (car (with-keys '(enter) (lambda () (ask "Age?" 'default 42)))) "42"))

(define-test "R-10 ask: an empty answer is asked again, unless it is allowed"
  (check (with-keys '(enter "x" enter) (lambda () (ask "Name?"))) (cons "x" (lines "Name?" "an answer is needed" "Name? x")))
  (check (car (with-keys '(enter) (lambda () (ask "Name?" 'allow-empty #t)))) ""))

(define-test "R-10 ask: validate, its message shown before asking again"
  (define (number-please a) (if (string->number a) #t "a number, please"))
  (check (with-keys '("ten" enter "10" enter) (lambda () (ask "Count?" 'validate number-please)))
         (cons "10" (lines "Count? ten" "a number, please" "Count? 10")))
  ;; a validator answering #f has a message of its own
  (check (cdr (with-keys '("x" enter "y" enter) (lambda () (ask "?" 'validate (lambda (a) (string=? a "y"))))))
         (lines "? x" "not a valid answer" "? y")))

(define-test "R-10 ask: a secret is typed as *"
  (check (with-keys '("pw" enter) (lambda () (ask "Password?" 'secret #t))) '("pw" . "Password? **"))
  (check (car (with-keys '("pwx" backspace enter) (lambda () (ask "Password?" 'secret #t)))) "pw"))

(define-test "R-10 ask: markup in the question, and options checked"
  (let ((s (with-test-console '(events ("a" enter)) (lambda () (ask "[bold]Name?[/]")))))
    (check (style-attributes (cdr (screen-cell s 1 1))) '(bold)))
  (check-error (ask "x" 'colour 'red) "ask: unknown option colour"))

;;; --- confirm ---------------------------------------------------------------

(define-test "R-10 confirm: y or n, or Enter for the default"
  (check (with-keys '(#\y) (lambda () (confirm "Go?"))) '(#t . "Go? [y/n] y"))
  (check (with-keys '(#\N) (lambda () (confirm "Go?"))) '(#f . "Go? [y/n] n"))
  (check (with-keys '(enter #\x enter #\y) (lambda () (confirm "Go?"))) '(#t . "Go? [y/n] y"))   ; no default: Enter waits
  (check (with-keys '(enter) (lambda () (confirm "Go?" 'default #t))) '(#t . "Go? [Y/n] y"))
  (check (with-keys '(enter) (lambda () (confirm "Go?" 'default #f))) '(#f . "Go? [y/N] n")))

;;; --- choose ------------------------------------------------------------------

(define colors '(red green blue cyan magenta yellow))

(define-test "R-10 choose: the arrow keys move, Enter chooses; the list goes, the answer stays"
  (check (with-keys '(enter) (lambda () (choose "Pick" colors))) '(red . "Pick red"))
  (check (with-keys '(down down enter) (lambda () (choose "Pick" colors))) '(blue . "Pick blue"))
  (check (car (with-keys '(down up up enter) (lambda () (choose "Pick" colors)))) 'red)          ; not past the top
  (check (car (with-keys '(end down enter) (lambda () (choose "Pick" colors)))) 'yellow)         ; nor the bottom
  (check (car (with-keys '(end home enter) (lambda () (choose "Pick" colors)))) 'red))

(define-test "R-10 choose: a page at a time, with where it is shown"
  (check (car (with-keys '(page-down enter) (lambda () (choose "Pick" colors 'page-size 2)))) 'blue)
  (check (car (with-keys '(end page-up enter) (lambda () (choose "Pick" colors 'page-size 2)))) 'cyan)
  ;; while choosing: the page, the marker, and the place in the list
  (check (screen-text (with-test-console '(width 30 height 10 events (down down))
                        (lambda () (guard (e (#t #f)) (choose "Pick" colors 'page-size 3)))))
         (lines "Pick" "  green" "> blue" "  cyan" "  (3 of 6)")))

(define-test "R-10 choose: the current item highlighted, items shown by display"
  (let ((s (with-test-console '(width 30 height 10 events (down))
             (lambda () (guard (e (#t #f)) (choose "Pick" colors))))))
    (check (screen-line s 3) "> green")
    (check (style-foreground (cdr (screen-cell s 3 3))) 'cyan)
    (check (style-attributes (cdr (screen-cell s 3 3))) '(bold))
    (check (style-foreground (cdr (screen-cell s 3 2))) #f))
  (check (with-keys '(enter) (lambda () (choose "Pick" '(1 2) 'display (lambda (n) (string-append "#" (number->string n))))))
         '(1 . "Pick #1"))
  (check-error (choose "Pick" '()) "choose: no items to choose from"))

(define-test "R-10 choose: a redraw leaves nothing of the last one"
  ;; the cursor goes back over the list and draws it again: nothing doubles
  (check (screen-text (with-test-console '(width 30 height 10 events (down down down up))
                        (lambda () (guard (e (#t #f)) (choose "Pick" '(a b c d))))))
         (lines "Pick" "  a" "  b" "> c" "  d")))

;;; --- choose-many ----------------------------------------------------------------

(define-test "R-10 choose-many: Space marks, Enter answers the marked, in order"
  (check (with-keys '(#\space down down #\space enter) (lambda () (choose-many "Some" '(a b c))))
         '((a c) . "Some a, c"))
  (check (car (with-keys '(down #\space down #\space up #\space enter) (lambda () (choose-many "Some" '(a b c))))) '(c))
  (check (car (with-keys '(enter) (lambda () (choose-many "Some" '(a b c) 'selected '(b))))) '(b))
  (check (screen-text (with-test-console '(width 30 height 10 events (#\space down))
                        (lambda () (guard (e (#t #f)) (choose-many "Some" '(a b))))))
         (lines "Some" "  [x] a" "> [ ] b")))

;;; --- cancelling (R-12) ---------------------------------------------------------

(define-test "R-12 Ctrl+C and Escape cancel, a condition a program can catch"
  (define (cancelled thunk keys) (car (with-keys keys (lambda () (guard (e ((prompt-cancelled? e) 'cancelled)) (thunk))))))
  (check (cancelled (lambda () (ask "x")) '("a" (ctrl #\c))) 'cancelled)
  (check (cancelled (lambda () (ask "x")) '(escape)) 'cancelled)
  (check (cancelled (lambda () (confirm "x")) '((ctrl #\c))) 'cancelled)
  (check (cancelled (lambda () (choose "x" '(a b))) '(down escape)) 'cancelled)
  (check (cancelled (lambda () (choose-many "x" '(a b))) '((ctrl #\c))) 'cancelled)
  (check-false (prompt-cancelled? (guard (e (#t e)) (error "other")))))

(define-test "R-12 the end of the keys is an error, not a hang"
  (check-error (car (with-keys '("ab") (lambda () (ask "x")))) "prompt: no answer: the input ended"))

(define-test "R-21 a list leaves the cursor shown, after Enter and after Escape"
  (let ((out (screen-output (with-test-console '(events (enter)) (lambda () (choose "x" '(a)))))))
    (check-true (string-search out (string (integer->char 27) #\[ #\? #\2 #\5 #\h))))
  (let ((out (screen-output (with-test-console '(events (escape)) (lambda () (guard (e (#t #f)) (choose "x" '(a))))))))
    (check-true (string-search out (string (integer->char 27) #\[ #\? #\2 #\5 #\h)))))

;;; --- without a console: lines, as piped input (R-11) ----------------------------------

(define-test "R-11 ask reads a line"
  (check (with-lines "Ann\n" (lambda () (ask "Name?"))) '("Ann" . "Name?"))
  (check (car (with-lines "\n" (lambda () (ask "Name?" 'default "Bo")))) "Bo")
  (check (with-lines "\nAnn\n" (lambda () (ask "Name?"))) (cons "Ann" (lines "Name?" "an answer is needed" "Name?")))
  (check-error (with-lines "" (lambda () (ask "Name?"))) "prompt: no answer: the input ended"))

(define-test "R-11 confirm reads y, yes, n or no, or an empty line for the default"
  (check (car (with-lines "yes\n" (lambda () (confirm "Go?")))) #t)
  (check (car (with-lines "N\n" (lambda () (confirm "Go?")))) #f)
  (check (car (with-lines "\n" (lambda () (confirm "Go?" 'default #t)))) #t)
  (check (with-lines "maybe\ny\n" (lambda () (confirm "Go?")))
         (cons #t (lines "Go? [y/n]" "answer y or n" "Go? [y/n]"))))

(define-test "R-11 choose reads a number or a name, from a numbered list"
  (check (with-lines "2\n" (lambda () (choose "Pick" '(red green))))
         (cons 'green (lines "Pick" "  1. red" "  2. green" "?")))
  (check (car (with-lines "red\n" (lambda () (choose "Pick" '(red green))))) 'red)
  (check (car (with-lines "9\nzz\n1\n" (lambda () (choose "Pick" '(red green))))) 'red))

(define-test "R-11 choose-many reads numbers or names, by spaces or commas"
  (check (car (with-lines "3, 1\n" (lambda () (choose-many "Some" '(a b c))))) '(a c))
  (check (car (with-lines "b c\n" (lambda () (choose-many "Some" '(a b c))))) '(b c))
  (check (car (with-lines "\n" (lambda () (choose-many "Some" '(a b c))))) '())
  (check (car (with-lines "x\n2\n" (lambda () (choose-many "Some" '(a b c))))) '(b)))

(run-tests)
