# Spec — Phase 8: Self-Hosting

| | |
|---|---|
| **Phase** | 8 |
| **Status** | Accepted (2026-11-04) |
| **Depends on** | Phases 1–7.9 |
| **Feeds** | CI/CD, Phase 9 (the pure LISP image: Opal can go once code generation is LISP) |
| **Shape** | Six steps, 8.1–8.6, each committed and green before the next (§4) |

## 1. Goal

Rewrite cog-lisp's **reader** and **compiler** in cog-lisp, so the language
compiles itself. The Smalltalk-hosted reader and compiler (Phases 1–7.9)
compile the LISP-written ones once; from then on the image compiles its own
source, and keeps doing so after changes to it.

This is the proof the language is complete: it can express its own front end
and code generator. It is also the turn of the north star: the part of the
world that turns text into running code becomes LISP the world can read and
change.

What stays Smalltalk in this phase: the runtime (`LispProcedure`, primitives,
conditions, ports), the data classes (`LispCons`, `LispSymbol`, …), the shell,
and Pharo's code generation underneath (until §4.6).

## 2. Scope

**In scope**
- 8.1 Moving language-behavior tests from Smalltalk to LISP (owner request).
- 8.2 The reader in LISP.
- 8.3 The compiler in LISP: special forms, macro expansion, quasiquote,
  internal define, tail calls and self-loops, guarded inlining, global cells,
  nesting spill, packed lambdas, source retention, error messages.
- 8.4 Bootstrap and fixpoint.
- 8.5 Switch-over: the built image reads and compiles with the LISP versions.
- 8.6 Direct code generation for the 2× compile-speed goal (§10, question 1).
- Examples (§9).

**Deferred**
- Rewriting the runtime and primitives in LISP, and removing Opal and the stock
  image: Phase 9.
- Hygienic macros and the numeric tower: Phase 9.
- A language server: later (README).

## 3. Decisions

- **Mirror, then improve.** The LISP compiler first reproduces the Smalltalk
  compiler's output exactly (same Opal nodes, so byte-identical methods), which
  makes every difference a bug with a precise location. Improvements (8.6)
  come only after the fixpoint holds.
- **Through interop.** The LISP compiler builds Opal nodes with `send` and
  `(smalltalk OCLiteralValueNode)`, a small library (`lib/compiler/opal.lisp`)
  over Phase 7.6 interop: Phase 8's "LISP-level interface to the Opal IR".
- **The LISP sources live in `lib/compiler/`** (`reader.lisp`, `opal.lisp`,
  `expand.lisp`, `compiler.lisp`, …), loaded by the build after `lib/core.lisp`,
  with their own LISP unit tests in `tests/lisp/`.
- **The Smalltalk reader and compiler stay** as the bootstrap and as an
  independent reference until Phase 9; the built image uses the LISP ones after
  8.5, with a switch back for diagnosis.

## 4. Steps

### 4.1 Step 8.1 — tests in LISP
- Every check in `tests/phase-3` … `phase-7.9-*.st` that only evaluates LISP and
  compares the result moves to `tests/lisp/phase-N.lisp` (`lib/test.lisp`), keeping
  its meaning and its spec reference (`AC-n` in the test name).
- The Smalltalk suites keep only what LISP cannot test about itself: the reader
  and core (Phases 1–2), the bytecode corpus, compiler options, the REPL, stdin
  and break-loop plumbing, the `CogLisp` facade from Smalltalk, the test
  framework's self-test.
- **No check is lost:** a count before and after shows every moved check present
  once (`tests\run-all.bat` totals by suite, plus a list of moved test names).
- From here on, language behavior is tested in LISP.

### 4.2 Step 8.2 — the reader in LISP
`lib/compiler/reader.lisp`: everything `LispReader` does, over string ports —
numbers, symbols, strings and escapes, characters, booleans, lists and dotted
pairs, vectors, quote and quasiquote abbreviations, brackets (Smalltalk sends),
comments, datum labels, **source ranges** for lists (for source retention), and
read errors with the same messages, positions and *incomplete* flag.
- `(read-datum port)` / `(read-all string)`; it makes the same objects
  (`LispCons`, interned `LispSymbol`s, Arrays, …).
- **Checked against the Smalltalk reader** on the Phase 1 corpus and on every
  `.lisp` file in the repository: identical datums (`equal?`, and identical
  printed form), identical errors.

### 4.3 Step 8.3 — the compiler in LISP
`lib/compiler/*.lisp`: everything `LispCompiler` does, the same way, emitting
the same Opal nodes through `opal.lisp`. Organized by concern: scopes and names,
special forms (a table, as in Phase 7.9), macro expansion, quasiquote, bodies
and internal define, lambdas (self-loops, packed), calls (fast calls, tail
calls, guarded inlining), sends, globals and cells, the nesting spill, source
retention, compile errors.
- `(compile-form datum)` answers a `CompiledMethod`, as `LispCompiler>>compile:`.
- **Checked against the Smalltalk compiler**: the bytecode corpus and every
  top-level form of `lib/` and `examples/` compile to byte-identical methods
  (literals compared by the same rules as the corpus test).

### 4.4 Step 8.4 — bootstrap and fixpoint
- **Stage 0** is the Smalltalk compiler. It compiles `lib/compiler/*.lisp`,
  giving **stage 1**: the LISP compiler, running as compiled code.
- Stage 1 compiles `lib/compiler/*.lisp` again, giving **stage 2**; stage 2
  compiles it, giving **stage 3**.
- **Fixpoint:** the methods stage 2 produces for the compiler's own source are
  byte-identical to stage 3's, and stage 1's are identical to stage 0's.

