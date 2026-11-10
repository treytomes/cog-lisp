# Review of Phases 1–7

Phase 7.5 (`specs/07-phase-7.5-review-and-tooling.md` §4). Each finding has evidence
(a check that was run, or a code reference where it is structural), a verdict,
and, once fixed, the commit.

Verdicts: **fix now** (in Phase 7.5) · **plan → phase** · **keep** (with reason).

**Status (2026-11-03):** every *fix now* finding is fixed, in four batches
(hygiene & tests; errors; compiler loops & speed; runtime correctness), each with
regression checks in `tests/phase-7.5-review.st` (114 checks) or a runner
fixture. What is left is *planned* for a named phase or *kept*; T-3 goes into the
Phase 7.5 VS Code extension.

*Plan targets, as re-ordered 2026-11-03 (README):* **self-hosting** items are
the *self-hosting groundwork* step before Phase 8; **Smalltalk interop** and
**conditions & restarts** also come before Phase 8; **numeric tower** and
**hygienic macros** are part of Phase 9; **language server** is unchanged.

Finding ids: **H** repo hygiene, **T** tests & build, **D** docs, **O**
optimization; **C** compiler & macros and **R** reader, data model, runtime &
REPL come from the independent reviews.

## Repo hygiene

### H-1 Sources check out as CRLF in a fresh clone — fixed (batch 1)
- **Evidence.** Git for Windows sets `core.autocrlf=true` system-wide, and
  `.gitattributes` covers only `*.bat`, `*.lisp`, `*.expected`, `*.stdin`. A fresh
  clone (`git clone` then `git ls-files --eol`) has 41 files as CRLF, including
  every `src/*.st` and `*.md`; every commit warns "LF will be replaced by CRLF".
  The suites still pass from the CRLF clone (Phase 3, 5, 7 suites checked:
  Pharo normalizes line endings on file-in), so this is hygiene, not breakage.
- **Done.** `.gitattributes` makes every text file LF (`* text=auto eol=lf`),
  `*.bat` CRLF, Pharo files binary; `git add --renormalize .` changed nothing in
  the index (it was already LF).

## Tests & build

### T-1 No single command runs everything — fixed (batch 1; AC-5)
- **Evidence.** Seven in-image suites, the runner suite and the benchmarks are
  run separately, each with its own command line.
- **Fix.** `tests\run-all.bat`: every `tests\phase-*.st` against the stock image,
  then `tests\phase-5-runner.bat`; per-suite RESULT lines and a total; exit 1 on
  any failure. Benchmarks stay separate (slow, and noisy on a busy machine).
- **Done.** All 8 suites, 507/507, in ~30 s. A planted failing suite is reported
  with its failing check and makes the run fail.

### T-2 The check harness is copied into every suite — fixed (batch 1)
- **Evidence.** All seven `tests/phase-*.st` define their own `out`, `check`,
  `checkErr` blocks and repeat the package-loading chunk (code reference). The
  copies have drifted: only Phase 7 has `checkMsg`, and suites differ in how they
  print a value that cannot be written.
- **Fix.** `tests/harness.st`, filed in by each suite after the packages: a
  `LispTestHarness` class with `check:actual:expected:`, `check:raises:do:`,
  `check:raises:containing:do:`, and `finish` (prints RESULT, exits 0/1). The
  suites keep their checks unchanged except for the call syntax.
- **Done.** As above, with `h checkBlock`/`checkErrBlock`/`checkMsgBlock` so the
  checks themselves are unchanged; every suite now exits 0 or 1 by its result
  (Phases 1–6 used to exit 0 regardless), and an unexpected error prints the
  partial RESULT and exits 1.

### T-3 Nothing warns that `pharo\cog-lisp.image` is older than the sources — fixed (VS Code extension)
- **Evidence.** `cog-lisp.bat` runs whatever image was last built; after editing
  `src/` or `lib/core.lisp`, programs silently run the old code until
  `build-image.bat` is run (code reference; observed during Phase 7).
- **Verdict.** The VS Code extension gets a "Rebuild image" command and warns
  when a source is newer than the image. No change to the runner.

## Docs

### D-1 CLAUDE.md does not record the compiler/runtime load-order rule — fixed (batch 1)
- **Evidence.** `src/coglisp-compiler.st` loads before `coglisp-runtime.st`, so a
  compiler method that names `LispProcedure` fails to compile ("undeclared");
  the compiler uses `Smalltalk at: #LispProcedure` and `respondsTo:` instead.
  Learned in Phase 6, not written down (`grep` of CLAUDE.md).
