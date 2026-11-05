# Phase 9 — Finishing the language: seeded builds, the numeric tower, hygienic macros

| | |
|---|---|
| **Status** | Accepted (2026-11-04) |
| **Depends on** | Phase 8 (complete), Phase 8.9 (CI, pinned Pharo) |
| **Feeds** | Phase 10 (the pure LISP image) |
| **Review items** | R-11 (reading rationals), R-21 (infinity and NaN), C-14 (shadowing and capture) |

## 1. Goal

Finish the language, so that Phase 10 can turn to the image:

- **Seeded builds**: an image is built from an earlier cog-lisp image instead of
  the stock Pharo image, and the Smalltalk reader and compiler retire.
- **The numeric tower**: exact rationals with read syntax, exactness, infinities
  and NaN, and the R7RS numeric procedures, open to new kinds of number (complex
  numbers can come as a library at any time).
- **Hygienic macros**: `syntax-rules`, with special-form names that a program can
  shadow and macros that cannot capture a program's variables.

The pure image (the runtime in LISP, the audit of Pharo's subsystems, stripping,
our own VM, the LISP-visible tools, then networking and graphics) is Phase 10
(`specs/phase-10-pure-image.md`), split off by the owner on 2026-11-04 because it
will take much longer.

## 2. Where we start (measured 2026-11-04)

- The build files `src/*.st` into the pinned stock Pharo image (`pharo.pins`),
  then compiles `lib/compiler/` with the Smalltalk compiler (stage 0) and runs the
  step 8.4 bootstrap to a fixpoint.
- **About 2,050 lines of Smalltalk** in `src/` are the Smalltalk reader and
  compiler, which the LISP ones have replaced in use since step 8.5. They remain
  as stage 0 of the bootstrap, as the reference for the 8.2 and 8.3 comparison
  suites, and behind `COGLISP_COMPILER=smalltalk`.
- Numbers: Smalltalk's `Fraction` already makes `(/ 6 4)` exact and prints it
  `3/2` (R-11, printer), but `3/2` does not read back, `(integer? 2.0)` is `#f`,
  `(+ 'a)` answers `a`, and infinities print as Smalltalk does (R-21).
- Macros: `define-macro` only. Special-form names cannot be shadowed, and `case`
  calls whatever `memv` is in scope where it is used (C-14).

## 3. Principles

- **Every step lands green**, with LISP tests and an example per feature (the
  manual-to-be), one commit per step, CI passing on both platforms, and a status
  line below.
- **The benchmarks stay no slower**, and compile time is recorded.
- Steps 9.2 and 9.3 come after 9.1, so each feature is written once, in the LISP
  reader and compiler.

## 4. Steps

### 9.1 Seeded builds: no stock image at build time
- **The build starts from a seed**: a released cog-lisp image, pinned like Pharo
  (a URL and a SHA-256 in `pharo.pins`), instead of the stock Pharo image. The
  seed's LISP reader and compiler compile `lib/compiler/` (stage 1), and the
  stages and fixpoint of step 8.4 follow, with the seed as stage 0.
- **The Smalltalk reader and compiler retire**, about 2,050 lines:
  - `LispReader`'s reading and `LispCompiler`'s translation;
  - the `smalltalk*` entry points and `COGLISP_COMPILER=smalltalk`;
  - the Opal code generator (`set-code-generator! 'opal`), whose byte-for-byte
    check has done its work;
  - the 8.2 and 8.3 comparison suites, whose findings stay in the record.
  `LispReader on:`, `LispCompiler new eval:` and the rest of the Smalltalk-side
  API stay, as entry points to the LISP reader and compiler. The data classes
  (`LispCons`, `LispSymbol`, the printer, errors) stay.
- **Until this step every suite runs both ways**; after it, once, and CI's
  second Linux job goes.
- The Smalltalk runtime in `src/` is still filed in by Opal, which the seed has
  (Phase 10 moves the runtime to LISP).
