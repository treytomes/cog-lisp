;;; Moved from ~/projects/lisp-expert/expert/test/test-datetime.lisp with
;;; lib/datetime.lisp (specs/lisp-expert-libraries.md). Changed: its load lines only.
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

(run-tests)