- **Done.** Recorded in CLAUDE.md's Opal section, with the batch-1 harness and
  VM findings (parallel runs on one image, the heap cap).

### D-2 "Deferred" lists in earlier specs — keep
- **Evidence.** Phases 1, 3 and 4 list items deferred to Phase 7 (quasiquote,
  internal define, `and`/`or`, …), now done.
- **Verdict.** Keep: each spec is the contract for its phase, and each deferral
  already names where the item went. Later specs record what they extend.

## Optimization

### O-1 Four-argument `+` takes the slow variadic path (and the `globals` benchmark measures it) — fixed (batch 3)
- **Evidence.** 50,000 iterations of a self-loop (`ms` per run, stock image):
  `(+ acc 1)` 0.75 · `(+ acc g1)` 1.05 · `(+ (+ (+ acc g1) g2) g3)` 1.50 ·
  `(+ acc 1 2)` 2.25 · **`(+ acc 1 2 3)` 32.3** · `(+ acc g1 g2 g3)` 34.3.
  `+` and `*` have direct entries for 1–3 arguments only, and `=`, `<`, … for 2
  only (`src/coglisp-runtime.st` ~388–407), though Phase 6 §10 says "0–4". With
  four arguments the call builds a rest list and folds it: ~600 ns a call. The
  `globals 50000` benchmark is `(+ acc g1 g2 g3)`, so its 65–80× gap to Smalltalk
  is this, not global access (global reads cost ~6 ns each above).
- **Fix.** Entries for 0–4 arguments on `+` and `*`, 1–4 on `-`, and 3–4 on the
  comparisons (`(< a b c)`). Rerun the benchmarks; update `bench/results.md` and
  Phase 6 §10. Consider a faster generic variadic path for 5+ arguments.

## Compiler & macros (independent review)

From the reviewer's headless scripts. C-1, C-6, C-10, C-11, C-14 and C-17 were
re-run and reproduced before being recorded.

### C-1 Self tail calls exhaust the frame at ~8 call sites — fixed (batch 3)
- **Evidence.** A `cond` whose k branches each self-tail-call `(st (- n 1) b c a)`:
  k=4 works; k=8 "Cannot compile -- stack including temps is too deep"; k=12
  `genStorePopTemp: index 64 is out of range`. Each self tail call allocates new
  temps for its arguments, all in one frame. Interpreter loops and state machines
  (Phase 8) have this shape.
- **Fix.** One shared set of argument temps per loop, reused by every self tail
  call (safe: an argument is never in tail position). Prototyped by the reviewer:
  30 branches compile and run. Folds in C-12.

### C-12 Self-tail-call arguments are compiled twice — fixed (batch 3)
- **Evidence.** Translated for the loop branch and again for the fallback tail
  call: a counting macro in such an argument expands twice; code and the inline
  temp budget are doubled.
- **Fix.** Evaluate the arguments into the C-1 temps first, then branch on the
  identity check; both branches use the temps.

### C-2 Back-end limits escape as raw Smalltalk errors — fixed (batch 2)
- **Evidence.** Frame overflow, `Too many arguments` and `genStorePopTemp`
  surface as `Error`/`OCCompilationError`, not `LispCompileError`.
