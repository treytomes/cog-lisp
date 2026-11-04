# CLAUDE.md — cog-lisp

Project-specific guidance for Claude Code. Machine-level guidance lives in the
global `~/CLAUDE.md`; this file is only what is true for **this** repo.

## What this project is

An **image-based LISP** that compiles down to **Cog/Spur bytecode** and runs
JIT-native inside a Pharo image. LISP forms are compiled to `CompiledMethod`s
(via the Opal IR), installed into the image, and executed by the same VM that
runs Smalltalk — so the LISP is a first-class, persistable citizen of the image,
not an interpreter walking a tree.

- **Host dialect:** Pharo 14 (chosen for the Opal compiler / `IRBuilder`, the
  richest bytecode-generation on-ramp in the Smalltalk family).
- **VM:** OpenSmalltalk-derived **Cog + Spur** (Pharo's own VM fork), reported as
  `v12.0.6-beta`.
- **Architecture:** "Path A" — generate `CompiledMethod`s in the image and let
  Cog JIT them. We do **not** modify the VM/Slang. Exact bytecode control
  (`EncoderForSistaV1`) is a later option only if IRBuilder's abstraction gets in
  the way.

See `README.md` for the phased plan.

## Standing up the environment

The VM + image are **not** committed (see `.gitignore`). Regenerate them with:

```bat
bootstrap-pharo.bat
```

It downloads the stable 64-bit Windows VM + image into `pharo\`, extracts them,
and prints the VM and image versions. It is idempotent (cached zips are reused).

The root scripts each have a bash equivalent for Git Bash (`bootstrap-pharo.sh`,
`build-image.sh`, `cog-lisp.sh`); keep each pair in step when changing either.
In mintty, stdin is a pipe, not a Windows console, so an interactive REPL needs
a console terminal (Windows Terminal, VS Code) or `winpty`; piped input works.
Re-running the bootstrap re-extracts over `pharo\` (including the stock image),
which fails if the GUI `Pharo.exe` has those files open.

## Running Pharo headless

Use **`PharoConsole.exe`** (writes to stdout), not `Pharo.exe` (GUI, detaches):

```bat
pharo\PharoConsole.exe pharo\Pharo14.0-SNAPSHOT-64bit-58e29ca31d.image st poc\answer.st
```

`st <file>` files-in and runs a script; `eval "<expr>"` evaluates one expression
and prints its `printString`.

## Headless gotchas (learned the hard way)

- **Always end a script with `Smalltalk snapshot: false andQuit: true`.** Without
  an explicit quit the headless VM runs forever and the call hangs.
- **Print with `Stdio stdout`, not `Transcript`.** The headless Transcript is a
  `StThreadSafeTranscript` that does **not** understand `showln:`. Use:
  `Stdio stdout nextPutAll: aString; nextPut: Character lf; flush`.
- **A `.st` run via `st` is read as chunk format: double every literal `!` to
  `!!`.** A lone `!` is a chunk terminator, even inside a `'string'` or a
  `"comment"`; an un-doubled one splits the chunk mid-token (e.g. the symbol
  `set!` or a label containing it). The chunk reader turns `!!` back into `!`.
  Source files (`src/*.st`) that contain no `!` are unaffected; test files that
  mention `set!` are the usual place this bites.
- **A hung VM is killed with `taskkill /IM PharoConsole.exe /F`.** Never kill
  `Pharo.exe` — that is the user's interactive GUI image.
- **Two processes may read the same `.image` file** as long as neither saves;
  running a headless script while the GUI is open is fine.
- Scripts are run with `-I`-style isolation in mind: they must be self-contained
  and must not depend on image state from a previous run (the image is never
  saved).

## Verified command-line, image, and stdio mechanics (Pharo 14) — Phase 5

- **Commands are Clap, not classic `CommandLineHandler`s.** The top-level
  dispatcher ignores `CommandLineHandler` subclasses. Define a `ClapApplication`
  subclass whose class-side method carries `<commandline>` and returns a
  `ClapCommandSpec` (`id:`, `commandClass: self`, `addHelp`,
  `addPositional: #args spec: [:p | p multiple: true; defaultValue: [:arg :app | #()]]`).
  Its instance-side `execute` does the work; `self positional: #args` reads the
  arguments. `PharoConsole.exe img lisp a b` gives `#('a' 'b')`.
- **Quit with `Smalltalk exit: n`.** It exits immediately with that process exit
  code. `self exitSuccess` does not end the process, and `Smalltalk snapshot:
  false andQuit: true` (and even the stock `eval` command) can hang when stdout is
  a pipe. Test scripts that end in `snapshot: false andQuit: true` happen to work.
- **Never let an error go unhandled in a command.** It falls through to Pharo's
  error reporting and the VM hangs. Catch `Error` (and resume `Warning`) and
  `Smalltalk exit: 1`.
- **Saving under a new name:** `PharoConsole.exe stock.image save newName`, or
  from a script `(Smalltalk saveAs: 'newName') isImageStarting ifFalse: [...]`.
  The stock image is left untouched.
- **Snapshots resume in the saving process.** Code after `saveAs:` /
  `snapshot: true andQuit: false` runs again when the saved image next starts, with
  `isImageStarting` true. Guard it: `isImageStarting ifTrue: [Processor
  activeProcess terminate]`, or the old process keeps running in the new session.
- **Launch the VM with `--headless`.** By default the VM appends `--interactive`
  to the image's arguments, even under `PharoConsole.exe`, so Pharo attaches a
  real SDL2 OS window to the world at every startup. Its drawing failures make
  `OSSDL2FormRenderer` print `There was an error during copy … Bad BitBlt arg`
  **to stdout**, at timing-dependent moments, corrupting program output. With
  `PharoConsole.exe --headless <image> …` the image chooses `NullWorldRenderer`
  and no window exists. `build-image.bat` and `cog-lisp.bat` both pass it. (A
  null-renderer swap before saving only appeared to work; startup replaces it.)
- **stdin never blocks, and can't tell "no input yet" from "end of input".**
  `Stdio stdin` is binary. With nothing buffered, `next:` answers 0 bytes and
  `atEnd` answers true, exactly as at real end of input. So wrapping it in
  `ZnCharacterReadStream` only *seems* to work, with input already sitting in a
  pipe: at a console it fails with "Incomplete input for character decoding", and
  with late-arriving pipe input it ends immediately. Use `LispStdin`
  (`src/coglisp-shell.st`): on 0 bytes it asks Windows via uFFI what stdin is
  (`GetStdHandle(-10)`, then `GetFileType`: 1 = file, 2 = console, 3 = pipe). A
  console never ends; a file has ended; a pipe has ended once
  `PeekNamedPipe` answers 0 (the writer closed it; while open it answers 1 even
  when empty). Otherwise it sleeps 20 ms and polls. It decodes UTF-8 a whole line
  at a time. Always test stdin code with **delayed** input, e.g.
  `(sleep 2; printf '…\n') | cog-lisp.bat`, not just a ready pipe.
- **A console is never readable through `Stdio stdin`.** The VM never issues a
  console read, so keys are neither echoed nor delivered (the REPL shows its
  prompt and ignores the keyboard). `LispStdin` reads a console with
  `ReadConsoleW` via uFFI instead: it blocks the VM until Enter, Windows does the
  echo and line editing, and it returns UTF-16. Ctrl+Z alone on a line arrives
  as `16r1A` and ends input.
- **`cmd /c name.bat` does not find a batch file in the current directory here**
  ("not recognized"): name it `.
ame.bat`. The VS Code extension does this.
- **Testing console input without a person:** open `CONIN$` with `CreateFileW`
  and inject keystrokes with `WriteConsoleInputW` (20-byte `INPUT_RECORD`s:
  EventType 1 at offset 1, bKeyDown 1 at 5, repeat 1 at 9, the UTF-16 char at
  15), then read with `LispStdin onConsoleHandle:`.
- **stdout/stderr:** `Stdio stdout` / `Stdio stderr` are separate. Redirecting
  Pharo's stdout to `/dev/null` (NUL) makes writes fail; redirect to a file.
- **`Stdio stdout` does not encode text.** It writes a string's internal
  representation: `é` as the Latin-1 byte `E9`, and wide strings as four bytes per
  character (`λ` → `BB 03 00 00`, which a console shows as `╗`). Write text through
  `LispTextOutput stdout` / `stderr` (`src/coglisp-runtime.st`): to a console it
  uses `WriteConsoleW` (UTF-16, so the console code page never matters and is
  never changed); to pipes and files it writes UTF-8. To verify console output
  without a person, read the screen back with `ReadConsoleOutputCharacterW` on
  `CONOUT$`.
- **Deprecated calls print to stdout.** Pharo 14's deprecation rewriter prints a
  `DeprecationPerformedNotification` to stdout the first time a deprecated method
  is called in a session (e.g. `Smalltalk os`; use `OSPlatform current`), which
  corrupts program output. Byte-exact `.expected` checks catch it.

## Timing and benchmarking (Pharo 14) — Phase 6

- **The VM clock has millisecond resolution**, even through
  `Time microsecondClockValue` (its values end in `000`). `Time
  microsecondsToRun:` does not exist. For short work, repeat it until a sample
  takes at least ~100 ms and divide.
- **Whatever runs first in a process measures slow** (up to 40%): heap growth and
  JIT warm-up. Run a full discarded warm-up pass, and `Smalltalk garbageCollect`
  before each series, or comparisons between configurations are meaningless.
- `bench/results.md` is the committed performance baseline; rerun
  `bench\run-benchmarks.bat` after compiler or runtime changes and compare.

## Verified Opal AST API (Pharo 14) — for the Phase 3 compiler

Building a `CompiledMethod` from a hand-built Smalltalk AST (confirmed live):

- Parser is **`OCParser`**; AST nodes are **`OC*`** (`OCMethodNode`,
  `OCMessageNode`, `OCLiteralValueNode`, `OCVariableNode`, `OCReturnNode`,
  `OCSequenceNode`, `OCBlockNode`, `OCAssignmentNode`). `RB*` names are the same
  classes.
- **Compile:** `aMethodNode doSemanticAnalysis.` then `aMethodNode generateMethod`
  → a `CompiledMethod`; run with `valueWithReceiver: nil arguments: #()`.
  (`compiledMethod` alone returns nil without semantic analysis first.)
- **Constructors that work:** `OCLiteralValueNode value:`,
  `OCReturnNode value:`, `OCSequenceNode statements:` /
  `temporaries:statements:`, `OCMethodNode selector:arguments:body:`,
  `OCBlockNode arguments:body:`, `OCVariableNode named:` (resolves globals and,
  by name, block/method args), `OCAssignmentNode variable:value:`.
- **Message nodes: do NOT use `OCMessageNode receiver:selector:arguments:`** (nor
  the `selector:` setter, nor `RBMessageNode`): they send `#parent:` to the
  selector Symbol and fail. Instead **template-splice**: parse a well-formed
  skeleton for the selector (e.g. `OCParser parseExpression: '0 + 0'`, or
  `'0 value: 0 value: 0'`), then `m receiver: recvNode. m arguments: argNodes`.
- **Brace arrays** (`{a. b}`) are **`OCArrayNode`**: template-splice
  `OCParser parseExpression: '{0}'`, then `n statements: elementNodes` (an empty
  collection gives `#()`). The compiler uses this for application args arrays.
- **Any object can be a literal**: `OCLiteralValueNode value: anObject` puts it
  in the method's literal frame, and every run returns that same object. Such
  objects stay **writable** (global cells, quoted lists). But **string literals
  are compiled read-only**: mutating one raises `ModificationForbidden`. Matters
  once cog-lisp has string-mutation primitives.
- **Temporaries inside inlined blocks work** (`true ifTrue: [| t | t := …. …]`):
  Opal hoists them into the enclosing method or block frame, with no closure.
  That gives statement sequencing inside an expression. But every such temp
  lands in that one frame, and the VM caps frame size: too many fail compilation
  with "Cannot compile -- stack including temps is too deep". Budget them.
- **`[...] value` is a real block call** (a closure and a stack frame) even when
  the block is a literal; only the control selectors (`ifTrue:`, `whileTrue:`,
  `and:`, …) are inlined. To sequence statements without a frame, use
  `true ifTrue: [...]`. (`begin` compiled to `[...] value` until Phase 7, which
  made each `begin` one frame deeper.)
- **Temps declared inside a `whileTrue:` loop block get fresh storage on each
  iteration** when a closure captures them; temps declared outside are shared
  by every iteration. A loop that creates closures must copy its variables into
  loop-block temps, or every closure sees the last iteration's values.
- Closure capture is automatic: nested `OCBlockNode`s whose bodies reference an
  outer block's argument name compile to a real capturing `BlockClosure`.
- **Block/method arguments are read-only** — assigning one fails semantic
  analysis ("Assignment to read-only variable"). To make a LISP local mutable by
  `set!`, bind it to a **temporary** initialized from the argument
  (`[:arg | | local | local := arg. … ]`) and reference the temp. The Phase 3
  compiler does this for every lambda parameter.
- Reminder: `src/*.st` files are filed in as chunk format, so a literal `!`
  (e.g. in `'set!'`) must be doubled to `!!` in the source too.
- **Method source in `src/*.st` is a string literal: double every `'`.** Each
  method is compiled from `cm value: cls value: 'cat' value: '<source>'`, so an
  apostrophe in a comment (`Floyd's`) ends the literal early and the whole file
  fails to load with "End of statement expected". Write `''` (and `!!` for `!`).
- **Opal inlines control selectors even when the argument is not a block.** A
  message node for `ifTrue:`, `and:`, `whileTrue:`, `to:do:`, `ifNil:` … built with
  a non-block argument compiles inline, the argument taken as a plain value; the
  method is never sent. To send one for real (e.g. with a LISP procedure as the
  block), use `perform:withArguments:` (`LispCompiler inlinedSelectors`).
- **An exception signalled inside a handler block is handled only *outside* that
  handler's `on:do:`** (ANSI Smalltalk), not by `on:do:`s between the original
  signal and the handler, even though they are still on the stack. So restarts
  cannot be an exception: cog-lisp invokes them by non-local return from a block
  created in the establishing method (`LispRestart class>>establish:during:`),
  which unwinds, runs `ensure:` blocks, and passes no handler.
- **A `DynamicVariable` subclass** (`LispRestarts value: x during: [...]`) gives a
  per-process dynamic binding that handlers, which run on top of the signalling
  stack, still see.
- **`aSymbol , aString` answers a Symbol** (`#+ , ': x'` is `#'+: x'`); send
  `asString` first when building text from a selector.
- **`anObject value` answers the object itself** (`Object>>value`), so any object
  silently "works" as a zero-argument block; a LISP procedure overrides it.
- **`aCharacter value` is the character itself**, not its code (it is
  `Object>>value`); use `asInteger`. `Character value: n` (class side) does make a
  character from a code.
- **A frame holds at most 64 temporaries, and pushed values count against the
  same frame.** Deep nesting and long brace arrays (`{a. b. …}` pushes every
  element) overflow it; the compiler spills deep forms into `[…] value` and fills
  long arrays element by element (Phase 7.9).
- **A procedure body in a method's literals is a clean `BlockClosure`**, not a
  `CompiledBlock`: to disassemble everything, recurse into `lit compiledBlock`
  too (`tests/phase-7.9-groundwork.st` AC-2). `symbolic` shows one level only.
- **Compile time is mostly Opal's**: about half bytecode generation and a quarter
  semantic analysis; cog-lisp's own translation is the remaining quarter.
- **Never `^` inside a primitive's block.** A block stored in a `LispProcedure`
  runs after the installing method has returned, so a `^` in it raises
  `BlockCannotReturn`. Use `ifTrue:ifFalse:` instead.
- **A method may name only classes from its own or an earlier package.** The
  packages load in order (reader, core, compiler, runtime, shell), and a method
  that names a class defined later fails to compile ("undeclared"). So the
  compiler reaches runtime classes as `Smalltalk at: #LispProcedure`, or tests
  `respondsTo:`, and generated code (compiled after everything is loaded) may
  name any of them. Since Phase 7.5 a package that fails to compile a method
  signals an error at the end of its file-in, so the build and the suites stop.

## Verified Opal / IRBuilder API (Pharo 14, build 788)

Memory of this API is unreliable across versions — these were confirmed live:

- Builder class is **`OCIRBuilder`** (`IRBuilder new` returns one).
- **Finalize:** `(IRBuilder new … ; ir) compiledMethod`. Note `compiledMethod`
  is **not** on the builder — it is on the `IRMethod` returned by `ir`, and the
  cascade must be **parenthesized** (`… ; ir compiledMethod` is a *syntax error*,
  because the cascade sends `ir` and then chokes on `compiledMethod`).
- **Run a method with no install:** `m valueWithReceiver: nil arguments: #(…)`
  (defined on `CompiledMethod`, not `CompiledCode`).
- **Args + temps:** `numArgs: 2; addTemps: #(a b)` then push by **name**:
  `pushTemp: #a`. There is **no** `returnReceiver` (use `returnTop`).
- **Branching:** `jumpAheadTo: #label if: aBoolean` … `jumpAheadTarget: #label`
  (also `jumpBackTarget:` / `jumpBackTo:`). There is **no** `label:`.
- **Install into a class:** `aClass addSelectorSilently: #sel withMethod: m`.
- **Make a class:** `Object subclass: #Name` works; the old
  `subclass:instanceVariableNames:classVariableNames:package:` is **gone** in
  Pharo 14 (use the Fluid `Object << #Name …` form for a fuller definition).
- **Disassemble:** `m symbolic` returns the bytecode listing as a String.
- Smalltalk **temporaries are declared only at the top** of a method/block; a
  `| x |` in the middle is a syntax error.

## Spec-driven development

This project follows spec-driven development: **write the spec before the code.**

- Specs live in `specs/` — one document per phase/feature, each with explicit
  requirements and **acceptance criteria**.
- Every acceptance criterion should be mechanically checkable by a headless
  script, following the `poc/answer.st` convention: build, run, print
  `PASS`/`FAIL` per check, and a final `RESULT: n/n` line.
- Code changes reference the spec section they satisfy. If reality forces a
  deviation, update the spec first, then the code.
- **Run everything with `tests\run-all.bat`** (~30 s): each `tests\phase-*.st`
  in a fresh stock image, then `tests\phase-5-runner.bat` (which rebuilds
  `pharo\cog-lisp.image`), with a total; exit 0 only if all pass. Benchmarks are
  separate (`bench\run-benchmarks.bat`) and noisy when the machine is busy.
- **Language behavior is tested in LISP** (Phase 8 step 8.1): `tests/lisp/*.lisp`
  with `lib/test.lisp` (`define-test`, `check`, `check-error`, `check-written`,
  `check-error-class`, `eval-all`, `run-tests`). Smalltalk suites are for what
  LISP cannot test about itself: the reader and core, bytecode, options, REPL and
  stdin plumbing, the `CogLisp` facade, the test framework's self-test. A new
  LISP test file in `tests/lisp/` runs in `run-all.bat` with no other change.
- **Suites use `tests/harness.st`** (`LispTestHarness`): file it in after the
  packages, then `h check:actual:expected:`, `h check:raises:do:`,
  `h check:raises:containing:do:` (or the `h checkBlock`-style blocks), and end
  with `h finish` inside `[...] on: Error do: [:e | h harnessError: e]`. `finish`
  exits 0 or 1, so a new suite is picked up by `run-all.bat` with no other change.
- **An unhandled error in a `st` chunk prints its stack and exits 1**; it does
  not hang (unlike an unhandled error inside a Clap command).
- **Parallel headless runs on one image file can collide**: filing in writes to
  the image's `.changes`, and a second VM may fail with "Cannot open non source
  file". For concurrent runs (e.g. several reviewers), use a copy of the stock
  image per run. Kill a stray VM by PID, not by `taskkill /IM`, when other runs
  may be live.
- **`--maxOldSpaceSize=<bytes>` caps the VM heap**, but at the cap the VM logs
  "MaxOldSpaceSize reached", aborts, writes `crash.dmp` (~75 MB) in the working
  directory, and then hangs instead of exiting. A cap is only a backstop.
