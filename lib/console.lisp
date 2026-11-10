;;; console.lisp -- rich console output and input, in the manner of Spectre.Console
;;; (specs/29-console.md). Load with (require 'console), or with a prefix:
;;; (require 'console 'prefix 'con:).
;;;
;;; This is step 1 of the spec: the console core (section 4.8) and what is built
;;; on it first.
;;;   - the console: its capabilities (R-1, R-2), overridden with with-console;
;;;   - styles and markup, "[bold red on blue]text[/]" (R-4, R-5), each written
;;;     with the colors the console has, and none to a pipe (R-3);
;;;   - text measured in cells (R-6);
;;;   - renderables, which render to lines of segments at a width (R-17), and
;;;     regions of the screen to draw lines into, clipped (R-18);
;;;   - input as events, read with a timeout (R-19, R-20), and terminal modes
;;;     that nest and are always restored (R-21);
;;;   - a test console that is a screen (R-23).
;;; The operating system's part is the runtime's (LispTerminal, through the
;;; %terminal- primitives); nothing here holds a handle or a console mode.
;;;
;;; Records are tagged vectors: #(style ...), #(styled ...), #(renderable ...),
;;; #(event ...), #(region ...), #(screen ...).

(library console
  (export console-capabilities console-width with-console
          style style? style-foreground style-background style-attributes style-link
          styled markup markup-escape print-markup print-markup-line
          segment segment-text segment-style
          text-width make-renderable renderable? render-lines render
          rule panel table table-column table-add-row! table-add-column! grid columns tree padded aligned
          ask confirm choose choose-many prompt-cancelled?
          make-region draw-region
          read-event event? event-kind event-key event-char event-modifiers event-text key-event?
          with-raw-mode with-alternate-screen with-hidden-cursor
          with-test-console screen-text screen-line screen-cell screen-output screen-cursor))

(define esc (integer->char 27))
(define (csi . parts) (apply string-append (cons (string esc #\[) parts)))
(define (tagged? x tag) (and (vector? x) (> (vector-length x) 0) (eq? (vector-ref x 0) tag)))

;;; ===========================================================================
;;; The console and its capabilities (R-1, R-2)

;; the console in use: a hash table of its capabilities, and for a test console
;; its events; #f until first asked, then the one detected
(define %console #f)

(define (%env name)
  (let ((v (get-environment-variable name))) (and v (not (string=? v "")) v)))

(define (%contains-ci? s part)
  (and s (string-search (string-downcase s) part) #t))

;; what the console can do, from the runtime and the environment's conventions
(define (%detect)
  (let* ((out (%terminal-output-kind))
         (in (%terminal-input-kind))
         (terminal? (not (eq? out 'other)))
         (escapes? (and terminal? (%terminal-enable-escapes)))
         (size (and terminal? (%terminal-size)))
         (force (%env "FORCE_COLOR"))
         (colors
          (cond ((%env "NO_COLOR") 'none)
                ((and (%env "TERM") (string=? (%env "TERM") "dumb")) 'none)
                (force (cond ((string=? force "0") 'none)
                             ((string=? force "2") '256)
                             ((string=? force "3") 'truecolor)
                             (else '16)))
                ((not escapes?) 'none)
                ((eq? out 'console) 'truecolor)
                ((or (%contains-ci? (%env "COLORTERM") "truecolor") (%contains-ci? (%env "COLORTERM") "24bit")) 'truecolor)
                ((%contains-ci? (%env "TERM") "256color") '256)
                (else '16)))
         (unicode?
          (cond ((eq? out 'console) #t)
                ((eq? out 'terminal)
                 (let ((loc (or (%env "LC_ALL") (%env "LC_CTYPE") (%env "LANG"))))
                   (or (%contains-ci? loc "utf-8") (%contains-ci? loc "utf8"))))
                (else #t)))                              ; pipes and files are UTF-8
         (caps (make-hash-table)))
    (hash-table-set! caps 'terminal? terminal?)
    (hash-table-set! caps 'colors colors)
    (hash-table-set! caps 'unicode? unicode?)
    (hash-table-set! caps 'interactive? (and terminal? (not (eq? in 'other))))
    (hash-table-set! caps 'width (cond (size (car size))
                                       ((and (%env "COLUMNS") (string->number (%env "COLUMNS"))) (string->number (%env "COLUMNS")))
                                       (else 80)))
    (hash-table-set! caps 'height (cond (size (cadr size))
                                        ((and (%env "LINES") (string->number (%env "LINES"))) (string->number (%env "LINES")))
                                        (else 24)))
    (hash-table-set! caps 'events #f)
    (hash-table-set! caps 'input #f)
    caps))

(define (%caps)
  (if (not %console) (set! %console (%detect)))
  %console)

(define (%cap name) (hash-table-ref/default (%caps) name #f))

(define (console-capabilities)
  "(console-capabilities)
What the console can do, a hash table: terminal? (a terminal, not a pipe or a file), colors (none, 16, 256 or truecolor), unicode? (box-drawing characters show), interactive? (keys can be read), width and height. Detected once, from the terminal and NO_COLOR, FORCE_COLOR, TERM, COLORTERM, COLUMNS and LINES; with-console overrides it."
  (hash-table-copy (%caps)))

(define (console-width)
  "(console-width)
The console's width in cells."
  (%cap 'width))

;; (key value ...) -> the capabilities with those changed
(define (%with-overrides caps overrides)
  (let ((copy (hash-table-copy caps)))
    (let loop ((o overrides))
      (cond ((null? o) copy)
            ((null? (cdr o)) (error "with-console: the option has no value" (car o)))
            (else (hash-table-set! copy (car o) (cadr o)) (loop (cddr o)))))))

(define (with-console overrides thunk)
  "(with-console overrides thunk)
Runs thunk with the console's capabilities changed as overrides says, a list of names and values: (with-console '(colors none width 40) thunk). Gives them back however thunk is left."
  (let ((old (%caps)) (new (%with-overrides (%caps) overrides)))
    (dynamic-wind (lambda () (set! %console new)) thunk (lambda () (set! %console old)))))

;;; ===========================================================================
;;; Colors

(define %color-names
  '((black . 0) (red . 1) (green . 2) (yellow . 3) (blue . 4) (magenta . 5) (cyan . 6) (white . 7)
    (grey . 8) (gray . 8) (bright-black . 8) (bright-red . 9) (bright-green . 10) (bright-yellow . 11)
    (bright-blue . 12) (bright-magenta . 13) (bright-cyan . 14) (bright-white . 15)))

;; the 16 colors' usual values (xterm's), for bringing a color down to them
(define %palette-16
  '#((0 0 0) (128 0 0) (0 128 0) (128 128 0) (0 0 128) (128 0 128) (0 128 128) (192 192 192)
     (128 128 128) (255 0 0) (0 255 0) (255 255 0) (0 0 255) (255 0 255) (0 255 255) (255 255 255)))

;; a color: a symbol among %color-names, an integer 0..255, or (rgb r g b); #f is
;; the default. Answers it, or #f for a text that names no color.
(define (%parse-color text)
  (let ((sym (string->symbol (string-downcase text))))
    (cond ((assq sym %color-names) sym)
          ((eq? sym 'default) 'default)
          ((and (= (string-length text) 7) (eq? (string-ref text 0) #\#))
           (let ((r (string->number (substring text 1 3) 16))
                 (g (string->number (substring text 3 5) 16))
                 (b (string->number (substring text 5 7) 16)))
             (and r g b (list 'rgb r g b))))
          ((and (string-prefix? "rgb(" text) (string-suffix? ")" text))
           (let ((parts (map string->number (string-split (substring text 4 (- (string-length text) 1)) #\,))))
             (and (= (length parts) 3) (every (lambda (n) (and n (exact-integer? n) (<= 0 n 255))) parts)
                  (cons 'rgb parts))))
          ((and (string-prefix? "color(" text) (string-suffix? ")" text))
           (let ((n (string->number (substring text 6 (- (string-length text) 1)))))
             (and n (exact-integer? n) (<= 0 n 255) n)))
          (else #f))))

(define (%color-rgb color)
  (cond ((symbol? color) (vector-ref %palette-16 (cdr (assq color %color-names))))
        ((integer? color)
         (cond ((< color 16) (vector-ref %palette-16 color))
               ((< color 232)
                (let* ((n (- color 16)) (steps '#(0 95 135 175 215 255)))
                  (list (vector-ref steps (quotient n 36)) (vector-ref steps (remainder (quotient n 6) 6))
                        (vector-ref steps (remainder n 6)))))
               (else (let ((v (+ 8 (* 10 (- color 232))))) (list v v v)))))
        (else (cdr color))))

(define (%distance a b)
  (let ((dr (- (car a) (car b))) (dg (- (cadr a) (cadr b))) (db (- (caddr a) (caddr b))))
    (+ (* dr dr) (* dg dg) (* db db))))

;; the index among the first count (16 or 256) closest to rgb
(define (%nearest rgb count)
  (let loop ((i 0) (best 0) (best-d #f))
    (if (= i count)
        best
        (let ((d (%distance rgb (%color-rgb i))))
          (if (or (not best-d) (< d best-d)) (loop (+ i 1) i d) (loop (+ i 1) best best-d))))))

;; the SGR parameters for color as a foreground (base 30) or background (base 40)
(define (%color-codes color base colors)
  (cond ((or (not color) (eq? color 'default)) '())
        ((symbol? color) (%index-16-codes (cdr (assq color %color-names)) base))
        ((eq? colors '16) (%index-16-codes (%nearest (%color-rgb color) 16) base))
        ((integer? color) (list (+ base 8) 5 color))
        ((eq? colors '256) (list (+ base 8) 5 (%nearest (cdr color) 256)))
        (else (list (+ base 8) 2 (cadr color) (caddr color) (cadddr color)))))

(define (%index-16-codes n base)
  (if (< n 8) (list (+ base n)) (list (+ base 60 (- n 8)))))

;;; ===========================================================================
;;; Styles (R-5)

;; #(style foreground background attributes link)
(define %attribute-codes '((bold . 1) (dim . 2) (italic . 3) (underline . 4) (invert . 7) (strikethrough . 9)))

(define (style? x)
  "(style? x)
True if x is a style."
  (tagged? x 'style))
(define (style-foreground s) "(style-foreground style)\nIts foreground color: a color name, an index 0..255, (rgb r g b), or #f." (vector-ref s 1))
(define (style-background s) "(style-background style)\nIts background color, as style-foreground's, or #f." (vector-ref s 2))
(define (style-attributes s) "(style-attributes style)\nIts attributes, a list of bold, dim, italic, underline, invert and strikethrough." (vector-ref s 3))
(define (style-link s) "(style-link style)\nThe URL it links to, or #f." (vector-ref s 4))

(define %plain (vector 'style #f #f '() #f))

;; inner over outer: a color or a link set in inner wins, attributes add up
(define (%merge outer inner)
  (vector 'style
          (or (style-foreground inner) (style-foreground outer))
          (or (style-background inner) (style-background outer))
          (append (style-attributes outer)
                  (filter (lambda (a) (not (memq a (style-attributes outer)))) (style-attributes inner)))
          (or (style-link inner) (style-link outer))))

;; the words of a style's text, "bold red on blue link=https://x", as a style;
;; fail with the message for a word it does not know
(define (%parse-style text fail)
  (let loop ((words (filter (lambda (w) (not (string=? w ""))) (string-split text #\space)))
             (fg #f) (bg #f) (attrs '()) (link #f))
    (cond ((null? words) (vector 'style fg bg (reverse attrs) link))
          ((string=? (car words) "on")
           (if (null? (cdr words))
               (fail "on needs a color")
               (let ((c (%parse-color (cadr words))))
                 (if c (loop (cddr words) fg c attrs link) (fail (string-append "unknown color " (cadr words)))))))
          ((string-prefix? "link=" (car words))
           (loop (cdr words) fg bg attrs (substring (car words) 5 (string-length (car words)))))
          ((assq (string->symbol (string-downcase (car words))) %attribute-codes)
           (loop (cdr words) fg bg (cons (string->symbol (string-downcase (car words))) attrs) link))
          ((%parse-color (car words)) => (lambda (c) (loop (cdr words) c bg attrs link)))
          (else (fail (string-append "unknown style " (car words)))))))

(define (style . parts)
  "(style part ...)
A style, from parts: a color or an attribute as a symbol or a string (red, #ff8800, rgb(1,2,3), color(208), bold), a list (on color) for the background, or a string of several, as markup writes them (\"bold red on blue\"). Later parts win."
  (fold (lambda (part s)
          (%merge s (cond ((style? part) part)
                          ((string? part) (%parse-style part (lambda (m) (error (string-append "style: " m)))))
                          ((symbol? part) (%parse-style (symbol->string part) (lambda (m) (error (string-append "style: " m)))))
                          ((and (pair? part) (eq? (car part) 'on) (pair? (cdr part)))
                           (let ((c (%parse-color (if (symbol? (cadr part)) (symbol->string (cadr part)) (cadr part)))))
                             (if c (vector 'style #f c '() #f) (error "style: unknown color" (cadr part)))))
                          (else (error "style: not a style part" part)))))
        %plain parts))

;; the escape codes that set style, for the console's colors (none: none at all)
(define (%sgr s colors)
  (if (or (eq? colors 'none) (eq? s %plain))
      ""
      (let ((codes (append (map (lambda (a) (cdr (assq a %attribute-codes))) (style-attributes s))
                           (%color-codes (style-foreground s) 30 colors)
                           (%color-codes (style-background s) 40 colors))))
        (if (null? codes) "" (csi (string-join (map number->string codes) ";") "m")))))

;;; ===========================================================================
;;; Segments and styled text

;; a segment: (text . style)
(define (segment text . s)
  "(segment text [style])
A piece of text in one style, the unit renderables are made of."
  (cons text (if (pair? s) (car s) %plain)))
(define (segment-text seg) "(segment-text segment)\nIts text." (car seg))
(define (segment-style seg) "(segment-style segment)\nIts style." (cdr seg))

;; #(styled segments): text with styles, a renderable
(define (styled text . parts)
  "(styled text style-part ...)
text in the style the parts make (as style takes them): a value to render, or to put in a table or a panel."
  (vector 'styled (list (segment text (apply style parts)))))

;; a segment written with the console's colors, its link as OSC 8 on a terminal
(define (%segment->string seg colors terminal?)
  (let* ((s (segment-style seg)) (code (%sgr s colors)) (link (and terminal? (style-link s))))
    (string-append (if link (string-append (string esc) "]8;;" link (string esc) "\\") "")
                   code (segment-text seg) (if (string=? code "") "" (csi "0m"))
                   (if link (string-append (string esc) "]8;;" (string esc) "\\") ""))))

;; every write goes through here, so a lock can go here too (R-22)
(define (%write text)
  (display text))

(define (%write-segments segs)
  (let ((colors (%cap 'colors)) (terminal? (%cap 'terminal?)))
    (for-each (lambda (seg) (%write (%segment->string seg colors terminal?))) segs)))

;;; ===========================================================================
;;; Markup (R-4)

(define (markup-escape text)
  "(markup-escape text)
text with [ and ] doubled, so markup shows them as they are."
  (with-output-to-string
    (lambda ()
      (string-for-each* (lambda (c) (if (or (eq? c #\[) (eq? c #\])) (begin (write-char c) (write-char c)) (write-char c)))
                        text))))

(define (string-for-each* proc s)
  (let ((n (string-length s)))
    (let loop ((i 0)) (if (< i n) (begin (proc (string-ref s i)) (loop (+ i 1)))))))

;; markup text -> segments; an error names the position (from 1)
(define (%parse-markup text)
  (let ((n (string-length text)))
    (define (fail i m) (error (string-append "markup: " m " at " (number->string (+ i 1)))))
    (let loop ((i 0) (stack (list %plain)) (chars '()) (segs '()))
      ;; the text gathered so far, as a segment in the current style
      (define (flush) (if (null? chars) segs (cons (segment (list->string (reverse chars)) (car stack)) segs)))
      (cond ((>= i n) (reverse (flush)))
            ((and (eq? (string-ref text i) #\[) (< (+ i 1) n) (eq? (string-ref text (+ i 1)) #\[))
             (loop (+ i 2) stack (cons #\[ chars) segs))
            ((and (eq? (string-ref text i) #\]) (< (+ i 1) n) (eq? (string-ref text (+ i 1)) #\]))
             (loop (+ i 2) stack (cons #\] chars) segs))
            ((eq? (string-ref text i) #\])
             (fail i "a ] that closes nothing: write ]] for one"))
            ((eq? (string-ref text i) #\[)
             (let ((close (let find ((j (+ i 1))) (cond ((>= j n) #f) ((eq? (string-ref text j) #\]) j) (else (find (+ j 1)))))))
               (if (not close) (fail i "a [ that is never closed: write [[ for one"))
               (let ((tag (string-trim (substring text (+ i 1) close))))
                 (cond ((string=? tag "/")
                        (if (null? (cdr stack))
                            (fail i "[/] closes no tag")
                            (loop (+ close 1) (cdr stack) '() (flush))))
                       ((string=? tag "") (fail i "an empty tag"))
                       (else
                        (loop (+ close 1)
                              (cons (%merge (car stack) (%parse-style tag (lambda (m) (fail i m)))) stack)
                              '() (flush)))))))
            (else (loop (+ i 1) stack (cons (string-ref text i) chars) segs))))))

(define (markup text)
  "(markup text)
The styled text that markup text describes, \"[bold red]done[/] in 3 s\": a value to render, or to put in a table. [[ and ]] are [ and ]; an error names the position."
  (vector 'styled (%parse-markup text)))

(define (print-markup text)
  "(print-markup text)
Writes markup text, \"[bold green]done[/] in [blue]3 s[/]\", in its styles, with the colors the console has (none to a pipe or a file)."
  (%write-segments (%parse-markup text)))

(define (print-markup-line text)
  "(print-markup-line text)
As print-markup, then a newline."
  (print-markup text)
  (newline))

;;; ===========================================================================
;;; Measuring text in cells (R-6)

;; ranges (first . last) of code points that take no cell, and that take two
(define %zero-width
  '((#x0300 . #x036F) (#x0483 . #x0489) (#x0591 . #x05BD) (#x0610 . #x061A) (#x064B . #x065F)
    (#x0E31 . #x0E31) (#x0E34 . #x0E3A) (#x1AB0 . #x1AFF) (#x1DC0 . #x1DFF) (#x200B . #x200F)
    (#x2028 . #x202E) (#x2060 . #x2064) (#x20D0 . #x20FF) (#xFE00 . #xFE0F) (#xFE20 . #xFE2F)
    (#xFEFF . #xFEFF)))
(define %wide
  '((#x1100 . #x115F) (#x2E80 . #x303E) (#x3041 . #x33FF) (#x3400 . #x4DBF) (#x4E00 . #x9FFF)
    (#xA000 . #xA4CF) (#xAC00 . #xD7A3) (#xF900 . #xFAFF) (#xFE30 . #xFE4F) (#xFF00 . #xFF60)
    (#xFFE0 . #xFFE6) (#x1F300 . #x1F64F) (#x1F900 . #x1F9FF) (#x20000 . #x3FFFD)))

(define (%in-ranges? code ranges)
  (any (lambda (r) (and (>= code (car r)) (<= code (cdr r)))) ranges))

(define (%char-width c)
  (let ((code (char->integer c)))
    (cond ((< code 32) 0)
          ((< code 127) 1)
          ((< code 160) 0)
          ((%in-ranges? code %zero-width) 0)
          ((%in-ranges? code %wide) 2)
          (else 1))))

(define (text-width text)
  "(text-width text)
How many cells text takes on a terminal: a wide East Asian character two, a combining mark or a control character none, any other one."
  (let ((n (string-length text)))
    (let loop ((i 0) (w 0)) (if (< i n) (loop (+ i 1) (+ w (%char-width (string-ref text i)))) w))))

;;; ===========================================================================
;;; Renderables and lines (R-7, R-17)

;; a line is a list of segments; a renderable answers its lines at a width
(define (make-renderable proc . measure)
  "(make-renderable proc [measure])
A renderable whose lines, at a width, are (proc width): a list of lines, each a list of segments (segment text style), at most width cells wide. measure, a procedure of no arguments, answers (narrowest . widest), the cells it needs without breaking a word and the most it takes, for a table or columns to lay it out; without one, both are its widest line at a large width. The renderables the library makes are such; so can a program's."
  (vector 'renderable proc (if (pair? measure) (car measure) #f)))

(define (renderable? x)
  "(renderable? x)
True if x is a renderable made by make-renderable."
  (tagged? x 'renderable))

;; segments -> a list of (char . style), and back
(define (%cells segs)
  (append-map (lambda (seg) (map (lambda (c) (cons c (segment-style seg))) (string->list (segment-text seg)))) segs))
(define (%uncells cells)
  ;; consecutive cells in one style are one segment
  (let loop ((cs cells) (acc '()))
    (cond ((null? cs) (reverse acc))
          ((and (pair? acc) (eq? (segment-style (car acc)) (cdr (car cs))))
           (loop (cdr cs) (cons (segment (string-append (segment-text (car acc)) (string (car (car cs)))) (cdr (car cs)))
                                (cdr acc))))
          (else (loop (cdr cs) (cons (segment (string (car (car cs))) (cdr (car cs))) acc))))))

(define (%cells-width cells) (fold (lambda (c w) (+ w (%char-width (car c)))) 0 cells))

;; one line of cells, wrapped at width: break after a space where it can, else
;; within a word; the spaces a break falls on are dropped
(define (%wrap cells width)
  (if (<= (%cells-width cells) width)
      (list cells)
      (let loop ((rest cells) (line '()) (w 0) (last-space #f) (lines '()))
        (cond ((null? rest) (reverse (cons (reverse line) lines)))
              (else
               (let* ((c (car rest)) (cw (%char-width (car c))))
                 (cond ((<= (+ w cw) width)
                        (loop (cdr rest) (cons c line) (+ w cw) (if (eq? (car c) #\space) (length line) last-space) lines))
                       ((eq? (car c) #\space)              ; a break on a space: the space goes
                        (loop (cdr rest) '() 0 #f (cons (reverse line) lines)))
                       (last-space                         ; back to the last space
                        (let* ((kept (reverse line))
                               (head (list-head kept last-space))
                               (tail (list-tail kept (+ last-space 1))))
                          (loop rest (reverse tail) (%cells-width tail) #f (cons head lines))))
                       ((null? line) (loop (cdr rest) (list c) cw #f lines)) ; wider than the width
                       (else (loop rest '() 0 #f (cons (reverse line) lines))))))))))

(define (list-head l n) (if (or (= n 0) (null? l)) '() (cons (car l) (list-head (cdr l) (- n 1)))))

;; cells -> lines at a newline
(define (%split-lines cells)
  (let loop ((cs cells) (line '()) (lines '()))
    (cond ((null? cs) (reverse (cons (reverse line) lines)))
          ((eq? (car (car cs)) #\newline) (loop (cdr cs) '() (cons (reverse line) lines)))
          (else (loop (cdr cs) (cons (car cs) line) lines)))))

;; segments, as lines at width
(define (%segment-lines segs width)
  (map %uncells (append-map (lambda (line) (%wrap line width)) (%split-lines (%cells segs)))))

(define (render-lines x width)
  "(render-lines x width)
x's lines at width cells: a list of lines, each a list of segments. x is a renderable, styled text (from styled or markup), a string, or any value (as display writes it); text is wrapped at spaces."
  (cond ((renderable? x) ((vector-ref x 1) width))
        ((tagged? x 'styled) (%segment-lines (vector-ref x 1) width))
        ((string? x) (%segment-lines (list (segment x)) width))
        (else (%segment-lines (list (segment (with-output-to-string (lambda () (display x))))) width))))

(define (render x)
  "(render x)
Writes x, a renderable, styled text or any value, at the console's width, a line at a time."
  (for-each (lambda (line) (%write-segments (%trim-line line)) (newline)) (render-lines x (console-width))))

;; a line without its trailing plain spaces: they show as nothing, and a pipe's
;; or a file's text keeps none (a styled space, a background, is kept)
(define (%trim-line line)
  (let loop ((rev (reverse line)))
    (cond ((null? rev) '())
          ((and (eq? (segment-style (car rev)) %plain) (string=? (%trim-right (segment-text (car rev))) ""))
           (loop (cdr rev)))
          ((eq? (segment-style (car rev)) %plain)
           (reverse (cons (segment (%trim-right (segment-text (car rev)))) (cdr rev))))
          (else (reverse rev)))))

;;; ===========================================================================
;;; Regions (R-18)

;; #(region column row width height), columns and rows from 1
(define (make-region column row width height)
  "(make-region column row width height)
A rectangle of the screen, its top left at column and row (from 1), to draw lines into."
  (vector 'region column row width height))

;; the first width cells of a line, as segments, and the cells it filled
(define (%clip line width)
  (let loop ((cells (%cells line)) (kept '()) (w 0))
    (if (or (null? cells) (> (+ w (%char-width (car (car cells)))) width))
        (cons (%uncells (reverse kept)) w)
        (loop (cdr cells) (cons (car cells) kept) (+ w (%char-width (car (car cells))))))))

(define (draw-region region lines)
  "(draw-region region lines)
Draws lines (from render-lines) into region: each at its row, cut at the region's width and filled with spaces to it; lines past its height are not drawn, and rows past the lines are cleared."
  (let ((col (vector-ref region 1)) (row (vector-ref region 2))
        (width (vector-ref region 3)) (height (vector-ref region 4)))
    (let loop ((i 0) (ls lines))
      (if (< i height)
          (let ((clipped (%clip (if (pair? ls) (car ls) '()) width)))
            (%write (csi (number->string (+ row i)) ";" (number->string col) "H"))
            (%write-segments (car clipped))
            (%write (make-string (- width (cdr clipped)) #\space))
            (loop (+ i 1) (if (pair? ls) (cdr ls) '())))))))

;;; ===========================================================================
;;; Terminal modes (R-21): scoped, nested, and restored at exit

;; how deep each screen mode is entered, and what restore must write
(define %alternate-depth 0)
(define %hidden-depth 0)

(define (%update-restore!)
  (%terminal-on-restore
   (if (and (= %alternate-depth 0) (= %hidden-depth 0))
       #f
       (string-append (if (> %hidden-depth 0) (csi "?25h") "") (if (> %alternate-depth 0) (csi "?1049l") "")))))

(define (%test-console?) (and (%cap 'events) #t))

(define (with-raw-mode thunk)
  "(with-raw-mode thunk)
Runs thunk with the terminal in raw mode (keys arrive one at a time, not echoed), and restores it however thunk is left, and at exit. Nested, the outermost restores. Without a terminal, it only runs thunk."
  (if (%test-console?)
      (thunk)
      (dynamic-wind (lambda () (%terminal-raw-on)) thunk (lambda () (%terminal-raw-off)))))

;; a screen mode entered by on and left by off, counted in the depth's box
(define (%with-mode get set on off thunk)
  (if (not (%cap 'terminal?))
      (thunk)
      (dynamic-wind
        (lambda () (if (= (get) 0) (begin (%write on) (%terminal-flush))) (set (+ (get) 1)) (%update-restore!))
        thunk
        (lambda () (set (- (get) 1)) (if (= (get) 0) (begin (%write off) (%terminal-flush))) (%update-restore!)))))

(define (with-alternate-screen thunk)
  "(with-alternate-screen thunk)
Runs thunk on the terminal's alternate screen, and brings the main screen back, as it was, however thunk is left, and at exit."
  (%with-mode (lambda () %alternate-depth) (lambda (n) (set! %alternate-depth n)) (csi "?1049h") (csi "?1049l") thunk))

(define (with-hidden-cursor thunk)
  "(with-hidden-cursor thunk)
Runs thunk with the cursor hidden, and shows it again however thunk is left, and at exit."
  (%with-mode (lambda () %hidden-depth) (lambda (n) (set! %hidden-depth n)) (csi "?25l") (csi "?25h") thunk))

;;; ===========================================================================
;;; Events (R-19, R-20)

;; #(event kind key char modifiers text)
(define (%event kind key char mods text) (vector 'event kind key char mods text))
(define (event? x) "(event? x)\nTrue if x is an event (from read-event)." (tagged? x 'event))
(define (event-kind e) "(event-kind event)\nkey, paste, resize or eof." (vector-ref e 1))
(define (event-key e) "(event-key event)\nA key's name (up, down, enter, escape, tab, backspace, f1, page-up and the like), or #f for a character." (vector-ref e 2))
(define (event-char e) "(event-char event)\nThe character a key typed, or #f." (vector-ref e 3))
(define (event-modifiers e) "(event-modifiers event)\nThe modifiers held: a list of ctrl, alt and shift." (vector-ref e 4))
(define (event-text e) "(event-text event)\nThe text of a paste, or #f." (vector-ref e 5))

(define (key-event? e key . mods)
  "(key-event? event key [modifier ...])
True if event is that key (a key's name, or a character), with exactly those modifiers."
  (and (event? e) (eq? (event-kind e) 'key)
       (if (char? key) (eqv? (event-char e) key) (eq? (event-key e) key))
       (equal? (sort (map symbol->string (event-modifiers e)) string<?) (sort (map symbol->string mods) string<?))))

(define (%key name mods) (%event 'key name #f mods #f))
(define (%char-key c mods) (%event 'key #f c mods #f))

;; the modifiers of a CSI parameter: 1 + shift 1, alt 2, ctrl 4
(define (%modifiers n)
  (let ((m (- n 1)))
    (filter (lambda (x) x)
            (list (and (odd? m) 'shift) (and (odd? (quotient m 2)) 'alt) (and (odd? (quotient m 4)) 'ctrl)))))

(define %tilde-keys
  '((1 . home) (2 . insert) (3 . delete) (4 . end) (5 . page-up) (6 . page-down) (7 . home) (8 . end)
    (11 . f1) (12 . f2) (13 . f3) (14 . f4) (15 . f5) (17 . f6) (18 . f7) (19 . f8) (20 . f9) (21 . f10)
    (23 . f11) (24 . f12)))
(define %final-keys
  '((#\A . up) (#\B . down) (#\C . right) (#\D . left) (#\H . home) (#\F . end) (#\Z . tab)
    (#\P . f1) (#\Q . f2) (#\R . f3) (#\S . f4)))

;; a control character as a key
(define (%control-key c)
  (let ((code (char->integer c)))
    (cond ((or (= code 13) (= code 10)) (%key 'enter '()))
          ((= code 9) (%key 'tab '()))
          ((or (= code 127) (= code 8)) (%key 'backspace '()))
          ((= code 0) (%char-key #\space '(ctrl)))
          ((<= code 26) (%char-key (integer->char (+ code 96)) '(ctrl)))
          (else (%char-key c '())))))

;; read one event through next, a procedure answering the next character within
;; its timeout (in ms, #f for none): a character, resize, eof, or #f
(define (%decode next timeout)
  (let ((c (next timeout)))
    (cond ((not c) #f)
          ((eq? c 'resize) (%event 'resize #f #f '() #f))
          ((eq? c 'eof) (%event 'eof #f #f '() #f))
          ((eq? c esc)
           (let ((c2 (next 50)))                   ; a lone ESC is the Escape key
             (cond ((not (char? c2)) (%key 'escape '()))
                   ((eq? c2 #\[) (%decode-csi next))
                   ((eq? c2 #\O) (let ((c3 (next 50)))
                                   (if (and (char? c3) (assv c3 %final-keys)) (%key (cdr (assv c3 %final-keys)) '())
                                       (%key 'escape '()))))
                   ((eq? c2 esc) (%key 'escape '(alt)))
                   (else (let ((e (if (< (char->integer c2) 32) (%control-key c2) (%char-key c2 '()))))
                           (%event 'key (event-key e) (event-char e) (cons 'alt (event-modifiers e)) #f))))))
          ((< (char->integer c) 32) (%control-key c))
          ((= (char->integer c) 127) (%key 'backspace '()))
          (else (%char-key c '())))))

;; after ESC [: parameters, then a final character
(define (%decode-csi next)
  (let loop ((chars '()))
    (let ((c (next 50)))
      (cond ((not (char? c)) (%key 'escape '()))
            ((and (char>=? c #\@) (char<=? c #\~))
             (let* ((params (map (lambda (p) (or (string->number p) 1))
                                 (string-split (list->string (reverse chars)) #\;)))
                    (first (if (pair? params) (car params) 1))
                    (mods (if (and (pair? params) (pair? (cdr params))) (%modifiers (cadr params)) '())))
               (cond ((and (eq? c #\~) (= first 200)) (%read-paste next))
                     ((eq? c #\~) (let ((k (assv first %tilde-keys))) (if k (%key (cdr k) mods) (%key 'unknown mods))))
                     ((eq? c #\Z) (%key 'tab '(shift)))
                     ((assv c %final-keys) (%key (cdr (assv c %final-keys)) mods))
                     (else (%key 'unknown mods)))))
            (else (loop (cons c chars)))))))

;; a bracketed paste, to ESC [ 2 0 1 ~
(define (%read-paste next)
  (let loop ((chars '()))
    (let ((c (next 1000)))
      (if (not (char? c))
          (%event 'paste #f #f '() (list->string (reverse chars)))
          (let* ((chars (cons c chars)) (end (reverse (string->list (string-append (string esc) "[201~")))))
            (if (and (>= (length chars) 6) (equal? (list-head chars 6) end))
                (%event 'paste #f #f '() (list->string (reverse (list-tail chars 6))))
                (loop chars)))))))

;; a test console's events: a shorthand list of key names, characters, strings
;; and (modifier ... key), or events
(define (%shorthand->events items)
  (append-map
   (lambda (x)
     (cond ((event? x) (list x))
           ((symbol? x) (list (%key x '())))
           ((char? x) (list (%char-key x '())))
           ((string? x) (map (lambda (c) (%char-key c '())) (string->list x)))
           ((pair? x) (let* ((key (car (last-pair* x))) (mods (list-head x (- (length x) 1))))
                        (list (if (char? key) (%char-key key mods) (%key key mods)))))
           (else (error "with-test-console: not an event" x))))
   items))

(define (last-pair* l) (if (null? (cdr l)) l (last-pair* (cdr l))))

(define (read-event . timeout)
  "(read-event [timeout])
The next event: a key, a paste or a resize; eof at the end of the input; or #f when timeout milliseconds pass first (none: wait as long as it takes). It waits without stopping other processes. On a terminal it reads in raw mode; on a test console, its events."
  (let ((ms (if (pair? timeout) (car timeout) #f)))
    (if (%test-console?)
        (let ((box (%cap 'events)))
          (if (null? (car box))
              (%event 'eof #f #f '() #f)
              (let ((e (car (car box)))) (set-car! box (cdr (car box))) e)))
        (begin
          (%terminal-flush)
          (with-raw-mode (lambda () (%decode (lambda (t) (%terminal-read t)) ms)))))))

;;; ===========================================================================
;;; Measuring renderables, and lines (for the layouts below)

;; (narrowest . widest): the fewest cells x can be drawn in without breaking a
;; word, and the most it takes
(define (%measure x)
  (cond ((and (renderable? x) (vector-ref x 2)) ((vector-ref x 2)))
        ((renderable? x)
         (let ((w (fold max 0 (map %line-width (render-lines x 1000))))) (cons w w)))
        (else
         (let* ((segs (cond ((tagged? x 'styled) (vector-ref x 1))
                            ((string? x) (list (segment x)))
                            (else (list (segment (with-output-to-string (lambda () (display x))))))))
                (text (apply string-append (map segment-text segs)))
                (lines (string-split text #\newline))
                (words (append-map (lambda (l) (string-split l #\space)) lines)))
           (cons (fold max 0 (map text-width words)) (fold max 0 (map text-width lines)))))))

(define (%line-width line) (fold (lambda (seg w) (+ w (text-width (segment-text seg)))) 0 line))

(define (%spaces n) (if (<= n 0) '() (list (segment (make-string n #\space)))))

;; a line placed in width cells: left, center or right; never cut
(define (%align line width align)
  (let ((gap (max 0 (- width (%line-width line)))))
    (cond ((eq? align 'right) (append (%spaces gap) line))
          ((eq? align 'center) (append (%spaces (quotient gap 2)) line (%spaces (- gap (quotient gap 2)))))
          (else (append line (%spaces gap))))))

;; the first n cells of line (a character too wide for what is left is left out)
(define (%cut-line line n)
  (let loop ((segs line) (room n) (acc '()))
    (if (or (null? segs) (<= room 0))
        (reverse acc)
        (let* ((s (car segs)) (text (segment-text s)) (w (text-width text)))
          (if (<= w room)
              (loop (cdr segs) (- room w) (cons s acc))
              (let take ((i 0) (cells 0))
                (let ((cw (if (< i (string-length text)) (%char-width (string-ref text i)) 0)))
                  (if (or (>= i (string-length text)) (> (+ cells cw) room))
                      (reverse (cons (segment (substring text 0 i) (segment-style s)) acc))
                      (take (+ i 1) (+ cells cw))))))))))

;; x as one line of at most width cells: whole if it fits, else cut and ended
;; with an ellipsis, ... without Unicode, so nothing is cut without a mark (R-24)
(define (%one-line x width)
  (let* ((lines (render-lines x 100000))
         (line (fold (lambda (l acc) (if (null? acc) l (append acc (list (segment " ")) l))) '() lines)))
    (if (<= (%line-width line) width)
        line
        (let* ((mark (if (%cap 'unicode?) (string (integer->char 8230)) "...")) (mw (text-width mark)))
          (if (< width mw)
              (%cut-line line width)
              (append (%cut-line line (- width mw)) (list (segment mark))))))))

;; the widest line of x, a title or a caption: the cells it takes on one line
(define (%widest x) (if x (cdr (%measure x)) 0))

;; options, as (name value ...): the value of name, or default
(define (%opt options name default)
  (let ((m (memq name options))) (if (and m (pair? (cdr m))) (cadr m) default)))

(define (%check-options who options names)
  (let loop ((o options))
    (cond ((null? o) #t)
          ((not (memq (car o) names))
           (error (string-append who ": unknown option " (with-output-to-string (lambda () (write (car o)))))))
          ((null? (cdr o)) (error (string-append who ": the option " (symbol->string (car o)) " has no value")))
          (else (loop (cddr o))))))

(define (%style-of x) (cond ((not x) %plain) ((style? x) x) (else (style x))))

;;; ===========================================================================
;;; Borders (R-9)

;; #(top-left horizontal top-right vertical bottom-left bottom-right
;;   left-tee right-tee top-tee bottom-tee cross)
(define %borders
  '((square . #("┌" "─" "┐" "│" "└" "┘" "├" "┤" "┬" "┴" "┼"))
    (rounded . #("╭" "─" "╮" "│" "╰" "╯" "├" "┤" "┬" "┴" "┼"))
    (heavy . #("┏" "━" "┓" "┃" "┗" "┛" "┣" "┫" "┳" "┻" "╋"))
    (double . #("╔" "═" "╗" "║" "╚" "╝" "╠" "╣" "╦" "╩" "╬"))
    (ascii . #("+" "-" "+" "|" "+" "+" "+" "+" "+" "+" "+"))
    (none . #(" " " " " " " " " " " " " " " " " " " " " "))))

;; the border set named, as the console can show it: ascii without Unicode
(define (%border name)
  (let ((b (assq name %borders)))
    (if (not b) (error "border: unknown border" name))
    (if (and (not (%cap 'unicode?)) (not (memq name '(ascii none)))) (cdr (assq 'ascii %borders)) (cdr b))))

(define (%check-border name)
  (if (not (assq name %borders))
      (error (string-append "border: unknown border " (with-output-to-string (lambda () (write name)))
                            "; the borders are square, rounded, heavy, double, ascii and none"))))

(define (%b border i) (vector-ref border i))
(define (%repeat s n) (apply string-append (map (lambda (i) s) (iota (max 0 n)))))

;;; ===========================================================================
;;; rule (R-7)

(define (rule . args)
  "(rule [title] option ...)
A line across the width, with title (text or markup's styled text) in it, shortened with an ellipsis when the width is too narrow for it. Options: style (the line's), align (left, center or right; center), character (the line's, else ─, or - without Unicode)."
  (let* ((title (and (pair? args) (not (symbol? (car args))) (car args)))
         (options (if title (cdr args) args)))
    (%check-options "rule" options '(style align character))
    (make-renderable
     (lambda (width)
       (let* ((ch (%opt options 'character (if (%cap 'unicode?) "─" "-")))
              (s (%style-of (%opt options 'style #f)))
              (line (lambda (n) (if (> n 0) (list (segment (%repeat ch n) s)) '()))))
         (if (not title)
             (list (line width))
             (let* ((t (%one-line title (max 1 (- width 4))))
                    (tw (%line-width t))
                    (rest (max 0 (- width tw 2)))
                    (align (%opt options 'align 'center))
                    (left (cond ((eq? align 'left) 2) ((eq? align 'right) (- rest 2)) (else (quotient rest 2)))))
               (list (append (line left) (list (segment " ")) t (list (segment " ")) (line (- rest left))))))))
     (lambda () (cons 1 1)))))

;;; ===========================================================================
;;; panel (R-7)

(define (%padding p)
  ;; a number for all four, or (vertical horizontal), or (top right bottom left)
  (cond ((number? p) (list p p p p))
        ((and (list? p) (= (length p) 2)) (list (car p) (cadr p) (car p) (cadr p)))
        ((and (list? p) (= (length p) 4)) p)
        (else (error "padding: a number, (vertical horizontal), or (top right bottom left)" p))))

(define (panel content . options)
  "(panel content option ...)
content in a box, as wide as its header if the width allows (else the header is shortened with an ellipsis). Options: header (text or styled text, in the top border), header-align (left, center, right), border (square, rounded, heavy, double, ascii, none; square), border-style, padding (a number, (vertical horizontal), or (top right bottom left); (0 1)), expand (#t: the full width), width."
  (%check-options "panel" options '(header header-align border border-style padding expand width))
  (%check-border (%opt options 'border 'square))
  (let ((pad (%padding (%opt options 'padding '(0 1)))))
    (make-renderable
     (lambda (width)
       (let* ((b (%border (%opt options 'border 'square)))
              (bs (%style-of (%opt options 'border-style #f)))
              (hpad (+ (cadr pad) (cadddr pad)))
              (header (%opt options 'header #f))
              ;; as wide as its header too (R-24)
              (natural (max (+ 2 hpad (cdr (%measure content))) (if header (+ 5 (%widest header)) 0)))
              (outer (min width (cond ((%opt options 'width #f) => (lambda (w) w))
                                      ((%opt options 'expand #f) width)
                                      (else natural))))
              (inner (max 1 (- outer 2 hpad)))
              (body (render-lines content inner))
              (edge (lambda (s) (segment s bs)))
              (row (lambda (line) (append (list (edge (%b b 3))) (%spaces (cadddr pad)) (%align line inner 'left)
                                          (%spaces (cadr pad)) (list (edge (%b b 3))))))
              (blank (row '()))
              (top (if (not header)
                       (list (edge (string-append (%b b 0) (%repeat (%b b 1) (- outer 2)) (%b b 2))))
                       ;; a corner, a line and a space at each side: the header has 5 cells less
                       (let* ((h (%one-line header (max 1 (- outer 5))))
                              (rest (max 0 (- outer 4 (%line-width h))))
                              (align (%opt options 'header-align 'left))
                              (left (cond ((eq? align 'center) (quotient rest 2)) ((eq? align 'right) (- rest 1)) (else 1))))
                         (append (list (edge (string-append (%b b 0) (%repeat (%b b 1) left) " ")))
                                 h
                                 (list (edge (string-append " " (%repeat (%b b 1) (- rest left)) (%b b 2))))))))
              (bottom (list (edge (string-append (%b b 4) (%repeat (%b b 1) (- outer 2)) (%b b 5))))))
         (append (list top)
                 (map (lambda (i) blank) (iota (car pad)))
                 (map row body)
                 (map (lambda (i) blank) (iota (caddr pad)))
                 (list bottom))))
     (lambda () (let ((m (%measure content)) (extra (+ 2 (cadr pad) (cadddr pad))))
                  (cons (+ extra (car m)) (max (+ extra (cdr m)) (let ((h (%opt options 'header #f))) (if h (+ 5 (%widest h)) 0)))))))))

;;; ===========================================================================
;;; The cell layout of tables, grids and columns

;; widths for columns, from their (narrowest . widest) and fixed widths (or #f),
;; to fit available cells: each its widest if all fit; else the widest give up
;; cells first, down to their narrowest, then below it (their words break)
(define (%fit measures fixed available expand?)
  (let* ((widths (%map2 (lambda (m f) (or f (cdr m))) measures fixed))
         (mins (%map2 (lambda (m f) (or f (car m))) measures fixed)))
    (define (total) (fold + 0 widths))
    (define (shrink! below-min?)
      ;; the column that can best give up a cell, or #f
      (let loop ((i 0) (ws widths) (ms mins) (fs fixed) (best #f) (best-room 0))
        (if (null? ws)
            (and best (begin (set! widths (%list-set widths best (- (list-ref widths best) 1))) #t))
            (let ((room (if below-min? (- (car ws) 1) (- (car ws) (car ms)))))
              (if (and (not (car fs)) (> room best-room))
                  (loop (+ i 1) (cdr ws) (cdr ms) (cdr fs) i room)
                  (loop (+ i 1) (cdr ws) (cdr ms) (cdr fs) best best-room))))))
    (let loop () (if (and (> (total) available) (shrink! #f)) (loop)))
    (let loop () (if (and (> (total) available) (shrink! #t)) (loop)))
    (if (and expand? (< (total) available) (pair? widths))
        ;; the rest to the columns in turn
        (let spread ((extra (- available (total))) (i 0))
          (if (> extra 0)
              (begin (set! widths (%list-set widths (remainder i (length widths)) (+ 1 (list-ref widths (remainder i (length widths))))))
                     (spread (- extra 1) (+ i 1))))))
    widths))

;; map over two lists at once (map takes one)
(define (%map2 f a b) (if (or (null? a) (null? b)) '() (cons (f (car a) (car b)) (%map2 f (cdr a) (cdr b)))))

(define (%list-set l i v) (if (= i 0) (cons v (cdr l)) (cons (car l) (%list-set (cdr l) (- i 1) v))))

;; one row of cells, at the widths: a list of lines, every cell as tall as the
;; tallest, each aligned, joined by the strings between (a list, one shorter)
(define (%row-lines cells widths aligns left between right)
  (let* ((blocks (%map2 (lambda (c w) (render-lines c w)) cells widths))
         (height (fold max 1 (map length blocks))))
    (map (lambda (r)
           (append left
                   (let join ((bs blocks) (ws widths) (as aligns) (sep between))
                     (if (null? bs)
                         '()
                         (append (%align (if (< r (length (car bs))) (list-ref (car bs) r) '()) (car ws) (car as))
                                 (if (null? (cdr bs)) '() (car sep))
                                 (join (cdr bs) (cdr ws) (cdr as) (if (null? (cdr bs)) sep (cdr sep))))))
                   right))
         (iota height))))

;;; ===========================================================================
;;; table (R-7; decision 2: values, and table-add-row!)

;; a column: #(column header align width no-wrap)
(define (table-column header . options)
  "(table-column header option ...)
A column of a table, for its columns option. Options: align (left, center, right; left), width (fixed, in cells)."
  (%check-options "table-column" options '(align width))
  (vector 'column header (%opt options 'align 'left) (%opt options 'width #f)))

(define (%as-column c) (if (tagged? c 'column) c (table-column c)))

(define (table . options)
  "(table option ...)
A table: columns (a list of headers, text or styled text, or table-column values), rows (a list of lists of cells, each any renderable), border (square, rounded, heavy, double, ascii, none; square), border-style, title and caption (above and below it; the table is at least as wide as each, if the width allows), show-header (#t), expand (#f: as wide as its content). Too wide for the console, it shrinks, wrapping its cells. Add rows and columns with table-add-row! and table-add-column!."
  (%check-options "table" options '(columns rows border border-style title caption show-header expand))
  (%check-border (%opt options 'border 'square))
  (let ((state (vector (map %as-column (%opt options 'columns '())) (%opt options 'rows '()) options)))
    (vector 'renderable (lambda (width) (%table-lines state width)) (lambda () (%table-measure state)) state)))

(define (%table-state t)
  (if (and (renderable? t) (> (vector-length t) 3)) (vector-ref t 3) (error "table: not a table" t)))

(define (table-add-row! t . cells)
  "(table-add-row! table cell ...)
Adds a row to table, a cell for each column; answers table."
  (let ((s (%table-state t)))
    (vector-set! s 1 (append (vector-ref s 1) (list cells)))
    t))

(define (table-add-column! t header . options)
  "(table-add-column! table header option ...)
Adds a column to table, as table-column makes it; answers table."
  (let ((s (%table-state t)))
    (vector-set! s 0 (append (vector-ref s 0) (list (apply table-column (cons header options)))))
    t))

;; every row, as many cells as there are columns ("" for the missing)
(define (%table-rows s)
  (let ((n (length (vector-ref s 0))))
    (map (lambda (row) (let fill ((r row) (i 0)) (cond ((= i n) '()) ((pair? r) (cons (car r) (fill (cdr r) (+ i 1)))) (else (cons "" (fill r (+ i 1)))))))
         (vector-ref s 1))))

(define (%table-columns-measure s)
  (let ((show-header (%opt (vector-ref s 2) 'show-header #t)) (rows (%table-rows s)))
    (let loop ((cols (vector-ref s 0)) (i 0) (acc '()))
      (if (null? cols)
          (reverse acc)
          (let* ((cells (append (if show-header (list (vector-ref (car cols) 1)) '()) (map (lambda (r) (list-ref r i)) rows)))
                 (ms (map %measure cells)))
            (loop (cdr cols) (+ i 1) (cons (cons (fold max 0 (map car ms)) (fold max 0 (map cdr ms))) acc)))))))

(define (%table-measure s)
  (let* ((ms (%table-columns-measure s)) (extra (+ 1 (* 3 (length ms)))) (options (vector-ref s 2)))
    (cons (+ extra (fold + 0 (map car ms)))
          ;; at its widest, as wide as its title and its caption too (R-24)
          (max (+ extra (fold + 0 (map cdr ms)))
               (%widest (%opt options 'title #f)) (%widest (%opt options 'caption #f))))))

(define (%table-lines s width)
  (let* ((cols (vector-ref s 0)) (options (vector-ref s 2)) (n (length cols)))
    (if (= n 0)
        '()
        (let* ((b (%border (%opt options 'border 'square)))
               (bs (%style-of (%opt options 'border-style #f)))
               (edge (lambda (str) (list (segment str bs))))
               (title (%opt options 'title #f))
               (caption (%opt options 'caption #f))
               (measures (%table-columns-measure s))
               (fixed (map (lambda (c) (vector-ref c 3)) cols))
               (fitted (%fit measures fixed (max n (- width 1 (* 3 n))) (%opt options 'expand #f)))
               ;; narrower than its title or caption: widened to them, as far as the width goes (R-24)
               (words (min width (max (%widest title) (%widest caption))))
               (widths (if (< (+ 1 (* 3 n) (fold + 0 fitted)) words)
                           (%fit measures fixed (max n (- words 1 (* 3 n))) #t)
                           fitted))
               (aligns (map (lambda (c) (vector-ref c 2)) cols))
               (outer (+ 1 (* 3 n) (fold + 0 widths)))
               (rule-line (lambda (l m r) (edge (string-append l (string-join (map (lambda (w) (%repeat (%b b 1) (+ w 2))) widths) m) r))))
               (row (lambda (cells)
                      (%row-lines cells widths aligns
                                  (edge (string-append (%b b 3) " "))
                                  (map (lambda (i) (edge (string-append " " (%b b 3) " "))) (iota (- n 1)))
                                  (edge (string-append " " (%b b 3)))))))
          (append
           (if title (map (lambda (l) (%align l outer 'center)) (render-lines title outer)) '())
           (list (rule-line (%b b 0) (%b b 8) (%b b 2)))
           (if (%opt options 'show-header #t)
               (append (row (map (lambda (c) (vector-ref c 1)) cols)) (list (rule-line (%b b 6) (%b b 10) (%b b 7))))
               '())
           (append-map row (%table-rows s))
           (list (rule-line (%b b 4) (%b b 9) (%b b 5)))
           (if caption (map (lambda (l) (%align l outer 'center)) (render-lines caption outer)) '()))))))

;;; ===========================================================================
;;; grid and columns (R-7)

(define (grid rows . options)
  "(grid rows option ...)
Cells side by side, without borders: rows is a list of lists of cells, each any renderable. Options: gap (cells between columns; 1), align (left, center, right, for every column), expand."
  (%check-options "grid" options '(gap align expand))
  (let* ((gap (%opt options 'gap 1)) (align (%opt options 'align 'left))
         (n (fold max 0 (map length rows)))
         (full (map (lambda (r) (append r (map (lambda (i) "") (iota (- n (length r)))))) rows))
         (measures (lambda () (map (lambda (i) (let ((ms (map (lambda (r) (%measure (list-ref r i))) full)))
                                                  (cons (fold max 0 (map car ms)) (fold max 0 (map cdr ms)))))
                                   (iota n)))))
    (make-renderable
     (lambda (width)
       (if (= n 0)
           '()
           (let ((widths (%fit (measures) (map (lambda (i) #f) (iota n)) (max n (- width (* gap (- n 1)))) (%opt options 'expand #f))))
             (append-map (lambda (r) (%row-lines r widths (map (lambda (i) align) (iota n)) '()
                                                 (map (lambda (i) (%spaces gap)) (iota (- n 1))) '()))
                         full))))
     (lambda () (let ((ms (measures)) (g (* gap (max 0 (- n 1)))))
                  (cons (+ g (fold + 0 (map car ms))) (+ g (fold + 0 (map cdr ms)))))))))

(define (columns items . options)
  "(columns items option ...)
items side by side, as many to a row as fit the width, the rest below: as a list wraps into columns. Options: gap (cells between columns; 2)."
  (%check-options "columns" options '(gap))
  (let ((gap (%opt options 'gap 2)))
    (make-renderable
     (lambda (width)
       (let* ((widest (map (lambda (x) (cdr (%measure x))) items))
              (count (let try ((k (max 1 (length items))))
                       ;; the most per row whose columns, each as wide as its widest item, fit
                       (if (= k 1)
                           1
                           (let ((ws (map (lambda (c) (fold max 0 (%every-nth widest c k))) (iota k))))
                             (if (<= (+ (fold + 0 ws) (* gap (- k 1))) width) k (try (- k 1))))))))
         (render-lines (grid (%chunk items count) 'gap gap) width)))
     (lambda () (let ((ms (map %measure items)))
                  (cons (fold max 0 (map car ms)) (+ (fold + 0 (map cdr ms)) (* gap (max 0 (- (length items) 1))))))))))

(define (%every-nth l start k)
  (let loop ((l (list-tail* l start)) (acc '()))
    (if (null? l) (reverse acc) (loop (list-tail* l k) (cons (car l) acc)))))
(define (list-tail* l k) (if (or (= k 0) (null? l)) l (list-tail* (cdr l) (- k 1))))
(define (%chunk l k) (if (null? l) '() (cons (list-head l k) (%chunk (list-tail* l k) k))))

;;; ===========================================================================
;;; tree (R-7)

(define (tree label . children)
  "(tree label child ...)
label, with children below it on guide lines; a child is a tree, or any renderable (a leaf). (tree \"root\" \"a\" (tree \"b\" \"c\"))."
  (%make-tree
   (lambda (width) (%tree-lines label children width))
   (lambda ()
     (let ((ms (map %measure (cons label children))))
       (cons (+ 4 (fold max 0 (map car ms))) (+ 4 (fold max 0 (map cdr ms))))))))

(define (%make-tree proc measure) (vector 'renderable proc measure 'tree))

(define (%tree-lines label children width)
  (let* ((u (%cap 'unicode?))
         (branch (if u "├── " "+-- ")) (last (if u "└── " "`-- "))
         (through (if u "│   " "|   ")) (after "    "))
    (append (render-lines label width)
            (let loop ((cs children))
              (if (null? cs)
                  '()
                  (let* ((final? (null? (cdr cs)))
                         (lines (render-lines (car cs) (max 1 (- width 4)))))
                    (append (if (null? lines) '()
                                (cons (cons (segment (if final? last branch)) (car lines))
                                      (map (lambda (l) (cons (segment (if final? after through)) l)) (cdr lines))))
                            (loop (cdr cs)))))))))

;;; ===========================================================================
;;; padded and aligned (R-7)

(define (padded content padding)
  "(padded content padding)
content with space around it: padding is a number for all four sides, (vertical horizontal), or (top right bottom left)."
  (let ((p (%padding padding)))
    (make-renderable
     (lambda (width)
       (let* ((inner (max 1 (- width (cadr p) (cadddr p))))
              (lines (render-lines content inner))
              (w (fold max 0 (map %line-width lines)))
              (blank (%spaces (+ w (cadr p) (cadddr p)))))
         (append (map (lambda (i) blank) (iota (car p)))
                 (map (lambda (l) (append (%spaces (cadddr p)) (%align l w 'left) (%spaces (cadr p)))) lines)
                 (map (lambda (i) blank) (iota (caddr p))))))
     (lambda () (let ((m (%measure content)) (h (+ (cadr p) (cadddr p))))
                  (cons (+ h (car m)) (+ h (cdr m))))))))

(define (aligned content align)
  "(aligned content align)
content's lines placed in the full width: left, center or right."
  (if (not (memq align '(left center right))) (error "aligned: left, center or right" align))
  (make-renderable
   (lambda (width) (map (lambda (l) (%align l width align)) (render-lines content width)))
   (lambda () (%measure content))))

;;; ===========================================================================
;;; Prompts (R-10 to R-12)

;; Ctrl+C or Escape in a prompt: an error a program can catch (R-12)
(define %cancel-message "prompt: cancelled")
(define (%cancel) (error %cancel-message))

(define (prompt-cancelled? e)
  "(prompt-cancelled? condition)
True if condition is the one a prompt raises when Ctrl+C or Escape ends it, for guard."
  (and (error-object? e) (string? (error-object-message e))
       (string-prefix? %cancel-message (error-object-message e))))

(define (%interactive?) (%cap 'interactive?))

;; a line of input for a prompt without a console (R-11): from the test
;; console's input, else the current input; the end of it is an error
(define (%read-answer-line)
  (%terminal-flush)
  (let ((line (read-line (or (%cap 'input) (current-input-port)))))
    (if (eof-object? line) (error "prompt: no answer: the input ended"))
    ;; the answer is not echoed: the prompt's line ends here, as if it were
    (newline)
    line))

(define (%show x) (if (string? x) x (with-output-to-string (lambda () (display x)))))

;; an event, in raw mode; Ctrl+C and Escape cancel
(define (%prompt-event)
  (let ((e (read-event)))
    (cond ((or (key-event? e #\c 'ctrl) (key-event? e 'escape)) (%cancel))
          ((eq? (event-kind e) 'eof) (error "prompt: no answer: the input ended"))
          (else e))))

(define (%dim text) (segment text (style 'dim)))

;;; --- ask ---------------------------------------------------------------------

(define (ask question . options)
  "(ask question option ...)
Asks question (markup), and answers the text typed. Options: default (answered for an empty answer, and shown), validate (a procedure of the answer answering #t, or a message to show before asking again), secret (#t: typed as *), allow-empty (#t: an empty answer, with no default, is the empty string). Without a console it reads a line (R-11). Ctrl+C or Escape is a condition prompt-cancelled? tells."
  (%check-options "ask" options '(default validate secret allow-empty))
  (let ((default (%opt options 'default #f))
        (validate (%opt options 'validate #f))
        (secret (%opt options 'secret #f))
        (allow-empty (%opt options 'allow-empty #f)))
    ;; the answer, or a message for why it is not one
    (define (judge text)
      (let ((answer (if (and (string=? text "") default) (%show default) text)))
        (cond ((and (string=? answer "") (not allow-empty)) (cons #f "an answer is needed"))
              (validate (let ((v (validate answer))) (if (eq? v #t) (cons #t answer) (cons #f (if (string? v) v "not a valid answer")))))
              (else (cons #t answer)))))
    (define (show-question)
      (print-markup question)
      (if default (begin (%write " ") (%write-segments (list (%dim (string-append "(" (%show default) ")"))))))
      (%write " "))
    (define (show-problem message)
      (%write-segments (list (segment message (style 'red))))
      (newline))
    (if (%interactive?)
        (with-raw-mode
         (lambda ()
           (let ask-again ()
             (show-question)
             (%terminal-flush)
             (let typing ((chars '()))
               (let ((e (%prompt-event)))
                 (cond ((key-event? e 'enter)
                        (newline)
                        (let ((j (judge (list->string (reverse chars)))))
                          (if (car j) (cdr j) (begin (show-problem (cdr j)) (ask-again)))))
                       ((key-event? e 'backspace)
                        (if (pair? chars) (%write (string (integer->char 8) #\space (integer->char 8))))
                        (%terminal-flush)
                        (typing (if (pair? chars) (cdr chars) chars)))
                       ((eq? (event-kind e) 'paste)
                        (%write (if secret (make-string (string-length (event-text e)) #\*) (event-text e)))
                        (%terminal-flush)
                        (typing (append (reverse (string->list (event-text e))) chars)))
                       ((and (event-char e) (null? (event-modifiers e)))
                        (%write (if secret "*" (string (event-char e))))
                        (%terminal-flush)
                        (typing (cons (event-char e) chars)))
                       (else (typing chars))))))))
        (let ask-again ()
          (show-question)
          (let ((j (judge (%read-answer-line))))
            (if (car j) (cdr j) (begin (show-problem (cdr j)) (ask-again))))))))

;;; --- confirm -------------------------------------------------------------------

(define (confirm question . options)
  "(confirm question option ...)
Asks a yes or no question (markup), and answers #t or #f: y or n answers it, and Enter the default. Options: default (#t or #f; none: an answer is needed)."
  (%check-options "confirm" options '(default))
  (let* ((m (memq 'default options))
         (has-default (and m #t))
         (default (and m (cadr m)))
         (hint (cond ((not has-default) "[y/n]") (default "[Y/n]") (else "[y/N]"))))
    (define (show-question)
      (print-markup question) (%write " ") (%write-segments (list (%dim hint))) (%write " "))
    (if (%interactive?)
        (with-raw-mode
         (lambda ()
           (show-question)
           (%terminal-flush)
           (let loop ()
             (let ((e (%prompt-event)))
               (cond ((or (key-event? e #\y) (key-event? e #\Y)) (%write "y") (newline) #t)
                     ((or (key-event? e #\n) (key-event? e #\N)) (%write "n") (newline) #f)
                     ((and (key-event? e 'enter) has-default) (%write (if default "y" "n")) (newline) default)
                     (else (loop)))))))
        (let loop ()
          (show-question)
          (let ((answer (string-downcase (string-trim (%read-answer-line)))))
            (cond ((member answer '("y" "yes")) #t)
                  ((member answer '("n" "no")) #f)
                  ((and (string=? answer "") has-default) default)
                  (else (%write-segments (list (segment "answer y or n" (style 'red)))) (newline) (loop))))))))

;;; --- choose and choose-many ------------------------------------------------------

;; the list a chooser shows: the title, then a page of items, the current one
;; marked, with a hint when there are more above or below
(define (%chooser-lines title items labels current page marks highlight)
  (let* ((n (length items))
         (top (max 0 (min (- current (quotient page 2)) (- n page))))
         (shown (iota (min page n) top))
         (width (console-width)))
    (append
     (render-lines (markup title) width)
     (map (lambda (i)
            (let* ((here (= i current))
                   (mark (if marks (if (list-ref marks i) "[x] " "[ ] ") ""))
                   (text (string-append (if here "> " "  ") mark (list-ref labels i))))
              (car (%clip (list (segment text (if here highlight %plain))) width))))
          shown)
     (if (> n page)
         (list (list (%dim (string-append "  (" (number->string (+ current 1)) " of " (number->string n) ")"))))
         '()))))

;; draw lines where the last draw was: up over its lines, each cleared and redrawn
(define (%redraw lines before)
  (if (> before 0) (%write (csi (number->string before) "A")))
  (for-each (lambda (line) (%write (string #\return)) (%write (csi "2K")) (%write-segments line) (newline)) lines)
  ;; a shorter list leaves no stale lines below it
  (let clear ((extra (- before (length lines))))
    (if (> extra 0) (begin (%write (csi "2K")) (newline) (clear (- extra 1)))))
  (if (> before (length lines)) (%write (csi (number->string (- before (length lines))) "A")))
  (%terminal-flush)
  (length lines))

;; the shared loop of choose and choose-many: answers the current index and the marks
(define (%choose-interactive title items labels page many? marks highlight)
  (let ((n (length items)))
    (with-hidden-cursor
     (lambda ()
       (with-raw-mode
        (lambda ()
          (let loop ((current 0) (marks marks) (drawn 0))
            (let* ((drawn (%redraw (%chooser-lines title items labels current page (and many? marks) highlight) drawn))
                   (e (%prompt-event)))
              (cond ((key-event? e 'up) (loop (max 0 (- current 1)) marks drawn))
                    ((key-event? e 'down) (loop (min (- n 1) (+ current 1)) marks drawn))
                    ((key-event? e 'page-up) (loop (max 0 (- current page)) marks drawn))
                    ((key-event? e 'page-down) (loop (min (- n 1) (+ current page)) marks drawn))
                    ((key-event? e 'home) (loop 0 marks drawn))
                    ((key-event? e 'end) (loop (- n 1) marks drawn))
                    ((and many? (key-event? e #\space)) (loop current (%list-set marks current (not (list-ref marks current))) drawn))
                    ((key-event? e 'enter)
                     ;; the list goes; the question and its answer stay
                     (%redraw '() drawn)
                     (cons current marks))
                    (else (loop current marks drawn)))))))))))

(define (%chooser-setup who items options)
  (%check-options who options '(page-size display highlight selected))
  (if (null? items) (error (string-append who ": no items to choose from")))
  (list (map (lambda (x) ((%opt options 'display %show) x)) items)
        (%opt options 'page-size 10)
        (%style-of (%opt options 'highlight "bold cyan"))))

;; without a console: an item's number (from 1) or its label, or #f
(define (%item-for answer items labels)
  (let ((n (string->number answer)))
    (cond ((and n (exact-integer? n) (<= 1 n (length items))) (list-ref items (- n 1)))
          ((let find ((is items) (ls labels)) (cond ((null? is) #f) ((string=? (car ls) answer) is) (else (find (cdr is) (cdr ls)))))
           => car)
          (else #f))))

(define (%list-numbered items labels)
  (let loop ((ls labels) (i 1))
    (if (pair? ls)
        (begin (%write (string-append "  " (number->string i) ". " (car ls))) (newline) (loop (cdr ls) (+ i 1))))))

(define (choose title items . options)
  "(choose title items option ...)
Shows title (markup) and items, and answers the item chosen: the arrow keys (and Page Up, Page Down, Home, End) move, Enter chooses. Options: page-size (items shown at once; 10), display (a procedure from an item to its text), highlight (the style of the current item). Without a console it lists them numbered and reads a number or a name (R-11). Ctrl+C or Escape is a condition prompt-cancelled? tells."
  (let* ((setup (%chooser-setup "choose" items options)) (labels (car setup)))
    (if (%interactive?)
        (let* ((r (%choose-interactive title items labels (cadr setup) #f #f (caddr setup)))
               (item (list-ref items (car r))))
          (print-markup title) (%write " ") (%write-segments (list (segment (list-ref labels (car r)) (caddr setup)))) (newline)
          item)
        (begin
          (print-markup-line title)
          (%list-numbered items labels)
          (let again ()
            (%write "? ")
            (let ((item (%item-for (string-trim (%read-answer-line)) items labels)))
              (or item (begin (%write-segments (list (segment "choose a number or a name from the list" (style 'red)))) (newline) (again)))))))))

(define (choose-many title items . options)
  "(choose-many title items option ...)
As choose, but Space marks and unmarks items, and Enter answers the marked ones, in their order. Options: those of choose, and selected (a list of the items marked at first). Without a console it reads numbers or names, separated by spaces or commas."
  (let* ((setup (%chooser-setup "choose-many" items options))
         (labels (car setup))
         (selected (%opt options 'selected '()))
         (marks (map (lambda (x) (and (member x selected) #t)) items)))
    (if (%interactive?)
        (let* ((r (%choose-interactive title items labels (cadr setup) #t marks (caddr setup)))
               (chosen (let pick ((is items) (ms (cdr r))) (cond ((null? is) '()) ((car ms) (cons (car is) (pick (cdr is) (cdr ms)))) (else (pick (cdr is) (cdr ms)))))))
          (print-markup title) (%write " ")
          (%write-segments (list (segment (string-join (map (lambda (x) ((%opt options 'display %show) x)) chosen) ", ") (caddr setup))))
          (newline)
          chosen)
        (begin
          (print-markup-line title)
          (%list-numbered items labels)
          (let again ()
            (%write "? ")
            (let* ((words (filter (lambda (w) (not (string=? w "")))
                                  (append-map (lambda (part) (string-split part #\space)) (string-split (%read-answer-line) #\,))))
                   (chosen (map (lambda (w) (%item-for w items labels)) words)))
              (if (every (lambda (x) x) chosen)
                  (filter (lambda (x) (member x chosen)) items)
                  (begin (%write-segments (list (segment "choose numbers or names from the list" (style 'red)))) (newline) (again)))))))))

;;; ===========================================================================
;;; The test console (R-15, R-23)

;; #(screen width height cells log cursor-col cursor-row)
(define (with-test-console options thunk)
  "(with-test-console options thunk)
Runs thunk against a test console, and answers its screen: options is a list of names and values, width (80), height (24), colors (truecolor), unicode? (#t), events (a list of key names, characters, strings, lists such as (ctrl #\\c), or events, for read-event and the prompts), and input (a string of lines: then the console reads no keys, and the prompts read these lines, as with piped input). The screen is what was written, as a terminal shows it: screen-text, screen-cell and the rest read it."
  (let* ((get (lambda (name default) (let ((m (memq name options))) (if m (cadr m) default))))
         (width (get 'width 80)) (height (get 'height 24))
         (caps (make-hash-table)))
    (hash-table-set! caps 'terminal? #t)
    (hash-table-set! caps 'interactive? (not (get 'input #f)))
    (hash-table-set! caps 'input (and (get 'input #f) (open-input-string (get 'input #f))))
    (hash-table-set! caps 'colors (get 'colors 'truecolor))
    (hash-table-set! caps 'unicode? (get 'unicode? #t))
    (hash-table-set! caps 'width width)
    (hash-table-set! caps 'height height)
    (hash-table-set! caps 'events (list (%shorthand->events (get 'events '()))))
    (let* ((old %console)
           (text (dynamic-wind (lambda () (set! %console caps))
                               (lambda () (with-output-to-string thunk))
                               (lambda () (set! %console old)))))
      (%emulate text width height))))

(define (%blank-row width) (make-vector width (cons #\space %plain)))

(define (%emulate text width height)
  (let ((rows (make-vector height #f)) (saved #f) (col 0) (row 0) (cur %plain) (n (string-length text)))
    (define (scroll!)
      (do ((i 1 (+ i 1))) ((= i height)) (vector-set! rows (- i 1) (vector-ref rows i)))
      (vector-set! rows (- height 1) (%blank-row width)))
    (define (newline!) (set! col 0) (if (= row (- height 1)) (scroll!) (set! row (+ row 1))))
    (define (put! c)
      (let ((w (%char-width c)))
        (if (> w 0)
            (begin
              (if (> (+ col w) width) (newline!))
              (vector-set! (vector-ref rows row) col (cons c cur))
              (if (= w 2) (vector-set! (vector-ref rows row) (+ col 1) (cons #f cur)))
              (set! col (+ col w))))))
    (define (clamp v lo hi) (max lo (min hi v)))
    ;; an escape sequence from i (at ESC); answers where it ends
    (define (sequence i)
      (cond ((>= (+ i 1) n) (+ i 1))
            ((eq? (string-ref text (+ i 1)) #\])                ; OSC: to ST or BEL
             (let find ((j (+ i 2)))
               (cond ((>= j n) j)
                     ((eq? (string-ref text j) (integer->char 7)) (+ j 1))
                     ((and (eq? (string-ref text j) esc) (< (+ j 1) n) (eq? (string-ref text (+ j 1)) #\\)) (+ j 2))
                     (else (find (+ j 1))))))
            ((eq? (string-ref text (+ i 1)) #\[)
             (let find ((j (+ i 2)))
               (if (or (>= j n) (let ((c (string-ref text j))) (and (char>=? c #\@) (char<=? c #\~))))
                   (begin (if (< j n) (control (substring text (+ i 2) j) (string-ref text j))) (+ j 1))
                   (find (+ j 1)))))
            (else (+ i 2))))
    (define (params s) (map (lambda (p) (string->number p)) (string-split s #\;)))
    (define (p1 s default) (let ((ps (params s))) (if (and (pair? ps) (car ps)) (car ps) default)))
    (define (control s final)
      (cond ((eq? final #\m) (set! cur (%sgr->style (params s) cur)))
            ((or (eq? final #\H) (eq? final #\f))
             (let ((ps (params s)))
               (set! row (clamp (- (if (and (pair? ps) (car ps)) (car ps) 1) 1) 0 (- height 1)))
               (set! col (clamp (- (if (and (pair? ps) (pair? (cdr ps)) (cadr ps)) (cadr ps) 1) 1) 0 (- width 1)))))
            ((eq? final #\A) (set! row (clamp (- row (p1 s 1)) 0 (- height 1))))
            ((eq? final #\B) (set! row (clamp (+ row (p1 s 1)) 0 (- height 1))))
            ((eq? final #\C) (set! col (clamp (+ col (p1 s 1)) 0 (- width 1))))
            ((eq? final #\D) (set! col (clamp (- col (p1 s 1)) 0 (- width 1))))
            ((eq? final #\G) (set! col (clamp (- (p1 s 1) 1) 0 (- width 1))))
            ((eq? final #\J) (if (= (p1 s 0) 2) (do ((i 0 (+ i 1))) ((= i height)) (vector-set! rows i (%blank-row width)))))
            ((eq? final #\K)
             (let ((mode (p1 s 0)) (r (vector-ref rows row)))
               (do ((c 0 (+ c 1))) ((= c width))
                 (if (or (= mode 2) (and (= mode 0) (>= c col)) (and (= mode 1) (<= c col)))
                     (vector-set! r c (cons #\space %plain))))))
            ((and (eq? final #\h) (string=? s "?1049"))
             (set! saved (vector-map-copy rows))
             (do ((i 0 (+ i 1))) ((= i height)) (vector-set! rows i (%blank-row width))))
            ((and (eq? final #\l) (string=? s "?1049") saved)
             (do ((i 0 (+ i 1))) ((= i height)) (vector-set! rows i (vector-ref saved i)))
             (set! saved #f))
            (else #f)))
    (do ((i 0 (+ i 1))) ((= i height)) (vector-set! rows i (%blank-row width)))
    (let loop ((i 0))
      (if (< i n)
          (let ((c (string-ref text i)))
            (cond ((eq? c esc) (loop (sequence i)))
                  ((eq? c #\newline) (newline!) (loop (+ i 1)))
                  ((eq? c #\return) (set! col 0) (loop (+ i 1)))
                  ((eq? c (integer->char 8)) (set! col (max 0 (- col 1))) (loop (+ i 1)))
                  ((eq? c #\tab) (set! col (min (- width 1) (* 8 (+ 1 (quotient col 8))))) (loop (+ i 1)))
                  (else (put! c) (loop (+ i 1)))))))
    (vector 'screen width height rows text col row)))

(define (vector-map-copy v)
  (let* ((n (vector-length v)) (copy (make-vector n #f)))
    (do ((i 0 (+ i 1))) ((= i n) copy) (vector-set! copy i (vector-ref v i)))))

;; SGR parameters, applied to a style
(define (%sgr->style ps s)
  (let loop ((ps (if (null? ps) '(0) ps)) (s s))
    (if (null? ps)
        s
        (let ((p (or (car ps) 0)))
          (cond ((= p 0) (loop (cdr ps) %plain))
                ((assv p (map (lambda (a) (cons (cdr a) (car a))) %attribute-codes))
                 => (lambda (a) (loop (cdr ps) (%merge s (vector 'style #f #f (list (cdr a)) #f)))))
                ((or (= p 38) (= p 48))
                 (let* ((rgb? (and (pair? (cdr ps)) (eqv? (cadr ps) 2)))
                        (color (if rgb? (cons 'rgb (list-head (cddr ps) 3)) (caddr ps)))
                        (rest (list-tail ps (if rgb? 5 3))))
                   (loop rest (if (= p 38) (vector 'style color (style-background s) (style-attributes s) (style-link s))
                                  (vector 'style (style-foreground s) color (style-attributes s) (style-link s))))))
                ((or (<= 30 p 37) (<= 90 p 97))
                 (loop (cdr ps) (vector 'style (%index->name (if (< p 90) (- p 30) (+ 8 (- p 90)))) (style-background s) (style-attributes s) (style-link s))))
                ((or (<= 40 p 47) (<= 100 p 107))
                 (loop (cdr ps) (vector 'style (style-foreground s) (%index->name (if (< p 100) (- p 40) (+ 8 (- p 100)))) (style-attributes s) (style-link s))))
                (else (loop (cdr ps) s)))))))

(define (%index->name n)
  (car (find (lambda (pair) (and (= (cdr pair) n) (not (memq (car pair) '(gray bright-black))))) %color-names)))

(define (%row-string row)
  (let ((chars (filter (lambda (c) c) (map car (vector->list row)))))
    (%trim-right (list->string chars))))

(define (%trim-right s)
  (let loop ((end (string-length s)))
    (if (and (> end 0) (eq? (string-ref s (- end 1)) #\space)) (loop (- end 1)) (substring s 0 end))))

(define (screen-text screen)
  "(screen-text screen)
The test console's screen as text: its rows, trailing spaces gone, joined by newlines, with the empty rows at the bottom left off."
  (let* ((rows (map %row-string (vector->list (vector-ref screen 3))))
         (kept (let drop ((r (reverse rows))) (if (and (pair? r) (string=? (car r) "")) (drop (cdr r)) r))))
    (string-join (reverse kept) (string #\newline))))

(define (screen-line screen row)
  "(screen-line screen row)
The text of one row of the screen (from 1), trailing spaces gone."
  (%row-string (vector-ref (vector-ref screen 3) (- row 1))))

(define (screen-cell screen column row)
  "(screen-cell screen column row)
One cell of the screen (from 1): (character . style); the character is #f in the second cell of a wide one."
  (vector-ref (vector-ref (vector-ref screen 3) (- row 1)) (- column 1)))

(define (screen-output screen)
  "(screen-output screen)
Everything written to the test console, escape codes and all."
  (vector-ref screen 4))

(define (screen-cursor screen)
  "(screen-cursor screen)
Where the cursor ended: (column . row), from 1."
  (cons (+ 1 (vector-ref screen 5)) (+ 1 (vector-ref screen 6))))
