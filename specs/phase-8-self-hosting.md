# Spec — Phase 8: Self-Hosting

| | |
|---|---|
| **Phase** | 8 |
| **Status** | Implemented (2026-11-04): steps 8.1–8.6 done |
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
| 8.2 Reader in LISP | **done** — `lib/compiler/reader.lisp`, built into the image; matches `LispReader` on 52 Phase 1 inputs, 88 feature and error inputs and all 59 `.lisp` files (`tests/phase-8.2-reader.st`, 204 checks); 57 LISP unit tests; 1211/1211 in all |
| 8.3 Compiler in LISP | **done** — `lib/compiler/opal.lisp` and `compiler.lisp`, built into the image; byte-identical to `LispCompiler` on the corpus (also with each optimization off), 37 path forms, 36 malformed forms and every top-level form of `lib/` and `examples/` (`tests/phase-8.3-compiler.st`, now compared by fingerprint, see step 8.4); 25 LISP unit tests; 2278/2278 in all |
| 8.4 Bootstrap and fixpoint | **done** — `lib/compiler/bootstrap.lisp`; stages 0–3 make identical methods for all 225 forms of the compiler's source (`tests/lisp/phase-8.4-bootstrap.lisp`, 18 checks; `examples/bootstrap.lisp`); 2336/2336 in all |
| 8.5 Switch-over | **done** — eval, load, the REPL, the runner and `read` use the LISP reader and compiler, sealed; `COGLISP_COMPILER=smalltalk` goes back; every suite, example and LISP test passes both ways (2384/2384 each), benchmarks 14/14; compile time 1.2× (AC-7); `examples/sealed-compiler.lisp` |
| 8.6 Direct code generation | **done** — `lib/compiler/codegen.lisp` writes bytecode itself; compiling the benchmark's 29 forms takes 17.1 ms against 36.4 ms for the Smalltalk compiler (2.1×; Phase 7.9: 36.3 ms); run-time benchmarks equal or faster; fixpoint of the new generator holds (stages 1 = 2 = 3); 2506/2506 both ways |

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

### Step 8.2
- **`lib/compiler/reader.lisp` mirrors `LispReader` procedure for procedure**
  (`rd-list-body` is `readListBodyFrom:`, `rd-send-form` is `sendFormFrom:at:`,
  …), so a difference between the two points at one place. It produces the
  same objects (`LispCons`, interned symbols, read-only Arrays, `LispLabelHole`
  filling for datum labels) and signals the same `LispReadError` (made through
  interop) with the same message, position and incomplete flag.
- **Interface.** `(make-reader string)`, `(reader-next r)` (a datum or the eof
  object), `(reader-datum-start r)`, `(reader-position r)`,
  `(reader-source-for r list)` and `(reader-range-of r list)` (the same 1-based
  ranges as `sourceFor:`), plus `(read-all string)`, `(read-from-string string)`
  and `(read-datum port)`.
- **Deviation from §4.2: it reads a string, not a port.** The state is the text
  and an offset, as in the Smalltalk reader (whose stream is over the text).
  `read-datum` reads a string or file port by reading its `ReadStream`'s text
  from the stream's position and setting the position after the datum, as the
  `read` primitive leaves it. Ports with no text behind them (stdin, a
  `LispLineStream`) fall back to `read`.
- **The build loads it** after `lib/core.lisp` (`build/build.st`, a list of
  `lib/compiler/` files for 8.3 to extend); the VS Code stale-image check
  watches `lib/compiler/*.lisp` too. It binds 67 global names: the interface
  above and `rd-` helpers. No `.lisp` file in the repository defines any of
  them, but a program that redefines one changes the reader, as with any
  global; a namespace for the compiler's own names is a question for 8.5.
- **The comparison** (`tests/phase-8.2-reader.st`) runs both readers over each
  input and compares event lists: for each datum its start and end offsets and
  its shape (every list with its source text, every vector with its size and
  read-only flag, every atom with its class and printed form, shared and
  cyclic structure as `#seen`), then the end position or the error's class,
  message, position and incomplete flag. A failure names the first differing
  event. Four control checks prove the comparison sees a difference in source
  text, in an error position, and between `1` and `1.0`.
