# Spec — Phase 7.6: Smalltalk Interop

| | |
|---|---|
| **Phase** | 7.6 (the first of the steps before Phase 8; README "Before Phase 8") |
| **Status** | Implemented (2026-11-03) — `tests/phase-7.6-interop.st` 82/82; five examples; all suites 719/719 |
| **Depends on** | Phases 1–7.5 |
| **Feeds** | 7.7 conditions & restarts, 7.8 native data, Phase 8 (the LISP-level interface to Opal), Phase 9 (the subsystem audit) |
| **Direction** | Both ways: LISP calls Smalltalk, and Smalltalk calls LISP |

## 1. Goal

Open the rest of the image to cog-lisp. A LISP program can send any message to
any Smalltalk object and reach any class or global; a Smalltalk program can call
a LISP procedure as if it were a block, and evaluate LISP code. Nothing is
converted on the way: the two languages already share integers, floats,
strings, characters and booleans as the same objects, and every other object
passes through by identity.

This is the way into everything the image already has (collections, streams,
files, the compiler), the interface Phase 8's compiler will use to build Opal
nodes, and what Phase 9's audit will reach the other subsystems through.

## 2. Scope

**In scope**
- `send`: a special form that compiles to a real Smalltalk message send.
- Bracket syntax `[receiver message …]` that reads as a `send`.
- `smalltalk`: a special form naming a Smalltalk global (a class, `Smalltalk`, …).
- Dynamic sends and lookups, for selectors and names computed at run time.
- Smalltalk `nil` and Smalltalk symbols as LISP-visible values, with predicates
  and conversions; list ⇄ array conversion.
- LISP procedures that work wherever Smalltalk expects a block, driving their
  own tail calls (review R-18).
- `CogLisp`: a Smalltalk-side facade to evaluate LISP and call LISP procedures.
- Printing of host objects as `#<…>` (review R-18).
- Examples for every feature, checked by the runner suite (§9).

**Deferred**
- Defining Smalltalk classes or methods from LISP (a method whose body is LISP).
  A natural next step once conditions exist; to be planned with Phase 9.
- Smalltalk cascades (`;`) and statement sequences inside brackets.
- Mapping Smalltalk exceptions to LISP conditions: Phase 7.7. Until then a
  Smalltalk error raised in a send is reported like any other error (§7).
- Vectors as a LISP type and `#(…)` syntax: Phase 7.8 (which is expected to make
  LISP vectors *be* Smalltalk Arrays; §6.3).

## 3. Decisions

- **No marshalling.** Values cross by identity in both directions. Lean on
  Pharo: a LISP string *is* a Smalltalk `String`, a LISP number *is* a Smalltalk
  number, so most calls need nothing at all. Where the two languages differ
  (lists vs. collections, LISP symbols vs. Smalltalk symbols, `nil`), conversion
  is explicit, never implicit.
- **`send` is compiled, not interpreted.** A send with a literal selector
  compiles to the same message-send bytecode Smalltalk would emit, so the JIT's
  inline caches apply and an interop call costs what a Smalltalk call costs.
- **The bracket syntax is sugar for `send`**, read by the reader, so macros and
  the printer see ordinary lists, and `macroexpand`/`procedure-source` stay
  truthful.
- **Smalltalk names are explicit.** A LISP symbol never silently falls back to a
  Smalltalk global. `(smalltalk OrderedCollection)` names one; inside brackets a
  capitalized receiver may name one directly (§4.2, open question 2).
