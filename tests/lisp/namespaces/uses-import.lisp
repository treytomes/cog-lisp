;; uses-import.lisp -- a fixture program file: loaded by a file that imported
;; beta's area, it uses area without requiring beta itself
(define (area-twice w h) (* 2 (area w h)))