- **Fix.** `compile:` catches errors from semantic analysis and code generation
  and re-signals `LispCompileError` with a plain message ("expression too deeply
  nested", "too many parameters (at most 15)").

### C-3 Quasiquote templates with more than ~25 unquoted elements fail — fixed (batch 3)
- **Evidence.** 20 `,x` elements compile; 30 or 60 overflow the frame (nested
  `LispCons car:cdr:`, two stack slots per element). `(list …)` with 300
  arguments is fine (brace arrays). Code-generating macros will hit this.
- **Fix.** Build each run of elements between splices from one brace array.

### C-4 More than 15 parameters or `let` bindings fail — fixed (lambda in 7.9)
- **Evidence.** 16: `OCCompilationError … Too many arguments` (Pharo's block
  argument limit).
- **Verdict.** `let`: compile as a zero-argument block with temporaries. `lambda`:
  **plan → self-hosting** (arguments passed as one array past 15). C-2 gives a
  clean error meanwhile.

### C-5 Calls nested ~20 deep fail — fixed (7.9)
- **Evidence.** `(g 1 (g 1 … 0))` works at 15 levels, fails at 20; 60 internal
  defines in one body also overflow.
- **Verdict.** Plan: hoist arguments into temps past a depth budget. C-2 makes it
  a clean error now.

### C-6 Malformed special forms crash or are silently accepted — fixed (batch 2)
- **Evidence.** `(lambda)`, `(let x)`, `(let ((x)) x)`, `(define)`, `(define x)`,
  `(set! x)`, `(define-macro foo)`, `(let loop)` → `SubscriptOutOfBounds`;
  `(quote)` → `MessageNotUnderstood`. Accepted silently: `(+ 1 . 2)` → 1,
  `(define 5 1)`, `((lambda (x x) x) 1 2)` → 2, `(lambda (x . 5) …)`,
  `(if #t 1 2 3)`, `(quote 1 2)`. Phase 3 §9 requires `LispCompileError` for
  `(lambda)` and `(let x)`.
- **Fix.** Shape checks per special form (arity, symbols for names, no duplicate
  parameters); `listToArray:` rejects improper lists.

### C-7 A macro that expands forever hangs the VM — fixed (batch 2)
- **Evidence.** `(define-macro (forever) '(forever)) (forever)`: no output; killed
  after 91 s.
- **Fix.** An expansion-depth limit: "macro expansion too deep: forever".

### C-8 Named `let`, `do`, `dolist`, `dotimes` are not compiled as loops — fixed (batch 3)
- **Evidence.** Only global defines get the self-loop; local procedures bounce
  every iteration. 10⁷ iterations: global self-loop 102 ms, named `let` 899 ms,
  `do` 875 ms. (Constant stack, as required.)
- **Fix.** The self-loop takes a local name too; its guard compares the local's
  temporary with the procedure instead of a global cell.

### C-9 Every `set!` and `define` allocates a closure — fixed (batch 3)
- **Evidence.** `andUnspecified:` builds `[node. LispUnspecified default] value`;
  a `set!` variable becomes heap-allocated. A `set!` loop: 392 → 179 ms per 10⁷
  iterations with `true ifTrue: [...]` (the Phase 7 `begin` fix).
- **Fix.** Same pattern as `begin`.

### C-10 Named `let` retains made-up source text — fixed (batch 3)
- **Evidence.** `(procedure-source (let lp ((i 0)) lp))` → `"(define (lp i) lp)"`
  (re-run). Also `let` with `#directLet` off.
- **Fix.** Set `sourceContext` to the form's recorded text, as for macro calls.

### C-11 `define-macro` is rejected inside a top-level `begin` — fixed (batch 3)
- **Evidence.** `(begin (define-macro (m1) 1) 2)` → "allowed only at top level"
  (re-run). In R7RS a top-level `begin` is top level; macro-defining macros need it.
- **Fix.** `eval:` expands the top of a form and runs a top-level `begin`'s forms
  one at a time, so a macro defined early in it is usable later in it.

### C-13 With `#literalQuote` off, quoted gensyms become interned — fixed (batch 3)
- **Evidence.** A quoted gensym `eq?` itself: `#t` normally, `#f` with the option off.
- **Fix.** Emit an uninterned symbol as a literal.

### C-14 Special-form names cannot be shadowed; `case` captures a local `memv` — fixed (Phase 9 step 9.3)
- **Evidence.** `((lambda (if) (if 1 2 3)) +)` → 2 (Scheme: 6; re-run);
  `(let ((memv (lambda (a b) #t))) (case 5 ((1) 'one) (else 'other)))` → `one`.
  The body scanner honours a local `begin`; `translateForm` does not.
- **Verdict.** Plan. Now: document it, and make the scanner match `translateForm`.
- **Closed in Phase 9 step 9.3** (2026-11-05). The compiler resolves an
  identifier's binding before it looks for a special form, so the first example
  is `6` (9.3a). `case` and the other derived forms are `syntax-rules` macros
  (`lib/core.lisp`), so the second is `other`: `case` calls the global
  `memv` (9.3b). Checked by `tests/lisp/phase-9.3-syntax-rules.lisp` and
  `tests/lisp/phase-9.3-derived-forms.lisp`; example `examples/shadowing.lisp`.

### C-15 Inner-level `,@,@x` is a compile error — keep
- **Evidence.** `` `(a `(b ,@,@x)) `` → "unquote-splicing outside a list".
- **Verdict.** Keep and document; obscure, and all other nesting cases are right.

