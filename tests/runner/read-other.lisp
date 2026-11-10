; a read the program runs fails: the error is at the running form, not at the
; offending character's place in the text it read (that is another text)
(read (open-input-string "\"\\q\""))
