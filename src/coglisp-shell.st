"============================================================================
 cog-lisp : Phase 5 implementation  (package CogLisp-Shell)
 The REPL and the command-line entry point, per specs/phase-5-repl-runner.md.

 LOADER script. Must be filed in AFTER the reader, core, compiler and runtime
 packages.

 Classes:
   LispRepl          read-eval-print loop over any in/out/err streams
   LispShellCommand  the Clap command  PharoConsole.exe cog-lisp.image lisp ...
                     (lisp repl | lisp run <file>)

 Commands must never let an error reach Pharo's own reporting (the VM hangs),
 and must end with Smalltalk exit: n. See CLAUDE.md.
 ============================================================================"
| failures cm stdin repl shell |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

stdin := (Object << #LispStdin) slots: { #kind. #handle. #pending. #eof }; package: 'CogLisp-Shell'; install.
repl  := (Object << #LispRepl) slots: { #in. #out. #err. #compiler }; package: 'CogLisp-Shell'; install.
shell := (ClapApplication << #LispShellCommand) sharedVariables: { #BuildTime }; package: 'CogLisp-Shell'; install.

"=== LispStdin ============================================================
 A line reader over the process stdin that WAITS for input. Pharo's stdin never
 blocks: with nothing buffered, reads answer 0 bytes and atEnd answers true, the
 same as at real end of input (CLAUDE.md). So when no bytes are available this
 asks the OS what stdin is: a console never ends (the user types (exit)); a
 redirected file has ended; a pipe has ended once PeekNamedPipe fails because
 the writer closed it. Otherwise it sleeps briefly and polls again.
 A console is NOT read through Pharo's stdin at all: the VM never issues a
 console read, so typed keys are never echoed or delivered. It is read with
 ReadConsoleW, which waits for Enter while Windows handles echo and line
 editing. That blocks the VM until a line is entered, which is what a REPL
 waiting at its prompt wants.
 Bytes are decoded as UTF-8 one complete line at a time, so a partly received
 character is never decoded early."
cm value: stdin class value: 'win32' value: 'readConsole: h buffer: b size: n read: r control: c
	^ self ffiCall: #(int ReadConsoleW(void* h, void* b, uint32 n, void* r, void* c)) module: ''kernel32.dll'''.
cm value: stdin class value: 'instance creation' value: 'onConsoleHandle: aHandle
	"A reader over a specific console input handle (used by tests)."
	^ self basicNew initializeConsole: aHandle'.
cm value: stdin value: 'initialization' value: 'initializeConsole: aHandle
	pending := OrderedCollection new.
	eof := false.
	kind := #console.
	handle := aHandle'.
cm value: stdin value: 'private' value: 'readConsoleLine
	"Block until the user enters a line; queue it as UTF-8 bytes. A failed or
	 empty read means the console input has ended."
	| units count ok text |
	units := ByteArray new: 8192.
	count := ByteArray new: 4.
	ok := [self class readConsole: handle buffer: units size: 4096 read: count control: nil]
		on: Error do: [:e | 0].
	(ok = 0 or: [(count unsignedLongAt: 1) = 0]) ifTrue: [^ eof := true].
	text := self utf16: units count: (count unsignedLongAt: 1).
	pending addAll: text utf8Encoded'.
cm value: stdin value: 'private' value: 'utf16: bytes count: n
	"Decode n little-endian UTF-16 code units, joining surrogate pairs."
	| out i unit low |
	out := WriteStream on: (String new: n).
	i := 1.
	[i <= n] whileTrue: [
		unit := bytes unsignedShortAt: i * 2 - 1.
		((unit between: 16rD800 and: 16rDBFF) and: [i < n])
			ifTrue: [
				low := bytes unsignedShortAt: i * 2 + 1.
				out nextPut: (Character value: 16r10000 + ((unit - 16rD800) bitShift: 10) + (low - 16rDC00)).
				i := i + 2]
			ifFalse: [
				out nextPut: (Character value: unit).
				i := i + 1]].
	^ out contents'.
cm value: stdin class value: 'win32' value: 'getStdHandle: n
	^ self ffiCall: #(void* GetStdHandle(long n)) module: ''kernel32.dll'''.
cm value: stdin class value: 'win32' value: 'getFileType: h
	^ self ffiCall: #(uint32 GetFileType(void* h)) module: ''kernel32.dll'''.
cm value: stdin class value: 'win32' value: 'peekNamedPipe: h buffer: b size: s read: r available: a left: l
	^ self ffiCall: #(int PeekNamedPipe(void* h, void* b, uint32 s, void* r, void* a, void* l)) module: ''kernel32.dll'''.
cm value: stdin class value: 'instance creation' value: 'new
	^ self basicNew initialize'.
cm value: stdin value: 'initialization' value: 'initialize
	| type |
	pending := OrderedCollection new.
	eof := false.
	kind := #unknown.
	OSPlatform current isWindows ifFalse: [^ self].
	[handle := self class getStdHandle: -10.
	 type := self class getFileType: handle.
	 kind := type = 1 ifTrue: [#file] ifFalse: [
		type = 2 ifTrue: [#console] ifFalse: [
		type = 3 ifTrue: [#pipe] ifFalse: [#unknown]]]]
		on: Error do: [:e | kind := #unknown]'.
cm value: stdin value: 'accessing' value: 'kind
	^ kind'.
cm value: stdin value: 'private' value: 'noInputMeansEnd
	"Called when a read found no bytes. Answer whether input has really ended."
	kind = #console ifTrue: [^ false].
	kind = #pipe ifTrue: [
		^ [(self class peekNamedPipe: handle buffer: nil size: 0 read: nil available: (ByteArray new: 4) left: nil) = 0]
			on: Error do: [:e | true]].
	^ true'.
cm value: stdin value: 'private' value: 'waitForInput
	"Block until at least one byte is pending, or input has ended."
	| chunk |
	kind = #console ifTrue: [
		[pending isEmpty and: [eof not]] whileTrue: [self readConsoleLine].
		^ self].
	[pending isEmpty and: [eof not]] whileTrue: [
		chunk := Stdio stdin next: 4096.
		chunk isEmpty
			ifTrue: [self noInputMeansEnd
				ifTrue: [eof := true]
				ifFalse: [(Delay forMilliseconds: 20) wait]]
			ifFalse: [pending addAll: chunk]]'.
cm value: stdin value: 'testing' value: 'atEnd
	self waitForInput.
	^ pending isEmpty'.
cm value: stdin value: 'reading' value: 'nextLine
	"The next line without its line ending; at end of input, whatever was left."
	| bytes b line |
	bytes := WriteStream on: (ByteArray new: 80).
	[self atEnd or: [(b := pending removeFirst) = 10]] whileFalse: [bytes nextPut: b].
	line := bytes contents.
	(line notEmpty and: [line last = 13]) ifTrue: [line := line allButLast].
	"Ctrl+Z typed alone on a console line means end of input, by Windows convention"
	(line size = 1 and: [line first = 26]) ifTrue: [eof := true. pending removeAll. ^ ''''].
	^ line utf8Decoded'.

"=== LispRepl =============================================================="
cm value: repl value: 'private' value: 'setIn: inStream out: outStream err: errStream
	in := inStream.
	out := outStream.
	err := errStream.
	compiler := LispCompiler new'.
cm value: repl value: 'reporting' value: 'errorText: anError
	^ LispError describe: anError'.
cm value: repl value: 'reporting' value: 'report: anError
	err nextPutAll: ''error: '' , (self errorText: anError); nextPut: Character lf; flush'.
cm value: repl value: 'running' value: 'prompt
	out nextPutAll: ''> ''; flush'.
cm value: repl value: 'running' value: 'evalAndPrint: datum from: aReader
	| value |
	[value := compiler eval: datum from: aReader.
	 value == LispUnspecified default ifFalse: [
		out nextPutAll: (LispPrinter writeString: value); nextPut: Character lf; flush]]
		on: Error
		do: [:e | self report: e]'.
cm value: repl value: 'running' value: 'process: buffer
	"Evaluate each complete datum in buffer as soon as it is read, and answer what is
	 left to keep reading: the text after the last complete datum if the input ends in
	 an incomplete one, else the empty string. Evaluating as we go means a read error
	 later on the line no longer discards the forms before it (review R-6)."
	| reader d consumed |
	reader := LispReader on: buffer.
	consumed := 0.
	[[(d := reader next) == LispReader eofObject] whileFalse: [
		consumed := reader position.
		self evalAndPrint: d from: reader]]
		on: LispReadError
		do: [:e |
			e isIncomplete ifTrue: [^ buffer copyFrom: consumed + 1 to: buffer size].
			self report: e.
			^ ''''].
	^ '''''.
cm value: repl value: 'running' value: 'run
	"Loop until end of input. Output from display/write goes to the same stream as results."
	| buffer |
	buffer := ''''.
	LispPrimitives withOutput: out do: [
		[buffer isEmpty ifTrue: [self prompt].
		 in atEnd] whileFalse: [
			buffer := self process: buffer , in nextLine , (String with: Character lf)]].
	(buffer allSatisfy: [:c | c isSeparator]) ifFalse: [
		err nextPutAll: ''error: unexpected end of input''; nextPut: Character lf; flush].
	out nextPut: Character lf; flush'.
cm value: repl class value: 'instance creation' value: 'in: inStream out: outStream err: errStream
	^ self new setIn: inStream out: outStream err: errStream'.

"=== LispShellCommand (Clap) ==============================================="
cm value: shell class value: 'command line' value: 'commandSpecification
	<commandline>
	^ (ClapCommandSpec id: #lisp)
		description: ''Run a cog-lisp program, or start the cog-lisp REPL'';
		commandClass: self;
		addHelp;
		addPositional: #args spec: [ :positional |
			positional
				description: ''repl | run <file>'';
				multiple: true;
				defaultValue: [ :arg :app | #() ] ];
		yourself'.
cm value: shell class value: 'build' value: 'markBuilt
	BuildTime := DateAndTime now'.
cm value: shell class value: 'build' value: 'buildTime
	^ BuildTime'.
cm value: shell value: 'running' value: 'fail: aString
	self failReport: ''error: '' , aString'.
cm value: shell value: 'running' value: 'failReport: aLine
	"The report starts its own line even when the program''s output did not end with
	 one: in a terminal stdout and stderr share lines, and an editor''s problem
	 matcher reads path:line:col: error: from the start of a line."
	LispTextOutput stdout flush.
	LispTextOutput stdout isMidLine ifTrue: [LispTextOutput stderr nextPut: Character lf].
	LispTextOutput stderr nextPutAll: aLine; nextPut: Character lf; flush.
	Smalltalk exit: 1'.
cm value: shell value: 'running' value: 'warnIfStale
	"Warn when any src/*.st file is newer than this image build (Phase 5 section 4.2)."
	| srcDir built |
	built := self class buildTime.
	built isNil ifTrue: [^ self].
	srcDir := Smalltalk imageDirectory parent / ''src''.
	srcDir exists ifFalse: [^ self].
	(srcDir filesMatching: ''*.st'') detect: [:f | f modificationTime > built] ifFound: [:f |
		LispTextOutput stderr
			nextPutAll: ''warning: '' , f basename , '' is newer than this image; run build-image.bat to rebuild'';
			nextPut: Character lf; flush]'.
cm value: shell class value: 'memory' value: 'memoryLimit
	"Bytes of heap a program may grow to before it is stopped with an error (review
	 R-3). 2 GB, or COGLISP_MAX_MEMORY_MB. cog-lisp.bat also caps the VM at 8 GB as
	 a backstop, so a larger setting has no effect past that."
	| mb |
	mb := [(OSEnvironment current at: ''COGLISP_MAX_MEMORY_MB'' ifAbsent: [nil]) ifNotNil: [:s | s asInteger]]
		on: Error do: [:e | nil].
	^ (mb ifNil: [2048]) * 1048576'.
cm value: shell value: 'memory' value: 'withMemoryLimitDo: aBlock
	^ self withMemoryLimit: self class memoryLimit do: aBlock'.
cm value: shell value: 'memory' value: 'withMemoryLimit: limit do: aBlock
	"Run aBlock while a watchdog checks the heap every 100 ms. Past the limit it
	 signals a LispError in the running program, which reports it like any error
	 (and the REPL carries on). Runaway recursion otherwise grows the heap until the
	 machine runs out of memory: Pharo has no stack limit (review R-3)."
	| main fired watchdog |
	main := Processor activeProcess.
	fired := false.
	watchdog := [[(Delay forMilliseconds: 100) wait.
		Smalltalk vm memorySize > limit
			ifTrue: [fired ifFalse: [
				fired := true.
				main signalException: ((LispError new) messageText:
					''out of memory: the program grew past '' , (limit // 1048576) printString ,
					'' MB (runaway recursion?)''; yourself)]]
			ifFalse: [fired := false]] repeat]
		forkAt: Processor userInterruptPriority.
	watchdog name: ''cog-lisp memory watchdog''.
	^ aBlock ensure: [watchdog terminate]'.
cm value: shell value: 'running' value: 'runRepl
	self withMemoryLimitDo: [
		(LispRepl
			in: LispStdin new
			out: LispTextOutput stdout
			err: LispTextOutput stderr) run].
	Smalltalk exit: 0'.
cm value: shell value: 'running' value: 'runFile: aPath
	aPath isNil ifTrue: [^ self fail: ''no program file given''].
	self withMemoryLimitDo: [LispCompiler new evalFile: aPath].
	LispTextOutput stdout flush.
	Smalltalk exit: 0'.
cm value: shell value: 'running' value: 'execute
	| args text |
	args := (self positional: #args) asArray.
	[[self warnIfStale.
	  (args isEmpty or: [args first = ''repl'']) ifTrue: [^ self runRepl].
	  args first = ''run'' ifTrue: [^ self runFile: (args at: 2 ifAbsent: [nil])].
	  self fail: ''unknown lisp command: '' , args first]
		on: Warning do: [:w | w resume]]
		on: Error do: [:e |
			"path:line:col: error: message, for an error while running a file (review R-1)"
			(e isKindOf: LispLocatedError) ifTrue: [^ self failReport: e reportText].
			self fail: (LispError describe: e)]'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Shell'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Shell: ' , failures size printString].
