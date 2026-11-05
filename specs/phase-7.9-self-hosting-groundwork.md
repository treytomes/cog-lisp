# Spec — Phase 7.9: Self-Hosting Groundwork

| | |
|---|---|
| **Phase** | 7.9 (the last step before Phase 8; README "Before Phase 8") |
| **Status** | Implemented (2026-11-04) — 46/46 + LISP unit tests; all suites 948/948; compile speed 1.2–1.4× (target 2×, §12) |
| **Depends on** | Phases 1–7.8 |
| **Feeds** | Phase 8 (a reader and compiler written in cog-lisp, compiling itself) |
| **Owns** | Review findings C-4 (lambda), C-5, C-18, R-4 (`equal?`, printing), R-20 (strings), R-22; the file ports deferred from 7.8 |

## 1. Goal

Remove what would stop cog-lisp compiling a large program written in itself.
Phase 8's compiler will be thousands of lines of cog-lisp in several files,
with deep expressions, big procedures and cyclic data structures (scopes that
point at each other). Today it would hit five walls: deeply nested calls do not
compile, a procedure cannot take more than 15 parameters, `equal?` and the
printer hang on cycles, a multi-file program cannot `load` its own parts
reliably or read files and stdin, and the compiler is slow to compile itself.
This phase takes them down, one at a time, each with an example.

## 2. Scope

**In scope**
- §4 Compiling deep and wide code: nesting limit (C-5), lambdas with more than
  15 parameters (C-4).
- §5 Files and programs: file ports, reading stdin from LISP, `load` relative to
  the loading file, program arguments, `file-exists?`, `delete-file` (R-22).
- §6 Cycle-safe `equal?` and printing, with R7RS datum labels (R-4).
- §7 String escapes for any character: `\x41;` (R-20).
- §8 Compiler speed: special-form dispatch table and cached message templates
  (C-18), measured.
- Examples for every feature (§10).

**Deferred**
- Procedure documentation strings and hover help (now Phase 10, specs/phase-10-documentation-and-editor.md),
  to be specified with the language server.
- Binary ports and bytevectors.
- Hygienic macros and the numeric tower (Phase 9).

## 3. Decisions

- **Fix limits in the compiler, not by asking programmers to write around
  them.** Phase 8's compiler is ordinary cog-lisp; whatever it is natural to
  write must compile.
- **Ports are one family.** File ports are `LispInputPort`/`LispOutputPort` over
  a file stream, so every 7.8 port procedure works on them unchanged; stdin and
  stdout become ports too.
- **Datum labels for printing cycles** (`#0=(a . #0#)`, R7RS `write`), and the
  reader reads them back, so `write` then `read` round-trips any structure.

## 4. Compiling deep and wide code

