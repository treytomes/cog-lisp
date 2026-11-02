# cog-lisp

An **image-based LISP** that compiles to **Cog/Spur bytecode** and runs
JIT-native inside a Pharo image.

The premise: instead of interpreting a syntax tree, cog-lisp compiles each LISP
form into a real `CompiledMethod` — the same object the Smalltalk compiler
produces — installs it into the running image, and lets the **Cog JIT** turn it
into machine code. LISP functions become first-class, inspectable, *persistable*
residents of a live object world. Save the image and your LISP session — every
definition, every compiled function — is still there when you reopen it.

## Why Pharo, why bytecode

The modern Smalltalk VM is **Cog** (a JIT engine) over **Spur** (its object
memory), under the OpenSmalltalk-VM lineage. Pharo ships its own fork of that VM
and — crucially for a compiler — the **Opal** compiler with an intermediate
representation (`IRBuilder`) that assembles bytecode and literal frames for us.
That IR is our compiler backend: we emit IR, Opal hands back a `CompiledMethod`,
Cog runs it native. We deliberately do **not** modify the VM itself.

## Status

| Phase | Name | State |
|------:|------|-------|
| 0 | Foundation & feasibility | ✅ **done** |
| 1 | Reader & printer | ✅ **done** — [spec](specs/phase-1-reader-printer.md), 77/77 |
| 2 | Core data model | ✅ **done** — [spec](specs/phase-2-core-data-model.md), 49/49 |
| 3 | Compiler core | ✅ **done** — [spec](specs/phase-3-compiler-core.md), 31/31 |
| 4 | Runtime & primitives | ✅ **done** — [spec](specs/phase-4-runtime-primitives.md), 44/44 |
| 5 | REPL & image integration | ✅ **done** — [spec](specs/phase-5-repl-runner.md), 28/28 + 28/28 |
| 6 | Optimization & native depth | ⬜ |
| 7 | Language reach (stretch) | ⬜ |
| 8 | Self-hosting (meta-circular) | ⬜ |
| 9 | Pure Lisp image | ⬜ |

Phase 0 is proven, not just planned: [`poc/answer.st`](poc/answer.st) builds
three `CompiledMethod`s directly from Opal IR — a constant, a two-argument add,
and a branching `max` — runs them, disassembles the branch to real SistaV1
bytecode, and JIT-hammers one. 6/6 checks pass. The backend the rest of the
project targets is validated against the live image.

## Getting started

