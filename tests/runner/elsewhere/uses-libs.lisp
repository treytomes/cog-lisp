; uses-libs.lisp -- run from a folder outside cog-lisp's: require finds cog-lisp's
; own libraries (specs/18-library-path.md AC-1)
(require 'cl)
(require 'test)
(defun twice (x) (* 2 x))
(display (twice 21))
(newline)
(display (if (assq 'test (hash-table-ref *env* 'libraries)) "test library loaded" "missing"))
(newline)
