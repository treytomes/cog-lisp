"============================================================================
 cog-lisp : image build script  (specs/phase-5-repl-runner.md section 4.1)
 Run by build-image.bat against the STOCK Pharo image:
   pharo\PharoConsole.exe pharo\<stock>.image st build\build.st
 Files in the five src packages, installs the primitive library, smoke-tests
 the result, and saves it as pharo\cog-lisp.image. The stock image itself is
 never saved.
 ============================================================================"

"--- Chunk 1: load the packages -------------------------------------------"
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

"--- Chunk 2: install, smoke-test, prepare for a headless snapshot ----------"
| out ok |
out := [:s | Stdio stdout nextPutAll: s asString; nextPut: Character lf; flush].
ok := [LispPrimitives installDefault.
	  "lib/core.lisp's derived forms (specs/phase-7-macros.md section 7), then the
	   reader and compiler written in LISP, compiled by themselves to a fixpoint,
	   sealed, and made the ones in use (specs/phase-8-self-hosting.md step 8.5)"
	  LispCompiler installLispCompilerWithFixpoint.
	  out value: 'the LISP compiler reached a fixpoint; it is the one in use'.
	  "defines nothing, so the image ships with only the primitives, core.lisp and lib/compiler bound"
	  ((LispCompiler new evalString: '((lambda (n) (* n n)) 7)') = 49)
		and: [(LispCompiler new evalString: '(let* ((a 1) (b (+ a 1))) (cond ((= b 1) 10) ((= b 2) 20) (else 30)))') = 20]]
		on: Error
		do: [:e | out value: 'BUILD ERROR: ' , e messageText printString. false].
ok ifFalse: [out value: 'BUILD FAILED: smoke test did not pass; image not saved'. Smalltalk exit: 1].
LispShellCommand markBuilt.
out value: 'BUILD OK: packages loaded, primitives, lib/core.lisp and lib/compiler installed, smoke test passed'.
!

"--- Chunk 3: save as cog-lisp. When the saved image later starts, this process
     resumes here; it must stop rather than run on in the new session. ---------"
(Smalltalk saveAs: 'cog-lisp') isImageStarting
	ifTrue: [Processor activeProcess terminate]
	ifFalse: [Smalltalk exit: 0].
!
