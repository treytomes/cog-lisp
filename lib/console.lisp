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
(define (make-renderable proc)
  "(make-renderable proc)
A renderable whose lines, at a width, are (proc width): a list of lines, each a list of segments (segment text style), at most width cells wide. The renderables the library makes are such; so can a program's."
  (vector 'renderable proc))

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
  (for-each (lambda (line) (%write-segments line) (newline)) (render-lines x (console-width))))

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
;;; The test console (R-15, R-23)

;; #(screen width height cells log cursor-col cursor-row)
(define (with-test-console options thunk)
  "(with-test-console options thunk)
Runs thunk against a test console, and answers its screen: options is a list of names and values, width (80), height (24), colors (truecolor), unicode? (#t) and events (a list of key names, characters, strings, lists such as (ctrl #\\c), or events, for read-event). The screen is what was written, as a terminal shows it: screen-text, screen-cell and the rest read it."
  (let* ((get (lambda (name default) (let ((m (memq name options))) (if m (cadr m) default))))
         (width (get 'width 80)) (height (get 'height 24))
         (caps (make-hash-table)))
    (hash-table-set! caps 'terminal? #t)
    (hash-table-set! caps 'interactive? #t)
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
