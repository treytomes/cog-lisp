# cog-lisp

[![CI](https://github.com/treytomes/cog-lisp/actions/workflows/ci.yml/badge.svg)](https://github.com/treytomes/cog-lisp/actions/workflows/ci.yml)

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
| 5 | REPL & image integration | ✅ **done** — [spec](specs/phase-5-repl-runner.md), 28/28 + 36/36 |
| 6 | Tail calls & optimization | ✅ **done** — [spec](specs/phase-6-optimization.md), 127/127, [benchmarks](bench/results.md) |
| 7 | Macros & derived forms | ✅ **done** — [spec](specs/phase-7-macros.md), 115/115 |
| 7.5 | Review & tooling | ✅ **done** — [spec](specs/phase-7.5-review-and-tooling.md), [review](specs/review-phases-1-7.md), [VS Code](vscode/README.md) |
| 7.6 | Smalltalk interop | ✅ **done** — [spec](specs/phase-7.6-smalltalk-interop.md), 82/82, [examples](examples/interop-send.lisp) |
| 7.7 | Conditions & restarts | ✅ **done** — [spec](specs/phase-7.7-conditions-restarts.md), 54/54, [examples](examples/restarts.lisp) |
| 7.8 | Strings, characters, vectors & hash tables | ✅ **done** — [spec](specs/phase-7.8-native-data.md), 58/58, [examples](examples/tiny-reader.lisp) |
| 7.9 | Self-hosting groundwork | ✅ **done** — [spec](specs/phase-7.9-self-hosting-groundwork.md), 46/46, LISP unit tests ([`lib/test.lisp`](lib/test.lisp)); all suites 948/948 |
| 8 | Self-hosting (meta-circular) | ✅ **done** — [spec](specs/phase-8-self-hosting.md); 8.1 tests in LISP, 8.2 reader and 8.3 compiler in LISP, 8.4 the compiler compiles itself to a fixpoint, 8.5 the LISP reader and compiler are the ones in use, 8.6 it writes bytecode itself, compiling 2.1× faster than Phase 7.9 ([`lib/compiler/`](lib/compiler/), examples [read-yourself](examples/read-yourself.lisp), [compile-yourself](examples/compile-yourself.lisp), [extend-the-compiler](examples/extend-the-compiler.lisp), [bootstrap](examples/bootstrap.lisp), [sealed-compiler](examples/sealed-compiler.lisp)) done; all suites 2506/2506, with either compiler |
| 8.9 | CI/CD, and running on Linux | ✅ **done** — [spec](specs/phase-8.9-ci-cd.md); every push tested on Linux (both compilers) and Windows; a `v*` tag publishes Linux and Windows bundles and the `.vsix` |
| 9 | Finishing the language: seeded builds, the numeric tower, hygienic macros | ✅ **done** — [spec](specs/phase-9-language.md); 9.1 seeded builds, 9.2 the numeric tower, 9.3 hygienic macros (examples [seeded-build](examples/seeded-build.lisp), [numbers](examples/numbers.lisp), [new-number-type](examples/new-number-type.lisp), [syntax-rules](examples/syntax-rules.lisp), [shadowing](examples/shadowing.lisp)) |
| 10 | A world of its own: the pure LISP image, then networking and graphics from LISP | ⬜ [spec](specs/phase-10-pure-image.md) accepted in outline |

Phase 0 is proven, not just planned: [`poc/answer.st`](poc/answer.st) builds
three `CompiledMethod`s directly from Opal IR — a constant, a two-argument add,
and a branching `max` — runs them, disassembles the branch to real SistaV1
bytecode, and JIT-hammers one. 6/6 checks pass. The backend the rest of the
project targets is validated against the live image.

## Installing a release

Each [release](https://github.com/treytomes/cog-lisp/releases) has a bundle for
Linux and one for Windows (x86-64), with the Pharo VM, the cog-lisp image, the
LISP library and the examples: unpack it and run `./cog-lisp.sh` (Linux) or
`cog-lisp.bat` (Windows). The VS Code extension is the release's `.vsix`.
`INSTALL.md` in the bundle has the details.

## Getting started

To build from a checkout instead, on Windows or Linux. One-time setup: download
the Pharo VM and the seed (an earlier cog-lisp release, pinned in `pharo.pins`),
then build the cog-lisp image from `src\` and `lib\`: the seed's compiler
compiles the new one (rerun the build after changing anything in `src\`,
`lib\core.lisp` or `lib\compiler\`). Each script has a bash equivalent, for Linux
and for Git Bash on Windows (`bootstrap-pharo.sh`, `build-image.sh`,
`cog-lisp.sh`, `tests/run-all.sh`); on Linux, use those:

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

At a console, an error does not throw your work away: it opens a **break loop**
inside the computation that failed, and lists the ways to recover (Phase 7.7):

```
> (+ undefined-var 1)
error: unbound variable: undefined-var
restarts: use-value store-value abort
1> (use-value 41)
42
```

`(store-value 5)` would define the variable and go on; `(abort)` returns to `>`.
Programs and piped input report errors without stopping.
Every procedure keeps the source it was compiled from: `(procedure-source f)`
returns it, and `(disassemble f)` shows its bytecode.

A program's exit code is 0 on success, 1 on an uncaught error (reported on
stderr as `path:line:col: error: …`), or whatever it passes to `(exit n)`. The programs in
[`examples\`](examples/) are a good place to start.

### Running the tests

Run every suite (about 2 minutes) with:

```bat
tests\run-all.bat
```

or `tests/run-all.sh` on Linux. GitHub Actions runs them on every push, on Linux
and on Windows ([`ci.yml`](.github/workflows/ci.yml)); pushing
a tag `vMAJOR.MINOR.PATCH` builds and publishes a release
([`release.yml`](.github/workflows/release.yml)).

The in-image suites run headless on a copy of the built image (`tests\run-all.bat`
makes a fresh one for each), for example:

```bat
copy /y pharo\cog-lisp.image pharo\suite.image & copy /y pharo\cog-lisp.changes pharo\suite.changes
pharo\PharoConsole.exe --headless pharo\suite.image st tests\phase-4-runtime.st
```

The runner suite builds the image and drives `cog-lisp.bat` end to end:

```bat
tests\phase-5-runner.bat
```

The benchmarks compare compiled cog-lisp with a tree-walking interpreter and
hand-written Smalltalk, and write [`bench/results.md`](bench/results.md):

```bat
bench\run-benchmarks.bat
```

Headless conventions and the verified Pharo mechanisms are documented in
[`CLAUDE.md`](CLAUDE.md).

### The Pharo build

cog-lisp builds against one exact Pharo: the Pharo 14 image build 788
(`58e29ca31d`) and the Pharo VM v12.0.6-beta (commit `bebdbac`), pinned with their
SHA-256 checksums in [`pharo.pins`](pharo.pins). The bootstrap scripts, CI and
the release bundles all use those files and check every download against its
checksum. To move to a newer Pharo, change a URL and its checksum together, run
the bootstrap, and run every suite.

The image is built from a **seed**, an earlier cog-lisp release pinned the same
way (`SEED_TAG`, `SEED_URL`, `SEED_SHA256`; Phase 9 step 9.1). Its compiler
compiles the new compiler, which then compiles itself to a fixpoint;
`(image-build-info)` shows how the running image was built
([example](examples/seeded-build.lisp)). If a seed is ever lost,
`scripts/rebuild-seed.sh` rebuilds it from its tagged source, the way it was
built; CI does that on every push.

## License

cog-lisp is released under the [MIT license](LICENSE). Release bundles also
carry the Pharo image (MIT, with parts under Apache 2.0), the Pharo VM (MIT),
libffi (MIT) and, on Windows, winpthreads (MIT and BSD), with each license's full
text in the bundle's `licenses/` folder. They leave out the third-party libraries
in the VM archives that cog-lisp does not use (graphics, Git, OpenSSL and
others). See the [third-party notices](release/THIRD-PARTY-NOTICES.md); the
license texts are in [`release/licenses/`](release/licenses/), with
[how they were chosen](release/licenses/README.md) (what the VM loads, what was
left out and what that costs), and the list of VM files a bundle ships is in
[`release/package.sh`](release/package.sh).

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

### Phase 7 — Macros & derived forms
- `define-macro` (non-hygienic, with `gensym`), quasiquote, internal `define`,
  and the standard derived forms (`cond`, `and`/`or`, `let*`, named `let`, `do`,
  …) written in cog-lisp itself. An optional `lib/cl.lisp` adds Common Lisp
  names for working through *ANSI Common Lisp*.
- `lib/core.lisp` is loaded into `cog-lisp.image` by the build; load the CL
  library with `(load "lib/cl.lisp")`. Its known gaps: `nil` and `()` are
  **true** (only `#f` is false), so test a list with `null` or `consp`, not
  plain `if`; there is one namespace and no `#'f` (write `f`); no `loop`,
  `format`, keywords, multiple values, `&optional` or `&key`.
- *Acceptance:* see the [Phase 7 spec](specs/phase-7-macros.md).

### Phase 7.5 — Review & tooling
A consolidation phase before self-hosting, with no new language features.
- **Review of Phases 1–7:** a full review of the first seven phases (specs, code,
  tests, build, and the Pharo findings in CLAUDE.md) to see what we would do
  better with what we know now. Each finding is fixed now, planned for a named
  phase, or kept with a reason, in `specs/review-phases-1-7.md`.
- **VS Code integration:** a local extension (`vscode/`, installed from a
  `.vsix`) with syntax highlighting, bracket handling, run file, a REPL in the
  integrated terminal, and send-form-to-REPL. Plus a plan for a language server
  served by the image itself: hover with procedure source, completion from the
  globals, diagnostics, macro expansion.
- *Acceptance:* see the [Phase 7.5 spec](specs/phase-7.5-review-and-tooling.md).

### Before Phase 8 (in this order; each numbered when specified)
Phase 8 rewrites the reader and compiler in cog-lisp, and today that code could
not be written: LISP cannot look inside a string, keep a table, build an Opal
node, or raise and catch an error. These come first (decided 2026-11-03):
- **Smalltalk interop** — ✅ done as Phase 7.6 ([spec](specs/phase-7.6-smalltalk-interop.md)): `[coll add: x]`, `(send d at:put: k v)`, `(smalltalk Dictionary)`. Call Smalltalk from LISP (send messages
  to Smalltalk objects, reach classes and globals) and LISP from Smalltalk (a
  LISP procedure usable as a block, which must drive its own tail calls; review
  R-18). The way into the rest of the image, into the subsystems Phase 10 may keep
  or reimplement, and Phase 8's "LISP-level interface to the Opal IR".
- **Conditions and restarts** — ✅ done as Phase 7.7 ([spec](specs/phase-7.7-conditions-restarts.md)): `guard`, `with-exception-handler`, `restart-case`, and a break loop at the console REPL. A LISP-level error system: `error`, condition
  objects, handlers, and restarts, with host errors mapped to conditions (review
  R-2, C-18). Before the primitives below, so they signal proper conditions.
- **Native strings, characters, vectors and hash tables** — ✅ done as Phase 7.8 ([spec](specs/phase-7.8-native-data.md)), with string ports and `read`: what a reader and a
  compiler written in LISP need (`string-ref`, `substring`, `string->symbol`,
  `string->number`, `char->integer`, character predicates, string building,
  vectors, hash tables), as **native primitives** in cog-lisp's runtime rather
  than LISP names over Smalltalk objects: the world stays readable in LISP
  (Phase 10), and the fixpoint check is simpler without host objects in the loop.
- **Self-hosting groundwork** — ✅ done as Phase 7.9 ([spec](specs/phase-7.9-self-hosting-groundwork.md)), with unit tests written in cog-lisp (`lib/test.lisp`, `tests/lisp/`): the review findings marked *plan → self-hosting*
  (`specs/review-phases-1-7.md`): calls nested ~20 deep (C-5), lambdas with
  more than 15 parameters (C-4), cycle-safe `equal?` and printing (R-4), string
  escapes for control characters (R-20), `load` relative to the loading file and
  program arguments (R-22), and the compiler's special-form dispatch and
  template parsing (C-18).

### Phase 8 — Self-hosting (meta-circular)
[Spec accepted](specs/phase-8-self-hosting.md). It starts by moving the
language-behavior tests from Smalltalk to LISP (owner, 2026-11-04), so the
self-hosted reader and compiler are checked against the same tests. Step 8.1
(tests in LISP) and step 8.2 (the reader in LISP, matching the Smalltalk reader
on every input and every `.lisp` file in the repository) are done, and so is step
8.3: the compiler in LISP, which compiles every form in `lib/` and `examples/`
to the same bytecode as the Smalltalk compiler; and step 8.4: compiled by
itself, twice, it still makes the same methods (a fixpoint); and step 8.5: eval,
load, the REPL and the runner now use the reader and compiler written in
cog-lisp (the Smalltalk ones retired in Phase 9 step 9.1); and step
8.6: it writes bytecode itself instead of going through Opal, and compiles
2.1× faster than Phase 7.9.
Reimplement cog-lisp **in cog-lisp**: rewrite the reader and the compiler — the
latter emitting the same `CompiledMethod`s through a LISP-level interface to the
Opal IR — in the language itself, bootstrapped by the Smalltalk-hosted
implementation of Phases 1–4 (and macros from Phase 7).
- The Smalltalk-hosted compiler compiles the cog-lisp-written compiler once; from
  then on the system compiles its own source.
- **Compile speed to 2×** (accepted at 1.3× in Phase 7.9, owner 2026-11-04): a
  compiler written in LISP can emit IR or bytecode directly instead of going
  through Opal's AST, semantic analysis and code generation, which take three
  quarters of compile time today.
- This is the real proof the language is complete: it can express its own
  front end and code generator.
- *Acceptance:* the self-hosted reader and compiler reproduce the Smalltalk-hosted
  implementation's output on the Phase 1–4 corpora, **and** the compiler compiles
  itself to a fixpoint (the compiler built by stage 2 produces byte-identical
  output to the one built by stage 3).

### Phase 8.9 — CI/CD, and running on Linux ✅
[Spec](specs/phase-8.9-ci-cd.md). cog-lisp runs on Linux as well as Windows (the
console and stdin layer reads through libc there), and GitHub Actions tests and
releases it, on Linux runners with a Windows job beside them. The plan before the
spec, for the record, was a pipeline on a Windows runner:
- **On every push and pull request:** bootstrap Pharo (cached), then
  `tests\run-all.bat` and the VS Code extension's `npm test`.
- **On a tagged release:** build `cog-lisp.image` (with its `.changes`) and the
  extension's `cog-lisp.vsix`, and attach them to the GitHub release, so cog-lisp
  can be tried without building anything.

### Phase 9 — Finishing the language
[Spec](specs/phase-9-language.md), accepted. Three steps, each with LISP tests
and examples:
- **9.1 Seeded builds** (done): an image is built from an earlier cog-lisp image
  (the v0.1.2 release, pinned like Pharo), not the stock Pharo image. The
  Smalltalk reader and compiler retired, with `COGLISP_COMPILER`; a lost seed is
  rebuilt from its tagged source (`scripts/rebuild-seed.sh`, run by CI).
- **9.2 The numeric tower** (done; R7RS 6.2): exact rationals with read syntax (`1/3`),
  exactness, `#e #i #x #o #b`, `+inf.0`/`+nan.0`, and the numeric procedures
  (review R-11, R-21). Open to new kinds of number, so complex numbers can come
  as a library at any time (owner, 2026-11-04).
- **9.3 Hygienic macros** (done): `syntax-rules`, `define-syntax`, `let-syntax`,
  `letrec-syntax`, by renaming; special-form names can be shadowed, and a macro's
  free names mean what they meant where it was defined (review C-14).
  `define-macro` stays.

### Phase 10 — A world of its own
[Spec](specs/phase-10-pure-image.md), accepted in outline; a long phase, each
step specified in detail before it starts (owner, 2026-11-04). The VM always
needs a small Smalltalk-shaped kernel; "pure" means no stock image at run or
build time, only the Pharo subsystems the world needs, and a world a user meets
in LISP.
- **10.1 The runtime in LISP**: `define-class` and `define-method`, and cog-lisp's
  runtime moved from Smalltalk to `lib/runtime/`, so no Smalltalk compiler is
  needed to build an image, and the world can read and change its own runtime.
- **10.2 The audit**: every Pharo package kept, reimplemented in LISP, or removed,
  measured statically and by running everything, and signed off by the owner
  before anything goes. Networking and graphics stay.
- **10.3 The pure image**: built from the seed by unloading what the audit
  removes; an image that builds its successor to a fixpoint.
- **10.4 Our own VM executables**: a spike building `pharo-vm` at the pinned
  commit in CI, kept only if it builds reliably (`--headless` by default).
- **10.5 The LISP-visible world**: describe, inspect, apropos, who-calls, edit, and
  LISP backtraces instead of Smalltalk ones.
- **10.6 Networking from LISP** and **10.7 Graphics from LISP**, specified when
  reached.

### Later: hover help in VS Code (owner idea, 2026-11-04)
Hover text for procedures, special forms and macros, designed so it costs
almost nothing to maintain:
- **One source of truth, in the image.** Each primitive gets a one-line
  documentation string where it is installed; a `define` or `define-macro` whose
  body starts with a string keeps it as its documentation (as Common Lisp does),
  stored with the procedure like its source. `(procedure-documentation f)` reads
  it, and a test fails if a primitive has none, so new primitives cannot be
  added undocumented.
- **The editor asks the image.** Hover comes from the planned image-served
  language server (Phase 7.5 spec §5.4): documentation, the parameter list, and
  `procedure-source` for user definitions. Nothing is copied into the extension.
- **Offline fallback, generated:** the build can dump every global's
  documentation to a JSON file the extension reads when no image is running, so
  even that list is never edited by hand.
- To be specified with the language server.

### Later: a reference of the built-ins (owner idea, 2026-11-04)
Every primitive, special form and `lib/` macro listed with its parameters, a
one-line description and the spec section that introduced it, so the growing
set stays known to both of us. Built on the hover-help plan above: the
documentation strings in the image are the source, and the reference
(`docs/builtins.md`) is generated from them by the build, with a test that
fails when a global has no documentation. Not yet scheduled; specify it with
hover help, or sooner if keeping track gets hard.

### Later: a user manual (owner idea, 2026-11-04)
The examples in `examples/` (each runnable, with its expected output checked by
the test suites) are written to become the backbone of a cog-lisp user manual:
one chapter per feature, with the example as its worked, verified code.

### Later: an expert system in cog-lisp (owner idea, 2026-11-03)
A first large program written *in* cog-lisp, once the language phases are done:
- **Forward chaining**, NRules/CLIPS style: facts in a working memory, rules that
  fire when their conditions match, matched efficiently with a Rete network.
- **Backward chaining**, Prolog style: goals proved from rules and facts by
  unification and backtracking search (the approach of *ANSI Common Lisp*'s
  chapter on inference).
- Rules written with macros, and the knowledge base kept in the image.
