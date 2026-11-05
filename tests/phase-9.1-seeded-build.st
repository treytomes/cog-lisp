"============================================================================
 cog-lisp : Phase 9 step 9.1 acceptance suite  (specs/phase-9-language.md,
 9.1 in detail, AC-1): what LISP cannot check about itself. The build's
 sweep removes what a seed had and src/ no longer defines; the pins are read;
 an image not built from a seed says so. The seeded build itself is checked by
 tests/lisp/phase-9.1-seeded-build.lisp and examples/seeded-build.lisp, on the
 image the runner suite builds.
 ============================================================================"

"--- Chunk 1: load the packages and the harness -----------------------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn].
(Smalltalk imageDirectory parent / 'tests' / 'harness.st') fileIn.
!

"--- Chunk 2: the checks -----------------------------------------------------"
| h stale staleClass old removed before pins |
h := LispTestHarness new.
[
h say: '== cog-lisp Phase 9.1 : seeded builds =='.
LispPrimitives installDefault.

"the sweep: a method the seed had that is still the same object, and a CogLisp
 class src/ does not define, are removed; nothing else is"
LispCons compile: 'zzStaleForTest
	^ 42' classified: 'testing'.
stale := LispCons >> #zzStaleForTest.
staleClass := (Object << #LispZzStaleForTest) package: 'CogLisp-Core'; install.
old := IdentitySet with: stale.
before := LispCompiler cogLispMethods size.
h check: 'AC-1 the CogLisp packages hold the stale method' actual: (LispCompiler cogLispMethods includes: stale) expected: true.
removed := LispCompiler removeStaleFrom: (Dictionary new at: #seedMethods put: old; yourself).
h check: 'AC-1 the sweep names what it removed' actual: removed asArray expected: #('LispZzStaleForTest' 'LispCons>>zzStaleForTest').
h check: 'AC-1 the stale method is gone' actual: (LispCons includesSelector: #zzStaleForTest) expected: false.
h check: 'AC-1 the class src/ does not define is gone' actual: (Smalltalk includesKey: #LispZzStaleForTest) expected: false.
h check: 'AC-1 every other method stays' actual: LispCompiler cogLispMethods size expected: before - 1.
h check: 'AC-1 the classes src/ defines stay' actual: ((Smalltalk includesKey: #LispCons) and: [Smalltalk includesKey: #LispShellCommand]) expected: true.
h check: 'AC-1 with nothing kept from a seed, the sweep removes nothing'
	actual: ((LispCompiler removeStaleFrom: (Dictionary new at: #seedMethods put: IdentitySet new; yourself)) isEmpty)
	expected: true.

"the pins: KEY=VALUE lines, comments left out"
pins := LispCompiler pinsAt: Smalltalk imageDirectory parent / 'pharo.pins'.
h check: 'AC-1 pharo.pins names the seed by its tag' actual: ((pins at: 'SEED_TAG' ifAbsent: ['']) beginsWith: 'v') expected: true.
h check: 'AC-1 and pins its checksum' actual: (pins at: 'SEED_SHA256' ifAbsent: ['']) size expected: 64.
h check: 'AC-1 comment lines are not pins' actual: (pins keys anySatisfy: [:k | k beginsWith: '#']) expected: false.
h check: 'AC-1 a missing pins file is no pins' actual: (LispCompiler pinsAt: Smalltalk imageDirectory / 'no-such.pins') isEmpty expected: true.

"an image the suites load into was not built from a seed"
h check: 'AC-1 (image-build-info) is () in an image not built from a seed'
	actual: (LispPrinter writeString: (LispCompiler new evalString: '(image-build-info)'))
	expected: '()'.

h finish
] on: Error do: [:e | h harnessError: e].
!
