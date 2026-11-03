; interop-streams.lisp -- word frequencies with Smalltalk streams and a Bag (Phase 7.6)
; A small, practical program: LISP for the logic, Smalltalk's library for the parts.

(define text "the quick brown fox jumps over the lazy dog the fox runs and the dog sleeps")

; Split the text into words with a ReadStream.
(define (words-of s)
  (let ((in [ReadStream on: s])
        (words [OrderedCollection new]))
    (let loop ()
      (when (not [in atEnd])
        (let ((w [in upTo: #\space]))
          (when (not [w isEmpty]) [words add: w]))
        (loop)))
    words))

; Count them with a Bag, then sort by count (and by word, for ties).
(define (frequencies words)
  (let ((bag [Bag new]))
    [bag addAll: words]
    [[[bag asSet] asArray] asSortedCollection:
       (lambda (a b)
         (let ((ca [bag occurrencesOf: a])
               (cb [bag occurrencesOf: b]))
           (or (> ca cb) (and (= ca cb) (<= [a compare: b] 2)))))]))

(define words (words-of text))
(display [words size])
(display " words, ")
(display [[words asSet] size])
(display " different")
(newline)

; The top four, written to a Smalltalk WriteStream and displayed.
(define out [WriteStream on: [String new]])
(define (report word count)
  [out nextPutAll: word]
  [out nextPutAll: ": "]
  [out print: count]
  [out nextPut: #\newline])
(define bag [Bag new])
[bag addAll: words]
(for-each (lambda (w) (report w [bag occurrencesOf: w]))
          (array->list [[(frequencies words) asArray] first: 4]))
(display [out contents])