- **Unit tests** (`tests/lisp/phase-8.2-reader.lisp`, 57 checks): every datum
  kind, brackets, comments, labels and cycles, source ranges, error messages
  with positions and incompleteness, `read-datum` on a port, and the reader
  reading its own file. Example: `examples/read-yourself.lisp`.
- **Speed: about 21× slower than `LispReader`** (456 ms against 22 ms for the
  72 K characters of `lib/` and `examples/`). Matching was this step's goal;
  AC-7 (compile time within 1.5× after 8.5) will need it faster. Likely
  remedies: accessors as macros instead of procedure calls, reading through
  the text's `ReadStream` by `send`, and table lookups for character classes.
- `tests\run-all.bat` now takes about 1 m 40 s on this machine (the runner 27 s,
  the LISP tests 16 s, this suite 10 s).

### Step 8.3
- **Two files.** `lib/compiler/opal.lisp` builds Opal nodes through interop
  (`opal-literal`, `opal-var`, `opal-assign`, `opal-send` with its own template
  cache, `opal-block`, `opal-thunk`, `opal-brace`, `opal-method-node`,
  `opal-generate`, `opal-run`). `lib/compiler/compiler.lisp` has one procedure
  per `LispCompiler` method, in the same order, named after it (`lc-translate-if`
  is `translateIf:inScope:tail:`).
- **The state is a vector** passed first, where the Smalltalk has `self`; a scope
  is a Smalltalk `IdentityDictionary`, as there. Unwinding uses Smalltalk's own
  `ensure:`, `ifCurtailed:` and `on:do:` through interop, so a compile error
  restores state exactly as in the Smalltalk compiler.
- **Order is part of the output.** Temporary names (`l1`, `l2`, …) appear in the
  generated code, so every name and every translation is made in the Smalltalk
  method's order: `let*` and a strictly left-to-right `lc-map`, never `map`.
- **Special forms are a LISP table** (`define-special-form`), as
  `LispCompiler class>>specialForms` is a Smalltalk one; adding a form needs no
  Smalltalk (`examples/extend-the-compiler.lisp`).
- **Interface.** `(compile-form datum [source-map [context]])` answers a
  `CompiledMethod`, as `compile:context:` (`source-map` a LISP or Smalltalk
  reader); `(lisp-eval datum [source-map])` evaluates as `eval:` does, a
  top-level `begin` or macro call form by form; `(lisp-eval-string s)` reads with
  the LISP reader and evaluates each form, so procedures keep their text.
- **One deliberate difference: which errors pass through.** The Smalltalk
  compiler turns a host error during translation into "bad syntax" but lets any
  `LispError` through. The LISP compiler lets only `LispCompileError` through,
  since a primitive's `LispError` (`car: not a pair`) raised inside the compiler
  plays the part a host error does there. The malformed-form corpus shows the
  messages agree.
- **The comparison** (`tests/phase-8.3-compiler.st`) compiles each form with both
  compilers and compares them as the bytecode corpus does: the `symbolic`
  listing of the method and of every block in its literals, or the error. Each
  compiler starts from the same gensym counter, since both expand the macros in
  the form. Forms of `lib/` and `examples/` are visited as `eval` sees them (a
  `begin`'s forms and a macro call's expansion are top-level forms), with the
  reader as source map; definitions run, so later forms compile in the same
  world, but nothing else does (examples read input and write files).
