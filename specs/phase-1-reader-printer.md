# Spec — Phase 1: Reader & Printer

| | |
|---|---|
| **Phase** | 1 |
| **Status** | Implemented (2026-11-02) — `tests/phase-1-reader-printer.st` passes 77/77 |
| **Depends on** | Phase 0 (foundation) |
| **Feeds** | Phase 2 (core data model), Phase 3 (compiler) |
| **Dialect** | Scheme-like (case-sensitive, `#t`/`#f`, distinct empty list) |

## 1. Goal

Turn source **text** into LISP **data**, and LISP data back into text, such that
the two are inverse: anything the reader produces, the printer can render, and
the reader reads back to an equal value. This is the project's front door — every
later phase consumes the data this phase produces.

Phase 1 is pure syntax and representation. **No evaluation, no environment, no
semantics of special forms.** `quote`, `lambda`, `if` are read as ordinary
symbols; their meaning is Phase 3's problem.

## 2. Scope

**In scope**
- Whitespace and comments (line `;`, block `#| … |#`, nestable).
- Atoms: integers, reals (floats), strings, characters, booleans, symbols.
- Compound data: proper lists `( … )`, dotted pairs `( a . b )`, nesting.
- The empty list `()`.
- The quote abbreviation `'x` ⇒ `(quote x)`.
- A reader (text → datum) and a `write`-style printer (datum → text) with a
  round-trip guarantee.
- A documented, machine-checkable acceptance suite.

**Deferred (explicitly out of scope for Phase 1)**
- Quasiquote / unquote `` ` , ,@`` (arrives with macros, Phase 7).
- Vectors `#( … )`, bytevectors (need Phase 2 data types).
- Datum comments `#;`, datum labels `#n=` / `#n#`, piped symbols `|…|`.
- Numeric tower beyond integer + float: rationals, complex, radix/exactness
  prefixes `#x #b #o #e #i` (Phase 4/7).
- `display`-style (human, non-re-readable) printing — only `write` is required
  here; `display` may come later.
- `[]` as list delimiters (decided: never; see §11).

## 3. Dialect decisions (Scheme-like)

- **Symbols are case-sensitive.** `Foo`, `foo`, `FOO` are three distinct symbols.
- **Booleans** are `#t` and `#f` (long forms `#true` / `#false` accepted on read,
  written short). Truthiness (only `#f` is false) is a **runtime** concern
  (Phase 3/4); the reader just produces the two boolean values.
- **The empty list `()` is its own object**, distinct from `#f` and from any
  symbol. There is no `nil` symbol with special status.
- **Numbers that parse as numbers are numbers; every other token is a symbol.**
  This single rule yields Scheme's "peculiar identifiers" (`+`, `-`, `...`,
  `->foo`) for free: the reader reads a maximal constituent run, tries to parse
  it as a number, and falls back to a symbol.

## 4. Reader output contract

Phase 1 introduces the **minimum** set of value types needed to represent read
data. Phase 2 owns their full behavior (equality predicates, the environment,
richer protocol); Phase 1 only needs construction and structural identity.

| Source syntax | Reader produces |
|---|---|
| `#t` / `#f` | Smalltalk `true` / `false` |
| integer, e.g. `42`, `-3` | Smalltalk `Integer` |
| real, e.g. `3.14`, `-1e9` | Smalltalk `Float` |
| character, e.g. `#\a`, `#\newline` | Smalltalk `Character` |
| string, e.g. `"hi\n"` | Smalltalk `String` (a fresh mutable instance) |
| symbol, e.g. `foo`, `+`, `set!` | **`LispSymbol`**, interned, case-sensitive |
| `()` | the **empty-list** singleton |
| `(a b c)` | **`LispCons`** chain terminated by the empty-list singleton |
| `(a . b)` | `LispCons` with car `a`, cdr `b` |
| `'x` | the list `(quote x)` = `LispCons quote (LispCons x ())` |

