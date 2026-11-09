# Phase 9 — Finishing the language: seeded builds, the numeric tower, hygienic macros

| | |
|---|---|
| **Status** | Implemented: 9.1–9.3 (2026-11-05), 9.4 (2026-11-09). Accepted 2026-11-04; 9.4 appended from issue #5 and accepted 2026-11-09 |
| **Depends on** | Phase 8 (complete), Phase 8.9 (CI, pinned Pharo) |
| **Feeds** | Phase 11 (the pure LISP image) |
| **Review items** | R-11 (reading rationals), R-21 (infinity and NaN), C-14 (shadowing and capture) |

## 1. Goal

Finish the language, so that Phase 11 can turn to the image:

- **Seeded builds**: an image is built from an earlier cog-lisp image instead of
  the stock Pharo image, and the Smalltalk reader and compiler retire.
- **The numeric tower**: exact rationals with read syntax, exactness, infinities
  and NaN, and the R7RS numeric procedures, open to new kinds of number (complex
  numbers can come as a library at any time).
- **Hygienic macros**: `syntax-rules`, with special-form names that a program can
  shadow and macros that cannot capture a program's variables.

The pure image (the runtime in LISP, the audit of Pharo's subsystems, stripping,
our own VM, the LISP-visible tools, then networking and graphics) is Phase 11
(`specs/phase-11-pure-image.md`), split off by the owner on 2026-11-04 because it
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
  (Phase 11 moves the runtime to LISP).
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
2. **Note the seed's packages** (`CogLisp-*`).
3. **File in `src/`, noting every method it compiles.** Classes are redefined in
   place, and every method in `src/` is compiled anew; each compile announces
   itself (`MethodAdded`, `MethodModified`), and the build records them.
4. **Remove what the seed had and the source no longer does, before any of it
   can run.** In the packages `src/` defines and the seed's, a method the
   file-in did not compile goes, and so does a class `src/` does not define.
   (As built: the first plan kept the seed's method objects and removed those
   still identical after the file-in, at the end of the build. Pharo recompiles
   every method of a class whose shape changes, so stale methods became new
   objects and stayed; and one ran first: the seed's `LispCompiler>>initialize`
   wrote a slot that no longer existed. Hence the announcements, and the early
   sweep.) A sweep that would remove more than half the methods is refused, as a
   mistake in what was noted.
5. **A fresh global environment.** `LispEnvironment default` is replaced, not
   cleared. The seed's code keeps its old cells, so the seed's compiler still
   works, and no definition of the seed's world reaches the new one. Then come
   the primitives (`installDefault`).
6. **The seed compiles `lib/core.lisp` and `lib/compiler/`.** Defining the
   compiler this way makes C1: the new source, compiled by the seed.
7. **The bootstrap**, with the seed as stage 0:
   - M0 is the seed compiling the compiler's source, read by the seed's reader.
   - M1 is C1 compiling it, read by the new reader. Installing M1 makes C2, which
     makes M2; installing M2 makes C3, which makes M3.
   - **The fixpoint is M1 = M2 = M3.** C1 has the new source's meaning whatever
     compiled it, so its output must already be final.
   - M0 = M1 holds only when the code generator has not changed since the seed.
     Its differences are reported (a count and labels), not required.
8. **Seal and install** the new compiler, as step 8.5 does.
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
  - `LispReader on:`, `read:`, `readAll:`, `eofObject`, and `readFrom:`, which
    `read` uses: on standard input (a `LispLineStream`) it reads another line
    while the datum is incomplete, as the Smalltalk reader's character-at-a-time
    reading did;
  - `LispCompiler new compile:`, `eval:`, `evalString:`, `evalAll:`, `evalFile:`;
  - the options (`withoutOptions:do:`, read by `lib/compiler/`).
- `macroexpand` and `macroexpand-1` still called the Smalltalk compiler; they
  now call `lisp-macroexpand` and `lisp-macroexpand-1` (`lib/compiler/compiler.lisp`)
  through the entry points.
- `bootstrap.lisp` keeps one stage 0, the seed. `definedNamesIn:` reads with the
  LISP reader.
