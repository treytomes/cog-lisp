"============================================================================
 cog-lisp : image build script  (specs/phase-9-language.md, 9.1 in detail;
 first written for specs/phase-5-repl-runner.md section 4.1)
 Run by build-image.bat / build-image.sh on the SEED image, an earlier cog-lisp
 image pinned in pharo.pins:
   pharo\PharoConsole.exe --headless pharo\seed.image st build\build.st
 Files in the src packages over the seed, removes what the seed had and the
 source no longer does, lets the seed's compiler compile lib/core.lisp and
 lib/compiler/ into a fresh environment, bootstraps the new compiler to a
 fixpoint, smoke-tests the result, and saves it as pharo\cog-lisp.image. The seed
 file itself is never saved.
 ============================================================================"

"--- Chunk 1: keep the seed's compiler, and note the seed's packages -------"
| out seedPackages |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
((Smalltalk includesKey: #LispCompiler) and: [(Smalltalk at: #LispCompiler) hasLispCompiler])
	ifFalse: [out value: 'BUILD FAILED: this is not a cog-lisp image with a LISP compiler; build from pharo/seed.image'.
		Smalltalk exit: 1].
"The build records every method source in the changes file: a read-only one
 (another VM holds the seed, or the folder cannot be written) would lose them
 (specs/startup-anywhere.md R-6)."
(SourceFiles changesFileStream isNil or: [SourceFiles changesFileStream isReadOnly])
	ifTrue: [out value: 'BUILD FAILED: pharo/seed.changes cannot be written: is another cog-lisp running on pharo/seed.image, or is pharo/ read-only?'.
		Smalltalk exit: 1].
seedPackages := (PackageOrganizer default packages select: [:p | p name beginsWith: 'CogLisp-'])
	collect: [:p | p name asString].
Smalltalk at: #CogLispBuild put: (Dictionary new
	at: #seedEntries put: (Smalltalk at: #LispCompiler) entries;
	at: #seedPackages put: seedPackages asArray;
	at: #compiled put: Set new;
	yourself).
out value: 'seed: ' , seedPackages size printString , ' CogLisp packages'.
!

"--- Chunk 2: file in the packages over the seed's, noting every method compiled
     (each one announces itself; Pharo's recompiling for a changed class shape
     does not, so a seed's method the source no longer has is never counted) --"
| dir compiled listener |
dir := Smalltalk imageDirectory parent / 'src'.
compiled := (Smalltalk at: #CogLispBuild) at: #compiled.
listener := Object new.
SystemAnnouncer uniqueInstance
	when: MethodAdded, MethodModified
	do: [:a | compiled add: a methodClass name asString , '>>' , a selector]
	for: listener.
"An unhandled error here would hang the VM; fail the build instead."
[[#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn]]
		ensure: [SystemAnnouncer uniqueInstance unsubscribe: listener]]
	on: Error
	do: [:e |
		Stdio stdout nextPutAll: 'BUILD FAILED while loading: ' , e messageText printString; nextPut: Character lf; flush.
		Smalltalk exit: 1].
!

"--- Chunk 3: remove what the seed had and src/ no longer defines, before any of
     it can run: a method of the seed's that was not compiled anew may use a
     slot or a class that is gone -------------------------------------------"
| out removed |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
[removed := LispCompiler removeStaleFrom: (Smalltalk at: #CogLispBuild).
 out value: 'removed from the seed, no longer in src/: ' , removed size printString.
 removed do: [:name | out value: '  ' , name]]
	on: Error
	do: [:e | out value: 'BUILD FAILED removing what the seed had: ' , e messageText printString. Smalltalk exit: 1].
!

"--- Chunk 4: the seed compiles the new compiler, which reaches a fixpoint;
     smoke-test, prepare for a headless snapshot -------------------------------"
| out build ok |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
build := Smalltalk at: #CogLispBuild.
ok := [| diffs |
	  diffs := LispCompiler buildFromSeed: build.
	  out value: 'the LISP compiler reached a fixpoint from the seed; it is the one in use'.
	  out value: 'forms where the seed''s code differs from the new compiler''s: ' , diffs size printString.
	  diffs do: [:label | out value: '  ' , label].
	  "defines nothing, so the image ships with only the primitives, core.lisp and lib/compiler bound"
	  ((LispCompiler new evalString: '((lambda (n) (* n n)) 7)') = 49)
		and: [(LispCompiler new evalString: '(let* ((a 1) (b (+ a 1))) (cond ((= b 1) 10) ((= b 2) 20) (else 30)))') = 20]]
		on: Error
		do: [:e | out value: 'BUILD ERROR: ' , e messageText printString. false].
ok ifFalse: [out value: 'BUILD FAILED: smoke test did not pass; image not saved'. Smalltalk exit: 1].
Smalltalk globals removeKey: #CogLispBuild.
"No Epicea (Pharo's log of code changes): at every start-up it created
 pharo-local/ombu-sessions beside the image, so an install the user cannot write
 failed to start (specs/startup-anywhere.md R-4). cog-lisp keeps its own source."
(Smalltalk hasClassNamed: #EpMonitor) ifTrue: [
	EpMonitor hasCurrent ifTrue: [EpMonitor current disable].
	EpMonitor reset.
	SessionManager default unregisterClassNamed: #EpMonitor; unregisterClassNamed: #EpLostChangesDetector].
LispShellCommand markBuilt.
out value: 'BUILD OK: built from the seed; packages, primitives, lib/core.lisp and lib/compiler installed, smoke test passed'.
!

"--- Chunk 5: save as cog-lisp. When the saved image later starts, this process
     resumes here; it must stop rather than run on in the new session. ---------"
(Smalltalk saveAs: 'cog-lisp') isImageStarting
	ifTrue: [Processor activeProcess terminate]
	ifFalse: [Smalltalk exit: 0].
!
