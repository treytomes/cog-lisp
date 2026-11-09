;;; datetime.lisp -- dates, durations and intervals, over Pharo's DateAndTime and
;;; Duration. Load with (require 'datetime). From ~/projects/lisp-expert's
;;; datetime.lisp (specs/lisp-expert-libraries.md R-3); changed: its Smalltalk
;;; names are written (smalltalk DateAndTime), (smalltalk Duration).
;;;
; datetime.lisp -- idiomatic Lisp layer over Pharo DateAndTime / Duration.
; Absolute datetimes are Smalltalk DateAndTime objects; durations are Durations.
; Intervals are (start . end) pairs of datetimes.

;;; --- Absolute datetimes ------------------------------------------------

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
