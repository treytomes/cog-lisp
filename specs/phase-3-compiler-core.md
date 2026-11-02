# Spec — Phase 3: Compiler Core

| | |
|---|---|
| **Phase** | 3 |
| **Status** | Implemented (2026-11-02) — `tests/phase-3-compiler.st` passes 31/31 |
| **Depends on** | Phase 1 (reader), Phase 2 (core data model) |
| **Feeds** | Phase 4 (runtime & primitives), Phase 5 (REPL), Phase 8 (self-hosting) |
| **Codegen** | LISP → Smalltalk AST → Opal compiler → `CompiledMethod` |

> **Partially superseded by [Phase 4](phase-4-runtime-primitives.md) (calling
> convention only).** Since Phase 4, `lambda` compiles to a `LispProcedure`
> (wrapping the block with arity metadata) rather than a bare `BlockClosure`, and
> application compiles to `LispProcedure apply: f to: {args}` rather than
> arity-selected `value:` sends. Everything else here stands. The Phase 3 suite
> was updated accordingly (AC-11 now asserts `LispProcedure`) and still passes.
>
> **Also revised by [Phase 5](phase-5-repl-runner.md) (unspecified value).** The
> "unspecified" placeholder is now `LispUnspecified default`, not the empty list:
> it is what `define`, `set!`, and a one-armed `if` whose test is false evaluate
> to. AC-7 was updated to match. Phase 5 also makes every compiled `lambda` keep
> its source text.

## 1. Goal

Compile s-expressions into real `CompiledMethod`s that the Cog JIT runs native.
This is the keystone: the reader's data becomes the compiler's input, Phase 2's
`isTruthy:`/`LispEnvironment` become the runtime it targets, and the
compile-to-`CompiledMethod` pathway proven in Phase 0 becomes the backend.

After Phase 3 we can read, compile, and evaluate a core Scheme-like language:
atoms, variables, application, `quote`, `if`, `lambda`, `let`, `begin`,
`define`, `set!`.

## 2. Guiding principle — lean on Pharo

cog-lisp is built by **reusing Pharo's architecture, not reinventing it.** This
tenet has shaped every phase and is decisive here:

- The VM is Cog+Spur; compiled LISP is ordinary `CompiledMethod`s it JITs.
- LISP **closures are Smalltalk `BlockClosure`s**; lexical capture is Smalltalk's.
- LISP **locals are Smalltalk block temps/args**; scoping is Smalltalk's.
- The **compiler front-end is Opal**: we translate to a Smalltalk AST and let the
  standard compiler do semantic analysis, closure conversion, and bytecode
  generation.
- Persistence is the image; reflection is Smalltalk's.

We write the *translation*; Pharo provides the *machinery*. When a choice arises,
prefer the one that rides existing Pharo infrastructure.

## 3. Scope

**In scope**
- Self-evaluating literals: numbers, strings, characters, booleans, `()`.
- Variable reference (local → Smalltalk temp; global → `LispEnvironment`).
- Procedure application `(f a …)` with fixed arity.
- Special forms: `quote`, `if`, `begin`, `lambda` (fixed arity), `let`,
  `define` (value form **and** `(define (f …) …)` sugar), `set!`.
- An `eval` entry point (compile a form and run it) and a multi-form driver.
- A machine-checkable acceptance suite.

**Deferred (explicitly out of scope for Phase 3)**
- **Variadic / rest parameters** (`(lambda (a . rest) …)`, `(lambda args …)`).
  Fixed arity only; rest args arrive in Phase 4.
- **Internal defines / `letrec` / named `let`** (only top-level `define`; a
  global procedure may still recurse by its global name).
- **Tail-call optimization** — deep recursion may overflow the Smalltalk stack
  until Phase 6.
- **Macros** and any Common-Lisp surface (`defun`, `setq`, `cond`, `and`/`or`,
  `when`, …) — Phase 7 (macros can then provide CL-flavored forms; see §12).
- **The primitive library** (`+`, `car`, `map`, …) — Phase 4. Phase 3 tests bind
  a handful of primitives by hand to exercise application.

## 4. Decisions

- **Codegen = LISP → Smalltalk AST → Opal** (settled). The compiler builds
  Smalltalk AST nodes and hands them to the Opal compiler, which produces the
  `CompiledMethod`. Consequence: closures, lexical scoping, temp allocation, and
  bytecode selection are Pharo's job, not ours.
- **Procedures are `BlockClosure`s.** `lambda` compiles to a Smalltalk block;
  application sends `value`/`value:`/… (or `valueWithArguments:`).
- **Special forms are reserved syntactic keywords** in Phase 3 (not shadowable by
  binding). Simpler than full hygienic keyword resolution; revisited with macros.