- **Interop is full power.** A LISP program can do anything a Smalltalk program
  can, including quitting the VM or deleting files. That is the point (the image
  is the world, and later an agent's body); it is stated, not restricted.

## 4. LISP calling Smalltalk

### 4.1 `send`

```scheme
(send receiver selector arg …)
```

- `selector` is **not evaluated**: a symbol spelled as in Smalltalk — `size`,
  `+`, `at:put:`. It decides the number of arguments: a unary selector takes 0,
  a binary one (made of `+-*/\<>=~@%|&?,`) takes 1, a keyword selector takes one
  per colon. Any other count is a compile error naming the selector.
- `receiver` and the arguments are evaluated left to right, then the message is
  sent. The value is whatever the method answers.
- Compiled as an `OCMessageNode`: a real send. In tail position it is still an
  ordinary send (Smalltalk has no tail calls); only LISP calls are tail calls.
- Selectors Opal compiles inline (`ifTrue:`, `whileTrue:`, `and:`, `==`, …) are
  sent as real messages when their arguments are not block literals, which they
  never are from LISP; a LISP procedure stands in for the block (§5.1).

### 4.2 Brackets

`[` and `]` become delimiters, read as a `send`, one message per bracket pair:

| Written | Reads as |
|---|---|
| `[coll size]` | `(send coll size)` |
| `[3 + 4]` | `(send 3 + 4)` |
| `[d at: k put: v]` | `(send d at:put: k v)` |
| `[[coll asSet] size]` | `(send (send coll asSet) size)` |
| `[OrderedCollection new]` | `(send (smalltalk OrderedCollection) new)` |

- Unary: a receiver and one symbol. Binary: receiver, a binary-selector symbol,
  one argument. Keyword: receiver, then `keyword: arg` pairs. Anything else is a
  read error with the bracket's position, which says *brackets are Smalltalk
  sends; use ( ) for grouping* (§10, 4).
- Every part is an ordinary datum, so arguments are any LISP expressions:
  `[d at: (car keys) put: (* 2 n)]`.
- **Receiver names (§10, 2):** inside brackets, a receiver symbol that
  starts with an upper-case letter names a Smalltalk global, as in
  `[OrderedCollection new]`. Everywhere else, `(smalltalk Name)` is required.
- `,` is the reader's unquote, so the Smalltalk `,` selector cannot be written
  in brackets; write `(send a (smalltalk-selector ",") b)` — see §4.4 — or use
  `copyWith:`/`,`-free selectors.
- The printer writes a `send` list as a list (`(send d at:put: k v)`), not
  brackets; brackets are input syntax only, like `'`.

### 4.3 Smalltalk globals

```scheme
(smalltalk OrderedCollection)   ; the class
(smalltalk Smalltalk)           ; the system dictionary
```

- A special form; the name is not evaluated. It compiles to a reference to the
  Smalltalk global (resolved by Opal, so it costs a literal load), and a name
  that is not a global is a compile error.
- `(smalltalk-global "Name")` (a procedure) looks one up at run time and answers
  `#f` when there is none, for names computed while running.

### 4.4 Dynamic sends

- `(smalltalk-send receiver selector arg …)` evaluates everything, including the
  selector (a LISP symbol, a Smalltalk symbol or a string), and performs it
  (`perform:withArguments:`). Arity is checked when it runs.
- `(smalltalk-selector "at:put:")` answers the Smalltalk symbol, so a computed
  selector can be kept and reused.

### 4.5 Values that differ between the languages

- **Smalltalk `nil`.** Methods often answer `nil` for "nothing". It reaches LISP
  as itself: `(smalltalk-nil)` answers it, `(smalltalk-nil? x)` tests for it, and
  it prints `#<nil>`. It is **true** in LISP conditionals, like everything except
  `#f`; test it with `smalltalk-nil?`. It is never converted to `()` or `#f`.
- **Symbols.** A LISP symbol and a Smalltalk symbol are different objects.
  `(smalltalk-symbol 'foo)` answers `#foo`, and `(lisp-symbol s)` turns a
  Smalltalk symbol `s` back into the LISP symbol. A Smalltalk symbol is not `string?` and not `symbol?` in LISP; it
  prints `#<#foo>`. (Selectors in `send` are converted at compile time.)
- **Lists and collections.** `(list->array l)` answers a Smalltalk `Array`;
  `(array->list a)` takes any Smalltalk sequenceable collection to a LISP list.
  From the Smalltalk side, `LispCons` and `LispEmptyList` understand `do:`,
  `collect:`, `size`, `asArray` and `asOrderedCollection`, so a LISP list can be
  handed to Smalltalk code that iterates.
- **Everything else** (collections, streams, classes, …) is used as it is, and
  `(smalltalk-object? x)` is true for any value that is not a LISP datum or
  procedure.

### 4.6 Printing

Values that are not LISP data print as `#<printString>`:
`#<an OrderedCollection(1 2 3)>`, `#<nil>`, `#<#foo>`, `#<OrderedCollection>`.
LISP data, procedures and the unspecified value print as before. `display`
writes the same. (Review R-18: `nil` printed as `nil`, which reads back as a
symbol.)

## 5. Smalltalk calling LISP

### 5.1 Procedures are blocks

A `LispProcedure` answers `value`, `value:`, `value:value:`,
`value:value:value:`, `value:value:value:value:`, `valueWithArguments:`,
`numArgs`, `cull:` and `cull:cull:`, so it can be passed wherever Smalltalk
expects a block that it only *sends messages to*: `collect:`, `select:`,
`inject:into:`, `detect:ifNone:`, `sort:`, `at:ifAbsent:`, `on:do:`,
`ensure:`. Each of these **drives the procedure's tail calls** before
answering, so a LISP procedure that ends in a tail call never hands a
`LispTailCall` to Smalltalk (review R-18). Arity is checked as in LISP.

Some Smalltalk code needs a real `BlockClosure` (`fork`, `newProcess`, methods
that test `isBlock`). `(procedure->block f)` answers one that calls `f`.

### 5.2 The `CogLisp` facade

A Smalltalk class for code that wants to use LISP:

```smalltalk
CogLisp eval: '(+ 1 2)'.              "3: evaluate LISP source"
CogLisp at: #fact.                    "the global's value, here a procedure"
(CogLisp at: #fact) value: 10.        "3628800"
CogLisp call: #fact with: 10.         "the same, by name"
CogLisp define: #greeting as: 'hi'.   "bind a LISP global"
CogLisp read: '(a b)'.                "the datum, unevaluated"
```

It works in the global environment `LispEnvironment default`, the one the REPL
and the runner use. Errors propagate as Smalltalk exceptions.

## 6. Notes on later phases

### 6.1 Phase 7.7 (conditions)
Host exceptions raised during a `send` become LISP conditions there; LISP
handlers then catch Smalltalk errors and vice versa (`on:do:` with a LISP
handler already works in 7.6, §5.1).

### 6.2 Phase 8 (self-hosting)
The LISP compiler builds Opal nodes with `send` and `smalltalk`:
`[(smalltalk OCLiteralValueNode) value: 42]`. Phase 8's "LISP-level interface to
the Opal IR" is a library over this phase, not a new mechanism.

### 6.3 Phase 7.8 (native data)
If LISP vectors are Smalltalk `Array`s (the leaning), `list->array` and
`array->list` become `list->vector` and `vector->list` with aliases kept.

## 7. Errors

- A message not understood is reported as
  `<receiver> does not understand <selector>`, e.g.
  `#<an OrderedCollection()> does not understand #frobnicate`. The translations
  of review R-2 for LISP primitives (`car: not a pair: 5`, `+: not a number`)
  stay, since those arise inside primitives, not in a `send`.
- Any other Smalltalk error keeps its message, located by the runner as usual
  (`path:line:col: error: …`).
- A `send` with the wrong number of arguments for its selector, a malformed
  bracket form, and an unknown `(smalltalk Name)` are compile or read errors.

## 8. Acceptance criteria

**`tests/phase-7.6-interop.st`** (headless; loads `lib/core.lisp`):

*Sends*
- AC-1 `send` with unary, binary and keyword selectors: `(send "abc" size)` → 3,
  `(send 3 + 4)` → 7, `(send d at:put: 1 2)` stores into a Dictionary.
- AC-2 A wrong argument count for the selector is a compile error naming it.
- AC-3 A literal-selector `send` compiles to a direct send: the disassembly of
  `(lambda (c) (send c size))` contains `send: #size` and no `perform:`.
- AC-4 Receiver and arguments are evaluated once, left to right.

*Brackets*
- AC-5 Each row of the §4.2 table reads as shown; nested brackets nest.
- AC-6 Malformed brackets (`[]`, `[a]`, `[a b c]`, `[a at: 1 put:]`, unclosed `[`)
  are read errors with positions; an unclosed `[` is incomplete (REPL keeps
  reading).
- AC-7 `]` and `[` end symbols (`[coll size]` does not read `size]`).

*Globals and dynamic sends*
- AC-8 `(smalltalk OrderedCollection)` is the class; an unknown name is a compile
  error; `(smalltalk-global "NoSuchThing")` → `#f`.
- AC-9 `smalltalk-send` with a LISP symbol, a Smalltalk symbol and a string
  selector; a wrong arity is an error when it runs.

*Values*
- AC-10 `smalltalk-nil`, `smalltalk-nil?`; `nil` is true in `if`.
- AC-11 `smalltalk-symbol`/`lisp-symbol` round-trip; a Smalltalk symbol is neither
  `string?` nor `symbol?`.
- AC-12 `list->array`/`array->list` round-trip, including the empty list; a LISP
  list answers `do:`, `collect:`, `size`, `asArray` from Smalltalk.
- AC-13 Host objects print as `#<…>` (nil, a collection, a class, a Smalltalk
  symbol); LISP values print as before (all earlier suites still pass).

*Smalltalk calling LISP*
- AC-14 A LISP lambda works as the block of `collect:`, `select:`,
  `inject:into:`, `detect:ifNone:`, `sort:`, `at:ifAbsent:`.
- AC-15 A LISP procedure whose body ends in a tail call answers its value to
  Smalltalk, never a `LispTailCall` (`collect:` with such a lambda).
- AC-16 `on:do:` with a LISP handler catches a Smalltalk error (`ZeroDivide`)
  and answers the handler's value; `ensure:` with a LISP procedure runs it.
- AC-17 `(procedure->block f)` is a `BlockClosure` with `f`'s arity.
- AC-18 `CogLisp eval:`, `at:`, `call:with:`, `define:as:`, `read:` behave as in §5.2.

*Errors*
- AC-19 An unknown message reports `… does not understand #…`; R-2 translations
  are unchanged.

*Cost*
- AC-20 Benchmark: a loop of 10⁶ `(send acc + 1)` runs within 1.5× of the same
  loop written with `(+ acc 1)` (both compiled; `bench/`).

*Regression*
- AC-21 All earlier suites, the runner suite and the benchmarks still pass.

## 9. Examples

Every feature lands **with an example that proves it**, written before or along
with the feature: each is a program in `examples/` with a `.expected` file, so
the runner suite runs it on every build (`tests\run-all.bat`). The examples are
written in order, each building on the last, and each is extended in the same
commit as the feature it shows.

| Example | Proves |
|---|---|
| `examples/interop-send.lisp` | `send` and brackets (unary, binary, keyword, nested), `smalltalk` globals, shared strings and numbers (`["hello" asUppercase]`, `[3 @ 4]`), dynamic `smalltalk-send` |
| `examples/interop-values.lisp` | `nil`, Smalltalk symbols, `list->array`/`array->list`, `#<…>` printing, the "nil is true" rule |
| `examples/interop-collections.lisp` | building and querying `OrderedCollection`, `Dictionary`, `Set` and `Interval` from LISP; sorting and filtering with LISP lambdas as blocks |
| `examples/interop-callbacks.lisp` | Smalltalk calling LISP: blocks that tail-call, `on:do:` with a LISP handler, `ensure:`, `procedure->block`, and `CogLisp eval:` called back from LISP |
| `examples/interop-streams.lisp` | a practical program: word frequencies of a string with `ReadStream`, a `Bag`, sorted by count, printed with `display` |

Outputs are chosen to be deterministic (no dates, hashes or identity order).

## 10. Resolved decisions

Settled 2026-11-03 (owner sign-off); the spec is Accepted on these.

1. **Phase number:** 7.6. Conditions & restarts are 7.7, native data 7.8, and the
   self-hosting groundwork 7.9.
2. **Capitalized receivers in brackets** name Smalltalk globals
   (`[OrderedCollection new]`); everywhere else `(smalltalk Name)` is required.
3. **Interop names** use the `smalltalk-` prefix.
4. **Both brackets and `send`.** Brackets have no meaning in R7RS (`[ ] { }` are
   reserved for extensions) or in standard Common Lisp, so they are free. Two
   consequences, recorded here:
   - R6RS/Racket code that uses brackets as parentheses (`(let ([x 1]) x)`) does
     not read; the read error says *brackets are Smalltalk sends; use ( ) for
     grouping* when a bracket form is not a valid send.
   - Vectors (Phase 7.8) use the R7RS `#(…)` syntax, never brackets.

## 11. As implemented

- **Tests:** `tests/phase-7.6-interop.st` 82/82 (AC-1 to AC-19); the five
  examples of §9 in the runner suite (now 52/52); AC-20 in
  `bench\run-benchmarks.bat`: a loop of 10⁶ `(send acc + 1)` runs at **0.9×** the
  same loop with `(+ acc 1)` (a literal send is a plain message send; `+` pays its
  redefinition guard). All suites: 719/719.
- **Inlined selectors are performed** (a detail the spec did not foresee). Opal
  compiles `ifTrue:`, `and:`, `whileTrue:`, `to:do:`, `ifNil:` and the like
  inline even when an argument is not a block literal, taking the argument as a
  plain value: `(send #t ifTrue: f)` answered `f` itself. `send` therefore
  compiles those selectors (the set Opal inlines) as `perform:withArguments:`, so
  the real method runs and sends `value` to the procedure. All other selectors are
  direct sends (AC-3).
- **"Not understood" replaces "wrong type of argument"** for any message without a
  more specific translation (§7): `#<an OrderedCollection()> does not
  understand #frobnicate`. One review check (R-2, a comparison of a string)
  now expects that wording.
- **Printing:** objects whose class is in a `CogLisp-*` package print as they
  say (`#<procedure sq>`, `#<unspecified>`); every other non-LISP value prints as
  `#<printString>`. `display` treats a Smalltalk symbol like `write` does, not
  as text.
- **`procedure->block`** accepts procedures of 0 to 4 fixed arguments; others are
  an error (a variadic procedure has no single block arity).
- **The VS Code extension** knows the new syntax: `[ ]` match, auto-close and
  nest for send-form-to-REPL; keyword selectors, capitalized names, `send` and
  `smalltalk` are highlighted (`vscode/test/syntax.test.lisp`).
