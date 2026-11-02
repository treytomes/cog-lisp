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
| 1 | Reader & printer | 📋 [spec accepted](specs/phase-1-reader-printer.md) |
| 2 | Core data model | ⬜ |
| 3 | Compiler core | ⬜ |
| 4 | Runtime & primitives | ⬜ |
| 5 | REPL & image integration | ⬜ |
| 6 | Optimization & native depth | ⬜ |
| 7 | Language reach (stretch) | ⬜ |
| 8 | Self-hosting (meta-circular) | ⬜ |

Phase 0 is proven, not just planned: [`poc/answer.st`](poc/answer.st) builds
three `CompiledMethod`s directly from Opal IR — a constant, a two-argument add,
and a branching `max` — runs them, disassembles the branch to real SistaV1
bytecode, and JIT-hammers one. 6/6 checks pass. The backend the rest of the
project targets is validated against the live image.

## Getting started

```bat
bootstrap-pharo.bat
```

downloads and unpacks the Pharo 14 VM + image into `pharo\` (not committed; see
`.gitignore`) and prints the versions. Then run the proof-of-concept:

```bat
pharo\PharoConsole.exe pharo\Pharo14.0-SNAPSHOT-64bit-58e29ca31d.image st poc\answer.st
```

Headless conventions and the verified Opal API are documented in
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
