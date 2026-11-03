# Spec — Phase 5: REPL, Runner & Image

| | |
|---|---|
| **Phase** | 5 |
| **Status** | Implemented (2026-11-02) — `tests/phase-5-shell.st` 28/28, `tests/phase-5-runner.bat` 30/30 (36/36 with the Phase 7 examples); Phases 1–4 still green |
| **Depends on** | Phases 1–4 |
| **Feeds** | Phase 6 (optimization), Phase 7 (language reach), Phase 8 (self-hosting) |
| **Image strategy** | Build a dedicated `cog-lisp.image` once; the runner and REPL start from it |

## 1. Goal

Make cog-lisp something you **use from the host OS**: build a cog-lisp image,
run a `.lisp` program from a Windows command line, and work interactively in a
REPL whose definitions can be **saved into the image** and are still there next
time. This is the phase where the project's image-based premise becomes visible.

## 2. Scope

**In scope**
- **Build:** `build-image.bat` produces `pharo\cog-lisp.image` (+ `.changes`) from
  the stock image by loading `src/` and installing the primitive library.
- **Runner:** `cog-lisp.bat program.lisp` compiles and runs a program, with its
  output on stdout and a meaningful exit code.
- **REPL:** `cog-lisp.bat` with no file starts a read-eval-print loop on
  stdin/stdout.
- **Persistence:** a `(save-image)` primitive snapshots the running image, so
  definitions survive a restart.
- **Language support the runner needs:** `load`, `exit`, `disassemble`, and a
  dedicated **unspecified value** (§5).
- **Source retention:** every compiled procedure keeps the exact source text it
  was compiled from, and that text survives `save-image` (§5.2).
- **Examples:** an `examples/` folder of small programs that run end to end.
- An acceptance suite that drives the real `.bat` entry points.

**Deferred**
- A GUI REPL (a cog-lisp Playground or Spec presenter) — later.
- Line editing / history in the REPL (stdin is read raw).
- Per-call environments (`eval:in:`, deferred here from Phase 3): neither the
  runner nor the REPL needs one. Re-deferred until a concrete use appears.
- Non-Windows launch scripts.

## 3. Decisions

- **Image strategy (settled):** build once, run from the built image. Startup
  skips loading `src/`, and saved state persists. The cost is a rebuild after any
  change to `src/`; the runner warns when `src/` is newer than the image (§6).
- **Lean on Pharo for the command line.** Entry is a Pharo **command-line
  handler** registered in the image (`PharoConsole.exe cog-lisp.image lisp …`),
  the same mechanism Pharo uses for `st` and `eval`. The `.bat` files are thin
  wrappers around it.
- **The stock image is never modified.** The build saves to a new image name;
  tests that save use a throwaway copy.
- **Nothing at run time depends on the stock image.** The stock image is needed
  only to *build* `cog-lisp.image`. This keeps the path open to the Phase 9 goal
  of a pure Lisp image, where the stock image is not needed at all; the build
  script is where image shrinking will later happen.

## 4. Components

