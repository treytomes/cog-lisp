;;; console-core.lisp -- the console library's core, step 1 of specs/29-console.md:
;;; capabilities, styles, markup, measuring, lines, regions, events, modes and
;;; the test console (R-1 to R-6, R-15 to R-23), on test consoles of several
;;; widths and color settings (AC-2).
(load "../../lib/test.lisp")
(require 'console)

(define esc (string (integer->char 27)))
(define (written thunk . options) (screen-output (with-test-console options thunk)))
(define (shown thunk . options) (screen-text (with-test-console options thunk)))

;;; --- the console (R-1, R-2) --------------------------------------------------

(define-test "R-1 the capabilities, as a hash table"
  (let ((caps (console-capabilities)))
    (for-each (lambda (k) (check-true (hash-table-contains? caps k)))
              '(terminal? colors unicode? interactive? width height))
    ;; the suites run with a pipe for output: no terminal, no colors
    (check (hash-table-ref caps 'terminal?) #f)
    (check (hash-table-ref caps 'colors) 'none)))

(define-test "R-2 with-console overrides, and gives the old ones back"
  (with-console '(width 33 colors 256)
    (lambda ()
      (check (console-width) 33)
      (check (hash-table-ref (console-capabilities) 'colors) '256)))
  (check-false (= (console-width) 33))
  (check-error (with-console '(width) (lambda () 1)) "the option has no value"))

;;; --- styles and markup (R-3 to R-5) ------------------------------------------

(define-test "R-5 styles are values"
  (let ((s (style 'bold 'red '(on blue))))
    (check (style-foreground s) 'red)
    (check (style-background s) 'blue)
    (check (style-attributes s) '(bold)))
  (check (style-foreground (style "#ff8800")) '(rgb 255 136 0))
  (check (style-foreground (style "rgb(1,2,3)")) '(rgb 1 2 3))
  (check (style-foreground (style "color(208)")) 208)
  (check (style-link (style "underline link=https://example.com")) "https://example.com")
  ;; later parts win
  (check (style-foreground (style 'red 'green)) 'green)
  (check-error (style 'sparkly) "style: unknown style sparkly")
  (check-error (style "red on") "on needs a color"))

(define-test "R-4 markup: tags nest, [/] closes the innermost, [[ and ]] escape"
  (check (written (lambda () (print-markup "[bold]a[red]b[/]c[/]d")))
         (string-append esc "[1ma" esc "[0m" esc "[1;31mb" esc "[0m" esc "[1mc" esc "[0md"))
  (check (shown (lambda () (print-markup-line "[[x]] and ]]"))) "[x] and ]")
  (check (shown (lambda () (print-markup (markup-escape "a[b]c")))) "a[b]c"))

(define-test "R-4 markup errors name their position"
  (check-error (print-markup "ab[/]") "markup: [/] closes no tag at 3")
  (check-error (print-markup "a [bold") "markup: a [ that is never closed: write [[ for one at 3")
  (check-error (print-markup "x]y") "markup: a ] that closes nothing: write ]] for one at 2")
  (check-error (print-markup "[sparkly]x") "markup: unknown style sparkly at 1")
  (check-error (print-markup "[]x") "markup: an empty tag at 1"))

(define-test "R-3 to a pipe there are no escape codes; and each color setting writes its own"
  (check (with-output-to-string (lambda () (print-markup "[red]r[/]"))) "r")   ; this suite's own output is a pipe
  (check (written (lambda () (print-markup "[red]r[/]")) 'colors 'none) "r")
  (check (written (lambda () (print-markup "[#ff0000]r[/]")) 'colors '16) (string-append esc "[91mr" esc "[0m"))
  (check (written (lambda () (print-markup "[#ff0000]r[/]")) 'colors '256) (string-append esc "[38;5;9mr" esc "[0m"))
  (check (written (lambda () (print-markup "[#ff0000]r[/]")) 'colors 'truecolor) (string-append esc "[38;2;255;0;0mr" esc "[0m"))
  (check (written (lambda () (print-markup "[color(208)]r[/]")) 'colors '16) (string-append esc "[93mr" esc "[0m"))
  (check (written (lambda () (print-markup "[white on blue]r[/]"))) (string-append esc "[37;44mr" esc "[0m"))
  (check (written (lambda () (print-markup "[bright-red]r[/]")) 'colors '16) (string-append esc "[91mr" esc "[0m")))

(define-test "R-4 a link is OSC 8 on a terminal"
  (check (written (lambda () (print-markup "[link=https://x.org]x[/]")))
         (string-append esc "]8;;https://x.org" esc "\\x" esc "]8;;" esc "\\")))

;;; --- measuring (R-6) -----------------------------------------------------------

(define-test "R-6 text is measured in cells"
  (check (text-width "abc") 3)
  (check (text-width "漢字") 4)
  (check (text-width (string #\e (integer->char #x0301))) 1)        ; e and a combining accent
  (check (text-width (string #\a (integer->char 7) #\b)) 2))

;;; --- lines (R-17) -------------------------------------------------------------------

(define (line-texts lines) (map (lambda (line) (apply string-append (map segment-text line))) lines))

(define-test "R-17 a renderable renders to lines of segments, at a width"
  (check (line-texts (render-lines "one two three four" 9)) '("one two" "three" "four"))
  (check (line-texts (render-lines "a\nb" 9)) '("a" "b"))
  (check (line-texts (render-lines "abcdefghij" 4)) '("abcd" "efgh" "ij"))     ; a word wider than the width
  (check (line-texts (render-lines '(1 2) 9)) '("(1 2)"))
  (check (line-texts (render-lines "漢字漢字" 5)) '("漢字" "漢字"))
  ;; styles stay with their text across a wrap
  (let ((lines (render-lines (markup "[red]aa bb[/] cc") 3)))
    (check (line-texts lines) '("aa" "bb" "cc"))
    (check (style-foreground (segment-style (car (cadr lines)))) 'red)
    (check (style-foreground (segment-style (car (caddr lines)))) #f)))

(define-test "R-17 a program's own renderable"
  (let ((boxed (make-renderable (lambda (width) (list (list (segment (make-string width #\=))))))))
    (check-true (renderable? boxed))
    (check (line-texts (render-lines boxed 4)) '("===="))
    (check (shown (lambda () (render boxed)) 'width 6) "======")))

(define-test "R-7 render writes at the console's width"
  (check (shown (lambda () (render "one two three")) 'width 7) "one two\nthree"))

;;; --- regions (R-18) ---------------------------------------------------------------

(define-test "R-18 lines drawn into a region are placed and clipped"
  (let ((s (with-test-console '(width 12 height 4)
             (lambda ()
               (print-markup "xxxxxxxxxxxx")
               (draw-region (make-region 3 1 5 2) (render-lines "hello world again" 5))))))
    (check (screen-line s 1) "xxhelloxxxxx")
    (check (screen-line s 2) "  world")
    (check (screen-line s 3) "")))

(define-test "R-18 a region clears what its lines leave, and cuts a wide character whole"
  (let ((s (with-test-console '(width 8 height 2)
             (lambda ()
               (print-markup "########")
               (draw-region (make-region 1 1 3 1) (list (list (segment "a漢字"))))))))
    (check (screen-line s 1) "a漢#####")
    (check (car (screen-cell s 3 1)) #f)))         ; the second cell of a wide character

;;; --- events (R-19, R-20) ---------------------------------------------------------------

(define (events-of items)
  (let ((got '()))
    (with-test-console (list 'events items)
      (lambda () (let loop () (let ((e (read-event))) (if (not (eq? (event-kind e) 'eof)) (begin (set! got (cons e got)) (loop)))))))
    (reverse got)))

(define-test "R-19 a test console plays its events back, from the shorthand"
  (let ((es (events-of '(down #\a "hi" (ctrl #\c) (alt shift up) enter))))
    (check (length es) 7)
    (check-true (key-event? (list-ref es 0) 'down))
    (check-true (key-event? (list-ref es 1) #\a))
    (check-true (key-event? (list-ref es 3) #\i))
    (check-true (key-event? (list-ref es 4) #\c 'ctrl))
    (check-true (key-event? (list-ref es 5) 'up 'shift 'alt))
    (check-false (key-event? (list-ref es 5) 'up 'alt))
    (check-true (key-event? (list-ref es 6) 'enter))))

(define-test "R-19 the input decoder: the bytes a terminal sends, as events"
  ;; console:%decode reads through a procedure: here, characters from a list
  (define (decode . chars)
    (let ((box chars))
      (console:%decode (lambda (ms) (if (null? box) #f (let ((c (car box))) (set! box (cdr box)) c))) #f)))
  (define e (integer->char 27))
  (check-true (key-event? (decode e #\[ #\B) 'down))
  (check-true (key-event? (decode e #\[ #\1 #\; #\5 #\C) 'right 'ctrl))
  (check-true (key-event? (decode e #\[ #\1 #\; #\3 #\A) 'up 'alt))
  (check-true (key-event? (decode e #\[ #\3 #\~) 'delete))
  (check-true (key-event? (decode e #\[ #\5 #\; #\2 #\~) 'page-up 'shift))
  (check-true (key-event? (decode e #\[ #\Z) 'tab 'shift))
  (check-true (key-event? (decode e #\O #\P) 'f1))
  (check-true (key-event? (decode e #\[ #\1 #\5 #\~) 'f5))
  (check-true (key-event? (decode e) 'escape))                 ; nothing after it
  (check-true (key-event? (decode e #\x) #\x 'alt))
  (check-true (key-event? (decode (integer->char 13)) 'enter))
  (check-true (key-event? (decode (integer->char 127)) 'backspace))
  (check-true (key-event? (decode (integer->char 3)) #\c 'ctrl))
  (check-true (key-event? (decode #\λ) #\λ))
  (check (event-kind (decode 'resize)) 'resize)
  (check (event-kind (decode 'eof)) 'eof)
  (check (decode) #f)
  (let ((p (apply decode (append (list e #\[ #\2 #\0 #\0 #\~) (string->list "pasted [x]") (list e #\[ #\2 #\0 #\1 #\~)))))
    (check (event-kind p) 'paste)
    (check (event-text p) "pasted [x]")))

(define-test "R-20 without a terminal, read-event waits no longer than its timeout"
  ;; the suites' input is a file: no key ever comes
  (let ((e (read-event 30)))
    (check-true (or (not e) (eq? (event-kind e) 'eof)))))

;;; --- modes (R-21) --------------------------------------------------------------------

(define-test "R-21 screen modes nest, and are left as they were entered"
  (check (written (lambda () (with-alternate-screen (lambda () (with-alternate-screen (lambda () (display "x")))))))
         (string-append esc "[?1049h" "x" esc "[?1049l"))
  (check (written (lambda () (with-hidden-cursor (lambda () (display "y")))))
         (string-append esc "[?25l" "y" esc "[?25h"))
  ;; left by an error, the mode is left too
  (check (written (lambda () (guard (e (#t #f)) (with-hidden-cursor (lambda () (error "stop"))))))
         (string-append esc "[?25l" esc "[?25h"))
  ;; to a pipe, nothing is written
  (check (with-output-to-string (lambda () (with-alternate-screen (lambda () (display "z"))))) "z")
  (check (with-raw-mode (lambda () 'ran)) 'ran))

;;; --- the test console (R-23) ------------------------------------------------------------

(define-test "R-23 the test console is a screen"
  (let ((s (with-test-console '(width 10 height 3)
             (lambda ()
               (print-markup "[bold red on blue]ab[/]")
               (display (string-append esc "[2;4H"))
               (print-markup "[#0a1414]cd[/]")))))
    (check (screen-text s) "ab\n   cd")
    (check (car (screen-cell s 1 1)) #\a)
    (check (style-foreground (cdr (screen-cell s 1 1))) 'red)
    (check (style-background (cdr (screen-cell s 1 1))) 'blue)
    (check (style-attributes (cdr (screen-cell s 2 1))) '(bold))
    (check (style-foreground (cdr (screen-cell s 4 2))) '(rgb 10 20 20))
    (check (screen-cursor s) '(6 . 2))))

(define-test "R-23 the screen wraps, scrolls, clears, and keeps the alternate screen apart"
  (check (shown (lambda () (display "abcdefg")) 'width 3) "abc\ndef\ng")
  (check (shown (lambda () (display "1\n2\n3\n4")) 'height 2) "3\n4")
  (check (shown (lambda () (display "abc") (display (string-append esc "[2J")))) "")
  (check (shown (lambda () (display "abcd") (display (string-append esc "[1;3H" esc "[K")))) "ab")
  (check (shown (lambda () (display "main") (with-alternate-screen (lambda () (display "other"))))) "main"))

(run-tests)
