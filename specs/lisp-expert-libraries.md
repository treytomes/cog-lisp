# Bringing lisp-expert's libraries into cog-lisp

| | |
|---|---|
| **Status** | Accepted (2026-11-09), with the owner's decisions (§5) |
| **Asked for by** | The owner (2026-11-09): sort out the library functions and test files in `~/projects/lisp-expert`'s root and `lib/`, set them up with their tests in cog-lisp, and remove them from lisp-expert |
| **Before** | HTTPS (specs/https-and-json.md), which comes next, before Phase 11 |

## 1. What is there (read 2026-11-09)

| File | Lines | What it is |
|---|---:|---|
| `lib/cl.lisp`, `lib/test.lisp` | 204, 149 | cog-lisp 0.2.1's own files, with a documentation string added to each definition |
| `lib/cl-test.lisp`, `lib/test-test.lisp` | 61 and 19 checks | tests of those two files |
| `format.lisp` and three `format-*-test.lisp` | 266; 81 checks | already in cog-lisp: `format` is built in, and the three suites run there (specs/format.md) |
| `common.lisp` | 128 | the hub every expert and weather file loads; it loads `lib/cl.lisp`, `datetime.lisp` and `format.lisp`, and defines the helpers below |
| `common-test.lisp` | 26 checks | tests of `common.lisp` |
| `datetime.lisp` | 156 | dates, durations and intervals over Pharo's `DateAndTime` and `Duration` |
| `expert/test/test-datetime.lisp` | 26 checks | its tests, filed under `expert/` |
| `pretty.lisp` | 60 | `lisp-pretty`: data (lists, hash tables, strings) as an indented string; no tests |
| `hello.lisp`, `fibo.lisp`, `functional.lisp` | 2, 22, 8 | scratch programs |

What `common.lisp` defines:
- `setf`, for variables only;
- `list-at`, `list-from`, `cadr`, `caddr`;
- `first`, `rest`, `second`, `third`, `fourth`;
- `boundp`;
- `filter`, `remove` (of an item), `unique`;
- `capitalize`, `symbol->display-name`.

## 2. The sort

| What | Where it goes | Why |
|---|---|---|
| `lib/cl.lisp`, `lib/test.lisp` | **merged** into cog-lisp's own: the documentation strings come upstream | they are cog-lisp's files; `(require 'cl)` and `(require 'test)` load them from anywhere |
| `lib/cl-test.lisp`, `lib/test-test.lisp` | `tests/lisp/cl.lisp` and `tests/lisp/test-library.lisp` | tests of cog-lisp's files belong with them |
| `format.lisp`, its three tests | deleted from lisp-expert | built in, with the tests already in cog-lisp |
| `list-at`, `list-from`, `cadr`, `caddr` | **built in, as R7RS names** (decision 1): `list-ref`, `list-tail`, and the `c[ad]r` family | R7RS defines them, and cog-lisp lacks them |
| `filter`, `remove`, `unique` | **built in, as SRFI 1 names** (decision 2): `filter`, `remove` (by a predicate), `delete` (an item), `delete-duplicates` | the names most Schemes use; the Common Lisp names go in `cl.lisp` |
| `first` … `fourth`, `rest`, `boundp`, `setf` | **`lib/cl.lisp`** | Common Lisp names. `cl.lisp` already has `first` to `third` and `rest`, and `setf` for places since 9.4; it gains `fourth` to `tenth`, `boundp`, `remove`/`delete` (by item), `remove-duplicates`, and `string-capitalize` |
| `datetime.lisp`, `test-datetime.lisp` | **`lib/datetime.lisp`**, loaded with `(require 'datetime)`; `tests/lisp/datetime.lisp` | a general library, not needed by every program, so not built in |
| `pretty.lisp` | **`lib/pretty.lisp`**, `(require 'pretty)`, with new tests (decision 3) | general; it gets the tests it never had |
| `capitalize`, `symbol->display-name` | **stay in lisp-expert**, as `expert/names.lisp` | they name knowledge-base symbols for display, which is the expert system's business |
| `common.lisp`, `common-test.lisp` | deleted; each lisp-expert file says what it needs: `(require 'cl)`, `(require 'datetime)`, `(load "names.lisp")` | nothing general is left in them |
| `hello.lisp`, `fibo.lisp`, `functional.lisp` | deleted | scratch: cog-lisp's examples already show the same |
| `run-tests.sh` | stays, without the suites that moved | the project's runner |

