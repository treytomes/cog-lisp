# Phase 10 — A world of its own: the pure LISP image

| | |
|---|---|
| **Status** | Accepted in outline (2026-11-04). A long phase: each step gets its own detailed spec, accepted by the owner, before it starts. |
| **Depends on** | Phase 9 (seeded builds, the numeric tower, hygienic macros) |

## 1. Goal

Make the image cog-lisp's own: built without the stock Pharo image, containing
what the world needs and nothing it does not, with everything a user meets
written in LISP, and with the subsystems a living world wants (networking and
graphics among them) reachable from LISP.

### What "pure" means

The VM always needs a small Smalltalk-shaped kernel: `nil`, `true`, `false`,
`SmallInteger`, `Array`, `CompiledMethod`, `BlockClosure`, processes, and so on.
Pure does not mean that kernel goes. It means:

1. **No stock image, at run time or at build time.** Phase 9 builds from a seed
   cog-lisp image; here the image also needs no Smalltalk compiler to build,
   because cog-lisp's runtime is LISP (10.1).
2. **Only what the world needs.** Every Pharo subsystem is audited and kept,
   reimplemented in LISP, or removed. Nothing is removed blindly: networking and
   graphics stay, because the world will want them (owner, 2026-11-02 and
   2026-11-04); networking is how an AI agent gets into and out of the world.
3. **The world a user meets is LISP**: the REPL, errors, inspection and saving,
   with no Smalltalk stack traces or tools in the way. Smalltalk interop (`send`,
   `(smalltalk Name)`) stays as a deliberate door to whatever is kept.

## 2. Where we start (measured 2026-11-04)

- The built image is **64.6 MB**, with **779 packages and 11,025 classes**.
- cog-lisp's own code names **82 classes in about 20 Pharo packages**: the kernel,
  collections and streams, the code model (`CompiledMethod`, `CompiledBlock`,
  clean and constant blocks), `EncoderForSistaV1`, Opal's AST (for the Opal code
  generator, which Phase 9 retires), Clap, `Stdio`, `OSEnvironment`/`OSPlatform`,
  `DateAndTime`. It also uses packages it never names, through messages alone:
  FileSystem (`asFileReference`), uFFI (`ffiCall:`), Regex (`matchesRegex:`),
  Zinc's UTF-8 encoders, exceptions, processes and `Delay`, `SessionManager`. A
  static count undercounts; the audit also watches the system run (10.2).
- After Phase 9, the Smalltalk in `src/` is the runtime: core data (cons cells,
  symbols, the printer, errors), the primitives, the shell and stdio, about 1,850
  lines today.
- **Pharo publishes no minimal image per build** (only `latest-minimal-64.zip`,
  which cannot be pinned). So the way to a small image is to shrink cog-lisp's
  own, not to start from Pharo's minimal one.

## 3. Principles

- **Audit before removing.** The owner signs off the audit before anything is
  stripped.
- **Phase 8's discipline for images**: an image builds its successor, and the
  successor builds the same thing again (a fixpoint), checked by a suite.
- **Every step lands green**, with LISP tests and an example per feature, one
  commit per step, CI on both platforms, and a status line below.
- **Measure each step**: image size, start-up time, memory at the prompt, the
  benchmarks (no slower), compile time.

## 4. Steps (in outline; each is specified in detail before it starts)

### 10.1 The runtime in LISP
The step that lets an image be built without a Smalltalk compiler, and lets the
world read and change its own runtime (owner, 2026-11-04).
- **`define-class` and `define-method`**: LISP forms that define Smalltalk classes
  (slots, superclass, class side) and compile methods with the LISP compiler
  (`self`, instance variables, `super` sends, primitives).
- **The runtime moves to `lib/runtime/`**: core data, the primitives, the shell
  and stdio, method by method, each behaving as before. The suites are the check,
  as they were for the compiler.
- **After this step**, building an image needs no Smalltalk compiler: the seed's
  LISP compiler builds everything.
- The data classes stay Smalltalk classes (the VM and interop need that), defined
  from LISP; the kernel classes are untouched.

### 10.2 The audit
- **A tool, `lib/audit.lisp`**, inventories what the world uses:
  - statically, the classes and selectors that cog-lisp's code and LISP library
    reach, and their packages, transitively;
  - dynamically, every method that runs while all the suites, examples and
    benchmarks run (method-level coverage).
- **A table, `specs/phase-10-audit.md`**: every Pharo package, grouped into
  subsystems (kernel, collections, streams, files, networking, FFI, graphics, UI,
  the IDE, Monticello and Metacello, refactoring, tests, Opal, Clap, …), each with
  what uses it and a decision: **keep**, **reimplement in LISP**, or **remove**,
  with a reason.
