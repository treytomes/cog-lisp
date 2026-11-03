# Spec — Phase 4: Runtime & Primitives

| | |
|---|---|
| **Phase** | 4 |
| **Status** | Implemented (2026-11-02) — `tests/phase-4-runtime.st` passes 44/44; revised Phase 3 suite 31/31 |
| **Depends on** | Phase 1 (reader), Phase 2 (core), Phase 3 (compiler) |
| **Feeds** | Phase 5 (REPL & runner), Phase 6 (optimization) |
| **Procedure model** | `LispProcedure` wrapper + uniform `applyTo:` an args array |

## 1. Goal

Turn the compiled core into a language you can actually program in: a **primitive
library** bound in the global environment (pairs/lists, arithmetic, comparison,
predicates, basic I/O), **variadic (rest) parameters**, `apply`, and proper
**arity errors**. After Phase 4, non-trivial LISP programs — recursive list
processing, higher-order functions over `map` — run end to end.

## 2. Scope

**In scope**
- `LispProcedure`: the uniform procedure representation and calling convention.
- Variadic lambda parameters: `(lambda (a . rest) …)`, `(lambda args …)`, and the
  `(define (f a . rest) …)` sugar.
- The Phase 4 **primitive library** (§7).
- `apply`; LISP-level **arity errors**.
- Revising the Phase 3 compiler's lambda/application codegen to this convention,
  and updating the Phase 3 suite to match (§6).
- A machine-checkable acceptance suite, including a small end-to-end program.

**Deferred (out of scope for Phase 4)**
- `and` / `or` (short-circuit) and other control macros — Phase 7 (macros).
- Multi-list `map`/`for-each`; the full numeric tower (rationals, complex);
  string/char libraries; vectors, hash tables; ports/files; `call/cc` — later.
- **Tail-call optimization** and a fixed-arity fast path — Phase 6.
- The CLI runner and REPL (the "run a program from the host OS" goal) — Phase 5.

## 3. Decisions

- **Procedures are `LispProcedure`s** wrapping a Smalltalk block plus arity
  metadata (`required` count, `hasRest`). **All application goes through
  `LispProcedure apply: fn to: anArgsArray`**, which checks arity, binds the rest
  list for variadic procedures, and raises a LISP arity error otherwise. The
  wrapped block is still a native, JITted `BlockClosure` — we lean on Pharo for
  the execution, and add only a thin arity-aware envelope.
- **This revises the Phase 3 calling convention** (which called bare blocks via
  `value:`), so Phase 4 updates the compiler and the Phase 3 suite (§6). The
  Phase 3 spec is annotated as superseded on this point.
- **Variadic encoding:** a procedure with `required = n` and `hasRest = true` is a
  block of `n+1` arguments; `applyTo:` passes the first `n` actual arguments
  through and the remaining ones as a single LISP list in the last slot.
- **Variadic arithmetic / chained comparison:** `+ *` fold over all arguments
  (`(+)`→0, `(*)`→1); `- /` take one argument as negate/reciprocal and 2+ as a
  left fold; `= < > <= >=` are **chained** (`(< 1 2 3)` is true iff strictly
  increasing).
- **I/O** (`display`, `write`, `newline`) writes to `Stdio stdout` so it works
  headless; Phase 5 may redirect it. `write` uses the Phase 1 printer. (Since
  Phase 5, output goes through `LispPrimitives output`, a `LispTextOutput` that
  encodes text for a console, pipe or file.)

## 4. New types

Package `CogLisp-Runtime` (loads after the compiler).

- **`LispProcedure`** — wraps `block`, `required`, `hasRest`, and an optional
  `name` (for printing / errors). It is a **wrapper, not a subclass**, of
  `BlockClosure`: all execution and lexical capture stay the block's; the wrapper
  adds only the one thing a block cannot express — **arity policy** (a block's
  `numArgs` cannot distinguish "exactly 2 args" from "1 fixed + rest"). Subclassing
  `BlockClosure` is not viable anyway — the VM manufactures plain `BlockClosure`s
  via the closure bytecode and never a subclass — so composition is both idiomatic
  and leaning-on-Pharo, not a reinvention. The envelope is only needed where arity
  is uncertain; Phase 6 may call the block directly for statically-known
  fixed-arity calls.
