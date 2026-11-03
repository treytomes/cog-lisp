# Spec — Phase 7.7: Conditions & Restarts

| | |
|---|---|
| **Phase** | 7.7 (the second step before Phase 8; README "Before Phase 8") |
| **Status** | Accepted (2026-11-03) |
| **Depends on** | Phases 1–7.6 |
| **Feeds** | 7.8 native data (its primitives signal conditions), Phase 8 (the self-hosted reader and compiler raise and catch errors) |
| **Model** | R7RS exceptions (`raise`, `guard`, `with-exception-handler`, `error`) plus Common Lisp–style restarts, both built on Pharo's exceptions |

## 1. Goal

Give LISP programs a real error system. A program can signal an error, raise
any value, catch and inspect what was raised, run code that a handler can
resume, and clean up however a block is left. On top of that, **restarts**: the
code that detects a problem can offer ways to recover (*use this value
instead*, *define the variable*), and a handler — or a person at the REPL —
picks one without unwinding the computation first.

Every Smalltalk exception is already a condition, so errors from primitives and
from `send` are caught by the same forms (review R-2's host-error mapping).

## 2. Scope

**In scope**
- `error`, `raise`, `raise-continuable`, `with-exception-handler`, `guard`,
  `dynamic-wind`, and the R7RS error-object accessors.
- Condition predicates and a message for any condition, LISP or Smalltalk.
- Restarts: `restart-case`, `invoke-restart`, `find-restart`,
  `compute-restarts`, and the standard restarts `use-value`, `store-value` and
  `abort`.
- Restarts offered by cog-lisp itself where recovery is natural: an unbound
  variable offers `use-value` and `store-value`.
- A **break loop** in the interactive REPL: an unhandled error opens a nested
  prompt in the failing computation, where restarts can be invoked.
- CL names in `lib/cl.lisp`: `handler-case`, `handler-bind`, `ignore-errors`,
  `unwind-protect`, `cerror`-free `error`.
- Examples for every feature (§9), and the review findings this phase owns
  (C-18 `qqAppend` signalling a plain `Error`).

**Deferred**
- Defining new condition *classes* from LISP (CL `define-condition`). Any value
  can be raised, so a tagged list or record serves for now; classes come with
  defining Smalltalk classes from LISP (planned with Phase 9).
- `call/cc` and full re-entrant continuations; `dynamic-wind` here guards exits
  only (§5.3).
- `warn`, `signal` of non-error conditions, and a condition hierarchy beyond what
  §4 lists.
- Choosing restarts in the break loop with a menu; it takes LISP forms (§7).

## 3. Decisions

- **Conditions are Pharo exceptions** (lean on Pharo). `error` signals a
  `LispError`; `raise` of a value that is not an exception signals a
  `LispRaise` carrying it; every Smalltalk `Error` is a condition as it stands.
  Handlers are `on:do:` underneath, so LISP and Smalltalk handlers see each
  other's errors, and handlers run on top of the signalling stack — which is
  what makes restarts possible without unwinding.
- **The core names are R7RS**, matching the rest of the core: `raise`, `guard`,
  `with-exception-handler`, `error-object-message`. Restarts have no R7RS
  equivalent, so they take the Common Lisp names (`restart-case`,
  `invoke-restart`). `lib/cl.lisp` adds `handler-case` and friends.
- **Restarts are dynamic, kept in a Pharo `DynamicVariable`** per process: a
  stack of the restarts currently established, innermost first.
- **Handlers catch errors and raised values, not every exception.** Pharo
  signals `Notification`s and `Warning`s internally (deprecations, compiler
  notices); `with-exception-handler` and `guard` see `Error` and `LispRaise`
  only, and restart transfers are invisible to them.

## 4. Conditions

### 4.1 Signalling

- `(error message irritant …)` signals an error whose message is `message` (a
  string) followed by the irritants, written as `write` would:
  `(error "bad size:" 5 'x)` → `bad size: 5 x`.
- `(raise obj)` signals `obj`. If a handler returns from a `raise`, that is
  itself an error ("handler returned from raise"), as in R7RS.
- `(raise-continuable obj)` signals `obj`; the handler's value becomes the value
  of the `raise-continuable` expression.
- Raising a Smalltalk exception object signals it as it is.

### 4.2 Handling

- `(with-exception-handler handler thunk)` calls `thunk`; a condition raised
  inside calls `(handler c)` **before unwinding**, with this handler removed so a
  raise inside it goes to the next one out (R7RS). For `raise-continuable` the
  handler's value is returned to the raise point; otherwise the handler should
  escape (by invoking a restart, raising, or `abort`).
- `(guard (var clause …) body …)` evaluates `body`; if a condition is raised,
  it **unwinds** to the `guard`, binds `var` to the raised value, and evaluates
  the `cond`-style clauses. If no clause matches, the condition is raised again
  where it was first raised (`=> ` and `else` work as in `cond`). `guard` is a
  macro in `lib/core.lisp` over one primitive.
- What a handler receives: the raised value for `raise`/`raise-continuable`;
  the condition object (the exception) for `error` and for Smalltalk errors.

### 4.3 Inspecting

| Procedure | |
|---|---|
| `(condition? x)` | any condition: a `LispError`, a raised value's wrapper, or a Smalltalk exception |
| `(error-object? x)` | a condition from `error`, or any Smalltalk `Error` |
| `(error-object-message c)` | the message: what `error` was given, or the translated host message (`car: not a pair: 5`) |
| `(error-object-irritants c)` | the irritants given to `error`; `()` for host errors |
| `(condition-report c)` | the full text the REPL would print: message and irritants |
| `(read-error? c)`, `(file-error? c)` | R7RS: a `LispReadError`; a file that cannot be opened or found |

Smalltalk errors can also be tested by class through interop:
`[c isKindOf: (smalltalk ZeroDivide)]`.

### 4.4 Cleanup

`(dynamic-wind before thunk after)` calls `before`, then `thunk`, then `after`,
and calls `after` however `thunk` is left: normally, by an error unwinding to a
`guard`, or by a restart. There are no re-entrant continuations, so `before`
runs once. (`ensure:` underneath; `lib/cl.lisp` names it `unwind-protect`.)

## 5. Restarts

### 5.1 Establishing and invoking

```scheme
(restart-case (risky-operation)
  (use-value (v) v)                ; a restart named use-value, taking one argument
  (retry () (risky-operation)))    ; and one named retry
```

- `(restart-case form (name (params …) body …) …)` evaluates `form` with the
  restarts established. If one is invoked while `form` runs, control **unwinds
  to the `restart-case`** and its body runs with the arguments; its value is
  the value of the `restart-case`.
- `(invoke-restart name arg …)` invokes the innermost active restart called
  `name` (a symbol), or a restart object. With no such restart it is an error.
- `(find-restart name)` answers the innermost active restart called `name`, or
  `#f`. `(compute-restarts)` answers the active restarts, innermost first.
  `(restart-name r)` answers a restart's name.
- Restarts are visible in handlers, which run before unwinding: a
  `with-exception-handler` handler can see and invoke the restarts established
  between it and the error. That is the point — the low-level code offers, the
  high-level code chooses.

### 5.2 Standard restarts

- `(use-value v)`, `(store-value v)`, `(abort)`: invoke the restart of that name
  if one is active (`abort`: return to the REPL's prompt, or end a program with
  exit 1). Each is an error if there is no such restart, except `abort`, which
  is always available at top level.
- **An unbound variable** offers `use-value` (use this value this once) and
  `store-value` (define the variable, then use it). So
  `(with-exception-handler (lambda (c) (use-value 0)) (lambda () (+ undefined 1)))`
  is `1`.

### 5.3 Restarts and Smalltalk
`invoke-restart` is implemented as a Smalltalk exception that `restart-case`
catches (not an `Error`), so Smalltalk `on: Error do:` handlers between the two
do not intercept it, and `ensure:` blocks run as it unwinds.

## 6. Errors from cog-lisp itself

- Errors from primitives, the compiler, the reader and `send` are conditions
  already; they keep their messages (review R-1, R-2), now also available as
  `error-object-message`.
- `qqAppend:to:` signals a `LispError` instead of a plain `Error` (review C-18).
- An uncaught `raise` of a non-condition is reported as
  `error: uncaught raise: <value written>`.

## 7. The break loop

When the **interactive** REPL (stdin is a console) meets an unhandled error, it
does not unwind. It prints the error and the active restarts, then opens a
nested prompt, `1>`, *inside the failing computation*:

```
> (+ undefined-var 1)
error: unbound variable: undefined-var
restarts: use-value store-value abort
1> (use-value 41)
42
>
```

- Forms typed at `1>` are evaluated normally and can see globals; an error there
  opens `2>`, and so on.
- Invoking a restart continues the original computation; `(abort)` or end of
  input returns to the top-level prompt.
- With piped or file input the REPL keeps today's behavior (report and carry
  on), so scripted sessions and the runner suite are unaffected. The runner
  (`cog-lisp file.lisp`) never opens a break loop.

