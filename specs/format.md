# `format`: finishing `lisp-expert`'s, as a built-in

| | |
|---|---|
| **Status** | Accepted (2026-11-09): base it on `lisp-expert`'s `format.lisp` and finish it (owner) |
| **Found by** | Reviewing `~/projects/lisp-expert` (2026-11-09); and Phase 10.7's skill, whose evaluation saw models reach for `format` |

## 1. Where it stands

- **cog-lisp has no `format`.**
  - The agent skill teaches it as a trap: `unbound variable: format`.
  - Text is built with `string-append` and `number->string`.
- **`lisp-expert`'s `format.lisp`** (266 lines, three test suites, 81 checks)
  was begun with Claude on the web, and is the owner's. Read 2026-11-09:
  - **Done:**
    - the parser, which reads literal text, each directive's parameters
      (numbers, `'c` characters, empty ones after commas) and the `@` and `:`
      flags;
    - the destination (`#f`, `#t`, a port);
    - the directives `~A ~S ~D ~B ~O ~X ~C ~% ~~`, in their plain forms.
  - **Not done:**
    - Output ignores every parameter and flag. `format-write-argument`
      dispatches on the directive's character alone, so `~10D`, `~:D`,
      `~@A` and `~5%` print as if plain.
    - None of the directives with structure exists.

## 2. Requirements

- **R-1. Both conventions, told apart by the first argument:**
  - `(format destination control arg ...)`, as in Common Lisp. The destination
    is `#f` (answer a string), `#t` (the current output port) or a port.
  - `(format control arg ...)`, as SRFI 28: the first argument is a string, and
    the answer is a string.
  - Guile and Chicken accept both the same way.
- **R-2. Finish what is parsed:** every parameter and flag of the existing
  directives takes effect, with Common Lisp's meanings and defaults:

  | Directive | Parameters and flags |
  |---|---|
  | `~mincol,colinc,minpad,padcharA` and `~S` | pad to `mincol` on the right; `@` pads on the left |
  | `~mincol,padchar,commachar,comma-intervalD` (and `~B ~O ~X`) | pad; `:` groups digits with commas; `@` always shows the sign |
  | `~nR` | `~D` in base `n`, with the same parameters (`~R` without a base is R-4) |
  | `~n%`, `~n~` | `n` newlines, `n` tildes |
  | `~C` | `@` writes it as `#\c`, as `write` does |

- **R-3. The directives with structure, which make `format` worth having:**

  | Directive | Does |
  |---|---|
  | `~{ ... ~}` | iterate over a list argument; `~:{` over sublists, `~@{` over the remaining arguments; `~^` leaves early |
  | `~[ ... ~; ... ~]` | choose by an integer; `~:[` by false or true; `~@[` when true, without consuming it |
  | `~( ... ~)` | case: lower; `~:(` capitalize words; `~@(` the first word; `~:@(` upper |
  | `~P` | plural `s`; `~:P` reuses the previous argument; `~@P` gives `y`/`ies` |
  | `~*` | skip an argument; `~:*` back up one; `~n@*` go to argument `n` |
  | `~w,dF` | a float with `d` digits after the point, padded to width `w` |
  | `~?` | a control string and its arguments, from the arguments |
  | `~&` | a newline, unless at the start of a line (the port tracks its column) |

  - The parser gains nesting: a directive's segments become a tree.
  - An unknown directive, unbalanced brackets, or too few arguments is an
    error naming the control string and the position.
- **R-4. Later, one at a time when a program needs one** (not this step):
  - `~R` in English words;
  - `~$` money;
  - `~T` tabulation;
  - `~< ~>` justification;
  - `~E` and `~G`.
- **R-5. Where it lives:** `lib/format.lisp`, a file of its own that the build
  loads after `lib/core.lisp`, so `format` is a built-in in every image.
  - The seed compiles it, so the code uses only what the seed supports.
  - `lisp-expert`'s version starts with `(load "lib/cl.lisp")`. Whatever it uses
    from there is rewritten in plain cog-lisp.
- **R-6. Documented and taught:**
  - `format` is in the reference, its documentation lists the directives, and
    an example joins the text chapter of the manual.
  - In the skill, the `format` trap becomes a positive example. Then the
    evaluation of 10.7 is run again (Ministral 3 8B, on `rojo`), to see whether
    models do better.

## 3. Acceptance criteria

- **AC-1:** both conventions, every directive, parameter and flag of R-2 and
  R-3, and each error of R-3, checked by a LISP test. Where Common Lisp
  specifies the output, the expected output is Common Lisp's.
- **AC-2:** `lisp-expert`'s three format suites (81 checks) pass against
  cog-lisp's `format`, with its own `format.lisp` not loaded.
- **AC-3:** the skill's suite passes with the trap replaced, and the
  evaluation's results are recorded in the Phase 10 spec.

## 4. Decisions

1. **`lisp-expert`'s `format.lisp` is the starting point** (owner, 2026-11-09),
   under cog-lisp's MIT license: it is the owner's own code, and its tests come
   with it.
2. **A file of its own**, `lib/format.lisp`, loaded by the build (proposed),
   keeping `core.lisp` to the derived forms and setters.
3. **When it lands, `lisp-expert` drops its copy.** Its suites then run against
   the built-in, as AC-2 does.