- **Removed:**
  - the `smalltalk*` entry points and `LispReader basicOn:`;
  - the translation methods;
  - `COGLISP_COMPILER`, `implementation`/`usesLisp`, `(compiler-implementation)`;
  - the Opal converter in `lib/compiler/opal.lisp` and `set-code-generator!`
    (the light-node trees stay: `codegen.lisp` reads them);
  - the 8.2 and 8.3 Smalltalk suites;
  - CI's second Linux job;
  - the benchmark's comparison with the Smalltalk compiler. Its baseline figure
    stays in `bench/results.md`; the check now compares with Phase 7.9's figure;
  - two Phase 7.9 checks of the Smalltalk compiler's internals (its special-form
    table and template cache). The bytecode corpus now pins the LISP compiler's
    code, by `method-listing` fingerprint (`COGLISP_REPIN=1` re-pins it).

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
    Smalltalk's coercion protocol (`adaptToInteger:andSend:`,
    `adaptToFraction:andSend:`, `adaptToFloat:andSend:`; Pharo 14 has no
    `generality`, measured 2026-11-05), not on a closed list of classes, so a new
    number class joins the arithmetic by implementing that protocol;
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

#### 9.2 in detail (2026-11-05)

Measured first: before 9.2, of the procedures above only `+ - * / quotient
modulo abs min max zero? positive? negative? number? integer?` existed; `1/3`
read as a symbol; `(/ 1.0 0.0)` was a division-by-zero error; infinity printed
as `Float infinity`; and cog-lisp had **no multiple values**, which `floor/`,
`truncate/` and `exact-integer-sqrt` return. Three commits:

**9.2a: the tower itself** (read, print, ask, convert).
- **The number protocol**: what cog-lisp asks of a number, as extension methods
  on Pharo's `Number` (package `CogLisp-Core`), each with a default a new class
  inherits and may override:

  | Message | `Number` default | `Integer` | `Fraction` | `Float` |
  |---|---|---|---|---|
  | `lispIsExact` | false | true | true | false |
  | `lispIsReal` | true | true | true | true |
  | `lispIsRational` | false | true | true | finite |
  | `lispIsInteger` | false | true | false | finite, no fraction part |
  | `lispIsNaN`, `lispIsInfinite` | false | false | false | as the float is |
  | `lispWriteOn:base:` | `printString`, base 10 only | digits | `n/d` | `+inf.0` etc., base 10 only |

  A new number type subclasses `Number`, implements its arithmetic and the
  `adaptTo…:andSend:` coercions, and overrides what differs (a complex type:
  `lispIsReal` false). The predicates and the printer use nothing else.
- **Reading** (`lib/compiler/reader.lisp`, one parser for the reader and
  `string->number`, which takes a radix): R7RS 7.1.1's real numbers.
  - Integers and `n/d` rationals in any radix; decimals (`1.5`, `.5`, `5.`,
    `1e10`) in radix 10.
  - The prefixes `#e #i #x #o #b #d`, at most one of each kind, in either order.
  - `+inf.0 -inf.0 +nan.0 -nan.0`.
  - `#e` on a decimal gives its exact value (`#e1.1` is `11/10`). `#i` gives
    the nearest float.
  - `n/0` is a read error ("division by zero"); `string->number` answers `#f`
    for it.
  - The common case stays cheap: a token that cannot start a number (its first
    character not a digit, sign or dot) is a symbol after one test.
- **Printing**: through `lispWriteOn:base:`. `+inf.0`, `-inf.0`, `+nan.0`;
  other floats as Pharo prints them, which read back; `-6/4` prints `-3/2`.
- **The predicates** of 9.2, from the protocol. `exact?`, `inexact?`, `nan?`,
  `infinite?`, `finite?` and the sign tests need a number, and `odd?`/`even?` an
  integer; anything else is an error naming the procedure.
- **`exact`, `inexact`** and the old names. `(exact 0.1)` is
  `3602879701896397/36028797018963968`, the float's exact value. `(exact +inf.0)`
  is an error.
- **Division by zero**: exact `(/ 1 0)` stays an error. With a float operand the
  answer is IEEE's: `(/ 1.0 0)` is `+inf.0`, `(/ 0.0 0)` is `+nan.0`.
- **Type errors**: the one-argument entries of `+ * - / min max` check their
  argument. A host "does not understand" from arithmetic on a non-number is
  reported as `+: not a number: a`.

