;;; Copied from ~/projects/lisp-expert/format-test.lisp (the owner's), to check that
;;; cog-lisp's built-in format passes it with lisp-expert's format.lisp not loaded
;;; (specs/format.md AC-2). Changed: the path to lib/test.lisp; no (load "format.lisp"); t is defined, as lib/cl.lisp would.
;;; format-test.lisp -- unit tests for the format procedure
;;;
;;; Adjust the load path to wherever this file lives relative to lib/test.lisp.
;;; (load resolves paths relative to the file being loaded.)

(load "../../lib/test.lisp")
(define t #t)   ; Common Lisp's, which the first test uses

;;; Destinations ---------------------------------------------------------

(define-test format-destination-t
  ;; The original motivating example: #t writes to the current output.
  (check (with-output-to-string
           (lambda () (format t "~A plus ~A equals ~A.~%" 2 3 (+ 2 3))))
         "2 plus 3 equals 5.\n")
  (check (with-output-to-string
           (lambda () (format #t "plain")))
         "plain"))

(define-test format-destination-false
  ;; #f answers a string.
  (check (format #f "~A plus ~A" 1 2) "1 plus 2")
  (check-true (string? (format #f "x"))))

(define-test format-destination-port
  (check (let ((p (open-output-string)))
           (format p "to a port: ~A" 42)
           (get-output-string p))
         "to a port: 42")
  ;; Two calls to the same port accumulate.
  (check (let ((p (open-output-string)))
           (format p "a~A" 1)
           (format p "b~A" 2)
           (get-output-string p))
         "a1b2"))

;;; Directives -----------------------------------------------------------

(define-test format-display-and-write
  (check (format #f "~A" "hi") "hi")
  (check (format #f "~S" "hi") "\"hi\"")
  (check (format #f "~S and ~A" "hi" "hi") "\"hi\" and hi")
  (check (format #f "~A" '(1 2 3)) "(1 2 3)")
  (check (format #f "~S" 'foo) "foo")
  (check (format #f "~A" #\x) "x")
  (check (format #f "~S" #\x) "#\\x"))

(define-test format-numbers
  (check (format #f "~D" 255) "255")
  (check (format #f "~D" -7) "-7")
  (check (format #f "~X" 255) "FF")
  (check (format #f "~B" 5) "101")
  (check (format #f "~O" 8) "10")
  (check (format #f "~X ~B ~O" 255 5 8) "FF 101 10")
  ;; Non-integers fall back to ~A.
  (check (format #f "~D" "not a number") "not a number"))

(define-test format-char-newline-tilde
  (check (format #f "~C~C" #\o #\k) "ok")
  (check (format #f "a~%b") "a\nb")
  (check (format #f "100~~ sure") "100~ sure")
  (check (format #f "~~~~") "~~"))

(define-test format-case-insensitive-directives
  (check (format #f "~a ~s ~d" "x" "x" 1) "x \"x\" 1")
  (check (format #f "~x" 255) "FF"))

;;; Plain text and edge cases -------------------------------------------

(define-test format-plain-text
  (check (format #f "no directives") "no directives")
  (check (format #f "") "")
  ;; Extra arguments are ignored, as in Common Lisp.
  (check (format #f "~A" 1 2 3) "1"))

(define-test format-long-control-string
  ;; Every loop call is a tail call, so length should not matter.
  (check (string-length (format #f (make-string 10000 #\a))) 10000)
  ;; 5000 tildes are 2500 "~~" pairs, so 2500 tildes come out.
  (check (string-length (format #f (make-string 5000 #\~))) 2500))

;;; Errors ---------------------------------------------------------------

(define-test format-errors
  (check-error (format #f "~A") "too few")
  (check-error (format #f "~A ~A" 1) "too few")
  (check-error (format #f "oops ~Q" 1) "unknown directive")
  (check-error (format #f "ends with ~") "lone"))

;;; Documentation --------------------------------------------------------

(define-test format-documentation
  (check-true (string? (documentation 'format))))

(run-tests)