# Spec — Phase 6: Tail Calls & Optimization

| | |
|---|---|
| **Phase** | 6 |
| **Status** | Implemented (2026-11-02) — `tests/phase-6-tail-calls.st` 127/127; `bench\run-benchmarks.bat` 12/12 (including §11, guarded inlining, added 2026-11-03) |
| **Depends on** | Phases 1–5 |
| **Feeds** | Phase 7 (macros), Phase 8 (self-hosting), Phase 9 (pure image) |
| **Tail calls** | Proper tail calls: self tail calls become loops; other tail calls use a trampoline |
| **Baselines** | Hand-written Smalltalk (the ceiling) and a tree-walking interpreter (the floor) |

## 1. Goal

Make cog-lisp **correct for iterative code** and **measurably fast**:

- **Proper tail calls**, as Scheme specifies: a procedure that calls another in
  tail position does not grow the stack. Loops written as recursion, mutual
  recursion, and state machines run in constant stack. Cog has no tail-call
  support, so cog-lisp provides it.
- **Remove the main per-call and per-reference overheads** in the Phase 3–5
  compiler.
- **Measure** all of it against two reference points, so "compiled to JIT-native
  bytecode" is a number, not a claim.

## 2. Scope

**In scope**
- Tail-position analysis and proper tail calls (§4).
- Fast calls: arity-specialized call paths with no argument-array allocation (§5.1).
- Global variable cells resolved at compile time (§5.2).
- Quoted constants as literals (§5.3).
- `let` compiled as direct block evaluation (§5.4).
- A `(stack-depth)` introspection primitive (used to test constant stack).
- A benchmark suite with two baselines and a before/after report (§6).

**Deferred**
- Emitting raw SistaV1 bytecode (`EncoderForSistaV1`) and Sista/Scorch adaptive
  optimization. Revisited only if the benchmarks show that Opal's code generation,
  rather than our calling convention, is the bottleneck.
- Internal `define`, `letrec`, named `let` (still deferred from Phase 3; they are
  natural with macros in Phase 7). Self tail calls here work through top-level
  `define`.
- Unboxed or type-specialized arithmetic.

## 3. Decisions

- **Tail calls (settled):** self tail calls compile to loops; every other tail
  call returns a trampoline "bounce". This gives full proper tail calls while the
  most common case, a procedure looping on itself, costs nothing extra.
- **Baselines (settled):** equivalent hand-written Smalltalk shows how close to
  native cog-lisp gets; a small tree-walking LISP interpreter, built only for the
  benchmarks, shows what compiling buys.