- **Recovering from nothing**: the first seed is built the old way, from the
  pinned stock image, and that path stays in the repository (a script and a CI
  job that run it) as the documented way back if every seed is lost.

#### 9.1 in detail (2026-11-05)

Three commits, each green on both platforms:

- **9.1a Build from the seed** (the Smalltalk compiler still present).
- **9.1b Retire** the Smalltalk reader and compiler, the Opal generator and
  `COGLISP_COMPILER`; suites run on the built image.
- **9.1c The recovery path**, as a script and a CI job.

**The seed.** The first seed is the v0.1.2 release: the first built on the
pinned Pharo build, and the first to carry the licenses. `pharo.pins` gains:
- `SEED_TAG=v0.1.2`;
- `SEED_URL`, the release's Linux bundle (one image serves every platform);
- `SEED_SHA256`, the bundle's checksum.

Both bootstraps fetch and check the seed bundle like the other pins, and extract
its image and changes file as `pharo/seed.image` and `pharo/seed.changes`. They
still fetch the VM. The stock image is fetched only by the recovery path (and,
until 9.1b, for the suites).

**The build** (`build/build.st`, run on `pharo/seed.image`; the seed file is
never saved) goes in this order:
1. **Keep the seed's compiler.** Its entry points (`LispCompiler entries`) are
   kept for the build. Sealing (step 8.5) made them independent of the global
   environment: they read private copies of every cell they use.
2. **Note what the seed has**: every method of the `CogLisp-*` packages,
   extension methods included.
3. **File in `src/`.** Classes are redefined in place, and every method in
   `src/` is compiled anew.
4. **A fresh global environment.** `LispEnvironment default` is replaced, not
   cleared. The seed's code keeps its old cells, so the seed's compiler still
   works, and no definition of the seed's world reaches the new one. Then come
   the primitives (`installDefault`).
5. **The seed compiles `lib/core.lisp` and `lib/compiler/`.** Defining the
   compiler this way makes C1: the new source, compiled by the seed.
6. **The bootstrap**, with the seed as stage 0:
   - M0 is the seed compiling the compiler's source, read by the seed's reader.
   - M1 is C1 compiling it, read by the new reader. Installing M1 makes C2, which
     makes M2; installing M2 makes C3, which makes M3.
   - **The fixpoint is M1 = M2 = M3.** C1 has the new source's meaning whatever
     compiled it, so its output must already be final.
   - M0 = M1 holds only when the code generator has not changed since the seed.
     Its differences are reported (a count and labels), not required.
7. **Seal and install** the new compiler, as step 8.5 does.
8. **Remove what the seed had and the source no longer does.** A method noted in
   step 2 that is still the same object was not compiled from the new source,
   so it goes. The same applies to a `CogLisp-*` class that `src/` no longer
   defines.
9. **Smoke-test, record, save.** The image records how it was built:
   - the seed's tag and checksum;
   - the number of forms compiled;
   - the fixpoint;
   - the M0/M1 differences.

   `(image-build-info)` reads this back (`examples/seeded-build.lisp`). The image
   is saved as `pharo/cog-lisp.image`.

**Compatibility, the self-hosting rule.** The new `src/` must keep working with
the seed's compiler, but only for the length of one build. A change the seed
cannot compile has two ways forward:
- keep the old method one more release;
- release, then move the seed pin forward (`SEED_*` in `pharo.pins`).

The suites and the fixpoint find such a break. Moving the seed pin forward is an
ordinary commit: build, every suite, then the pin.

**After 9.1b:**
- A suite runs on a copy of the built `pharo/cog-lisp.image`, and no longer files
  `src/` into a stock image (a stock image has no compiler for `lib/compiler/`).
- `run-all` builds the image first.
- The Smalltalk side keeps its API, now over the LISP reader and compiler:
  - `LispReader on:`, `LispReader eofObject`;
  - `LispCompiler new compile:`, `eval:`, `evalString:`, `evalAll:`, `evalFile:`;
  - the options (`withoutOptions:do:`, read by `lib/compiler/`), `inlinedSelectors`.
