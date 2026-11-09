"============================================================================
 cog-lisp : the compiler's Smalltalk side  (package CogLisp-Compiler)
 The reader and compiler are written in LISP (lib/compiler/, Phase 8) and built
 into the image from a seed (Phase 9 step 9.1, which retired the ones written in
 Smalltalk). This package is how Smalltalk code reaches them:
   LispCompiler new compile: / eval: / evalString: / evalAll: / evalFile:
 their options (read by lib/compiler/), the entry points the build installs and
 seals, the seeded build itself, and LispReaderInLisp, the reader behind
 LispReader on:.

 LOADER script (see coglisp-reader.st). Must be filed in AFTER coglisp-reader.st
 and coglisp-core.st.

 The compiler's optimizations (Phase 6) are named options, all on by default:
   #tailCalls #fastCalls #globalCells #literalQuote #directLet #inlinePrimitives
 LispCompiler withoutOptions: #(...) do: [...] switches some off, for
 benchmarks and debugging.
 ============================================================================"
| failures cm comp err lpath lread |
failures := OrderedCollection new.
cm := [:cls :cat :src |
  [cls compile: src classified: cat]
    on: Error
    do: [:e | failures add: cls name , ' >> ' , src lines first , '  --  ' , e messageText]].

comp := (Object << #LispCompiler)
	slots: { #sourceMap };
	sharedVariables: { #DefaultOptions. #LispEntries. #BuildInfo };
	package: 'CogLisp-Compiler';
	install.
err  := (LispError << #LispCompileError) slots: { #forms }; package: 'CogLisp-Compiler'; install.
"The full path of the file being loaded or run, per process (Phase 7.9 section 5.3)."
lpath := (DynamicVariable << #LispLoadPath) package: 'CogLisp-Compiler'; install.
"The reader written in LISP, behind LispReader's protocol (Phase 8 step 8.5)."
lread := (Object << #LispReaderInLisp) slots: { #state. #stream. #source }; package: 'CogLisp-Compiler'; install.

cm value: err value: 'accessing' value: 'forms
	"The forms the error happened in, innermost first, ending with the top-level
	 form, or nil (Phase 10 step 10.5; review C-18)."
	^ forms'.
cm value: err value: 'accessing' value: 'forms: aList
	forms := aList'.

"=== options ==============================================================="
cm value: comp class value: 'options' value: 'allOptions
	^ #(#tailCalls #fastCalls #globalCells #literalQuote #directLet #inlinePrimitives)'.
cm value: comp class value: 'options' value: 'defaultOptions
	DefaultOptions isNil ifTrue: [DefaultOptions := self allOptions asSet].
	^ DefaultOptions'.
cm value: comp class value: 'options' value: 'withoutOptions: anArray do: aBlock
	"Compile with some optimizations switched off while aBlock runs."
	| saved |
	saved := self defaultOptions copy.
	DefaultOptions := saved copy.
	anArray do: [:each | DefaultOptions remove: each ifAbsent: []].
	^ aBlock ensure: [DefaultOptions := saved]'.

"=== entry points =========================================================="
cm value: comp value: 'compiling' value: 'compile: datum
	^ self compile: datum context: nil'.
cm value: comp value: 'compiling' value: 'compile: datum context: text
	"A CompiledMethod for datum, from the LISP compiler (lib/compiler/). A top-level
	 form is not in tail position: its calls are ordinary calls."
	^ (self class entries at: #compile) value: datum value: (self class lispSourceMap: sourceMap) value: (text ifNil: [false])'.
cm value: comp value: 'evaluating' value: 'eval: datum
	^ self eval: datum context: nil steps: 0'.
cm value: comp value: 'evaluating' value: 'eval: datum context: text steps: n
	"Evaluate with the LISP compiler. At top level, the forms of a begin and the
	 expansion of a macro call are themselves top-level forms (R7RS; review C-11).
	 text is the source a made-up lambda takes; n counts macro expansions."
	^ (Smalltalk at: #LispProcedure) apply: (self class entries at: #eval)
		to: { datum. self class lispSourceMap: sourceMap. text ifNil: [false]. n }'.
cm value: comp value: 'evaluating' value: 'eval: datum from: aReader
	"Evaluate a datum read by aReader, so procedures can keep their exact source text."
	sourceMap := aReader.
	^ [self eval: datum] ensure: [sourceMap := nil]'.
cm value: comp value: 'evaluating' value: 'evalString: aString
	| r |
	r := LispReader on: aString.
	^ self eval: r readSingle from: r'.
cm value: comp value: 'evaluating' value: 'evalAll: aString
	| r d result |
	r := LispReader on: aString.
	result := LispUnspecified default.
	[(d := r next) == LispReader eofObject] whileFalse: [result := self eval: d from: r].
	^ result'.
cm value: comp value: 'evaluating' value: 'evalAll: aString named: aName
	"Like evalAll:, but an error from any form is signalled again as a
	 LispLocatedError saying where it happened: the start of the top-level form, or
	 the offending character for a read error (review R-1). An error that is already
	 located, from a nested load, keeps its own (innermost) location."
	| r d result |
	r := LispReader on: aString.
	result := LispUnspecified default.
	[[(d := r next) == LispReader eofObject] whileFalse: [result := self eval: d from: r]]
		on: Error
		do: [:e | | offset |
			(e isKindOf: LispLocatedError) ifTrue: [e pass].
			offset := (e isKindOf: LispReadError)
				ifTrue: [e position ifNil: [r datumStart]]
				ifFalse: [r datumStart].
			^ (LispLocatedError cause: e file: aName source: aString offset: (offset ifNil: [0])) signal].
	^ result'.
cm value: comp value: 'evaluating' value: 'evalFile: aPath
	| file |
	file := self class resolveInput: aPath.
	file exists ifFalse: [^ (LispFileError new) signal: ''file not found: '' , aPath].
	^ LispLoadPath value: file fullName during: [self evalAll: file contents named: file fullName]'.

"=== paths ================================================================="
cm value: comp class value: 'paths' value: 'isAbsolute: aPath
	^ aPath notEmpty and: [aPath first = $/ or: [aPath first = $\ or: [aPath size > 1 and: [(aPath at: 2) = $:]]]]'.
cm value: comp class value: 'paths' value: 'resolve: aPath
	"A relative path names a file beside the file being loaded or run, else in the
	 current directory (section 5.3)."
	| base |
	base := LispLoadPath value.
	((self isAbsolute: aPath) or: [base isNil]) ifTrue: [^ aPath asFileReference].
	^ base asFileReference parent resolveString: aPath'.
cm value: comp class value: 'paths' value: 'resolveInput: aPath
	"As resolve:, but a file that is not beside the loading file is also looked for in
	 the current directory, where programs written before Phase 7.9 expect it."
	| ref |
	ref := self resolve: aPath.
	(ref exists or: [self isAbsolute: aPath]) ifTrue: [^ ref].
	^ aPath asFileReference exists ifTrue: [aPath asFileReference] ifFalse: [ref]'.

"=== the reader and compiler: entry points and sealing (Phase 8 step 8.5) ==="
cm value: comp class value: 'implementation' value: 'hasLispCompiler
	^ LispEntries notNil'.
cm value: comp class value: 'implementation' value: 'entries
	"The entry points of the LISP reader and compiler, which the build installs."
	LispEntries isNil ifTrue: [self error: ''this image has no LISP reader and compiler: cog-lisp images are built from a seed (build-image)''].
	^ LispEntries'.
cm value: comp class value: 'implementation' value: 'lispSourceDirectory
	^ Smalltalk imageDirectory parent / ''lib'''.
cm value: comp class value: 'implementation' value: 'compilerSourceNames
	"The compiler''s source, in lib/compiler/, in load order. bootstrap.lisp is the
	 tool that compiles it to a fixpoint; it is not part of it, nor of the seal."
	^ #(''reader.lisp'' ''opal.lisp'' ''codegen.lisp'' ''compiler.lisp'' ''syntax-rules.lisp'')'.
cm value: comp class value: 'implementation' value: 'lispEntries
	"The LISP procedures the Smalltalk side calls, taken now, after sealing: later
	 definitions of these names do not change what eval and the reader use."
	| at |
	at := [:name | (LispEnvironment default cellFor: (LispSymbol named: name)) value].
	^ Dictionary new
		at: #compile put: (at value: ''lisp-compile-from'');
		at: #eval put: (at value: ''lisp-eval-from'');
		at: #macroexpand1 put: (at value: ''lisp-macroexpand-1'');
		at: #macroexpand put: (at value: ''lisp-macroexpand'');
		at: #parseNumber put: (at value: ''reader-parse-number'');
		at: #makeReader put: (at value: ''make-reader'');
		at: #next put: (at value: ''reader-next'');
		at: #datumStart put: (at value: ''reader-datum-start'');
		at: #position put: (at value: ''reader-position'');
		at: #setPosition put: (at value: ''rd-pos!!'');
		at: #sourceFor put: (at value: ''reader-source-for'');
		at: #skipIntertoken put: (at value: ''rd-skip-intertoken!!'');
		at: #atEnd put: (at value: ''rd-at-end?'');
		yourself'.
cm value: comp class value: 'implementation' value: 'definedNamesIn: aFile
	"The names a file of LISP defines at top level."
	| r d names |
	r := LispReader on: aFile contents.
	names := OrderedCollection new.
	[(d := r next) == LispReader eofObject] whileFalse: [
		((d isKindOf: LispCons) and: [d car == (LispSymbol named: ''define'') and: [d cdr isKindOf: LispCons]]) ifTrue: [
			names add: ((d cdr car isKindOf: LispCons) ifTrue: [d cdr car car] ifFalse: [d cdr car])]].
	^ names'.
cm value: comp class value: 'implementation' value: 'sealLispCompiler: lib
	"Make the compiler independent of later definitions: every global cell its code
	 reads (car, append, its own procedures, ...) becomes a private cell holding the
	 value it has now, so a program that defines append, or make-reader, changes
	 its own world, not the compiler. The code is everything reachable from the
	 values of the names the compiler''s source defines: procedures, and the
	 procedures in its tables (the special forms). define-special-form still
	 extends it: the table is shared; only the cell is private."
	| frozen seen walk walkProc |
	frozen := IdentityDictionary new.
	seen := IdentitySet new.
	walk := nil.
	walk := [:code |
		(seen includes: code) ifFalse: [
			seen add: code.
			1 to: code numLiterals do: [:i | | lit |
				lit := code literalAt: i.
				(lit isKindOf: LispGlobal)
					ifTrue: [code literalAt: i put: (frozen at: lit ifAbsentPut: [lit frozenCopy])]
					ifFalse: [
						(lit isKindOf: CompiledBlock) ifTrue: [walk value: lit].
						(lit isKindOf: BlockClosure) ifTrue: [walk value: lit compiledBlock]]]]].
	walkProc := [:v |
		((v isKindOf: (Smalltalk at: #LispProcedure)) and: [v block isKindOf: BlockClosure])
			ifTrue: [walk value: v block compiledBlock]].
	self compilerSourceNames do: [:name |
		(self definedNamesIn: lib / ''compiler'' / name) do: [:sym | | v |
			v := (LispEnvironment default cellFor: sym) valueIfUnbound: [nil].
			walkProc value: v.
			(v isKindOf: (Smalltalk at: #LispHashTable)) ifTrue: [v values do: [:x | walkProc value: x]]]].
	"machine code made before sealing may still read the old cells"
	Smalltalk vm voidCogVMState'.
cm value: comp class value: 'implementation' value: 'lispSourceMap: aSourceMap
	"What the LISP compiler takes as a source map: the LISP reader''s state inside
	 its adapter, or #f."
	aSourceMap isNil ifTrue: [^ false].
	(aSourceMap isKindOf: LispReaderInLisp) ifTrue: [^ aSourceMap state].
	^ aSourceMap'.
cm value: comp class value: 'implementation' value: 'readerOn: aStringOrStream
	"The LISP reader over aStringOrStream: a string, or a ReadStream over one."
	^ (LispReaderInLisp on: aStringOrStream entries: self entries)
		ifNil: [self error: ''the reader reads a string, or a ReadStream over one'']'.

"=== the image build, from a seed (Phase 9 step 9.1) ======================="
cm value: comp class value: 'seeded build' value: 'buildFromSeed: build
	"Steps 4 to 7 of the build (specs/phase-9-language.md, 9.1 in detail), run by
	 build/build.st on the seed image after it has filed in src/. build holds what
	 the build kept from the seed (#seedEntries, its sealed compiler). The seed
	 compiles lib/core.lisp and lib/compiler/ into a fresh environment, the
	 bootstrap runs with the seed as stage 0, and the compiler it reaches is sealed
	 and put in use. Answers the bootstrap''s labels of the forms where the seed''s
	 code and the new compiler''s differ."
	| lib seed prims call result forms diffs |
	lib := self lispSourceDirectory.
	seed := build at: #seedEntries.
	prims := Smalltalk at: #LispPrimitives.
	call := [:name :args | (Smalltalk at: #LispProcedure)
		apply: (LispEnvironment default lookup: (LispSymbol named: name)) to: args].
	LispEntries := seed.
	LispEnvironment reset.
	prims classPool at: #GensymCounter put: nil.
	prims installDefault.
	self new evalFile: (lib / ''core.lisp'') fullName.
	"format, built in (specs/format.md), compiled by the seed like core.lisp"
	self new evalFile: (lib / ''format.lisp'') fullName.
	"json-read and json-write (specs/https-and-json.md R-3)"
	self new evalFile: (lib / ''json.lisp'') fullName.
	"the coverage recorder (specs/coverage.md), before the compiler, which calls it"
	self new evalFile: (lib / ''coverage.lisp'') fullName.
	self compilerSourceNames , #(''bootstrap.lisp'') do: [:name |
		self new evalFile: (lib / ''compiler'' / name) fullName].
	result := call value: ''bootstrap-compiler-from-seed'' value: { (lib / ''compiler'') fullName. seed }.
	(call value: ''bootstrap-fixpoint?'' value: { result }) == true
		ifFalse: [self error: ''the compiler did not reach a fixpoint: stages 1, 2 and 3 differ'' ].
	forms := call value: ''length'' value: { result at: 2 }.
	diffs := LispCons elementsOf: (call value: ''bootstrap-differences'' value: { result. 0. 1 }) for: ''build''.
	self sealLispCompiler: lib.
	LispEntries := self lispEntries.
	prims classPool at: #GensymCounter put: nil.
	BuildInfo := OrderedCollection new.
	(self pinsAt: lib parent / ''pharo.pins'') in: [:pins |
		BuildInfo
			add: #seed -> (pins at: ''SEED_TAG'' ifAbsent: [''unknown'']);
			add: #''seed-sha256'' -> (pins at: ''SEED_SHA256'' ifAbsent: [''unknown''])].
	BuildInfo
		add: #''stage-0'' -> (LispSymbol named: ''seed'');
		add: #fixpoint -> true;
		add: #forms -> forms;
		add: #''seed-differences'' -> diffs size.
	^ diffs'.
cm value: comp class value: 'seeded build' value: 'pinsAt: aFile
	"KEY=VALUE lines of pharo.pins, as a Dictionary; # starts a comment."
	| pins |
	pins := Dictionary new.
	aFile exists ifFalse: [^ pins].
	aFile contents lines do: [:line | | i |
		i := line indexOf: $=.
		(i > 1 and: [line first ~= $#]) ifTrue: [
			pins at: (line copyFrom: 1 to: i - 1) trimBoth put: (line copyFrom: i + 1 to: line size) trimBoth]].
	^ pins'.
cm value: comp class value: 'seeded build' value: 'sourceDefinitions
	"What src/ defines: (class names) -> (package names), read from its class
	 definitions (the class name after the shift-hash, the package name after the
	 package keyword). Keep those two patterns out of comments in src/."
	| classes packages |
	classes := Set new.
	packages := Set new.
	(self lispSourceDirectory parent / ''src'') files do: [:f |
		f extension = ''st'' ifTrue: [ | text |
			text := f contents.
			(text allRegexMatches: ''<< #[A-Za-z0-9]+'') do: [:m | classes add: (m copyAfter: $#) asSymbol].
			text lines do: [:line | | i |
				i := line indexOfSubCollection: ''package: ''''''.
				i > 0 ifTrue: [packages add: ((line copyFrom: i + 10 to: line size) copyUpTo: $'')]]]].
	^ classes -> packages'.
cm value: comp class value: 'seeded build' value: 'methodsOfPackages: names
	"Every method of the named packages, extension methods included."
	| methods |
	methods := IdentitySet new.
	(PackageOrganizer default packages select: [:p | names includes: p name asString]) do: [:p |
		methods addAll: p methods; addAll: p extensionMethods].
	^ methods'.
cm value: comp class value: 'seeded build' value: 'cogLispMethods
	"Every method of the packages src/ defines, extension methods included."
	^ self methodsOfPackages: self sourceDefinitions value'.
cm value: comp class value: 'seeded build' value: 'removeStaleFrom: build
	"What the seed had and src/ no longer defines, removed before any of it can run,
	 in the packages src/ defines and the ones the seed had (build at:
	 #seedPackages): a method the file-in did not compile (build at: #compiled,
	 ''Class>>selector'' strings; Pharo recompiling a class for a new shape does not
	 count), and a class src/ does not define. A sweep that would take most of the
	 methods is a mistake in what was noted, not a change to the source: it is
	 refused before anything is removed. Answers the names removed."
	| defs packages compiled removed classes all stale |
	defs := self sourceDefinitions.
	packages := defs value copy addAll: (build at: #seedPackages ifAbsent: [#()]); yourself.
	compiled := build at: #compiled.
	classes := OrderedCollection new.
	(PackageOrganizer default packages select: [:p | packages includes: p name asString]) do: [:p |
		p definedClasses do: [:c | (defs key includes: c name) ifFalse: [classes add: c]]].
	all := self methodsOfPackages: packages.
	stale := all reject: [:m |
		(classes includes: m methodClass instanceSide)
			or: [compiled includes: m methodClass name asString , ''>>'' , m selector]].
	stale size * 2 > all size ifTrue: [
		self error: ''the build refuses to remove '' , stale size printString , '' of '' , all size printString ,
			'' methods as no longer in src/: was every compiled method noted?''].
	removed := OrderedCollection new.
	classes do: [:c | removed add: c name asString. c removeFromSystem].
	stale do: [:m |
		removed add: m methodClass name asString , ''>>'' , m selector.
		m methodClass removeSelector: m selector].
	Smalltalk vm voidCogVMState.
	^ removed'.
cm value: comp class value: 'seeded build' value: 'buildInfoList
	"What (image-build-info) answers: an association list, or () in an image that
	 was not built from a seed."
	BuildInfo isNil ifTrue: [^ LispEmptyList default].
	^ LispCons fromArray: (BuildInfo asArray collect: [:a | LispCons car: (LispSymbol named: a key) cdr: a value])'.

"=== LispReaderInLisp: LispReader's protocol over the LISP reader =========="
cm value: lread class value: 'instance creation' value: 'on: aStringOrStream entries: entries
	aStringOrStream isString ifTrue: [
		^ self new setState: ((entries at: #makeReader) value: aStringOrStream) stream: nil source: aStringOrStream].
	((aStringOrStream isKindOf: ReadStream) and: [aStringOrStream originalContents isString]) ifTrue: [ | r |
		r := (entries at: #makeReader) value: aStringOrStream originalContents.
		(entries at: #setPosition) value: r value: aStringOrStream position.
		^ self new setState: r stream: aStringOrStream source: aStringOrStream originalContents].
	^ nil'.
cm value: lread value: 'private' value: 'setState: aReader stream: aStream source: aString
	state := aReader.
	stream := aStream.
	source := aString'.
cm value: lread value: 'private' value: 'entry: aSymbol
	^ LispCompiler entries at: aSymbol'.
cm value: lread value: 'private' value: 'syncStream
	"A stream read from is left just after what was read, as LispReader leaves it."
	stream ifNotNil: [:s | s position: ((self entry: #position) value: state)]'.
cm value: lread value: 'accessing' value: 'state
	^ state'.
cm value: lread value: 'reading' value: 'next
	"The next datum, or the eof object."
	^ [(self entry: #next) value: state] ensure: [self syncStream]'.
cm value: lread value: 'reading' value: 'atEnd
	[(self entry: #skipIntertoken) value: state] ensure: [self syncStream].
	^ (self entry: #atEnd) value: state'.
cm value: lread value: 'reading' value: 'readSingle
	| d |
	d := self next.
	d == LispReader eofObject ifTrue: [^ (LispReadError new) incomplete: true; signal: ''read: empty input''].
	self next == LispReader eofObject ifFalse: [^ (LispReadError new) signal: ''read: more than one datum''].
	^ d'.
cm value: lread value: 'source' value: 'datumStart
	^ (self entry: #datumStart) value: state'.
cm value: lread value: 'source' value: 'position
	^ (self entry: #position) value: state'.
cm value: lread value: 'source' value: 'source
	^ source'.
cm value: lread value: 'source' value: 'sourceFor: aCons
	| s |
	s := (self entry: #sourceFor) value: state value: aCons.
	^ s == false ifTrue: [nil] ifFalse: [s]'.

"=== load report ==========================================================="
Stdio stdout
	nextPutAll: (failures isEmpty ifTrue: ['LOAD OK: CogLisp-Compiler'] ifFalse: ['LOAD FAILURES: ' , failures size printString]);
	nextPut: Character lf.
failures do: [:f | Stdio stdout nextPutAll: '  ' , f; nextPut: Character lf].
Stdio stdout flush.
"a failed method must stop the build and the test suites, not just be reported"
failures isEmpty ifFalse: [Error signal: 'LOAD FAILURES in CogLisp-Compiler: ' , failures size printString].