### 4.1 `build-image.bat`
1. Requires `bootstrap-pharo.bat` to have run (stock image present).
2. Copies the stock image to `pharo\cog-lisp.image` (exact mechanism probed:
   Pharo's `save <name>` command, or a file copy).
3. Runs `build/build.st` in it: files in the four `src/` packages, installs the
   primitive library and the Phase 5 additions, records a build timestamp, and
   saves (`Smalltalk snapshot: true andQuit: true`).
4. Prints the image path and package load results. Idempotent: rebuilding
   replaces the previous `cog-lisp.image`.

### 4.2 `cog-lisp.bat`
```
cog-lisp.bat                 start the REPL
cog-lisp.bat program.lisp    run a program, then exit
```
- **Run mode:** reads the file, evaluates every top-level form in order (`evalAll`
  semantics). Output from `display`/`write`/`newline` goes to stdout. Exit code
  **0** on success; **1** on an uncaught LISP error, after printing
  `error: <message>` to stderr. The image is not saved.
- **REPL mode:** prompt `> `; reads one complete datum (it may span lines), evals
  it, prints the value with `write`, and loops. The unspecified value is not
  printed. An error prints `error: <message>` and the loop continues. EOF or
  `(exit)` ends the session; the image is saved only if `(save-image)` was called.
- **Missing image:** if `pharo\cog-lisp.image` does not exist, say so and tell the
  user to run `build-image.bat`. If any `src/*.st` file is newer than the image,
  print a one-line warning but run anyway.

### 4.3 New package `CogLisp-Shell`
- `LispShellCommand` — the `lisp` command (`lisp run <file>`, `lisp repl`). (First
  planned as a `LispCommandLineHandler`; Pharo 14 dispatches Clap commands, see
  §10.)
- `LispRepl` — the read-eval-print loop over a read stream and a write stream, so
  it is testable without a console.

## 5. Language additions

| Name | Behavior |
|---|---|
| unspecified value | A singleton `LispUnspecified default`, printed as `#<unspecified>`. Returned by `define`, `set!`, a one-armed `if` whose test is false, `display`/`write`/`newline`, `for-each`, `set-car!`/`set-cdr!`, and `load`. It replaces the Phase 3 placeholder (the empty list), so `(if #f 1)` no longer looks like `()`. |
| `(load "path")` | Read and evaluate every form in a file, relative to the current directory. |
| `(exit)` / `(exit n)` | End the process with code 0 / `n`. |
| `(save-image)` | Snapshot the running image in place and keep running. |
| `(disassemble f)` | Print the bytecode of `f`'s compiled block (`symbolic`), the Phase 0 view applied to LISP procedures. |

The unspecified-value change revises Phase 3 AC-7 and some Phase 4 checks; those
suites are updated to expect `LispUnspecified default`, and the Phase 3 spec is
annotated, as was done for the Phase 4 calling convention.

### 5.1 What the unspecified value is, and is not

- It is a **first-class value**. It can be bound (`(define y (if #f #f))`),
  passed, stored in a list, and compared with `eq?`. That is Scheme semantics,
  and it means it can end up assigned to things.
- It is **not "undefined"**. A variable with no binding is an *error*
  (`LispUnboundError`), never a value. Unspecified only means "this form has no
  useful result".
- It is **truthy**, like every value except `#f`.
- It is **visible**: it prints as `#<unspecified>`, so it shows up if it leaks
  into data. Only the REPL suppresses printing it, and only for a top-level
  result.
- It will **not** double as an "uninitialized variable" marker. When internal
  `define` / `letrec` arrive, using a variable before it is initialized must be
  an error; any marker that needs is separate and internal and never escapes as
  a value.

### 5.2 Source retention

Compiled code keeps its source, so the image can always show and (later) rewrite
its own definitions.

- **The reader records source ranges.** While reading, `LispReader` records the
  start and end offset of every list it reads, in an identity table keyed by the
  cons. `LispReader` keeps the source string alongside it.
- **The compiler attaches source to procedures.** When a `lambda` form compiles,
  its exact source text (a substring of the input, comments and formatting
  included) is passed to the `LispProcedure` constructor as a literal. For
  `(define (f …) …)` the text is the whole `define` form. Forms built by the
  compiler itself (such as the lambda that `let` desugars into) have no text of
  their own and fall back to the printed form.
- **Source lives in the image, not in side files.** It is an instance variable
  of `LispProcedure`, so it persists with `save-image` and does not depend on
  Pharo's `.sources` / `.changes` files, which a pure Lisp image (Phase 9) will
  not have.
- **`(procedure-source f)`** returns the text as a string. Primitives return
  `#f` (they have no LISP source).

## 6. Mechanism probes (before implementation)

Each is checked against the live image first and recorded in CLAUDE.md, as with
Opal in Phases 0 and 3:
1. Registering a command-line handler in Pharo 14 (classic `CommandLineHandler`
   subclass vs. a Clap command), and reading its arguments.
2. Saving a copy of the image under a new name headlessly.
3. Reading `Stdio stdin` line by line in `PharoConsole.exe`, including piped input.
4. Exiting with a specific process exit code, and writing to stderr.

## 7. Examples (`examples/`)

Small programs written for this project, each runnable with `cog-lisp.bat`:
- `hello.lisp` — `display` and `newline`.
- `factorial.lisp` — recursion, printing a table of results.
- `lists.lisp` — `map`, `append`, `reverse`, and a recursive list function.
- `closures.lisp` — a counter built from a closure and `set!`.

## 8. Acceptance criteria

Two suites:
- **`tests/phase-5-shell.st`** (headless, like earlier suites) for `LispRepl`
  driven by in-memory streams and for the language additions.
- **`tests/phase-5-runner.bat`** for the real entry points. It runs fixtures in
  `tests/runner/` through `cog-lisp.bat`, compares stdout to `.expected` files
  (`fc`), checks exit codes, and prints `PASS`/`FAIL` and `RESULT: n/n`.

**Build**
- AC-1 `build-image.bat` creates `pharo\cog-lisp.image`; the stock image is
  unchanged.
- AC-2 The built image has all five packages loaded and the primitives installed
  (checked by running a one-line program).

**Runner**
- AC-3 `cog-lisp.bat examples\hello.lisp` prints the expected text and exits 0.
- AC-4 A program with several definitions and a final `display` prints the
  expected output (fixture vs `.expected`).
- AC-5 A program that raises an unbound-variable error prints `error: …` to
  stderr and exits 1.
- AC-6 `(exit 3)` makes the process exit with code 3.
- AC-7 Every program in `examples/` runs and matches its `.expected` output.

**REPL**
- AC-8 Piped input `(+ 1 2)` prints `3`.
- AC-9 A multi-line datum is read as one form.
- AC-10 `(define x 5)` prints nothing; `x` then prints `5`.
- AC-11 An error prints `error: …` and the next form still evaluates.
- AC-12 EOF ends the session with exit code 0.

**Persistence (the image-based payoff)**
- AC-13 On a throwaway copy of the image: session 1 defines `(define (sq n) (* n
  n))` and calls `(save-image)`; session 2, a new process on the same image,
  evaluates `(sq 7)` → `49`.

**Language additions**
- AC-14 `(if #f 1)` evaluates to `LispUnspecified default`; `(define y 1)` too.
- AC-15 `(load "…")` evaluates a file's definitions.
- AC-16 `(disassemble sq)` prints bytecode text (it contains `send:`).

- AC-17 The unspecified value can be bound and retrieved: `(define u (if #f #f))`
  then `(eq? u (if #f #f))` → `#t`; reading an unbound variable still raises
  `LispUnboundError`.

**Source retention**
- AC-18 `(define (sq n) ; square it` / `(* n n))` then `(procedure-source sq)`
  returns the exact text of the `define` form, comment and line break included.
- AC-19 An anonymous `lambda` keeps its own text: `(procedure-source (lambda (x)
  (+ x 1)))` → `"(lambda (x) (+ x 1))"`.
- AC-20 `(procedure-source car)` → `#f`.
- AC-21 Source survives a save: in the AC-13 persistence test, session 2's
  `(procedure-source sq)` returns session 1's text.

**Regression**
- AC-22 All earlier suites pass (Phases 1–4, with the unspecified-value updates).

**Definition of done:** both Phase 5 suites pass, earlier suites pass, and
running an example from a Windows prompt works as documented in the README.

## 9. Resolved decisions

Settled 2026-11-02 (owner sign-off); the spec is Accepted on these.

1. **Command shape.** `cog-lisp.bat file.lisp` runs a program; no argument starts
   the REPL.
2. **Image location.** `pharo\cog-lisp.image`, beside the stock image and its
   `.sources` file (already gitignored).
3. **Unspecified value.** Introduce `LispUnspecified` now and update the earlier
   suites; the empty-list placeholder is retired.
4. **REPL prompt and output.** Prompt `> `, results printed with `write`, errors
   as `error: <message>`.
5. **`save-image` saves in place.** No save-as for now.
6. **Source granularity.** Every `lambda` keeps its own text, nested ones
   included, not only top-level definitions.

## 10. As implemented

Where the implementation settled details the spec left open, or reality forced
a change:

- **The VM is launched with `--headless`.** Without it the VM appends
  `--interactive` to the image's arguments, Pharo attaches an SDL2 OS window at
  every startup, and its drawing failures print to stdout at unpredictable
  moments. `build-image.bat` and `cog-lisp.bat` pass `--headless`, so no window
  is ever created. Details and the other probe results (Clap commands,
  `Smalltalk exit:`, the snapshot resume guard, stdin decoding) are in CLAUDE.md.
- **Command entry** is `LispShellCommand`, a Clap command (`lisp repl`,
  `lisp run <file>`), not a classic `CommandLineHandler`, which Pharo 14's
  dispatcher ignores.
- **Snapshots are guarded.** Both the build (`saveAs: 'cog-lisp'`) and
  `(save-image)` terminate the saving process on the resume path, so it cannot
  run on in the next session.
- **`LispUnspecified`** lives in `CogLisp-Reader`, beside the other value types,
  so the printer can write it.
- **Output port.** `display`, `write`, `newline` and `disassemble` write to
  `LispPrimitives output` (stdout by default); `LispPrimitives withOutput:do:`
  redirects it, which is how the REPL and the in-image tests capture output.
- **Incomplete input.** `LispReadError>>isIncomplete` is true when the input ran
  out (unterminated list, string, comment); the REPL keeps reading on those and
  reports the rest.
- **The REPL reads stdin through `LispStdin`, which waits for input.** Pharo's
  stdin never blocks and reports "no input yet" the same way as end of input, so
  the first version failed at an interactive console ("Incomplete input for
  character decoding") and ended at once when piped input arrived late.
  `LispStdin` asks Windows whether stdin is a console, pipe, or file to decide
  when input has really ended, and polls otherwise. A console is read with
  `ReadConsoleW` instead, because the VM never reads a console at all (typed
  keys were not even echoed). The runner suite checks late-arriving input; the
  console path was verified by injecting keystrokes with `WriteConsoleInputW`.
- **Output is encoded through `LispTextOutput`.** Pharo's `Stdio` streams write a
  string's internal representation, so non-ASCII text came out garbled.
  `LispTextOutput` writes to a console with `WriteConsoleW` (UTF-16) and to pipes
  and files as UTF-8. The runner suite checks UTF-8 in a program's source and
  output; console output was verified by reading back the screen buffer.
- **REPL errors** go to stderr, like run-mode errors; results and program output
  go to stdout.
- **`cog-lisp.bat`** exits 2 if the image is missing, and honours
  `COGLISP_IMAGE` to run a different image (the persistence test uses a copy).
  The staleness warning is done inside the image, which compares `src/*.st`
  modification times with its recorded build time.
- **The build smoke-tests** the image before saving and refuses to save if any
  package fails to load.
- **Runner fixtures**: `tests/runner/NAME.lisp` (program) or `NAME.stdin` (REPL
  input), with optional `NAME.expected` (exact stdout), `NAME.exitcode`, and
  `NAME.stderr` (required substring). Examples keep their `.expected` beside them.
  `.gitattributes` keeps these LF so byte-exact comparison is stable.

## 11. Downstream notes

- Phase 6's benchmarks can run as `cog-lisp.bat bench.lisp`, so performance work
  is measured through the real entry point.
- Phase 7's macros and Common-Lisp-flavored forms become testable as plain
  `.lisp` files, which is the natural way to work through *ANSI Common Lisp*.
- A saved image with accumulated definitions is the first concrete form of the
  "body that persists" in the project's north star.
- **Phase 9 (pure Lisp image)** builds on the image strategy chosen here: shrink
  the built image to the VM's kernel plus cog-lisp, and eventually build new
  images from an existing cog-lisp image rather than from the stock download.
