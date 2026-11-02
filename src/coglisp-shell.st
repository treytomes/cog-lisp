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
| failures cm repl shell |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , (src copyUpTo: Character cr) , (src copyUpTo: Character lf) , '  --  ' , e messageText]].

repl  := (Object << #LispRepl) slots: { #in. #out. #err. #compiler }; package: 'CogLisp-Shell'; install.
shell := (ClapApplication << #LispShellCommand) sharedVariables: { #BuildTime }; package: 'CogLisp-Shell'; install.

"=== LispRepl =============================================================="
cm value: repl value: 'private' value: 'setIn: inStream out: outStream err: errStream
	in := inStream.
	out := outStream.
	err := errStream.
	compiler := LispCompiler new'.
cm value: repl value: 'reporting' value: 'errorText: anError
	| text |
	text := anError messageText.
	(text isNil or: [text isEmpty]) ifTrue: [text := anError class name].
	^ text'.
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
	"Evaluate every complete datum in buffer and answer what is left to keep reading:
	 the buffer itself if the input so far is an incomplete datum, else the empty string."
	| reader data d |
	reader := LispReader on: buffer.
	data := OrderedCollection new.
	[[(d := reader next) == LispReader eofObject] whileFalse: [data add: d]]
		on: LispReadError
		do: [:e |
			e isIncomplete ifTrue: [^ buffer].
			self report: e.
			^ ''''].
	data do: [:each | self evalAndPrint: each from: reader].
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
	Stdio stderr nextPutAll: ''error: '' , aString; nextPut: Character lf; flush.
	Smalltalk exit: 1'.
cm value: shell value: 'running' value: 'warnIfStale
	"Warn when any src/*.st file is newer than this image build (Phase 5 section 4.2)."
	| srcDir built |
	built := self class buildTime.
	built isNil ifTrue: [^ self].
	srcDir := Smalltalk imageDirectory parent / ''src''.
	srcDir exists ifFalse: [^ self].
	(srcDir filesMatching: ''*.st'') detect: [:f | f modificationTime > built] ifFound: [:f |
		Stdio stderr
			nextPutAll: ''warning: '' , f basename , '' is newer than this image; run build-image.bat to rebuild'';
			nextPut: Character lf; flush]'.
cm value: shell value: 'running' value: 'runRepl
	(LispRepl
		in: (ZnCharacterReadStream on: Stdio stdin encoding: ''utf8'')
		out: Stdio stdout
		err: Stdio stderr) run.
	Smalltalk exit: 0'.
cm value: shell value: 'running' value: 'runFile: aPath
	aPath isNil ifTrue: [^ self fail: ''no program file given''].
	LispCompiler new evalFile: aPath.
	Stdio stdout flush.
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
			text := e messageText.
			(text isNil or: [text isEmpty]) ifTrue: [text := e class name].
			self fail: text]'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Shell'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
