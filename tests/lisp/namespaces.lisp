;;; namespaces.lisp -- libraries, exports and imports (specs/namespaces.md AC-2,
;;; AC-3), with the fixture libraries in namespaces/. An import serves the forms
;;; compiled after its require: a require inside a test runs after the test's
;;; body was compiled, so the body reaches what it imported through eval.
(load "../../lib/test.lisp")

(require "namespaces/alpha.lisp")
(require "namespaces/beta.lisp" 'prefix 'b:)

(define-test "two libraries export rule: one unqualified, one through a prefix"
  (check (rule 1) "alpha 1")
  (check (b:rule 2) "beta 2")
  (check (alpha:rule 3) "alpha 3")                 ; full names always work
  (check (beta:rule 4) "beta 4"))

(define-test "a program's own definition, beside the imports"
  (eval '(define (my-rule n) (list 'mine n)))
  (check (eval '(my-rule 5)) '(mine 5))
  (check (rule 1) "alpha 1"))

(define-test "imports lists each name with its full name"
  (check (assq 'rule (imports)) '(rule . alpha:rule))
  (check (assq 'b:area (imports)) '(b:area . beta:area))
  (check (assq 'area (imports)) #f))

(define-test "private names: no import brings them, the full name reaches them"
  (check-error (eval 'hidden) "unbound variable: hidden")
  (check-error (eval '(%box "x")) "unbound variable: %box")
  (check alpha:hidden 7)
  (check (alpha:%box "x") "[x]"))

(define-test "private state is the library's, changed through its exports"
  (let ((n (bump!)))
    (check (bump!) (+ n 1))
    (check alpha:counter (+ n 1))))

(define-test "an exported syntax-rules macro uses a private helper, here"
  (check (wrap "y") "[y]"))

(define-test "an exported macro's literal keyword matches here, unbound in both files"
  (check (either otherwise 'fallback) 'fallback)
  (check (either 'given 'fallback) 'given))

(define-test "an exported define-macro names a private helper in full"
  (check (note "z") "note [z]"))

(define-test "only, except, rename and prefix, alone and together"
  (require "namespaces/beta.lisp" 'only '(area))
  (check (eval '(area 2 3)) 6)
  (check-error (eval 'perimeter) "unbound variable: perimeter")
  (require "namespaces/beta.lisp" 'except '(rule area shared) 'prefix 'bx:)
  (check (eval '(bx:perimeter 2 3)) 10)
  (check-error (eval 'bx:rule) "unbound variable: bx:rule")
  (require "namespaces/beta.lisp" 'only '(perimeter) 'rename '((perimeter around)))
  (check (eval '(around 1 1)) 4))

(define-test "a library's own imports and names stay in its file"
  (require "namespaces/gamma.lisp")
  (check (eval '(head-of '(1 2))) 1)               ; gamma used cl's first
  (check-error (eval 'first) "unbound variable: first")   ; but this file did not import cl
  (check (eval '(keep-odd '(1 2 3 4 5))) '(1 3 5)) ; gamma's own remove
  (check (remove even? '(1 2 3 4)) '(1 3)))        ; here, the built-in remove

(define-test "a program file loaded by this one starts with this file's imports"
  (load "namespaces/uses-import.lisp")             ; area is beta's, imported above
  (check (eval '(area-twice 2 3)) 12))

(define-test "a library starts with no imports, whatever its loader imported"
  (require "namespaces/no-inherit.lisp")
  (check-error (eval '(try-area)) "unbound variable: no-inherit:area"))

(define-test "conflicts are errors, and a refused require imports nothing"
  (check-error (require "namespaces/beta.lisp") "require: rule is already imported as alpha:rule")
  (check-error (eval 'perimeter) "unbound variable: perimeter")   ; nothing came in
  (check-error (eval '(define (rule n) n)) "rule is imported (as alpha:rule)")
  (check-error (require "namespaces/beta.lisp" 'only '(volume)) "require: beta does not export volume (in only)")
  (check-error (require "namespaces/beta.lisp" 'sideways 'x) "require: unknown option sideways")
  (check-error (require "namespaces/beta.lisp" 'prefix) "require: the option prefix has no value")
  (check-error (require "namespaces/uses-import.lisp" 'only '(x)) "is not a library, so it has nothing to import"))

(define-test "the same import twice is nothing"
  (require "namespaces/alpha.lisp")
  (check (rule 6) "alpha 6"))

(define-test "documentation finds a name through its import, and by its full name"
  (check (documentation 'rule) (documentation 'alpha:rule)))

(define-test "library is only a file's first form, while it loads"
  (check-error (eval '(library nowhere (export x))) "library: only as the first form of a file that is being loaded"))

(define-test "a program redefining a built-in: the built-ins keep their own (R-9)"
  (eval '(define (http-request . args) 'mine))
  (check (eval '(http-request 1)) 'mine)
  (check-error (http-get "http://127.0.0.1:1/") "http: could not connect to 127.0.0.1"))

(run-tests)
