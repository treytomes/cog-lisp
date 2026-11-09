;; format.lisp -- format: ~A display, ~S write, ~D, ~,2F, ~% newline
(display (format #f "~A has ~D item~:P, ~,2F" "Ada" 3 7.5)) (newline)
(display (format #f "~{~A~^, ~}" (list 1 2 3))) (newline)
(format #t "~S~%" "x")   ; #t: to the output
