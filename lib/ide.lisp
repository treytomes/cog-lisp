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
          ide-indent-unit ide-indent ide-format
          ide-groups ide-group-definitions ide-definition-kind ide-browse
          ide-callers ide-callees ide-search ide-disassembly ide-write-definition
          ide-sealed-sources
          ide-views ide-evaluate-with-it ide-inspect ide-open-source))
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
                        [s name] (ide-session-maker s) 'evaluate names text))
      ;; as part of the compiler's source (or a built-in library's): the sealed code too
      (when (hash-table-ref/default %sealed-sessions s #f)
        [(smalltalk LispCompiler) resealAll: (list->vector (map string->symbol names))
         sourceDirectory: (string-append (hash-table-ref *env* 'home) "/lib")]))))

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
The session that evaluates forms as part of the file at path (R-9): in its unit, so a define in a library's file defines the library's name. For a sealed source (ide-sealed-sources), what it defines changes the sealed code too, so the compiler is edited live. A library's file is loaded first if it has not been; a program's is not, since loading it would run it. The session is made once and kept. Options: maker (person or agent; person)."
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
            (when (%sealed-source? full) (hash-table-set! %sealed-sessions s #t))
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

;;; ---------------------------------------------------------------------------
;;; The body, as the browser reads it (step 4a, R-17 to R-21)


(define (%env) [(smalltalk LispEnvironment) default])

(define (%bound-cells)
  (let ((acc '()))
    [(%env) cellsDo: (lambda (cell) (when [cell isBound] (set! acc (cons cell acc))))]
    acc))

(define (%value-of name)
  (if (memq name (special-form-names))
      (hash-table-ref/default lc-special-forms name #f)        ; its translator
      (and [(%env) isBound: name] [(%env) lookup: name])))

(define (%qualified? s) (and (string-index s #\:) #t))

(define (%take l n) (if (or (null? l) (= n 0)) '() (cons (car l) (%take (cdr l) (- n 1)))))

(define (%sort-names names)
  (sort names (lambda (a b) (string<? (symbol->string a) (symbol->string b)))))

;; the procedure behind a value: itself, or a macro's expander
(define (%procedure-of v)
  (cond ([v isKindOf: (smalltalk LispMacro)] [v expander])
        ((procedure? v) v)
        (else #f)))

(define (%source-of v)
  (let ((p (%procedure-of v)))
    (and p (procedure-source p))))

;; a procedure installed by Smalltalk (a primitive) has its block in a method of
;; a class; one cog-lisp compiled, in a method of no class (a doIt)
(define (%primitive? p)
  (guard (e (#t #f))
    (let ((cls [[[[p block] compiledBlock] method] methodClass]))
      (not (eq? cls (smalltalk UndefinedObject))))))

(define (ide-definition-kind name)
  "(ide-definition-kind name)
What the symbol name is in the image: special-form, macro, syntax (a define-syntax macro), primitive (installed by Smalltalk), procedure, or variable; #f when it is not bound."
  (if (memq name (special-form-names))
      'special-form
      (let ((v (and [(%env) isBound: name] [(%env) lookup: name])))
        (cond ((not [(%env) isBound: name]) #f)
              ([v isKindOf: (smalltalk LispMacro)]
               (let ((s (%source-of v))) (if (and s (string-prefix? "(define-syntax" s)) 'syntax 'macro)))
              ((procedure? v) (if (%primitive? v) 'primitive 'procedure))
              (else 'variable)))))

;; the built-in names in a category, special forms among them
(define (%category-names category)
  (let ((acc (if (string=? category "Special forms") (special-form-names) '())))
    (for-each (lambda (cell)
                (let* ((name [cell symbol]) (s (symbol->string name)))
                  (when (and (not (%qualified? s)) (not (memq name (special-form-names)))
                             (equal? (documentation-category name) category))
                    (set! acc (cons name acc)))))
              (%bound-cells))
    (%sort-names acc)))

;; the globals programs defined: unqualified, not built in
(define (%program-names)
  (%sort-names
   (filter-map (lambda (cell)
                 (let* ((name [cell symbol]) (s (symbol->string name)))
                   (and (not (%qualified? s)) (not (memq name (special-form-names)))
                        (not [(smalltalk LispUnit) isBuiltin: name])
                        name)))
               (%bound-cells))))

(define (ide-groups)
  "(ide-groups)
The groups the browser lists (R-17), each #(name kind): the built-in categories that have names, in the reference's order (kind category); the sealed sources, the compiler's files and the built-in libraries', each listing everything it defines, helpers included (kind source; ide-sealed-sources); the loaded libraries, by name (kind library); and programs (kind programs), the globals programs have defined, when there are any."
  (append
   (filter-map (lambda (c) (and (pair? (%category-names c)) (vector c 'category))) (documentation-categories))
   (map (lambda (path) (vector (%source-label path) 'source)) (ide-sealed-sources))
   (map (lambda (name) (vector name 'library))
        (sort (map (lambda (u) (symbol->string [u library])) (vector->list [[(smalltalk LispUnit) libraries] asArray]))
              string<?))
   (if (pair? (%program-names)) (list (vector "programs" 'programs)) '())))

(define (ide-group-definitions name kind)
  "(ide-group-definitions name kind)
The definitions in a group of ide-groups, each #(name kind exported?): name the full symbol, kind ide-definition-kind's, exported? whether a library exports it (#t outside libraries). A library's exports come first, then its private names, each by name; a sealed source's are in the file's order, its special forms among them."
  (case kind
    ((category) (map (lambda (n) (vector n (ide-definition-kind n) #t)) (%category-names name)))
    ((programs) (map (lambda (n) (vector n (ide-definition-kind n) #t)) (%program-names)))
    ((source)
     (let ((path (find (lambda (p) (string=? (%source-label p) name)) (ide-sealed-sources))))
       (if (not path)
           '()
           (map (lambda (n) (vector n (ide-definition-kind n) #t)) (%names-defined-in path)))))
    ((library)
     (let* ((unit [(smalltalk LispUnit) libraryNamed: (string->symbol name)])
            (exports (map symbol->string (vector->list [unit exports])))
            (prefix (string-append name ":"))
            (names (%sort-names
                    (filter-map (lambda (cell)
                                  (let ((s (symbol->string [cell symbol])))
                                    (and (string-prefix? prefix s) [cell symbol])))
                                (%bound-cells))))
            (local (lambda (n) (substring (symbol->string n) (string-length prefix) (string-length (symbol->string n)))))
            (exported? (lambda (n) (and (member (local n) exports) #t))))
       (map (lambda (n) (vector n (ide-definition-kind n) (exported? n)))
            (append (filter exported? names) (remove exported? names)))))
    (else (error "ide-group-definitions: no such kind of group" kind))))

;; the files a name's definition may be in: its library's; the files the image
;; has loaded; cog-lisp's own built-in sources
(define (%candidate-files name)
  (let* ((s (symbol->string name))
         (colon (string-index s #\:))
         (library (and colon [(smalltalk LispUnit) libraryNamed: (string->symbol (substring s 0 colon))]))
         (home (hash-table-ref/default *env* 'home #f))
         (builtins (if home
                       (append (map (lambda (f) (string-append home "/lib/" f ".lisp")) '("core" "format" "json" "http" "coverage"))
                               (filter-map (lambda (e) (and [[e basename] endsWith: ".lisp"] [e fullName]))
                                           (guard (x (#t '())) (vector->list [[[(string-append home "/lib/compiler") asFileReference] files] asArray]))))
                       '())))
    (if (and library (not (smalltalk-nil? library)) (not (smalltalk-nil? [library path])))
        (list [library path])
        (append (filter-map (lambda (u) (let ((p [u path])) (and (not (smalltalk-nil? p)) p)))
                            (vector->list [[(smalltalk LispUnit) units] asArray]))
                builtins))))

;; where name is defined: (path start end stale?), or #f
(define (%place-of name source)
  (let* ((s (symbol->string name))
         (colon (string-index s #\:))
         (local (if colon (substring s (+ colon 1) (string-length s)) s))
         (named #f))
    (let loop ((files (%candidate-files name)))
      (if (null? files)
          (and named (append named (list (and source #t))))      ; found by name only: stale if it had a text
          (let* ((path (car files))
                 (text (guard (e (#t #f)) (car (ide-read-file path))))
                 (defs (if text (filter (lambda (d) (string=? (definition-name d) local)) (editor-definitions text path)) '())))
            (cond ((null? defs) (loop (cdr files)))
                  ((and source (string-search text source))
                   => (lambda (at) (list path at (+ at (string-length source)) #f)))
                  (else
                   (unless named (set! named (list path (definition-start (car defs)) (definition-end (car defs)))))
                   (if source (loop (cdr files)) (list path (definition-start (car defs)) (definition-end (car defs)) #f)))))))))

(define (ide-browse name)
  "(ide-browse name)
A definition as the browser shows it (R-17, R-21): #(name kind documentation source path start end stale? smalltalk). documentation and source are strings or #f (a built-in compiled by the seed keeps no source); path, start and end (character offsets from 0, in the file's text with line feeds) say where it is, or are #f: a special form's is its define-special-form in the compiler's source; stale? is #t when its file no longer holds the text it was compiled from; smalltalk, for a primitive, is (class selector source): the method of Smalltalk that installs it and the block that implements it. #f when name is not bound."
  (let ((kind (ide-definition-kind name)))
    (and kind
         (let* ((v (and (not (eq? kind 'special-form)) (%value-of name)))
                (source (and v (%source-of v)))
                (place (if (eq? kind 'special-form) (%special-form-place name) (%place-of name source))))
           (vector name kind (documentation name) source
                   (and place (car place)) (and place (cadr place)) (and place (caddr place))
                   (and place (cadddr place))
                   (and (eq? kind 'primitive) (%smalltalk-of v)))))))

;; the compiled code of a value: its procedure's block and the blocks inside it
(define (%codes-of v)
  (let ((p (%procedure-of v)))
    (if (not p)
        '()
        (let walk ((code (guard (e (#t #f)) [[p block] compiledBlock])) (acc '()))
          (if (not code)
              acc
              (fold (lambda (lit acc)
                      (cond ([lit isKindOf: (smalltalk CompiledBlock)] (walk lit acc))
                            ([lit isKindOf: (smalltalk BlockClosure)] (walk [lit compiledBlock] acc))
                            (else acc)))
                    (cons code acc)
                    (vector->list [code literals])))))))

;; the names a value's code names: its global cells, and the symbols an inlined
;; call guards with (R-18)
(define (%names-used v)
  (delete-duplicates
   (append-map (lambda (code)
                 (filter-map (lambda (lit)
                               (cond ([lit isKindOf: (smalltalk LispGlobal)] [lit symbol])
                                     ((symbol? lit) lit)
                                     (else #f)))
                             (vector->list [code literals])))
               (%codes-of v))
   eq?))

(define (ide-callers name)
  "(ide-callers name)
The bound names whose compiled code names name (R-18): procedures and macros that call it or read it, built-ins included, found from their code's literals as Pharo finds senders (a quoted symbol of that name counts too). Sorted."
  (%sort-names
   (filter-map (lambda (cell)
                 (let ((n [cell symbol]))
                   (and (not (eq? n name))
                        (%procedure-of [cell value])
                        (memq name (%names-used [cell value]))
                        n)))
               (%bound-cells))))

(define (ide-callees name)
  "(ide-callees name)
The bound names name's compiled code names (R-18): what it calls and reads, from its code's literals; for a special form, its translator's. Sorted; () for a variable."
  (let ((v (%value-of name)))
    (if (not v)
        '()
        (%sort-names (filter (lambda (n) (and (not (eq? n name)) [(%env) isBound: n])) (%names-used v))))))

(define (ide-search text)
  "(ide-search text)
The names bound in the image, special forms among them, whose name or documentation holds text, ignoring case (R-19): those matching by name first, each part by name. At most 300."
  (let* ((needle (string-downcase text))
         (names (append (special-form-names) (map (lambda (c) [c symbol]) (%bound-cells))))
         (in-name (filter (lambda (n) (string-search (string-downcase (symbol->string n)) needle)) names))
         (in-doc (filter (lambda (n) (and (not (memq n in-name))
                                          (let ((d (documentation n))) (and d (string-search (string-downcase d) needle)))))
                         names))
         (all (append (%sort-names (delete-duplicates in-name eq?)) (%sort-names (delete-duplicates in-doc eq?)))))
    (%take all 300)))

(define (ide-disassembly name)
  "(ide-disassembly name)
The bytecode of name's compiled code as text, each block after its own heading, one bytecode a line; for a special form, its translator's; #f for a variable."
  (let ((v (%value-of name)))
    (and v (%procedure-of v)
         (with-output-to-string
          (lambda ()
            (let loop ((codes (reverse (%codes-of v))) (k 0))
              (when (pair? codes)
                (display (if (= k 0) "; the procedure" (string-append "; block " (number->string k))))
                (newline)
                (vector-for-each (lambda (b) (display "  ") (display [b printString]) (newline))
                                 [[[(car codes) symbolicBytecodes] asArray] copy])
                (loop (cdr codes) (+ k 1)))))))))

(define (ide-write-definition name text . options)
  "(ide-write-definition name text option ...)
Edits a definition from the browser (R-20): writes text in place of name's definition in its file, saves the file (recorded as a save, undoable) and evaluates text as part of the file, answering the result (as ide-eval does). #f, writing nothing, when the file no longer holds the definition's text there (its place is stale), for the window to open the file in the editor instead. An error when name has no file. Options: maker (person or agent; person)."
  (let* ((b (ide-browse name))
         (path (and b (vector-ref b 4))))
    (cond ((not path) (error "ide-write-definition: no file holds" name))
          ((vector-ref b 7) #f)
          (else
           (let* ((maker (%option options 'maker 'person))
                  (file (car (ide-read-file path)))
                  (updated (string-append (substring file 0 (vector-ref b 5)) text
                                          (substring file (vector-ref b 6) (string-length file)))))
             (ide-save-file path updated 'session "browser" 'maker maker)
             (let* ((s (ide-file-session path 'maker maker))
                    (r (ide-eval s text)))
               (if (eq? (result-status r) 'error) (ide-eval s "(abort)"))
               r))))))

;;; ---------------------------------------------------------------------------
;;; The sealed sources, edited live (section 22): the compiler's files and the
;;; built-in libraries'

(define (ide-sealed-sources)
  "(ide-sealed-sources)
The files whose code the image seals (the compiler's, in lib/compiler/, and the built-in libraries' in lib/: core, format, json, http, coverage), as full paths, those that exist in cog-lisp's home. A definition evaluated as part of one of them, in its file's session (ide-file-session), changes the sealed code too: the compiler is edited live."
  (let ((home (hash-table-ref/default *env* 'home #f)))
    (if (not home)
        '()
        (filter (lambda (p) [[p asFileReference] exists])
                (append (map (lambda (n) [[[[[home asFileReference] / "lib"] / "compiler"] / n] fullName])
                             (map (lambda (s) [s asString]) (vector->list [(smalltalk LispCompiler) compilerSourceNames])))
                        (map (lambda (n) [[[[home asFileReference] / "lib"] / n] fullName])
                             (map (lambda (s) [s asString]) (vector->list [(smalltalk LispCompiler) builtInLibraryNames]))))))))

(define (%sealed-source? path)
  (let ((key (editor-key [[path asFileReference] fullName])))
    (and (find (lambda (p) (string=? (editor-key p) key)) (ide-sealed-sources)) #t)))

;; compiler/codegen.lisp, core.lisp: a sealed source's name in the browser
(define (%source-label path)
  (let ((ref [path asFileReference]))
    (if (string=? [[ref parent] basename] "compiler")
        (string-append "compiler/" [ref basename])
        [ref basename])))

;; the names a file defines at top level, in its order, special forms among them
(define (%names-defined-in path)
  (let ((r (make-reader (car (ide-read-file path)))))
    (let loop ((acc '()))
      (let ((d (guard (e (#t (eof-object))) (reader-next r))))
        (cond ((eof-object? d) (reverse acc))
              ((and (pair? d) (eq? (car d) 'define-special-form) (pair? (cdr d))
                    (pair? (cadr d)) (eq? (car (cadr d)) 'quote))
               (loop (cons (cadr (cadr d)) acc)))
              ((%definition-of-form d) => (lambda (n) (loop (if (memq n acc) acc (cons n acc)))))
              (else (loop acc)))))))

(define (%definition-of-form d)
  (and (pair? d) (memq (car d) '(define define-macro define-syntax)) (pair? (cdr d))
       (let ((target (cadr d)))
         (cond ((symbol? target) target)
               ((and (pair? target) (symbol? (car target))) (car target))
               (else #f)))))

;; a special form's define-special-form, in the compiler's source: (path start end #f)
(define (%special-form-place name)
  (let loop ((files (filter (lambda (p) (string-search p "compiler")) (ide-sealed-sources))))
    (if (null? files)
        #f
        (let* ((path (car files))
               (r (make-reader (car (ide-read-file path)))))
          (let scan ()
            (let ((d (guard (e (#t (eof-object))) (reader-next r))))
              (cond ((eof-object? d) (loop (cdr files)))
                    ((and (pair? d) (eq? (car d) 'define-special-form) (pair? (cdr d))
                          (equal? (cadr d) (list 'quote name)))
                     (list path (reader-datum-start r) (reader-position r) #f))
                    (else (scan)))))))))

;; a primitive's Smalltalk: (class selector block-source)
(define (%smalltalk-of p)
  (guard (e (#t #f))
    (let* ((code [[p block] compiledBlock])
           (method [code method]))
      (list [[[method methodClass] name] asString]
            [[method selector] asString]
            [[[code sourceNode] sourceCode] asString]))))

;; the sessions evaluating as part of a sealed source
(define %sealed-sessions (make-hash-table eq?))

;;; ---------------------------------------------------------------------------
;;; Looking into a value (step 4b, R-22 to R-24)

(define (%row label value) (vector label (%written value) value))

;; at most n rows, then one saying how many more
(define (%rows-up-to rows n)
  (if (<= (length rows) n)
      rows
      (append (%take rows n)
              (list (vector "..." (string-append (number->string (- (length rows) n)) " more") #f)))))

(define (%list-view v)
  (let loop ((l v) (i 1) (rows '()))
    (cond ((pair? l) (loop (cdr l) (+ i 1) (cons (%row (number->string i) (car l)) rows)))
          ((null? l) (vector "List" (%rows-up-to (reverse rows) 1000)))
          (else (vector "List" (%rows-up-to (reverse (cons (%row "rest" l) rows)) 1000))))))   ; improper

(define (%vector-view v)
  (vector "Vector" (%rows-up-to (let loop ((i (- (vector-length v) 1)) (rows '()))
                                  (if (< i 0) rows (loop (- i 1) (cons (%row (number->string i) (vector-ref v i)) rows))))
                                1000)))

(define (%string-view s)
  (vector "String"
          (cons (%row "length" (string-length s))
                (%rows-up-to (let loop ((i (- (string-length s) 1)) (rows '()))
                               (if (< i 0) rows (loop (- i 1) (cons (%row (number->string i) (string-ref s i)) rows))))
                             500))))

(define (%symbol-view s)
  (let ((kind (ide-definition-kind s)))
    (vector "Symbol"
            (append (list (%row "name" (symbol->string s))
                          (%row "kind" (or kind 'unbound)))
                    (if (and kind (not (eq? kind 'special-form))) (list (%row "value" (%value-of s))) '())
                    (let ((d (documentation s))) (if d (list (%row "documentation" d)) '()))))))

(define (%name-of v)
  (let ((n [v name])) (if (smalltalk-nil? n) #f n)))

(define (%procedure-view p)
  (let* ((name (%name-for p))
         (b (and name (symbol? name) (ide-browse name)))
         (src (procedure-source p)))
    (vector "Procedure"
            (append (list (%row "name" (or name 'anonymous)))
                    (let ((d (and name (symbol? name) (documentation name)))) (if d (list (%row "documentation" d)) '()))
                    (if src (list (%row "source" src)) '())
                    (if (and b (vector-ref b 4))
                        (list (%row "file" (vector-ref b 4)))
                        '())
                    (if (and name (symbol? name)) (list (%row "callers" (ide-callers name))) '())
                    (list (%row "kind" (if (%primitive? p) 'primitive 'procedure)))))))

(define (%macro-view m)
  (let ((src (%source-of m)))
    (vector "Macro"
            (append (list (%row "expander" [m expander]))
                    (if src (list (%row "source" src)) '())))))

(define (%hash-table-view h)
  (vector "Hash table"
          (%rows-up-to (map (lambda (k) (vector (%written k) (%written (hash-table-ref h k)) (hash-table-ref h k)))
                            (sort (hash-table-keys h) (lambda (a b) (string<? (%written a) (%written b)))))
                       1000)))

(define (%unit-view u)
  (vector "Unit"
          (list (%row "library" (let ((l [u library])) (if (smalltalk-nil? l) #f l)))
                (%row "path" (let ((p [u path])) (if (smalltalk-nil? p) #f p)))
                (%row "exports" (let ((e [u exports])) (if (smalltalk-nil? e) '() (vector->list e))))
                (%row "imports" (map (lambda (a) (cons [a key] [a value]))
                                     (vector->list [[[u imports] associations] asArray]))))))

(define (%condition-view c)
  (vector "Condition"
          (list (%row "report" (condition-report c))
                (%row "message" (error-object-message c))
                (%row "irritants" (error-object-irritants c)))))

(define (ide-views value)
  "(ide-views value)
What the inspector shows of value (R-22), as data: a list of views, each #(title rows), a row #(label written value), written as write writes it, value the part itself, inspectable in its turn. A list's elements, numbered from 1 (an improper list's rest last); a vector's and a string's, from 0; a symbol's name, kind, value and documentation; a procedure's name, documentation, source, file and callers; a macro's expander and source; a hash table's keys and values; a unit's library, path, exports and imports; a condition's report, message and irritants. Every value has a last view, Value: what it is written as, and its class. Long ones show their first thousand rows."
  (append
   (cond ((pair? value) (list (%list-view value)))
         ((vector? value) (list (%vector-view value)))
         ((string? value) (list (%string-view value)))
         ((symbol? value) (list (%symbol-view value)))
         ([value isKindOf: (smalltalk LispMacro)] (list (%macro-view value)))
         ((procedure? value) (list (%procedure-view value)))
         ([value isKindOf: (smalltalk LispHashTable)] (list (%hash-table-view value)))
         ([value isKindOf: (smalltalk LispUnit)] (list (%unit-view value)))
         ((error-object? value) (list (%condition-view value)))
         (else '()))
   (list (vector "Value" (list (let ((w (%written value))) (vector "written" w w))
                               (vector "class" [[[value class] name] asString] [value class]))))))

(define (ide-evaluate-with-it value text)
  "(ide-evaluate-with-it value text)
Evaluates text's forms with it bound to value (R-23), as the inspector's evaluator does, and answers the last form's value."
  ((eval (read (open-input-string (string-append "(lambda (it) " text "\n)")))) value))

(define (ide-inspect value)
  "(ide-inspect value)
Inspects value (R-24): in an inspector window when a world is showing (the development image), else by writing its views to the output port, a row a line. Answers value."
  (if [(smalltalk LispIde) canOpenWindows]
      [(smalltalk LispIde) inUI: (procedure->block (lambda () [(smalltalk LispInspectorPresenter) openOn: value]))]
      (for-each (lambda (view)
                  (display (vector-ref view 0)) (newline)
                  (for-each (lambda (row) (display "  ") (display (vector-ref row 0)) (display ": ") (display (vector-ref row 1)) (newline))
                            (vector-ref view 1)))
                (ide-views value)))
  value)

;;; ---------------------------------------------------------------------------
;;; A definition's original source, opened (browse)

;; the name a value is bound to: its procedure's own name, else a cell holding it
(define (%name-for x)
  (if (symbol? x)
      x
      (let ((own (and (procedure? x)
                      (guard (e (#t #f))
                        (let ((n [x name]))
                          (cond ((smalltalk-nil? n) #f)
                                ((string? n) (string->symbol n))
                                ((symbol? n) n)
                                (else #f)))))))
        (if (and own (eq? (%value-of own) x))
            own
            (let ((cell (find (lambda (c) (eq? [c value] x)) (%bound-cells))))
              (and cell [cell symbol]))))))

(define (%line-at path offset)
  (let ((text (guard (e (#t #f)) (car (ide-read-file path)))))
    (if (not text)
        1
        (let loop ((i 0) (line 1))
          (if (>= i (min offset (string-length text)))
              line
              (loop (+ i 1) (if (eq? (string-ref text i) #\newline) (+ line 1) line)))))))

(define (ide-open-source x)
  "(ide-open-source name-or-value)
The original source of a definition, given its name or its value, opened where it can be read and changed (what browse does): a definition in a file, in the editor at its place; a primitive, in the browser of Smalltalk, on the method that implements it; anything else bound, in the LISP browser. Without a world to open windows in, writes where it is instead. Answers the place: (path start end) for a file, (smalltalk class selector) for a primitive, (browser name) else; #f when x names nothing."
  (let* ((name (%name-for x))
         (b (and name (ide-browse name))))
    (if (not b)
        #f
        (let* ((path (vector-ref b 4))
               (st (vector-ref b 8))
               (place (cond (path (list path (vector-ref b 5) (vector-ref b 6)))
                            (st (list 'smalltalk (car st) (cadr st)))
                            (else (list 'browser name)))))
          (cond ((not [(smalltalk LispIde) canOpenWindows])
                 (display name) (display ": ")
                 (cond (path (display path) (display ":") (display (%line-at path (vector-ref b 5))))
                       (st (display "a primitive, written in Smalltalk, in ") (display (car st)) (display ">>") (display (cadr st))
                           (newline) (display (caddr st)))
                       (else (display "no file holds it")))
                 (newline))
                (path [(smalltalk LispIde) inUI: (procedure->block
                                                  (lambda () [(smalltalk LispIde) openEditorOn: path from: (vector-ref b 5) to: (vector-ref b 6)]))])
                (st [(smalltalk LispIde) inUI: (procedure->block
                                                (lambda () [(smalltalk LispIde) browseSmalltalk: (car st) selector: (cadr st)]))])
                (else [(smalltalk LispIde) inUI: (procedure->block
                                                  (lambda () [(smalltalk LispBrowserPresenter) openOn: name]))]))
          place))))
