;;; ide-browser.lisp -- the body as the browser reads it, step 4a of
;;; specs/34-morphic-ide.md (R-17 to R-21, R-32 to R-35; AC-4): the groups, a
;;; group's definitions, a definition and its place, callers and callees,
;;; search, disassembly, and a definition written back into its file. No window
;;; is opened; the files are written in a temporary folder.
(load "../../lib/test.lisp")
(require 'ide)

(define (temp name)
  (let ((d [[[(smalltalk FileLocator) temp] / name] asFileReference]))
    [d ensureDeleteAll] [d ensureCreateDirectory] d))
(define (write-raw! f text)
  [f ensureDelete]
  [f writeStreamDo: (procedure->block (lambda (s) [s nextPutAll: text]))]
  [f fullName])
(define (raw f) [[[f asFileReference] contents] asString])
(define (names entries) (map (lambda (e) (vector-ref e 0)) entries))
(define (key path) [[[path asFileReference] fullName] asLowercase])

;; a library and a program of our own, loaded
(define dir (temp "cog-lisp-ide-browser"))
(define lib-file
  (write-raw! [dir / "brlib.lisp"]
              "(library browse-lib (export twice))\n\n(define (%double x)\n  \"(%double x)\nx and x.\"\n  (* 2 x))\n\n(define (twice x) (%double x))\n"))
(define prog-file
  (write-raw! [dir / "brprog.lisp"] "(define browse-limit 10)\n(define (browse-go n) (if (> n browse-limit) 'big (browse-lib:twice n)))\n"))
(ide-load-file lib-file)
(ide-load-file prog-file)

(define-test "R-17 the groups: the built-in categories, the loaded libraries, the programs"
  (let ((groups (ide-groups)))
    (check (vector-ref (car groups) 0) "Special forms")
    (check-true (and (member (vector "Lists" 'category) groups) #t))
    (check-true (and (member (vector "browse-lib" 'library) groups) #t))
    (check (car (reverse groups)) (vector "programs" 'programs))
    (check-false (member (vector "Language server" 'library) groups))))

(define-test "R-17 a group's definitions: a library's exports first, each marked by kind"
  (check (ide-group-definitions "browse-lib" 'library)
         (list (vector 'browse-lib:twice 'procedure #t) (vector 'browse-lib:%double 'procedure #f)))
  (check-true (and (member (vector 'car 'primitive #t) (ide-group-definitions "Lists" 'category)) #t))
  (check-true (and (member (vector 'if 'special-form #t) (ide-group-definitions "Special forms" 'category)) #t))
  (let ((programs (ide-group-definitions "programs" 'programs)))
    (check-true (and (member (vector 'browse-limit 'variable #t) programs) #t))
    (check-true (and (member (vector 'browse-go 'procedure #t) programs) #t)))
  (check (map ide-definition-kind '(if when filter car browse-limit no-such-name))
         '(special-form syntax procedure primitive variable #f)))

(define-test "R-21 a definition and its place: by its text, a variable by its name"
  (let ((b (ide-browse 'browse-lib:%double)))
    (check (vector-ref b 1) 'procedure)
    (check (vector-ref b 2) "(%double x)\nx and x.")
    (check (key (vector-ref b 4)) (key lib-file))
    (check (substring (car (ide-read-file lib-file)) (vector-ref b 5) (vector-ref b 6))
           "(define (%double x)\n  \"(%double x)\nx and x.\"\n  (* 2 x))")
    (check-false (vector-ref b 7)))
  (let ((b (ide-browse 'browse-limit)))
    (check (key (vector-ref b 4)) (key prog-file))
    (check (substring (car (ide-read-file prog-file)) (vector-ref b 5) (vector-ref b 6)) "(define browse-limit 10)"))
  ;; a built-in from cog-lisp's own sources, and a primitive with no file
  (let ((b (ide-browse 'filter)))
    (check-true (string-suffix? "core.lisp" (vector-ref b 4))))
  (check (vector-ref (ide-browse 'car) 4) #f)
  (check-false (ide-browse 'no-such-name)))

(define-test "R-21 a definition whose file no longer holds its text is stale"
  (let ((f (write-raw! [dir / "stale.lisp"] "(define (browse-stale) 1)\n")))
    (ide-load-file f)
    (write-raw! [f asFileReference] "(define (browse-stale) 2)\n")
    (check-true (vector-ref (ide-browse 'browse-stale) 7))))

(define-test "R-18 callers and callees, from the compiled code"
  (check (ide-callers 'browse-lib:%double) '(browse-lib:twice))
  (check-true (and (memq 'browse-go (ide-callers 'browse-lib:twice)) #t))
  (check-true (and (memq 'browse-limit (ide-callees 'browse-go)) #t))
  (check-true (and (memq 'browse-lib:twice (ide-callees 'browse-go)) #t))
  (check-false (memq 'browse-go (ide-callees 'browse-go)))
  (check (ide-callees 'browse-limit) '())
  (check-true (and (memq 'remove (ide-callers 'filter)) #t)))           ; built-ins too

(define-test "R-19 search: names first, then documentation"
  (let ((found (ide-search "browse-")))
    (check-true (and (memq 'browse-go found) (memq 'browse-limit found) #t)))
  (let ((found (ide-search "X AND X")))                                 ; case ignored
    (check-true (and (memq 'browse-lib:%double found) #t)))
  (check (ide-search "no-such-text-anywhere-zzq") '()))

(define-test "R-17 disassembly: each block's bytecode"
  (let ((d (ide-disassembly 'browse-lib:twice)))
    (check-true (string-prefix? "; the procedure\n" d))
    (check-true (and (string-search d "pushTemp:") #t)))
  (check-false (ide-disassembly 'browse-limit))
  (check-true (string? (ide-disassembly 'if))))                         ; its translator's

(define-test "R-20 editing from the browser: written into its file, saved, evaluated, recorded"
  (let ((r (ide-write-definition 'browse-lib:%double "(define (%double x)\n  \"(%double x)\nx and x, by three.\"\n  (* 3 x))")))
    (check (result-status r) 'done))
  (check (browse-lib:twice 2) 6)                                        ; in force, as the library's
  (check (car (ide-read-file lib-file))
         "(library browse-lib (export twice))\n\n(define (%double x)\n  \"(%double x)\nx and x, by three.\"\n  (* 3 x))\n\n(define (twice x) (%double x))\n")
  (check-false (vector-ref (ide-browse 'browse-lib:%double) 7))         ; its place follows it
  (let ((save (car (filter (lambda (c) (eq? (change-kind c) 'save)) (reverse (ide-changes))))))
    (check (change-session save) "browser")
    (check-true (string-search (change-before save) "(* 2 x)")))
  ;; stale: nothing written
  (check-false (ide-write-definition 'browse-stale "(define (browse-stale) 3)"))
  (check (raw [dir / "stale.lisp"]) "(define (browse-stale) 2)\n")
  (check-error (ide-write-definition 'car "(define (car x) x)") "ide-write-definition: no file holds"))

;;; ---------------------------------------------------------------------------
;;; The whole body, the compiler included (section 22)

(define home (hash-table-ref *env* 'home))
(define compiler-file (string-append home "/lib/compiler/compiler.lisp"))

(define-test "one list of categories: the image's, in the reference's order"
  (check (car (documentation-categories)) "Special forms")
  (check (map (lambda (g) (vector-ref g 0)) (filter (lambda (g) (eq? (vector-ref g 1) 'category)) (ide-groups)))
         (filter (lambda (c) (pair? (ide-group-definitions c 'category))) (documentation-categories))))

(define-test "a special form: its define-special-form in the compiler's source, its translator"
  (let ((b (ide-browse 'if)))
    (check (vector-ref b 1) 'special-form)
    (check (key (vector-ref b 4)) (key compiler-file))
    (check-true (string-prefix? "(define-special-form 'if"
                                (substring (car (ide-read-file compiler-file)) (vector-ref b 5) (vector-ref b 6)))))
  (check-true (and (memq 'lc-translate-if (ide-callees 'if)) #t))
  (check-true (string-prefix? "; the procedure" (ide-disassembly 'if))))

(define-test "a primitive: the Smalltalk that implements it"
  (check (vector-ref (ide-browse 'car) 8) '("LispPrimitives class" "installListsInto:" "[:p | p car]"))
  (check-false (vector-ref (ide-browse 'filter) 8)))

(define-test "the sealed sources: a group each, all their definitions in the file's order"
  (check (map (lambda (p) [[p asFileReference] basename]) (ide-sealed-sources))
         '("reader.lisp" "opal.lisp" "codegen.lisp" "compiler.lisp" "syntax-rules.lisp"
           "core.lisp" "format.lisp" "json.lisp" "http.lisp" "coverage.lisp"))
  (check-true (and (member (vector "compiler/compiler.lisp" 'source) (ide-groups)) #t))
  (let ((names (names (ide-group-definitions "compiler/compiler.lisp" 'source))))
    (check (car names) 'lc-nesting-budget)                            ; its first definition
    (check-true (and (memq 'if names) (memq 'lc-expansion-too-deep names) #t))))

(define-macro (bw-forever) '(bw-forever))
(define-test "the compiler edited live: from its own source, not from a program"
  (let* ((too-deep (lambda () (guard (e (#t (condition-report e))) (compile-form '(bw-forever)) "no error")))
         (normal (too-deep)))
    (check-true (string-prefix? "macro expansion too deep" normal))
    ;; a program's definition of a compiler's name changes nothing for the compiler
    (ide-eval (ide-session) "(define (lc-expansion-too-deep form) (error \"from a program\"))")
    (check (too-deep) normal)
    ;; the same name evaluated as part of the compiler's source changes the compiler
    (let ((s (ide-file-session compiler-file)))
      (check (result-status (ide-eval s "(define (lc-expansion-too-deep form) (lc-error \"edited live\"))")) 'done)
      (check-true (string-prefix? "edited live" (too-deep)))
      ;; and its file's text puts it back
      (let ((b (ide-browse 'lc-expansion-too-deep)))
        (ide-eval s (substring (car (ide-read-file compiler-file)) (vector-ref b 5) (vector-ref b 6)))))
    (check (too-deep) normal)))

(run-tests)
[dir ensureDeleteAll]
