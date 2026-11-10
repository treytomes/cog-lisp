;;; Moved from ~/projects/lisp-expert/expert/test/test-datetime.lisp with
;;; lib/datetime.lisp (specs/22-lisp-expert-libraries.md). Changed: its load lines only.
;;; Unit tests for expert/datetime.lisp
;;;
;;; Run with:  ./cog-lisp.sh expert/test/test-datetime.lisp

(load "../../lib/test.lisp")
(require 'datetime)

(define-test datetime-unix-roundtrip
  (check (datetime->unix (datetime-from-unix 1794163445)) 1794163445))

(define-test datetime-parts
  (let ((dt (datetime-from-parts 2026 11 8 13 44 5)))
    (check (datetime-year dt) 2026)
    (check (datetime-month dt) 11)
    (check (datetime-day dt) 8)
    (check (datetime-hour dt) 13)
    (check (datetime-minute dt) 44)
    (check (datetime-second dt) 5)))

(define-test datetime-from-date
  (let ((dt (datetime-from-date 2026 11 8)))
    (check (datetime-year dt) 2026)
    (check (datetime-month dt) 11)
    (check (datetime-day dt) 8)
    (check (datetime-hour dt) 0)))

(define-test datetime-arithmetic
  (let* ((dt (datetime-from-unix 1000))
         (dur (duration-seconds 3600))
         (dt2 (datetime-add dt dur)))
    (check (datetime-diff-seconds dt2 dt) 3600)
    (check (datetime->unix (datetime-subtract dt2 dur)) 1000)))

(define-test datetime-comparison
  (let ((a (datetime-from-unix 1000))
        (b (datetime-from-unix 2000)))
    (check-true (datetime<? a b))
    (check-true (datetime<=? a b))
    (check-true (datetime=? a a))
    (check-true (datetime>? b a))
    (check-true (datetime>=? b a))))

(define-test duration-conversion
  (let ((dur (duration-hours 2)))
    (check (duration->seconds dur) 7200)
    (check-true (duration<? (duration-seconds 10) (duration-seconds 20)))
    (check (duration->string dur) "0:02:00:00")))

(define-test interval-contains
  (let* ((s (datetime-from-unix 1000))
         (e (datetime-from-unix 2000))
         (iv (make-interval s e)))
    (check-true (interval-contains? iv (datetime-from-unix 1500)))
    (check-false (interval-contains? iv (datetime-from-unix 500)))
    (check (interval-duration-seconds iv) 1000)))

(define-test datetime-visualization
  (let ((dt (datetime-from-unix 1794163445)))
    (check-true (string? (datetime->string dt)))
    (check-true (string? (interval->string (make-interval dt (datetime-add dt (duration-seconds 60))))))))

;; datetime-from-string (specs/23-lisp-expert-review.md R-4, AC-3). 2026-11-09T13:00Z
;; is Unix time 1794229200 wherever the machine is.
(define-test "datetime-from-string reads every ISO 8601 form"
  (check (datetime->unix (datetime-from-string "2026-11-09")) 1794182400)
  (check (datetime->unix (datetime-from-string "2026-11-09T13:00")) 1794229200)
  (check (datetime->unix (datetime-from-string "2026-11-09T13:00:05")) 1794229205)
  (check (datetime->unix (datetime-from-string "2026-11-09T13:00:05.25")) 1794229205)
  (check (datetime->unix (datetime-from-string "2026-11-09T13:00Z")) 1794229200)
  (check (datetime->unix (datetime-from-string "2026-11-09T14:00+01:00")) 1794229200)
  (check (datetime->unix (datetime-from-string "2026-11-09T07:00-06:00")) 1794229200)
  (check (datetime->unix (datetime-from-string "2026-11-09T13:30:00+00:30")) 1794229200)
  (check (datetime-second (datetime-from-string "2026-11-09T13:00:05.25Z")) 5))

(define-test "a string without an offset is UTC, not the machine's zone"
  (check (datetime->unix (datetime-from-string "1970-01-01T00:00")) 0)
  (check (datetime->unix (datetime-from-string "1970-01-01")) 0))

(define-test "datetime-from-string is the inverse of datetime->string"
  (let ((dt (datetime-from-unix 1794163445)))
    (check (datetime->unix (datetime-from-string (datetime->string dt))) 1794163445))
  (let ((dt (datetime-from-string "2026-11-09T13:00:05.25+01:00")))
    (check-true (datetime=? (datetime-from-string (datetime->string dt)) dt))))

(define-test "a string it cannot read is an error naming it"
  (for-each (lambda (s)
              (check-error (datetime-from-string s) "datetime-from-string: not an ISO 8601 date and time"))
            '("hello" "" "2026-11-9" "2026/11/09" "2026-13-01" "2026-11-09T25:00"
              "2026-11-09T13:00+1" "2026-11-09T13:00Zjunk" "2026-11-09T13:00:05." "2026-02-30"))
  (check-error (datetime-from-string 42) "datetime-from-string: not an ISO 8601 date and time: 42"))

(run-tests)