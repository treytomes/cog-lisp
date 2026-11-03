# Spec — Phase 7: Macros & Derived Forms

| | |
|---|---|
| **Phase** | 7 |
| **Status** | Accepted (2026-11-03) |
| **Depends on** | Phases 1–6 |
| **Feeds** | Phase 8 (self-hosting), the later language phases (§10) |
| **Macro system** | Non-hygienic, procedural (`defmacro` style) with `gensym` |
| **CL surface** | Optional library `lib/cl.lisp`; the core stays Scheme-like |

## 1. Goal

Let cog-lisp programs **extend the language**: a macro is an ordinary procedure
that receives unevaluated code and returns new code, which the compiler then
compiles in its place. On top of that, provide the standard **derived forms**
(`cond`, `and`, `or`, `when`, `let*`, named `let`, `do`, …) written in cog-lisp
itself, and an optional **Common Lisp compatibility library** for working
through *ANSI Common Lisp*.

## 2. Scope

**In scope**
- Reader: the quasiquote abbreviations `` ` `` `,` `,@` (deferred since Phase 1).
- Compiler: `quasiquote` (with nesting), `define-macro`, macro expansion at
  compile time, and **internal `define`** in bodies (deferred since Phase 3).
- Primitives: `gensym`, `macroexpand-1`, `macroexpand`, `eval`, and the list
  searches `memq` `memv` `member` `assq` `assv` `assoc`.
- `lib/core.lisp`: the derived forms, as macros written in cog-lisp, loaded into
  the built image.
- `lib/cl.lisp`: the optional CL library.
- Acceptance suite and example programs.

**Deferred** (each its own later phase; see §10)
- Hygienic macros (`syntax-rules`).
- Numeric tower (rationals, exactness), conditions and restarts, two-way
  Smalltalk interop.
- Local macros (`let-syntax`, `macrolet`); macros are top-level only.
- Vectors, so quasiquote covers lists only.

## 3. Decisions

- **Macros are procedures (settled).** `(define-macro (name . params) body…)`
  defines an *expander*: a `LispProcedure` that takes the macro call's operands,
  unevaluated, and returns the replacement form. Expanders are compiled like any
  procedure, so they are fast, inspectable, and keep their source.
- **Non-hygienic, with `gensym` (settled).** Macro authors avoid capturing names
  by generating fresh symbols with `gensym`, as in Common Lisp.
- **Derived forms are written in LISP** (`lib/core.lisp`), not as compiler special
  forms. They are short, readable, keep their source, and move cog-lisp toward
  Phase 8 (self-hosting). Only `quasiquote`, `define-macro`, and the Phase 3
  forms are special forms.
- **The CL library is opt-in (settled)**: `(load "lib/cl.lisp")`. The core
  namespace stays Scheme.
- **Lean on Pharo:** expansion happens in the compiler before translation to the
  Smalltalk AST, so everything downstream (tail calls, inlining, cells) applies
  to expanded code unchanged.

## 4. Quasiquote

**Reader.** `` `x `` reads as `(quasiquote x)`, `,x` as `(unquote x)`, `,@x` as
`(unquote-splicing x)`. The printer writes them in full list form.

**Compiler.** `(quasiquote t)` compiles to code that builds the structure `t`
describes: constant parts are literals (shared, as `quote` is), `(unquote e)`
inserts the value of `e`, and `(unquote-splicing e)` splices the list value of
`e` into the enclosing list. Construction uses internal runtime operations, never
the global `cons`/`append`, so redefining those names does not break
quasiquote.

- **Nesting** follows R7RS: each `quasiquote` raises the level and each
  `unquote`/`unquote-splicing` lowers it; only level-0 unquotes are evaluated.