Reusing Smalltalk's `Integer`/`Float`/`String`/`Character` keeps Phase 1 small
and lets the eventual compiler lean on the host's numeric tower. The only genuinely
new types are **`LispSymbol`** (interned so `eq?` is pointer identity later),
**`LispCons`**, and the **empty-list** singleton.

### 4.1 Value type definitions

These three types are defined concretely here. Phase 2 extends their protocol
(predicates, equality, richer list operations) but must not change the invariants
below.

**`LispCons`** — a mutable pair; the building block of every list.
- Instance variables: `car`, `cdr`.
- Construction: `LispCons car: aValue cdr: aValue` → a new pair.
- Access: `car`, `cdr` (read); `car:`, `cdr:` (write — the basis for Phase 4's
  `set-car!` / `set-cdr!`).
- A **proper list** is a chain of `LispCons` whose final `cdr` is the
  `LispEmptyList` singleton. An **improper list** ends in any other non-cons value
  (the dotted tail).
- Phase-1 conveniences the printer and tests depend on:
  - `LispCons fromArray: anArray` → a proper list of the array's elements (an
    empty array → the empty-list singleton).
  - `isProperList` → `true` iff the spine terminates in the empty-list singleton.
  - `elementsAndTail` (or `do:`) → walk the spine, yielding each `car` and the
    final tail, so the printer can choose `( … )` vs `( … . tail )` and the reader
    round-trips both.
- Equality is identity by default; structural comparison is the Phase-1 test
  helper's job (and `equal?` in Phase 2).

**`LispSymbol`** — an interned name.
- Instance variable: `name` (a Smalltalk `String`, case preserved).
- Interning: `LispSymbol named: aString` returns the **one** canonical instance
  for that exact spelling, from a class-side table. Two reads of the same spelling
  return the identical object (`==`) — which is what makes `eq?` pointer identity
  in Phase 2. Case-sensitive: the symbol `foo` is not the symbol `Foo`.
- `name` reads the spelling; equality and hash are identity.

**`LispEmptyList`** — the empty list `()`.
- A singleton, `LispEmptyList default`: the object the reader yields for `()`.
  Distinct from `#f`, from Smalltalk `nil`, and from every symbol and cons.
- Immutable; it has no `car` / `cdr`.

## 5. Lexical grammar (tokens)

Intertoken space is discarded and never produces data:

```
intertoken   = ( whitespace | line-comment | block-comment )*
whitespace   = SPACE | TAB | LF | CR | FF
line-comment = ";" , { any-char - LF } , [ LF ]
block-comment= "#|" , { block-comment | any-char } , "|#"   (* nests *)
```

A **delimiter** ends a token: whitespace, `(`, `)`, `"`, `;`, `'`, `#|`, or EOF.

```
constituent  = letter | digit
             | "!" | "$" | "%" | "&" | "*" | "+" | "-" | "." | "/"
             | ":" | "<" | "=" | ">" | "?" | "@" | "^" | "_" | "~"
token        = constituent , { constituent }     (* maximal run *)
```

A `token` is then classified: if it matches `number` (§6) it is that number;
otherwise it is a `symbol` with that exact (case-preserved) name. A lone `.`
token is **not** a symbol — it is the dotted-pair marker, legal only inside a
list (§6).

## 6. Reader grammar (data)

```
datum        = atom | list | abbreviation
atom         = boolean | number | character | string | symbol

boolean      = "#t" | "#f" | "#true" | "#false"

number       = integer | real
integer      = [ sign ] , digit , { digit }
real         = [ sign ] , digit , { digit } , "." , { digit } , [ exponent ]
             | [ sign ] , { digit } , "." , digit , { digit } , [ exponent ]
             | [ sign ] , digit , { digit } , exponent
exponent     = ( "e" | "E" ) , [ sign ] , digit , { digit }
sign         = "+" | "-"

character    = "#\" , ( char-name | any-single-char )
char-name    = "space" | "newline" | "tab" | "return" | "null"
             | "#\x" , hex , { hex }          (* e.g. #\x41 => 'A' *)

string       = '"' , { string-elem } , '"'
string-elem  = ( any-char - ( '"' | "\" ) ) | escape
escape       = "\" , ( '"' | "\" | "n" | "t" | "r" | "0" )

symbol       = token  (* that does not parse as a number, and is not "." *)

list         = "(" , { datum } , ")"
             | "(" , datum , { datum } , "." , datum , ")"
abbreviation = "'" , datum        (* => ( quote datum ) *)
```

