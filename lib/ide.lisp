;;; ide.lisp -- the image's tools as LISP procedures (specs/34-morphic-ide.md
;;; section 5.10). Load with (require 'ide).
;;;
;;; Every tool is a procedure here before it is a window (R-32): the REPL window
;;; calls these, and so will the model's doorway (R-36). They answer plain data
;;; (R-33), and every change they make to the image or a file is recorded (R-35).
;;;
;;; Step 2 (sessions and the record of changes):
;;;   - a session evaluates in a process of its own, with its own unit and ports
;;;     (R-12, R-13, R-31); an error leaves it waiting at a break, on the failing
;;;     computation's stack, where a restart continues it (R-14); a running
;;;     evaluation can be interrupted (R-15), and a program it runs reads the
;;;     lines typed for it;
;;;   - an evaluation that defines names is recorded: when, which session, made
;;;     by a person or an agent, the names, and the text.
;;;
;;; Step 2b (the development image, R-1 to R-4, R-37): the project it works on,
;;; the requests the launchers and VS Code leave for it, what changed in the
;;; checkout since it was built, and the update in place (R-3).
;;;
;;; Records are vectors, read with their accessors:
;;;   a result  #(status values written output report restarts level)
;;;   a change  #(time session maker kind names text)

(library ide
  (export ide-session ide-sessions ide-session-name ide-session-maker ide-session-busy? ide-session-output
          ide-eval ide-wait ide-type ide-interrupt ide-close
          result-status result-values result-written result-output result-report result-restarts result-level
          ide-changes ide-log-to!
          change-time change-session change-maker change-kind change-names change-text
          ide-project ide-request ide-stale-files ide-update
          ide-window-console ide-loaded-files
          change-before ide-project-files ide-read-file ide-save-file ide-undo-change
          ide-form-at ide-file-session ide-load-file
          ide-check ide-describe ide-complete ide-definitions ide-index-project!
          ide-indent-unit ide-indent ide-format))
(require 'editor-services)
(require 'console)

;; an option's value in (name value ...), or default
(define (%option options name default)
  (let ((m (memq name options))) (if (and m (pair? (cdr m))) (cadr m) default)))

(define (%symbol x) (string->symbol [x asString]))

;;; ---------------------------------------------------------------------------
;;; Sessions

(define %count 0)

(define (ide-session . options)
  "(ide-session option ...)
A new session: evaluations in a process of their own, with their own unit and output and input ports. Options: name (a string; session 1, 2, ...), maker (person or agent: who its changes are recorded as made by; person), unit (the unit to evaluate in, such as a file's; a session unit of its own), wrapper (a procedure given a thunk, run around every evaluation: (lambda (thunk) (with-console '(colors none) thunk)))."
  (set! %count (+ %count 1))
  (let* ((name (%option options 'name (string-append "session " (number->string %count))))
         (unit (%option options 'unit #f))
         (s [(smalltalk LispSession) named: name
                                     unit: (if unit unit (smalltalk-nil))
                                     maker: [(symbol->string (%option options 'maker 'person)) asSymbol]])
         (wrapper (%option options 'wrapper #f)))
    (if wrapper [s wrapper: wrapper])
    s))

(define (ide-sessions)
  "(ide-sessions)
The sessions open in the image."
  (vector->list [[[(smalltalk LispSession) all] copy] asArray]))

(define (ide-session-name s) "(ide-session-name session)\nIts name, a string." [s name])
(define (ide-session-maker s) "(ide-session-maker session)\nperson or agent: who its changes are recorded as made by." (%symbol [s maker]))
(define (ide-session-busy? s) "(ide-session-busy? session)\n#t while it evaluates; at a break, waiting for a restart or another form, #f." [s isBusy])
(define (ide-session-output s) "(ide-session-output session)\nEverything the session has written to its output port, a string." [s output])

;;; ---------------------------------------------------------------------------
;;; Results

(define %unspecified [(smalltalk LispUnspecified) default])

(define (%written v) (with-output-to-string (lambda () (write v))))

(define (%result r)
  (if (string=? [[r status] asString] "running")
      #f
      (let ((values (filter (lambda (v) (not (eq? v %unspecified))) (vector->list [r values]))))
        (vector (%symbol [r status])
                values
                (map %written values)
                [r output]
                (let ((rep [r report])) (if (smalltalk-nil? rep) #f rep))
                (map (lambda (n) n) (vector->list [r restarts]))
                [r level]))))

(define %running (vector 'running '() '() "" #f '() 0))

(define (result-status r) "(result-status result)\ndone; error (the session waits at a break); aborted (an abort restart came back to the top); or running (not finished in the time asked for: ide-wait answers it later)." (vector-ref r 0))
(define (result-values r) "(result-values result)\nThe values of the forms evaluated, as a list, leaving out the unspecified value." (vector-ref r 1))
(define (result-written r) "(result-written result)\nThe values, each as write writes it." (vector-ref r 2))
(define (result-output r) "(result-output result)\nWhat the evaluation wrote to the output port, a string." (vector-ref r 3))
(define (result-report r) "(result-report result)\nAn error's report, a string; or #f." (vector-ref r 4))
(define (result-restarts r) "(result-restarts result)\nAt an error, the names of the restarts active, strings: evaluating (name args ...) in the session invokes one." (vector-ref r 5))
(define (result-level r) "(result-level result)\nHow many breaks deep the session is: 0 at the top." (vector-ref r 6))

;;; ---------------------------------------------------------------------------
;;; Evaluating

;; the texts sent to each session and not yet answered, oldest first
(define %sent (make-hash-table eq?))

(define (ide-eval s text . options)
  "(ide-eval session text option ...)
Evaluates text's forms in session and answers the result. Options: timeout (milliseconds to wait; as long as it takes if not given): a result still running then has status running, and ide-wait answers it. An evaluation that defines names is recorded (ide-changes)."
  (hash-table-set! %sent s (append (hash-table-ref/default %sent s '()) (list text)))
  [s evaluate: text]
  (ide-wait s (%option options 'timeout #f)))

(define (ide-wait s . timeout)
  "(ide-wait session [milliseconds])
The result of the oldest evaluation not yet answered, waiting at most milliseconds (as long as it takes if not given); a result with status running if it has not come."
  (let ((r [s waitFor: (if (and (pair? timeout) (car timeout)) (car timeout) (smalltalk-nil))]))
    (or (let ((result (%result r)))
          (and result
               (let* ((sent (hash-table-ref/default %sent s '()))
                      (text (if (pair? sent) (car sent) "")))
                 (hash-table-set! %sent s (if (pair? sent) (cdr sent) '()))
                 (unless (eq? (result-status result) 'aborted) (%record-evaluation! s text))
                 result)))
        %running)))

(define (ide-type s line)
  "(ide-type session line)
Gives the program session runs a line to read: read-line answers it, and read reads from it."
  [s type: line])

(define (ide-interrupt s)
  "(ide-interrupt session)
Stops the evaluation session is running: it waits at a break, with its restarts (abort among them), and the evaluation's result has status error."
  [s interrupt])

(define (ide-close s)
  "(ide-close session)
Ends session and its process."
  [s close])

;;; ---------------------------------------------------------------------------
;;; The record of changes (R-35)

(define %changes '())             ; newest first
(define %log-path #f)

(define (change-time c) "(change-time change)\nWhen it was made, a date and time as text." (vector-ref c 0))
(define (change-session c) "(change-session change)\nThe name of the session that made it." (vector-ref c 1))
(define (change-maker c) "(change-maker change)\nperson or agent." (vector-ref c 2))
(define (change-kind c) "(change-kind change)\nevaluate (an evaluation that defined names), run (a file run, from a request), update (the image updated in place), or log (the record began to be kept in a file)." (vector-ref c 3))
(define (change-names c) "(change-names change)\nThe names it defined, strings." (vector-ref c 4))
(define (change-text c) "(change-text change)\nThe text evaluated; for a file saved, the text it was saved with." (vector-ref c 5))
(define (change-before c)
  "(change-before change)
For a file saved, the text it held before, which ide-undo-change writes back; else #f."
  (if (> (vector-length c) 6) (vector-ref c 6) #f))

(define (%record! change)
  (set! %changes (cons change %changes))
  (when %log-path
    (with-output-to-file %log-path
      (lambda () (for-each (lambda (c) (write c) (newline)) (reverse %changes))))))

(define (%record-evaluation! s text)
  (let ((names (map definition-name (guard (e (#t '())) (editor-definitions text)))))
    (unless (null? names)
      (%record! (vector [[[(smalltalk DateAndTime) now] printString] asString]
                        [s name] (ide-session-maker s) 'evaluate names text)))))

(define (ide-changes)
  "(ide-changes)
The changes made through these tools, oldest first: each evaluation that defined names, with when, its session, who made it (person or agent), the names and the text."
  (reverse %changes))

(define (ide-log-to! path)
  "(ide-log-to! path)
From now on the changes are also kept in the file at path, one written record a line, rewritten at each change, so the record outlives a crash. #f stops it."
  (set! %log-path path)
  (when path (%record! (vector [[[(smalltalk DateAndTime) now] printString] asString] "" 'person 'log '() path)))
  path)

;;; ---------------------------------------------------------------------------
;;; The project, and requests (R-1, R-37)

(define %project #f)

(define (%now) [[[(smalltalk DateAndTime) now] printString] asString])

(define (ide-project . folder)
  "(ide-project [folder])
The project folder the image works on, or #f; with folder, makes it the project (a path) and indexes its .lisp files for the editor services."
  (when (pair? folder)
    (set! %project (car folder))
    (guard (e (#t #f)) (editor-index-folder! (car folder))))
  %project)

(define (ide-request text)
  "(ide-request text)
Takes a request the launchers (ide.bat, ide.sh) and VS Code leave for the image, a form as text: (project folder) makes folder the project and answers project; (repl) answers repl, for a new REPL window; (run path) records the run (a change, kind run) and answers (run path); (update) answers update. Anything else answers unknown."
  (let ((d (guard (e (#t #f)) (read (open-input-string text)))))
    (cond ((and (pair? d) (eq? (car d) 'project) (pair? (cdr d)) (string? (cadr d)))
           (ide-project (cadr d))
           'project)
          ((equal? d '(repl)) 'repl)
          ((and (pair? d) (eq? (car d) 'run) (pair? (cdr d)) (string? (cadr d)))
           (%record! (vector (%now) "" 'person 'run (list (cadr d)) text))
           (list 'run (cadr d)))
          ((equal? d '(update)) 'update)
          (else 'unknown))))

;;; ---------------------------------------------------------------------------
;;; What changed in the checkout, and the update in place (R-3)

;; the built-in libraries the seed compiles into every image, in their order
(define %built-in-libraries '("core" "format" "json" "http" "coverage"))

;; when the image last took the checkout's source: its build, or its last update
(define %updated #f)
(define (%since)
  (or %updated
      (let ((built (assq 'built (image-build-info))))
        (and built [(smalltalk DateAndTime) fromString: (cdr built)]))))

(define (%home options)
  (%option options 'home (hash-table-ref/default *env* 'home #f)))

;; (relative . full) for each source file an image is built from, under home
(define (%sources home)
  (let ((in (lambda (folder ext)
              (let ((dir [[home asFileReference] / folder]))
                (if [dir isDirectory]
                    (filter-map (lambda (f) (and [[f basename] endsWith: ext]
                                                 (cons (string-append folder "/" [f basename]) [f fullName])))
                                (vector->list [[dir files] asArray]))
                    '())))))
    (append (in "src" ".st")
            (in "lib/compiler" ".lisp")
            (filter-map (lambda (name)
                          (let ((f [[home asFileReference] / (string-append "lib/" name ".lisp")]))
                            (and [f exists] (cons (string-append "lib/" name ".lisp") [f fullName]))))
                        %built-in-libraries))))

(define (ide-stale-files . options)
  "(ide-stale-files option ...)
The source files the image is built from (src/*.st, lib/compiler/, and the built-in libraries core, format, json, http and coverage) that changed since it was built or last updated, as paths relative to the cog-lisp folder; () when it is up to date, or was not built from a seed. Options: home (the cog-lisp folder; *env*'s)."
  (let ((since (%since)) (home (%home options)))
    (if (not (and since home))
        '()
        (map car (filter (lambda (s) [[[(cdr s) asFileReference] modificationTime] > since]) (%sources home))))))

(define (%starts-with? s prefix) (and (>= (string-length s) (string-length prefix)) (string=? (substring s 0 (string-length prefix)) prefix)))

;; a copy of the image as it was last saved, beside it: the way back (R-3)
(define (%backup image)
  (let* ((f [image asFileReference])
         (base [f basenameWithoutExtension])
         (copy [[f parent] / (string-append base ".before-update.image")])
         (changes [[f parent] / (string-append base ".changes")])
         (changes-copy [[f parent] / (string-append base ".before-update.changes")]))
    [copy ensureDelete]
    [f copyTo: copy]
    (when [changes exists] [changes-copy ensureDelete] [changes copyTo: changes-copy])
    [copy fullName]))

(define (ide-update . options)
  "(ide-update option ...)
Brings the image up to date with the checkout, in place, keeping what it holds (R-3): copies the image as last saved beside it (name.before-update.image), files in src/ again and removes the methods src/ no longer defines, compiles each changed built-in library into the live environment, loads the project's files again, and records the update. A change to lib/compiler/ it cannot carry: it answers fresh, for a fresh image (ide.bat --fresh). Answers an association list: status (current, updated, fresh or failed), files (the changed ones), backup (the copy's path), report (a failure's). Options: home (the cog-lisp folder), image (the image file to copy; this one)."
  (let* ((home (%home options))
         (files (ide-stale-files 'home home))
         (image (%option options 'image [[(smalltalk Smalltalk) imagePath] asString])))
    (cond
      ((null? files) (list (cons 'status 'current) (cons 'files '())))
      ((any (lambda (f) (%starts-with? f "lib/compiler/")) files)
       (list (cons 'status 'fresh) (cons 'files files)
             (cons 'report "lib/compiler/ changed: the compiler cannot rebuild itself in place yet; make a fresh image")))
      (else
       (let ((backup (%backup image)))
         (guard (e (#t (list (cons 'status 'failed) (cons 'files files) (cons 'backup backup)
                             (cons 'report (condition-report e)))))
           (when (any (lambda (f) (%starts-with? f "src/")) files)
             [(smalltalk LispIde) refileSourceFrom: [[[home asFileReference] / "src"] fullName]])
           (for-each (lambda (name)
                       (let ((relative (string-append "lib/" name ".lisp")))
                         (when (member relative files)
                           (load [[[home asFileReference] / relative] fullName]))))
                     %built-in-libraries)
           ;; the project's files the image had loaded, loaded again (those still there)
           (when %project
             (let ((key (editor-key %project)))
               (for-each (lambda (path) (when (and (%starts-with? (editor-key path) key) [[path asFileReference] exists]) (load path)))
                         (filter string? (map (lambda (p) (if (smalltalk-nil? p) #f [p asString]))
                                              (vector->list [[[(smalltalk LispUnit) units] keys] asArray]))))))
           (set! %updated [(smalltalk DateAndTime) now])
           (%record! (vector (%now) "" 'person 'update files home))
           (list (cons 'status 'updated) (cons 'files files) (cons 'backup backup))))))))

;;; ---------------------------------------------------------------------------
;;; A console in a window (R-39)

(define (ide-window-console width height keys)
  "(ide-window-console width height keys)
A wrapper for a session (ide-session's wrapper option) whose evaluations run in a console that is a window's: a terminal, interactive, true color and Unicode, width by height cells, its keys read from keys (an object answering nextWithin: milliseconds with the next character typed, or nil), so the console library renders and reads keys as in a terminal."
  (let ((reader (lambda (ms)
                  (let ((c [keys nextWithin: (if ms ms (smalltalk-nil))]))
                    (if (smalltalk-nil? c) #f c)))))
    (lambda (thunk)
      (with-console (list 'terminal? #t 'interactive? #t 'colors 'truecolor 'unicode? #t
                          'width width 'height height 'reader reader)
                    thunk))))

;;; ---------------------------------------------------------------------------
;;; The files the image has loaded (R-41)

(define (ide-loaded-files)
  "(ide-loaded-files)
The files the image has loaded, programs and libraries, each (path . library): library is the library's name, or #f for a program. In the order of their paths."
  (sort (filter-map (lambda (u)
                      (let ((p [u path]))
                        (and (not (smalltalk-nil? p))
                             (cons [p asString]
                                   (let ((l [u library])) (if (smalltalk-nil? l) #f l))))))
                    (vector->list [[[(smalltalk LispUnit) units] values] asArray]))
        (lambda (a b) (string<? (car a) (car b)))))

;;; ---------------------------------------------------------------------------
;;; Files, for the editor (step 3, R-5 to R-9)

(define %skipped '("pharo" "node_modules" ".vscode-test" ".git" "dist" "coverage"))

(define (ide-project-files . folder)
  "(ide-project-files [folder])
The .lisp files under folder (the project's, ide-project, if not given), as full paths, sorted; the folders pharo, node_modules, .git, dist, coverage and .vscode-test left out. () when there is no folder."
  (let ((root (if (pair? folder) (car folder) (ide-project))))
    (if (not root)
        '()
        (let walk ((dir [root asFileReference]))
          (if (not [dir isDirectory])
              '()
              (sort (append-map (lambda (entry)
                                  (cond ([entry isDirectory]
                                         (if (member [entry basename] %skipped) '() (walk entry)))
                                        ([[entry basename] endsWith: ".lisp"] (list [entry fullName]))
                                        (else '())))
                                (vector->list [[dir children] asArray]))
                    string<?))))))

;; the text with CR LF and CR as LF; its line ending, crlf or lf
(define (%split-ending text)
  (if (string-search text (string #\return #\newline))
      (cons [text copyReplaceAll: (string #\return #\newline) with: (string #\newline)] 'crlf)
      (cons text 'lf)))

(define (ide-read-file path)
  "(ide-read-file path)
The file at path as an editor holds it: (text . ending), its lines ended by line feeds whatever the file has, and ending crlf or lf, the file's own (R-8)."
  (%split-ending [[[path asFileReference] contents] asString]))

(define (%write-file! path text)
  (let ((f [path asFileReference]))
    [f ensureDelete]
    [f binaryWriteStreamDo: (procedure->block
                             (lambda (s) [s nextPutAll: [[(smalltalk ZnUTF8Encoder) new] encodeString: text]]))]))

(define (ide-save-file path text . options)
  "(ide-save-file path text option ...)
Writes text, its lines ended by line feeds, to the file at path as UTF-8, its lines ended as the file had them (R-8): ending, an option, says crlf or lf, else the file's own, else lf. Records the save as a change (kind save) with the text before it, for ide-undo-change. Options: ending, session (the name of the session saving it; editor), maker (person or agent; person)."
  (let* ((f [path asFileReference])
         (old (and [f exists] (ide-read-file path)))
         (ending (%option options 'ending (if old (cdr old) 'lf)))
         (out (if (eq? ending 'crlf) [text copyReplaceAll: (string #\newline) with: (string #\return #\newline)] text)))
    (%write-file! path out)
    (%record! (vector (%now) (%option options 'session "editor") (%option options 'maker 'person)
                      'save (list path) text (if old (car old) "")))
    #t))

(define (ide-undo-change change)
  "(ide-undo-change change)
Writes back the text a file held before a save (a change of kind save), keeping its line ending, and records that as a change too (kind undo). An error for any other change."
  (if (not (eq? (change-kind change) 'save))
      (error "ide-undo-change: only a file saved can be undone" (change-kind change))
      (let* ((path (car (change-names change)))
             (ending (cdr (ide-read-file path)))
             (before (change-before change)))
        (%write-file! path (if (eq? ending 'crlf) [before copyReplaceAll: (string #\newline) with: (string #\return #\newline)] before))
        (%record! (vector (%now) "editor" 'person 'undo (list path) before (car (ide-read-file path))))
        #t)))

;;; ---------------------------------------------------------------------------
;;; The form at a place, and evaluating in a file's unit (R-9)

(define (ide-form-at text offset)
  "(ide-form-at text offset)
The top-level form holding offset in text, a character offset from 0, or else the last one before it: (start . end), the form's text from start to before end; #f when there is none. The forms are read, not run; reading stops at the first that does not read."
  (let ((r (make-reader text)))
    (let loop ((last #f))
      (let ((d (guard (e (#t (eof-object))) (reader-next r))))
        (if (eof-object? d)
            last
            (let ((start (reader-datum-start r)) (end (reader-position r)))
              (cond ((and (<= start offset) (< offset end)) (cons start end))
                    ((> start offset) (or last (cons start end)))
                    (else (loop (cons start end))))))))))

(define %file-sessions (make-hash-table equal?))

(define (ide-load-file path . options)
  "(ide-load-file path option ...)
Loads the file at path, as load does, in a session of its own, and answers the result (as ide-eval does); the evaluation is recorded as a change when it defines names. Options: maker (person or agent; person)."
  (let* ((s (ide-session 'name [[path asFileReference] basename] 'maker (%option options 'maker 'person)))
         (r (ide-eval s (string-append "(load " (with-output-to-string (lambda () (write path))) ")"))))
    (if (eq? (result-status r) 'error) (ide-eval s "(abort)"))
    (ide-close s)
    r))

;; does the file's first form declare a library?
(define (%library-file? path)
  (let ((d (guard (e (#t #f)) (reader-next (make-reader (car (ide-read-file path)))))))
    (and (pair? d) (eq? (car d) 'library))))

(define (ide-file-session path . options)
  "(ide-file-session path option ...)
The session that evaluates forms as part of the file at path (R-9): in its unit, so a define in a library's file defines the library's name. A library's file is loaded first if it has not been; a program's is not, since loading it would run it. The session is made once and kept. Options: maker (person or agent; person)."
  ;; units are known by the path's full name, as load gives it
  (let* ((full [[path asFileReference] fullName]) (key (editor-key full)))
    (or (let ((s (hash-table-ref/default %file-sessions key #f)))
          (and s (memq s (ide-sessions)) s))
        (begin
          (when (and (smalltalk-nil? [(smalltalk LispUnit) atPath: full]) (%library-file? full))
            (ide-load-file full 'maker (%option options 'maker 'person)))
          (let* ((unit [(smalltalk LispUnit) atPath: full])
                 (s (ide-session 'name [[path asFileReference] basename]
                                 'maker (%option options 'maker 'person)
                                 'unit (if (smalltalk-nil? unit) #f unit))))
            (hash-table-set! %file-sessions key s)
            s)))))

;;; ---------------------------------------------------------------------------
;;; What the editor knows about a text (step 3b, R-7, R-10): editor-services'
;;; answers, for a file's text as an editor holds it

(define (ide-check path text)
  "(ide-check path text)
The problems in text, the file at path as an editor holds it, in the order of the text: editor-check's (read and compile errors, warnings, and uses of globals nothing defines). The text is indexed as the file's, so its definitions are found before it is saved. Runs only its define-syntax, define-macro, require and library forms."
  (editor-index-text! path text)
  (editor-check path text))

(define (%first-line-of s)
  (let ((i (string-index s #\newline))) (if i (substring s 0 i) s)))

(define (ide-describe path text offset)
  "(ide-describe path text offset)
The documentation of the name at offset in text (the file at path): a documented definition's, else what the name means in the file (a built-in's, an import's), else the first line of its definition; #f for no name or nothing known."
  (let ((found (editor-symbol-at text offset)))
    (and found
         (let* ((name (car found))
                (defs (editor-definitions-for path name))
                (documented (find definition-documentation defs))
                (doc (documentation (editor-resolve path name))))
           (cond (documented (definition-documentation documented))
                 (doc doc)
                 ((pair? defs) (%first-line-of (definition-source (car defs))))
                 (else #f))))))

(define (ide-complete path text offset)
  "(ide-complete path text offset)
The names that complete the one being typed at offset in text: (start end completions), where start to end is the name around offset, to be replaced, and completions (editor-services' records) are those whose label starts with what is before offset, sorted; #f when no name is being typed."
  (let ((found (editor-symbol-at text offset)))
    (and found
         (let* ((start (cadr found)) (prefix (substring text start offset)))
           (and (not (string=? prefix ""))
                (list start (caddr found)
                      (sort (filter (lambda (c) (string-prefix? prefix (completion-label c))) (editor-completions path))
                            (lambda (a b) (string<? (completion-label a) (completion-label b))))))))))

(define %indexed-projects (make-hash-table equal?))

(define (ide-index-project! . folder)
  "(ide-index-project! [folder])
Indexes the .lisp files under folder (the project's, ide-project, if not given), once, for go to definition and completion. Answers #t, or #f with no folder."
  (let ((root (if (pair? folder) (car folder) (ide-project))))
    (and root
         (let ((key (editor-key [[root asFileReference] fullName])))
           (unless (hash-table-ref/default %indexed-projects key #f)
             (editor-index-folder! root)
             (hash-table-set! %indexed-projects key #t))
           #t))))

(define (ide-definitions path text offset)
  "(ide-definitions path text offset)
The definitions of the name at offset in text (the file at path), as editor-services' records: where go to definition goes. The project is indexed first (ide-index-project!); () for a built-in with no file, or no name."
  (ide-index-project!)
  (let ((found (editor-symbol-at text offset)))
    (if found (editor-definitions-for path (car found)) '())))

(define (ide-indent-unit text)
  "(ide-indent-unit text)
How text indents a level: a tab when its first indented line starts with one, else that line's spaces (2 when no line is indented)."
  (let loop ((lines (string-split text #\newline)))
    (if (null? lines)
        "  "
        (let* ((line (car lines)) (n (string-length line)))
          (cond ((and (> n 0) (eq? (string-ref line 0) #\tab)) (string #\tab))
                ((and (> n 0) (eq? (string-ref line 0) #\space))
                 (let count ((i 0))
                   (cond ((and (< i n) (eq? (string-ref line i) #\space)) (count (+ i 1)))
                         ((< i n) (make-string (min i 8) #\space))
                         (else (loop (cdr lines))))))      ; a blank line
                (else (loop (cdr lines))))))))

(define (ide-indent text offset)
  "(ide-indent text offset)
The indentation for a new line started at offset in text (R-7): one level deeper than the line holding the innermost list still open there, as format-source lays a form's arguments one level deeper; none outside any list. A level is ide-indent-unit's."
  (let loop ((tokens (editor-tokens (substring text 0 offset))) (open '()))
    (cond ((pair? tokens)
           (case (token-kind (car tokens))
             ((open) (loop (cdr tokens) (cons (token-start (car tokens)) open)))
             ((close) (loop (cdr tokens) (if (pair? open) (cdr open) open)))
             (else (loop (cdr tokens) open))))
          ((null? open) "")
          (else
           (let* ((at (car open))
                  (line-start (let back ((i at)) (if (and (> i 0) (not (eq? (string-ref text (- i 1)) #\newline))) (back (- i 1)) i)))
                  (lead (let ahead ((i line-start))
                          (if (and (< i at) (memv (string-ref text i) '(#\space #\tab))) (ahead (+ i 1)) i))))
             (string-append (substring text line-start lead) (ide-indent-unit text)))))))

(define (ide-format text)
  "(ide-format text)
text laid out by format-source, indented as text indents (ide-indent-unit): with tabs, or that many spaces a level."
  (require 'format-source)
  (let ((unit (ide-indent-unit text)))
    (if (string=? unit (string #\tab))
        (format-source:format-source text)
        (format-source:format-source text 'spaces (string-length unit)))))
