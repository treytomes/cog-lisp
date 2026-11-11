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
   LispReplPresenter  the REPL window (R-12 to R-16), on lib/ide.lisp's sessions
 ============================================================================"
| failures cm sess sinput sresult ide replp |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

sess := (Object << #LispSession) slots: { #name. #maker. #unit. #compiler. #process. #requests. #ready. #answers. #answered. #pending. #output. #input. #inputPort. #busy. #wrapper }; sharedVariables: { #Sessions }; package: 'CogLisp-IDE'; install.
sinput := (Object << #LispSessionInput) slots: { #lines. #ready. #closed }; package: 'CogLisp-IDE'; install.
sresult := (Object << #LispSessionResult) slots: { #status. #values. #output. #report. #restarts. #level }; package: 'CogLisp-IDE'; install.
ide := (Object << #LispIde) sharedVariables: { #Watcher }; package: 'CogLisp-IDE'; install.
replp := (SpPresenter << #LispReplPresenter) slots: { #session. #transcript. #input. #restartsBar. #interruptButton. #history. #historyIndex. #shown. #transcriptText. #updates. #idle. #busy. #level. #restarts }; package: 'CogLisp-IDE'; install.

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
	^ #((0 0 0) (128 0 0) (0 128 0) (128 128 0) (0 0 128) (128 0 128) (0 128 128) (192 192 192)
		(128 128 128) (255 0 0) (0 255 0) (255 255 0) (0 0 255) (255 0 255) (0 255 255) (255 255 255))
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
		yourself)) asArray'.
cm value: ide class value: 'world menu' value: 'menuCommandOn: aBuilder
	<worldMenu>
	(aBuilder item: #''cog-lisp: update the image from the checkout'')
		order: 0.6;
		help: ''Bring this image up to date with the source in the checkout, in place (specs/34-morphic-ide.md R-3)'';
		action: [self updateFromCheckout]'.

"=== LispReplPresenter: the REPL window (R-12 to R-16) ======================="
cm value: replp class value: 'opening' value: 'open
	"A new REPL window, on a session of its own."
	^ self new open'.
cm value: replp class value: 'world menu' value: 'menuCommandOn: aBuilder
	<worldMenu>
	(aBuilder item: #''cog-lisp REPL'')
		order: 0.5;
		help: ''A cog-lisp REPL, on a session of its own (specs/34-morphic-ide.md)'';
		action: [self open]'.
cm value: replp value: 'initialization' value: 'initializePresenters
	"a code pane: its font is monospace, with the box-drawing characters tables use"
	transcript := self newCode.
	transcript withoutSyntaxHighlight; withoutLineNumbers; beNotEditable.
	input := self newText.
	input placeholder: ''A form, then Enter. Up and Down: the history.''.
	input addShortcutWith: [:action | action shortcutKey: Character cr asKeyCombination; action: [self submit]].
	[input addShortcutWith: [:action | action shortcutKey: Character arrowUp asKeyCombination; action: [self historyBack]].
	 input addShortcutWith: [:action | action shortcutKey: Character arrowDown asKeyCombination; action: [self historyForward]]]
		on: Error do: [:e | nil].
	interruptButton := self newButton.
	interruptButton label: ''Interrupt''; help: ''Stop the evaluation running''; action: [self interrupt]; disable.
	restartsBar := self newPresenter.
	restartsBar layout: SpBoxLayout newLeftToRight.
	history := OrderedCollection new.
	historyIndex := 0.
	shown := 0.
	transcriptText := Text new.
	updates := OrderedCollection new.
	idle := Semaphore new.
	busy := false.
	level := 0.
	restarts := #().
	session := LispIde call: ''ide:ide-session'' with: {
		LispIde symbol: ''name''. ''REPL''.
		LispIde symbol: ''wrapper''. (LispIde evalString: ''(lambda (thunk) (console:with-console (list (quote colors) (quote truecolor) (quote unicode?) #t (quote terminal?) #t (quote interactive?) #f (quote width) 100) thunk))'') }'.
cm value: replp value: 'initialization' value: 'defaultLayout
	^ SpBoxLayout newTopToBottom
		add: transcript;
		add: restartsBar expand: false;
		add: (SpBoxLayout newLeftToRight add: input; add: interruptButton expand: false; yourself) height: 70;
		yourself'.
cm value: replp value: 'initialization' value: 'initializeWindow: aWindowPresenter
	aWindowPresenter
		title: ''cog-lisp REPL'';
		initialExtent: 760 @ 520.
	[aWindowPresenter whenClosedDo: [self closeSession]] on: Error do: [:e | nil]'.

cm value: replp value: 'accessing' value: 'session
	^ session'.
cm value: replp value: 'accessing' value: 'transcriptText
	"The transcript as shown: a Text, its output in the colors the program wrote."
	^ transcriptText'.
cm value: replp value: 'accessing' value: 'transcriptString
	^ transcriptText asString'.
cm value: replp value: 'accessing' value: 'inputText
	^ input text asString'.
cm value: replp value: 'accessing' value: 'inputText: aString
	input text: aString'.
cm value: replp value: 'accessing' value: 'restartNames
	"The restarts offered while the session waits at a break."
	^ restarts'.
cm value: replp value: 'accessing' value: 'isBusy
	^ busy'.
cm value: replp value: 'accessing' value: 'level
	^ level'.

cm value: replp value: 'transcript' value: 'append: aText
	transcriptText := transcriptText , aText.
	transcript text: transcriptText.
	[transcript cursorPositionIndex: transcriptText size + 1] on: Error do: [:e | nil]'.
cm value: replp value: 'transcript' value: 'append: aString color: aColor
	self append: (Text string: aString attributes: (aColor ifNil: [#()] ifNotNil: [{ TextColor color: aColor }]))'.
cm value: replp value: 'transcript' value: 'appendOutput
	"What the session wrote since it was last shown."
	| out |
	session ifNil: [^ self].
	out := session outputSince: shown.
	shown := shown + out size.
	out isEmpty ifFalse: [self append: (LispIde textFromTerminal: out)]'.
cm value: replp value: 'transcript' value: 'prompt
	^ level > 0 ifTrue: [level printString , ''> ''] ifFalse: [''> '']'.

cm value: replp value: 'evaluating' value: 'submit
	"What Enter does: evaluates the input when it holds whole forms, and otherwise
	 starts a new line in it (R-12). While an evaluation runs, the line is for the
	 program to read."
	| text |
	text := self inputText.
	busy ifTrue: [
		self append: text , String lf color: Color gray.
		LispIde call: ''ide:ide-type'' with: { session. text }.
		input text: ''''.
		^ self].
	text trimBoth isEmpty ifTrue: [^ self].
	(LispIde isComplete: text) ifFalse: [
		input text: text , String lf.
		[input cursorPositionIndex: text size + 2] on: Error do: [:e | nil].
		^ self].
	history addLast: text.
	historyIndex := history size + 1.
	input text: ''''.
	self evaluate: text'.
cm value: replp value: 'evaluating' value: 'evaluate: text
	"Shows text after the prompt, and evaluates it in the session; the window goes on
	 working while it runs. waitUntilIdle: waits for it."
	| first |
	self append: self prompt , text , String lf color: nil.
	busy := true.
	interruptButton enable.
	self showRestarts: #().
	first := LispIde call: ''ide:ide-eval'' with: { session. text. LispIde symbol: ''timeout''. 0 }.
	[| r |
	 r := first.
	 [(r at: 1) name = ''running''] whileTrue: [
		self queue: [self appendOutput].
		r := LispIde call: ''ide:ide-wait'' with: { session. 100 }].
	 self queue: [self show: r].
	 idle signal] forkAt: Processor userBackgroundPriority'.
cm value: replp value: 'evaluating' value: 'show: aResult
	"A result in the transcript: the values written, or the error and its restarts."
	| status |
	self appendOutput.
	status := (aResult at: 1) name asString.
	busy := false.
	interruptButton disable.
	level := aResult at: 7.
	status = ''done'' ifTrue: [
		(aResult at: 3) do: [:w | self append: w , String lf color: (Color r: 0.2 g: 0.4 b: 0.8)].
		self showRestarts: #()].
	status = ''aborted'' ifTrue: [
		self append: ''aborted'' , String lf color: Color gray.
		self showRestarts: #()].
	status = ''error'' ifTrue: [
		self append: ''error: '' , (aResult at: 5) , String lf color: Color red.
		self showRestarts: (aResult at: 6) asArray]'.
cm value: replp value: 'evaluating' value: 'showRestarts: names
	"The restarts as buttons (R-14): abort runs at once; one that takes values puts
	 (name ) in the input to be finished."
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
		ifTrue: [self evaluate: ''('' , aName , '')'']
		ifFalse: [
			input text: ''('' , aName , '' )''.
			[input cursorPositionIndex: aName size + 3] on: Error do: [:e | nil]]'.
cm value: replp value: 'evaluating' value: 'interrupt
	"Stops the evaluation running: the session waits at a break (R-15)."
	busy ifTrue: [LispIde call: ''ide:ide-interrupt'' with: { session }]'.
cm value: replp value: 'evaluating' value: 'closeSession
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
	input text: (history at: historyIndex)'.
cm value: replp value: 'history' value: 'historyForward
	history isEmpty ifTrue: [^ self].
	historyIndex := historyIndex + 1.
	historyIndex > history size
		ifTrue: [historyIndex := history size + 1. input text: '''']
		ifFalse: [input text: (history at: historyIndex)]'.

"the development image takes its requests when it starts in the GUI (R-37)"
SessionManager default registerUserClassNamed: #LispIde.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-IDE'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-IDE: ' , failures size printString].
