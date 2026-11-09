; format.lisp -- format: text with ~ directives, as in Common Lisp
;
; (format #f control arg ...) answers a string, (format #t ...) writes to the
; current output, and (format port ...) to a port; (format control arg ...),
; with the control string first, answers a string as SRFI 28 does. Each ~
; directive takes what it needs from the arguments: ~A displays, ~S writes,
; ~D ~X ~B ~O print integers, ~F floats, ~% is a newline. Parameters and flags
; go between the ~ and the letter: ~5D pads to five columns, ~:D groups digits
; with commas, ~,2F rounds to two decimals. ~{ ~} loops over a list, ~^ leaves
; it before the separator after the last element, ~[ ~; ~] chooses, ~:P and
; ~:@P make plurals, and ~( ~) changes case.

(define (show s) (display s) (newline))

(show (format #f "~A has ~D item~:P, worth ~,2F." "Ada" 3 7.5))
(show (format #f "~5D|~5,'0D|~:D" 42 42 1234567))
(show (format #f "#x~X is ~D" 255 255))
(show (format #f "~{~A~^, ~}" '(red green blue)))
(show (format #f "~:{~A=~A ~}" '((a 1) (b 2))))
(show (format #f "~D pon~:@P and ~D pon~:@P" 1 3))
(show (format #f "~[none~;one~;two~:;many~] of them" 7))
(show (format #f "~:[off~;on~]" #t))
(show (format #f "~:(the quick brown fox~)"))
(show (format "SRFI 28 style: ~a, ~s" "plain" "written"))
(format #t "straight to the output~%")