**9.2b: the procedures, and multiple values.**
- **Multiple values** (R7RS 6.10), because `floor/` needs them:
  - `values` answers its argument when given one, otherwise a values object;
  - `call-with-values` calls its consumer with the values, as a tail call;
  - `let-values` and `let*-values` are macros in `lib/core.lisp`;
  - a values object prints as its values separated by spaces (what the REPL
    shows).
- **Rounding**: `floor ceiling round truncate` keep exactness: `(floor 2.5)` is
  `2.0`, and `(round 5/2)` is `2` (to even).
- **The division family** on integers, and on floats with integer values (the
  answers are then inexact):
  - `floor/` and `truncate/` answer two values;
  - `floor-quotient`, `floor-remainder`, `truncate-quotient`, `truncate-remainder`;
  - `quotient remainder modulo`.
- **Rationals and integers**: `numerator`, `denominator` (of a float, inexact),
  `gcd`, `lcm`, `abs`, `square`.
- **Contagion**: `min` and `max` answer inexact if any argument is.
- **Roots and powers**:
  - `sqrt` is exact for an exact perfect square (`(sqrt 16)` is `4`,
    `(sqrt 1/4)` is `1/2`), otherwise inexact. A negative argument is an error
    naming complex numbers, which are a library;
  - `exact-integer-sqrt` answers two values;
  - `expt` is exact for an exact base and an exact integer power;
  - `rationalize` answers the simplest rational within the tolerance (Stern-Brocot).
- **Transcendental functions**: `exp log sin cos tan asin acos atan`, inexact,
  with `log` and `atan` also taking two arguments. `(log 0)` is `-inf.0`.
  Outside the real domain they answer `+nan.0`.
- **`number->string`** with a radix, for rationals too (`(number->string 1/3 2)`
  is `"1/11"`).
- As built: `expt` with a float power goes through Pharo's `raisedTo:` (`exp`
  of `ln`), so `(expt 2 0.5)` is `1.414213562373095`, one unit in the last place
  from `(sqrt 2)`. R7RS asks no more; a correctly rounded `pow` would need a
  primitive Pharo does not have. `magnitude` came too, as `abs` of a real.

**9.2c: open to new kinds.**
- **`(define-number-syntax predicate parser)`**: the reader and `string->number`
  try each registered syntax, in order, on a token that is not a built-in number,
  before it becomes a symbol. The registry is a shared box, so it reaches the
  sealed reader (step 8.5), as `define-special-form` reaches the compiler.
- **The example `new-number-type.lisp`** defines dual numbers (`a+bε`, the basis
  of automatic differentiation) as a `Number` subclass through interop, with
  their read syntax. It then uses them in ordinary arithmetic, mixed with
  integers and rationals, and in comparisons, predicates and printing. A test
  checks the same.
- As built: the type lives in `examples/dual.lisp`, which the example and the
  test load, so both use one definition. It is a few dozen lines of Smalltalk
  method source, compiled through interop, and needed no change to cog-lisp:
  the measure of "open".

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

#### 9.3 in detail (2026-11-05)

Measured first:
- The compiler checks the special-form table *before* the scope. So no local
  binding can shadow `if`, which is the cause of C-14's first example.
- A scope is an `IdentityDictionary` from an identifier to its temp name, so
  any object can be a key.
- **The self-hosting rule (9.1) bites.** The seed compiles `lib/core.lisp`, and
  the v0.1.2 seed has no `define-syntax`. So `core.lisp` itself cannot use
  `syntax-rules` until a release that has it becomes the seed.

Two commits.

**9.3a: identifiers, resolution, `syntax-rules`.**
- **An alias** (`LispAlias`, a data class beside `LispSymbol`) has a `name` (a
  symbol, or an alias, for a macro written by a macro) and an `env`: the
  compile-time scope where the macro was defined (an empty scope for a top-level
  `define-syntax`). An *identifier* is a symbol or an alias.
- **Resolution**, the one rule every part of the compiler now uses:
  1. An identifier found in the scope means that binding: a local variable (its
     temp name) or a local macro.
  2. An alias not found there means what its name means in its `env`.
  3. A symbol not found there is global: a special form if it names one, else a
     global macro, else a global variable.

  So a local `if` is an ordinary variable (C-14). Binding forms take identifiers
  (`lambda`, `let`, named `let`, internal `define`, `set!`), so a variable a
  template binds is a key that the program's own symbols never match.