- **Lean on Pharo.** Global cells mirror how Smalltalk itself compiles globals
  (a binding object in the method's literal frame). Loops are ordinary Smalltalk
  `whileTrue:` loops that Opal inlines and Cog JITs.
- **Each optimization can be switched off** by a compiler setting
  (`LispCompiler` options). The benchmarks use this for before/after
  measurements; it also helps when debugging codegen. Default: all on.

## 4. Proper tail calls

### 4.1 Tail position

An expression is in **tail position** when its value is returned directly as the
value of the enclosing procedure:
- the last expression of a `lambda` body;
- both branches of an `if` that is itself in tail position (not the test);
- the last expression of a `begin` in tail position;
- the last expression of a `let` body, when the `let` is in tail position.

Not in tail position: `if` tests, arguments of any call, the value expressions of
`define`, `set!`, and `let` bindings, and every top-level form (the top level is
not a procedure; top-level calls are ordinary calls).

Tail position stops at a `lambda`: a nested `lambda` starts its own procedure.

### 4.2 Self tail calls become loops

Inside `(define (f p…) body…)`, a call to `f` in tail position is a **self tail
call**. The procedure's body runs inside a loop; a self tail call evaluates all
new argument values first, assigns them to the parameter temporaries, and goes
round the loop again instead of calling. Shape of the generated code:

```smalltalk
[:a1 :a2 | | p1 p2 again result |
	p1 := a1. p2 := a2.
	again := true.
	[again] whileTrue: [
		again := false.
		result := <body>]   "a self tail call in <body> sets p1/p2 and again := true"
	result]
```

**Redefinition stays correct.** The global `f` can be rebound while the old
procedure is running. So a self tail call first checks that the global still
holds *this* procedure (an identity check on the global cell, §5.2); if it does
not, the call becomes an ordinary tail call (§4.3) to whatever `f` now is.

### 4.3 Other tail calls use a trampoline

Any other call in tail position compiles to a **bounce**: a small `LispTailCall`
object holding the procedure and its arguments, returned instead of calling.
Every *non-tail* call site, and every primitive that calls procedures (`map`,
`for-each`, `apply`), **drives** the result: while it is a `LispTailCall`, run
it. The stack therefore holds at most one frame for any chain of tail calls.

- A bounce never escapes to LISP code: the code that receives a procedure's
  result always drives it first.
- Cost: an allocation per non-self tail call, and a class check on each call's
  result.

### 4.4 `(stack-depth)`

A primitive answering the number of contexts on the current process's stack. It
makes constant-stack behaviour testable. It may also serve later reflection
needs.

## 5. Optimizations

### 5.1 Fast calls

A non-tail call `(f a b)` compiles to an arity-specialized entry,
`LispProcedure call: f with: a with: b` (0–4 arguments). When `f` is a fixed-arity
`LispProcedure` of exactly that arity, the entry calls its block directly
(`block value: a value: b`), with no argument array, then drives the result.
Anything else (variadic, wrong count, more than 4 arguments, not a procedure)
falls back to the general `apply:to:`, which keeps today's behaviour and errors.

### 5.2 Global variable cells

Every global becomes a **cell** (`LispGlobal`: a value and a bound flag) owned by
the environment. The compiler resolves a global name to its cell **once, at
compile time**, and the compiled code holds the cell itself as a literal.
Referencing the global reads the cell; `define` and `set!` write it.

- One indirection at run time, instead of `LispSymbol named:` plus a dictionary
  lookup on every reference.
- Forward references work: compiling a reference to a not-yet-defined global
  creates an unbound cell, which a later `define` binds.
- Reading an unbound cell still raises `LispUnboundError`; `set!` on an unbound
  cell still raises it.
- The Phase 2 `LispEnvironment` API (`define:value:`, `lookup:`, `set:value:`,
  `isBound:`, `at:ifAbsent:`) is unchanged, now implemented over cells.
- *Probe first:* that Opal accepts an arbitrary object as a literal-node value and
  keeps it in the literal frame across `save-image`.

### 5.3 Quoted constants are literals

`(quote d)` compiles to the datum itself as a literal, instead of code that
rebuilds it on every evaluation (the Phase 3 decision). Each evaluation of a
given `quote` yields the **same** object, as in Scheme, and no allocation
happens. (Mutating a quoted constant is an error in Scheme; cog-lisp does not
detect it.)

### 5.4 `let` as direct block evaluation

`let` compiles to a Smalltalk block evaluated in place (`[:v1 :v2 | body] value:
e1 value: e2`), not to a `LispProcedure` that is then applied. This avoids
creating a procedure object per `let`, and keeps a `let` in tail position from
being treated as a tail *call* (its body inherits tail position instead, §4.1).

## 6. Benchmarks

`bench\run-benchmarks.bat` runs `bench/bench.st` against `pharo\cog-lisp.image`
and prints a table. Each benchmark exists in three forms: cog-lisp (compiled), the
same LISP source on the **tree-walking interpreter**, and **hand-written
Smalltalk**.

| Benchmark | Exercises |
|---|---|
| `fib 25` | non-tail recursion, calls |
| `tak 18 12 6` | many small calls |
| `loop 1e6` | self tail call (loop) |
| `even?/odd? 1e5` | mutual tail calls (trampoline) |
| `list 1e5` | build a list, `map`, sum it |
| `globals` | a loop that reads several globals per iteration |

- **Timing:** each measurement is the median of 5 runs after a warm-up run (so the
  JIT has compiled the code).
- **Before/after:** the cog-lisp column is measured with all optimizations on and,
  for each optimization, with that one switched off.
- **Report:** milliseconds per benchmark per implementation, plus the ratios
  compiled ÷ tree-walker and compiled ÷ Smalltalk.
- The **tree-walker** (`bench/tree-walker.st`, class `LispTreeWalker`) evaluates
  the Phase 3 core forms by walking the data with an environment of frames,
  calling primitives through `LispProcedure apply:to:`. It lives in `bench/`, is
  loaded only by the benchmark script, and is not part of the cog-lisp image.

## 7. Acceptance criteria

**`tests/phase-6-tail-calls.st`** (headless, in-image):

*Tail calls*
- AC-1 A self-tail-recursive loop of 1,000,000 iterations returns the right
  result, and `(stack-depth)` at iteration 1,000 equals it at iteration 1.
- AC-2 Mutual recursion: `even?`/`odd?` defined by mutual tail calls returns the
  right answer for 100,000, with constant `(stack-depth)`.
- AC-3 Tail position through `if` (both branches), `begin`, and `let` runs in
  constant stack.
- AC-4 Non-tail calls are unaffected: `(fact 20)` is correct, and `(stack-depth)`
  grows with depth in a non-tail recursion.
- AC-5 Redefinition: a procedure saved before its global `f` is redefined, whose
  body self-tail-calls `f`, continues into the *new* definition.
- AC-6 A procedure passed to `map`/`for-each`/`apply` that makes tail calls
  returns correct values (a bounce never escapes).
- AC-7 Arity errors and "not applicable" errors still occur, through both the
  fast path and tail calls.

*Optimizations*
- AC-8 Fast calls: calls of 0–4 arguments, variadic calls, and calls of more
  than 4 arguments all evaluate correctly.
- AC-9 Global cells: a forward reference works once defined; redefinition is
  visible to already-compiled code; an unbound reference still raises
  `LispUnboundError`; the Phase 2 environment API behaves as before.
- AC-10 `(define (k) '(1 2))` then `(eq? (k) (k))` → `#t`.
- AC-11 `let` still scopes and shadows correctly.
- AC-12 Each optimization switch can be turned off, and the suite's correctness
  checks pass both ways.
- AC-13 Global cells survive `save-image` (checked by the runner suite's
  persistence test).

**`bench\run-benchmarks.bat`:**
- AC-14 It runs every benchmark in all three implementations and prints the
  report.
- AC-15 Compiled cog-lisp is faster than the tree-walker on every benchmark.
- AC-16 Each optimization makes its target benchmark faster than with it switched
  off (fast calls → `fib`/`tak`; global cells → `globals`; tail calls → `loop`).
- AC-17 The report is saved as `bench/results.md` and committed, so later phases
  can compare against it. (Ratios are recorded, not asserted against fixed
  thresholds; machines vary.)

**Regression**
- AC-18 All earlier suites pass, and the examples still match their output.

## 8. Resolved decisions

Settled 2026-11-02 (owner sign-off); the spec is Accepted on these.

1. **Optimization switches stay permanently** in `LispCompiler`, for benchmarks
   and debugging.
2. **Quoted constants become literals** (same object each evaluation),
   reversing the Phase 3 reconstruction decision.
3. **Benchmark home:** `bench/`, with the tree-walker kept out of `src/` and out of
   the cog-lisp image.
4. **Improvement criterion:** median of 5 warm runs; "faster" means a ratio above
   1.0, with no fixed threshold.
5. **`(stack-depth)`** keeps a plain name, since it is also useful for reflection.

## 9. Downstream notes

- **Phase 7** macros can provide named `let`, `do`, and `loop`-style iteration,
  all of which rely on proper tail calls to run in constant stack.
- **Phase 8** (self-hosting): a compiler written in LISP is deeply recursive over
  its input; proper tail calls and fast calls keep it practical.
- **Phase 9**: global cells and literal constants live in the image like any
  object, so they need nothing from Pharo's `.sources`/`.changes` files.
- `bench/results.md` becomes the baseline for any later performance work.

## 10. As implemented

Where the implementation settled details the spec left open, or the benchmarks
forced a change:

- **Variadic primitives have fixed-arity entries** (revising §5.1, which had
  variadic calls fall back to the general path). The first benchmark run showed
  that `+`, `-`, `<`, `=` and the like dominated: they are variadic, so every
  `(+ a 1)` built an argument array, a rest list and a collection to fold over,
  and fast calls could not help (AC-16 failed for `fib` at 0.9×). Now a
  procedure may carry direct entries for 0–4 arguments
  (`LispProcedure>>entry:is:`), and the fast-call path uses them. The arithmetic,
  comparison, `min` and `max` primitives have them. `(+ a b)` is one block call.
- **Tail calls to primitives are made directly, not bounced** (refining §4.3). A
  primitive cannot grow the stack, so bouncing it only cost an allocation and the
  slow call path: `fib` ran 3.4× faster with tail calls *off* until this was
  fixed. A primitive is a procedure with no LISP source (`isPrimitive`). The
  exception is `apply`, which now *returns* a bounce instead of calling, so a tail
  call through `apply` runs in constant stack (checked in AC-6).
- **Arity-specialized tail calls** (`LispProcedure tailCall:with:…`, 0–4
  arguments) mirror the fast calls, under the `#fastCalls` option.
- **Self-loop shape.** A defined procedure whose body self-tail-calls compiles to
  `[| p | p := LispProcedure fixed: [...] .... p] value`, so the loop can compare
  the global's current value with `p` (redefinition check, §4.2). The loop and
  the extra temporaries are only generated when a self tail call is present.
- **`(stack-depth)`** counts the contexts on the current process's stack.
- **Benchmark method.** The VM clock ticks in whole milliseconds, so each timed
  sample repeats a run until it takes at least 100 ms and divides by the count.
  Each series starts after a garbage collection, and the whole matrix is run once
  as a discarded warm-up: without it, whichever configuration ran first measured
  up to 40% slower.
- **Benchmark sizes** are smaller than §6 listed (fib 22, loop 100,000, even?/odd?
  20,000, list 20,000, globals 50,000), so the tree-walker, which recurses on the
  host stack, finishes in reasonable time and memory.
- **Results** (in `bench/results.md`): compiled cog-lisp is 33–193× faster than
  the tree-walker and 2.4–67× slower than hand-written Smalltalk. With an
  optimization switched off, its target benchmark slows by 4.6× (global cells,
  `globals`) to 15× (tail calls, `loop`).
- **Next performance step** (done afterwards; see §11): guarded inlining of primitives.
  The remaining gap to Smalltalk is mostly that `(+ a b)` is still a call, where
  Smalltalk's JIT inlines integer arithmetic. The compiler could emit `a + b`
  directly when the global `+` still holds the original primitive, checked by
  identity as the self-loop check is.

## 11. Addendum: guarded inlining of primitives

Added 2026-11-03, after the main phase, to close part of the gap to Smalltalk
that §10 attributed to arithmetic being a call. **Redefining a primitive must
keep working** (owner requirement): `(define (+ a b) …)` changes what every
`(+ a b)` does, including in code compiled earlier.

### 11.1 Design

A call `(op a b …)` is inlined when `op` is a global, not shadowed by a local,
and at compile time its cell holds a primitive that declares an **inline form**
for that many arguments. The compiler emits, with fresh temporaries:

```smalltalk
true ifTrue: [| f x y |
	f := <read op's cell>.  x := <a>.  y := <b>.
	f == <that primitive, as a literal>
		ifTrue: [x + y]                              "the inline form"
		ifFalse: [LispProcedure call: f with: x with: y]]   "or tailCall: in tail position"
```

- Opal inlines the `true ifTrue:` block, so its temporaries are ordinary method
  temporaries and no closure is created. Each argument is evaluated once, after
  the operator, in the same order as an ordinary call.
- The guard is one identity comparison, which the JIT compiles inline. If `op`
  is rebound (before or after compiling), the guard fails and the call goes to
  whatever `op` now holds. Restoring the original makes the guard pass again.
- The inline form is exactly what the primitive's fixed-arity entry does
  (`[:a :b | a + b]` → `x + y`), so results and errors are unchanged.
- It is a `LispCompiler` option, `#inlinePrimitives`, on by default.

### 11.2 Inline forms

| Primitive | Arguments | Inline form |
|---|---|---|
| `+ - * = < > <= >=` | 2 | the Smalltalk binary send of the same name |
| `eq?` | 2 | `x == y` |
| `car`, `cdr` | 1 | `x car`, `x cdr` |
| `not` | 1 | `x == false` |
| `null?` | 1 | `x == ()` (the empty-list object as a literal) |

A primitive declares its inline form with `LispProcedure>>inline:`.

### 11.3 Acceptance criteria

In `tests/phase-6-tail-calls.st`:
- AC-19 Inlined calls return the same results as calls, for every form in §11.2,
  including in tail position and at top level.
- AC-20 A procedure compiled while `+` is the primitive follows a later
  redefinition of `+`, and returns to the fast path when `+` is restored.
- AC-21 A procedure compiled while `+` is redefined calls the redefinition.
- AC-22 A local variable named `+` is never inlined: `(let ((+ -)) (+ 5 3))` → 2.
- AC-23 Inlining really happens: the compiled code contains the `+` send.
- AC-12's sweep includes the new option, so every correctness check also runs
  with inlining off.

In `bench\run-benchmarks.bat`:
- AC-24 `#inlinePrimitives` makes `fib` and `tak` faster than with it off.

### 11.4 As implemented

Status: implemented 2026-11-03. `tests/phase-6-tail-calls.st` 127/127 (AC-19–23,
and the AC-12 sweep with inlining off); `bench\run-benchmarks.bat` 12/12 (AC-24).

- **Simple arguments get no temporary** (revising §11.1). The first version gave
  every call a temporary for the operator and one per argument. Temporaries of
  inlined blocks all land in the enclosing procedure's frame, and a wide
  expression hit the VM's limit ("stack including temps is too deep"). Now a
  literal, quoted datum, or variable is used directly (only one branch runs, so
  it is still evaluated once), and the guard reads the operator's global
  directly. `(+ n 1)` compiles to `(+cell value == prim) ifTrue: [n + 1] ifFalse:
  [...]` with no temporaries at all.
- **Nested calls in argument position still take a temporary**, assigned before
  the guard inside `true ifTrue: [| t | ...]`. So when an argument is itself a
  call, it is evaluated *before* the operator, unlike an ordinary call. Scheme
  leaves this order unspecified; it only shows if an argument rebinds the
  operator.
- **A budget of 12 such temporaries per procedure**: past it, a call is not
  inlined. Checked by a wide-expression test.
- **Results:** `fib` 5.84 → 2.34 ms and `tak` 6.25 → 2.14 ms. The gap to
  hand-written Smalltalk narrowed from 28× to 12× (`fib`) and from 26× to 10×
  (`tak`). With inlining off, `tak` is 2.7× slower and `loop` 3.6× slower.
- **Noise:** one benchmark run showed `globals` at 45.8 ms with everything on
  (vs ~25 ms in every other column); an immediate rerun gave 24.8 ms. Single
  runs can still be disturbed by other load on the machine; rerun before
  trusting an outlier.
