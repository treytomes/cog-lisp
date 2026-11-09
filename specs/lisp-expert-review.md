# What reviewing lisp-expert's code found: library gaps, library use, bugs

| | |
|---|---|
| **Status** | Done (2026-11-09); accepted with the leanings of §7. lisp-expert's side awaits the owner's commit |
| **Asked for by** | The owner (2026-11-09): review all of `~/projects/lisp-expert`'s LISP for what belongs in the common library and where the library could be better used; then "a spec to cover sections A, B, and C … resolve the entire set in one pass" |
| **Follows** | specs/lisp-expert-libraries.md (done), which moved lisp-expert's general libraries here |
| **Before** | HTTPS (specs/https-and-json.md); its AC-5 re-tests `weather/examples/fetch.lisp` |

## 1. How the review was done

- Every top-level definition in lisp-expert (297, outside its tests) was listed
  and each name looked up on the built image with `(documentation 'name)`.
- Every file but the test suites was read, and each proposed replacement's
  behavior checked on the image (e.g. `string-split` keeps empty fields;
  hash tables find list keys by equality; `string-capitalize` gives
  `"Sample-Person"`).
- Three sections came out of it, each one part of this spec:
  - **A:** what cog-lisp lacks, so lisp-expert wrote it by hand (§3);
  - **B:** what cog-lisp has and lisp-expert does not use (§4);
  - **C:** bugs found on the way (§5).

## 2. Two repositories, one pass

- **Section A changes cog-lisp**; sections B and C change lisp-expert.
- **lisp-expert runs against this checkout** (`COGLISP_HOME` pointing here)
  until a release carries A. Its launcher's default moves to that release.
- **Order:**
  1. record lisp-expert's baseline (§6, R-9) before any change;
  2. A in cog-lisp, on a branch, through CI;
  3. B and C in lisp-expert, checked against the baseline;
  4. one release afterwards, as last time.
- **lisp-expert's changes are committed only with the owner's go-ahead**: it
  is the owner's repository.

## 3. Section A: built into cog-lisp

| Missing | What lisp-expert wrote instead |
|---|---|
| SRFI 1 `any`, `every` | `any?` and `all?` (about 10 uses), `working-memory-contains?`, `every-branch-binds?`, `rete-token-member?` |
| SRFI 1 `append-map` | `(apply append (map …))`, 9 times |
| SRFI 1 `filter-map` | loops in `prove`, `rete-alpha-filter-facts`, `load-kb` |
| SRFI 1 `find` | `extract-query-variable`, `find-endpoint`, loops in `base-fact-solution` and `class-path-supports` |
| SRFI 1 `alist-delete` | `(filter (lambda (e) (not (equal? (car e) k))) alist)`, about 12 times |
| `string-prefix?`, `string-suffix?` | `predicate->attribute` |
| R7RS `make-parameter`, `parameterize` | `with-time` and `with-tracing`, saving and restoring globals by hand |
| ISO 8601 parsing in `datetime` | `iso->unix`, over `DateAndTime` directly |

- **R-1. In `lib/core.lisp`, as SRFI 1 defines them,** documented, under
  category Lists:
  - `(any pred list)`: the first true value `pred` answers, else `#f` (a value,
    not just `#t`: `base-fact-solution` needs the environment);
  - `(every pred list)`: `#t` for an empty list, else the last value, or `#f`;
  - `(find pred list)`: the first element satisfying `pred`, else `#f`;
  - `(filter-map f list)`: `f`'s true values, in order;
  - `(append-map f list)`: `f`'s lists appended, in order;
  - `(alist-delete key alist [=])`: every entry whose key is not `key`
    (`equal?` by default; `=` is called as `(= key k)`), the alist unchanged.
  - Each takes **one list**, as `map` and `for-each` do here. Errors name the
    procedure, as the built-ins' do.