- **Where an alias goes back to a symbol**:
  - inside `quote`, and the constant parts of `quasiquote`;
  - the name a top-level `define` defines (a template's top-level definition
    defines that name globally);
  - `send` selectors, `smalltalk` names, `define-macro` names, procedure names
    and error messages.

  Keyword tests (`unquote`, `unquote-splicing`, `define` and `begin` in bodies,
  `lambda` in `define`) resolve the identifier instead of comparing it with
  `eq?`.
- **Forms**:
  - `define-syntax`: at top level it defines a global macro; in a body it is a
    local one, visible to the whole body;
  - `let-syntax` and `letrec-syntax`, whose bodies are bodies, as `let`'s are;
  - `syntax-rules`, with literals, `_`, an ellipsis after any element (with more
    patterns after it, and a dotted tail), nested ellipses, vectors, a custom
    ellipsis (`(syntax-rules ::: (lit ...) rule ...)`) and `(... ...)` in
    templates;
  - `syntax-error`, which stops compilation with its message and arguments.

  A literal matches an input identifier when both resolve to the same binding,
  or both are free with the same name (R7RS 4.3.2). The transformer is built at
  compile time; a top-level macro is a literal of the method that defines it.
- **The expander** is `lib/compiler/syntax-rules.lisp`, a fifth compiler source:
  matched in LISP, sealed with the rest. Each expansion makes one alias per
  template symbol. Aliases arise only from `syntax-rules`, so a compile that
  expands none never walks a quoted datum to strip them.
- **`define-macro` stays non-hygienic.** Its expander sees aliases when it is
  used inside a `syntax-rules` template. `lib/core.lisp`'s `cond` compares
  `else` and `=>` by name through a helper, so it works there; a user's
  `define-macro` that compares symbols with `eq?` may not (documented).