- `bootstrap.lisp` keeps one stage 0, the seed. `definedNamesIn:` reads with the
  LISP reader.
- **Removed:**
  - the `smalltalk*` entry points and `LispReader basicOn:`;
  - the translation methods;
  - `COGLISP_COMPILER`, `implementation`/`usesLisp`;
  - the Opal converter in `lib/compiler/opal.lisp` and `set-code-generator!`
    (the light-node trees stay: `codegen.lisp` reads them);
  - the 8.2 and 8.3 Smalltalk suites;
  - CI's second Linux job;
  - the benchmark's comparison with the Smalltalk compiler. Its baseline figure
    stays in `bench/results.md`.

  Tests that use any of these change to what remains, or go when only the
  retired code was their subject. The record of what they found stays in the
  Phase 8 spec.

**The recovery path** (`scripts/rebuild-seed.sh`, bash, so it runs in Git Bash
too):
1. Export the seed's tag (`git archive SEED_TAG`) into a temporary folder.
2. If that tree's own `pharo.pins` names a seed, rebuild that seed first, the
   same way (recursively). Otherwise bootstrap it from its pinned stock image.
3. Build it with its own scripts, and install the result as `pharo/seed.image`.

So the way back is always "build the seed's own source the way it was built". A
CI job runs it on Linux, then builds the current tree from the rebuilt seed and
runs every suite.

