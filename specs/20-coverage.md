# Code coverage for LISP programs

| | |
|---|---|
| **Status** | Done (2026-11-09). Accepted with the decisions as proposed |
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
  - **Corrected 2026-11-09, while starting the step:** the compiler already has
    them. `load` reads a file with one reader and passes it to the compiler
    with each form (`LispCompiler>>eval:from:`), which keeps it as its source
    map (`c-source-map`) to give each procedure its exact source text. So
    `(reader-range-of (c-source-map c) form)` gives a probe its range. The
    earlier text said the loader did not pass the reader on; it does.
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
  - The compiler takes the range from its source map, the reader that read the
    file (§2). A form typed at the REPL, or built by a program, has no range;
    its probe names the file (or the REPL) and the form's text instead.
- **R-4. The recorder,** a small runtime library:
  - `(coverage-start [files])` begins a session, optionally only for some
    files;
  - `(coverage-stop)` ends it and answers its counts;
  - `(coverage-report counts [port])` writes, by file, the procedures and
    branches never run, with their lines.
  - Sessions do not mix.
- **R-5. Not instrumented:** the compiler, the recorder, and `lib/test.lisp`.
- **R-6. A whole run:** `COGLISP_COVERAGE=1` makes the launcher start a session
  before the program loads, and write the report to stderr when the program
  ends, or calls `exit`.
  - `run-tests` ends with `exit`, so a test run's report comes from there.
  - `run-tests` itself prints nothing more (changed 2026-11-09, while starting
    the step: two reports for one run would only repeat each other).
- **R-7. What a session covers:** the code compiled while it runs, since the
  probes are placed then. `(coverage-start)` comes before `load`, which
  `COGLISP_COVERAGE` does for a whole program.
  - Not instrumented by default: cog-lisp's own `lib/` (the test library,
    `cl.lisp`), whose code is not the program's.

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

## 5. As built (2026-11-09)

- **The recorder is `lib/coverage.lisp`**, loaded by the build after
  `lib/format.lisp` and before the compiler.
  - It holds `coverage-start`, `coverage-stop` and `coverage-report`, documented
    under "Evaluation and macros".
  - A probe is a record, `#(count kind file source start end text)`, made by
    `%coverage-register` while the form compiles.
  - The compiled code counts into it with `rec at: 1 put: (rec at: 1) + 1`. That
    is a literal and a send: no new class, no temporary, no frame.
- **The compiler** (`lib/compiler/compiler.lisp`): `lc-probe-record` and its
  helpers.
  - Each procedure gets an entry probe after its parameters are bound.
  - Each `if` gets a probe in each branch's block.
  - Both are added only when the option is on. The build's fixpoint showed
    "forms where the seed's code differs from the new compiler's: 0", so with
    the option off the compiler makes exactly the code it made before (AC-4,
    off).
- **Placing a side of an `if`:** at its test first, then at the nearest form
  being compiled that the reader has a range for.
  - The first try used only the second. Then a `cond` clause's untaken side was
    reported at the enclosing `define`. The `if` that `cond` makes has no range,
    but its test is the clause's own, from the reader.
  - A `guard` clause is a `cond` clause, so it is covered with no probe of its
    own.
- **`exit` and the end of a program** now call `LispPrimitives runAtExit`. It
  runs `%at-exit` once, if a library set it; `COGLISP_COVERAGE` sets it to write
  the report.
- **The shell** calls `%coverage-from-environment` at the start of each run,
  with `*env*`.
- **A self-call is a loop**, so a procedure's entry counts once per call from
  outside, not once per turn. A million turns ran with coverage on, in constant
  space.
- **Paths are reported as the program loaded them**, so a library loaded as
  `../../lib/x.lisp` shows that way. Not normalized yet.
- **Checks:**
  - `tests/lisp/coverage.lisp`, 23/23 (AC-1 to AC-4, R-7);
  - `lisp-expert`'s suites with `COGLISP_COVERAGE=1`, which pass unchanged
    (113/113, 36/36, 4/4) and report their uncovered code by file and line
    (AC-5);
  - every suite, run again with `COGLISP_COVERAGE=1` (AC-4, on).

## 6. Risks

- **Frame size** (CLAUDE.md: 64 temporaries, pushed values included). Probes
  must not push values that stay on the stack.
- **The self-hosting rule.** The compiler's own source may use only what the
  seed supports. Adding the option does not use it.

## 7. Decisions (owner, 2026-11-09: as proposed)

1. **Branch probes in the first version, or procedure entries only?** Proposed:
   both. `if` is a single place in the compiler.
2. **The report's form:** proposed text, by file, uncovered lines first. A
   machine-readable form (LCOV) is for later, if an editor or CI wants it.

## 8. Across runs (2026-11-10)

Asked for by the owner (2026-11-10): `lisp-expert`'s `run-tests` checks its
coverage over all its suites. A suite is a process of its own, so one run's
report cannot speak for the others, and three things got in the way:

- the report was text, which cannot be added up;
- a file loaded twice in one run (a test reloading a module to reset it) made a
  second set of probes, and the copy that ran was reported beside the copy that
  did not;
- paths were as the program wrote them (`..\knowledge-base.lisp`,
  `..\..\expert\knowledge-base.lisp`), so one file had several names.

Requirements:

- **R-8. One probe per place:** `coverage-stop` answers one record for each
  file, line, column and kind, its count the sum of every copy's.
- **R-9. Full paths:** a record's file is its full, canonical path.
- **R-10. The counts as data:** with `COGLISP_COVERAGE_DATA` set to a file, a
  whole run (R-6) also writes its counts there, one record per line, as
  `write` writes them, so `read` reads them back.
- **R-11. `(coverage-merge counts ...)`** adds up several runs' counts by R-8's
  rule, for `coverage-report`.

Acceptance: `tests/lisp/coverage.lisp` checks R-8 (a file loaded twice), R-9,
R-10 and R-11; `lisp-expert`'s `run-tests` reports its coverage across its
suites.