### 4.5 Step 8.5 — switch-over
- The build compiles `lib/compiler/` with stage 0, checks the fixpoint, and
  makes the LISP reader and compiler the ones `eval`, `load`, the REPL and the
  runner use. `(compiler-implementation)` answers `lisp` or `smalltalk`;
  `COGLISP_COMPILER=smalltalk` selects the old one for diagnosis.
- Every suite, example, LISP test and benchmark passes with the LISP compiler,
  and again with the Smalltalk one.

### 4.6 Step 8.6 — direct code generation (2× compile speed)
With the fixpoint holding, the LISP compiler stops building Opal's AST (whose
semantic analysis and code generation are three quarters of compile time, Phase
7.9 §12) and emits code through `OCIRBuilder` directly, or bytecode with
`EncoderForSistaV1`. Generated code may now differ from the Smalltalk
compiler's; correctness is checked by every suite and the fixpoint (stage 2 vs
3 of the new generator). Target: compiling the benchmark's forms at least **2×
faster than Phase 7.9** (36 ms then), with run-time benchmarks no slower.

## 5. Interface to the image (Smalltalk side)

`LispCompiler` keeps its Smalltalk API (`compile:`, `eval:`, `evalAll:`,
`evalFile:`), so the shell, `CogLisp` facade and tests do not change; after 8.5
it delegates to the LISP compiler. Same for `LispReader read:`.

## 6. Errors and source

- Compile and read errors from the LISP versions carry the same messages and
  positions (`path:line:col: error: …` works unchanged).
- Every procedure of the compiler keeps its source (`procedure-source` on any
  part of the compiler shows its LISP text).

## 7. Performance

- After 8.5 (mirroring Opal): compile time within 1.5× of the Smalltalk
  compiler; run-time benchmarks unchanged (same bytecode).
- After 8.6: the 2× target of §4.6.

## 8. Acceptance criteria

- AC-1 (8.1) LISP test files per phase in `tests/lisp/`; every moved check
  accounted for; Smalltalk suites trimmed; all pass.
- AC-2 (8.2) The LISP reader matches the Smalltalk reader on the Phase 1 corpus
  and every `.lisp` file in the repository, including errors, positions,
  incompleteness and source ranges; it has its own LISP unit tests.
- AC-3 (8.3) The LISP compiler produces byte-identical methods to the Smalltalk
  compiler on the bytecode corpus and every top-level form in `lib/` and
  `examples/`; its own LISP unit tests pass.
- AC-4 (8.4) Stage 0 = stage 1 and stage 2 = stage 3 on the compiler's own
  source, checked by a suite.
- AC-5 (8.5) With the LISP compiler as default, every suite, example, LISP test
  and benchmark passes; also with `COGLISP_COMPILER=smalltalk`.
- AC-6 (8.5) `procedure-source` works on the compiler's own procedures;
  compile-error messages and positions are unchanged.
- AC-7 (§7) Compile time with the mirrored LISP compiler within 1.5× of the
  Smalltalk one.
- AC-8 (8.6) Compile time at least 2× faster than Phase 7.9; fixpoint holds for
  the new generator; run-time benchmarks no slower.

## 9. Examples

| Example | Proves |
|---|---|
| `examples/read-yourself.lisp` | the LISP reader reading this very file and printing its forms |
| `examples/compile-yourself.lisp` | compiling a procedure with the LISP compiler, running it, disassembling it; the compiler's own source via `procedure-source` |
| `examples/extend-the-compiler.lisp` | adding a special form to the running compiler from LISP (an `unless`-like form compiled directly), and using it — the compiler is part of the world |

## 10. Resolved decisions

Settled 2026-11-04 (owner sign-off); the spec is Accepted on these.

1. **8.6 is in this phase**, last, after the fixpoint holds.
2. **Byte-identical to the Smalltalk compiler** is the 8.3 check.
3. **The built image switches to the LISP compiler at 8.5**;
   `COGLISP_COMPILER=smalltalk` goes back.
4. **One commit per step**, each green, with a status line per step below.

## 11. Step status

| Step | Status |
|---|---|
| 8.1 Tests in LISP | **done** — 412 checks moved to `tests/lisp/phase-*.lisp` (list: `tests/lisp/moved-checks.txt`); the total stays 948/948, suite by suite |
| 8.2 Reader in LISP | not started |
| 8.3 Compiler in LISP | not started |
| 8.4 Bootstrap and fixpoint | not started |
| 8.5 Switch-over | not started |
| 8.6 Direct code generation | not started |

## 12. As implemented

### Step 8.1
- `tests/lisp/convert-suites.py` moved every check that only evaluates LISP and
  compares the result (or expects an error) from the Phase 3–7.9 suites into
  `tests/lisp/phase-N.lisp`, one `define-test` per check, named by its label
  (spec references kept). 412 checks moved; 5 that depend on running inside a
  Smalltalk test (a top-level `abort` restart and a load path exist under the
  runner; one needs a Smalltalk-side definition) stayed. The script is kept as
  the record of the move; it is not meant to be run again.
- **Definitions travel both ways.** A check that stays in Smalltalk but defines
  something is copied into the LISP file as a setup; a check that moves but
  defines something stays behind in the suite as a guarded setup. That keeps
  every suite's state as it was.
- **`lib/test.lisp` gained what the moved checks need:** `eval-all` (compile and
  run a string at top level through the compiler, so procedures keep their source
  text), `check-written`, `check-error-class`; `define-test` now compiles its body
  when the test runs (a test can use macros defined by earlier tests); and the
  framework holds its own references to `+`, `display`, … so a test that
  redefines one cannot break the reporting.
- Checks that compile LISP at test time (definitions, expected compile errors,
  source retention) are written as `(eval-all "…")`; the rest as plain code.
