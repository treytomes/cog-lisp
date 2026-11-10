;; console.lisp -- styled text, measured and wrapped, and a screen to test it on
;;
;; (require 'console) brings in the console library (specs/29-console.md), in
;; the manner of .NET's Spectre.Console. Markup such as "[bold green]done[/]"
;; writes its text in its styles, with the colors the terminal has: to a pipe or
;; a file there are none, so this example's output is plain text. Text is
;; measured in cells, as a terminal shows it, and wrapped at the console's width.
;;
;; with-test-console runs a piece of a program against a pretend terminal of a
;; given size, and answers its screen: the text on it, and the style of each
;; cell. That is how a program that draws on a terminal is tested without one.
;; Inside it, a program's output goes to that screen; the keys it reads come
;; from a list, and arrive as events.
(require 'console)

(print-markup-line "[bold green]done[/] in [blue]3 s[/], with [[brackets]] shown as they are")
(with-console '(width 30)
  (lambda () (render "Text is wrapped at the console's width, here thirty cells, at its spaces.")))
(display (list (text-width "abc") (text-width "漢字"))) (newline)

;; a screen 12 cells wide: what was drawn, and how
(define screen
  (with-test-console '(width 12 height 4)
    (lambda () (print-markup-line "[red on white]warning[/] two") (render "wraps at twelve cells"))))
(display (screen-text screen)) (newline)
(display (style-foreground (cdr (screen-cell screen 1 1)))) (newline)

;; keys, as a terminal would send them, read as events
(define keys '())
(with-test-console '(events (down down enter (ctrl #\c)))
  (lambda ()
    (let loop ()
      (let ((e (read-event)))
        (if (not (eq? (event-kind e) 'eof))
            (begin (set! keys (cons (list (or (event-key e) (event-char e)) (event-modifiers e)) keys))
                   (loop)))))))
(for-each (lambda (k) (write k) (newline)) (reverse keys))