## 3. Requirements

- **R-1. Built in** (in `lib/core.lisp`, which the seed compiles, so plain code):
  - `list-ref` and `list-tail`;
  - the 28 `c[ad]r` names of R7RS: `caar` to `cddr` (base) and the three- and
    four-letter ones (`(scheme cxr)`);
  - `filter`, `remove`, `delete` and `delete-duplicates`, as SRFI 1 defines
    them;
  - SRFI 1's `fold`, `reduce` and `iota`, and `sort` (decision 2).

  Each is documented, and the derived forms and the compiler stay free to use
  them a release later (the self-hosting rule).
- **R-2. `lib/cl.lisp` gains:**
  - `fourth` to `tenth`, with setters (9.4);
  - `boundp`, true if the global environment binds the symbol (it asks the
    environment, not `eval`);
  - Common Lisp's `remove` and `delete` of an item, which shadow SRFI 1's
    `remove` when `cl.lisp` is loaded (its known gaps say so);
  - `remove-duplicates`;
  - `string-capitalize`, Common Lisp's: each word capitalized, the rest lower
    case.
- **R-3. `lib/datetime.lisp`** is lisp-expert's `datetime.lisp`, with its
  Smalltalk names written `(smalltalk DateAndTime)` so it does not depend on how
  a bare name in brackets resolves. Each definition keeps its documentation
  string.
- **R-4. `lib/pretty.lisp`:**
  - `(pretty-string value [indent])`, lisp-expert's `lisp-pretty` under a
    cog-lisp name. It is new, so there is no alias (decision 3);
  - JSON's `null`, now `()` (specs/https-and-json.md), prints as `()`;
  - its own `string-join` and `->string` are dropped, since `string-join` is
    built in, with the same arguments.
- **R-5. Tests:**
  - each moved suite runs in `tests/lisp/`, changed only in its `load` lines;
  - `lib/pretty.lisp` and the new built-ins get new tests;
  - every name the skill's traps call missing is checked again (R-6).
- **R-6. The skill** (Phase 10.7): `list-ref`, `filter`, `fold`, `iota` and
  `sort` are no longer traps, since they are built in. The helpers example
  becomes one that uses them. Names still missing (`first`, `second`, `last`)
  stay a trap. The evaluation is run again.
- **R-7. lisp-expert:**
  - the moved files are deleted;
  - each file that loaded `common.lisp` requires what it uses instead;
  - `unique` and the item-`remove` become `delete-duplicates` and `delete`;
  - `run-tests.sh` loses the moved suites;
  - every remaining suite passes against cog-lisp.

  lisp-expert then needs the cog-lisp release that has these. Until that
  release, it runs against a cog-lisp checkout (`COGLISP_RUNNER`).

## 4. Acceptance criteria

- **AC-1:** every moved suite passes in cog-lisp, on Windows and Linux, and
  `tests/lisp/pretty.lisp` covers lists, dotted pairs, hash tables, strings,
  numbers, booleans and `()`.
- **AC-2:** the new built-ins answer as R7RS and SRFI 1 specify, checked by a
  LISP test, and each is documented.
- **AC-3:** every remaining lisp-expert suite passes against cog-lisp's
  checkout, with nothing left in its root or `lib/` but the project's own files
  (`run-tests.sh`, its notes, `scripts/`, `expert/`, `weather/`).
- **AC-4:** the skill's suite passes, with its traps re-checked.

## 5. Decisions (owner, 2026-11-09)

1. **R7RS's list names are built in:** `list-ref`, `list-tail`, the `c[ad]r`
   family.
2. **SRFI 1's procedures are built in:** `filter`, `remove`, `delete` and
   `delete-duplicates` (with Common Lisp's item-`remove` in `cl.lisp`), and
   `fold`, `reduce`, `iota` and `sort` too.
3. **The pretty-printer is `pretty-string`**, with no alias: it is new.
4. **The release comes after lisp-expert is cleaned up and verified**, not
   straight after this step.