**9.3b: hygienic derived forms.**
- **`lib/core-syntax.lisp`** (merged into `core.lisp` after Phase 9; see below), loaded by the build once the new compiler is
  installed (after the fixpoint, before saving), redefines `case`, `do` and
  `guard` with `syntax-rules`. Then `case` calls the global `memv` inside
  `(let ((memv ...)) ...)` (C-14's second example), and `do`'s loop name cannot
  capture anything.
  - Named `let` is the compiler's, and is hygienic through identifiers in 9.3a.
  - `core.lisp` keeps the `define-macro` versions, which compile the compiler.
  - When a seed has `syntax-rules`, the two files can become one.
- **Measured**: compile time with `syntax-rules` `case`, `do` and `guard` stays
  within the Phase 8 check (below Phase 7.9's 36.3 ms).
- **As built**:
  - `core-syntax.lisp` redefines every derived form whose expansion uses names a
    program could bind: `cond and or when unless let* letrec letrec* case do
    guard restart-case`. Measured first: with only `case`, `do` and `guard`
    converted, `cond`'s `define-macro` expansion still inserted plain `if` and
    `let`, so a local `if` broke every `cond` inside a hygienic macro. `case` and
    `cond` also take `=>` (R7RS).
  - `let-values` and `let*-values` stay `define-macro`; their bindings are
    gensyms already.
  - Compiling the benchmark's forms took 21.4 ms (below the Phase 8 check). Every
    suite took 104 s on Windows, about as before.
  - `macroexpand` and `macroexpand-1` answer plain data: a `syntax-rules`
    expansion's aliases become their symbols there, since they are for reading.
  - A `define-macro` macro (`lib/cl.lisp`'s `defmacro`) is still not hygienic:
    its expansion's names mean what they mean where it is used.

**After Phase 9: the seed moves to v0.1.3, and the two files become one**
(owner, 2026-11-05: "get the `define-macro` references fixed").
- **v0.1.3 became the seed**: it has `syntax-rules`, so the seed can compile
  `syntax-rules` derived forms.
- **`lib/core.lisp` is now the `syntax-rules` definitions**:
  - `lib/core-syntax.lisp` and the build step that loaded it are gone;
  - `let-values` and `let*-values` became `syntax-rules` too (R7RS's reference
    definition);
  - `%keyword?` and `%values-formals`, which existed only for the
    `define-macro` versions, are gone.

  `core.lisp` has no `define-macro` left, and the compiler is compiled through
  the hygienic forms. The build's fixpoint holds, with no form where the seed's
  code differs.
- **`lib/test.lisp`'s forms** (`define-test`, `check`, …) are `syntax-rules`
  macros, so a test may bind `lambda` or `if` around a `check`.
- **A `define-syntax` macro keeps its source**, as a `define-macro`'s does (the
  project's rule that compiled code keeps its text): its expander's
  `procedure-source` is the defining form.
- **The bytecode corpus was re-pinned for one form.** `do`'s loop procedure is
  now named `loop` (the template's name) instead of a gensym, and its recorded
  text changed with it. The bytecode bytes are unchanged.
- **Where `define-macro` remains**, by design:
  - `lib/cl.lisp`'s `defmacro`, which is Common Lisp's non-hygienic macro;
  - the compiler's own record accessors in `lib/compiler/codegen.lisp`, which
    capture nothing;
  - the examples and tests of `define-macro` itself.

### 9.4 Generalized `set!` (SRFI 17), and `setf` (accepted 2026-11-09)

Two parts: **9.4a**, this section, and **9.4b**, the rest, below.

Appended on 2026-11-09 from issue #5, "Dynamic array assignment". The issue
asks that `(set! (car x) 'n)` assign the list's first element. Today it fails
with `set!: bad name: (car x)`. `set-car!` and `set-cdr!` do it already, but the
place syntax is the familiar one.

**Where we start (checked 2026-11-09):**
- `set!` takes only a variable, as in R7RS: the special form in
  `lib/compiler/compiler.lisp` rejects anything that is not an identifier.
- `setf` is not defined anywhere. `lib/cl.lisp` has `setq`, `defparameter`,
  `push` and `pop`, and `push` and `pop` expand to `set!` of their place.
- `set-car!`, `set-cdr!`, `vector-set!`, `string-set!` and `hash-table-set!`
  exist.

**Follow SRFI 17 ("Generalized set!")**, which Guile, Chicken, Gauche and Kawa
implement, rather than invent a rule of our own:
- `(set! (proc arg ...) value)` means `((setter proc) arg ... value)`.
- `proc` and the arguments are evaluated as usual, in the scope of the `set!`,
  so a local `car` is that local procedure.
- `(set! name value)` is unchanged.

**What changes:**
- **The `set!` special form** (`lib/compiler/compiler.lisp`): a target that is
  a call, `(proc arg ...)`, compiles to `((setter proc) arg ... value)`.
  - The `setter` it calls is the global one, reached directly, the way the
    compiler reaches its other runtime procedures. A program's own local
    `setter` cannot capture it.
  - Any other target (a number, a string, `()`) is still
    `set!: bad name: <target>`.
- **`setter`** (`lib/core.lisp`): `(setter proc)` answers proc's setter
  procedure. It signals `setter: no setter for <proc>` when proc has none.
  - It knows, from the start:

    | getter | setter |
    |---|---|
    | `car` | `set-car!` |
    | `cdr` | `set-cdr!` |
    | `vector-ref` | `vector-set!` |
    | `string-ref` | `string-set!` |
    | `hash-table-ref` | `hash-table-set!` |
    | `hash-table-ref/default` | a procedure that ignores the default and sets the key |

    The last one makes a counter read naturally:
    `(set! (hash-table-ref/default h w 0) (+ 1 (hash-table-ref/default h w 0)))`.
  - **A program adds its own** with `(set! (setter f) g)`, which is
    generalized `set!` itself: `setter`'s own setter registers one, as SRFI 17
    specifies.
  - The table is keyed by the procedure object, so a renamed or copied
    procedure needs its own entry.
  - `hash-table-ref` with its optional `missing` argument passes that argument
    on to `hash-table-set!`, which then fails on its arity. SRFI 17 behaves the
    same way, and the documentation says so.
- **`setf`** (`lib/cl.lisp`):
  - `(setf place value ...)` takes pairs, like `setq`.
  - Each place is a variable or a call, assigned with the generalized `set!`.
  - It answers the last value, as Common Lisp's does, evaluating each value
    once.
  - `push` and `pop` then work on places too: `(push 0 (car x))`.
- **Documentation:**
  - `set!`'s documentation string gains the call form;
  - `setter` and `setf` are documented, and the reference, hover data, manual
    and skill are regenerated;
  - the skill gains a line or a trap only if its suite shows the need.
- **The rest is 9.4b**, below: `getter-with-setter`, `defsetf`, the Common Lisp
  accessors' setters, and the compile-time shortcut. This part, 9.4a, is
  generalized `set!`, `setter` and `setf`.

**Checks:** a LISP test, `tests/lisp/phase-9.4-generalized-set.lisp`:
- the issue's example, `(set! (car x) 'n)` giving `(n b c)`;
- each built-in setter, including `vector-ref` (the issue's title) and
  `hash-table-ref/default`;
- `(set! (setter f) g)` and then `(set! (f ...) v)`;
- the arguments and the value evaluated once each, left to right;
- a local `car`, and a local `setter`, that do not change what the compiler
  does;
- the errors: no setter, and a bad target;
- `setf` with pairs and its answer, and `push` and `pop` on `(car x)`;
- a `syntax-rules` macro that expands to `(set! (car ,a) ...)`.

**The example:** `examples/places.lisp`, with its `.expected`, added to the
lists chapter of the manual.

**The self-hosting rule:**
- The compiler gains the feature but does not use it.
- `setter` in `lib/core.lisp` is plain code: a hash table and procedures.
  The seed compiles `core.lisp`, so it must not use the generalized `set!`
  either.
- `lib/cl.lisp` is loaded by programs at run time, by the new compiler, so
  `setf` may use the generalized `set!` from the start.

**Issue #5** is closed by the commit that implements 9.4a.

#### 9.4b The rest of generalized assignment (accepted 2026-11-09)

What 9.4a leaves out, specified at the owner's request (2026-11-09). It follows
9.4a and needs it.

**`getter-with-setter`** (SRFI 17, `lib/core.lisp`):
- `(getter-with-setter get set)` answers a new procedure that does what `get`
  does, and whose setter is `set`: `(set! ((getter-with-setter get set) x) v)`
  calls `(set x v)`.
- `get` itself is left as it is.
- The new procedure keeps `get`'s documentation.

**`defsetf`** (`lib/cl.lisp`), both of Common Lisp's forms, each defined
through `(set! (setter access) ...)`:
- **The short form:** `(defsetf access update)`. Here `(setf (access arg ...) v)`
  calls `(update arg ... v)`: the new value last, as Common Lisp's short form
  and SRFI 17 both pass it.
- **The long form:** `(defsetf access (param ...) (store) body ...)`. Here
  `(setf (access arg ...) v)` runs the body with each param bound to its
  argument and `store` to `v`. The parameters take `&rest`, as `cl.lisp`'s
  `defun` does.
- It answers `access`'s name, as in Common Lisp.

**`define-setf-expander`: considered, and not provided** (the owner accepted this, 2026-11-09).
- Common Lisp's expander protocol (`get-setf-expansion` and its five values)
  assumes that `setf` expands each place at compile time. cog-lisp's `setf`
  finds its setter at run time, through `setter`, so an expander would have
  nothing to hook into.
- What programs use expanders for, places that read and write through
  temporaries, `defsetf`'s long form covers here.
- If the owner wants it anyway, it needs `setf` rebuilt as a compile-time
  expansion: a step of its own.

**The Common Lisp accessors' setters** (`lib/cl.lisp`):
- **Existing accessors** gain setters:
  - `first`, `second` and `third`, through `set-car!` on the right pair;
  - `rest`, through `set-cdr!`;
  - `nth`: `(setf (nth n lst) v)` sets the element.
- **New accessors**, with their setters:
  - `(aref vector index ...)`: one index, since cog-lisp's vectors have one
    dimension; more indexes are an error that says so. Its setter is
    `vector-set!`.
  - `(gethash key table [default])`: the value, or `default` (else `nil`, which
    is `()` here). The argument order is Common Lisp's, key first. Its setter
    sets the key, ignoring any default.
    - **Only the value is answered** (changed while building, 2026-11-09).
      Common Lisp also answers whether the key was there, as a second value,
      which a caller wanting one value never sees.
    - cog-lisp's multiple values do not collapse to the first value where one
      is expected: `(+ 1 (values 2 3))` fails with `+: not a number: 2 3`. So a
      second value would break `(+ 1 (gethash k h 0))`, the commonest use.
    - Presence is tested with `hash-table-contains?`, and `lib/cl.lisp`'s known
      gaps say so.
  - `(remhash key table)`, so that a table written with `gethash` can lose a
    key.
- They are documented, and `lib/cl.lisp`'s list of known gaps changes to
  match.

**The compile-time shortcut**, only if a benchmark shows it is worth having:
- **First, measure.** A benchmark in `bench/` runs `(set! (car p) i)` against
  `(set-car! p i)`, and `(set! (vector-ref v i) x)` against `(vector-set! v i x)`,
  a million times each, after a warm-up (CLAUDE.md, Phase 6). The result is
  recorded in `bench/results.md`.
- **Build it only if** the generalized form is more than 1.5 times slower.
- **What it would do:** when the target's head is a global name, not a local
  one, for one of the built-in getters, compile
  `(if (eq? car <the built-in car>) (set-car! x v) ((setter car) x v))`.
  - The built-in procedure is a literal in the method, so a program that
    redefines `car` still gets its own setter.
  - **The cost to SRFI 17:** a program can no longer change a built-in getter's
    setter. `(set! (setter car) g)` then signals
    `setter: the setter of car is built in`. The shortcut could not see such a
    change without the very lookup it removes.
- **If it is not built,** the measurement is recorded with the reason, and
  SRFI 17's behavior stays complete.

**Checks** (`tests/lisp/phase-9.4-generalized-set.lisp`, a second part):
- `getter-with-setter`;
- both forms of `defsetf`, with `&rest`;
- each Common Lisp accessor and its `setf`;
- `aref` with two indexes, and `gethash`'s default and its use in arithmetic;
- if the shortcut is built: a redefined `car`, and the refused
  `(set! (setter car) g)`.

The examples in `examples/` that use `lib/cl.lisp` gain a `setf` of a place.

#### 9.4b as built (2026-11-09)

- **The benchmark decided it.** In `bench/results.md`, before the shortcut:

  | Loop of 1,000,000 | direct | `set!` of the place | ratio |
  |---|---:|---:|---:|
  | `(car p)` | 33.8 ms | 703.0 ms | 20.8x |
  | `(vector-ref v 0)` | 75.0 ms | 734.0 ms | 9.8x |

  Both are far past 1.5 times, so the shortcut was built. After it, two runs:
  - 32.8 against 37.3 ms (1.1x), and 73.0 against 83.0 ms (1.1x);
  - 27.5 against 41.8 ms (1.5x), and 80.0 against 97.0 ms (1.2x). This run is
    the one committed in `bench/results.md`.

  Timings on this machine vary that much between runs. The shortcut's gain
  does not: from about 10 to 20 times slower, to within about 1.5 times.
- **How the shortcut recognizes a built-in getter.** The compiler recognizes it
  by identity, not by name.
  - `lib/core.lisp` keeps the built-in getters in a second table,
    `%builtin-setters`.
  - The shortcut is compiled only when the global's value, as the form is
    compiled, is in that table. A program that had already redefined `car`
    gets the plain `(setter car)` call.
  - The compiled test is
    `[car == <the built-in car>] ifTrue: [<set-car!>] ifFalse: [(setter car)]`.
    It chooses only the setter, which is then called once, with the arguments
    and the value. So nothing is compiled twice, and the order of evaluation
    stays SRFI 17's.
  - Both tables compare keys with `eq?`. The `equal?` table of 9.4a was slower
    than an identity table needs to be; the generic path's speed was not
    measured again.
- **Found on the way: the setters are keyed by procedure objects.**
  `bench/bench.st` reinstalls the primitives (`LispPrimitives installDefault`),
  which makes new procedure objects, and then `(setter car)` found nothing.
  - Anything that reinstalls the primitives must load `lib/core.lisp` again,
    and the benchmark now does.
  - Normal runs never reinstall them: every suite passed.
- **`gethash` answers only the value.** See above: cog-lisp's multiple values do
  not collapse to the first value where one is expected.
- **`defsetf`'s long form** passes the new value last, after any `&rest`
  arguments, so its setter takes all its arguments and splits off the last.
- **Checks:** `tests/lisp/phase-9.4-generalized-set.lisp`, 66/66, covering
  9.4a and 9.4b. Among them:
  - a `set!` compiled while `car` was the built-in one, run after `car` was
    redefined (it reaches the program's setter), and again after `car` was
    restored;
  - `(set! (setter car) g)` refused with
    `setter: the setter of car is built in`.

  `examples/cl-style.lisp` gains `setf` of `second`, `nth` and `gethash`.

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

**Checked 2026-11-05.**
- AC-4 (9.4) `(set! (proc arg ...) value)` assigns through `(setter proc)`, as
  SRFI 17 specifies, for the built-in getters and for setters a program adds.
  `setf` in `lib/cl.lisp` assigns variables and places. Issue #5's example
  gives `(n b c)`. All of it is checked by
  `tests/lisp/phase-9.4-generalized-set.lisp`, and the example runs (9.4a).
  9.4b adds `getter-with-setter`, `defsetf` (both forms), and setters for
  Common Lisp's `first`, `second`, `third`, `rest`, `nth` and the new `aref`
  and `gethash`, each checked by the same test. The benchmark of the
  generalized form is recorded, with the shortcut built only if it is more than
  1.5 times slower.
- AC-1: every suite passes on Windows and Linux, and in CI; the recovery job
  rebuilds the seed from source (recursively, v0.1.3 then v0.1.2).
- The benchmarks pass 14/14 on Windows and, by the benchmarks workflow
  (run 42091231387), on Linux, where compiling took 15.1 ms.
- AC-2 and AC-3: the LISP tests named in 9.2 and 9.3; R-11, R-21 and C-14 are
  closed in the review record.

## 6. Examples

| Example | Proves |
|---|---|
| `examples/seeded-build.lisp` | the running image's seed and stages, read back from the image itself |
| `examples/numbers.lisp` | rationals, exactness, the read syntax, infinities and NaN, the division family |
| `examples/new-number-type.lisp` | a number type added from outside the core, used in ordinary arithmetic |
| `examples/syntax-rules.lisp` | `syntax-rules` macros, ellipses, and hygiene in both directions |
| `examples/shadowing.lisp` | a local named `if`, and a local `memv` that `case` does not see |
| `examples/places.lisp` | `set!` of a list's element, a vector's slot and a hash table's entry, and a setter a program adds (9.4) |

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

1. **Two phases**: this one is the language; the pure image is Phase 11, which
   will take a long time and add graphics and networking.
2. **The runtime is rewritten in LISP** (Phase 11, step 11.1).
3. **Complex numbers are a library**, addable at any time: the tower is built open
   to new kinds of number (9.2).
4. **Hygiene by renaming** (aliases), not syntactic closures or `syntax-case`.
5. **Our own VM: a spike first** (Phase 11, step 11.4).

## 9. Step status

| Step | Status |
|---|---|
| 9.1 Seeded builds | done (2026-11-05): built from the v0.1.2 seed (9.1a); the Smalltalk reader and compiler retired (9.1b); the seed rebuilt from its source in CI (9.1c) |
| 9.2 Numeric tower | done (2026-11-05): read, print, predicates, exactness, IEEE division, type errors (9.2a; R-11, R-21 closed); multiple values and the numeric procedures (9.2b); dual numbers added from outside the core, with their read syntax (9.2c) |
| 9.3 Hygienic macros | done (2026-11-05): aliases and resolution, shadowable special forms, syntax-rules, define-syntax, let-syntax, letrec-syntax, syntax-error (9.3a); the derived forms hygienic, in lib/core-syntax.lisp (9.3b); C-14 closed |
| 9.4a Generalized set! and setf | done (2026-11-09): set! of a call through (setter proc), setters for car, cdr, vector-ref, string-ref, hash-table-ref and hash-table-ref/default, (set! (setter f) g); setf in lib/cl.lisp; examples/places.lisp; issue #5 closed |
| 9.4b getter-with-setter, defsetf, the CL accessors' setters, the shortcut | done (2026-11-09): all four; the benchmark found set! of a place 20.8x slower, so the shortcut was built (1.1x to 1.5x after); gethash answers one value |