- **Only top-level `define`.** Recursion works through the global name.
- **Unspecified value.** Forms with no meaningful value (`(if #f #f)`, `set!`,
  `define`) yield a placeholder — Phase 3 uses `LispEmptyList default`; a
  dedicated unspecified value may be introduced later.
- **`quote` compiles to reconstruction code** (build the datum at run time:
  numbers/strings as literals, symbols as `LispSymbol named:`, lists as nested
  `LispCons car:cdr:`, `()` as `LispEmptyList default`) rather than smuggling a
  non-literal object into the method's literal frame.

## 5. Compilation model

- A **top-level form compiles to a zero-argument `CompiledMethod`** (a thunk)
  whose execution returns the form's value. `eval:` compiles the form and runs
  the thunk via `valueWithReceiver: nil arguments: #()` (the Phase 0 pathway).
- A **`lambda` compiles to a Smalltalk `BlockClosure`**. Applying a procedure is a
  Smalltalk eval-send: `value` / `value:` / `value:value:` /
  `value:value:value:` / `value:value:value:value:` for 0–4 arguments, else
  `valueWithArguments: anArray`. (Wrong arg count surfaces as a Smalltalk
  `WrongArgumentCount`; nicer LISP arity errors come later.)
- Everything compiled is a real `CompiledMethod`/`CompiledBlock`, so it is JITted
  — the acceptance suite asserts this (a `lambda` evaluates to a `BlockClosure`,
  `compile:` yields a `CompiledMethod`).

## 6. The lexical contour (compile-time scope)

A compile-time stack of scopes maps each in-scope LISP symbol to a **synthetic
Smalltalk variable name**. There is **no runtime environment object for locals**
(per the Phase 2 decision); the only runtime environment is the global one.

- Entering a `lambda`/`let` pushes a scope binding its parameters to fresh
  synthetic names (`l1`, `l2`, …). LISP symbols such as `+`, `set!`, or `->x` are
  **not valid Smalltalk identifiers**, so locals are always mangled to synthetic
  names; the contour holds the mapping.
- A **variable reference** resolves innermost-out: found in the contour → a
  Smalltalk temp/arg reference to that synthetic name; not found → a **global**
  read, compiled as `LispEnvironment default lookup: <symbolLiteral>`.
- Because nested `lambda`s compile to nested Smalltalk blocks using these
  synthetic names, **Opal performs closure capture for us** — a captured local is
  just a Smalltalk block closing over an outer temp.
- Smalltalk block **arguments are read-only**, so a local that `set!` may mutate
  cannot be the argument itself. Each lambda parameter is therefore bound to a
  mutable **temporary** initialized from the argument (`[:arg | | v | v := arg.
  … ]`); references and `set!` use the temporary.

## 7. Form-by-form translation

Each LISP form maps to a Smalltalk AST shape (shown here as the equivalent
Smalltalk source for readability; the compiler builds the nodes directly):

| LISP | Smalltalk AST (as source) |
|---|---|
| `42`, `"hi"`, `#t`, `#\a` | the literal `42`, `'hi'`, `true`, `$a` |
| `()` | `LispEmptyList default` |
| local var `x` | the synthetic temp, e.g. `l1` |
| global var `x` | `LispEnvironment default lookup: #x` *(a `LispSymbol` literal)* |
| `(f a b)` | `fVal value: aVal value: bVal` (arity-selected send) |
| `(quote d)` | reconstruction of `d` (see §4) |
| `(if t a b)` | `(LispCore isTruthy: tVal) ifTrue: [aVal] ifFalse: [bVal]` |
| `(if t a)` | `(LispCore isTruthy: tVal) ifTrue: [aVal] ifFalse: [LispEmptyList default]` |
| `(begin e1 … en)` | statement sequence; value is `en` |
| `(lambda (p…) body…)` | `[:l1 :l2 … \| bodyStmts ]` (params → synthetic block args) |
| `(let ((v e)…) body…)` | desugar to `((lambda (v…) body…) e…)` |
| `(define x e)` | `LispEnvironment default define: #x value: eVal` |
| `(define (f p…) body…)` | desugar to `(define f (lambda (p…) body…))` |
| `(set! x e)` | local → `l_k := eVal`; global → `LispEnvironment default set: #x value: eVal` |

Notes:
- `begin` / `lambda` / `let` bodies are an **implicit `begin`**: evaluate each
  form, the last is the value.
- The operator position of an application is checked against the reserved
  special-form names first; otherwise it is an ordinary application (the operator
  is itself compiled as an expression, so computed operators like
  `((if … car cdr) x)` work).

## 8. API

Package `CogLisp-Compiler`.

```smalltalk
LispCompiler new
    compile: aSexpr            "=> a zero-arg CompiledMethod (the thunk)"
    eval: aSexpr               "=> compile and run; returns the value"
    evalString: aString        "=> read one datum and eval it"
    evalAll: aString           "=> read all top-level data, eval in order, return the last"
```

