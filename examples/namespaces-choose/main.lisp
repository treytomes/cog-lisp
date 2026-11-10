; namespaces-choose/main.lisp -- choosing what to import: only, except, rename
;
; require takes options, after the library's name, applied in this order:
;   'only '(name ...)        just these exports;
;   'except '(name ...)      every export but these;
;   'rename '((old new) ...) these under other names;
;   'prefix p                every one as p followed by its name.
; They combine: below, palette.lisp's exports come in three times, each a
; different way, under names that cannot collide. A name the library does not
; export is an error in any of them, so a typo is caught at the require.

(require "palette.lisp" 'only '(red green))
(require "palette.lisp" 'except '(red green blue) 'prefix 'p:)
(require "palette.lisp" 'only '(blue) 'rename '((blue sky)))

(display (list (red) (green))) (newline)          ; only
(display (list (p:mix 'red 'blue) (p:all))) (newline)  ; except, prefixed
(display (sky)) (newline)                          ; renamed
(display (palette:blue)) (newline)                 ; the full name is still there
(display (map car (imports))) (newline)

(display (guard (e (#t (error-object-message e)))
           (require "palette.lisp" 'only '(purple))))
(newline)
