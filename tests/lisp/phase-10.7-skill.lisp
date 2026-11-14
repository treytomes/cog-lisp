;;; phase-10.7-skill.lisp -- the skill for agents is what docs/skill/ and the image
;;; generate, follows Bionic's rules, and says only what is true
;;; (specs/16-phase-10-documentation-and-editor.md step 10.7, AC-7). After changing
;;; docs/skill/ or documentation, run ./cog-lisp.sh tools/generate-docs.lisp and
;;; commit what it writes. The examples' outputs are checked by the runner suite
;;; (tests/phase-5-runner), like examples/.
(load "../../lib/test.lisp")
(load "../../tools/docs.lisp")

(define-test "AC-7 SKILL.md and reference.md are what the generator writes"
  (for-each (lambda (f)
              (check (list (car f) (and (docs-file? (car f)) (string=? (cdr f) (docs-file-text (car f)))))
                     (list (car f) #t)))
            (skill-files)))

;; the front matter's fields: (key . value), between the first two --- lines
(define (front-matter text)
  (let loop ((lines (cdr (docs-lines text))) (acc '()))
    (cond ((null? lines) #f)
          ((string=? (string-trim (car lines)) "---") (reverse acc))
          (else (let* ((line (car lines)) (colon (string-search line ": ")))
                  (loop (cdr lines)
                        (if colon (cons (cons (substring line 0 colon) (substring line (+ colon 2))) acc) acc)))))))

;; Bionic: kebab-case, 1 to 63 characters, no leading, trailing or doubled hyphen
(define (bionic-name? s)
  (and (> (string-length s) 0) (< (string-length s) 64)
       (not (char=? (string-ref s 0) #\-))
       (not (char=? (string-ref s (- (string-length s) 1)) #\-))
       (not (string-search s "--"))
       (let loop ((cs (string->list s)))
         (or (null? cs)
             (and (or (char-lower-case? (car cs)) (char-numeric? (car cs)) (char=? (car cs) #\-))
                  (loop (cdr cs)))))))

(define-test "AC-7 the front matter follows Bionic's rules"
  (let* ((text (skill-markdown))
         (fields (front-matter text))
         (name (cdr (assoc "name" fields)))
         (description (cdr (assoc "description" fields))))
    (check-true (docs-starts? text "---\n"))
    (check name "cog-lisp")
    (check-true (bionic-name? name))
    (check-false (bionic-name? "Cog--Lisp"))
    (check (substring skill-folder (- (string-length skill-folder) (string-length name))) name)
    (check-true (assoc "display-name" fields))
    (check-true (< (string-length description) 150))))

(define-test "AC-7 SKILL.md stays within its budget: 10 KB, about 2,500 tokens"
  (check-true (< (string-length (skill-markdown)) 10240)))

(define-test "AC-7 every example is in SKILL.md once, with its output"
  (check (docs-sort-strings (skill-marked-examples)) (skill-example-names))
  (check-true (>= (length (skill-example-names)) 8))
  (for-each (lambda (name)
              (check (list name (docs-file? (skill-example-path name ".expected"))) (list name #t)))
            (skill-example-names))
  (check-true (string-search (skill-markdown) "an-error.lisp:4:1: error: car: not a pair: 5")))

;; what running some code does: (error message) or (answers printed-text)
(define (outcome-of source)
  (guard (e (#t (list 'error (test:%message e))))  ; the test library's own, private
    (list 'answers (with-output-to-string (lambda () (eval-all source))))))

(define-test "AC-7 each trap's wrong code does what SKILL.md says"
  (for-each (lambda (trap)
              (let ((said (vector-ref trap 2)) (did (outcome-of (vector-ref trap 1))))
                (check (list (vector-ref trap 1) (car did)) (list (vector-ref trap 1) (car said)))
                (check (list (vector-ref trap 1)
                             (if (eq? (car said) 'error)
                                 (and (string-search (car (cdr did)) (car (cdr said))) #t)
                                 (car (cdr did))))
                       (list (vector-ref trap 1)
                             (if (eq? (car said) 'error) #t (car (cdr said)))))))
            (skill-traps))
  (check-true (>= (length (skill-traps)) 8)))

(define-test "AC-7 each trap's right code runs"
  (for-each (lambda (trap)
              (when (vector-ref trap 3)
                (check (list (vector-ref trap 3) (car (outcome-of (vector-ref trap 3))))
                       (list (vector-ref trap 3) 'answers))))
            (skill-traps)))

;; specs/35-mcp-server.md R-22, AC-14: mcp.md teaches the MCP server's tools, all
;; of them and no others, and SKILL.md points to it
(define (tool-names-in text)
  (let loop ((i 0) (acc '()))
    (let ((at (string-search (substring text i (string-length text)) "lisp_")))
      (if (not at)
          ;; "the lisp_ tools" names the family, not a tool
          (docs-sort-strings (delete (string-copy "lisp_") (delete-duplicates acc)))
          (let* ((start (+ i at))
                 (end (let scan ((j (+ start 5)))
                        (if (and (< j (string-length text))
                                 (let ((c (string-ref text j))) (or (char-lower-case? c) (char=? c #\_))))
                            (scan (+ j 1))
                            j))))
            (loop end (cons (substring text start end) acc)))))))

(define-test "AC-14 mcp.md names every tool of the MCP server, and only those"
  (load "../../lib/mcp.lisp")
  (check (tool-names-in (skill-mcp-markdown))
         (docs-sort-strings (map (lambda (tool) (vector-ref tool 0)) (eval 'mcp-tools)))))

(define-test "AC-14 mcp.md stays small, and SKILL.md points to it"
  (check-true (< (string-length (skill-mcp-markdown)) 3072))
  (check-true (string-search (skill-markdown) "`mcp.md`")))

;; specs/36-console-driver.md R-5, AC-4: console.md teaches the console driver,
;; stays small, SKILL.md points to it, and the driver it names is there
(define-test "36 AC-4 console.md stays small, SKILL.md points to it, and its driver exists"
  (check-true (< (string-length (skill-console-markdown)) 3072))
  (check-true (string-search (skill-markdown) "`console.md`"))
  (check-true (string-search (skill-console-markdown) "tools/console_driver.py"))
  (check-true (file-exists? (docs-path "tools/console_driver.py"))))

;; every step and key console.md teaches is one the driver knows (its docstring
;; lists them), so the page and the driver cannot drift apart
(define-test "36 AC-4 every step and key console.md names is the driver's"
  (let ((driver (docs-file-text "tools/console_driver.py"))
        (page (skill-console-markdown)))
    (for-each (lambda (word)
                (check (list word (and (string-search page word) #t)) (list word #t))
                (check (list word (and (string-search driver word) #t)) (list word #t)))
              '("send " "type " "key " "expect " "expect-re" "expect-screen " "expect-screen-re" "refute " "print" "exit "
                "enter" "up" "down" "tab" "esc" "ctrl-c" "eof" "--cwd" "--transcript"))))

(define-test "AC-7 the reference lists every built-in, a line each"
  (let ((text (skill-reference)))
    (for-each (lambda (e) (check-true (string-search text (docs-entry-call e)))) (builtin-entries))
    (check-true (string-search text "`` (quasiquote template), `template ``"))))

(run-tests)
