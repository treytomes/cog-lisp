; counter.lisp -- a library with private state and a private helper
(library counter (export next! tally note))

(define count 0)                                  ; private: not exported
(define (%label x) (string-append "<" (symbol->string x) ">"))

(define (next!) (set! count (+ count 1)) count)

;; hygienic: the template's %label means this library's, wherever tally is used
(define-syntax tally
  (syntax-rules ()
    ((_ what) (string-append (%label what) " counted " (number->string count)))))

;; not hygienic: the expansion is read where note is used, so it names the
;; helper in full
(define-macro (note what)
  `(string-append "note " (counter:%label ,what)))
