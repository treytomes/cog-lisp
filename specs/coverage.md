# Code coverage for LISP programs

| | |
|---|---|
| **Status** | Accepted (2026-11-09), with the decisions as proposed |
| **Asked for by** | `~/projects/lisp-expert/TODO-COVERAGE.md`, which needs the change in cog-lisp's compiler, not in a project |

## 1. The need

A test suite should be able to report which of a program's procedures and
branches ran, and which did not. That is visible only inside the compiled code,
so the compiler must place the probes. `lisp-expert` planned this, and
correctly noted that its test library cannot do it alone.

## 2. What cog-lisp has already (checked 2026-11-09)

- **Source positions.** The LISP reader keeps a source range for every list it
  reads: the 1-based first and last character, by list identity
  (`reader-range-of`, `lib/compiler/reader.lisp`). The language server already
  turns these ranges into lines and columns to underline errors (10.5).
  - What is missing: `load` (`LispCompiler>>evalFile:`) does not hand the reader
    that read the file to the compiler, so compiled code cannot know its own
    positions yet.
- **The file being loaded.** It is known while compiling (`LispLoadPath`, which
  documentation categories already use).
- **Compiler options.** `LispCompiler` has named options (`allOptions`,
  `withoutOptions:do:`), and the compiler tests them with `lc-uses?`. Every
  current option is on by default.
- **Each procedure's source text.** It is kept (`procedure-source`).
- **Pharo's own coverage tools** probe installed Smalltalk methods. cog-lisp's
  procedures are closures in methods that are never installed in a class, so
  those tools do not see them.

## 3. Requirements

- **R-1. A `coverage` compiler option, off by default.**
  - With it off, the compiled code is exactly what it is today. The bytecode
    fingerprints (`method-listing`) are unchanged, and the build's fixpoint is
    unaffected.
- **R-2. Probes**, placed by the compiler when the option is on:
  - one at each procedure's entry;
  - one on each side of every `if`, which is what `cond`, `case`, `when`,
    `unless`, `and` and `or` expand to;
  - one at each `guard` clause.
  - A probe is a statement before the body. It adds no stack frame and keeps
    tail calls tail calls.
- **R-3. A probe's identity:**
  - the file, and the character range of the form it stands for, turned into
    line and column in reports;
  - code a macro expanded is attributed to the macro's use, the nearest form
    that has a range.
  - The loader passes the reader's ranges to the compiler (the gap in §2).
- **R-4. The recorder,** a small runtime library:
  - `(coverage-start [files])` begins a session, optionally only for some
    files;
  - `(coverage-stop)` ends it and answers its counts;
  - `(coverage-report counts [port])` writes, by file, the procedures and
    branches never run, with their lines.
  - Sessions do not mix.
- **R-5. Not instrumented:** the compiler, the recorder, and `lib/test.lisp`.
- **R-6. The test runner:** `lib/test.lisp`'s `run-tests` reports coverage when
  a session is running. `COGLISP_COVERAGE=1` makes the launcher start one for a
  whole run, and write the report to stderr at the end.

## 4. Acceptance criteria

- **AC-1:** a procedure that is called is counted, and one that is not is
  reported uncovered, with its line.
- **AC-2:** both sides of an `if`, a `cond` and a `case`, nested, are counted
  and reported separately.
- **AC-3:** a macro's expansion is attributed to its use; a closure's body to
  its `lambda`.
- **AC-4:** with the option on, every suite's results are unchanged, and tail
  calls still run in constant space. With it off, `method-listing` of every form
  in `lib/compiler/` is unchanged.
- **AC-5:** `lisp-expert`'s suites run with `COGLISP_COVERAGE=1`, and the report
  names its uncovered code.

## 5. Risks

- **Frame size** (CLAUDE.md: 64 temporaries, pushed values included). Probes
  must not push values that stay on the stack.
- **The self-hosting rule.** The compiler's own source may use only what the
  seed supports. Adding the option does not use it.

## 6. Decisions (owner, 2026-11-09: as proposed)

1. **Branch probes in the first version, or procedure entries only?** Proposed:
   both. `if` is a single place in the compiler.
2. **The report's form:** proposed text, by file, uncovered lines first. A
   machine-readable form (LCOV) is for later, if an editor or CI wants it.
