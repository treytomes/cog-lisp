; namespaces/main.lisp -- libraries: what a library exports, and bringing it in
;
; A library is a file whose first form is (library name (export ...)). Its
; definitions belong to it: in shapes.lisp beside this file, (define (area w h)
; ...) defines shapes:area, its full name. (require "shapes.lisp") loads the
; file once and brings every exported name into this file, unqualified, so
; area means shapes:area here. A full name works from anywhere, imported or not.
; (require 'name) finds a library on the library path instead, as
; (require 'cl) does; a file name, as here, is looked for beside this file.
;
; (imports) lists what this file brought in: each name with the full name it
; stands for.

(require "shapes.lisp")

(display (area 3 4)) (newline)              ; shapes:area, through the import
(display (shapes:area 3 4)) (newline)       ; the full name: always works
(display (perimeter 3 4)) (newline)
(display (imports)) (newline)
