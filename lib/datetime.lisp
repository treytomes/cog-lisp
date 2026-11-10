;;; datetime.lisp -- dates, durations and intervals, over Pharo's DateAndTime and
;;; Duration. Load with (require 'datetime). From ~/projects/lisp-expert's
;;; datetime.lisp (specs/22-lisp-expert-libraries.md R-3); changed: its Smalltalk
;;; names are written (smalltalk DateAndTime), (smalltalk Duration).
;;;
; datetime.lisp -- idiomatic Lisp layer over Pharo DateAndTime / Duration.
; Absolute datetimes are Smalltalk DateAndTime objects; durations are Durations.
; Intervals are (start . end) pairs of datetimes.

;;; --- Absolute datetimes ------------------------------------------------

;;; A library (specs/27-namespaces.md): (require 'datetime) brings these names in; each
;;; is also datetime:name everywhere, and the names not exported are private.

(library datetime
  (export datetime-now datetime-from-unix datetime-from-date datetime-from-parts
         datetime->unix datetime->string datetime-from-string datetime-year
         datetime-month datetime-day datetime-hour datetime-minute
         datetime-second datetime-add datetime-subtract datetime-diff-seconds
         datetime<? datetime<=? datetime=? datetime>? datetime>=?
         duration-seconds duration-minutes duration-hours duration-days
         duration->seconds duration->string duration-add duration-subtract
         duration<? duration<=? duration=? make-interval interval-start
         interval-end interval-contains? interval-duration-seconds
         interval->string))

(define (datetime-now)
	"Current date and time."
	[(smalltalk DateAndTime) now]
)

(define (datetime-from-unix ts)
	"DateAndTime from a Unix timestamp (seconds)."
	[(smalltalk DateAndTime) fromUnixTime: ts]
)

(define (datetime-from-date year month day)
	"DateAndTime at midnight on the given date."
	[(smalltalk DateAndTime) year: year month: month day: day]
)

(define (datetime-from-parts year month day hour minute second)
	"DateAndTime from full components."
	[(smalltalk DateAndTime) year: year month: month day: day hour: hour minute: minute second: second]
)

(define (datetime->unix dt)
	"Unix timestamp (seconds) for dt."
	[dt asUnixTime]
)

(define (datetime->string dt)
	"Readable string for dt."
	[dt asString]
)

;; ISO 8601 (cog-lisp specs/23-lisp-expert-review.md R-4): YYYY-MM-DD, optionally
;; THH:MM, :SS and .fraction, optionally Z or +HH:MM / -HH:MM. A string without
;; an offset is UTC: Pharo's own fromString: would read it as local time, which
;; makes an answer depend on the machine it runs on.
(define (datetime-from-string s)
  "(datetime-from-string string)
The datetime an ISO 8601 string names: 2026-11-09, 2026-11-09T13:00, 2026-11-09T13:00:05.25+01:00. Without an offset it is UTC. The inverse of datetime->string."
  (let ((n (if (string? s) (string-length s) -1)))
    (define (fail)
      (error (string-append "datetime-from-string: not an ISO 8601 date and time: "
                            (with-output-to-string (lambda () (write s))))))
    (define (at? i c) (and (< i n) (eq? (string-ref s i) c)))
    (define (digits start end)
      (if (> end n) (fail))
      (let loop ((i start))
        (if (< i end)
            (if (char-numeric? (string-ref s i)) (loop (+ i 1)) (fail))
            (string->number (substring s start end)))))
    (define (digits-from start)
      (let loop ((i start))
        (if (and (< i n) (char-numeric? (string-ref s i))) (loop (+ i 1)) i)))
    (if (< n 10) (fail))
    (if (not (and (at? 4 #\-) (at? 7 #\-))) (fail))
    (let ((year (digits 0 4)) (month (digits 5 7)) (day (digits 8 10))
          (hour 0) (minute 0) (second 0) (nano 0) (sign 1) (off-h 0) (off-m 0)
          (pos 10))
      (when (< pos n)
        (if (not (and (at? 10 #\T) (at? 13 #\:))) (fail))
        (set! hour (digits 11 13))
        (set! minute (digits 14 16))
        (set! pos 16)
        (when (at? 16 #\:)
          (set! second (digits 17 19))
          (set! pos 19)
          (when (at? 19 #\.)
            (let ((end (digits-from 20)))
              (if (= end 20) (fail))
              (let ((frac (substring s 20 (min end 29))))
                (set! nano (* (string->number frac)
                              (expt 10 (- 9 (string-length frac))))))
              (set! pos end))))
        (cond ((= pos n) #t)
              ((and (at? pos #\Z) (= (+ pos 1) n)) #t)
              ((and (or (at? pos #\+) (at? pos #\-)) (at? (+ pos 3) #\:) (= (+ pos 6) n))
               (set! sign (if (at? pos #\-) -1 1))
               (set! off-h (digits (+ pos 1) (+ pos 3)))
               (set! off-m (digits (+ pos 4) (+ pos 6))))
              (else (fail))))
      (if (not (and (<= 1 month 12) (<= 1 day 31) (<= hour 23) (<= minute 59)
                    (<= second 59) (<= off-h 23) (<= off-m 59)))
          (fail))
      (guard (e (#t (fail)))
        [(smalltalk DateAndTime) year: year month: month day: day hour: hour minute: minute
           second: second nanoSecond: nano
           offset: [(smalltalk Duration) days: 0 hours: (* sign off-h) minutes: (* sign off-m) seconds: 0]]))))

(define (datetime-year dt)
  "Returns the year component of a datetime." [dt year])
(define (datetime-month dt)
  "Returns the month component of a datetime." [dt monthIndex])
(define (datetime-day dt)
  "Returns the day component of a datetime." [dt dayOfMonth])
(define (datetime-hour dt)
  "Returns the hour component of a datetime." [dt hour])
(define (datetime-minute dt)
  "Returns the minute component of a datetime." [dt minute])
(define (datetime-second dt)
  "Returns the second component of a datetime." [dt second])

(define (datetime-add dt dur)
	"dt + dur (dur is a Duration)."
	[dt + dur]
)

(define (datetime-subtract dt dur)
	"dt - dur (dur is a Duration)."
	[dt - dur]
)

(define (datetime-diff-seconds a b)
	"Seconds between two datetimes (a - b)."
	[[a - b] asSeconds]
)

(define (datetime<? a b)
  "Compares two datetimes for less-than." [a < b])
(define (datetime<=? a b)
  "Compares two datetimes for less-than-or-equal." [a <= b])
(define (datetime=? a b)
  "Compares two datetimes for equality." [a = b])
(define (datetime>? a b)
  "Compares two datetimes for greater-than." [a > b])
(define (datetime>=? a b)
  "Compares two datetimes for greater-than-or-equal." [a >= b])

;;; --- Durations (relative) ----------------------------------------------

(define (duration-seconds n)
	"Duration of n seconds."
	[(smalltalk Duration) seconds: n]
)

(define (duration-minutes n)
	"Duration of n minutes."
	[(smalltalk Duration) minutes: n]
)

(define (duration-hours n)
	"Duration of n hours."
	[(smalltalk Duration) hours: n]
)

(define (duration-days n)
	"Duration of n days."
	[(smalltalk Duration) days: n]
)

(define (duration->seconds dur)
	"Seconds in dur."
	[dur asSeconds]
)

(define (duration->string dur)
	"Readable string for dur."
	[dur printString]
)

(define (duration-add a b)
  "Adds two durations."
	[a + b]
)

(define (duration-subtract a b)
  "Subtracts the second duration from the first."
	[a - b]
)

(define (duration<? a b)
  "Tests whether the first duration is shorter than the second."
	(< [a asSeconds] [b asSeconds])
)

(define (duration<=? a b)
  "Tests whether the first duration is no longer than the second."
	(<= [a asSeconds] [b asSeconds])
)

(define (duration=? a b)
  "Tests whether two durations are equal."
	(= [a asSeconds] [b asSeconds])
)

;;; --- Intervals ---------------------------------------------------------

(define (make-interval start end)
	"Interval from start datetime to end datetime."
	(cons start end))

(define (interval-start iv)
  "Returns the start datetime of an interval." (car iv))
(define (interval-end iv)
  "Returns the end datetime of an interval." (cdr iv))

(define (interval-contains? iv dt)
	"True if dt lies within iv (inclusive on both ends)."
	(and (datetime>=? dt (interval-start iv))
	     (datetime<=? dt (interval-end iv))))

(define (interval-duration-seconds iv)
	"Length of iv in seconds."
	[[ (interval-end iv) - (interval-start iv) ] asSeconds])

(define (interval->string iv)
  "Returns a readable representation of an interval."
	(string-append (datetime->string (interval-start iv))
	               " .. "
	               (datetime->string (interval-end iv))))