- **`LispArityError`** — `Error` subclass raised on an arity mismatch; carries the
  procedure and the actual count.
- **`LispPrimitives`** — installs the library: `LispPrimitives installInto: anEnv`
  (and a convenience that targets `LispEnvironment default`).

## 5. `LispProcedure`

```smalltalk
LispProcedure fixed: aBlock arity: n            "required=n, hasRest=false"
LispProcedure variadic: aBlock required: n       "required=n, hasRest=true (block takes n+1 args)"
LispProcedure class >> apply: fn to: anArray      "the one application entry point"
aProc applyTo: anArray                            "arity-checked invocation"
aProc isVariadic   aProc name   aProc name: aString
```

`apply: fn to: anArray` — if `fn` is not a `LispProcedure`, raise a LISP error
("object is not applicable"); otherwise `fn applyTo: anArray`.

`applyTo: anArray`:
- `hasRest = false`: require `anArray size = required`, else `LispArityError`;
  then `block valueWithArguments: anArray`.
- `hasRest = true`: require `anArray size >= required`, else `LispArityError`;
  pass the first `required` args plus one final argument — the remaining args as a
  LISP list (`LispCons fromArray:`, or the empty list when none).

## 6. Compiler changes (revising Phase 3)

- **`lambda`** now compiles to a `LispProcedure`:
  - Parse the parameter spec into `fixed` symbols and an optional `rest` symbol:
    a proper list → all fixed; a dotted list `(a b . r)` → fixed `a b`, rest `r`;
    a bare symbol `args` → rest only.
  - Build the block over the fixed params **plus** the rest param when present
    (each still bound to a mutable temporary, per Phase 3), then wrap:
    `LispProcedure fixed: block arity: n` or `variadic: block required: n`.
- **Application** `(f a b)` compiles to
  `LispProcedure apply: <fVal> to: {<aVal>. <bVal>}` (a runtime args array),
  replacing the Phase 3 arity-selected `value:` sends.
- **Impact on the Phase 3 suite:** applications now require the operator to be a
  `LispProcedure`, and a `lambda` evaluates to a `LispProcedure` (not a bare
  `BlockClosure`). Phase 4 updates `tests/phase-3-compiler.st` so its hand-bound
  primitives are `LispProcedure`s and AC-11 asserts `LispProcedure`; the Phase 3
  spec is annotated accordingly. Both suites stay green.
- *Implementation note:* constructing the runtime args-array node (a brace array)
  uses the same template-splice technique as message nodes; the exact node class
  is probed against the live image first.

## 7. The Phase 4 primitive library

Bound in the global environment by `LispPrimitives`. Representative core (final
list may grow slightly during implementation):

**Pairs & lists:** `cons` `car` `cdr` `pair?` `null?` `list?` `list`(var)
`length` `append`(var) `reverse` `set-car!` `set-cdr!` `map`(proc + 1 list)
`for-each`(proc + 1 list).

**Numbers:** `+` `-` `*` `/` (variadic per §3); `=` `<` `>` `<=` `>=` (chained);
`modulo` `quotient` `abs` `min`(var) `max`(var) `zero?` `positive?` `negative?`.

**Predicates & equality:** `eq?` `eqv?` `equal?` `not` `pair?` `null?` `symbol?`
`number?` `integer?` `string?` `char?` `boolean?` `procedure?` `list?` (the
`LispCore` facade promoted to callable procedures; `procedure?` is now meaningful
= `isKindOf: LispProcedure`).

**I/O:** `display` `write` `newline` (to `Stdio stdout`).

**Control:** `apply`.

Each primitive is a `LispProcedure` of the right arity, so arity errors and
variadics are uniform with user procedures.

## 8. Acceptance criteria

Realized as `tests/phase-4-runtime.st` (files in reader, core, compiler, runtime;
installs the primitive library), PASS/FAIL per check, final `RESULT: n/n`. `ev` =
`LispCompiler new evalString:` / `evalAll:` against the default environment.