## 8. Acceptance criteria

**`tests/phase-7.7-conditions.st`** (headless; loads `lib/core.lisp`):

*Signalling and handling*
- AC-1 `error` builds its message from the message and written irritants;
  `error-object?`, `-message`, `-irritants` answer them.
- AC-2 `guard` catches `error`, a raised symbol, a raised list, and a Smalltalk
  error (`(car 5)`, `(/ 1 0)`, a `send` not understood); `=>` and `else` work;
  with no matching clause the condition reaches an outer `guard`.
- AC-3 `guard`'s body value is returned when nothing is raised; nested guards
  catch innermost first.
- AC-4 `with-exception-handler`: the handler runs before unwinding (it sees the
  restarts, and `dynamic-wind` `after` has not run yet); `raise-continuable`
  resumes with the handler's value; a handler returning from `raise` is an
  error; a raise inside the handler goes to the next handler out.
- AC-5 `condition?`, `read-error?`, `file-error?`, `condition-report`.
- AC-6 Handlers do not see `Notification`s or `Warning`s.

*Cleanup*
- AC-7 `dynamic-wind`'s `after` runs on normal exit, on an error unwinding to a
  `guard`, and on a restart; `before` runs once.

*Restarts*
- AC-8 `restart-case` with a restart invoked from a handler returns that
  restart's value; arguments are passed; the restart's body runs after unwinding.