### 4.1 Nested calls (review C-5)
Each nested call costs about three stack slots in the procedure's one frame, so
`(f (f (f … )))` about 20 deep fails ("too large or too deeply nested to
compile"). The compiler will **spill**: past a depth budget, it evaluates an
argument into a temporary first (A-normal form, applied only where needed), and
past the frame's temporaries budget it moves a subexpression into a nested
block. Programs of any nesting depth compile; code that never hits the budget
compiles exactly as today (no speed change).

### 4.2 Many parameters (review C-4, lambda)
Pharo blocks take at most 15 arguments. A lambda with more than 15 parameters
(or 15 plus a rest parameter) compiles to a block taking **one array of
arguments**, unpacked into temporaries; `LispProcedure` calls such a procedure
with the array. Callers do not change; it is only slower for those procedures.

## 5. Files and programs (review R-22; deferred from 7.8)

### 5.1 File ports
- `open-input-file path`, `open-output-file path` (creates or truncates),
  `close-port` (and `close-input-port`, `close-output-port`),
  `call-with-input-file path proc`, `call-with-output-file path proc`,
  `with-input-from-file path thunk`, `with-output-to-file path thunk`.
- Every 7.8 port procedure works on them: `read-char`, `peek-char`,
  `read-line`, `read-string`, `read`, `write-char`, `write-string`, `display`,
  `write`, `newline`.
- Text is UTF-8. Relative paths resolve against the directory of the file being
  loaded or run (§5.3), else the current directory.
- `file-exists?`, `delete-file`. A missing file is a `file-error?` condition
  naming the path.

### 5.2 Standard ports
- `(current-input-port)`, `(current-output-port)`, `(current-error-port)`.
- `read`, `read-char`, `peek-char` and `read-line` with no port read **stdin**
  (through `LispStdin`, waiting for input as the REPL does). In the REPL, they
  read the lines after the form being evaluated.

### 5.3 Programs
- `load` resolves a relative path against the **directory of the file doing the
  loading**; at the REPL, against the current directory.
- `(command-line)` answers the program's arguments as a list of strings, the
  program file first: `cog-lisp.bat prog.lisp a b` → `("prog.lisp" "a" "b")`.
  `cog-lisp.bat` and `cog-lisp.sh` pass extra arguments through.
- `(current-load-path)` answers the full path of the file being loaded or run,
  or `#f` at the REPL.

## 6. Cycles (review R-4)

- **`equal?` terminates on cyclic structure** and gives the R7RS answer (two
  cyclic structures that unfold to the same infinite tree are `equal?`). Cost on
  acyclic data: none measurable (a cycle check runs only past a depth or length
  threshold).
- **`write` uses datum labels** when the value has cycles: `#0=(1 2 . #0#)`.
  `display` does the same. Values without cycles print exactly as today (no
  labels for mere sharing; `write-shared`, which labels sharing too, is
  provided).
- **The reader reads datum labels**, `#n=` and `#n#`, so a written cycle reads
  back as an equal cycle.
- The REPL can print a cyclic result instead of hanging.

## 7. String escapes (review R-20)

- The reader accepts `\xHH…;` in strings (any code point) and the R7RS escapes
  `\a` `\b` `\0` already partly supported.
- `write` writes control characters in strings as `\xHH;` (tab, newline and
  return keep `\t` `\n` `\r`), so every string round-trips visibly.

## 8. Compiler speed (review C-18)

- **Special forms dispatch through a table** (`IdentityDictionary` from symbol
  to selector) instead of a chain of string comparisons; adding a form is one
  entry.
- **Message templates are parsed once** per selector and copied, instead of
  re-parsed for every node.
- **Measured:** a new benchmark compiles `lib/core.lisp` plus a 300-line program
  repeatedly; the target is at least **2× faster** compilation than today, with
  generated code byte-identical (the disassembly of a corpus of procedures is
  unchanged).

## 8a. Unit tests written in cog-lisp (added 2026-11-04, owner request)

Phase 8's reader and compiler will be cog-lisp, so their tests should be too.
`lib/test.lisp` is a small test framework, written in cog-lisp:

- `(define-test name body …)` registers a test; `(check expr expected)` compares
  with `equal?`; `(check-true expr)`, `(check-false expr)`;
  `(check-error expr)` passes when `expr` signals an error, and
  `(check-error expr "text")` when its message contains `text`.
- A failing check records the test name, the expression, what it gave and what
  was expected, and the test goes on; an unexpected error fails the test with
  its message.
- `(run-tests)` runs every registered test in order and prints, in the same
  format as the Smalltalk suites, `PASS`/`FAIL` per check and a final
  `== RESULT: n/n checks passed ==`, then exits 0 or 1.
- `tests/lisp/*.lisp` are LISP test files (each loads `lib/test.lisp`, defines
  tests, and calls `(run-tests)`); `testsun-all.bat` runs each with
  `cog-lisp.bat` and counts them like any suite.
- The first LISP test files test 7.8 and 7.9 features (strings, hash tables,
  ports, cycles), so the framework is proven before Phase 8 depends on it.

## 9. Acceptance criteria

**`tests/phase-7.9-groundwork.st`** (headless):
- AC-1 A call nested 200 deep, a `cond` with 50 nested `let`s, and a 100-element
  list built by nested `cons` compile and give the right values.
- AC-2 Code below the nesting budget compiles to the same bytecode as before
  (disassembly of `fib`, `tak` and the Phase 6 corpus unchanged).
- AC-3 Lambdas with 16, 20 and 40 parameters, and 20 plus a rest parameter, are
  called with the right arity checks and values; also as self-loops.
- AC-4 File ports: write a file with `call-with-output-file`, read it back with
  `read-line`, `read-char` and `read`; `with-output-to-file`; `file-exists?`,
  `delete-file`; a missing file is a `file-error?`.
- AC-5 `read`/`read-char`/`read-line` with no port read stdin (driven through a
  `LispStdin` on a file, and in the runner suite with piped input).
- AC-6 `load` from a file in a subdirectory loads its sibling by a relative path;
  `current-load-path` answers the loading file.
- AC-7 `(command-line)` in a runner fixture with extra arguments.
- AC-8 `equal?` on two equal cyclic lists is `#t`, on different ones `#f`, and
  terminates; on acyclic data the result is unchanged.
- AC-9 `write` of a cyclic list, a cyclic vector and a list whose car is itself
  uses labels; `read` of the output gives an `equal?` structure; acyclic values
  print as before.
- AC-10 `"\x3bb;"` reads as λ; control characters in strings write as `\xHH;` and
  read back.
- AC-11 The special-form table and template cache are in place; the
  compile-speed benchmark shows at least 2× (bench), and AC-2 holds.
- AC-12 `lib/test.lisp`: passing and failing checks are reported as specified,
  an error inside a test fails only that test, `check-error` works with and
  without a message, and the exit code is 0 only when all pass (checked by
  running small LISP test files with known failures from the suite).
- AC-13 `tests/lisp/*.lisp` run in `testsun-all.bat` and count in its total.
- AC-14 All earlier suites, the runner suite (with the examples) and the
  benchmarks pass.

## 10. Examples

| Example | Proves |
|---|---|
| `examples/files.lisp` | writing and reading a file with ports: a small CSV round trip, `read-line` loop, `call-with-input-file` |
| `examples/program/main.lisp` + `examples/program/lib/util.lisp` | a two-file program: `load` relative to the loading file, `(command-line)`, `current-load-path` |
| `examples/cycles.lisp` | building a circular list and a graph with back pointers; `write` with datum labels; `equal?` on cycles; reading a labelled datum back |
| `examples/escapes.lisp` | string escapes, `\x…;`, control characters written and read back |
| `examples/big-code.lisp` | a deeply nested expression and a 20-parameter procedure, compiled and run: what a code generator produces |
| `examples/echo.lisp` (runner fixture with `.stdin`) | reading stdin a line at a time from a program: `read-line` until `eof-object?` |

## 11. Resolved decisions

Settled 2026-11-04 (owner sign-off); the spec is Accepted on these.

1. **Datum labels in `write` for cycles only** (R7RS); `write-shared` labels
   sharing too.
2. **Relative file-port paths** resolve against the loading file's directory,
   like `load`.
3. **`read` at the REPL with no port** reads the next lines typed.
4. **Compile speed: at least 2×**, measured by a benchmark.

## 12. As implemented

- **Tests:** `tests/phase-7.9-groundwork.st` 46/46; six examples (`files`,
  `cycles`, `escapes`, `big-code`, `echo` with `echo.input`, and the two-file
  `program/` with `main.args`) in the runner suite (83/83); the first LISP unit
  tests, `tests/lisp/test-data.lisp` (23) and `test-groundwork.lisp` (16), in
  `tests\run-all.bat`. All suites 948/948; benchmarks 13/13, unchanged.
- **AC-11 compile speed: 1.2–1.4×, not 2×** (deviation). Profiling before the
  work showed where compile time goes: about a quarter in cog-lisp's translation
  to a Smalltalk syntax tree, a quarter in Pharo's semantic analysis and half in
  Pharo's bytecode generation. The dispatch table and template cache roughly
  halved translation time, which caps the whole gain near 1.3×; measured over
  three interleaved runs of 60 compilations of 29 forms, 1.38×, 1.24×, 1.20×.
  Reaching 2× needs cog-lisp to stop going through Opal's AST: emitting IR or
  bytecode directly (the `EncoderForSistaV1` option in CLAUDE.md), which is
  Phase 8/9 territory. The benchmark report now records compile time.
- **Nesting spill:** a non-tail form deeper than 10 levels compiles inside
  `[form] value`; each procedure body starts its own budget. Bytecode of code
  within the budget is unchanged, checked against `tests/bytecode-corpus.*`.
- **Long argument arrays** (more than 16 elements) are filled one element at a
  time, found while writing `big-code.lisp`: 26 arguments to a 26-parameter
  procedure overflowed the frame.
- **Packed procedures** (more than 15 parameters) take one Array; they tail-call
  themselves through the trampoline rather than as a loop (their parameters,
  per-iteration copies and scratch temps would not fit one frame). Pharo's limit
  of 64 temporaries per frame still caps a single procedure at about 60
  parameters (a clean compile error beyond).
- **Relative paths** resolve against the loading file's directory and, when the
  file is not there, the current directory, so programs written before 7.9
  (`(load "lib/cl.lisp")` from the repo root) keep working.
- **Stdin** is read through a `LispLineStream` over the REPL's input or the
  runner's `LispStdin`, so `(read)` at the REPL reads the following lines.
  File input ports read the whole file (UTF-8) when opened; output ports write
  through a UTF-8 file stream, closed by `close-port` or the `call-with-`/`with-`
  forms.
- **Datum labels** are parsed directly by the reader (a `#` after the digits
  would otherwise be part of the word, which broke `#0=#(…)`).
- **`equal?`** starts remembering compared pairs past depth 200, so short data
  pays nothing and long lists pay a little.
