# Common Lisp issues: #1, #2, #3, #4 and #6

| | |
|---|---|
| **Status** | Done (2026-11-09); accepted by the owner: "document #1's current functionality, then defer it for now. Complete #6, #2, #3, and #4" |
| **Issues** | [#1](https://github.com/treytomes/cog-lisp/issues/1), [#2](https://github.com/treytomes/cog-lisp/issues/2), [#3](https://github.com/treytomes/cog-lisp/issues/3), [#4](https://github.com/treytomes/cog-lisp/issues/4), [#6](https://github.com/treytomes/cog-lisp/issues/6) |
| **Checked against** | v0.3.0 (2026-11-09) |

## 1. What v0.3.0 does

| Issue | Today |
|---|---|
| #6 `boundp` | Done (specs/lisp-expert-libraries.md): `(require 'cl)` gives `(boundp symbol)`, documented. |
| #2 `format` | Built in (specs/format.md); `(format t "~A plus ~A equals ~A.~%" 2 3 5)` works. With `cl` loaded, `(format nil ...)` fails ("write-string: not an output port: ()"): `cl`'s `nil` is `()`, and `format` takes only `#f` for "answer a string". |
| #3 `defparameter` | Answers `#<unspecified>`, as do `defvar`, `defun` and `defmacro`; Common Lisp's answer the name. |
| #4 `defconstant` | Missing. |
| #1 `nil` | `cl` binds `nil` to `()`, which is true: `(if nil 'yes 'no)` is `yes`. |

## 2. Requirements

- **R-1 (#2).** `format` takes `()` as a destination the way it takes `#f`:
  it answers a string. So `(format nil ...)` works with `cl` loaded, as in
  Common Lisp. Its documentation says so.
- **R-2 (#3).** `defun`, `defmacro`, `defvar` and `defparameter` answer the
  name they define, as a symbol: `(defparameter *glob* 99)` prints `*glob*` at
  the REPL.
- **R-3 (#4).** `(defconstant name value)` defines name and answers it.
  - **Not enforced:** a later `define`, `set!` or `defconstant` of the name is
    not refused. Refusing it needs the compiler's help, and the issue's own
    comment notes that `define` covers the use. The header of `lib/cl.lisp`
    lists this among the known gaps.
- **R-4 (#1, documented, then deferred).** `nil` stays `()`. The
  documentation says plainly what follows:
  - **why:** Common Lisp's `nil` is both the empty list and false, and in
    cog-lisp those are two values (`()` and `#f`). Binding `nil` to `#f` would
    make `(cons 1 nil)` an improper list;
  - **the consequence:** `nil` is true, so `(if nil ...)` takes its first
    branch, and so does `(if (member x lst) ...)` when it answers `()`;
  - **what to write instead:** `(null x)` or `(consp x)` for a list; `#f`, or
    a predicate, for false.

  It is said in the header of `lib/cl.lisp`, the opening of
  `examples/cl-style.lisp` (and so the manual's chapter), and the agent
  skill: its trap "The empty list counts as true" now names `nil` too (a trap
  of its own would have to `(require 'cl)`, which leaks into the traps after
  it, since they run in one image). The issue stays open, deferred.

## 3. Acceptance criteria

- **AC-1:** `tests/lisp/cl-issues.lisp` checks R-1 to R-3, each against the
  issue's own example, and that `nil` is `()` and true (R-4).
- **AC-2:** the skill's trap for R-4 runs (the 10.7 suite), `SKILL.md` stays
  under 10 KB, and the generated files are current.
- **AC-3:** every suite passes on Windows and Linux.

## 4. As built (2026-11-09)

- `lib/format.lisp`: `()` is a destination like `#f`.
- `lib/cl.lisp`: `defun`, `defmacro`, `defvar` and `defparameter` expand to
  `(begin (define ...) 'name)`; `defconstant` is new, the same, not enforced;
  the header explains `nil` (#1) and lists `defconstant` among the gaps.
- `tests/lisp/cl-issues.lisp`: 23 checks. `tests/lisp/cl.lisp`'s three
  macroexpansion checks expect the new expansions.
- `examples/cl-style.lisp`'s opening explains `nil`; its output is unchanged.
- The skill: `SKILL.md` is 9,740 bytes.