### 9.2 The numeric tower (R7RS 6.2)
- **Kinds**: exact integers (as now), exact rationals (Smalltalk's `Fraction`),
  inexact reals (`Float`).
- **Open to new kinds** (owner, 2026-11-04: complex numbers should be a library
  that can be added at any time):
  - the arithmetic and comparison primitives dispatch on their operands through
    Smalltalk's coercion protocol (`generality`, `adaptToNumber:andSend:`), not on
    a closed list of classes, so a new number class joins the arithmetic by
    implementing that protocol;
  - the numeric predicates (`number?`, `complex?`, `real?`, …) and printing ask
    the object, so a new class answers for itself;
  - the reader offers a hook for number syntax it does not know
    (`(define-number-syntax predicate parser)`), so `1+2i` can be added by the
    library that adds complex numbers;
  - an example and a test add a small number type through interop and use it in
    ordinary arithmetic.
  `lib/complex.lisp` is not part of this phase.
- **Read syntax** (the LISP reader): `1/3`, `-6/4` (read as `-3/2`); the prefixes
  `#e #i #x #o #b #d` in either order; `+inf.0`, `-inf.0`, `+nan.0`, `-nan.0`.
  `string->number` accepts the same.
- **Printing**: `1/3`, `+inf.0`, `-inf.0`, `+nan.0`; floats as now (R-11, R-21).
- **Predicates**: `number? complex? real? rational? integer? exact? inexact?
  exact-integer? exact-rational? nan? infinite? finite? zero? positive?
  negative? odd? even?`. `(integer? 2.0)` is `#t` (R-11). Without complex numbers,
  `complex?` is `number?`.
- **Procedures**: `exact inexact` (and the old names `exact->inexact`,
  `inexact->exact`); `numerator denominator`; `floor ceiling round truncate`
  (`round` to even); `floor/ truncate/ floor-quotient floor-remainder
  truncate-quotient truncate-remainder quotient remainder modulo`; `gcd lcm abs
  min max` (inexact contagion); `exp log sin cos tan asin acos atan` (one and two
  arguments); `sqrt exact-integer-sqrt expt square rationalize`;
  `number->string` with a radix, for rationals too.
- **Type errors in arithmetic**: `(+ 'a)` is an error, not `a` (R-11).
- **Speed**: the inlined fast paths for small integers stay as they are.

### 9.3 Hygienic macros (R7RS 4.3)
- **Forms**: `define-syntax`, `let-syntax`, `letrec-syntax`, `syntax-rules` with
  literals, `_`, nested ellipses, vector patterns, a custom ellipsis, and
  `syntax-error`.
- **Hygiene, in both directions**:
  - a binding a macro introduces never captures a variable of the program that
    uses the macro;
  - a free name in a macro's template means what it meant where the macro was
    defined: `case` calls the global `memv` even inside `(let ((memv ...)) ...)`
    (C-14).
- **Special-form names can be shadowed**: `((lambda (if) (if 1 2 3)) +)` is `6`
  (C-14).
- **By renaming** (owner, 2026-11-04): a template's symbols become *aliases*,
  identifier objects that remember the macro's definition scope. The compiler
  resolves an alias to a fresh local if the same expansion binds it, else to its
  meaning at the definition site; `quote` turns an alias back into its symbol.
  `syntax-case` can come later; it is not part of this phase.
- **`define-macro` stays**, for non-hygienic macros and `lib/cl.lisp`'s
  `defmacro`. The derived forms in `lib/core.lisp` move to `syntax-rules` where
  capture can bite (`case`, `do`, named `let`, `guard`).
- **The sealed compiler** (step 8.5) still works: macros a program defines are
  looked up in the program's environment; the compiler's own references stay
  private.

## 5. Acceptance criteria

- AC-1 (9.1) The build starts from a pinned seed image, not the stock image, and
  the step 8.4 fixpoint holds with the seed as stage 0. The Smalltalk reader and
  compiler, the Opal code generator and `COGLISP_COMPILER` are gone; every suite,
  example, LISP test and benchmark passes on Linux and Windows. The recovery path
  rebuilds a seed from the pinned stock image, in CI.
- AC-2 (9.2) The read syntax, printing, predicates and procedures of 9.2, each
  tested in LISP; a number type added through interop works in ordinary
  arithmetic, comparison, predicates and printing; the reader hook reads a new
  syntax; R-11 and R-21 are closed; the benchmarks are no slower.
- AC-3 (9.3) `syntax-rules` passes a hygiene suite (capture in both directions,
  nested ellipses, literals, vectors, `let-syntax` and `letrec-syntax`); C-14's
  two examples give the Scheme answers; every existing suite passes.

## 6. Examples

| Example | Proves |
|---|---|
| `examples/seeded-build.lisp` | the running image's seed and stages, read back from the image itself |
| `examples/numbers.lisp` | rationals, exactness, the read syntax, infinities and NaN, the division family |
| `examples/new-number-type.lisp` | a number type added from outside the core, used in ordinary arithmetic |
| `examples/syntax-rules.lisp` | `syntax-rules` macros, ellipses, and hygiene in both directions |
| `examples/shadowing.lisp` | a local named `if`, and a local `memv` that `case` does not see |

## 7. Risks

- **Seeds can be lost** (a release deleted, files.pharo.org gone): hence the
  recovery path from the pinned stock image, kept working by CI.
- **A seed carries old code.** Building filed-in Smalltalk and newly compiled
  LISP on top of a seed must not keep stale definitions: the fixpoint and every
  suite are the check, and the build starts by removing cog-lisp's own globals
  and packages from the seed's world before loading the new ones.
- **Hygiene touches every macro use.** `lib/core.lisp` moves to `syntax-rules`
  one form at a time, with every suite after each.

## 8. Decisions (owner, 2026-11-04)

1. **Two phases**: this one is the language; the pure image is Phase 10, which
   will take a long time and add graphics and networking.
2. **The runtime is rewritten in LISP** (Phase 10, step 10.1).
3. **Complex numbers are a library**, addable at any time: the tower is built open
   to new kinds of number (9.2).
4. **Hygiene by renaming** (aliases), not syntactic closures or `syntax-case`.
5. **Our own VM: a spike first** (Phase 10, step 10.4).

## 9. Step status

| Step | Status |
|---|---|
| 9.1 Seeded builds | 9.1a done (2026-11-05): the image is built from the v0.1.2 seed; 9.1b, 9.1c to come |
| 9.2 Numeric tower | not started |
| 9.3 Hygienic macros | not started |
