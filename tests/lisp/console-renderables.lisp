;;; console-renderables.lisp -- the console library's renderables, step 2 of
;;; specs/29-console.md (R-7 to R-9): rule, panel, table, grid, columns, tree,
;;; padded and aligned, their golden output at several widths, with and without
;;; Unicode (AC-2).
(load "../../lib/test.lisp")
(require 'console)

;; what x shows at a width, as the lines of a test console
(define (at width x . options)
  (screen-text (with-test-console (append (list 'width width 'height 40) options) (lambda () (render x)))))
(define (lines . ls) (string-join ls (string #\newline)))

;;; --- rule ------------------------------------------------------------------

(define-test "rule: across the width, a title centered, left or right"
  (check (at 10 (rule)) "──────────")
  (check (at 14 (rule "Hi")) "───── Hi ─────")
  (check (at 14 (rule "Hi" 'align 'left)) "── Hi ────────")
  (check (at 14 (rule "Hi" 'align 'right)) "──────── Hi ──")
  (check (at 6 (rule 'character "=")) "======")
  (check (at 8 (rule) 'unicode? #f) "--------")
  (check-error (rule 'colour 'red) "rule: unknown option colour"))

;;; --- panel ------------------------------------------------------------------

(define-test "panel: a box as wide as its content, or the width"
  (check (at 20 (panel "hi")) (lines "┌────┐" "│ hi │" "└────┘"))
  (check (at 12 (panel "hi" 'expand #t)) (lines "┌──────────┐" "│ hi       │" "└──────────┘"))
  (check (at 20 (panel "hi" 'width 8)) (lines "┌──────┐" "│ hi   │" "└──────┘"))
  (check (at 20 (panel "hi" 'padding 1)) (lines "┌────┐" "│    │" "│ hi │" "│    │" "└────┘"))
  (check (at 20 (panel "hi" 'padding '(0 0))) (lines "┌──┐" "│hi│" "└──┘")))

(define-test "panel: a header, its border sets, and wrapping inside it"
  (check (at 20 (panel "hello" 'header "N")) (lines "┌─ N ───┐" "│ hello │" "└───────┘"))
  (check (at 20 (panel "hello" 'header "N" 'header-align 'right)) (lines "┌─── N ─┐" "│ hello │" "└───────┘"))
  (check (at 20 (panel "x" 'border 'rounded)) (lines "╭───╮" "│ x │" "╰───╯"))
  (check (at 20 (panel "x" 'border 'heavy)) (lines "┏━━━┓" "┃ x ┃" "┗━━━┛"))
  (check (at 20 (panel "x" 'border 'double)) (lines "╔═══╗" "║ x ║" "╚═══╝"))
  (check (at 20 (panel "x" 'border 'ascii)) (lines "+---+" "| x |" "+---+"))
  (check (at 20 (panel "x" 'border 'rounded) 'unicode? #f) (lines "+---+" "| x |" "+---+"))   ; R-9
  (check (at 10 (panel "one two three")) (lines "┌────────┐" "│ one    │" "│ two    │" "│ three  │" "└────────┘"))
  (check-error (panel "x" 'border 'wavy) "border: unknown border")
  (check-error (panel "x" 'padding) "panel: the option padding has no value"))

;;; --- table ------------------------------------------------------------------

(define t1
  (table 'columns (list "Name" (table-column "Qty" 'align 'right)) 'rows '(("apples" 3) ("figs" 120))))

(define-test "table: columns, rows, alignment"
  (check (at 40 t1)
         (lines "┌────────┬─────┐"
                "│ Name   │ Qty │"
                "├────────┼─────┤"
                "│ apples │   3 │"
                "│ figs   │ 120 │"
                "└────────┴─────┘")))

(define-test "table: a title and a caption, no header, other borders"
  (check (at 40 (table 'columns '("A") 'rows '(("x")) 'title "T" 'caption "c" 'show-header #f))
         (lines "  T" "┌───┐" "│ x │" "└───┘" "  c"))
  (check (at 40 (table 'columns '("A" "B") 'rows '((1 2)) 'border 'ascii))
         (lines "+---+---+" "| A | B |" "+---+---+" "| 1 | 2 |" "+---+---+"))
  (check (at 40 (table 'columns '("A" "B") 'rows '((1 2)) 'border 'double))
         (lines "╔═══╦═══╗" "║ A ║ B ║" "╠═══╬═══╣" "║ 1 ║ 2 ║" "╚═══╩═══╝")))

(define-test "table: built a row at a time, with a column added, missing cells empty"
  (let ((t (table 'columns '("K"))))
    (table-add-row! t "a")
    (table-add-column! t "V" 'align 'center)
    (table-add-row! t "b" "two")
    (check (at 40 t) (lines "┌───┬─────┐" "│ K │  V  │" "├───┼─────┤" "│ a │     │" "│ b │ two │" "└───┴─────┘"))))

(define-test "table: too wide, it shrinks, the widest columns first, wrapping cells"
  (let ((t (table 'columns '("Key" "Description") 'rows '(("k" "a long description of it")))))
    (check (at 40 t) (lines "┌─────┬──────────────────────────┐"
                            "│ Key │ Description              │"
                            "├─────┼──────────────────────────┤"
                            "│ k   │ a long description of it │"
                            "└─────┴──────────────────────────┘"))
    (check (at 24 t) (lines "┌─────┬────────────────┐"
                            "│ Key │ Description    │"
                            "├─────┼────────────────┤"
                            "│ k   │ a long         │"
                            "│     │ description of │"
                            "│     │ it             │"
                            "└─────┴────────────────┘"))
    ;; narrower than its words: they break
    (check (at 14 t) (lines "┌─────┬──────┐" "│ Key │ Desc │" "│     │ ript │" "│     │ ion  │"
                            "├─────┼──────┤" "│ k   │ a    │" "│     │ long │" "│     │ desc │" "│     │ ript │"
                            "│     │ ion  │" "│     │ of   │" "│     │ it   │" "└─────┴──────┘"))))

(define-test "table: expanded to the width, and fixed column widths"
  (check (at 15 (table 'columns '("A" "B") 'rows '((1 2)) 'expand #t))
         (lines "┌──────┬──────┐" "│ A    │ B    │" "├──────┼──────┤" "│ 1    │ 2    │" "└──────┴──────┘"))
  (check (at 40 (table 'columns (list (table-column "A" 'width 4)) 'rows '((1))))
         (lines "┌──────┐" "│ A    │" "├──────┤" "│ 1    │" "└──────┘")))

(define-test "table: any renderable in a cell, a panel or a table"
  (check (at 40 (table 'columns '("In") 'rows (list (list (panel "x")))))
         (lines "┌───────┐" "│ In    │" "├───────┤" "│ ┌───┐ │" "│ │ x │ │" "│ └───┘ │" "└───────┘")))

(define-test "table: styles stay with their cells, and the border can have one"
  (let ((s (with-test-console '(width 40 height 10)
             (lambda () (render (table 'columns (list (markup "[bold]H[/]")) 'rows (list (list (markup "[red]r[/]")))
                                       'border-style 'blue))))))
    (check (style-attributes (cdr (screen-cell s 3 2))) '(bold))
    (check (style-foreground (cdr (screen-cell s 3 4))) 'red)
    (check (style-foreground (cdr (screen-cell s 1 1))) 'blue)))

;;; --- grid and columns ---------------------------------------------------------

(define-test "grid: cells side by side, a gap between, no borders"
  (check (at 40 (grid '(("a" "bb" "c") ("dd" "e")))) (lines "a  bb c" "dd e"))
  (check (at 40 (grid '(("a" "b")) 'gap 3)) "a   b")
  (check (at 40 (grid '(("a" "bbb") ("cc" "d")) 'align 'right)) (lines " a bbb" "cc   d")))

(define-test "columns: as many to a row as fit"
  (check (at 40 (columns '("one" "two" "three"))) "one  two  three")
  (check (at 12 (columns '("one" "two" "three" "four"))) (lines "one    two" "three  four"))   ; a gap of 2
  (check (at 5 (columns '("one" "two"))) (lines "one" "two")))

;;; --- tree ------------------------------------------------------------------------

(define-test "tree: guide lines, nested, with and without Unicode"
  (check (at 40 (tree "root" "a" (tree "b" "c") "d"))
         (lines "root" "├── a" "├── b" "│   └── c" "└── d"))
  (check (at 40 (tree "root" "a" (tree "b" "c")) 'unicode? #f)
         (lines "root" "+-- a" "`-- b" "    `-- c"))
  ;; a child of several lines keeps its guide
  (check (at 40 (tree "r" (panel "x") "y"))
         (lines "r" "├── ┌───┐" "│   │ x │" "│   └───┘" "└── y")))

;;; --- padded and aligned --------------------------------------------------------------

(define-test "padded and aligned"
  ;; the blank line below it is there; screen-text leaves off empty rows at the bottom
  (check (at 10 (padded "x" '(1 2))) (lines "" "  x"))
  (check (length (render-lines (padded "x" '(1 2)) 10)) 3)
  (check (at 10 (aligned "x" 'right)) "         x")
  (check (at 9 (aligned "x" 'center)) "    x")
  (check-error (aligned "x" 'middle) "aligned: left, center or right"))

;;; --- measuring and render ---------------------------------------------------------------

(define-test "a program's renderable with a measure lays out in a table"
  (let ((bar (make-renderable (lambda (w) (list (list (segment (make-string w #\#))))) (lambda () (cons 3 3)))))
    (check (at 40 (table 'columns '("Bar") 'rows (list (list bar))))
           (lines "┌─────┐" "│ Bar │" "├─────┤" "│ ### │" "└─────┘"))))

(define-test "render leaves no trailing spaces on a line"
  (check (with-console '(width 8) (lambda () (with-output-to-string (lambda () (render (aligned "x" 'left))))))
         (string-append "x" (string #\newline))))

(run-tests)
