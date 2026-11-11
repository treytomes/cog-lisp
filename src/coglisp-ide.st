"============================================================================
 cog-lisp : developing in the image  (package CogLisp-IDE)
 The glue the image's own tools stand on, per specs/34-morphic-ide.md: thin
 Smalltalk where Pharo's machinery needs a class, the rest in LISP
 (lib/ide.lisp, lib/editor-services.lisp).

 LOADER script. Must be filed in AFTER the shell package.

 Classes:
   LispSession        an evaluation in a process of its own (R-12, R-13, R-31):
                      requests in, results out, its own unit and ports, and a
                      break loop on the failing computation's stack (R-14)
   LispSessionInput   the lines a session's program reads, as they are typed
   LispSessionResult  what a request answered: done, error, aborted or running
   LispIde            the way from Smalltalk into lib/ide.lisp, the console
                      library's escape codes as text attributes (R-16), and the
                      development image's start in the GUI: its requests, its
                      heartbeat, its update in place (R-1 to R-4, R-37)
   LispReplPresenter  the REPL window (R-12 to R-16), on lib/ide.lisp's sessions;
                      its transcript an emulated terminal, the console library
                      rendering there as in a terminal (R-39)
   LispKeyQueue       the keys typed in a window, for the console there (R-39)
   LispTerminalView   the terminal pane: the console's rows in the code font,
                      typed into at its cursor (R-40)
   LispFilesPresenter the files the image has loaded (R-41)
   LispStyler         LISP source styled from its tokens (R-6)
   LispEditorPage     one file open in the editor (R-5 to R-9)
   LispEditorPresenter the editor: the project's files, a tab for each (R-5 to R-11)
 ============================================================================"
| failures cm sess sinput sresult ide replp keyq tview files styler epage editorp |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