**Procedures & variadics**
- AC-1 `lambda` evaluates to a `LispProcedure`; `procedure?` of it is `#t`.
- AC-2 fixed arity: `((lambda (x y) (+ x y)) 2 3)` → 5; wrong count →
  `LispArityError`.
- AC-3 rest: `((lambda args args) 1 2 3)` → `(1 2 3)`; `((lambda (a . r) r) 1 2 3)`
  → `(2 3)`; `((lambda (a . r) r) 9)` → `()`.
- AC-4 variadic `define`: `(define (f a . rest) rest)` then `(f 1 2 3)` → `(2 3)`.

**Pairs & lists**
- AC-5 `cons`/`car`/`cdr`: `(car (cons 1 2))`→1, `(cdr (cons 1 2))`→2.
- AC-6 `(list 1 2 3)` → `(1 2 3)`; `(length (list 1 2 3))`→3; `(null? (list))`→#t.
- AC-7 `(append '(1 2) '(3 4))`→`(1 2 3 4)`; `(reverse '(1 2 3))`→`(3 2 1)`.
- AC-8 `set-car!`/`set-cdr!` mutate a pair.
- AC-9 `(map (lambda (x) (* x x)) '(1 2 3))` → `(1 4 9)`.

**Numbers**
- AC-10 variadic `+`/`*`: `(+ 1 2 3)`→6, `(+)`→0, `(* 2 3 4)`→24, `(*)`→1.
- AC-11 `-`/`/`: `(- 5)`→-5, `(- 10 3 2)`→5.
- AC-12 chained comparison: `(< 1 2 3)`→#t, `(< 1 3 2)`→#f, `(= 2 2 2)`→#t.
- AC-13 `modulo`/`quotient`/`zero?`: `(modulo 7 3)`→1, `(zero? 0)`→#t.

**Predicates / equality**
- AC-14 `eq?`/`equal?`/`not`: `(equal? '(1 2) '(1 2))`→#t, `(not #f)`→#t,
  `(not 0)`→#f.
- AC-15 type predicates callable: `(number? 3)`→#t, `(symbol? 'x)`→#t,
  `(procedure? car)`→#t.

**apply & errors**
- AC-16 `(apply + (list 1 2 3))` → 6.
- AC-17 applying a non-procedure (e.g. `(5 6)`) raises a LISP error.

**End-to-end program**
- AC-18 define and run a recursive list sum:
  `(define (sum lst) (if (null? lst) 0 (+ (car lst) (sum (cdr lst)))))`,
  then `(sum '(1 2 3 4 5))` → 15.
- AC-19 higher-order: `(define (compose f g) (lambda (x) (f (g x))))`, then
  `((compose (lambda (x) (* x x)) (lambda (x) (+ x 1))) 4)` → 25.

**Regression**
- AC-20 the updated Phase 3 suite still passes (run it, or assert its key cases
  under the new convention).

**Definition of done:** the Phase 4 suite passes headless, the (updated) Phase 3
suite still passes, and both are committed and runnable.

## 9. Resolved decisions

Settled 2026-11-02 (owner sign-off); the spec is Accepted on these.

1. **Package name.** `CogLisp-Runtime` for `LispProcedure` / `LispPrimitives` /
   `LispArityError`.
2. **Variadic arithmetic & chained comparison** exactly as §3.
3. **`and`/`or` deferred** to Phase 7 macros rather than added as special forms now.
4. **I/O to `Stdio stdout`** for Phase 4; Phase 5 may redirect it.
5. **`map` is single-list** in Phase 4; multi-list deferred.

## 10. Downstream notes

- **Phase 5** builds the REPL and a **host-OS runner** that compiles and runs a
  `.lisp` program end to end — the running example you want — now that Phase 4
  makes such programs worth running.
- **Phase 6** adds a fast path for statically-known fixed-arity calls (bypassing
  the wrapper) and tail-call handling.
- **Phase 7** adds macros, which bring `and`/`or`, `cond`, `when`/`unless`, and a
  path to Common-Lisp-flavored surface syntax for working through *ANSI Common
  Lisp* in familiar forms.
- These primitives are the vocabulary most of Graham's list-processing examples
  assume; Phase 4 is the point where those examples become transliterable.