Notes:
- `()` reads as the empty-list singleton (zero elements).
- `( a . b )` requires exactly one datum after the `.`; `( a . b c )` and
  `( . a )` are errors.
- Lists nest arbitrarily; the reader tracks depth and reports unbalanced parens.

## 7. Reader API (proposed)

Package `CogLisp-Reader`.

```smalltalk
LispReader class >> on: aStringOrStream          "=> a reader"
LispReader    >> next                             "=> next datum, or the eof object"
LispReader    >> atEnd                            "=> Boolean"
LispReader class >> read: aString                 "=> the single datum in aString
                                                     (error if 0 or >1 data)"
LispReader class >> readAll: aString              "=> an OrderedCollection of all
                                                     top-level data"
LispReader class >> eofObject                      "=> the unique end-of-input marker"
```

- `eofObject` is a dedicated singleton. It must be distinct from `#f`, the empty
  list, and every symbol, so callers can test for end unambiguously (`nil` and
  `#f` are both valid data, so neither can signal EOF).
- Reader errors signal **`LispReadError`** (subclass of `Error`) with position
  information (offset into the source).

## 8. Printer spec

Package `CogLisp-Reader` (printer lives beside the reader).

```smalltalk
LispPrinter class >> writeString: aValue           "=> String, re-readable"
```

`write` output per value type:

| Value | `write` output |
|---|---|
| `true` / `false` | `#t` / `#f` |
| `Integer` | decimal digits, leading `-` if negative |
| `Float` | shortest decimal that reads back to the identical value |
| `Character` | `#\name` for the named set, else `#\c` |
| `String` | `"…"` with `"` `\` and control chars re-escaped |
| `LispSymbol` | its name verbatim (case preserved) |
| empty-list | `()` |
| `LispCons` (proper list) | `(` elems space-separated `)` |
| `LispCons` (improper tail) | `( e1 … en . tail )` |

- The printer **does not** abbreviate `(quote x)` back to `'x` in Phase 1 (keeps
  the round trip trivially correct); may be added later.
- Cyclic structure is out of scope (the reader cannot produce it in Phase 1).

### Round-trip guarantee

For every datum `d` the §6 grammar can produce:

```
LispReader read: (LispPrinter writeString: d)   ≡   d
```

where `≡` is structural equality (`equal?`-style: booleans/numbers/chars by
value, strings by contents, symbols by interned identity, lists element-wise,
dotted tails compared recursively). `Float` values must reproduce **exactly**
(bit-identical). A Phase-1 test helper provides this structural comparison; the
real `equal?` is Phase 2.

## 9. Error handling

All reader errors are `LispReadError` with a human-readable message and a source
offset. At minimum these must be detected:

- Unterminated string (EOF before closing `"`).
- Unterminated list / unterminated block comment (EOF before close).
- Unexpected `)` with no open list.
- Malformed dotted pair (`( . a )`, `( a . )`, `( a . b c )`).
- Unknown `#` syntax (e.g. `#q`) — distinct, clear message.
- A lone `.` token outside a list.

The reader never returns a partial datum on error; it signals.

## 10. Acceptance criteria

Realized as a headless script **`tests/phase-1-reader-printer.st`** following the
`poc/answer.st` convention (build, assert, print `PASS`/`FAIL` per check, end with
`RESULT: n/n`). Each criterion below is one or more checks.

