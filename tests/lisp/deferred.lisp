;;; deferred.lisp -- deferred work is never lost (specs/35-mcp-server.md R-23,
;;; AC-15): every item of a spec's "Later" section, an id L-<spec>.<n>, is on
;;; PROJECT-PLAN.md's list "Deferred: to pick up", and every id on that list is
;;; in its spec's "Later" section. specs/README.md's workflow says how.
(load "../../lib/test.lisp")

(define here [[[[(smalltalk LispLoadPath) value] asFileReference] parent] fullName])
(define root (string-append here "/../.."))
(define (read-file path) [[[path asFileReference] contents] asString])
(define (lines-of text) (map string-trim (string-split text #\newline)))
(define (starts? s prefix) (string-prefix? prefix s))

;; the ids L-<digits>.<digits> in a text, in order
(define (ids-in text)
  (let ((n (string-length text)))
    (define (digits-from i) (let loop ((j i)) (if (and (< j n) (char-numeric? (string-ref text j))) (loop (+ j 1)) j)))
    (let loop ((i 0) (acc '()))
      (cond ((>= i (- n 1)) (reverse acc))
            ((and (eq? (string-ref text i) #\L) (eq? (string-ref text (+ i 1)) #\-)
                  (or (= i 0) (not (char-alphabetic? (string-ref text (- i 1))))))
             (let* ((a (digits-from (+ i 2))))
               (if (and (> a (+ i 2)) (< a n) (eq? (string-ref text a) #\.))
                   (let ((b (digits-from (+ a 1))))
                     (if (> b (+ a 1))
                         (loop b (cons (substring text i b) acc))
                         (loop (+ i 1) acc)))
                   (loop (+ i 1) acc))))
            (else (loop (+ i 1) acc))))))

;; the heading level of a line (# count), or #f
(define (heading-level line)
  (and (starts? line "#")
       (let loop ((k 0)) (if (and (< k (string-length line)) (eq? (string-ref line k) #\#)) (loop (+ k 1)) k))))

;; the text of the section whose heading satisfies wanted?, up to the next
;; heading of its level or above; "" when there is none
(define (section text wanted?)
  (let loop ((lines (lines-of text)) (level #f) (acc '()))
    (cond ((null? lines) (string-join (reverse acc) "\n"))
          ((not level)
           (if (and (heading-level (car lines)) (wanted? (car lines)))
               (loop (cdr lines) (heading-level (car lines)) '())
               (loop (cdr lines) #f acc)))
          ((let ((l (heading-level (car lines)))) (and l (<= l level)))
           (string-join (reverse acc) "\n"))
          (else (loop (cdr lines) level (cons (car lines) acc))))))

(define (later-heading? line) (string-suffix? "Later" line))

;; (file-name . ids) for each spec with a "Later" section
(define spec-files
  (filter (lambda (name) (and (string-suffix? ".md" name) (char-numeric? (string-ref name 0))))
          (map (lambda (f) [f basename])
               (vector->list [[[(string-append root "/specs") asFileReference] files] asArray]))))

(define spec-later
  (filter-map (lambda (name)
                (let ((ids (ids-in (section (read-file (string-append root "/specs/" name)) later-heading?))))
                  (and (pair? ids) (cons name ids))))
              spec-files))

(define plan-list
  (section (read-file (string-append root "/PROJECT-PLAN.md"))
           (lambda (line) (string-suffix? "Deferred: to pick up" line))))

(define plan-ids (ids-in plan-list))
(define spec-ids (append-map cdr spec-later))

(define-test "the plan has its list, and at least one deferred item"
  (check-true (> (string-length plan-list) 0))
  (check-true (pair? spec-ids)))

(define-test "every deferred item of a spec is on the plan's list"
  (for-each (lambda (id) (check (list id (and (member id plan-ids) #t)) (list id #t))) spec-ids))

(define-test "every item on the plan's list is in a spec's Later section"
  (for-each (lambda (id) (check (list id (and (member id spec-ids) #t)) (list id #t))) plan-ids))

(define-test "an item's id names its own spec: L-35.1 is in 35-*.md"
  (for-each (lambda (entry)
              (let ((number (substring (car entry) 0 (string-index (car entry) #\-))))
                (for-each (lambda (id) (check (list id (starts? id (string-append "L-" number "."))) (list id #t)))
                          (cdr entry))))
            spec-later))

(define-test "the checks catch what they are for"
  (check (ids-in "a **L-35.1 x** and L-7.12, not XL-3.4 or L-5") '("L-35.1" "L-7.12"))
  (check (section "# a\n## 10. Later\n- L-1.1\n## 11. Next\n- L-1.2" later-heading?) "- L-1.1")
  ;; an id missing from the list is found
  (check-false (member "L-35.1" (ids-in (section "### Deferred: to pick up\n| L-34.9 |\n### Phase 11"
                                                  (lambda (l) (string-suffix? "Deferred: to pick up" l)))))))

(run-tests)
