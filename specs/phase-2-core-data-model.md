# Spec — Phase 2: Core Data Model

| | |
|---|---|
| **Phase** | 2 |
| **Status** | Implemented (2026-11-02) — `tests/phase-2-core.st` passes 49/49 |
| **Depends on** | Phase 1 (reader & printer) |
| **Feeds** | Phase 3 (compiler), Phase 4 (runtime & primitives) |
| **Variable model** | Lexical + global table (locals compile to Smalltalk temps; one runtime global environment) |

## 1. Goal

Give the values the reader produces their **behavior**: the equality predicates
(`eq?`, `eqv?`, `equal?`), the type predicates (`pair?`, `null?`, `symbol?`, …),
the single notion of truth the language runs on, and the **global environment**
that holds top-level definitions. These are the semantic primitives the Phase 3
compiler and Phase 4 runtime are written against.

Phase 1 made the data; Phase 2 makes it *mean* something — without yet
evaluating or compiling anything.

## 2. Scope

**In scope**
- The three equality predicates with R7RS semantics.
- Type/shape predicates over all Phase-1 value types, plus `list?` (proper list).
- **Truthiness**: the one rule the whole language branches on.
- The **global environment**: a mutable mapping from interned symbols to values,
  with define / lookup / set! / bound?, and the unbound-variable error.
- A machine-checkable acceptance suite (`tests/phase-2-core.st`).

**Deferred (explicitly out of scope for Phase 2)**
- **Compile-time lexical scope** (the mapping from a local name to a Smalltalk
  temp/argument slot). That is the compiler's *lexical contour* and belongs to
  Phase 3 — it is not a runtime structure. Per the variable-model decision, local
  variables never live in a runtime environment object; only globals do.
- Procedures / closures and `procedure?` (Phase 3/4 — procedures do not exist
  yet).
- Numeric tower beyond integer + float (rationals, complex, bignum behavior
  beyond what Smalltalk gives for free), vectors, hash tables, ports.

## 3. Decisions

- **Variable model: lexical + global table** (settled). Local/lambda variables
  will compile to Smalltalk method temporaries and arguments in Phase 3; closures
  become Smalltalk `BlockClosure`s. The only environment that exists at run time
  is the **global** one, holding top-level `define`s. This keeps variable access
  at native speed and is why there is no runtime frame-chain here.
- **Equality follows R7RS** (`eq?` ⊆ `eqv?` ⊆ `equal?`); see §6.
- **Scheme booleans, no `nil`/`t`.** Truth is `#t`/`#f` with only `#f` false, and
  the empty list `()` is a distinct, *truthy* object. (This supersedes the
  offhand "nil/t" wording in the top-level README plan, which predated the
  Scheme-dialect decision.)
- **Predicates and equality live in a stateless facade, `LispCore`** (class-side
  methods), mirroring `LispPrinter`. They dispatch by type test, so no methods are
  added to Smalltalk base classes and Phase-1 classes are left unmodified.

## 4. New types

Package `CogLisp-Core` (loads after `CogLisp-Reader`).

- **`LispCore`** — stateless facade; class-side predicates, equality, truthiness.
- **`LispEnvironment`** — the global binding table (instances allowed; a
  conventional shared one via `LispEnvironment default`).
- **`LispUnboundError`** — `Error` subclass signalled on lookup/`set!` of an
  unbound variable; carries the offending symbol.

## 5. Type predicates (`LispCore`, class-side)

Each returns a Smalltalk boolean (which *is* a cog-lisp boolean).

| Selector | True when the value is… |
|---|---|
| `isPair: v` | a `LispCons` |
| `isNull: v` | the empty-list singleton (`LispEmptyList default`) |
| `isList: v` | the empty list, or a pair whose spine ends in the empty list (proper list) |
| `isSymbol: v` | a `LispSymbol` |
| `isBoolean: v` | `true` or `false` |
| `isString: v` | a Smalltalk `String` |
| `isChar: v` | a Smalltalk `Character` |
| `isNumber: v` | a Smalltalk `Number` |
| `isInteger: v` | a Smalltalk `Integer` |
| `isReal: v` | a Smalltalk `Number` (every Phase-2 number is real) |

