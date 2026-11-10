# Spec — Phase 7.8: Strings, Characters, Vectors & Hash Tables

| | |
|---|---|
| **Phase** | 7.8 (the third step before Phase 8; README "Before Phase 8") |
| **Status** | Implemented (2026-11-04) — `tests/phase-7.8-native-data.st` 58/58; five examples; all suites 853/853 |
| **Depends on** | Phases 1–7.7 (primitives signal conditions, §7) |
| **Feeds** | Phase 8 (a reader and compiler written in LISP), the expert system (fact indexing) |
| **Approach** | Native primitives (owner decision): LISP procedures in the runtime, not LISP names over interop |

## 1. Goal

Give cog-lisp the data a reader and a compiler written in LISP need: look inside
and build strings, classify characters, keep fixed-size indexed data, keep
tables, and read characters from a string one at a time. Today a LISP program
cannot do any of these without dropping into Smalltalk with `send`.

## 2. Scope

**In scope:** the R7RS character, string, vector and string-port procedures in
§4–§6 and §8; hash tables (SRFI 69, §7); `#(…)` vector syntax; `read` from a
string port; printing and equality for vectors and tables; examples (§10).

**Deferred:** bytevectors; Unicode normalization and full case folding beyond
what Pharo's `Character` gives; file ports (`open-input-file`) — Phase 7.9
(with `load` relative to the loading file, review R-22); `string-for-each` and
`string-map` over several strings; SRFI 13's full string library.

## 3. Decisions

- **Lean on Pharo for representation, keep LISP names.** A LISP string *is* a
  Smalltalk `String`, a character a `Character`, and (leaning) a **vector a
  Smalltalk `Array`**, so interop needs no conversion and `list->array` from
  Phase 7.6 becomes an alias of `list->vector`. A **hash table** is a
  `LispHashTable` wrapping a Pharo `PluggableDictionary`, because LISP keys need
  LISP equality (§7.1).
- **The primitives are native**: compiled into `LispPrimitives`, checked, and
  signalling conditions with LISP messages (`string-ref: index 9 out of range
  for a string of length 3`), never Smalltalk errors.
- **Literal strings and vectors are immutable** (R7RS allows it; Opal already
  makes string literals read-only). `string-set!` on a literal is an error that
  says so; `string-copy`, `make-string` and `string` make mutable ones.
- **Indexes are 0-based**, as in Scheme (Smalltalk is 1-based; the primitives
  translate).

## 4. Characters

`char?` (exists), `char->integer`, `integer->char`, `char=?` `char<?` `char>?`
`char<=?` `char>=?` (two or more arguments), `char-ci=?`, `char-alphabetic?`,
`char-numeric?`, `char-whitespace?`, `char-upper-case?`, `char-lower-case?`,
`char-upcase`, `char-downcase`, `digit-value`.

## 5. Strings

- **Construct:** `make-string k [char]`, `string char …`, `string-copy s [start
  [end]]`, `string-append s …`, `list->string`, `number->string z [radix]`,
  `symbol->string`.
- **Inspect:** `string-length`, `string-ref`, `substring s start [end]`,
  `string->list s [start [end]]`, `string->number s [radix]` (`#f` when it is not
  a number; it accepts what the reader accepts), `string->symbol` (interned).
- **Compare:** `string=?` `string<?` `string>?` `string<=?` `string>=?`,
  `string-ci=?`.
- **Change:** `string-set!`, `string-fill!`, `string-copy! to at from [start [end]]`.
- **Convenience (not R7RS, needed by a reader and common in CL):**
  `string-upcase`, `string-downcase`, `string-index s char` (first index or
  `#f`), `string-search s pattern` (first index or `#f`), `string-split s char`,
  `string-join list [separator]`, `string-trim`.

## 6. Vectors

- **Syntax:** `#(1 2 "x")` reads as a vector and is self-evaluating (quoted or
  not). The printer writes `#(1 2 "x")`.
- **Procedures:** `vector?`, `make-vector k [fill]`, `vector obj …`,
  `vector-length`, `vector-ref`, `vector-set!`, `vector->list v [start [end]]`,
  `list->vector`, `vector-fill!`, `vector-copy`, `vector-append`, `vector-map`,
  `vector-for-each`, `subvector`.