- Dotted tails work: `` `(1 . ,x) ``.
- `unquote-splicing` of a non-list, or outside a list, is a compile error.

## 5. Macros

### 5.1 Definition and expansion

```scheme
(define-macro (swap! a b)
  (let ((tmp (gensym)))
    `(let ((,tmp ,a)) (set! ,a ,b) (set! ,b ,tmp))))
```

- `define-macro` binds the name's **global cell** to a `LispMacro` (wrapping the
  expander). It is allowed only at top level; elsewhere it is a compile error.
- When the compiler meets a form `(op …)` where `op` is a symbol **not bound
  locally** and whose global cell holds a `LispMacro` **at compile time**, it
  calls the expander with the operands (as data) and compiles the result in the
  original form's place, including its tail position. Expansion repeats until
  the form is no longer a macro call.
- Because each top-level form is compiled just before it runs, a macro defined
  earlier in a file is available to every later form.
- **Redefining a macro affects only code compiled afterwards**: code already
  compiled contains the old expansion. (Unlike procedures. Inherent to macros.)
- Referencing a macro name as a variable, e.g. `(map and xs)`, is a compile
  error: "macro used as a value".
- A local binding shadows a macro: in `(let ((when 5)) when)`, `when` is the
  variable.
- An error raised by an expander is reported as a compile error naming the macro.

### 5.2 Introspection

- `(macroexpand-1 'form)` expands `form` once if it is a macro call, else returns
  it unchanged. `(macroexpand 'form)` expands repeatedly at the top only.
- `(gensym)` returns a fresh **uninterned** symbol, printed `g<n>` (unique in the
  session). Reading `g<n>` back yields a different, interned symbol.
- `(eval form)` compiles and runs `form` in the global environment.

### 5.3 Source retention

Per the source-retention requirement, a procedure created by macro expansion
keeps the **text the user wrote**: when a lambda in an expansion has no source
range of its own, it takes the source of the innermost user-written form it came
from. `(defun sq (x) (* x x))` therefore yields a procedure whose source is the
`defun` text. Expanders keep the `define-macro` text.

## 6. Internal `define`

`define` forms at the start of a `lambda`, `let`, or `define` body define local
variables, with `letrec*` semantics: all names are in scope throughout the body
(so local procedures can be mutually recursive), and their values are assigned
in order. Compiled as locals initialized to the unspecified value, then assigned.
A body-level `define` after an expression is a compile error, as in R7RS.

## 7. Derived forms (`lib/core.lisp`)

Written as `define-macro`s; loaded into `cog-lisp.image` by the build and by the
test suites.

| Form | Meaning |
|---|---|
| `(cond (test e…)… (else e…))` | first clause whose test is true; `(test => f)` calls `f` on the test value |
| `(case key ((d…) e…)… (else e…))` | compares with `memv` |
| `(and e…)`, `(or e…)` | short-circuit; `(and)` → `#t`, `(or)` → `#f`; last expression in tail position |
| `(when test e…)`, `(unless test e…)` | one-armed conditionals with bodies |
| `(let* ((v e)…) body…)` | sequential `let` |
| `(letrec ((v e)…) body…)`, `letrec*` | recursive bindings |
| `(let name ((v e)…) body…)` | named `let`, for loops |
| `(do ((v init step)…) (test res…) body…)` | iteration |

All run in constant stack where they loop (named `let`, `do`), relying on Phase
6's proper tail calls.

## 8. The CL library (`lib/cl.lisp`)

Loaded with `(load "lib/cl.lisp")`. Provides, as macros and procedures:

- **Definitions:** `defun`, `defmacro`, `defvar`, `defparameter`.
- **Assignment and sequencing:** `setq` (one or more pairs), `progn`, `prog1`.
- **Binding and local functions:** `let*` (core), `labels`, `flet`.
- **Iteration:** `dolist`, `dotimes`.
- **Lists and predicates:** `first` … `third`, `rest`, `nth`, `nthcdr`, `last`,
  `consp`, `listp`, `atom`, `null`, `eql`, `mapcar` (one list), `funcall`,
  `push`, `pop`.
- **Constants:** `t` is bound to `#t`, `nil` to `()`.

**Known gaps** (documented in the file's header and the README): `nil` and `()`
are **true** in cog-lisp, so CL code that tests a list for emptiness with plain
`if` must use `null` or `consp`; `#'f` is not read (use `f`); there is one
namespace, so a variable and a function cannot share a name; `loop`, `format`,
keywords, multiple values, and `&optional`/`&key` are not provided.

## 9. Acceptance criteria

**`tests/phase-7-macros.st`** (headless; loads `lib/core.lisp`):

*Reader and quasiquote*
- AC-1 `` `x ``, `,x`, `,@x` read as the three list forms; existing reader checks
  still pass.
- AC-2 `` `(1 ,(+ 1 1) ,@(list 3 4) 5) `` → `(1 2 3 4 5)`; dotted
  `` `(1 . ,(+ 1 1)) `` → `(1 . 2)`.
- AC-3 Nested quasiquote evaluates only level-0 unquotes:
  `` `(a `(b ,(c ,(+ 1 2)))) `` → `(a (quasiquote (b (unquote (c 3)))))`.
- AC-4 Redefining `cons` or `append` does not affect quasiquote.

*Macros*
- AC-5 `define-macro` then use: `swap!` (§5.1) swaps two variables.
- AC-6 Expansion is recursive (a macro expanding into another macro call).
- AC-7 A macro call in tail position keeps the tail call (constant stack).
- AC-8 `macroexpand-1` / `macroexpand` return the expected forms.
- AC-9 `gensym` returns distinct uninterned symbols; a `gensym`-using macro does
  not capture a user variable of the same printed name.
- AC-10 A local binding shadows a macro name.
- AC-11 Using a macro as a value, and `define-macro` inside a body, are compile
  errors; an expander error is reported with the macro's name.
- AC-12 `eval` evaluates a constructed form.

*Internal define*
- AC-13 Internal defines in a `lambda` body, including mutually recursive local
  procedures; a `define` after an expression is an error.

*Derived forms*
- AC-14 Each form in §7 gives correct results, including `cond =>`, `case`
  with `else`, and the `(and)` / `(or)` identities.
- AC-15 `and`/`or` short-circuit (side effects observed).
- AC-16 Named `let` and `do` loop 100,000 times in constant stack.

*Source retention*
- AC-17 A procedure defined through a macro (`defun`, or a user macro) returns
  the user's text from `procedure-source`; an expander keeps its
  `define-macro` text.

*CL library*
- AC-18 With `lib/cl.lisp` loaded: `defun`, `defmacro`, `setq`, `progn`,
  `dolist`, `dotimes`, `labels`, `push`/`pop`, `mapcar`, `funcall`, `nth`
  work; `(cond ((null x) …) (t …))` works with `t` bound to `#t`.

*Regression and image*
- AC-19 All earlier suites pass, the benchmarks still pass, and the examples
  still match.
- AC-20 The built image contains the derived forms (a runner fixture uses `cond`
  and `let*` without loading anything).

**Examples:** `examples/macros.lisp` (a `while` macro with `gensym`,
`macroexpand`) and `examples/cl-style.lisp` (a program in the style of the CL
book's early chapters, written for this project), each with `.expected` output.

## 10. Resolved decisions

Settled 2026-11-03 (owner sign-off); the spec is Accepted on these.

1. **Core macro-definer name:** `define-macro` (as in Guile and Gambit);
   `defmacro` comes from `lib/cl.lisp`.
2. **Derived forms are written in LISP** (`lib/core.lisp`, loaded at build), not
   as compiler special forms.
3. **Internal `define` is included** in Phase 7, with `letrec*` semantics.
4. **Nested quasiquote is supported** in this phase.
5. **README plan re-scoped:** Phase 7 is "Macros & derived forms". The rest of
   the old Phase 7 is tracked as planned later phases, numbered when each is
   specified: **Smalltalk interop** (owner priority), numeric tower, conditions
   and restarts, hygienic macros. Self-hosting and the pure image keep 8 and 9.