- AC-9 `find-restart`, `compute-restarts` (innermost first), `restart-name`;
  `invoke-restart` of an inactive restart is an error.
- AC-10 Restart transfers pass through Smalltalk `on: Error do:` handlers and run
  `ensure:` blocks on the way.
- AC-11 An unbound variable offers `use-value` and `store-value`; `store-value`
  defines the global.
- AC-12 `abort` at top level of a program ends it with exit code 1 (runner fixture).

*The break loop* (driven through `LispRepl` with a console flag)
- AC-13 An unhandled error at an interactive prompt prints the error and the
  restarts and opens `1>`; `(use-value v)` there continues the computation and
  prints its value at the top-level prompt.
- AC-14 `(abort)` and end of input in the break loop return to `>`; an error at
  `1>` opens `2>`.
- AC-15 Piped input behaves as before (the earlier REPL fixtures still pass).

*CL library*
- AC-16 `handler-case`, `handler-bind`, `ignore-errors`, `unwind-protect` work as
  in Common Lisp for the cases above.

*Regression*
- AC-17 All earlier suites, the runner suite (with the new examples) and the
  benchmarks still pass; review C-18 is fixed.

## 9. Examples

As in Phase 7.6, every feature lands with an example in `examples/`, with a
`.expected` file the runner suite checks, written with the feature:

| Example | Proves |
|---|---|
| `examples/conditions-basics.lisp` | `error` and its accessors; `guard` catching errors, raised symbols and lists, and Smalltalk errors (`car`, division, `send`); re-raising to an outer `guard` |
| `examples/conditions-handlers.lisp` | `with-exception-handler` running before unwinding; `raise-continuable` supplying a value back; `dynamic-wind` cleanup order |
| `examples/restarts.lisp` | a parser that offers `use-value` and `skip` restarts for bad input, and callers that choose differently; `use-value`/`store-value` on an unbound variable; `compute-restarts` |
| `examples/conditions-cl.lisp` | the same ideas in Common Lisp style with `lib/cl.lisp`: `handler-case`, `handler-bind`, `ignore-errors`, `unwind-protect` |
| `tests/runner/abort.lisp` | `(abort)` in a program: exit code 1 (fixture) |

The break loop needs a console, so it is checked in the suite through `LispRepl`
and by hand, with the steps in the README.

## 10. Resolved decisions

Settled 2026-11-03 (owner sign-off); the spec is Accepted on these.

1. **Names:** R7RS for the core (`raise`, `guard`, `with-exception-handler`,
   `error-object-message`), Common Lisp names for restarts (`restart-case`,
   `invoke-restart`); `lib/cl.lisp` adds `handler-case` and friends.
2. **The break loop is in this phase.**
3. **Break loop on consoles only:** piped and file input, and the runner, keep
   report-and-continue.
4. **Built-in restarts:** an unbound variable offers `use-value` and
   `store-value`; others may come with later phases.
