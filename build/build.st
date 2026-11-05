"============================================================================
 cog-lisp : image build script  (specs/phase-9-language.md, 9.1 in detail;
 first written for specs/phase-5-repl-runner.md section 4.1)
 Run by build-image.bat / build-image.sh on the SEED image, an earlier cog-lisp
 image pinned in pharo.pins:
   pharo\PharoConsole.exe --headless pharo\seed.image st build\build.st
 Files in the src packages over the seed, lets the seed's compiler compile
 lib/core.lisp and lib/compiler/ into a fresh environment, bootstraps the new
 compiler to a fixpoint, removes what the seed had and the source no longer
 does, smoke-tests the result, and saves it as pharo\cog-lisp.image. The seed
 file itself is never saved.
 ============================================================================"

"--- Chunk 1: keep the seed's compiler, and note what the seed has ---------"
| out seedPackages |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
((Smalltalk includesKey: #LispCompiler) and: [(Smalltalk at: #LispCompiler) hasLispCompiler])
	ifFalse: [out value: 'BUILD FAILED: this is not a cog-lisp image with a LISP compiler; build from pharo/seed.image'.
		Smalltalk exit: 1].
seedPackages := (PackageOrganizer default packages select: [:p | p name beginsWith: 'CogLisp-'])
	collect: [:p | p name asString].
Smalltalk at: #CogLispBuild put: (Dictionary new
	at: #seedEntries put: (Smalltalk at: #LispCompiler) entries;
	at: #seedPackages put: seedPackages asArray;
	at: #seedMethods put: ((PackageOrganizer default packages select: [:p | seedPackages includes: p name asString])
		inject: IdentitySet new into: [:all :p | all addAll: p methods; addAll: p extensionMethods; yourself]);
	yourself).
out value: 'seed: ' , ((Smalltalk at: #CogLispBuild) at: #seedMethods) size printString , ' methods in the CogLisp packages'.
!

"--- Chunk 2: file in the packages over the seed's -------------------------"
| dir |
dir := Smalltalk imageDirectory parent / 'src'.
"An unhandled error here would hang the VM; fail the build instead."
[#('coglisp-reader.st' 'coglisp-core.st' 'coglisp-compiler.st' 'coglisp-runtime.st' 'coglisp-shell.st')
	do: [:name | (dir / name) fileIn]]
	on: Error
	do: [:e |
		Stdio stdout nextPutAll: 'BUILD FAILED while loading: ' , e messageText printString; nextPut: Character lf; flush.
		Smalltalk exit: 1].
!

"--- Chunk 3: the seed compiles the new compiler, which reaches a fixpoint;
     then remove what is stale, smoke-test, prepare for a headless snapshot --"
| out build ok |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
build := Smalltalk at: #CogLispBuild.
ok := [| diffs removed |
	  diffs := LispCompiler buildFromSeed: build.
	  out value: 'the LISP compiler reached a fixpoint from the seed; it is the one in use'.
	  out value: 'forms where the seed''s code differs from the new compiler''s: ' , diffs size printString.
	  diffs do: [:label | out value: '  ' , label].
	  removed := LispCompiler removeStaleFrom: build.
	  out value: 'removed from the seed, no longer in src/: ' , removed size printString.
	  removed do: [:name | out value: '  ' , name].
	  "defines nothing, so the image ships with only the primitives, core.lisp and lib/compiler bound"
	  ((LispCompiler new evalString: '((lambda (n) (* n n)) 7)') = 49)
		and: [(LispCompiler new evalString: '(let* ((a 1) (b (+ a 1))) (cond ((= b 1) 10) ((= b 2) 20) (else 30)))') = 20]]
		on: Error
		do: [:e | out value: 'BUILD ERROR: ' , e messageText printString. false].
ok ifFalse: [out value: 'BUILD FAILED: smoke test did not pass; image not saved'. Smalltalk exit: 1].
Smalltalk globals removeKey: #CogLispBuild.
LispShellCommand markBuilt.
out value: 'BUILD OK: built from the seed; packages, primitives, lib/core.lisp and lib/compiler installed, smoke test passed'.
!

"--- Chunk 4: save as cog-lisp. When the saved image later starts, this process
     resumes here; it must stop rather than run on in the new session. ---------"
(Smalltalk saveAs: 'cog-lisp') isImageStarting
	ifTrue: [Processor activeProcess terminate]
	ifFalse: [Smalltalk exit: 0].
!