One-time setup: download the Pharo VM and stock image, then build the cog-lisp
image from `src\` (rerun the build after changing anything in `src\`):

```bat
bootstrap-pharo.bat
```

```bat
build-image.bat
```

Run a program:

```bat
cog-lisp.bat examples\factorial.lisp
```

Or start the REPL by running `cog-lisp.bat` with no arguments:

```
> (define (sq n) (* n n))
> (sq 12)
144
> (procedure-source sq)
"(define (sq n) (* n n))"
> (save-image)
```

`(save-image)` writes your definitions into `pharo\cog-lisp.image`, so they are
there the next time you start it. End a session with `(exit)`.
Every procedure keeps the source it was compiled from: `(procedure-source f)`
returns it, and `(disassemble f)` shows its bytecode.

A program's exit code is 0 on success, 1 on an uncaught error (reported on
stderr as `error: …`), or whatever it passes to `(exit n)`. The programs in
[`examples\`](examples/) are a good place to start.

### Running the tests

The in-image suites run headless against the stock image, for example:

```bat
pharo\PharoConsole.exe pharo\Pharo14.0-SNAPSHOT-64bit-58e29ca31d.image st tests\phase-4-runtime.st
```

The runner suite builds the image and drives `cog-lisp.bat` end to end:

```bat
tests\phase-5-runner.bat
```

Headless conventions and the verified Pharo mechanisms are documented in
[`CLAUDE.md`](CLAUDE.md).

---

## Project plan

Development is **spec-driven**: each phase is broken into specification documents
under [`specs/`](specs/), every spec carries explicit **acceptance criteria**, and
each criterion is a headless script that prints `PASS`/`FAIL` (the `poc/answer.st`
pattern). Code follows the spec; when reality disagrees, the spec is corrected
first. See [`specs/README.md`](specs/README.md) for the workflow and index.

### Phase 0 — Foundation & feasibility ✅
Stand up the VM and image; prove the compile-to-`CompiledMethod` pathway end to
end (build-from-IR, execute, arguments, sends, branching, JIT). **Done.**

### Phase 1 — Reader & printer
Turn source text into LISP data and back.
- A tokenizer and an s-expression reader producing an AST of LISP values.
- Support atoms (symbols, integers, floats, strings, characters), lists, dotted
  pairs, `quote`/quasiquote reader macros, comments, and nesting.
- A printer (`write`/`print` semantics) that round-trips.
- *Acceptance:* read-then-print is identity over a corpus of forms.

### Phase 2 — Core data model
The objects the language manipulates.
- Cons cells, interned symbols, the canonical `nil` / `t`, numbers (mapped onto
  Smalltalk's numeric classes), strings, characters.
- The environment model (lexical frames) that Phases 3–4 compile against.
- *Acceptance:* constructor/accessor laws (`car (cons a b) = a`, interning
  identity, etc.) hold.

### Phase 3 — Compiler core
The heart of the project: s-expression → Opal IR → `CompiledMethod`.
- Self-evaluating atoms, variable references, and function application (compiled
  as Smalltalk sends).
- Special forms: `quote`, `if`, `lambda`, `let`, `define`/`defun`,
  `begin`/`progn`, `set!`.
- A LISP function is a compiled method (or closure); calls are real sends, so
  they JIT.
- *Acceptance:* each form compiles to expected bytecode and evaluates to the
  expected value; `if` emits a conditional jump (as in the POC).

### Phase 4 — Runtime & primitives
Make it a usable language.
- Primitives: arithmetic, comparison, list ops (`cons`/`car`/`cdr`/`list`),
  predicates, basic I/O — bound as Smalltalk sends or primitive methods.
- Lexical closures with proper capture (mapping to Smalltalk `BlockClosure`s or
  copied temps).
- Proper argument arity, variadics, and recursion.
- *Acceptance:* a suite of small LISP programs (factorial, map, fold, closures)
  produce correct results.

### Phase 5 — REPL & image integration
The "image-based" payoff.
- An interactive REPL (in the GUI Playground and headless).
- Definitions persist in the image; `save` / reopen restores the full LISP
  session.
- Tooling: inspect and disassemble compiled LISP functions from Smalltalk.
- *Acceptance:* define a function, save the image, reopen, call it — it runs.

### Phase 6 — Optimization & native depth
Go deeper into the VM where it pays.
- Tail-call handling; drop to `EncoderForSistaV1` for exact bytecode control
  where IRBuilder's abstraction is limiting.
- Benchmarks vs. a tree-walking baseline to quantify the JIT win.
- Explore Sista/adaptive-optimization territory (research, optional).
- *Acceptance:* measured speedup over an interpreter baseline; tail-recursive
  loops run in constant stack.

### Phase 7 — Language reach (stretch)
- Macros (compile-time expansion), a richer numeric tower, a condition/restart
  error system, and two-way interop with Smalltalk objects.
- *Acceptance:* defined per sub-feature spec when the phase is reached.

### Phase 8 — Self-hosting (meta-circular)
Reimplement cog-lisp **in cog-lisp**: rewrite the reader and the compiler — the
latter emitting the same `CompiledMethod`s through a LISP-level interface to the
Opal IR — in the language itself, bootstrapped by the Smalltalk-hosted
implementation of Phases 1–4 (and macros from Phase 7).
- The Smalltalk-hosted compiler compiles the cog-lisp-written compiler once; from
  then on the system compiles its own source.
- This is the real proof the language is complete: it can express its own
  front end and code generator.
- *Acceptance:* the self-hosted reader and compiler reproduce the Smalltalk-hosted
  implementation's output on the Phase 1–4 corpora, **and** the compiler compiles
  itself to a fixpoint (the compiler built by stage 2 produces byte-identical
  output to the one built by stage 3).

### Phase 9 — Pure Lisp image
Make the cog-lisp image stand on its own, so the stock Pharo image is not needed.
- Start from what the VM requires (its kernel objects and classes:
  `nil`/`true`/`false`, `SmallInteger`, `Array`, `CompiledMethod`,
  `BlockClosure`, …) plus cog-lisp.
- **Audit every other Pharo subsystem before removing anything.** For each one —
  networking, UI, file system, the IDE tools — decide to **keep** it, **reimplement
  it in LISP**, or **remove** it, based on what the world needs. Networking is
  expected to stay in some form: it is how an AI agent gets into and out of the
  world. Reimplementing a subsystem in LISP is preferred where practical, so the
  world can read and change it.
- The Opal dependency goes once code generation emits bytecode directly (Phase 6)
  and the compiler is written in LISP (Phase 8).
- Build new images from an existing cog-lisp image, or from a bootstrapped kernel,
  instead of from the stock download.
- Build cog-lisp's own VM executables in place of the stock `Pharo.exe` and
  `PharoConsole.exe` (for example with `--headless` as the default, which the
  launch scripts must pass explicitly today).
- *Acceptance:* a cog-lisp image built without the stock image runs the example
  programs and the acceptance suites, and the user-visible world is LISP.