- **The owner signs off the table before 10.3.** Kept, as the owner has said:
  networking and graphics. Expected keeps besides: the kernel, collections,
  streams, files, stdio, processes, FFI. Expected removals: the IDE, Monticello,
  Metacello, refactoring, Pharo's own tests. Decided by measurement: Opal, Clap,
  Regex, the windowing UI (Morphic, Spec), which graphics may or may not need.

### 10.3 The pure image
- **Built from the seed**: the build loads cog-lisp, unloads every package the
  audit marked **remove** (dependents first), cleans up, and saves.
- **Fixpoint**: an image built by that image is equivalent to it (every method's
  fingerprint, as `method-listing` gives, and the same globals).
- **The checks**: every suite, example, LISP test and benchmark passes on the
  pure image, on Linux and Windows, and the release bundles ship it.
- **Measured and recorded**: image size, start-up time, memory at the prompt.

### 10.4 cog-lisp's own VM executables
- **A spike first** (owner, 2026-11-04): build the VM from `pharo-vm` at the pinned
  commit, unchanged, in CI for Linux and Windows, and run every suite on it.
- **If it builds reliably**: name it `cog-lisp` / `cog-lisp.exe`, make
  `--headless` the default and the image beside it the default image; the launch
  scripts become thin, or go.
- **If not**: keep the stock binaries, renamed, with a launcher, and record the
  decision and its reason.

### 10.5 The LISP-visible world
What Pharo's IDE gave a Smalltalk programmer, for a LISP programmer at the REPL:
- `(describe x)`, `(inspect x)` (a REPL-driven inspector), `(apropos "name")`,
  `(who-calls 'f)`, `(procedure-source f)` and `(disassemble f)` (as now), and
  `(edit f)` (the source in `$EDITOR`, recompiled on save).
- **Errors never show Smalltalk stack traces**: a LISP backtrace of procedure
  names and source locations, at the break loop (`backtrace`).
- `(save-image)`, `(save-image "name")`.
- These are the first entries in the generated built-ins reference (README, "a
  reference of the built-ins"), with the hover help planned for VS Code.

### 10.6 Networking from LISP
Sockets, HTTP client and server (Zinc, as the audit keeps it), and whatever the
agent's way in and out of the world needs, as a LISP library. Specified when
reached.

### 10.7 Graphics from LISP
Drawing and, if the audit keeps it, windows: a LISP library over what Pharo
provides (Athens and Cairo, SDL2, Morphic or Spec, as measured in 10.2).
Specified when reached.

## 5. Acceptance criteria (in outline)

- AC-1 (10.1) No Smalltalk source is filed in to build an image; the runtime's
  methods come from `lib/runtime/`; every suite passes.
- AC-2 (10.2) The audit table covers every package in the image, and the owner has
  signed it off.
- AC-3 (10.3) The pure image passes every suite, example, LISP test and benchmark
  on both platforms; the image-builds-image fixpoint holds; the release ships it;
  its size and start-up time are recorded.
- AC-4 (10.4) cog-lisp's own VM executables run every suite on both platforms, or
  the decision to keep the stock binaries is recorded with its reason.
- AC-5 (10.5) Each tool of 10.5 works at the REPL and has a test and an example; an
  uncaught error shows a LISP backtrace, not a Smalltalk one.
- AC-6 and AC-7 (10.6, 10.7): set by their detailed specs.

## 6. Examples (in outline)

| Example | Proves |
|---|---|
| `examples/define-class.lisp` | a Smalltalk class and its methods defined from LISP, and used through `send` |
| `examples/world-tour.lisp` | describe, apropos, who-calls, a backtrace: the world examining itself |
| (10.6, 10.7) | set by their detailed specs |

## 7. Risks

- **Unloading Pharo packages is notoriously tangled**: hidden dependencies,
  start-up and shut-down handlers, class-side registrations. The audit's dynamic
  half exists to find them, and stripping goes one subsystem at a time, with
  every suite run after each.
- **The runtime rewrite (10.1) is the largest step.** It replaces working code;
  the suites are the safety net, as they were for the compiler.
- **Keeping graphics may keep a lot**: the audit measures what drawing alone needs
  before deciding on the windowing UI.
- **Building the VM (10.4)** pulls in a CMake and Slang toolchain this project has
  never needed; the spike decides whether it is worth it.

## 8. Step status

| Step | Status |
|---|---|
| 10.1 Runtime in LISP | not started |
| 10.2 Audit | not started |
| 10.3 Pure image | not started |
| 10.4 Own VM executables | not started |
| 10.5 LISP-visible world | not started |
| 10.6 Networking from LISP | not started |
| 10.7 Graphics from LISP | not started |