- **R-2. `string-prefix?` and `string-suffix?`** (`(string-prefix? prefix
  string)`, SRFI 13's argument order), in category Strings.
- **R-3. `make-parameter` and `parameterize`** (R7RS 4.2.6):
  - `(make-parameter value [converter])` answers a procedure; calling it with no
    arguments answers the current value. A converter is applied to the initial
    value and to each `parameterize` value.
  - `parameterize` is a `syntax-rules` macro in `lib/core.lisp` (the seed
    compiles `syntax-rules`), over `dynamic-wind`: the old values come back when
    the body returns, raises an error, or is left by a restart (cog-lisp has
    no `call/cc`; its non-local exits are errors and restarts).
  - The binding is per image, not per Smalltalk process; cog-lisp programs run
    in one. (Recorded so that threads, when they come, revisit it.)
- **R-4. `lib/datetime.lisp` gains `(datetime-from-string string)`**, the
  inverse of `datetime->string`:
  - ISO 8601: a date (`2026-11-09`), or a date and time with or without seconds
    (`2026-11-09T13:00`, `…T13:00:00`), with or without an offset (`Z`,
    `+01:00`, `-06:00`).
  - **A string without an offset is UTC.** Pharo's own `fromString:` reads it
    as the machine's local time (on this machine, 6 hours apart), which would
    make a program's answers depend on where it runs. Open-Meteo's times have
    no offset.
  - A string it cannot read is an error naming `datetime-from-string` and the
    string.
- **R-5.** The new names reach `docs/builtins.md`, `vscode/builtins.json`, the
  manual and the skill's reference (all generated). `SKILL.md` stays under its
  10 KB budget; the `list-tools` example may show `any` or `find` only if it
  fits.

## 4. Section B: lisp-expert uses what cog-lisp has

- **R-6. Its own copies of library procedures go:**

  | lisp-expert | Becomes |
  |---|---|
  | `dedup-list`, `dedup-pairs` (two copies of one function), `unique-symbols` | `delete-duplicates` |
  | `any?`, `all?` | `any`, `every` (R-1) |
  | `string-join` (defined twice, shadowing cog-lisp's, same arguments) | the built-in |
  | `->string` (defined twice, the copies different) | one copy, in `weather/transport.lisp` |
  | `trim`, and `parse-int`'s use of it | `string-trim` |
  | `repl-split` | `string-split` on `#\space`, empty fields dropped (it keeps them) |
  | `sort-activations` / `insert-activation` (insertion sort, O(n²), every agenda build) | the built-in stable `sort` with `activation-before?`: the same order |
  | `trace-indent`, `pprint-indent` (one space at a time) | `make-string` |
  | `public-env` and `proof-bindings` (one function twice) | one procedure, over `alist-delete` |
  | `predicate->attribute`'s prefix test | `string-prefix?` (R-2) |
  | `iso->unix` | `datetime-from-string` (R-4), then `datetime->unix` |
  | `extract-query-variable`, `find-endpoint` | `find` |

- **R-7. Loops that are library procedures become them:**
  - `(apply append (map …))` becomes `append-map`;
  - accumulating loops become `filter`, `filter-map`, `fold`, `any`;
  - the min/max/sum loops (`aggregate-confidence`, `support-recency`,
    `sum-aggregate-values`) become `fold` or `apply min`/`max`;
  - the CF-combining loops (`negation-certainty`, `recompute-derived-fact!`)
    become `fold`;
  - `with-supports` becomes `fold`.
  - **Order is kept:** a loop that builds its answer reversed
    (`negative-supports`, `uncertain-supports`) is replaced by code that gives
    the same order, or the change of order is shown to reach no output (R-9).
- **R-8. Keyed stores become hash tables**, which find list keys by equality:
  - `*cf-kb*`, `*base-cf-kb*`, `*recency-kb*` and `*temporal-kb*`, keyed by the
    `(s p o)` triple;
  - the memo table, keyed by `(pattern env time)`;
  - the two activation indexes.

  The repeated "update the entry, or add one" idiom (about 8 copies) becomes
  `hash-table-set!`, and "delete the entry" becomes `hash-table-delete!`.
  - **Order and persistence stay as they are.** Anything that walks a store
    (`save-kb`, `derived-state`, `snapshot-facts`) sorts or follows the triple
    lists, so a saved knowledge base is byte-identical to one saved before. A
    store whose iteration order reaches output stays a list.
  - **`display` chains become `format`** where they print one line
    (`explanation.lisp`, the time-of-day demo in `main.lisp`, `repl-help`).
- **R-8a. The weather JSON layer moves onto `json-read`**:
  - `json-decode` keeps its `(ok . value)` / `(error . message)` answer, but
    reads with `json-read`, and `json->lisp` goes;
  - the accessors stay (`json-get`, `json-has?`, `json-keys`, …), so callers do
    not change, except where the data does (decision 3):
    - an array is a vector (it was a list): `forecast->facts` walks it as one;
    - `null` is `()` (it was Smalltalk `nil`): `json-null?` and the `null`
      skip in `forecast->facts` test for `()`;
    - an absent key answers `#f` from `json-get`; `json-has?` tells it from a
      present `false`.
  - The curl transport itself is HTTPS's to replace (its AC-5); this spec only
    removes its copies of library procedures (R-6).

## 5. Section C: bugs in lisp-expert

- **R-9 (baseline).** Before any change, the output of each expert example
  (`expert/main.lisp`, `examples/main-family.lisp`, `main-medical.lisp`,
  `persist.lisp`, `datetime-example.lisp`), the weather examples that run
  offline, the 10 suites' results, and a saved knowledge base are recorded.
  After B and C they are compared byte for byte. A difference is either a bug
  this spec fixes, and is listed, or it is a regression.
- **R-10. The bugs to fix:**
  1. **`with-time` is defined twice** in `backward-chaining.lisp`: a procedure
     (line 271), then a macro (line 285). The procedure is dead.
  2. **`with-time` does not restore `*current-time*` when its body raises an
     error.** `*current-time*` becomes a parameter (R-3), and `with-time` a
     `parameterize`; `with-tracing` likewise for `*trace-firings*`.
  3. **`unique-symbols` keeps the last occurrence**, though its docstring says
     the first (`(a b a)` gives `(b a)`). It goes (R-6). Its callers test
     membership only, so nothing changes, which R-9 confirms.
  4. **`rule-variables` and `collect-vars` are one function**, and `vars-in`
     and `query-variables` compute the same thing in different orders: one of
     each remains, in first-occurrence order.
  5. **`rete-beta-provenance-for-input` has two docstrings**; the second is a
     dead expression.
  6. **`eval-goals*` binds `combined-cf` and never uses it.**
  7. **`rete-alpha-entry-for-triple` calls `(member triple (query-facts))`**,
     and `query-facts` rebuilds the fact list with `map` on every call: a
     membership test against the store itself replaces it.
  8. **`->string` in `transport.lisp` prints an unknown value to stdout** (its
     `else` branch is `(display x) ""`): it answers the value's written form
     instead, and writes nothing.
  9. **`iso->unix` appends `Z` to any string not ending in `Z`**, so a time
     with an offset (`…+01:00`) becomes unreadable. `datetime-from-string`
     (R-4) reads every form.
- **R-11.** Each fix in R-10 that a suite can show gets a check in lisp-expert's
  suites (2, 8, 9 at least); the others are shown by R-9 or by reading.

## 6. Acceptance criteria

- **AC-1 (A):** `tests/lisp/lists-srfi1-more.lisp` checks R-1, including `any`
  answering the predicate's value, `every` on `()`, `alist-delete` with a test
  argument and leaving its argument unchanged. `tests/lisp/strings-prefix.lisp`
  checks R-2. Every new name is documented (the 10.1 suite).
- **AC-2 (A):** `tests/lisp/parameterize.lisp` checks R-3: a converter applied,
  nesting, the old value back after a normal return, after an error caught
  outside, and after a restart leaves the body.
- **AC-3 (A):** `tests/lisp/datetime.lisp` checks `datetime-from-string` on
  every form in R-4, that a string without an offset is UTC (the same Unix time
  whatever the machine's zone), the round trip with `datetime->string`, and the
  error.
- **AC-4 (A):** every cog-lisp suite passes on Windows and Linux, the generated
  files are current (10.2, 10.4, 10.7 suites), and `SKILL.md` is under 10 KB.
- **AC-5 (B):** none of the names R-6 removes is defined anywhere in
  lisp-expert outside its tests (a listing of its definitions shows it), and no
  `(apply append (map` remains.
- **AC-6 (B, C):** lisp-expert's 10 suites pass, with the new checks of R-11,
  and R-9's outputs match the baseline byte for byte, apart from the listed bug
  fixes.
- **AC-7 (B):** a knowledge base saved by `expert/examples/persist.lisp` is
  byte-identical to the baseline's, and loads.
- **AC-8 (B):** the 10 suites and `expert/main.lisp` take no longer than at the
  baseline (best of three runs each, recorded here).

## 7. Decisions for the owner

1. **`any`/`every` replace `any?`/`all?`** rather than living beside them.
   Leaning: replace them (SRFI 1's names, as with `filter`).
2. **`parameterize` binds per image** (R-3), not per Smalltalk process.
   Leaning: per image now; cog-lisp has no threads to see the difference.
3. **The weather JSON data changes shape** (R-8a): arrays become vectors and
   `null` becomes `()`, matching `json-read`. The alternative is to keep the old
   shape by converting after `json-read`. Leaning: change it, so the weather
   code and cog-lisp agree, and `pretty-string` already prints that shape.
4. **The stores become hash tables** (R-8). This is the largest change in
   lisp-expert, and the only one that is about speed rather than tidiness.
   Leaning: do it, held to AC-7 and AC-8.
5. **A string without an offset reads as UTC** in `datetime-from-string`
   (R-4), unlike Pharo. Leaning: UTC.

## 8. As built (2026-11-09)

- **cog-lisp (A):**
  - `lib/core.lisp`: `any`, `every`, `find`, `filter-map`, `append-map`,
    `alist-delete` (Lists); `string-prefix?`, `string-suffix?` (Strings);
    `make-parameter` (Control) and the derived form `parameterize`.
  - `lib/datetime.lisp`: `datetime-from-string`, a strict parser that builds
    the time with `DateAndTime year:month:day:hour:minute:second:nanoSecond:offset:`
    (Pharo's lenient `fromString:` reads `"hello"` as an error about a year,
    and an offset-less time as local).
  - Suites: `lists-srfi1-more` (36 checks), `strings-prefix` (13),
    `parameterize` (19), and 50 in `datetime` (24 new). The skill's
    `list-tools` example gained `find`; `SKILL.md` is 9,717 bytes.
- **Deviations, recorded here first:**
  - **cog-lisp has no `call/cc`**, so R-3 and AC-2 test the old value coming
    back after a restart leaves the body, cog-lisp's non-local exit.
  - **`*trace-firings*` stays a variable** (R-10 item 2): `trace-on` and
    `trace-off` are switches that stay set, which a parameter cannot be.
    `with-tracing` now gives back the previous value instead of always turning
    tracing off. `*current-time*` is a parameter, as specified.
- **Found while doing it:**
  - **`with-time`'s only test never ran its check.** The test calls
    `(with-time 15 (lambda () (check …)))`, the procedure's form; the macro
    that replaced the procedure evaluated the `lambda` and never called it.
    `with-time` is now one procedure over `parameterize`, and the check runs.
  - **`*cf-kb*` and `*base-cf-kb*` were one list** after
    `reset-working-memory`, `reset-derived-state` or `load-kb`, so a derived
    CF written through `*cf-kb*` (`assert-derived`, `set-fact-cf!`) also changed
    the base CF of a triple that was both. `*cf-kb*` is now a copy of
    `*base-cf-kb*`. No example or suite output changed.
  - **cog-lisp's `map` evaluates right to left** (R7RS leaves it open), so
    `(apply append (map f …))` called `f` last element first, and `append-map`
    calls it first to last. Where `f` freshens rules this changes the numbers in
    fresh variable names; no output showed it.
  - `rete-join-alpha` was never called, and `negative-rule-supports` had no
    caller left: both went.
- **lisp-expert (B, C):** 17 files, 408 lines added and 651 removed; every
  name R-6 removes is gone (AC-5), and no `(apply append (map` remains.
- **AC-6, AC-7 (against R-9's baseline):** the outputs of `expert/main.lisp`,
  `main-family`, `main-medical` and both `persist` runs, and both saved
  knowledge bases, are byte-identical. The differences are:
  - the labels of the suite checks that now read hash tables;
  - the checks R-11 adds: the temporal suite has 18 checks (14 before: one is
    the `with-time` check that never ran), the JSON suite 16 (12), the
    transport suite 12 (6), the model suite 7 (4);
  - `weather/examples/json.lisp` prints the new JSON shape (decision 3):
    `null` as `()` and arrays as `#(…)`;
  - `datetime-example` prints the current time, run to run.
  - The live curl HTTPS check in `test-transport` fails on Windows before and
    after (its POSIX shell command; HTTPS's AC-5).
- **AC-8 (best of three):** the 10 suites took 37.9 s (39.5 s before) and
  `expert/main.lisp` 2.08 s (2.15 s before).
- **Noticed, not fixed here:** a cog-lisp program whose stdout is closed early
  (piped into `head`) leaves a `PharoDebug.log` ("File stderr write failed")
  in the current folder.