Phase 3 compiles against `LispEnvironment default`. A per-call environment
(`eval:in:`) is deferred to Phase 5 (REPL), where supplying an explicit
environment becomes useful.

## 9. Errors

- Reference to an unbound global → `LispUnboundError` (from Phase 2, raised by
  `LispEnvironment lookup:`).
- `set!` on an unbound global → `LispUnboundError`.
- Malformed special form (e.g. `(if)`, `(lambda)`, `(let x)`) → a
  `LispCompileError` (new `Error` subclass) with a message naming the form.
- Applying a non-procedure, or wrong argument count → surfaces as the underlying
  Smalltalk error in Phase 3; promoted to LISP-level errors later.

## 10. Acceptance criteria

Realized as `tests/phase-3-compiler.st` (files in reader, core, compiler; binds a
few arithmetic primitives for application tests), PASS/FAIL per check, final
`RESULT: n/n`. `eval` means `LispCompiler new evalString:`/`eval:` unless noted.

**Literals & quote**
- AC-1 self-evaluating: `42`→42, `"hi"`→"hi", `#t`→true, `#\a`→$a, `()`→empty.
- AC-2 `(quote x)` → the symbol `x`; `'x` likewise.
- AC-3 `'(1 2 3)` → a list `equal?` to `(1 2 3)`; `'(1 . 2)` → the dotted pair.

**Variables**
- AC-4 global read: after `(define x 5)`, `x` → 5.
- AC-5 unbound read signals `LispUnboundError`.

**if / begin**
- AC-6 `(if #t 1 2)`→1, `(if #f 1 2)`→2, `(if 0 1 2)`→1 (0 is truthy).
- AC-7 `(if #f 1)` → the unspecified value (empty list).
- AC-8 `(begin 1 2 3)`→3; `begin` evaluates in order (observed via `set!`).

**lambda / application / closures**
- AC-9 `((lambda (x) x) 5)`→5.
- AC-10 `((lambda (x y) (+ x y)) 2 3)`→5 (with `+` bound).
- AC-11 a `lambda` evaluates to a Smalltalk `BlockClosure`; `compile:` of a form
  yields a `CompiledMethod` (the compiled/native nature is real).
- AC-12 **closure capture**: `(((lambda (x) (lambda (y) (+ x y))) 2) 3)`→5.

**let**
- AC-13 `(let ((x 1) (y 2)) (+ x y))`→3.
- AC-14 `let` scoping: inner `let` shadows an outer binding of the same name.

**define / set!**
- AC-15 `(define x 10)` then `x`→10 (value form).
- AC-16 `(define (sq n) (* n n))` then `(sq 4)`→16 (function sugar).
- AC-17 global `set!`: after `(define x 1)`, `(set! x 2)` then `x`→2; `set!` of an
  unbound global signals.
- AC-18 local `set!`: a `lambda`/`let` body that `set!`s its own parameter sees
  the updated value.

**recursion**
- AC-19 `(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))` then `(fact 5)`→120.

**driver**
- AC-20 `evalAll:` of several top-level forms evaluates them in order and returns
  the last (e.g. a `define` followed by a use).

**Definition of done:** all checks pass headless, suite committed and runnable.

## 11. Resolved decisions

Settled 2026-11-02 (owner sign-off); the spec is Accepted on these.

1. **Compiler class / package.** `LispCompiler` in `CogLisp-Compiler`.
2. **Calling convention.** `value:`…`value:value:value:value:` for 0–4 args, then
   `valueWithArguments:`.
3. **Unspecified value.** `LispEmptyList default` is the Phase-3 placeholder; a
   dedicated unspecified value may be introduced later.

**Implementation note (not a decision):** the exact Opal selectors for building a
method AST and compiling it to a `CompiledMethod` will be **probed against the
live image first** (as the Opal API was in Phase 0), then recorded in CLAUDE.md.
Implementation starts with that mechanism probe.

## 12. Downstream notes

- **Phase 4** binds the real primitive library in the global environment and adds
  variadic/rest parameters; `equal?`/`eq?`/predicates (Phase 2) become callable.
- **Phase 6** adds tail-call handling so idiomatic recursion runs in bounded
  stack, and may drop to raw SistaV1 for hot paths where the Opal route is a
  bottleneck.
- **Phase 7** adds macros — the natural home for Common-Lisp-flavored surface
  syntax (`defun`, `cond`, `when`, …) layered over this Scheme-like core, so
  concepts from *ANSI Common Lisp* can be exercised with familiar forms.
- **Phase 8** (self-hosting): because the compiler is a clean tree transform from
  LISP data to a target AST, it is a strong candidate to be rewritten in cog-lisp
  itself.