### C-16 Quoting a runtime string makes it read-only — plan → Smalltalk interop
- **Evidence.** `eval` of a form holding a fresh string freezes that string.
- **Verdict.** Plan with string mutation: `eval` copies strings it embeds.

### C-17 / R-7 Procedures are never named; arity errors say nothing — fixed (batch 2)
- **Evidence.** `(define (sq x) x) (sq)` → "error: wrong number of arguments"
  (re-run); `sq` and `car` both print `#<procedure>`. Nothing calls `name:`.
- **Fix.** `define` (global and internal) and the primitive installer name the
  procedure; `#<procedure sq>`; "sq: expected 1 argument, got 0".

### C-18 Smaller structural notes — fixed (7.9: dispatch table, template cache; qqAppend in 7.7; error positions planned → language server)
- `qqAppend:to:` signals a plain `Error` → **conditions & restarts**.
- `LispCompileError` carries no form or position → **language server**.
- Special-form dispatch by string comparison; `messageNode:` re-parses a template
  per node (~1.7 ms to compile `fib`) → **self-hosting**.

**Checked and fine:** tail position through every derived form; per-iteration
capture; redefinition while looping; quasiquote nesting, dotted tails and
splices; macro errors and introspection; source retention through macros and
`eval`; inlined and ordinary primitive calls agree; `cond` with 300 clauses.

## Reader, data model, runtime & REPL (independent review)

From the reviewer's scripts and `cog-lisp.bat` runs. R-1, R-6, R-7, R-8 and R-11
were re-run and reproduced.

### R-1 Errors carry no file, line or position — fixed (batch 2)
- **Evidence.** A program failing on line 6 prints only `error: Message not
  understood: SmallInteger >> #car`; a read error prints `error: unterminated
  list` with no position (and the reader's position is the end of input, not the
  opening paren); errors in a nested `load` don't name the file.
- **Fix.** `evalAll:`/`evalFile:` keep each top-level datum's start; errors are
  reported as `path:line:col: error: message` (`<stdin>` in the REPL); read
  errors point at the opening delimiter. Pin the format in the Phase 5 spec; the
  VS Code problem matcher parses it.

### R-2 Primitives leak raw Smalltalk errors — fixed (batch 2; lists; host-error mapping still planned → conditions & restarts)
- **Evidence.** `(car 5)`, `(car '())` → MNU `#car`; `(length 5)`, `(append '(1)
  5)`, `(map car 5)`, `(apply + 5)` → MNU `#lispElements`; `(+ 1 "a")` →
  `#adaptToNumber:andSend:`; `(/ 1 0)` → `ZeroDivide`; `(procedure-source 5)`.
- **Fix.** Checked accessors (`lispCar`, `lispCdr`, `lispElements` on `Object`
  signalling "car: not a pair: 5"), also used by the inline specs; one send, same
  cost. Arithmetic: rewrite the host error at report time for now. General
  host-error mapping: **plan → conditions & restarts**.

### R-3 Runaway recursion eats all memory and never errors — fixed (batch 2)
- **Evidence.** `(define (f) (+ 1 (f))) (f)`: no output in 90 s; PharoConsole
  reached ~17 GB. Deep finite recursion (`10⁶`) is fine.
- **Verdict.** Fix now (owner, 2026-11-03), in batch 2. The VM accepts
  `--maxOldSpaceSize`, but at the cap it aborts, writes a 75 MB `crash.dmp` and
  hangs (checked: killed by `timeout` after 120 s). So: a memory watchdog in
  the image that signals a LISP error in the running program well below the
  cap, with the cap as the backstop.

### R-4 Cyclic lists hang `list?`, `length`, `equal?` and printing — fixed (equal? and printing in 7.9)
- **Evidence.** After `(set-cdr! (cdr l) l)`, each of those timed out.
- **Fix.** Cycle check (two pointers) in `list?` (R7RS: `#f`) and `length`
  (error). Cycle-safe `equal?` and printing: **plan → self-hosting**.

### R-5 The build saves an image even when a package fails to load — fixed (batch 1)
- **Evidence.** A reader with one broken method printed `LOAD FAILURES: 1` and
  the file-in returned normally; the build would continue and save. Phase 5 §10
  says it refuses. The failure label also prints the method's first line twice.
