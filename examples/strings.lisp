; strings.lisp -- strings and characters (Phase 7.8 sections 4 and 5)
; Indexes start at 0. Strings written in the source are constants; make-string,
; string-copy and string build ones you can change.

(define greeting "Hello, cog-lisp")
(display (string-length greeting))
(newline)
(display (list (string-ref greeting 0) (substring greeting 7 15)))
(newline)
(write (string-append "cog" "-" "lisp"))
(newline)

; Searching and splitting.
(display (list (string-index greeting #\,) (string-search greeting "lisp")))
(newline)
(write (string-split "red,green,,blue" #\,))
(newline)
(write (string-join '("a" "b" "c") ", "))
(newline)

; Comparing (by character code) and case.
(display (list (string<? "apple" "banana") (string=? "x" "x" "x") (string-ci=? "LISP" "lisp")))
(newline)
(display (list (string-upcase "shout") (string-downcase "QUIET")))
(newline)

; Characters and their codes.
(display (list (char->integer #\A) (integer->char 955) (char-upcase #\q)))
(newline)
(display (map (lambda (c) (list c (char-alphabetic? c) (char-numeric? c)))
              (string->list "a1 ")))
(newline)

; Numbers to and from text.
(display (list (string->number "42") (string->number "2.5e3") (string->number "ff" 16)
               (string->number "forty-two") (number->string 255 2)))
(newline)

; Changing a string: copy the constant first.
(define name (string-copy "cat"))
(string-set! name 0 #\b)
(display name)
(newline)
(display (guard (e ((error-object? e) (error-object-message e)))
  (string-set! "cat" 0 #\b)))
(newline)

; A Caesar cipher, one character at a time.
(define (shift-char c k)
  (if (char-alphabetic? c)
      (let ((base (if (char-upper-case? c) 65 97)))
        (integer->char (+ base (modulo (+ (- (char->integer c) base) k) 26))))
      c))
(define (caesar s k) (list->string (map (lambda (c) (shift-char c k)) (string->list s))))
(define secret (caesar "Attack at dawn!" 3))
(display secret)
(newline)
(display (caesar secret -3))
(newline)