- **The forms written for the compiler's limits found a bug** the corpus and the
  834 library forms did not: a `let` of more than 15 bindings, where
  `for-each` was called with two lists (cog-lisp's takes one).
- **Speed: 1.26× the Smalltalk compiler** (57 ms against 45 ms for the 29 forms
  of the compile benchmark), because Opal's semantic analysis and code
  generation dominate both. Within AC-7's 1.5× already, before reading.
- **For 8.5: the compiler's procedures are globals.** A program that redefines
  `append` or `cons` (as `tests/lisp/phase-7-macros.lisp` does) would change the
  compiler once it compiles everything. Macros do not matter (the compiler is
  compiled before they are defined); procedure calls through global cells do.
  8.5 needs the compiler's own references bound to the primitives it was built
  with.
- Examples: `examples/compile-yourself.lisp` (compile, run, disassemble, compare
  with the Smalltalk compiler, read the compiler's own source) and
  `examples/extend-the-compiler.lisp` (a `repeat` special form, and one that
  rejects bad syntax).
- `tests\run-all.bat` takes about 2 m 30 s (this suite about 25 s).

### Step 8.4
- **`lib/compiler/bootstrap.lisp`** runs the stages. `(bootstrap-compiler dir)`
  compiles every top-level form of `compiler-sources` (`reader.lisp`,
  `opal.lisp`, `compiler.lisp`) with stage 0 (`LispCompiler`, reading with
  `LispReader`) and with stage 1 (the image's LISP compiler, reading with the
  LISP reader); installs stage 1's methods, making stage 2; compiles again;
  installs, making stage 3; compiles again. It answers the four stages'
  fingerprints and leaves stage 3 installed. `(bootstrap-differences b i j)`
  names the forms that differ; `(bootstrap-fixpoint? b)`.
- **A stage is compiled completely before it is installed.** The compiler calls
  its own procedures through global cells, so installing as it went would have
  the new compiler compile the rest of itself. The driver is not among the
  sources, so installing never replaces it mid-run.
- **Result: stages 0, 1, 2 and 3 make identical methods** for all 225 forms of
  the compiler's source. Stage 3 then compiles as `LispCompiler` does, reads,
  runs programs, and its procedures keep their source. A check that
  `compile-form` is a different procedure afterwards shows the stages really
  were installed.
- **Forms are visited as `eval` sees them** (a `begin`'s forms and a macro
  call's expansion are top-level forms), and each starts from the same gensym
  counter in every stage, as in the 8.3 suite.
- **A bug found in the 8.3 comparison, and fixed.** Pharo cannot produce the
  `symbolic` listing of many nested blocks in these methods: printing a block
  literal looks up its source node, and the lookup lands on an `OCSequenceNode`
  (`does not understand #sourceNodeForPC:`), 326 times in the compiler's own
  source. The 8.3 suite caught every error into a string, so where both
  compilers' listings failed it compared two identical error texts and passed.
  Both comparisons now use a **fingerprint** instead (`method-listing` here, the
  same rule in `tests/phase-8.3-compiler.st`): each method's header, its bytecode
  bytes, and every literal, blocks recursively. That is stricter than the
  listing, and an error while taking it now fails the check. With fingerprints
  the 8.3 suite still passes in full (the compilers did agree) and runs in 11 s
  instead of 25. The 8.3 LISP unit tests and `examples/compile-yourself.lisp`
  use `method-listing` too. The Phase 7.9 corpus test keeps `symbolic`, which
  works for its forms and is pinned by its `.expected` file.
- Example: `examples/bootstrap.lisp` runs the bootstrap from its own location
  and reports each stage (about 5 s).
- `tests\run-all.bat` takes about 2 m 10 s.

### Step 8.5
- **The switch is on `LispCompiler`'s class side.** `implementation` answers
  `#lisp`, or `#smalltalk` when the environment variable `COGLISP_COMPILER` is
  `smalltalk`, read once per image session. `compile:context:` and
  `eval:context:steps:` delegate to LISP entry procedures (`lisp-compile-from`,
  `lisp-eval-from`) when the LISP compiler is in use; `LispReader on:` (and so
  `read:`, `readAll:`, `evalAll:`, the REPL, the `read` primitive and
  `string->number`) answers a `LispReaderInLisp`, LispReader's protocol over
  the LISP reader, for a string or a `ReadStream` over one (a stream is left just
  after what was read); stdin's line stream still goes to the Smalltalk reader.
  The Smalltalk ones stay reachable as `smalltalkCompile:context:`,
  `smalltalkEval:context:steps:` and `LispReader basicOn:`, which stage 0 of
  the bootstrap and the 8.2/8.3 comparisons now use (they would otherwise
  compare the LISP versions with themselves). `(compiler-implementation)`
  answers `lisp` or `smalltalk`.
- **The build installs it with the fixpoint check**
  (`installLispCompilerWithFixpoint`): `lib/core.lisp` and `lib/compiler/` loaded
  by stage 0, the bootstrap of step 8.4 run (the build fails if the stages
  differ), then the result sealed and made the one in use. It takes about 12 s.
  A **stock image installs it on demand** at its first compile, without the
  bootstrap, so every Smalltalk suite runs on the LISP compiler too; the
  harness prints which one a suite ran on (`== compiler: lisp ==`). Installing
  restores the gensym counter, so it is invisible to the program that caused it
  (the Phase 7.9 bytecode corpus pins gensym names).
- **Sealing**, for the namespace problem found in 8.3: every global cell the
  compiler's code reads, found by walking the code of the values of every name
  `reader.lisp`, `opal.lisp` and `compiler.lisp` define (and the procedures in
  the special-form table), is replaced by a private cell holding the value it
  has then (`LispGlobal>>frozenCopy`). A program may now define `append`, `cons`,
  `make-reader`, even `lc-translate-if`: only the program sees it. Extending
  the compiler still works through `define-special-form`, since the table is
  shared and only the cell holding it is private. Changing the compiler's code
  means editing `lib/compiler/` and rebuilding. `bootstrap.lisp` is not sealed:
  it must see the stages it installs. `Smalltalk vm voidCogVMState` afterwards,
  in case machine code holds the old cells.
- **A bug the seal exposed, fixed:** `make-hash-table` recognized `eq?`, `eqv?`
  and `equal?` by identity with what those names were bound to at the moment,
  so the sealed reader's `eq?` was refused after `LispPrimitives installDefault`
  made new primitives (the benchmark does), and a program's own `eq?` would have
  been taken for the real one. The primitives are now registered, weakly, as
  they are made, and a table knows its test by the procedure itself.
- **The reader is about 4× faster** (751 ms to 164 ms over the 136 K characters
  of `lib/` and `examples/`, against 46 ms for the Smalltalk reader: from 16× to
  3.9×), found by profiling, not guessing: the variadic `char=?` built an
  argument list for every character comparison, and `vector-ref` and
  `string-ref` were calls with checks. Characters (immediate objects) are now
  compared with `eq?`, which compiles to `==`; the per-character accessors are
  macros over Smalltalk sends (`at:`, `asInteger`); character classes come from
  a 128-entry table. The 8.2 comparison passes unchanged. (A first attempt,
  macros alone, gained only 20%.)
- **Results.** Every suite, example and LISP test passes with the LISP
  compiler (2384/2384) and again with `COGLISP_COMPILER=smalltalk` (2384/2384);
  `tests\run-all.bat` names the implementation in its header. Benchmarks 14/14
  with the LISP compiler; compile time 1.2× the Smalltalk compiler's (AC-7,
  1.5× allowed); reading the compile benchmark's 6.8 K characters 5.8× (a
  reader's set-up cost weighs more on small text). Run-time benchmarks are
  unchanged within noise (the bytecode is the same). AC-6: `procedure-source`
  works on the compiler's own procedures, and compile-error messages and the
  runner's `path:line:col` positions are unchanged (the runner suite).
- **The 8.3 comparison now tests the installed, sealed compiler**
  (`LispCompiler entries at: #compile`) rather than a copy it loaded from
  source. The new example redefines `cons` and `append`, and the suite runs the
  examples' definitions, which broke the unsealed copy: the suite was testing a
  compiler nothing uses.
- Tests: `tests/lisp/phase-8.5-switch-over.lisp` (17 checks, either way).
  Example: `examples/sealed-compiler.lisp` (the same output either way).

### Step 8.6
- **Measured first.** Of the LISP compiler's 43–48 ms for the benchmark's 29
  forms, translation to Opal nodes took 11–15, semantic analysis 9–11 and code
  generation 21–24, spread over hundreds of small costs (parent walks, option
  checks, IR sequences, collection growth). Only replacing the AST, the analysis
  and the IR together could halve it.
- **The translator is unchanged.** `lib/compiler/opal.lisp` now builds light
  trees (`#(lit x)`, `#(var name)`, `#(assign name node)`, `#(send receiver
  selector args)`, `#(block args temps statements)`, `#(brace elements)`,
  `#(method node)`) instead of Opal's nodes, behind the same `opal-*` procedures,
  and `opal-generate` compiles a tree one of two ways: `direct`
  (`lib/compiler/codegen.lisp`, the default) or `opal` (the tree converted to
  exactly the Opal AST of 8.3, compiled by Opal). `(set-code-generator! 'opal)`
  switches, in the sealed compiler too (the setting is a box).
- **`codegen.lisp` does Opal's work for the translator's trees** and writes the
  bytes with Pharo's own `EncoderForSistaV1`. Analysis in evaluation order
  decides each variable's place: a frame temporary, a value copied into a
  closure, or a slot of a temp vector (a variable written after a closure has
  captured it, or written by another frame), made when its scope is entered, so
  a loop body gets a fresh one each time round. A loop is analyzed twice, so a
  write early in the body counts as after a capture late in the previous
  iteration. The blocks of `ifTrue:`, `ifTrue:ifFalse:` and `whileTrue:` are
  inlined; a block that captures nothing becomes a `CleanBlockClosure` (or
  `ConstantBlockClosure`) made once at compile time, as Opal does. Each branch is
  emitted on its own first, so every jump's distance is known when it is
  written. String literals are made read-only, as Opal makes them.
- **Better code than Opal's, in three places:** `(LispCore isTruthy: x)
  ifTrue:...` is an inline `x == false` test; `true ifTrue: [...]`, the
  translator's sequencing, is just its statements; and a global that is bound at
  compile time is read with `pushLiteralVariable` (a `LispGlobal`'s value is its
  second slot, where the VM reads a binding's value) instead of a send of
  `value`. A cell is never unbound again, so only a forward reference needs the
  checked send. `LispGlobal>>key` answers its name for the tools that list such
  code. Also, in the runtime: `pair?` and `symbol?` are inlined as one send
  (`isLispPair`, `isLispSymbol` on `Object`) instead of a call that runs
  `isKindOf:`.
- **The generator's own speed** came from what the profile named: record fields
  through macros over `at:`/`at:put:` sends, not checked `vector-ref`; selector
  symbols and global bindings cached by the translator's literal strings.
- **Results.** Compiling the 29 forms: 17.1 ms, against 36.4 ms for the
  Smalltalk compiler in the same run, 2.1× faster (Phase 7.9: 36.3 ms, so 2.1×
  that too); on busier runs 1.8–2.2×. The benchmark checks a 1.5× margin. Run-time
  benchmarks are equal or faster (loop 100000: 1.97 to 1.04 ms; tak 2.81 to 2.02;
  globals 2.67 to 1.75), within noise elsewhere. Reading got faster too, since
  the reader runs on generated code: 3.7× the Smalltalk reader, from 5.8×.
- **The fixpoint for the new generator:** stages 1, 2 and 3 make the same
  methods (`bootstrap-fixpoint?` compares stage 0 only through Opal, whose code
  stage 0 shares); the build checks it, and `tests/lisp/phase-8.4-bootstrap.lisp`
  runs both bootstraps. A bootstrap keeps the generator it started with across
  the stages it installs.
- **Byte-identity with the Smalltalk compiler is still checked, through Opal:**
  `tests/phase-8.3-compiler.st` and the 8.3 LISP tests switch to `opal`. The
  Phase 7.9 corpus test now pins the Smalltalk compiler's code
  (`smalltalkCompile:context:`), which it was written to check.
- **Bugs found on the way:** a loop's second analysis pass made a new frame for
  a closure in the loop body while the inlined scopes inside it kept the old one
  (found by compiling the compiler's own source: `(let loop () ...)` around a
  `let`); `examples/compile-yourself.lisp` compared the LISP compiler with itself
  (plain `compile:` delegates since 8.5).
- Tests: `tests/lisp/phase-8.6-codegen.lisp` (23 checks, either way): closures
  in loops, shared captured variables, letrec, loops in a `let`, truth, globals
  as they are now and forward references, big and deep code, the frame limit,
  read-only literals. Examples: `bootstrap.lisp` runs both bootstraps;
  `compile-yourself.lisp` shows both generators.
- Owner, 2026-11-04: 1.8× would have been accepted as done; the cheap last round
  (accessors, caches, two inlined predicates) reached 2.1×.