- **Fix.** Each loader signals an error when it has failures; fix the label.
- **Done.** Checked with a broken method in a copy of `coglisp-core.st`: the
  build prints the failure once, `BUILD FAILED while loading: 'LOAD FAILURES in
  CogLisp-Core: 1'`, exits 1 and saves nothing. An unhandled error in a test
  suite's load chunk prints its stack and exits 1.

### R-6 The REPL drops forms before a read error on the same line — fixed (batch 4)
- **Evidence.** `(display 1) (display 2) )` prints nothing, then `error:
  unexpected )` (re-run).
- **Fix.** Evaluate each datum as soon as it is read; keep only the incomplete
  tail for the next line.

### R-8 `display` writes characters and nested strings — fixed (batch 4)
- **Evidence.** `(display #\a)` → `#\a`; `(display '("a" #\b c))` → `("a" #\b c)`
  (re-run). R7RS: `a`, `(a b c)`.
- **Fix.** A display mode in `LispPrinter`.

### R-9 List primitives mishandle improper lists — fixed (batch 2)
- **Evidence.** `(append '(1) '(2 . 3))` → `(1 2)`; `(append '() 5)` → MNU;
  `(length '(1 . 2))` → 1; `(apply + '(1 . 2))` → 1.
- **Fix.** `append` shares its last argument as the tail; the others use the
  checked proper-list walk of R-2.

### R-10 `(exit x)` does not check its argument — fixed (batch 2)
- **Evidence.** `(exit "x")` → 18, `(exit -1)` → 127, `(exit 300)` → 44,
  `(exit 2.5)` → 0.
- **Fix.** Integers 0–255; `#t` → 0, `#f` → 1 (R7RS); otherwise an error.

### R-11 Fractions print as `(3/2)` — fixed (batch 4: printer; Phase 9 step 9.2: the rest)
- **Evidence.** `(display (/ 6 4))` → `(3/2)` (re-run), which reads back as a list.
- **Fix.** Write `3/2`. Reading rationals, `integer?` on `2.0`, type checks in
  one-argument arithmetic (`(+ 'a)` → `a`): **plan → numeric tower**.
- **Closed in Phase 9 step 9.2a** (2026-11-05): `1/3` and `-6/4` read (as `1/3`
  and `-3/2`), `(integer? 2.0)` is `#t`, and `(+ 'a)` is the error
  `+: not a number: a` (`tests/lisp/phase-9.2-numbers.lisp`).

### R-12 The reader loses the sign of `-0.0`; `eqv?` ignores it — fixed (batch 4)
- **Evidence.** `-0.0` reads with sign bit 0; `(eqv? 0.0 -0.0)` → `#t` (R7RS: `#f`).
- **Fix.** `Float negativeZero` in `parseFloat:`; `eqv:` compares float sign bits.

### R-13 A bad `#\x` escape raises a plain `Error` — fixed (batch 2)
- **Evidence.** `#\xZZ` → `Error: Reading a number failed …`.
- **Fix.** Validate the digits; `LispReadError` "bad character code".

### R-14 A lone `.` reads as a symbol — fixed (batch 2)
- **Evidence.** `.` reads as the symbol `.` (Phase 1 §5, §9: an error).
- **Fix.** "unexpected dot" in `classifyToken:`.

### R-15 `isIncomplete` is set for any error at end of input — fixed (batch 2)
- **Evidence.** `#tru` and `#\spacex` report incomplete. Harmless in today's REPL
  (it adds a newline); not for `read` or a language server.
- **Fix.** Only unterminated list, string, comment, character and quote set it.

### R-16 Reader and compiler errors are not `LispError`s — fixed (batch 2)
- **Evidence.** `LispReadError`, `LispCompileError`, `LispUnboundError` subclass
  `Error` directly; `LispError` is defined in the runtime, which loads last. Error
  reporting (R-1, R-2) cannot tell a LISP error from a host bug.
- **Fix.** Define `LispError` in the reader package; reparent. Full condition
  system: **plan → conditions & restarts**.

### R-17 Re-reading an incomplete REPL form is quadratic — plan → the REPL (owner, 2026-11-05)
- **Evidence.** A 1000-line form piped to the REPL: 1.76 s; 4000 lines: 13.7 s
  (1.05 s as a file).
- **Verdict.** Plan; promote if send-to-REPL sends large forms.
- **2026-11-05.** It stays with the REPL (owner): the Phase 10 language server
  reads whole documents, so it does not need the fix. Fixed when a large form
  sent to the REPL makes it matter.