`isProcedure:` is intentionally absent until procedures exist (Phase 3/4).
`isList:` must terminate on improper/cyclic input — Phase 2 cannot produce
cycles, but the predicate walks the spine and returns `false` on a non-empty,
non-pair tail rather than looping forever.

## 6. Equality

Three predicates, nested in strength (`eq?` implies `eqv?` implies `equal?`).

**`eq: a with: b`** — pointer identity. Exactly Smalltalk `==`. True for the same
symbol (interning guarantees it), the same boolean, the empty list, and in
practice small integers and characters; unspecified-but-harmless for larger
numbers (use `eqv?` for numbers).

**`eqv: a with: b`** — like `eq?`, but compares **numbers and characters by
value**, respecting exactness:
- both numbers → true iff **same exactness and numerically equal**. Exactness:
  `Integer` is exact, `Float` is inexact. So `eqv?(1, 1)` ⇒ `#t`,
  `eqv?(1, 1.0)` ⇒ `#f`, `eqv?(1.0, 1.0)` ⇒ `#t`. (A `SmallInteger` and a
  `LargePositiveInteger` of equal value are both exact ⇒ `#t`.)
- both characters → true iff the same character.
- otherwise → `eq?`.

**`equal: a with: b`** — deep structural equality:
- both pairs → `equal?` on cars **and** `equal?` on cdrs (recursive).
- both strings → same length and contents.
- otherwise → `eqv?`.

Worked truth table the suite will check:

| a | b | eq? | eqv? | equal? |
|---|---|---|---|---|
| `foo` | `foo` (re-read) | #t | #t | #t |
| `1` | `1` | #t | #t | #t |
| `1` | `1.0` | #f | #f | #f |
| `1.0` | `1.0` | #f* | #t | #t |
| `"ab"` | `"ab"` (distinct) | #f | #f | #t |
| `(1 2)` | `(1 2)` (distinct) | #f | #f | #t |
| `()` | `()` | #t | #t | #t |

\* `eq?` on two equal floats is unspecified in Scheme; the suite only asserts the
`eqv?`/`equal?` columns for floats.

## 7. Truthiness

One rule, used by every conditional the language will ever run:

**`isTruthy: v`** ⇒ `false` only when `v == false`; `true` for everything else —
including `()`, `0`, `""`, and `#t`.

Phase 3's `if` compiles its test through this rule (not through Smalltalk's own
`ifTrue:`, which only accepts Booleans).

## 8. The global environment (`LispEnvironment`)

A mutable map from **interned symbols** (compared by `eq?`/identity — an
`IdentityDictionary` keyed by `LispSymbol`) to values.

| Selector | Behavior |
|---|---|
| `define: aSymbol value: aValue` | bind/rebind `aSymbol`; returns the value |
| `lookup: aSymbol` | the bound value, or signal `LispUnboundError` |
| `at: aSymbol ifAbsent: aBlock` | value, or `aBlock` value if unbound |
| `set: aSymbol value: aValue` | rebind an **already-bound** symbol; signal `LispUnboundError` if unbound (Scheme `set!` semantics) |
| `isBound: aSymbol` | `true`/`false` |

Class-side: `LispEnvironment new` for a fresh table; `LispEnvironment default`
for the conventional shared global that top-level `define` populates.

Because keys are interned symbols, a symbol read from source and the same
spelling read later are the identical object, so they hit the same binding — the
suite checks this explicitly.

## 9. Smalltalk API summary