- `equal?` compares vectors element by element; `eqv?` by identity.
- Quasiquote over vectors (`` `#(1 ,x) ``) works (it was deferred to here in
  Phase 7 §2).

## 7. Hash tables (SRFI 69)

### 7.1 Equality
`(make-hash-table)` compares keys with `equal?` (strings and lists work as
keys); `(make-hash-table eq?)` and `(make-hash-table eqv?)` give faster tables
for symbols and numbers. Hashing follows the same equality, so a list key
mutated after insertion is lost, as in every Scheme.

### 7.2 Procedures
`make-hash-table [equal]`, `hash-table?`, `hash-table-set!`,
`hash-table-ref table key [thunk]` (calls `thunk` when absent; without one,
absent is an error), `hash-table-ref/default table key default`,
`hash-table-delete!`, `hash-table-contains?`, `hash-table-count`,
`hash-table-keys`, `hash-table-values`, `hash-table->alist`,
`hash-table-walk table proc`, `hash-table-update! table key proc [thunk]`,
`hash-table-update!/default table key proc default`, `hash-table-copy`,
`hash-table-clear!`, `alist->hash-table alist [equal]`.

`hash-table-keys`, `-values` and `->alist` answer in **insertion order** (the
`OrderedDictionary` behavior), so programs and `.expected` outputs are
deterministic.

### 7.3 Printing
`#<hash-table 3>` (its count).

## 8. String ports and `read`

What a LISP reader needs: read characters from a string one at a time.

- `open-input-string s`, `read-char [port]`, `peek-char [port]`,
  `read-line [port]`, `read-string k [port]`, `eof-object`, `eof-object?`,
  `char-ready?` (always `#t` for a string port).
- `open-output-string`, `write-char c [port]`, `write-string s [port]`,
  `get-output-string port`; `display` and `write` take an optional port.
- `(read [port])` reads one datum with the Phase 1 reader, `eof-object` at the
  end. With no port, `read` reads from stdin.
- `with-output-to-string thunk` captures what `thunk` writes (convenience).

## 9. Errors (Phase 7.7)

Every primitive checks its arguments and signals a `LispError` (so `guard` and
`error-object-message` see it) naming the procedure: `vector-ref: index 5 out of
range for a vector of length 3`, `string-ref: not a string: 5`,
`string-set!: string is immutable (a literal)`, `hash-table-ref: no key: foo`.

## 10. Examples

Each feature lands with an example, run by the runner suite:

| Example | Proves |
|---|---|
| `examples/strings.lisp` | building, slicing, searching and comparing strings; characters; `string->number`; a Caesar cipher |
| `examples/vectors.lisp` | `#(…)` syntax, `make-vector`, `vector-map`, an in-place sort of a vector |
| `examples/hash-tables.lisp` | word counts with `hash-table-update!/default`; `equal?` keys (lists, strings); `eq?` tables |
| `examples/string-ports.lisp` | a tiny tokenizer over `open-input-string` with `peek-char`/`read-char`; `read` of data from a string; building output with `open-output-string` |
| `examples/tiny-reader.lisp` | a reader for a subset of cog-lisp (lists, symbols, integers, strings) **written in cog-lisp**, checked against the built-in `read` — Phase 8 in miniature |

## 11. Acceptance criteria

**`tests/phase-7.8-native-data.st`**:
- AC-1 Each character procedure of §4, including `integer->char` of 955 (λ).
- AC-2 Each string procedure of §5, with 0-based indexes and optional ranges.
- AC-3 `string-set!` on `(make-string 3 #\a)` works; on a literal it is an error.
- AC-4 `string->number` on integers, floats, `-0.0`, and non-numbers (`#f`).
- AC-5 `#(…)` reads, self-evaluates, prints, and round-trips; `equal?` on vectors.
- AC-6 Each vector procedure of §6; `list->array` still works and is a vector.
- AC-7 Quasiquote over a vector with unquote and splicing.
- AC-8 Hash tables with `equal?` keys (strings, lists, numbers), `eqv?` and `eq?`
  tables; every procedure of §7.2; insertion order of `keys`/`->alist`.
- AC-9 String ports: input (`read-char`, `peek-char`, `read-line`, EOF), output
  (`write-char`, `display` to a port, `get-output-string`), and `read` of
  several datums then the EOF object.
- AC-10 Errors are `LispError`s with the messages of §9 (one per family).
- AC-11 Interop: a LISP vector passed to Smalltalk is an `Array`; an `Array` from
  Smalltalk is `vector?`; strings unchanged.
- AC-12 All earlier suites, the runner suite (with the examples) and the
  benchmarks pass. Earlier `.expected` files that printed an `Array` as
  `#<#(…)>` (Phase 7.6 examples) now print `#(…)`, updated in the same commit.

## 12. Resolved decisions

Settled 2026-11-04 (owner sign-off); the spec is Accepted on these.

1. **Vectors are Smalltalk `Array`s.**
2. **Hash tables use the SRFI 69 names.**
3. **Literal strings (and vectors) are immutable**; `string-copy`, `make-string`
   and `vector-copy` make mutable ones.
4. **String ports and `read` are in this phase**; file ports come with 7.9.

## 13. As implemented

- **Tests:** `tests/phase-7.8-native-data.st` 58/58 (AC-1 to AC-11); five
  examples in the runner suite (73/73); all suites 853/853; benchmarks
  unchanged.
- **`read` and `read-char` need a port** in this phase: reading stdin a
  character or a datum at a time comes with file ports in 7.9 (the REPL owns
  stdin today). The error says so.
- **Hash tables** wrap each key in a `LispHashKey` whose `=` and `hash` follow the
  table's equality, kept in a Pharo `OrderedDictionary` for insertion order.
  `equal?` hashing is bounded in depth (a circular key cannot hang it); the
  equality must be `eq?`, `eqv?` or `equal?` (others are an error). SRFI 69's
  `hash-table-exists?` and `hash-table-size` are aliases of `-contains?` and
  `-count`.
- **Literal vectors are read-only** (`beReadOnlyObject` when read), like literal
  strings; `vector-copy`, `vector` and `make-vector` make writable ones.
- **Strings** are built through a stream, so a wide character (λ) makes a
  `WideString` as needed; `string-set!` of a wide character into a byte string
  works.
- **`display`, `write` and `newline`** take an optional output port;
  `with-output-to-string` captures `display` output.
- **The end-of-file object** prints `#<eof>` (review R-18).
- **Smalltalk `Array`s print as vectors** (`#(3 1 2)`), so
  `examples/interop-values.expected` changed one line.
