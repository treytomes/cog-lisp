;; console-renderables.lisp -- rules, panels, tables and trees
;;
;; A renderable is a value: (render x) writes it at the console's width. rule
;; draws a titled line, panel a box, table a grid of cells with headers, tree a
;; label with branches, and columns lays items side by side. Options follow as
;; pairs of a name and a value, since cog-lisp has no keyword arguments.
;;
;; Anything renders: text, markup's styled text, any value, and the renderables
;; themselves, so a table's cell can hold a panel. A table too wide for the
;; console shrinks, wrapping its cells at their spaces. Without Unicode, the
;; borders are drawn in ASCII.
(require 'console)

(with-console '(width 44)
  (lambda ()
    (render (rule "Inventory"))
    (let ((t (table 'columns (list "Item" (table-column "Qty" 'align 'right) "Note") 'title "Stock")))
      (table-add-row! t "apples" 12 "")
      (table-add-row! t "figs" 3 (markup "[red]low: order more before the weekend[/]"))
      (render t))
    (render (panel "Two items, fifteen in all." 'header "Summary" 'border 'rounded))
    (render (tree "warehouse" (tree "shelf a" "apples") (tree "shelf b" "figs")))
    (render (columns '("north" "south" "east" "west")))))

(with-console '(width 30 unicode? #f)
  (lambda () (render (panel "ASCII, for a console without Unicode"))))
