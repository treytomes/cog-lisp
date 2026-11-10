;;; format.lisp -- the built-in format (specs/19-format.md AC-1): both conventions,
;;; every parameter and flag, the directives with structure, and the errors.
;;; Where Common Lisp specifies the output, the expected text is Common Lisp's.
;;; lisp-expert's own suites run beside this one (format-*-lisp-expert.lisp).
(load "../../lib/test.lisp")

(define-test "both conventions, told apart by the first argument (R-1)"
  (check (format #f "~A plus ~A is ~D." 2 3 5) "2 plus 3 is 5.")
  (check (format "SRFI 28: ~a and ~s" "x" "y") "SRFI 28: x and \"y\"")
  (check (with-output-to-string (lambda () (format #t "to ~A" "stdout"))) "to stdout")
  (check (let ((p (open-output-string))) (format p "~A" 1) (format p "~A" 2) (get-output-string p)) "12")
  (check-error (format #f) "no control string"))

(define-test "~A and ~S: mincol, colinc, minpad, padchar, and @ on the left (R-2)"
  (check (format #f "~10A|" "ab") "ab        |")
  (check (format #f "~10@A|" "ab") "        ab|")
  (check (format #f "~5,,,'-A|" "ab") "ab---|")
  (check (format #f "~3,2,1A|" "abcd") "abcd |")           ; minpad 1 already reaches mincol
  (check (format #f "~6,4,1A|" "ab") "ab     |")             ; minpad 1, then colinc 4
  (check (format #f "~8S|" "s") "\"s\"     |"))

(define-test "~D ~B ~O ~X and ~nR: padding, : digit groups, @ sign (R-2)"
  (check (format #f "~5D|~5,'0D|" 42 42) "   42|00042|")
  (check (format #f "~:D ~@D ~@D" 1234567 42 -42) "1,234,567 +42 -42")
  (check (format #f "~,,'.,4:D" 123456789) "1.2345.6789")
  (check (format #f "~X ~O ~B" 255 8 5) "FF 10 101")
  (check (format #f "~16R ~2,8,'0R" 255 5) "FF 00000101")
  (check (format #f "~D" 1/2) "1/2")                       ; not an integer: as ~A
  (check-error (format #f "~R" 5) "in words is not supported yet"))

(define-test "~F, ~C, and counts on ~% ~& ~~ (R-2, R-3)"
  (check (format #f "~,2F|~6,2F|~F" 3.14159 2.5 1.5) "3.14|  2.50|1.5")
  (check (format #f "~,0F ~,3F ~,1@F" 2 -0.5 1) "2. -0.500 +1.0")
  (check (format #f "~3,1,,'*F" 12345.6) "***")
  (check (format #f "~@C ~C" #\a #\b) "#\\a b")
  (check-error (format #f "~C" "a") "needs a character")
  (check (format #f "~3%x~2~") "\n\n\nx~~")
  (check (format #f "a~&b~%~&c") "a\nb\nc")
  (check (format #f "~2&x") "\nx"))

(define-test "~P plurals (R-3)"
  (check (format #f "~D item~:P, ~D item~:P" 1 3) "1 item, 3 items")
  (check (format #f "~D pon~:@P, ~D pon~:@P" 1 2) "1 pony, 2 ponies")
  (check (format #f "~P~P" 1 0) "s"))

(define-test "~* skips, backs up and goes to an argument (R-3)"
  (check (format #f "~A ~* ~A ~:* ~A" 1 2 3) "1  3  3")
  (check (format #f "~A ~A ~0@*~A" 1 2) "1 2 1")
  (check-error (format #f "~:*~A" 1) "moves past the arguments"))

(define-test "~{ ~} iteration, ~^ (R-3)"
  (check (format #f "~{~A~^, ~}" '(a b c)) "a, b, c")
  (check (format #f "~{~A~}" '()) "")
  (check (format #f "~:{<~A ~A>~}" '((1 2) (3 4))) "<1 2><3 4>")
  (check (format #f "~@{~A~^-~}" 1 2 3) "1-2-3")
  (check (format #f "~:@{[~A]~}" '(1) '(2)) "[1][2]")
  (check (format #f "~2{~A~}" '(a b c)) "ab")
  (check (format #f "~{x~:}" '()) "x")                      ; ~:} runs at least once
  (check (format #f "~{~}" "<~A>" '(1 2)) "<1><2>"))        ; the body from an argument

(define-test "~[ ~; ~] choice (R-3)"
  (check (format #f "~[zero~;one~;two~]" 1) "one")
  (check (format #f "~[zero~;one~]" 5) "")
  (check (format #f "~[zero~;one~:;many~]" 9) "many")
  (check (format #f "~1[zero~;one~]" 'unused) "one")       ; the parameter, not an argument
  (check (format #f "~:[no~;yes~] ~:[no~;yes~]" #t #f) "yes no")
  (check (format #f "~@[(~A)~] ~A" 5 'next) "(5) next")
  (check (format #f "~@[(~A)~]~A" #f 'next) "next"))

(define-test "~( ~) case conversion (R-3)"
  (check (format #f "~(HELLO World~)") "hello world")
  (check (format #f "~:(hello world~)") "Hello World")
  (check (format #f "~@(hello WORLD~)") "Hello world")
  (check (format #f "~:@(up ~A~)" "here") "UP HERE"))

(define-test "~?, v and # parameters, and ~newline (R-3)"
  (check (format #f "~? and ~A" "<~A>" '(inner) 'outer) "<inner> and outer")
  (check (format #f "~@? and ~A" "<~A>" 'used 'left) "<used> and left")
  (check (format #f "~v,'*D|~vA|" 6 42 4 "a") "****42|a   |")
  (check (format #f "~#[none~;one~;two~]" 'x 'y) "two")
  (check (format #f "joined ~
                     here") "joined here")
  (check (format #f "kept~:
  blanks") "kept  blanks"))

(define-test "errors name the control string and the position, and write nothing (R-3)"
  (check-error (format #f "~A ~A" 1) "too few arguments at position 3")
  (check-error (format #f "oops ~Q" 1) "unknown directive ~Q at position 5")
  (check-error (format #f "~{~A" '(1)) "~{ without its closing ~}")
  (check-error (format #f "a ~} b") "~} without its opening directive")
  (check-error (format #f "~[a~;b") "~[ without its closing ~]")
  (check-error (format #f "~(x") "~( without its closing ~)")
  (check-error (format #f "~{~A~}" 'not-a-list) "~{ needs a list")
  (check (let ((p (open-output-string)))
           (guard (e (#t #f)) (format p "fine so far ~{~A"))
           (get-output-string p))
         ""))

(define-test "format is documented, in the Output section"
  (check-true (string? (documentation 'format)))
  (check (documentation-category 'format) "Output"))

(run-tests)