### R-18 Interop gaps — plan → Smalltalk interop
- **Evidence.** A tail-calling procedure called from Smalltalk with `value:`
  returns a `LispTailCall`; `LispProcedure` has no `value:`; a Smalltalk `Symbol`
  counts as `string?`; `nil` writes as `nil`; the eof object writes as `an Object`.

### R-19 `(gensym 'pre)` fails — fixed (batch 4; prefix; plain printing kept)
- **Evidence.** `(gensym 'pre)` → MNU `LispSymbol >> #,`. Gensyms print like
  interned symbols.
- **Verdict.** Accept a symbol prefix. Keep plain printing (easier to read in
  macro expansions); revisit with hygienic macros.

### R-20 Control characters are written raw — fixed (strings in 7.9)
- **Evidence.** `(Character value: 1)` writes `#\` plus the raw byte (Phase 1 §8:
  re-escaped).
- **Fix.** Write `#\x1`. Strings need a `\x..;` reader escape: **plan →
  self-hosting**.

### R-21 Infinity and NaN print as `Float infinity` / `Float nan` — fixed (Phase 9 step 9.2a)
- **Fix.** They print and read as `+inf.0`, `-inf.0` and `+nan.0`; `nan?`,
  `infinite?` and `finite?` ask about them; a float divided by zero gives
  IEEE's answer (`tests/lisp/phase-9.2-numbers.lisp`).

### R-22 `load` resolves against the current directory; programs can't see arguments — fixed (7.9)
- **Evidence.** `(load "b.lisp")` in `sub\a.lisp` loads `.\b.lisp`;
  `cog-lisp.bat e1.lisp extra` ignores `extra`.

### R-23 `#|` does not end a token — fixed (batch 2)
- **Evidence.** `abc#|c|#def` reads as one symbol (Phase 1 §5 lists `#|` as a
  delimiter).

### R-24 Spec text that predates later phases — fixed (batch 1)
- **Evidence.** Phase 5 §4 names `LispCommandLineHandler` (corrected later in the
  same spec); Phase 4 says I/O goes to `Stdio stdout` (now `LispTextOutput`).
- **Done.** Both specs now say what changed and where.

### R-25 Equal string literals in one form are shared — keep
- **Evidence.** `(let ((a "abc") (b "abc")) (eq? a b))` → `#t`.
- **Verdict.** Keep (R7RS allows it); document beside the read-only-literal note.

**Checked and fine:** number syntax and float round trips; peculiar symbols
(`+`, `...`, `1+`); character names and `#\x41`; booleans, block and line
comments; unterminated-input errors; Unicode source; string escapes; `eqv?` on
bignums and fractions; arity errors and "not applicable"; tail calls through
`apply` at depth 10⁵; runner exit codes, missing files, REPL from `NUL`, REPL
recovery after an error.

## Summary

| Verdict | Findings |
|---|---|
| **Fix now** | H-1 · T-1 · T-2 · D-1 · O-1 · C-1/C-12 · C-2 · C-3 · C-4 (`let`) · C-6 · C-7 · C-8 · C-9 · C-10 · C-11 · C-13 · C-17/R-7 · R-1/R-15 · R-2 (lists) · R-4 (`list?`, `length`) · R-5 · R-6 · R-8 · R-9 · R-10 · R-11 (printer) · R-12 · R-13 · R-14 · R-16 · R-19 (prefix) · R-20 (chars) · R-23 · R-24 · R-3 (watchdog) |
| **Plan → self-hosting** | C-4 (`lambda`) · C-5 · C-18 (dispatch, templates) · R-4 (`equal?`, printer) · R-20 (strings) · R-22 |
| **Plan → Smalltalk interop** | C-16 · R-18 |
| **Plan → conditions & restarts** | C-18 (`qqAppend`) · R-2 (host errors) |
| **Plan → numeric tower** | R-11 (reading) · R-21: both closed in Phase 9 step 9.2 |
| **Plan → hygienic macros** | C-14: closed in Phase 9 step 9.3 |
| **Plan → language server** | C-18 (positions): Phase 10 step 10.5 (specs/16-phase-10-documentation-and-editor.md) · R-17: stays with the REPL (owner, 2026-11-05) |
| **Plan → 7.5 tooling** | T-3 |
| **Keep** | D-2 · C-15 · R-19 (printing) · R-25 |