```smalltalk
"predicates / equality / truth — all class-side on LispCore"
LispCore isPair: v     LispCore isNull: v     LispCore isList: v
LispCore isSymbol: v   LispCore isBoolean: v  LispCore isString: v
LispCore isChar: v     LispCore isNumber: v   LispCore isInteger: v
LispCore isReal: v
LispCore eq: a with: b    LispCore eqv: a with: b    LispCore equal: a with: b
LispCore isTruthy: v

"global environment"
LispEnvironment default
anEnv define: aSymbol value: aValue
anEnv lookup: aSymbol            "LispUnboundError if unbound"
anEnv at: aSymbol ifAbsent: aBlock
anEnv set: aSymbol value: aValue "LispUnboundError if unbound"
anEnv isBound: aSymbol
```

## 10. Acceptance criteria

Realized as `tests/phase-2-core.st` (files in `coglisp-reader.st` then
`coglisp-core.st`, then checks), PASS/FAIL per check, final `RESULT: n/n`.

**Predicates**
- AC-1 `isPair:` / `isNull:` / `isList:` correct for `()`, `(1)`, `(1 . 2)`, `5`.
- AC-2 `isSymbol:` `isBoolean:` `isString:` `isChar:` `isNumber:` `isInteger:`
  each true on a matching value and false on a non-matching one.
- AC-3 `isList:` is `#t` for `()` and `(1 2 3)`, `#f` for `(1 . 2)` and for a
  non-list atom, and **terminates** on an improper list.

**Equality** (the §6 truth table)
- AC-4 `eq?`: interned symbols equal; distinct strings not equal.
- AC-5 `eqv?`: `1`/`1` equal; `1`/`1.0` not; `1.0`/`1.0` equal; `#\a`/`#\a` equal.
- AC-6 `equal?`: distinct `"ab"` equal; distinct `(1 2)` equal; nested
  `(1 (2) 3)` equal; `(1 2)`/`(1 3)` not equal; `1`/`1.0` not equal.
- AC-7 `equal?` on a dotted pair compares the dotted tail (`(1 . 2)` vs
  `(1 . 2)` equal; vs `(1 . 3)` not).

**Truthiness**
- AC-8 `isTruthy:` is `#f` only for `false`; `#t` for `()`, `0`, `""`, `#t`, a
  symbol, a pair.

**Global environment**
- AC-9 `define:value:` then `lookup:` returns the value; redefine updates it.
- AC-10 `lookup:` of an unbound symbol signals `LispUnboundError`.
- AC-11 `set:value:` on a bound symbol updates it; on an unbound symbol signals
  `LispUnboundError`.
- AC-12 `isBound:` / `at:ifAbsent:` behave accordingly.
- AC-13 **Interning bridges source and table**: `define:` under the symbol read
  from `"x"`, then `lookup:` under the symbol re-read from `"x"`, finds the
  binding (same interned key).

**Definition of done:** all checks pass headless, suite committed and runnable.

## 11. Resolved decisions

Settled 2026-11-02 (owner sign-off); the spec is Accepted on these.

1. **Facade name.** `LispCore` holds the predicates, equality, and truthiness
   (class-side, stateless).
2. **Shared global accessor.** `LispEnvironment default` is the conventional
   top-level environment. The Phase 3 compiler may still take an explicit
   environment argument rather than reaching for the default.
3. **`eqv?` on big integers.** All `Integer`s are one exact domain: compared by
   value regardless of `SmallInteger`/`LargePositiveInteger` representation.

## 12. Downstream notes

- Phase 3 compiles `if` through `LispCore isTruthy:`, top-level `define`/variable
  reference through `LispEnvironment`, and **local** variables through its own
  compile-time lexical contour (temps/args) — which is defined in the Phase 3
  spec, not here.
- In Phase 4 these predicates and equality operators become callable LISP
  primitives (`pair?`, `eq?`, `equal?`, …) bound in the global environment.
- `equal?`'s structural walk is the production version of the throwaway
  comparison helper used in the Phase 1 test suite.
