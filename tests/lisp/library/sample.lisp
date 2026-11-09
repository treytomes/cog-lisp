;; sample.lisp -- a library for tests/lisp/library-path.lisp; counts its loads
(set! library-test-loads (+ library-test-loads 1))
(define (sample-greeting) "hello from sample")
