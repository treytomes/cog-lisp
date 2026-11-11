;;; ide-development-image.lisp -- the development image, step 2b of
;;; specs/34-morphic-ide.md (R-1 to R-4, R-37; AC-2): the requests the launchers
;;; and VS Code leave for it, taken as the running image takes them; the project
;;; folder; what changed in the checkout; and the update in place, on a copy of
;;; the checkout's source in a temporary folder, so the checkout is never changed.
(load "../../lib/test.lisp")
(require 'ide)
(require 'editor-services)

(define here [[[[(smalltalk LispLoadPath) value] asFileReference] parent] fullName])
(define home (hash-table-ref *env* 'home))
(define (temp name)
  (let ((d [[[(smalltalk FileLocator) temp] / name] asFileReference]))
    [d ensureDeleteAll] [d ensureCreateDirectory] d))
(define (write-file! dir name text)
  (let ((f [dir / name])) [f ensureDelete] [f writeStreamDo: (procedure->block (lambda (s) [s nextPutAll: text]))] f))
(define (has? text part) (if (string-search text part) #t #f))

;;; --- requests (R-37) --------------------------------------------------------------------

(define-test "ide-request: project, repl, run and update; anything else is unknown"
  (check (ide-request (string-append "(project " (with-output-to-string (lambda () (write (string-append here "/editor-services")))) ")"))
         'project)
  (check-true (string-suffix? "editor-services" (ide-project)))
  ;; the project is indexed for the editor services
  (check (length (editor-definitions-named "perimeter")) 1)
  (check (ide-request "(repl)") 'repl)
  (check (ide-request "(update)") 'update)
  (let ((before (length (ide-changes))))
    (check (ide-request "(run \"c:/x/y.lisp\")") '(run "c:/x/y.lisp"))
    (let ((c (car (reverse (ide-changes)))))
      (check (length (ide-changes)) (+ before 1))
      (check (change-kind c) 'run)
      (check (change-names c) '("c:/x/y.lisp"))
      (check (change-maker c) 'person)))
  (check (ide-request "(frobnicate)") 'unknown)
  (check (ide-request "(run 5)") 'unknown)
  (check (ide-request "(unclosed") 'unknown)
  (check (ide-request "") 'unknown))

(define-test "the image takes request files in name order, removes them, and opens what they ask"
  (let* ((dir (temp "cog-lisp-ide-requests"))
         (prog (write-file! dir "prog.lisp" "(define (from-a-run) 41)\n(display \"ran\")\n"))
         (fwd (lambda (f) [[f fullName] copyReplaceAll: "\\" with: "/"])))
    (write-file! dir "2-run.request" (string-append "(run " (with-output-to-string (lambda () (write (fwd prog)))) ")\n"))
    (write-file! dir "1-repl.request" "(repl)\n")
    (write-file! dir "0-project.request" (string-append "(project " (with-output-to-string (lambda () (write (fwd dir)))) ")\n"))
    (write-file! dir "x.txt" "not a request")
    (let ((opened (vector->list [[(smalltalk LispIde) takeRequestsIn: [dir fullName]] asArray])))
      (check (length opened) 2)
      (check (sort (map (lambda (f) [f basename]) (vector->list [[dir files] asArray])) string<?) '("prog.lisp" "x.txt"))   ; a folder lists in no set order
      (check (ide-project) (fwd dir))
      ;; the run's window loaded the file
      (let ((run (cadr opened)))
        (check-true [run waitUntilIdle: 10000])
        (check-true (has? [run transcriptString] "ran"))
        (check (from-a-run) 41))
      (for-each (lambda (p) [[p window] close]) opened))
    ;; no folder: nothing taken
    (check (vector->list [[(smalltalk LispIde) takeRequestsIn: [[dir / "none"] fullName]] asArray]) '())
    [dir ensureDeleteAll]))

(define-test "quitting, a development image removes its heartbeat; saving, it keeps it"
  (let ((beat [[(smalltalk Smalltalk) imageDirectory] / "heartbeat"])
        (pool [(smalltalk LispIde) classPool]))
    [beat writeStreamDo: (procedure->block (lambda (s) [s nextPutAll: "now"]))]
    [pool at: ["Watcher" asSymbol] put: [(procedure->block (lambda () #f)) newProcess]]
    [(smalltalk LispIde) shutDown: #f]                          ; a save: kept
    (check-true [beat exists])
    [(smalltalk LispIde) shutDown: #t]                          ; quitting: gone
    (check-false [beat exists])
    (check-true (smalltalk-nil? [pool at: ["Watcher" asSymbol]]))
    [beat ensureDelete]))

(define-test "the start-up hook does nothing in a headless run"
  ;; a build and every suite start headless: no watcher, no window
  [(smalltalk LispIde) startUp: #t]
  (check-false [(smalltalk Smalltalk) isInteractive]))

;;; --- what changed, and the update in place (R-3) -------------------------------------------

;; a copy of the checkout's src/ and lib/ in a temporary folder, its files newer than the image
(define (copy-of-checkout name with-compiler?)
  (let ((h (temp name)))
    [[[home asFileReference] / "src"] copyAllTo: [h / "src"]]
    [[h / "lib"] ensureCreateDirectory]
    (for-each (lambda (lib) [[[[home asFileReference] / "lib"] / lib] copyTo: [[h / "lib"] / lib]])
              '("core.lisp" "format.lisp" "json.lisp" "http.lisp" "coverage.lisp"))
    (when with-compiler? [[[[home asFileReference] / "lib"] / "compiler"] copyAllTo: [[h / "lib"] / "compiler"]])
    h))

(define-test "ide-stale-files: what changed since the image was built"
  (let ((h (copy-of-checkout "cog-lisp-ide-stale" #t)))
    (let ((stale (ide-stale-files 'home [h fullName])))
      (check-true (and (member "src/coglisp-ide.st" stale) #t))
      (check-true (and (member "lib/core.lisp" stale) #t))
      (check-true (and (member "lib/compiler/compiler.lisp" stale) #t))
      (check-false (member "lib/console.lisp" stale)))         ; not built in
    ;; a change to the compiler cannot be carried in place: a fresh image
    (let ((answer (ide-update 'home [h fullName] 'image "no-such.image")))
      (check (cdr (assq 'status answer)) 'fresh)
      (check-true (has? (cdr (assq 'report answer)) "lib/compiler/")))
    [h ensureDeleteAll]))

(define-test "ide-update: src/ and a built-in library carried in place, the image's own work kept"
  (let* ((h (copy-of-checkout "cog-lisp-ide-update" #f))
         (images (temp "cog-lisp-ide-update-image"))
         (image (write-file! images "dev.image" "the image as last saved"))
         (s (ide-session 'name "kept")))
    (write-file! images "dev.changes" "its changes")
    ;; the image's own work, before the update
    (ide-eval s "(define (my-own-work) 'still-here)")
    ;; the checkout moves on: a new built-in, and a new method in src/
    [[[h / "lib"] / "core.lisp"] writeStreamDo:
      (procedure->block (lambda (st) [st setToEnd] [st nextPutAll: "\n(define (%ide-update-probe) 'new-built-in)\n"]))]
    (let* ((ide-st [[h / "src"] / "coglisp-ide.st"])
           (text [[ide-st contents] asString])
           (i (string-search text "\"the development image takes its requests")))
      [ide-st ensureDelete]
      [ide-st writeStreamDo: (procedure->block (lambda (st)
        [st nextPutAll: (string-append (substring text 0 i)
                                       "cm value: ide class value: 'probe' value: 'updateProbe\n\t^ 42'.\n"
                                       (substring text i (string-length text)))]))])
    (let ((answer (ide-update 'home [h fullName] 'image [image fullName])))
      (check (cdr (assq 'status answer)) 'updated)
      (check-true (and (member "lib/core.lisp" (cdr (assq 'files answer))) #t))
      (check-true [[[(cdr (assq 'backup answer)) asFileReference] contents] = "the image as last saved"])
      (check-true [[images / "dev.before-update.changes"] exists]))
    ;; the new definitions are in force; the image's own work still answers
    (check (eval '(%ide-update-probe)) 'new-built-in)
    (check [(smalltalk LispIde) updateProbe] 42)
    (check (result-values (ide-eval s "(my-own-work)")) '(still-here))
    (check (result-values (ide-eval s "(+ 1 2)")) '(3))
    ;; recorded, and up to date now
    (check (change-kind (car (reverse (ide-changes)))) 'update)
    (check (ide-stale-files 'home [h fullName]) '())
    (check (cdr (assq 'status (ide-update 'home [h fullName]))) 'current)
    (ide-close s)
    [h ensureDeleteAll]
    [images ensureDeleteAll]))

(run-tests)