sess := (Object << #LispSession) slots: { #name. #maker. #unit. #compiler. #process. #requests. #ready. #answers. #answered. #pending. #output. #input. #inputPort. #busy. #wrapper }; sharedVariables: { #Sessions }; package: 'CogLisp-IDE'; install.
sinput := (Object << #LispSessionInput) slots: { #lines. #ready. #closed }; package: 'CogLisp-IDE'; install.
sresult := (Object << #LispSessionResult) slots: { #status. #values. #output. #report. #restarts. #level }; package: 'CogLisp-IDE'; install.
ide := (Object << #LispIde) sharedVariables: { #Watcher }; package: 'CogLisp-IDE'; install.
replp := (SpPresenter << #LispReplPresenter) slots: { #session. #view. #termView. #restartsBar. #interruptButton. #history. #historyIndex. #shown. #transcriptText. #historyLines. #buffer. #bufferCursor. #updates. #idle. #busy. #level. #restarts. #terminal. #keys. #columns. #rows. #sessionSource. #ownsSession. #after }; package: 'CogLisp-IDE'; install.
tview := (Morph << #LispTerminalView) slots: { #target. #lines. #caret. #top. #selectFrom. #selectTo }; package: 'CogLisp-IDE'; install.
files := (SpPresenter << #LispFilesPresenter) slots: { #list. #source. #runButton. #refreshButton }; package: 'CogLisp-IDE'; install.
styler := (SHRBTextStyler << #LispStyler) slots: { #palette. #page }; package: 'CogLisp-IDE'; install.
epage := (SpPresenter << #LispEditorPage) slots: { #code. #path. #ending. #savedText. #editor. #repl. #bottom. #problemsList. #problems. #checkGeneration. #diskText. #choices }; package: 'CogLisp-IDE'; install.
editorp := (SpPresenter << #LispEditorPresenter) slots: { #tree. #notebook. #status. #toolbar. #pages. #tabs. #folder. #lastRun. #watching }; package: 'CogLisp-IDE'; install.
keyq := (Object << #LispKeyQueue) slots: { #chars. #ready. #wanted }; package: 'CogLisp-IDE'; install.

"=== LispSessionInput: lines typed for a program that reads ==================="
cm value: sinput class value: 'instance creation' value: 'new
	^ super new setUp'.
cm value: sinput value: 'private' value: 'setUp
	lines := OrderedCollection new.
	ready := Semaphore new.
	closed := false'.
cm value: sinput value: 'adding' value: 'add: aLine
	"A line for the program to read; it waits for one while none is there."
	lines addLast: aLine.
	ready signal'.
cm value: sinput value: 'adding' value: 'close
	closed := true.
	ready signal'.
cm value: sinput value: 'reading' value: 'atEnd
	"Waits, in the session''s process only (the UI is never stopped), for a line or the end."
	[lines isEmpty and: [closed not]] whileTrue: [ready wait].
	^ lines isEmpty'.
cm value: sinput value: 'reading' value: 'nextLine
	^ lines isEmpty ifTrue: [''''] ifFalse: [lines removeFirst]'.

"=== LispSessionResult ======================================================="
cm value: sresult class value: 'instance creation' value: 'status: aSymbol values: anArray output: aString report: aReport restarts: names level: n
	^ self new setStatus: aSymbol values: anArray output: aString report: aReport restarts: names level: n'.
cm value: sresult class value: 'instance creation' value: 'running
	^ self status: #running values: #() output: '''' report: nil restarts: #() level: 0'.
cm value: sresult value: 'private' value: 'setStatus: aSymbol values: anArray output: aString report: aReport restarts: names level: n
	status := aSymbol.
	values := anArray.
	output := aString.
	report := aReport.
	restarts := names.
	level := n'.
cm value: sresult value: 'accessing' value: 'status
	"#done, #error (the session waits at a break: level is its depth), #aborted, or #running"
	^ status'.
cm value: sresult value: 'accessing' value: 'values
	^ values'.
cm value: sresult value: 'accessing' value: 'output
	"What the request wrote to the current output port."
	^ output'.
cm value: sresult value: 'accessing' value: 'report
	"An error''s report, or nil."
	^ report'.
cm value: sresult value: 'accessing' value: 'restarts
	"The names of the restarts active at an error."
	^ restarts'.
cm value: sresult value: 'accessing' value: 'level
	^ level'.
cm value: sresult value: 'printing' value: 'printOn: aStream
	aStream nextPutAll: ''a session result ('' , status , '')'''.

"=== LispSession ============================================================="
cm value: sess class value: 'instance creation' value: 'named: aName unit: aUnit maker: aSymbol
	"A session, its process started, waiting for its first request. aUnit nil makes a
	 session unit of its own (specs/27-namespaces.md R-12); aSymbol says who makes its
	 changes: #person or #agent (specs/34-morphic-ide.md R-35)."
	| s |
	s := self new setName: aName unit: aUnit maker: aSymbol.
	self all add: s.
	^ s start'.
cm value: sess class value: 'registry' value: 'all
	"The sessions open in this image."
	^ Sessions ifNil: [Sessions := OrderedCollection new]'.
cm value: sess value: 'private' value: 'setName: aName unit: aUnit maker: aSymbol
	name := aName.
	unit := aUnit ifNil: [LispUnit session].
	maker := aSymbol.
	compiler := LispCompiler new.
	requests := OrderedCollection new.
	ready := Semaphore new.
	answers := OrderedCollection new.
	answered := Semaphore new.
	pending := 0.
	output := WriteStream on: (String new: 1000).
	input := LispSessionInput new.
	inputPort := LispInputPort onStream: (LispLineStream on: input).
	busy := false'.
cm value: sess value: 'private' value: 'start
	process := [self serveAt: 0] newProcess.
	process name: ''cog-lisp session '' , name asString.
	"below the UI: a long evaluation never keeps the windows from drawing"
	process priority: Processor userBackgroundPriority.
	process resume'.
cm value: sess value: 'accessing' value: 'name
	^ name'.
cm value: sess value: 'accessing' value: 'maker
	^ maker'.
cm value: sess value: 'accessing' value: 'unit
	^ unit'.
cm value: sess value: 'accessing' value: 'isBusy
	"Evaluating now; at a break, a session waits and is not busy."
	^ busy'.
cm value: sess value: 'accessing' value: 'wrapper: aProcedureOrBlock
	"Runs around every evaluation, given a thunk to call: (lambda (thunk) (with-console ... thunk))."
	wrapper := aProcedureOrBlock'.
cm value: sess value: 'accessing' value: 'output
	"Everything the session has written so far."
	^ output contents'.
cm value: sess value: 'accessing' value: 'outputSince: aPosition
	| s |
	s := output contents.
	^ aPosition >= s size ifTrue: [''''] ifFalse: [s copyFrom: aPosition + 1 to: s size]'.

cm value: sess value: 'requests' value: 'evaluate: aString
	"Ask the session to evaluate aString''s forms; answers at once. waitFor: answers the result."
	pending := pending + 1.
	requests addLast: aString.
	ready signal'.
cm value: sess value: 'requests' value: 'evaluate: aString waitFor: milliseconds
	self evaluate: aString.
	^ self waitFor: milliseconds'.
cm value: sess value: 'requests' value: 'waitFor: milliseconds
	"The next result, waiting at most milliseconds (nil: as long as it takes); a
	 running result if it has not come by then, and a later waitFor: answers it."
	milliseconds isNil
		ifTrue: [answered wait]
		ifFalse: [(answered waitTimeoutMilliseconds: milliseconds) ifTrue: [^ LispSessionResult running]].
	^ answers removeFirst'.
cm value: sess value: 'requests' value: 'type: aLine
	"A line for the program the session runs to read."
	input add: aLine'.
cm value: sess value: 'requests' value: 'interrupt
	"Stops the evaluation running now: the session waits at a break, its restarts offered."
	busy ifTrue: [process signalException: (Error new messageText: ''interrupted'')]'.
cm value: sess value: 'requests' value: 'close
	input close.
	process ifNotNil: [process terminate].
	self class all remove: self ifAbsent: [nil]'.

cm value: sess value: 'serving' value: 'nextRequest
	[requests isEmpty] whileTrue: [ready wait].
	^ requests removeFirst'.
cm value: sess value: 'serving' value: 'answer: aResult
	pending := pending - 1 max: 0.
	answers addLast: aResult.
	answered signal'.
cm value: sess value: 'serving' value: 'serveAt: level
	"Evaluates requests, one at a time. At level 0 an abort restart comes back here;
	 deeper, this is a break loop on the stack of the computation that failed."
	[self run: self nextRequest at: level] repeat'.
cm value: sess value: 'serving' value: 'run: text at: level
	| start values aborted |
	start := output position.
	values := OrderedCollection new.
	aborted := false.
	busy := true.
	LispRestart
		withRestarts: (level = 0 ifTrue: [{ LispRestart name: ''abort'' action: [aborted := true. nil] }] ifFalse: [#()])
		do: [
			[self inContext: [| reader d |
				reader := LispReader on: text.
				[(d := reader next) == LispReader eofObject] whileFalse: [
					values add: (compiler eval: d from: reader)]].
			 busy := false.
			 self answer: (LispSessionResult status: #done values: values asArray output: (self outputSince: start)
				report: nil restarts: #() level: level)]
				on: Error
				do: [:e |
					busy := false.
					self answer: (LispSessionResult status: #error values: #() output: (self outputSince: start)
						report: (LispError describe: e)
						restarts: (LispRestart active collect: [:r | r name name asString]) asArray
						level: level + 1).
					self serveAt: level + 1]].
	busy := false.
	"an abort comes back here: the request that asked for it is answered"
	aborted ifTrue: [
		self answer: (LispSessionResult status: #aborted values: #() output: (self outputSince: start)
			report: nil restarts: #() level: 0)]'.
cm value: sess value: 'serving' value: 'inContext: aBlock
	"aBlock in the session''s unit, with its own output and input ports (R-31), inside
	 its wrapper if it has one."
	^ LispCurrentUnit value: unit during: [
		LispPrimitives withOutput: output do: [
			LispPrimitives withInput: inputPort do: [
				wrapper isNil
					ifTrue: [aBlock value]
					ifFalse: [(wrapper isKindOf: LispProcedure)
						ifTrue: [LispProcedure apply: wrapper to: { LispProcedure fixed: [aBlock value] arity: 0 }]
						ifFalse: [wrapper value: aBlock]]]]]'.

"=== LispIde: into lib/ide.lisp, and terminal text as Text =================="
cm value: ide class value: 'calling' value: 'ensureLoaded
	"The ide and console libraries, loaded once."
	(LispEnvironment default isBound: (LispSymbol named: ''console:with-console'')) ifFalse: [
		LispCompiler new evalString: ''(require (quote console))''].
	(LispEnvironment default isBound: (LispSymbol named: ''ide:ide-eval'')) ifFalse: [
		LispCompiler new evalString: ''(require (quote ide))'']'.
cm value: ide class value: 'calling' value: 'call: aName with: anArray
	"Calls the LISP procedure aName (its full name, ide:ide-eval) on anArray''s values."
	self ensureLoaded.
	^ LispProcedure apply: (LispEnvironment default lookup: (LispSymbol named: aName)) to: anArray asArray'.
cm value: ide class value: 'calling' value: 'onUi: aBlock
	"aBlock''s value, run in Morphic''s UI process (here at once if this is it); an
	 error in it is signalled here. Windows are changed only in that process: the
	 VM yields a process at a preemption, so another at the same priority can run
	 in the middle of a layout."
	| ui done result error |
	"Morphic''s, which cycles the world headless too (UIManager default has none there)"
	ui := [MorphicUIManager uiProcess] on: Error do: [:e | nil].
	(ui isNil or: [ui == Processor activeProcess or: [ui isTerminated]]) ifTrue: [^ aBlock value].
	done := Semaphore new.
	self currentWorld defer: [
		[result := aBlock value] on: Error do: [:e | error := e].
		done signal].
	(done waitTimeoutMilliseconds: 120000)
		ifTrue: [^ LispError new messageText: ''the UI process did not answer''; signal].
	error ifNotNil: [^ LispError new messageText: (LispError describe: error); signal].
	^ result'.
cm value: ide class value: 'calling' value: 'symbol: aString
	^ LispSymbol named: aString'.
cm value: ide class value: 'calling' value: 'evalString: aString
	self ensureLoaded.
	^ LispCompiler new evalString: aString'.
cm value: ide class value: 'reading' value: 'isComplete: aString
	"Does aString hold whole forms? An unfinished one (an open list or string) is not;
	 one that does not read at all is, so that evaluating it reports the error."
	^ [| r | r := LispReader on: aString.
		[r next == LispReader eofObject] whileFalse.
		true]
		on: LispReadError
		do: [:e | e isIncomplete not]'.
cm value: ide class value: 'terminal text' value: 'palette16
	"meant for a dark background: VS Code''s terminal''s (R-40)"
	^ #((0 0 0) (205 49 49) (13 188 121) (229 229 16) (36 114 200) (188 63 188) (17 168 205) (229 229 229)
		(102 102 102) (241 76 76) (35 209 139) (245 245 67) (59 142 234) (214 112 214) (41 184 219) (255 255 255))
		collect: [:rgb | Color r: (rgb at: 1) / 255 g: (rgb at: 2) / 255 b: (rgb at: 3) / 255]'.
cm value: ide class value: 'terminal text' value: 'color256: n
	| levels k |
	n < 16 ifTrue: [^ self palette16 at: n + 1].
	n > 231 ifTrue: [k := (8 + (10 * (n - 232))) / 255. ^ Color r: k g: k b: k].
	levels := #(0 95 135 175 215 255).
	k := n - 16.
	^ Color
		r: (levels at: k // 36 + 1) / 255
		g: (levels at: k // 6 \\ 6 + 1) / 255
		b: (levels at: k \\ 6 + 1) / 255'.
cm value: ide class value: 'terminal text' value: 'textFromTerminal: aString
	"aString as a Text: the console library''s SGR codes as color and emphasis (R-16);
	 every other escape sequence (a cursor movement, a title) dropped."
	| result segment fg bold italic underline flush i n c params apply |
	result := Text new.
	segment := WriteStream on: String new.
	fg := nil. bold := false. italic := false. underline := false.
	flush := [segment contents isEmpty ifFalse: [| attrs |
		attrs := OrderedCollection new.
		fg ifNotNil: [attrs add: (TextColor color: fg)].
		bold ifTrue: [attrs add: TextEmphasis bold].
		italic ifTrue: [attrs add: TextEmphasis italic].
		underline ifTrue: [attrs add: TextEmphasis underlined].
		result := result , (Text string: segment contents attributes: attrs asArray).
		segment := WriteStream on: String new]].
	apply := [:codes | | k code |
		k := 1.
		[k <= codes size] whileTrue: [
			code := codes at: k.
			code = 0 ifTrue: [fg := nil. bold := false. italic := false. underline := false].
			code = 1 ifTrue: [bold := true].
			code = 3 ifTrue: [italic := true].
			code = 4 ifTrue: [underline := true].
			code = 22 ifTrue: [bold := false].
			code = 23 ifTrue: [italic := false].
			code = 24 ifTrue: [underline := false].
			code = 39 ifTrue: [fg := nil].
			(code between: 30 and: 37) ifTrue: [fg := self palette16 at: code - 29].
			(code between: 90 and: 97) ifTrue: [fg := self palette16 at: code - 81].
			(code = 38 or: [code = 48]) ifTrue: [
				(k + 1 <= codes size and: [(codes at: k + 1) = 5]) ifTrue: [
					code = 38 ifTrue: [fg := self color256: (codes at: k + 2 ifAbsent: [0])].
					k := k + 2].
				(k + 1 <= codes size and: [(codes at: k + 1) = 2]) ifTrue: [
					code = 38 ifTrue: [fg := Color
						r: (codes at: k + 2 ifAbsent: [0]) / 255
						g: (codes at: k + 3 ifAbsent: [0]) / 255
						b: (codes at: k + 4 ifAbsent: [0]) / 255].
					k := k + 4]].
			k := k + 1]].
	i := 1.
	n := aString size.
	[i <= n] whileTrue: [
		c := aString at: i.
		c asInteger = 27
			ifFalse: [segment nextPut: c. i := i + 1]
			ifTrue: [
				flush value.
				(i < n and: [(aString at: i + 1) = $[])
					ifTrue: [| j |
						j := i + 2.
						[j <= n and: [((aString at: j) asInteger between: 64 and: 126) not]] whileTrue: [j := j + 1].
						(j <= n and: [(aString at: j) = $m]) ifTrue: [
							params := (aString copyFrom: i + 2 to: j - 1) substrings: '';''.
							apply value: (params isEmpty
								ifTrue: [#(0)]
								ifFalse: [params collect: [:s | s asInteger ifNil: [0]]])].
						i := j + 1]
					ifFalse: [
						(i < n and: [(aString at: i + 1) = $]])
							ifTrue: [| j |
								j := i + 2.
								[j <= n and: [(aString at: j) asInteger ~= 7 and: [(aString at: j) asInteger ~= 27]]] whileTrue: [j := j + 1].
								i := (j <= n and: [(aString at: j) asInteger = 27]) ifTrue: [j + 2] ifFalse: [j + 1]]
							ifFalse: [i := i + 2]]]].
	flush value.
	^ result'.

"=== LispIde: the development image in the GUI (R-1 to R-4, R-37) ==========="
cm value: ide class value: 'development image' value: 'startUp: resuming
	"At a GUI start of a development image (one with a requests folder beside it),
	 take its requests and keep its heartbeat. Any other start, a headless run or
	 a build, does nothing here."
	(resuming and: [Smalltalk isInteractive and: [(Smalltalk imageDirectory / ''requests'') exists]])
		ifTrue: [[self startInGui] forkAt: Processor userBackgroundPriority]'.
cm value: ide class value: 'development image' value: 'shutDown: quitting
	"Quitting, a development image removes its heartbeat, so a launcher does not take
	 it for running for the ten seconds after (R-37)."
	(quitting and: [Watcher notNil]) ifTrue: [
		Watcher terminate.
		Watcher := nil.
		[(Smalltalk imageDirectory / ''heartbeat'') ensureDelete] on: Error do: [:e | nil]]'.
cm value: ide class value: 'development image' value: 'startEnvironment
	"*env* as a program run has it. The launchers set COGLISP_HOME; without it the
	 cog-lisp folder is the one above pharo/ide/."
	| name |
	[(OSEnvironment current at: ''COGLISP_HOME'' ifAbsent: ['''']) isEmpty ifTrue: [
		OSEnvironment current at: ''COGLISP_HOME'' put: Smalltalk imageDirectory parent parent fullName]]
		on: Error do: [:e | nil].
	name := LispSymbol named: ''%env-start!!''.
	(LispEnvironment default isBound: name) ifTrue: [(LispEnvironment default lookup: name) value]'.
cm value: ide class value: 'development image' value: 'startInGui
	"Takes requests every two seconds, touching the heartbeat the launchers read;
	 the first time, opens a REPL if no request did, and offers an update when the
	 checkout has changed since the image was built (R-3, R-4)."
	| dir first |
	dir := Smalltalk imageDirectory / ''requests''.
	self startEnvironment.
	self ensureLoaded.
	Watcher ifNotNil: [:w | w terminate].
	first := true.
	Watcher := [[| opened |
		self touchHeartbeat.
		opened := [self takeRequestsIn: dir] on: Error do: [:e | #()].
		first ifTrue: [
			first := false.
			opened isEmpty ifTrue: [self inUI: [LispReplPresenter open]].
			[self offerUpdate] on: Error do: [:e | nil]].
		(Delay forSeconds: 2) wait] repeat] newProcess.
	Watcher name: ''cog-lisp requests''; priority: Processor userBackgroundPriority; resume'.
cm value: ide class value: 'development image' value: 'touchHeartbeat
	(Smalltalk imageDirectory / ''heartbeat'') ensureDelete; writeStreamDo: [:s | s nextPutAll: DateAndTime now printString]'.
cm value: ide class value: 'development image' value: 'inUI: aBlock
	"aBlock in the UI process; at once, headless."
	UIManager default defer: aBlock'.
cm value: ide class value: 'development image' value: 'takeRequestsIn: aDirectory
	"Takes the request files in aDirectory, oldest name first, each removed once read,
	 and acts on what lib/ide.lisp makes of it. Answers the REPL windows opened."
	| dir opened |
	dir := aDirectory asFileReference.
	opened := OrderedCollection new.
	dir exists ifFalse: [^ opened].
	((dir files select: [:f | f extension = ''request'']) asSortedCollection: [:a :b | a basename <= b basename]) do: [:f | | text answer |
		text := [f contents] on: Error do: [:e | nil].
		f ensureDelete.
		text ifNotNil: [
			answer := [self call: ''ide:ide-request'' with: { text }] on: Error do: [:e | nil].
			(self act: answer) ifNotNil: [:p | opened add: p]]].
	^ opened'.
cm value: ide class value: 'development image' value: 'act: anAnswer
	"repl: a new REPL window; (run path): a new REPL window that loads path; update:
	 the update in place. Answers the window opened, or nil."
	| p |
	anAnswer isNil ifTrue: [^ nil].
	(anAnswer isKindOf: LispSymbol) ifTrue: [
		anAnswer name = ''repl'' ifTrue: [p := LispReplPresenter new. self inUI: [p open]. ^ p].
		anAnswer name = ''update'' ifTrue: [self inUI: [self updateFromCheckout]].
		^ nil].
	(anAnswer isKindOf: LispCons) ifTrue: [| path |
		path := anAnswer cdr car.
		p := LispReplPresenter new.
		self inUI: [p open. p evaluate: ''(load '' , (LispPrinter writeString: path) , '')''].
		^ p].
	^ nil'.
cm value: ide class value: 'development image' value: 'offerUpdate
	| stale |
	stale := self call: ''ide:ide-stale-files'' with: #().
	(stale isKindOf: LispCons) ifFalse: [^ self].
	self inUI: [
		(UIManager default confirm: ''The checkout has changed since this image was built: '' ,
			(LispPrinter writeString: stale) ,
			''. Update the image in place now? A copy of it as last saved is kept beside it.'')
			ifTrue: [self updateFromCheckout]]'.
cm value: ide class value: 'development image' value: 'updateFromCheckout
	"The update in place (R-3), its answer shown."
	| answer |
	answer := self call: ''ide:ide-update'' with: #().
	UIManager default inform: ''cog-lisp update: '' , (LispPrinter writeString: answer)'.
cm value: ide class value: 'development image' value: 'refileSourceFrom: aPath
	"Files in the src/ packages at aPath again, as the build does (build.st chunk 2),
	 then removes the methods src/ no longer defines (chunk 3). Answers the names removed."
	| dir compiled listener packages |
	dir := aPath asFileReference.
	compiled := Set new.
	listener := Object new.
	SystemAnnouncer uniqueInstance
		when: MethodAdded, MethodModified
		do: [:a | compiled add: a methodClass name asString , ''>>'' , a selector]
		for: listener.
	[#(''coglisp-reader.st'' ''coglisp-core.st'' ''coglisp-compiler.st'' ''coglisp-runtime.st'' ''coglisp-shell.st'' ''coglisp-ide.st'')
		do: [:name | (dir / name) fileIn]]
		ensure: [SystemAnnouncer uniqueInstance unsubscribe: listener].
	packages := ((PackageOrganizer default packages select: [:p | p name beginsWith: ''CogLisp-'']) collect: [:p | p name asString]) asArray.
	^ (LispCompiler removeStaleFrom: (Dictionary new
		at: #compiled put: compiled;
		at: #seedPackages put: packages;
		at: #sourceDirectory put: dir;
		yourself)) asArray'.
cm value: ide class value: 'world menu' value: 'menuCommandOn: aBuilder
	"One cog-lisp menu in the menu bar (R-41)."
	<worldMenu>
	(aBuilder item: #''cog-lisp'')
		order: 0.5;
		help: ''cog-lisp''''s tools (specs/34-morphic-ide.md)''.
	(aBuilder item: #''New REPL'')
		parent: #''cog-lisp''; order: 1;
		help: ''A cog-lisp REPL, on a session of its own'';
		action: [LispReplPresenter open].
	(aBuilder item: #''Editor'')
		parent: #''cog-lisp''; order: 1.5;
		help: ''The editor, on the project: its files, a tab for each (Ctrl+S save, Ctrl+D do it, Ctrl+P print it, Ctrl+L load)'';
		action: [LispEditorPresenter open].
	(aBuilder item: #''Loaded files'')
		parent: #''cog-lisp''; order: 2;
		help: ''The files the image has loaded: their source, and running one in a new REPL'';
		action: [LispFilesPresenter open].
	(aBuilder item: #''Update the image from the checkout'')
		parent: #''cog-lisp''; order: 3;
		help: ''Bring this image up to date with the source in the checkout, in place (R-3)'';
		action: [self updateFromCheckout]'.

"=== LispReplPresenter: the REPL window (R-12 to R-16) ======================="
"=== LispKeyQueue: the keys typed in a window, for a console there (R-39) ==="
cm value: keyq class value: 'instance creation' value: 'new
	^ super new reset'.
cm value: keyq value: 'adding' value: 'add: aString
	"Characters typed, for the program that reads keys."
	aString do: [:c | chars addLast: c].
	ready signal'.
cm value: keyq value: 'reading' value: 'nextWithin: milliseconds
	"The next character typed, waiting at most milliseconds (nil: as long as it
	 takes), or nil. Marks that the program reads keys (wantsKeys)."
	| deadline |
	wanted := true.
	milliseconds isNil ifTrue: [
		[chars isEmpty] whileTrue: [ready wait].
		^ chars removeFirst].
	deadline := Time millisecondClockValue + milliseconds.
	[chars isEmpty] whileTrue: [| left |
		left := deadline - Time millisecondClockValue.
		left <= 0 ifTrue: [^ nil].
		ready waitTimeoutMilliseconds: left].
	^ chars removeFirst'.
cm value: keyq value: 'accessing' value: 'wantsKeys
	"Has the program asked for a key since the queue was reset?"
	^ wanted'.
cm value: keyq value: 'accessing' value: 'reset
	chars := OrderedCollection new.
	ready := Semaphore new.
	wanted := false'.

"=== LispIde: keys and cells, for a console in a window (R-39) =============="
cm value: ide class value: 'console in a window' value: 'keysForValue: keyValue character: aCharacter control: control alt: alt
	"What a terminal sends for a key pressed in a window: an arrow, Home, End, Page
	 Up and Down and Delete as xterm escape sequences, Backspace as DEL, Enter as CR,
	 a Ctrl+letter as its control character, Alt+key after ESC. Morphic codes 28 to
	 31 are the arrows; 0 is Control alone, which sends nothing."
	| esc special |
	esc := String with: (Character value: 27).
	(control and: [aCharacter notNil and: [aCharacter isLetter]])
		ifTrue: [^ String with: (Character value: aCharacter asLowercase asInteger - 96)].
	special := #(30 ''[A'' 31 ''[B'' 29 ''[C'' 28 ''[D'' 1 ''[H'' 4 ''[F'' 11 ''[5~'' 12 ''[6~'' 127 ''[3~'').
	1 to: special size by: 2 do: [:i | (special at: i) = keyValue ifTrue: [^ esc , (special at: i + 1)]].
	keyValue = 8 ifTrue: [^ String with: (Character value: 127)].
	keyValue = 13 ifTrue: [^ String with: Character cr].
	keyValue = 27 ifTrue: [^ esc].
	keyValue = 9 ifTrue: [^ String with: Character tab].
	(aCharacter isNil or: [aCharacter asInteger < 32]) ifTrue: [^ ''''].
	^ alt ifTrue: [esc , (String with: aCharacter)] ifFalse: [String with: aCharacter]'.
cm value: ide class value: 'console in a window' value: 'colorFor: aValue
	"A console style''s color: a name (red, bright-blue), a 256-color index, or (rgb r g b)."
	| names i |
	(aValue isNil or: [aValue == false]) ifTrue: [^ nil].
	(aValue isKindOf: LispSymbol) ifTrue: [
		names := #(''black'' ''red'' ''green'' ''yellow'' ''blue'' ''magenta'' ''cyan'' ''white''
			''bright-black'' ''bright-red'' ''bright-green'' ''bright-yellow'' ''bright-blue'' ''bright-magenta'' ''bright-cyan'' ''bright-white'').
		i := names indexOf: aValue name asString.
		(#(''grey'' ''gray'') includes: aValue name asString) ifTrue: [i := 9].
		^ i = 0 ifTrue: [nil] ifFalse: [self palette16 at: i]].
	aValue isInteger ifTrue: [^ self color256: aValue].
	(aValue isKindOf: LispCons) ifTrue: [| rgb rest |
		rgb := OrderedCollection new.
		rest := aValue cdr.
		[rest isKindOf: LispCons] whileTrue: [rgb add: rest car. rest := rest cdr].
		rgb size = 3 ifTrue: [^ Color r: (rgb at: 1) / 255 g: (rgb at: 2) / 255 b: (rgb at: 3) / 255]].
	^ nil'.
cm value: ide class value: 'console in a window' value: 'attributesForStyle: aStyle
	"A console style, #(style foreground background attributes link), as text attributes."
	| attrs fg names list |
	(aStyle isKindOf: Array) ifFalse: [^ #()].
	attrs := OrderedCollection new.
	names := OrderedCollection new.
	list := aStyle at: 4.
	[list isKindOf: LispCons] whileTrue: [names add: list car name asString. list := list cdr].
	fg := self colorFor: (aStyle at: 2).
	(fg isNil and: [names includes: ''dim'']) ifTrue: [fg := Color gray].
	fg ifNotNil: [attrs add: (TextColor color: fg)].
	(names includes: ''bold'') ifTrue: [attrs add: TextEmphasis bold].
	(names includes: ''italic'') ifTrue: [attrs add: TextEmphasis italic].
	(names includes: ''underline'') ifTrue: [attrs add: TextEmphasis underlined].
	^ attrs asArray'.
cm value: ide class value: 'console in a window' value: 'textForRow: aRow
	"A row of an emulated terminal''s cells, (character . style), as a Text, without
	 its trailing spaces; the second cell of a wide character holds none."
	| text run runStyle flush end |
	text := Text new.
	run := WriteStream on: String new.
	runStyle := nil.
	flush := [run contents isEmpty ifFalse: [
		text := text , (Text string: run contents attributes: (self attributesForStyle: runStyle))].
		run := WriteStream on: String new].
	aRow do: [:cell | | c |
		c := cell car.
		(c isKindOf: Character) ifTrue: [
			cell cdr == runStyle ifFalse: [flush value. runStyle := cell cdr].
			run nextPut: c]].
	flush value.
	end := text size.
	[end > 0 and: [(text at: end) = Character space]] whileTrue: [end := end - 1].
	^ end = text size ifTrue: [text] ifFalse: [text copyFrom: 1 to: end]'.
cm value: ide class value: 'console in a window' value: 'rowIsBlank: aRow
	^ aRow allSatisfy: [:cell | (cell car isKindOf: Character) not or: [cell car = Character space]]'.
cm value: ide class value: 'console in a window' value: 'sgr: aCode
	^ (String with: (Character value: 27)) , ''['' , aCode , ''m'''.

"=== LispTerminalView: a terminal pane, drawn in the code font (R-39, R-40) ===="
cm value: tview class value: 'instance creation' value: 'on: aTarget
	"A view whose keys, and whose size, go to aTarget (the REPL window)."
	^ self new setTarget: aTarget'.
cm value: tview value: 'initialization' value: 'setTarget: aTarget
	lines := OrderedCollection with: Text new.
	caret := nil.
	top := 1.
	selectFrom := nil.
	selectTo := nil.
	self color: (Color r: 0.118 g: 0.118 b: 0.118); clipSubmorphs: true; extent: 600 @ 400.
	"the target last: a size set before it is the view''s own"
	target := aTarget'.
cm value: tview value: 'accessing' value: 'font
	^ StandardFonts codeFont'.
cm value: tview value: 'accessing' value: 'cellWidth
	^ (self font widthOf: $M) max: 1'.
cm value: tview value: 'accessing' value: 'lineHeight
	^ self font height max: 1'.
cm value: tview value: 'accessing' value: 'columns
	"How many cells fit across."
	^ ((self width - 12) / self cellWidth) floor max: 1'.
cm value: tview value: 'accessing' value: 'rows
	"How many lines fit down."
	^ ((self height - 6) / self lineHeight) floor max: 1'.
cm value: tview value: 'accessing' value: 'lines
	^ lines'.
cm value: tview value: 'accessing' value: 'lines: aCollection caret: aPoint
	"Shows these lines (Texts), the caret at aPoint (column @ line, from 1), or none
	 for nil; brings the end into view."
	lines := aCollection isEmpty ifTrue: [OrderedCollection with: Text new] ifFalse: [aCollection].
	caret := aPoint.
	self scrollToEnd.
	self changed'.
cm value: tview value: 'scrolling' value: 'scrollToEnd
	top := (lines size - self rows + 1) max: 1'.
cm value: tview value: 'scrolling' value: 'scrollBy: n
	top := ((top + n) min: (lines size - self rows + 1)) max: 1.
	self changed'.
cm value: tview value: 'geometry' value: 'extent: aPoint
	| old |
	old := self extent.
	super extent: aPoint.
	old = aPoint ifFalse: [target ifNotNil: [:t | t viewResized]]'.
cm value: tview value: 'drawing' value: 'drawOn: aCanvas
	| font bold cw lh x0 y caretColor |
	super drawOn: aCanvas.
	font := self font.
	bold := [font emphasized: 1] on: Error do: [:e | font].
	cw := self cellWidth.
	lh := self lineHeight.
	x0 := self left + 6.
	caretColor := Color r: 0.85 g: 0.85 b: 0.85.
	aCanvas clipBy: self innerBounds during: [:c |
		y := self top + 3.
		top to: (top + self rows min: lines size) do: [:i | | line col |
			line := lines at: i.
			self drawSelectionOf: i on: c at: y.
			col := 0.
			line runs withStartStopAndValueDo: [:start :stop :attrs | | s fg isBold |
				s := line string copyFrom: start to: stop.
				fg := Color r: 0.85 g: 0.85 b: 0.85.
				isBold := false.
				attrs do: [:a |
					(a isKindOf: TextColor) ifTrue: [fg := a color].
					((a isKindOf: TextEmphasis) and: [a emphasisCode = 1]) ifTrue: [isBold := true]].
				c drawString: s at: (x0 + (col * cw)) @ y font: (isBold ifTrue: [bold] ifFalse: [font]) color: fg.
				col := col + s size].
			(caret notNil and: [caret y = i]) ifTrue: [| cx ch |
				cx := x0 + (caret x - 1 * cw).
				c fillRectangle: (cx @ y extent: cw @ lh) color: caretColor.
				ch := caret x <= line size ifTrue: [(line string at: caret x) asString] ifFalse: [''''].
				ch isEmpty ifFalse: [c drawString: ch at: cx @ y font: font color: self color]].
			y := y + lh]]'.
cm value: tview value: 'selecting' value: 'drawSelectionOf: i on: aCanvas at: y
	| from to a b cw x0 |
	(selectFrom isNil or: [selectTo isNil]) ifTrue: [^ self].
	from := selectFrom min: selectTo. to := selectFrom max: selectTo.
	(i between: from y and: to y) ifFalse: [^ self].
	cw := self cellWidth.
	x0 := self left + 6.
	a := i = from y ifTrue: [from x] ifFalse: [1].
	b := i = to y ifTrue: [to x] ifFalse: [(lines at: i) size + 1].
	b > a ifTrue: [
		aCanvas fillRectangle: ((x0 + (a - 1 * cw)) @ y extent: ((b - a) * cw) @ self lineHeight)
			color: (Color r: 0.2 g: 0.35 b: 0.55)]'.
cm value: tview value: 'selecting' value: 'positionAt: aPoint
	"column @ line under aPoint, from 1"
	| line col |
	line := ((aPoint y - self top - 3) / self lineHeight) floor + top.
	line := (line max: 1) min: lines size.
	col := ((aPoint x - self left - 6) / self cellWidth) rounded + 1.
	col := (col max: 1) min: (lines at: line) size + 1.
	^ col @ line'.
cm value: tview value: 'selecting' value: 'hasSelection
	^ selectFrom notNil and: [selectTo notNil and: [selectFrom ~= selectTo]]'.
cm value: tview value: 'selecting' value: 'selectedText
	"The text selected, lines joined by line feeds."
	| from to out |
	self hasSelection ifFalse: [^ ''''].
	from := selectFrom min: selectTo. to := selectFrom max: selectTo.
	(selectTo y < selectFrom y or: [selectTo y = selectFrom y and: [selectTo x < selectFrom x]])
		ifTrue: [from := selectTo. to := selectFrom].
	out := WriteStream on: String new.
	from y to: to y do: [:i | | s a b |
		s := (lines at: i) string.
		a := i = from y ifTrue: [from x] ifFalse: [1].
		b := i = to y ifTrue: [to x - 1] ifFalse: [s size].
		out nextPutAll: (s copyFrom: a to: (b min: s size)).
		i < to y ifTrue: [out nextPut: Character lf]].
	^ out contents'.
cm value: tview value: 'selecting' value: 'clearSelection
	selectFrom := nil. selectTo := nil'.
cm value: tview value: 'events' value: 'handlesKeyboard: anEvent
	^ true'.
cm value: tview value: 'events' value: 'handlesMouseDown: anEvent
	^ true'.
cm value: tview value: 'events' value: 'handlesMouseWheel: anEvent
	^ true'.
cm value: tview class value: 'keys' value: 'keyValueFor: aKeyboardKey
	"The Morphic key value of a key that types no character, as the REPL window
	 takes it (28 to 31 the arrows); nil for any other."
	| table |
	table := {
		KeyboardKey left -> 28. KeyboardKey right -> 29. KeyboardKey up -> 30. KeyboardKey down -> 31.
		KeyboardKey home -> 1. KeyboardKey end -> 4. KeyboardKey pageUp -> 11. KeyboardKey pageDown -> 12.
		KeyboardKey backspace -> 8. KeyboardKey delete -> 127. KeyboardKey escape -> 27.
		KeyboardKey enter -> 13. KeyboardKey keypadEnter -> 13. KeyboardKey tab -> 9 }.
	table do: [:a | a key = aKeyboardKey ifTrue: [^ a value]].
	"a key made from another platform''s table may be another object of the same name"
	table do: [:a | ([a key name = aKeyboardKey name] on: Error do: [:e | false]) ifTrue: [^ a value]].
	^ nil'.
cm value: tview class value: 'keys' value: 'legacyKeyValues
	"Morphic''s own codes for the keys that type no character, as a key-down event
	 carries them on Windows (Pharo''s Spotter reads them so)."
	^ #(1 4 8 9 11 12 13 27 28 29 30 31 127)'.
cm value: tview class value: 'keys' value: 'letterOf: aKeyboardKey
	"The letter a key types, lower case, or nil: for Ctrl+letter, which types none."
	| name |
	name := [aKeyboardKey name asString] on: Error do: [:e | ''''].
	^ (name size = 1 and: [name first isLetter]) ifTrue: [name first asLowercase] ifFalse: [nil]'.
cm value: tview value: 'events' value: 'handlesKeyDown: anEvent
	^ true'.
cm value: tview value: 'events' value: 'keyDown: anEvent
	"A key that types no character (an arrow, Backspace, Enter), or Ctrl with a
	 letter, arrives only as a key down: it goes to the REPL window here, and the
	 key press that may follow it is suppressed, so nothing happens twice (R-40)."
	| value control letter |
	target ifNil: [^ self].
	value := self class keyValueFor: anEvent key.
	control := anEvent controlKeyPressed or: [anEvent commandKeyPressed].
	(value isNil and: [control not and: [self class legacyKeyValues includes: anEvent keyValue]])
		ifTrue: [value := anEvent keyValue].
	letter := control ifTrue: [self class letterOf: anEvent key] ifFalse: [nil].
	(value isNil and: [letter isNil]) ifTrue: [^ self].
	[anEvent supressNextKeyPress: true] on: Error do: [:e | nil].
	target
		pressKey: (value ifNil: [letter asInteger])
		character: (letter ifNil: [Character value: value])
		control: control
		alt: anEvent altKeyPressed'.
cm value: tview value: 'events' value: 'keyStroke: anEvent
	"A character typed goes to the REPL window: it edits the line, or goes to the
	 program. Keys without a character came as key downs (keyDown:)."
	| c control |
	target ifNil: [^ self].
	c := [anEvent keyCharacter] on: Error do: [:e | nil].
	control := anEvent controlKeyPressed or: [anEvent commandKeyPressed].
	(c isNil or: [control or: [c asInteger < 32 or: [c asInteger = 127]]]) ifTrue: [^ self].
	target keyStroke: anEvent'.
cm value: tview value: 'events' value: 'mouseDown: anEvent
	self takeKeyboardFocus.
	selectFrom := self positionAt: anEvent position.
	selectTo := selectFrom.
	self changed'.
cm value: tview value: 'events' value: 'mouseMove: anEvent
	anEvent redButtonPressed ifTrue: [
		selectTo := self positionAt: anEvent position.
		self changed]'.
cm value: tview value: 'events' value: 'mouseUp: anEvent
	self changed'.
cm value: tview value: 'events' value: 'mouseWheel: anEvent
	self scrollBy: (anEvent isUp ifTrue: [-3] ifFalse: [3])'.

"=== LispReplPresenter: the REPL window (R-12 to R-16, R-39, R-40) ============"
cm value: replp class value: 'opening' value: 'open
	"A new REPL window, on a session of its own."
	^ self new open; yourself'.
cm value: replp value: 'initialization' value: 'initializePresenters
	"The window is a terminal pane (R-39), typed into at its cursor (R-40), with
	 the restarts of a break and an Interrupt button below it."
	termView := LispTerminalView on: self.
	view := self newMorph.
	view morph: termView.
	interruptButton := self newButton.
	interruptButton
		label: ''Interrupt'';
		icon: ([self iconNamed: #stop] on: Error do: [:e | nil]);
		help: ''Stop the evaluation running (Ctrl+C)'';
		action: [self interrupt];
		disable.
	[interruptButton color: (Color r: 0.55 g: 0.2 b: 0.2)] on: Error do: [:e | nil].
	restartsBar := self newPresenter.
	restartsBar layout: SpBoxLayout newLeftToRight.
	history := OrderedCollection new.
	historyIndex := 0.
	shown := 0.
	historyLines := OrderedCollection new.
	transcriptText := Text new.
	buffer := ''''.
	bufferCursor := 0.
	updates := OrderedCollection new.
	idle := Semaphore new.
	busy := false.
	level := 0.
	restarts := #().
	keys := LispKeyQueue new.
	"made at the first evaluation: a session of its own, or the one sessionSource: gives"
	sessionSource := [LispIde call: ''ide:ide-session'' with: { LispIde symbol: ''name''. ''REPL'' }].
	ownsSession := true.
	self emit: self prompt sgr: self promptColor'.
cm value: replp value: 'initialization' value: 'defaultLayout
	^ SpBoxLayout newTopToBottom
		add: view;
		add: (SpBoxLayout newLeftToRight
			add: restartsBar;
			add: interruptButton expand: false;
			yourself) height: 34;
		yourself'.
cm value: replp value: 'initialization' value: 'initializeWindow: aWindowPresenter
	aWindowPresenter
		title: ''cog-lisp REPL'';
		initialExtent: 760 @ 520.
	[aWindowPresenter whenOpenedDo: [termView takeKeyboardFocus]] on: Error do: [:e | nil].
	[aWindowPresenter whenClosedDo: [self closeSession]] on: Error do: [:e | nil]'.

cm value: replp value: 'accessing' value: 'session
	^ session ifNil: [session := sessionSource value]'.
cm value: replp value: 'accessing' value: 'sessionSource: aBlock
	"The REPL evaluates in the session aBlock answers, made at its first evaluation
	 and not its own: closing the REPL leaves it open (the editor''s pane, R-44)."
	sessionSource := aBlock.
	ownsSession := false'.
cm value: replp value: 'accessing' value: 'terminalView
	^ termView'.
cm value: replp value: 'accessing' value: 'transcriptText
	"The transcript as shown: a Text, its output in the colors the program wrote."
	^ transcriptText'.
cm value: replp value: 'accessing' value: 'transcriptString
	^ transcriptText asString'.
cm value: replp value: 'accessing' value: 'inputText
	"The line being typed at the cursor."
	^ buffer'.
cm value: replp value: 'accessing' value: 'inputText: aString
	buffer := aString.
	bufferCursor := aString size.
	self refresh'.
cm value: replp value: 'accessing' value: 'restartNames
	"The restarts offered while the session waits at a break."
	^ restarts'.
cm value: replp value: 'accessing' value: 'isBusy
	^ busy'.
cm value: replp value: 'accessing' value: 'level
	^ level'.
cm value: replp value: 'accessing' value: 'columns
	"The console''s width there, in cells: the pane''s."
	columns ifNil: [self measure].
	^ columns'.
cm value: replp value: 'accessing' value: 'rows
	rows ifNil: [self measure].
	^ rows'.
cm value: replp value: 'accessing' value: 'wantsKeys
	"Is the program running reading keys (a prompt, read-event)?"
	^ keys wantsKeys'.

cm value: replp value: 'colors' value: 'promptColor
	^ ''92'''.
cm value: replp value: 'colors' value: 'valueColor
	^ ''96'''.

cm value: replp value: 'terminal' value: 'measure
	"The console''s size: the pane''s, in cells of the code font."
	"too small to be a pane (a headless world is 240 by 120): a terminal''s usual size"
	columns := termView columns.
	columns < 40 ifTrue: [columns := 100].
	rows := termView rows.
	rows < 8 ifTrue: [rows := 30]'.
cm value: replp value: 'terminal' value: 'viewResized
	"The pane changed size: the next evaluation''s console takes the new one."
	busy ifFalse: [self ensureTerminal. self refresh]'.
cm value: replp value: 'terminal' value: 'ensureTerminal
	"The emulated terminal, made again when the pane''s size changed: what it showed
	 then stays above, as history."
	| oldColumns oldRows |
	oldColumns := columns.
	oldRows := rows.
	self measure.
	(terminal notNil and: [oldColumns = columns and: [oldRows = rows]]) ifTrue: [^ self].
	terminal ifNotNil: [| screenLines |
		screenLines := self screenLines.
		"the prompt is written again into the new terminal: leave the old one out"
		(level = 0 and: [busy not and: [screenLines notEmpty and: [screenLines last asString = self prompt trimRight]]])
			ifTrue: [screenLines removeLast].
		historyLines addAll: screenLines].
	terminal := LispIde call: ''console:make-terminal'' with: {
		columns. rows. LispIde symbol: ''history''. 2000. LispIde symbol: ''log''. false }.
	(oldColumns notNil and: [busy not]) ifTrue: [
		LispIde call: ''console:terminal-write!!'' with: { terminal. (LispIde sgr: self promptColor) , self prompt , (LispIde sgr: ''0'') }]'.
cm value: replp value: 'terminal' value: 'emit: aString
	"Writes to the terminal, as a program''s output is, and shows it."
	terminal ifNil: [self ensureTerminal].
	LispIde call: ''console:terminal-write!!'' with: { terminal. aString }.
	self refresh'.
cm value: replp value: 'terminal' value: 'emit: aString sgr: aCode
	self emit: (LispIde sgr: aCode) , aString , (LispIde sgr: ''0'')'.
cm value: replp value: 'terminal' value: 'takeScrolled
	| scrolled |
	terminal ifNil: [^ self].
	scrolled := LispIde call: ''console:terminal-take-scrolled!!'' with: { terminal }.
	[scrolled isKindOf: LispCons] whileTrue: [
		historyLines add: (LispIde textForRow: scrolled car).
		scrolled := scrolled cdr].
	historyLines size > 5000 ifTrue: [historyLines removeFirst: historyLines size - 5000]'.
cm value: replp value: 'terminal' value: 'screenLines
	"The screen''s rows down to the cursor or the last row written, as Texts."
	| screen screenRows cursorRow last result |
	screen := LispIde call: ''console:terminal-screen'' with: { terminal }.
	screenRows := screen at: 4.
	cursorRow := (screen at: 7) + 1.
	last := cursorRow.
	cursorRow + 1 to: screenRows size do: [:i | (LispIde rowIsBlank: (screenRows at: i)) ifFalse: [last := i]].
	result := OrderedCollection new.
	1 to: last do: [:i | result add: (LispIde textForRow: (screenRows at: i))].
	^ result'.
cm value: replp value: 'terminal' value: 'refresh
	"The pane: the history, the screen, and the line being typed at the cursor, with
	 the caret where typing goes (R-40)."
	| screen all cursorRow cursorCol bufferLines caretPoint |
	terminal ifNil: [^ self].
	self takeScrolled.
	all := OrderedCollection withAll: historyLines.
	screen := LispIde call: ''console:terminal-screen'' with: { terminal }.
	cursorRow := historyLines size + (screen at: 7) + 1.
	cursorCol := (screen at: 6) + 1.
	all addAll: self screenLines.
	[all size < cursorRow] whileTrue: [all add: Text new].
	(busy and: [keys wantsKeys])
		ifTrue: [caretPoint := cursorCol @ cursorRow]
		ifFalse: [| line pos |
			"the line being typed, written after the cursor"
			bufferLines := buffer lines.
			(buffer isEmpty or: [buffer last = Character lf]) ifTrue: [bufferLines := bufferLines , #('''')].
			line := all at: cursorRow.
			line size < (cursorCol - 1) ifTrue: [line := line , (Text fromString: (String new: cursorCol - 1 - line size withAll: Character space))].
			line := (line copyFrom: 1 to: cursorCol - 1) , (Text fromString: bufferLines first).
			all at: cursorRow put: line.
			bufferLines allButFirst doWithIndex: [:l :k |
				cursorRow + k > all size
					ifTrue: [all add: (Text fromString: l)]
					ifFalse: [all at: cursorRow + k put: (Text fromString: l)]].
			pos := self caretInBuffer.
			caretPoint := (pos y = 1 ifTrue: [cursorCol + pos x - 1] ifFalse: [pos x]) @ (cursorRow + pos y - 1)].
	transcriptText := Text new.
	all doWithIndex: [:l :i |
		transcriptText := transcriptText , l.
		i < all size ifTrue: [transcriptText := transcriptText , (Text fromString: String lf)]].
	termView lines: all caret: caretPoint'.
cm value: replp value: 'terminal' value: 'caretInBuffer
	"column @ line of the caret within the line being typed, from 1"
	| line col |
	line := 1. col := 1.
	1 to: bufferCursor do: [:i |
		(buffer at: i) = Character lf
			ifTrue: [line := line + 1. col := 1]
			ifFalse: [col := col + 1]].
	^ col @ line'.
cm value: replp value: 'transcript' value: 'appendOutput
	"What the session wrote since it was last shown."
	| out |
	session ifNil: [^ self].
	out := session outputSince: shown.
	shown := shown + out size.
	out isEmpty ifFalse: [self emit: out]'.
cm value: replp value: 'transcript' value: 'prompt
	^ level > 0 ifTrue: [level printString , ''> ''] ifFalse: [''> '']'.

cm value: replp value: 'keys' value: 'keyStroke: anEvent
	"A key pressed in the pane (R-40)."
	self
		pressKey: anEvent keyValue
		character: ([anEvent keyCharacter] on: Error do: [:e | nil])
		control: (anEvent controlKeyPressed or: [anEvent commandKeyPressed])
		alt: anEvent altKeyPressed'.
cm value: replp value: 'keys' value: 'pressKey: keyValue character: aCharacter control: control alt: alt
	"While the program reads keys, every key is its own; otherwise the key edits the
	 line at the cursor. Ctrl+C copies a selection, else interrupts; Ctrl+V pastes."
	| ch |
	ch := (control and: [aCharacter notNil]) ifTrue: [aCharacter asLowercase] ifFalse: [nil].
	(ch = $c and: [termView hasSelection]) ifTrue: [
		Clipboard clipboardText: termView selectedText.
		termView clearSelection; changed.
		^ self].
	ch = $v ifTrue: [^ self paste: Clipboard clipboardText asString].
	termView clearSelection.
	(busy and: [keys wantsKeys]) ifTrue: [
		^ self typeKeys: (LispIde keysForValue: keyValue character: aCharacter control: control alt: alt)].
	ch = $c ifTrue: [busy ifTrue: [self interrupt] ifFalse: [buffer := ''''. bufferCursor := 0. self refresh]. ^ self].
	(control and: [keyValue = 28]) ifTrue: [^ self wordLeft].
	(control and: [keyValue = 29]) ifTrue: [^ self wordRight].
	control ifTrue: [^ self].
	keyValue = 13 ifTrue: [^ self submit].
	keyValue = 8 ifTrue: [^ self deleteBack].
	keyValue = 127 ifTrue: [^ self deleteForward].
	keyValue = 28 ifTrue: [bufferCursor := bufferCursor - 1 max: 0. ^ self refresh].
	keyValue = 29 ifTrue: [bufferCursor := bufferCursor + 1 min: buffer size. ^ self refresh].
	keyValue = 1 ifTrue: [bufferCursor := 0. ^ self refresh].
	keyValue = 4 ifTrue: [bufferCursor := buffer size. ^ self refresh].
	keyValue = 30 ifTrue: [^ self historyBack].
	keyValue = 31 ifTrue: [^ self historyForward].
	keyValue = 9 ifTrue: [^ self insert: ''  ''].
	(aCharacter notNil and: [aCharacter asInteger >= 32 and: [aCharacter asInteger ~= 127]])
		ifTrue: [self insert: (String with: aCharacter)]'.
cm value: replp value: 'keys' value: 'typeKeys: aString
	"Keys for the program running, as a terminal sends them."
	(busy and: [aString notEmpty]) ifTrue: [keys add: aString]'.
cm value: replp value: 'editing' value: 'insert: aString
	buffer := (buffer copyFrom: 1 to: bufferCursor) , aString , (buffer copyFrom: bufferCursor + 1 to: buffer size).
	bufferCursor := bufferCursor + aString size.
	self refresh'.
cm value: replp value: 'editing' value: 'paste: aString
	| text |
	text := aString copyReplaceAll: String crlf with: String lf.
	text := text copyReplaceAll: String cr with: String lf.
	(busy and: [keys wantsKeys]) ifTrue: [^ self typeKeys: text].
	self insert: text'.
cm value: replp value: 'editing' value: 'wordLeft
	"To the start of the word before the caret."
	[bufferCursor > 0 and: [(buffer at: bufferCursor) isAlphaNumeric not]] whileTrue: [bufferCursor := bufferCursor - 1].
	[bufferCursor > 0 and: [(buffer at: bufferCursor) isAlphaNumeric]] whileTrue: [bufferCursor := bufferCursor - 1].
	self refresh'.
cm value: replp value: 'editing' value: 'wordRight
	"To the end of the word after the caret."
	[bufferCursor < buffer size and: [(buffer at: bufferCursor + 1) isAlphaNumeric not]] whileTrue: [bufferCursor := bufferCursor + 1].
	[bufferCursor < buffer size and: [(buffer at: bufferCursor + 1) isAlphaNumeric]] whileTrue: [bufferCursor := bufferCursor + 1].
	self refresh'.
cm value: replp value: 'editing' value: 'deleteBack
	bufferCursor = 0 ifTrue: [^ self].
	buffer := (buffer copyFrom: 1 to: bufferCursor - 1) , (buffer copyFrom: bufferCursor + 1 to: buffer size).
	bufferCursor := bufferCursor - 1.
	self refresh'.
cm value: replp value: 'editing' value: 'deleteForward
	bufferCursor >= buffer size ifTrue: [^ self].
	buffer := (buffer copyFrom: 1 to: bufferCursor) , (buffer copyFrom: bufferCursor + 2 to: buffer size).
	self refresh'.

cm value: replp value: 'evaluating' value: 'submit
	"What Enter does: evaluates the line typed when it holds whole forms, and
	 otherwise starts a new line in it (R-12, R-40). While an evaluation runs, the
	 line is for the program: read as a line, or, when it reads keys, as keys."
	| text |
	text := buffer.
	busy ifTrue: [
		buffer := ''''. bufferCursor := 0.
		keys wantsKeys
			ifTrue: [self typeKeys: text , (String with: Character cr)]
			ifFalse: [
				self emit: text , String lf.
				LispIde call: ''ide:ide-type'' with: { session. text }].
		^ self].
	text trimBoth isEmpty ifTrue: [
		buffer := ''''. bufferCursor := 0.
		self emit: String lf , self prompt sgr: self promptColor.
		^ self].
	(LispIde isComplete: text) ifFalse: [^ self insert: String lf].
	history addLast: text.
	historyIndex := history size + 1.
	buffer := ''''. bufferCursor := 0.
	self evaluate: text'.
cm value: replp value: 'evaluating' value: 'evaluate: text
	^ self evaluate: text showing: text then: nil'.
cm value: replp value: 'evaluating' value: 'evaluate: text showing: shown then: aBlock
	"Shows shown after the prompt (the text itself when typed), and evaluates text in
	 the session, in a console the size of the pane whose keys are the ones typed
	 here (R-39); the window goes on working while it runs. Once its result is
	 shown, aBlock (if any) is given it. waitUntilIdle: waits for it."
	| first s |
	self ensureTerminal.
	self emit: shown , String lf.
	after := aBlock.
	s := self session.
	busy := true.
	keys reset.
	interruptButton enable.
	self showRestarts: #().
	s wrapper: (LispIde call: ''ide:ide-window-console'' with: { columns. rows. keys }).
	first := LispIde call: ''ide:ide-eval'' with: { s. text. LispIde symbol: ''timeout''. 0 }.
	[| r |
	 r := first.
	 [(r at: 1) name = ''running''] whileTrue: [
		self queue: [self appendOutput. self refresh].
		r := LispIde call: ''ide:ide-wait'' with: { s. 100 }].
	 self queue: [self show: r].
	 idle signal] forkAt: Processor userBackgroundPriority'.
cm value: replp value: 'evaluating' value: 'show: aResult
	"A result in the transcript, the values written or the error and its restarts,
	 then the prompt again."
	| status |
	self appendOutput.
	status := (aResult at: 1) name asString.
	busy := false.
	interruptButton disable.
	level := aResult at: 7.
	status = ''done'' ifTrue: [
		(aResult at: 3) do: [:w | self emit: w , String lf sgr: self valueColor].
		self showRestarts: #()].
	status = ''aborted'' ifTrue: [
		self emit: ''aborted'' , String lf sgr: ''90''.
		self showRestarts: #()].
	status = ''error'' ifTrue: [
		self emit: ''error: '' , (aResult at: 5) , String lf sgr: ''91''.
		self showRestarts: (aResult at: 6) asArray].
	self emit: self prompt sgr: self promptColor.
	after ifNotNil: [:b | after := nil. b value: aResult]'.
cm value: replp value: 'evaluating' value: 'showRestarts: names
	"The restarts as buttons (R-14): abort and continue run at once; one that takes
	 values puts (name ) at the prompt to be finished."
	| layout |
	restarts := names.
	layout := SpBoxLayout newLeftToRight.
	names do: [:name | | b |
		b := self newButton.
		b label: name; help: ''Invoke the restart '' , name; action: [self chooseRestart: name].
		layout add: b expand: false].
	restartsBar layout: layout'.
cm value: replp value: 'evaluating' value: 'chooseRestart: aName
	(#(''abort'' ''continue'') includes: aName)
		ifTrue: [self inputText: ''('' , aName , '')''. self submit]
		ifFalse: [
			buffer := ''('' , aName , '' )''.
			bufferCursor := aName size + 2.
			self refresh.
			termView takeKeyboardFocus]'.
cm value: replp value: 'evaluating' value: 'interrupt
	"Stops the evaluation running: the session waits at a break (R-15)."
	busy ifTrue: [LispIde call: ''ide:ide-interrupt'' with: { session }]'.
cm value: replp value: 'evaluating' value: 'closeSession
	"a session handed to it is not the REPL''s to close"
	ownsSession == false ifTrue: [^ self].
	session ifNotNil: [LispIde call: ''ide:ide-close'' with: { session }. session := nil]'.

cm value: replp value: 'updating' value: 'queue: aBlock
	"Runs aBlock in the UI process: a session''s results come from another one."
	updates add: aBlock.
	self defer: [self flushUpdates]'.
cm value: replp value: 'updating' value: 'flushUpdates
	| pending |
	pending := updates copy.
	updates removeAll.
	pending do: [:each | each value]'.
cm value: replp value: 'updating' value: 'waitUntilIdle: milliseconds
	"For a test: waits for the evaluation to be answered, then shows it."
	(idle waitTimeoutMilliseconds: milliseconds) ifTrue: [^ false].
	self flushUpdates.
	^ true'.

cm value: replp value: 'history' value: 'historyBack
	history isEmpty ifTrue: [^ self].
	historyIndex := historyIndex - 1 max: 1.
	self inputText: (history at: historyIndex)'.
cm value: replp value: 'history' value: 'historyForward
	history isEmpty ifTrue: [^ self].
	historyIndex := historyIndex + 1.
	historyIndex > history size
		ifTrue: [historyIndex := history size + 1. self inputText: '''']
		ifFalse: [self inputText: (history at: historyIndex)]'.

"=== LispFilesPresenter: the files the image has loaded (R-41) =================="
cm value: files class value: 'opening' value: 'open
	^ self new open; yourself'.
cm value: files value: 'initialization' value: 'initializePresenters
	list := self newList.
	list display: [:entry | (entry at: 1) asFileReference basename , ''   '' , (entry at: 2)].
	list whenSelectionChangedDo: [:s | self showSource].
	source := self newCode.
	source withoutSyntaxHighlight; beNotEditable.
	runButton := self newButton.
	runButton label: ''Run in a new REPL''; action: [self runSelected].
	refreshButton := self newButton.
	refreshButton label: ''Refresh''; action: [self refresh].
	self refresh'.
cm value: files value: 'initialization' value: 'defaultLayout
	^ SpBoxLayout newTopToBottom
		add: (SpPanedLayout newTopToBottom positionOfSlider: 0.35; add: list; add: source; yourself);
		add: (SpBoxLayout newLeftToRight add: runButton expand: false; add: refreshButton expand: false; yourself) height: 34;
		yourself'.
cm value: files value: 'initialization' value: 'initializeWindow: aWindowPresenter
	aWindowPresenter title: ''cog-lisp: loaded files''; initialExtent: 700 @ 520'.
cm value: files value: 'accessing' value: 'items
	^ list items'.
cm value: files value: 'accessing' value: 'list
	^ list'.
cm value: files value: 'accessing' value: 'source
	^ source'.
cm value: files value: 'actions' value: 'refresh
	"The files, as ide-loaded-files answers them: each (path . library), shown as
	 its name, then its library or its folder."
	| answer entries |
	answer := LispIde call: ''ide:ide-loaded-files'' with: #().
	entries := OrderedCollection new.
	[answer isKindOf: LispCons] whileTrue: [| e lib |
		e := answer car.
		lib := e cdr.
		entries add: { e car. (lib == false ifTrue: [e car asFileReference parent fullName] ifFalse: [''library '' , lib name asString]) }.
		answer := answer cdr].
	list items: entries asArray'.
cm value: files value: 'actions' value: 'showSource
	| entry |
	entry := list selectedItem.
	source text: (entry ifNil: [''''] ifNotNil: [[(entry at: 1) asFileReference contents] on: Error do: [:e | ''(the file cannot be read: '' , e messageText , '')'']])'.
cm value: files value: 'actions' value: 'runSelected
	| entry p |
	entry := list selectedItem.
	entry ifNil: [^ self].
	p := LispReplPresenter new.
	p open.
	p inputText: ''(load '' , (LispPrinter writeString: (entry at: 1)) , '')''.
	p submit.
	^ p'.

"=== LispStyler: LISP source, styled from its tokens (R-6), problems underlined (R-10) ==="
cm value: styler value: 'styling' value: 'privateStyle: aText
	"The text styled from editor-services'' tokens: comments, strings, characters,
	 numbers, quotes, keywords (special forms and macros), parentheses by depth;
	 then the page''s problems underlined, an error in red too."
	| tokens |
	aText ifEmpty: [^ self].
	charAttr := Array new: aText size withAll: (self attributesFor: #default).
	tokens := [LispIde call: ''editor-services:editor-tokens'' with: { aText asString }] on: Error do: [:e | nil].
	[tokens isKindOf: LispCons] whileTrue: [| t |
		t := tokens car.
		self addStyle: (self styleFor: t) from: (t at: 2) + 1 to: (t at: 3).
		tokens := tokens cdr].
	page ifNotNil: [:pg | pg problems do: [:p | | from to extra |
		from := (p at: 2) + 1.
		to := (p at: 3) min: aText size.
		extra := (p at: 1) name = ''error''
			ifTrue: [{ TextEmphasis underlined. TextColor color: self class errorColor }]
			ifFalse: [{ TextEmphasis underlined }].
		from to: to do: [:i | charAttr at: i put: (charAttr at: i) , extra]]].
	^ aText runs: (RunArray newFrom: charAttr)'.
cm value: styler value: 'styling' value: 'page: aPage
	"The page whose problems are underlined."
	page := aPage'.
cm value: styler value: 'styling' value: 'styleFor: aToken
	| kind |
	kind := (aToken at: 1) name asString.
	kind = ''comment'' ifTrue: [^ #lispComment].
	kind = ''string'' ifTrue: [^ #lispString].
	kind = ''character'' ifTrue: [^ #lispCharacter].
	kind = ''number'' ifTrue: [^ #lispNumber].
	kind = ''quote'' ifTrue: [^ #lispQuote].
	kind = ''keyword'' ifTrue: [^ #lispKeyword].
	(kind = ''open'' or: [kind = ''close''])
		ifTrue: [^ #(#lispParen1 #lispParen2 #lispParen3) at: ((aToken at: 4) \\ 3) + 1].
	^ #lispDefault'.
cm value: styler value: 'styling' value: 'attributesFor: aSymbol
	"cog-lisp''s own colors (VS Code''s Dark+ or Light+, by the theme), not Pharo''s
	 Smalltalk styles, which are hard to read on LISP; any other style is Pharo''s."
	palette ifNil: [palette := self class paletteForDark: self class isDarkTheme].
	^ palette at: aSymbol ifAbsent: [super attributesFor: aSymbol]'.
cm value: styler class value: 'palette' value: 'isDarkTheme
	^ [Smalltalk ui theme backgroundColor luminance < 0.5] on: Error do: [:e | true]'.
cm value: styler class value: 'palette' value: 'errorColor
	^ Color fromHexString: ''F14C4C'''.
cm value: styler class value: 'palette' value: 'paletteForDark: dark
	"style -> text attributes: a color, and italic for comments"
	| colors d |
	colors := dark
		ifTrue: [#(#lispDefault ''D4D4D4'' #lispComment ''6A9955'' #lispString ''CE9178''
			#lispCharacter ''D7BA7D'' #lispNumber ''B5CEA8'' #lispQuote ''4EC9B0''
			#lispKeyword ''569CD6'' #lispParen1 ''FFD700'' #lispParen2 ''DA70D6'' #lispParen3 ''179FFF'')]
		ifFalse: [#(#lispDefault ''000000'' #lispComment ''008000'' #lispString ''A31515''
			#lispCharacter ''795E26'' #lispNumber ''098658'' #lispQuote ''267F99''
			#lispKeyword ''0000FF'' #lispParen1 ''0431FA'' #lispParen2 ''319331'' #lispParen3 ''7B3814'')].
	d := Dictionary new.
	colors pairsDo: [:style :hex | | attrs |
		attrs := OrderedCollection with: (TextColor color: (Color fromHexString: hex)).
		style = #lispComment ifTrue: [attrs add: TextEmphasis italic].
		d at: style put: attrs asArray].
	^ d'.
cm value: styler class value: 'installing' value: 'installOn: aCodePresenter
	^ self installOn: aCodePresenter for: nil'.
cm value: styler class value: 'installing' value: 'installOn: aCodePresenter for: aPage
	"Styles aCodePresenter''s text as LISP, once its widget is built, underlining
	 aPage''s problems (if a page is given)."
	aCodePresenter withSyntaxHighlight.
	aCodePresenter whenBuiltDo: [:ann | self installInWidget: ann widget for: aPage].
	aCodePresenter withAdapterDo: [:a | a widget ifNotNil: [:w | self installInWidget: w for: aPage]]'.
cm value: styler class value: 'installing' value: 'installInWidget: aWidget for: aPage
	[| decorator |
	 decorator := aWidget textArea shoutStyler.
	 decorator styler: (self new view: decorator; page: aPage; yourself).
	 decorator refreshStyling] on: Error do: [:e | nil]'.

"=== LispEditorPage: one file, open in the editor (R-5 to R-11, R-44) ========="
cm value: epage value: 'initialization' value: 'initializePresenters
	code := self newCode.
	"not wrapped: a wrapped Rubric pane can recompose forever as its scroll bar comes and goes"
	code beNotWrapWord.
	"Pharo''s own Do it, Print it and Inspect it evaluate Smalltalk: replaced by the
	 page''s actions, which are its menu too (Spec refuses contextMenu: with actions)"
	code overrideContextMenu: true.
	problems := #().
	LispStyler installOn: code for: self.
	"the output pane is a REPL on the file''s session (R-44), made at its first evaluation"
	repl := self instantiate: LispReplPresenter.
	repl sessionSource: [self session].
	"the problems the text would meet (R-10), beside it"
	problemsList := self newList.
	problemsList display: [:p | self describeProblem: p].
	problemsList whenActivatedDo: [:selection | selection selectedItem ifNotNil: [:p | self selectFrom: (p at: 2) to: (p at: 3)]].
	bottom := self newNotebook.
	bottom addPage: (SpNotebookPage title: ''REPL'' provider: [repl]).
	bottom addPage: (SpNotebookPage title: ''Problems'' provider: [problemsList]).
	checkGeneration := 0.
	code whenSelectionChangedDo: [:selection | self describeAtCursor].
	self bindKeys'.
cm value: epage value: 'initialization' value: 'defaultLayout
	^ SpPanedLayout newTopToBottom
		positionOfSlider: 0.62;
		add: code;
		add: bottom;
		yourself'.
cm value: epage value: 'initialization' value: 'keys
	"The page''s actions (R-11): name, menu label (nil: a key only), key (a letter,
	 #space, #enter, or nil: none), shifted?, action."
	^ {
		{ ''run''. ''Run''. $r. false. [self run] }.
		{ ''do-it''. ''Do it''. $d. false. [self doIt] }.
		{ ''print-it''. ''Print it''. $p. false. [self printIt] }.
		{ ''load-file''. ''Load file''. $l. false. [self loadFile] }.
		{ ''interrupt''. ''Interrupt''. nil. false. [self interrupt] }.
		{ ''save''. ''Save''. $s. false. [self save] }.
		{ ''format''. ''Format''. $f. true. [self format] }.
		{ ''complete''. ''Complete''. #space. false. [self complete] }.
		{ ''go-to-definition''. ''Go to definition''. $b. false. [self goToDefinition] }.
		{ ''reload''. ''Reload from disk''. nil. false. [self reloadFromDisk] }.
		{ ''newline''. nil. #enter. false. [self newlineAndIndent] }.
		"keys of Rubric''s own: Ctrl+X, Ctrl+C, Ctrl+V"
		{ ''cut''. ''Cut''. nil. false. [self withEditor: [:ed | ed cut]] }.
		{ ''copy''. ''Copy''. nil. false. [self withEditor: [:ed | ed copySelection]] }.
		{ ''paste''. ''Paste''. nil. false. [self withEditor: [:ed | ed paste]] } }'.
cm value: epage value: 'initialization' value: 'withEditor: aBlock
	code withAdapterDo: [:a | aBlock value: a widget textArea editor]'.
cm value: epage value: 'initialization' value: 'bindKeys
	"Each action in the pane''s menu with its key, a real key (a KeyboardKey); the same
	 key typed (a Character, as a script sends it) is bound too, shortcut only and
	 under its own name, or Spec refuses it. An action with no label is a key only."
	self keys do: [:each | | name label key shifted action real typed |
		name := each at: 1. label := each at: 2. key := each at: 3. shifted := each at: 4. action := each at: 5.
		key
			ifNil: [code addActionWith: [:a | a name: label; action: action]]
			ifNotNil: [
				key == #space
					ifTrue: [real := KeyboardKey space asKeyCombination actionModifier. typed := Character space actionModifier]
					ifFalse: [key == #enter
						ifTrue: [real := KeyboardKey enter asKeyCombination. typed := Character cr asKeyCombination]
						ifFalse: [
							real := (KeyboardKey named: key asUppercase asString) asKeyCombination.
							typed := key.
							"shift first: actionModifier answers Ctrl or Cmd, which takes no shift"
							shifted ifTrue: [real := KMModifier shift + real. typed := typed shift].
							real := real actionModifier.
							typed := typed actionModifier]].
				label
					ifNil: [code addActionWith: [:a | a name: name; shortcutKey: real; beShortcutOnly; action: action]]
					ifNotNil: [code addActionWith: [:a | a name: label; shortcutKey: real; action: action]].
				code addActionWith: [:a | a name: name , ''-typed''; shortcutKey: typed; beShortcutOnly; action: action]]]'.
cm value: epage value: 'accessing' value: 'editor: anEditor
	editor := anEditor'.
cm value: epage value: 'accessing' value: 'path
	^ path'.
cm value: epage value: 'accessing' value: 'name
	^ path asFileReference basename'.
cm value: epage value: 'accessing' value: 'code
	^ code'.
cm value: epage value: 'accessing' value: 'repl
	"The REPL below the text, on the file''s session (R-44)."
	^ repl'.
cm value: epage value: 'accessing' value: 'bottom
	"The notebook below the text: the REPL and the problems."
	^ bottom'.
cm value: epage value: 'accessing' value: 'text
	^ code text asString'.
cm value: epage value: 'accessing' value: 'text: aString
	code text: aString'.
cm value: epage value: 'accessing' value: 'isDirty
	"Edited since it was opened or saved?"
	^ self text ~= savedText'.
cm value: epage value: 'accessing' value: 'hasDiskConflict
	"Changed on disk while it had unsaved edits, and not yet chosen between (R-8)?"
	^ diskText notNil'.
cm value: epage value: 'accessing' value: 'title
	^ self name , (self isDirty ifTrue: ['' *''] ifFalse: ['''']) ,
		(diskText ifNil: [''''] ifNotNil: [:t | '' (changed on disk)''])'.
cm value: epage value: 'accessing' value: 'cursorOffset
	"Where the cursor (or the selection) starts: a character offset from 0."
	^ ((code selectionInterval ifNil: [1 to: 0]) first - 1) max: 0'.
cm value: epage value: 'accessing' value: 'listFrom: aList
	"A LISP list as an Array."
	| items l |
	items := OrderedCollection new.
	l := aList.
	[l isKindOf: LispCons] whileTrue: [items add: l car. l := l cdr].
	^ items asArray'.
cm value: epage value: 'accessing' value: 'oneLine: aString
	"The first two lines of aString, on one line: a documentation''s call and its first sentence."
	| lines |
	lines := (aString lines reject: [:l | l trimBoth isEmpty]) asArray.
	lines isEmpty ifTrue: [^ ''''].
	^ lines size = 1 ifTrue: [lines first] ifFalse: [lines first , ''  '' , (lines at: 2)]'.

cm value: epage value: 'editing' value: 'placeCursor: offset
	"The cursor before the character at offset (from 0)."
	code selectionInterval: (offset + 1 to: offset)'.
cm value: epage value: 'editing' value: 'selectFrom: start to: end
	"The text from start to before end (offsets from 0) selected, and brought into view."
	code selectionInterval: (start + 1 to: end).
	[code withAdapterDo: [:a | a widget textArea scrollSelectionIntoView: nil]] on: Error do: [:e | nil]'.
cm value: epage value: 'editing' value: 'replaceFrom: start to: end with: aString
	"The text from start to before end (offsets from 0) replaced by aString, as typing
	 it would (Rubric''s editor, so Undo undoes it), the cursor after it."
	| done text |
	done := false.
	code selectionInterval: (start + 1 to: end).
	[code withAdapterDo: [:a | a widget textArea editor replaceSelectionWith: aString. done := true]]
		on: Error do: [:e | done := false].
	done ifFalse: [
		text := self text.
		code text: (text copyFrom: 1 to: start) , aString , (text copyFrom: end + 1 to: text size)].
	self placeCursor: start + aString size'.
cm value: epage value: 'editing' value: 'newlineAndIndent
	"Enter (R-7): a new line, indented one level deeper than the line of the list
	 still open there, in the file''s own indentation (ide-indent)."
	| sel start end indent |
	sel := code selectionInterval ifNil: [1 to: 0].
	start := (sel first - 1) max: 0.
	end := sel isEmpty ifTrue: [start] ifFalse: [sel last].
	indent := [LispIde call: ''ide:ide-indent'' with: { self text. start }] on: Error do: [:e | ''''].
	self replaceFrom: start to: end with: (String with: Character lf) , indent'.

cm value: epage value: 'file' value: 'openPath: aPath
	"Reads the file (ide-read-file): its text with line feeds, its line ending kept for saving."
	| answer |
	path := aPath.
	answer := LispIde call: ''ide:ide-read-file'' with: { aPath }.
	savedText := answer car.
	ending := answer cdr.
	code text: savedText.
	code whenTextChangedDo: [
		editor ifNotNil: [:e | e pageChanged: self].
		self scheduleCheck].
	self scheduleCheck'.
cm value: epage value: 'file' value: 'save
	"Writes the file in its own line endings (R-8); saving does not evaluate. Chooses
	 these edits over the file''s, if it changed on disk meanwhile."
	| text |
	text := self text.
	LispIde call: ''ide:ide-save-file'' with: { path. text. LispIde symbol: ''ending''. ending }.
	savedText := text.
	diskText := nil.
	self report: ''saved '' , self name.
	editor ifNotNil: [:e | e pageChanged: self]'.
cm value: epage value: 'file' value: 'format
	"The whole text laid out by format-source, the formatter VS Code uses, indented
	 as the file indents (ide-format)."
	| formatted |
	formatted := [LispIde call: ''ide:ide-format'' with: { self text }]
		on: Error do: [:e | self report: ''format: '' , (LispError describe: e). ^ self].
	code text: formatted'.
cm value: epage value: 'file' value: 'checkDisk
	"The file as it is on disk (R-8): taken when the page has no unsaved edits; else
	 kept aside and reported, until Save (these edits) or Reload from disk (the file''s)."
	| answer disk |
	path asFileReference exists ifFalse: [^ self].
	answer := [LispIde call: ''ide:ide-read-file'' with: { path }] on: Error do: [:e | nil].
	answer ifNil: [^ self].
	disk := answer car.
	disk = savedText ifTrue: [
		diskText ifNotNil: [diskText := nil. editor ifNotNil: [:e | e pageChanged: self]].
		^ self].
	self isDirty
		ifFalse: [
			savedText := disk.
			ending := answer cdr.
			diskText := nil.
			code text: disk.
			self report: ''reloaded '' , self name , '': it changed on disk'']
		ifTrue: [disk = diskText ifFalse: [
			diskText := disk.
			self report: self name , '' changed on disk while it has unsaved edits here: Save keeps these, Reload from disk takes the file''''s'']].
	editor ifNotNil: [:e | e pageChanged: self]'.
cm value: epage value: 'file' value: 'reloadFromDisk
	"The file as it is on disk, in place of the page''s text and its unsaved edits."
	| answer |
	answer := LispIde call: ''ide:ide-read-file'' with: { path }.
	savedText := answer car.
	ending := answer cdr.
	diskText := nil.
	code text: savedText.
	self report: ''reloaded '' , self name.
	editor ifNotNil: [:e | e pageChanged: self]'.

cm value: epage value: 'problems' value: 'problems
	"The problems of the last check (R-10): #(severity start end message) each."
	^ problems ifNil: [#()]'.
cm value: epage value: 'problems' value: 'scheduleCheck
	"Checks the text once it has rested for 0.4 s, in a process of its own; a check of
	 a text that has changed since is dropped."
	| gen text |
	checkGeneration := checkGeneration + 1.
	gen := checkGeneration.
	text := self text.
	[(Delay forMilliseconds: 400) wait.
	 gen = checkGeneration ifTrue: [self check: text generation: gen]]
		forkAt: Processor userBackgroundPriority named: ''cog-lisp editor check'''.
cm value: epage value: 'problems' value: 'checkNow
	"Checks the text now (a test''s way)."
	checkGeneration := checkGeneration + 1.
	self check: self text generation: checkGeneration'.
cm value: epage value: 'problems' value: 'check: text generation: gen
	| found |
	found := [LispIde call: ''ide:ide-check'' with: { path. text }] on: Error do: [:e | nil].
	(found isNil or: [gen ~= checkGeneration]) ifTrue: [^ self].
	LispIde onUi: [self showProblems: (self listFrom: found)]'.
cm value: epage value: 'problems' value: 'showProblems: anArray
	problems := anArray.
	problemsList items: anArray.
	bottom pages size >= 2 ifTrue: [
		(bottom pages at: 2) title: (anArray isEmpty
			ifTrue: [''Problems'']
			ifFalse: [''Problems ('' , anArray size printString , '')''])].
	[code withAdapterDo: [:a | a widget textArea shoutStyler refreshStyling]] on: Error do: [:e | nil]'.
cm value: epage value: 'problems' value: 'describeProblem: aProblem
	| line |
	line := ((self text copyFrom: 1 to: ((aProblem at: 2) min: self text size)) occurrencesOf: Character lf) + 1.
	^ ''line '' , line printString , '': '' , (aProblem at: 1) name , '': '' , (aProblem at: 4)'.

cm value: epage value: 'knowing' value: 'describeAtCursor
	"The documentation of the name at the cursor, in the status line (R-10)."
	| doc |
	editor ifNil: [^ self].
	path ifNil: [^ self].
	doc := [LispIde call: ''ide:ide-describe'' with: { path. self text. self cursorOffset }] on: Error do: [:e | false].
	doc == false ifTrue: [^ self].
	self report: (self oneLine: doc)'.
cm value: epage value: 'knowing' value: 'completionAnswer
	^ LispIde call: ''ide:ide-complete'' with: { path. self text. self cursorOffset }'.
cm value: epage value: 'knowing' value: 'completions
	"The names that complete the one at the cursor (R-10)."
	| answer |
	answer := self completionAnswer.
	answer == false ifTrue: [^ #()].
	^ (self listFrom: answer cdr cdr car) collect: [:c | c at: 1]'.
cm value: epage value: 'knowing' value: 'complete
	"Ctrl+Space: the name at the cursor completed; with several, a choice of them."
	| answer labels start end |
	answer := self completionAnswer.
	answer == false ifTrue: [^ self report: ''nothing to complete here''].
	start := answer car.
	end := answer cdr car.
	labels := (self listFrom: answer cdr cdr car) collect: [:c | c at: 1].
	labels isEmpty ifTrue: [^ self report: ''no name starts so''].
	labels size = 1 ifTrue: [^ self replaceFrom: start to: end with: labels first].
	self showChoices: labels then: [:i | self replaceFrom: start to: end with: (labels at: i)]'.
cm value: epage value: 'knowing' value: 'goToDefinition
	"Ctrl+B: the definition of the name at the cursor, opened at its place; with
	 several, a choice of them; a built-in with no file, its documentation."
	| defs |
	editor ifNotNil: [:e | e indexProject].
	defs := self listFrom: (LispIde call: ''ide:ide-definitions'' with: { path. self text. self cursorOffset }).
	defs isEmpty ifTrue: [| doc |
		doc := [LispIde call: ''ide:ide-describe'' with: { path. self text. self cursorOffset }] on: Error do: [:e | false].
		^ self report: (doc == false
			ifTrue: [''no definition found'']
			ifFalse: [''defined in the image, with no file here: '' , (self oneLine: doc)])].
	defs size = 1 ifTrue: [^ editor openDefinition: defs first].
	self showChoices: (defs collect: [:d | (d at: 1) , ''  ('' , (d at: 2) asFileReference basename , '')''])
		then: [:i | editor openDefinition: (defs at: i)]'.
cm value: epage value: 'knowing' value: 'showChoices: labels then: aBlock
	"A list of labels below the text; choosing one (Enter, a double click) gives
	 aBlock its index."
	| list pop |
	list := self newList.
	list items: labels.
	list whenActivatedDo: [:selection | selection selectedItem ifNotNil: [:label | self choose: label]].
	choices := { labels. aBlock. nil }.
	pop := [self newPopover] on: Error do: [:e | nil].
	pop ifNotNil: [
		[pop relativeTo: code; presenter: list; bePositionBottom; popup.
		 choices at: 3 put: pop.
		 list takeKeyboardFocus] on: Error do: [:e | nil]]'.
cm value: epage value: 'knowing' value: 'choices
	"The labels offered by the last choice, or #()."
	^ choices ifNil: [#()] ifNotNil: [:c | c first]'.
cm value: epage value: 'knowing' value: 'choose: aLabel
	| c i |
	c := choices.
	c ifNil: [^ self].
	i := c first indexOf: aLabel.
	i = 0 ifTrue: [^ self].
	choices := nil.
	(c at: 3) ifNotNil: [:pop | [pop dismiss] on: Error do: [:e | nil]].
	(c at: 2) value: i'.
cm value: epage value: 'evaluating' value: 'session
	"The session that evaluates as part of this file (R-9)."
	^ LispIde call: ''ide:ide-file-session'' with: { path }'.
cm value: epage value: 'evaluating' value: 'formInterval
	"The selection, or else the top-level form at the cursor: an Interval in the text, or nil."
	| sel form |
	sel := code selectionInterval.
	(sel notNil and: [sel notEmpty]) ifTrue: [^ sel].
	form := LispIde call: ''ide:ide-form-at'' with: { self text. ((code cursorPositionIndex ifNil: [1]) - 1) max: 0 }.
	form == false ifTrue: [^ nil].
	^ (form car + 1) to: form cdr'.
cm value: epage value: 'evaluating' value: 'evaluate: aString showing: shown then: aBlock
	"Evaluates aString as part of the file, in the page''s REPL (R-44): shown after its
	 prompt, its output and values there as they come; then aBlock (if any) is
	 given the result. One evaluation at a time."
	repl isBusy ifTrue: [^ self report: ''busy: an evaluation is running (Interrupt stops it)''].
	repl evaluate: aString showing: shown then: aBlock'.
cm value: epage value: 'evaluating' value: 'interrupt
	"Stops the evaluation running: the REPL shows its break and restarts (R-15)."
	repl isBusy
		ifTrue: [repl interrupt]
		ifFalse: [self report: ''nothing to interrupt'']'.
cm value: epage value: 'evaluating' value: 'isBusy
	^ repl isBusy'.
cm value: epage value: 'evaluating' value: 'waitUntilIdle: milliseconds
	"For a test: waits for the evaluation to finish and be shown. False if it is still running."
	repl isBusy ifFalse: [^ true].
	^ repl waitUntilIdle: milliseconds'.
cm value: epage value: 'evaluating' value: 'run
	"Ctrl+R: the file as saved, run as a program in a new REPL window (R-43), where it
	 reads what is typed. Answers that window''s presenter."
	| name |
	name := path asFileReference basename.
	self report: (self isDirty
		ifTrue: [''running '' , name , '' as saved: its unsaved edits are not in it'']
		ifFalse: [''running '' , name]).
	^ editor ifNotNil: [:e | e runFile: path]'.
cm value: epage value: 'evaluating' value: 'doIt
	"Ctrl+D: the selection or the form at the cursor, evaluated as part of the file;
	 its values reported (R-9)."
	| interval |
	interval := self formInterval.
	interval ifNil: [^ self].
	self evaluate: (self text copyFrom: interval first to: interval last)
		showing: (self text copyFrom: interval first to: interval last)
		then: nil'.
cm value: epage value: 'evaluating' value: 'printIt
	"Ctrl+P: as Do it, and the value written after the form as ;; => value (R-9)."
	| interval |
	interval := self formInterval.
	interval ifNil: [^ self].
	self evaluate: (self text copyFrom: interval first to: interval last)
		showing: (self text copyFrom: interval first to: interval last)
		then: [:r | (r at: 1) name = ''done'' ifTrue: [| values written |
			values := OrderedCollection new.
			(r at: 3) do: [:w | values add: w].
			written := values isEmpty ifTrue: [''(no value)''] ifFalse: [values last].
			"the code pane is changed in the UI process: a result can come from another"
			LispIde onUi: [| text |
				text := self text.
				code text: (text copyFrom: 1 to: interval last) , String lf , '';; => '' , written ,
					(text copyFrom: interval last + 1 to: text size).
				code selectionInterval: (interval last + 9 + written size to: interval last + 8 + written size)]]]'.
cm value: epage value: 'evaluating' value: 'loadFile
	"Ctrl+L: the whole text, as the file holds it now, evaluated as part of the file."
	self evaluate: self text showing: ''; load '' , path asFileReference basename then: nil'.
cm value: epage value: 'reporting' value: 'report: aString
	editor ifNotNil: [:e | e report: aString]'.

"=== LispEditorPresenter: the editor window (R-5 to R-11) ===================="
cm value: editorp class value: 'opening' value: 'open
	"An editor on the project (ide-project), else the cog-lisp folder."
	^ self new open; yourself'.
cm value: editorp class value: 'opening' value: 'openOn: aFolder
	^ self new folder: aFolder; open; yourself'.
cm value: editorp value: 'initialization' value: 'initializePresenters
	tree := self newTree.
	tree display: [:ref | ref basename].
	tree children: [:ref | self childrenOf: ref].
	tree whenActivatedDo: [:selection | selection selectedItem ifNotNil: [:ref | ref isFile ifTrue: [self openFile: ref fullName]]].
	notebook := self newNotebook.
	toolbar := self newToolbar.
	self toolbarItems do: [:each | | b |
		b := SpToolbarButtonPresenter new.
		b label: (each at: 1); help: (each at: 2); action: (each at: 4).
		[b icon: (self iconNamed: (each at: 3))] on: Error do: [:e | nil].
		toolbar addItem: b].
	status := self newLabel.
	pages := OrderedCollection new.
	tabs := IdentityDictionary new.
	self folder: (self defaultFolder)'.
cm value: editorp value: 'initialization' value: 'toolbarItems
	"The toolbar (R-42): label, help, icon, action on the tab chosen."
	^ {
		{ ''Run''. ''Run the file, as saved, as a program in a new REPL window (Ctrl+R)''. #smallDoIt. [self withPage: [:p | p run]] }.
		{ ''Load''. ''Evaluate the whole text as part of the file, in its REPL below (Ctrl+L)''. #smallLoadProject. [self withPage: [:p | p loadFile]] }.
		{ ''Save''. ''Save the file, in its own line endings (Ctrl+S)''. #smallSave. [self withPage: [:p | p save]] }.
		{ ''Format''. ''Lay the text out as format-source does (Ctrl+Shift+F)''. #smallJustified. [self withPage: [:p | p format]] }.
		{ ''Interrupt''. ''Stop the evaluation running in the file''''s REPL''. #stop. [self withPage: [:p | p interrupt]] } }'.
cm value: editorp value: 'initialization' value: 'defaultLayout
	^ SpBoxLayout newTopToBottom
		add: toolbar expand: false;
		add: (SpPanedLayout newLeftToRight
			positionOfSlider: 0.22;
			add: tree;
			add: notebook;
			yourself);
		add: status expand: false;
		yourself'.
cm value: editorp value: 'initialization' value: 'initializeWindow: aWindowPresenter
	aWindowPresenter title: ''cog-lisp editor''; initialExtent: 1100 @ 760.
	"while the window is open, its files are compared with the disk (R-8)"
	[aWindowPresenter whenOpenedDo: [self startWatching]] on: Error do: [:e | nil].
	[aWindowPresenter whenClosedDo: [watching := false]] on: Error do: [:e | nil]'.
cm value: editorp value: 'files on disk' value: 'startWatching
	"Every two seconds, the open files compared with the disk, in the UI process."
	watching == true ifTrue: [^ self].
	watching := true.
	[[watching] whileTrue: [
		(Delay forMilliseconds: 2000) wait.
		watching ifTrue: [[LispIde onUi: [self checkFilesOnDisk]] on: Error do: [:e | nil]]]]
		forkAt: Processor userBackgroundPriority named: ''cog-lisp editor: files on disk'''.
cm value: editorp value: 'files on disk' value: 'checkFilesOnDisk
	"Each open file compared with the disk: reloaded, or its change reported (R-8)."
	self openPages do: [:p | p checkDisk]'.
cm value: editorp value: 'files on disk' value: 'isWatching
	^ watching == true'.
cm value: editorp value: 'accessing' value: 'toolbar
	^ toolbar'.
cm value: editorp value: 'accessing' value: 'lastRun
	"The REPL window the last Run opened."
	^ lastRun'.
cm value: editorp value: 'files' value: 'defaultFolder
	| project |
	project := LispIde call: ''ide:ide-project'' with: #().
	^ project == false
		ifTrue: [(OSEnvironment current at: ''COGLISP_HOME'' ifAbsent: [FileSystem workingDirectory fullName]) asFileReference fullName]
		ifFalse: [project]'.
cm value: editorp value: 'files' value: 'folder: aPath
	"The project folder whose files the tree shows (R-5)."
	folder := aPath asFileReference.
	tree roots: (self childrenOf: folder)'.
cm value: editorp value: 'files' value: 'childrenOf: aReference
	"The folders holding .lisp files, then the .lisp files, each sorted."
	| files dirs |
	aReference isDirectory ifFalse: [^ #()].
	dirs := (aReference directories reject: [:d | #(''pharo'' ''node_modules'' ''.git'' ''dist'' ''coverage'' ''.vscode-test'') includes: d basename])
		select: [:d | self holdsLisp: d].
	files := aReference files select: [:f | f extension = ''lisp''].
	^ ((dirs asSortedCollection: [:a :b | a basename <= b basename]) asArray) ,
		((files asSortedCollection: [:a :b | a basename <= b basename]) asArray)'.
cm value: editorp value: 'files' value: 'holdsLisp: aDirectory
	^ (LispIde call: ''ide:ide-project-files'' with: { aDirectory fullName }) isKindOf: LispCons'.
cm value: editorp value: 'files' value: 'pages
	^ pages'.
cm value: editorp value: 'files' value: 'pageFor: aPath
	"The page of a tab still open on aPath."
	^ self openPages detect: [:p | p path asFileReference = aPath asFileReference] ifNone: [nil]'.
cm value: editorp value: 'files' value: 'openPages
	^ notebook pages collect: [:tab | tabs at: tab] thenSelect: [:p | p notNil]'.
cm value: editorp value: 'files' value: 'selectedPage
	"The page of the tab chosen, or nil."
	^ notebook selectedPage ifNotNil: [:tab | tabs at: tab ifAbsent: [nil]]'.
cm value: editorp value: 'files' value: 'withPage: aBlock
	self selectedPage
		ifNil: [self report: ''no file is open: choose one in the tree'']
		ifNotNil: [:p | aBlock value: p]'.
cm value: editorp value: 'definitions' value: 'indexProject
	"The project''s files indexed for go to definition and completion, once."
	folder ifNotNil: [:f | [LispIde call: ''ide:ide-index-project!!'' with: { f fullName }] on: Error do: [:e | nil]]'.
cm value: editorp value: 'definitions' value: 'openDefinition: aDefinition
	"Its file in a tab, the definition selected (R-10). The definition is found by its
	 text, which the tab holds with line feeds whatever the file has; else by its place."
	| page source at |
	page := self openFile: (aDefinition at: 2).
	source := (aDefinition at: 6) copyReplaceAll: (String with: Character cr with: Character lf) with: (String with: Character lf).
	at := page text indexOfSubCollection: source.
	at > 0
		ifTrue: [page selectFrom: at - 1 to: at - 1 + source size]
		ifFalse: [page selectFrom: (aDefinition at: 3) to: (aDefinition at: 4)].
	^ page'.
cm value: editorp value: 'running' value: 'runFile: aPath
	"A new REPL window running the file at aPath as a program, from a clean start (R-43)."
	| p |
	p := LispReplPresenter new.
	p open.
	[p window title: ''cog-lisp: '' , aPath asFileReference basename] on: Error do: [:e | nil].
	p evaluate: ''(load '' , (LispPrinter writeString: aPath) , '')''.
	lastRun := p.
	^ p'.
cm value: editorp value: 'files' value: 'openFile: aPath
	"The file in a tab of its own, or its tab if it has one (R-5). Answers its page."
	| page tab |
	(self pageFor: aPath) ifNotNil: [:p | self selectPage: p. ^ p].
	page := self instantiate: LispEditorPage.
	page editor: self.
	page openPath: aPath.
	pages add: page.
	tab := SpNotebookPage title: page title provider: [page].
	[tab beCloseable] on: Error do: [:e | nil].
	tabs at: tab put: page.
	notebook addPage: tab.
	self selectPage: page.
	^ page'.
cm value: editorp value: 'files' value: 'tabFor: aPage
	^ notebook pages detect: [:tab | (tabs at: tab ifAbsent: [nil]) == aPage] ifNone: [nil]'.
cm value: editorp value: 'files' value: 'selectPage: aPage
	(self tabFor: aPage) ifNotNil: [:tab | notebook selectPage: tab]'.
cm value: editorp value: 'files' value: 'pageChanged: aPage
	"Its title marks unsaved edits."
	(self tabFor: aPage) ifNotNil: [:tab | tab title: aPage title]'.
cm value: editorp value: 'reporting' value: 'statusText
	^ status label asString'.
cm value: editorp value: 'reporting' value: 'report: aString
	"The status line: what the last action did (R-42); evaluations show in the tab''s REPL."
	status label: aString'.

"the development image takes its requests when it starts in the GUI (R-37)"
SessionManager default registerUserClassNamed: #LispIde.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-IDE'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-IDE: ' , failures size printString].
