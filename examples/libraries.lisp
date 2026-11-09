; libraries.lisp -- require, and *env*: libraries from any folder
;
; (load path) runs the file at a path, relative to the file that loads it.
; (require 'name) is the smarter loader: it finds name.lisp in the library path
; and loads it once, answering where it came from. The library path is the
; folders of the COGLISP_PATH environment variable, then cog-lisp's own lib
; folder, so (require 'cl) and (require 'test) work from a program anywhere.
;
; *env* is a table of what the running world knows about itself: home (the
; cog-lisp folder), library-path, libraries (what require has loaded),
; platform and version. A program changes the library path with set!:
;   (set! (hash-table-ref *env* 'library-path)
;         (cons "my/libs" (hash-table-ref *env* 'library-path)))

(define where (require 'test))
(display (string? where))                       ; the full path it loaded
(newline)
(display (string=? (require 'test) where))     ; a second require loads nothing
(newline)
(display (map car (hash-table-ref *env* 'libraries)))
(newline)
(display (string? (require-path 'cl)))          ; where it would load cl from
(newline)
(display (require-path 'no-such-library))
(newline)
(display (list? (hash-table-ref *env* 'library-path)))
(newline)