**Atoms**
- AC-1 `42` → `Integer` 42; `-3` → -3; `+7` → 7.
- AC-2 `3.14` → `Float`; `-1e9`, `.5`, `2.` parse as reals.
- AC-3 `"hi"` → String `hi`; `"a\nb"` has an embedded newline; escapes `\" \\ \t`.
- AC-4 `#t`/`#true` → `true`; `#f`/`#false` → `false`.
- AC-5 `#\a` → `$a`; `#\space` → space; `#\newline` → LF; `#\x41` → `$A`.
- AC-6 `foo` → `LispSymbol`; `set!`, `+`, `->x`, `...` all read as symbols.
- AC-7 `foo` read twice yields the **same** `LispSymbol` (interning); `Foo` ≠ `foo`.
- AC-8 Tokens that look numeric are numbers, not symbols (`+` is a symbol, `+1`
  is a number).

**Compounds**
- AC-9 `()` → empty-list singleton; is not `#f`, not a symbol.
- AC-10 `(1 2 3)` → proper 3-element list; length and elements correct.
- AC-11 `(1 . 2)` → dotted pair (car 1, cdr 2).
- AC-12 `(1 (2 3) 4)` → correct nesting.
- AC-13 `'x` → `(quote x)` with `quote` the interned symbol.

**Whitespace / comments**
- AC-14 Leading/trailing/interior whitespace ignored: `"  (1   2)\n"` → `(1 2)`.
- AC-15 Line comment: `"; hi\n 1"` → 1. Block comment `"#| a #| b |# c |# 2"` → 2
  (nested). 

**Reader protocol**
- AC-16 `readAll: "1 2 3"` → three data in order.
- AC-17 `read:` of empty/whitespace-only input → signals `LispReadError`;
  `read:` of two data → signals `LispReadError`; `next` on empty input → eof
  object; `readAll:` of empty input → empty collection.

**Errors (each signals `LispReadError`)**
- AC-18 `"\"abc"` (unterminated string).
- AC-19 `"(1 2"` (unterminated list); `"1)"` (stray close).
- AC-20 `"( a . )"`, `"( . a )"`, `"( a . b c )"` (bad dotted pairs).
- AC-21 `"#q"` (unknown hash syntax).

**Round trip**
- AC-22 For a fixed corpus spanning every value type, nesting, dotted pairs,
  strings-with-escapes, booleans, chars, and symbols:
  `read(writeString(d)) ≡ d`.
- AC-23 Float round trip is exact for a set including `0.1`, `1e100`,
  `-3.14159`, very small and very large magnitudes.

**Definition of done:** all acceptance checks pass headless, and the suite is
committed and runnable via the command in `CLAUDE.md`.

## 11. Resolved decisions

Settled 2026-11-02 (owner sign-off); the spec is Accepted on these.

1. **Class-name prefix.** `Lisp*` (`LispReader`, `LispPrinter`, `LispSymbol`,
   `LispCons`, `LispEmptyList`) in package `CogLisp-Reader`.
2. **Empty list representation.** A dedicated `LispEmptyList` singleton — **not**
   Smalltalk `nil` — so `()` stays distinct from "absent".
3. **`read:` on empty/multiple input.** `read:` **signals** `LispReadError` on
   zero or more-than-one datum; `next` returns the eof object at end; `readAll:`
   of empty input returns an empty collection.
4. **`[]` brackets as list delimiters.** Not supported, by decision.
5. **String escape set.** v1 is exactly `\" \\ \n \t \r \0`. `\xHH;` is deferred.

## 12. Downstream notes

- `LispSymbol` interning established here is the basis for `eq?` in Phase 2.
- The reader's output is the compiler's input in Phase 3; keeping it plain data
  (no behaviour baked in) keeps the compiler free to interpret forms.
- When quasiquote lands (Phase 7), it extends §6 `abbreviation` only; nothing
  here needs to change.
