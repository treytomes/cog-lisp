"============================================================================
 cog-lisp : Phase 9 step 9.1 acceptance suite  (specs/15-phase-9-language.md,
 9.1 in detail, AC-1): what LISP cannot check about itself. The build's
 sweep removes what a seed had and src/ no longer defines (whatever the file-in
 did not compile); the pins are read;
 the image names its seed. The seeded build itself is checked by
 tests/lisp/phase-9.1-seeded-build.lisp and examples/seeded-build.lisp, on the
 image the runner suite builds.
 ============================================================================"

"--- Chunk 1: the harness -------------------------------------------------"
"The suite runs on a copy of the built image (pharo/suite.image, made by
 tests/run-all), which holds every package: only the harness is filed in."
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h stale compiled removed before pins key |
h := LispTestHarness new.
[
h say: '== cog-lisp Phase 9.1 : seeded builds =='.
LispPrimitives installDefault.

"the sweep: in the packages src/ defines, a method the file-in did not compile
 (here, every method but one counts as compiled) and a class src/ does not
 define are removed; nothing else is"
key := [:m | m methodClass name asString , '>>' , m selector].
compiled := Set new.
LispCompiler cogLispMethods do: [:m | compiled add: (key value: m)].
LispCons compile: 'zzStaleForTest
	^ 42' classified: 'testing'.
stale := LispCons >> #zzStaleForTest.
(Object << #LispZzStaleForTest) package: 'CogLisp-Core'; install.
before := LispCompiler cogLispMethods size.
h check: 'AC-1 the CogLisp packages hold the stale method' actual: (LispCompiler cogLispMethods includes: stale) expected: true.
removed := LispCompiler removeStaleFrom: (Dictionary new at: #compiled put: compiled; yourself).
h check: 'AC-1 the sweep names what it removed' actual: removed asArray expected: #('LispZzStaleForTest' 'LispCons>>zzStaleForTest').
h check: 'AC-1 the stale method is gone' actual: (LispCons includesSelector: #zzStaleForTest) expected: false.
h check: 'AC-1 the class src/ does not define is gone' actual: (Smalltalk includesKey: #LispZzStaleForTest) expected: false.
h check: 'AC-1 every other method stays' actual: LispCompiler cogLispMethods size expected: before - 1.
h check: 'AC-1 the classes src/ defines stay' actual: ((Smalltalk includesKey: #LispCons) and: [Smalltalk includesKey: #LispShellCommand]) expected: true.
h check: 'AC-1 a method recompiled for a changed class shape is still stale: the rule is what the file-in compiled, not object identity'
	actual: ([LispCons compile: 'zzStaleForTest ^ 42' classified: 'testing'.
		(LispCompiler removeStaleFrom: (Dictionary new at: #compiled put: compiled; yourself)) asArray]
			value)
	expected: #('LispCons>>zzStaleForTest').
h check: 'AC-1 with every method compiled, the sweep removes nothing'
	actual: ((LispCompiler removeStaleFrom: (Dictionary new at: #compiled put: compiled; yourself)) isEmpty)
	expected: true.
h check: 'AC-1 a sweep that would remove most of the methods refuses, and removes nothing'
	actual: ([LispCompiler removeStaleFrom: (Dictionary new at: #compiled put: Set new; yourself). #none]
		on: Error do: [:e | (e messageText includesSubstring: 'refus') & (LispCons includesSelector: #car)])
	expected: true.
h check: 'AC-1 another package, not in src/ nor the seed, is left alone'
	actual: (Smalltalk includesKey: #LispTestHarness)
	expected: true.

"the pins: KEY=VALUE lines, comments left out"
pins := LispCompiler pinsAt: Smalltalk imageDirectory parent / 'pharo.pins'.
h check: 'AC-1 pharo.pins names the seed by its tag' actual: ((pins at: 'SEED_TAG' ifAbsent: ['']) beginsWith: 'v') expected: true.
h check: 'AC-1 and pins its checksum' actual: (pins at: 'SEED_SHA256' ifAbsent: ['']) size expected: 64.
h check: 'AC-1 comment lines are not pins' actual: (pins keys anySatisfy: [:k | k beginsWith: '#']) expected: false.
h check: 'AC-1 a missing pins file is no pins' actual: (LispCompiler pinsAt: Smalltalk imageDirectory / 'no-such.pins') isEmpty expected: true.

"the suites run on the built image, which says it was built from the pinned seed"
h check: 'AC-1 (image-build-info) names the pinned seed'
	actual: (LispPrinter writeString: (LispCompiler new evalString: '(car (image-build-info))'))
	expected: '(seed . "' , (pins at: 'SEED_TAG' ifAbsent: ['']) , '")'.

h finish
] on: Error do: [:e | h harnessError: e].
!
