;;; library-path.lisp -- require, *env*, and what load answers
;;; (specs/18-library-path.md). The fixtures are in tests/lisp/library/; running from
;;; another folder is checked by the runner suite (tests/phase-5-runner).
(load "../../lib/test.lisp")

(define library-test-loads 0)
;; the full path of a file in folder dir, one name per level
(define (file-in dir . names)
  (let loop ((ref [dir asFileReference]) (ns names))
    (if (null? ns) [ref fullName] (loop [ref / (car ns)] (cdr ns)))))
(define here [[[(current-load-path) asFileReference] parent] fullName])
(define fixtures (file-in here "library"))
(define home (hash-table-ref *env* 'home))

(define-test "*env* holds the keys of R-1"
  (check-true (string? (hash-table-ref *env* 'home)))
  (check-true [[(file-in home "lib" "core.lisp") asFileReference] exists])
  (check-true (memq (hash-table-ref *env* 'platform) '(windows linux)))
  (check-true (string? (hash-table-ref *env* 'version)))
  (check-true (list? (hash-table-ref *env* 'libraries)))
  (let ((path (hash-table-ref *env* 'library-path)))
    (check-true (pair? path))
    ;; cog-lisp's own lib folder comes last
    (check (let loop ((p path)) (if (null? (cdr p)) (car p) (loop (cdr p))))
           (file-in home "lib"))))

(define-test "require loads a library once, and answers its path"
  (set! (hash-table-ref *env* 'library-path) (cons fixtures (hash-table-ref *env* 'library-path)))
  (let ((first (require 'sample))
        (second (require 'sample)))
    (check first (file-in fixtures "sample.lisp"))
    (check second first)
    (check library-test-loads 1)
    (check (sample-greeting) "hello from sample")
    (check (cdr (assq 'sample (hash-table-ref *env* 'libraries))) first)))

(define-test "a name with a slash finds its subfolder"
  (check (require 'sub/nested) (file-in fixtures "sub" "nested.lisp"))
  (check (nested-answer) 42))

(define-test "a library that requires itself does not loop"
  (check-true (string? (require 'self)))
  (check (self-loaded) #t))

(define-test "a folder put first in the library path is searched first; cog-lisp's own are found"
  (check (require-path 'sample) (file-in fixtures "sample.lisp"))
  (check (require-path 'cl) (file-in home "lib" "cl.lisp"))
  (check (require-path 'test) (file-in home "lib" "test.lisp")))

(define-test "an unknown name, a file that is not there, and a name that is neither"
  (check (require-path 'no-such-library) #f)
  (check-error (require 'no-such-library) "require: no library named no-such-library in")
;; a string names a file beside this one (specs/27-namespaces.md)
  (check-error (require "cl") "require: no such file: cl")
  (check-error (require 42) "require: not a symbol or a file name: 42"))

(define-test "load answers the full path of the file it loaded (R-5)"
  (let ((before library-test-loads))
    (check (load "library/sample.lisp") (file-in fixtures "sample.lisp"))
    (check library-test-loads (+ before 1))))

(define-test "get-environment-variable answers a string, or #f"
  (check-true (string? (get-environment-variable "PATH")))
  (check (get-environment-variable "COGLISP_NO_SUCH_VARIABLE_FOR_TESTS") #f))

(run-tests)
