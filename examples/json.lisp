; json.lisp -- JSON: json-read and json-write
;
; (json-read text) turns JSON text into LISP data, and (json-write value [port])
; turns it back. An object is a hash table with string keys, an array a vector,
; true and false are #t and #f, and null is (), the empty list (Common Lisp's
; nil). JSON has no lists, so () is never anything but null. In cog-lisp only #f
; is false, so test a null with null?, not with a plain if. An object's keys are
; written sorted, so the same table always writes the same text.

(define order (json-read "{\"id\": 7, \"items\": [\"tea\", \"café\"], \"paid\": false, \"note\": null}"))

(display (hash-table-ref order "id")) (newline)
(write (hash-table-ref order "items")) (newline)
(display (if (null? (hash-table-ref order "note")) "no note" "a note")) (newline)
(display (if (hash-table-ref order "paid") "paid" "not paid")) (newline)

(hash-table-set! order "paid" #t)
(json-write order) (newline)

(define summary (make-hash-table))
(hash-table-set! summary "count" (vector-length (hash-table-ref order "items")))
(hash-table-set! summary "nothing" '())
(json-write summary) (newline)
