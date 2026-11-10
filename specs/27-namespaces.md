# Libraries and namespaces

| | |
|---|---|
| **Status** | Done (2026-11-09). Accepted with the leanings in §9; built as §10 describes |
| **Asked for by** | The owner (2026-11-09), on the console spec (`specs/29-console.md`): names like `rule` are generic and come up in `lisp-expert`; "C# handles this with namespaces. How do we handle it here?" Then: "Let's write the namespaces spec first. I want to do this right." |
| **Before** | `specs/29-console.md`, whose short names (`rule`, `table`, `render`) depend on this |

## 1. The problem, as it is today

- **cog-lisp has one namespace**: every top-level `define`, in every file, in
  every library, binds a name in the image's one global environment
  (`LispEnvironment default`, a table from symbol to cell).
- **The last definition wins, silently.** This has already gone wrong once:
  `lisp-expert`'s own `http-request`, with a different signature, replaced
  cog-lisp's built-in for the whole image, and the built-in `http-get` (which
  calls `http-request`) would have called it. It was found by reading, and
  `lisp-expert`'s procedure was renamed `weather-request`.
- **A library's names are everyone's:** `(require 'cl)` makes `cl`'s `remove`
  (which takes an item) replace the built-in `remove` (which takes a test) for
  every file in the image, not only the file that asked for Common Lisp's.
- **A library cannot have private names**: its helpers are global too, kept
  apart only by a `%` in their names.
- **So a library cannot safely use a common word.** The console library's `rule`,
  `table` or `render` would collide with any program's, and `lisp-expert` uses
  `rule` throughout.

## 2. What C# does, and what Scheme does

- **C#:** a type lives in a namespace (`Spectre.Console.Rule`). A file says
  `using Spectre.Console;` to write `Rule`, or `using SC = Spectre.Console;` to
  write `SC.Rule`, and the full name always works. A `using` affects only its
  own file.
- **R7RS Scheme:** `(define-library (console) (export rule table) (begin ...))`
  declares a library and what it exports; `(import (console))` brings the
  exports in, and `(import (prefix (console) con:))`, `(only ...)`,
  `(except ...)` and `(rename ...)` choose how. An import affects only the
  program or library that makes it. Defining a name that was imported is an
  error.
- **Common Lisp** has packages: symbols are qualified (`console:rule`), a
  package exports some of its symbols, and `use-package` makes them available
  unqualified.

The design takes from all three: libraries that export, imports per file with
a chosen prefix, and the full name always available, as C#'s is.

## 3. What cog-lisp already has to build on

- **A qualified name is already an ordinary symbol**: `console:rule` reads,
  prints and can be defined today (checked 2026-11-09).
- **Every global reference already goes through one place in the compiler**:
  `lc-binding` (`lib/compiler/compiler.lisp`) resolves an identifier through the
  local scope, and otherwise answers a global symbol, which `lc-cell` turns into
  that symbol's cell; macros are found from the same symbol (`lc-global-macro`).
  A table that maps a file's names to other symbols fits there, and compiled code
  is unchanged: it still holds cells.
- **`load` compiles and runs a file form by form**, so a `require` at the top of
  a file runs before the file's later forms are compiled.
- **Sealing exists**: the installed compiler runs on private copies of the cells
  it reads (`LispCompiler class>>sealLispCompiler:`), so a program's `append`
  never changes the compiler. The same can protect the built-in libraries.
- **Hygiene exists**: a `syntax-rules` expansion makes `LispAlias`es that
  remember the scope their macro was defined in.

## 4. The spike, before the design is fixed

1. **The hook:** a table consulted where `lc-binding` falls back to a global
   symbol makes `rule` in one file compile to the cell of `console:rule`, for
   reading, `set!`, `define` and macro calls, and the sealed compiler takes it.
2. **The compilation unit:** `load`, `eval`, the REPL and the language server
   each compile with a current table (a dynamic variable), and a nested `load`
   has its own.
3. **Hygienic macros across files:** a `syntax-rules` macro a library exports,
   whose template uses a helper the library does not export, expands correctly in
   another file. Its aliases must carry the library's table, not only its scope.
4. **Non-hygienic macros across files:** a `define-macro` expansion that names a
   library helper by its full name (`console:%draw`) works in a file that only
   imported the macro.
5. **Brackets:** `[obj at: con:rule put: 1]`. Does the bracket reader take
   `con:rule` as a symbol, or as a keyword part? **Answered (2026-11-09):** as a
   symbol, as the receiver (`[con:x + 1]`), an operand (`[3 + con:x]`) and a
   keyword's argument (`[con:v at: con:x]`). Only `[con:v at:con:x]`, with no
   space after the keyword, is refused ("bad message send"), as it would be
   written by no one.
6. **Sealing the built-in libraries** (`lib/core.lisp`, `format.lisp`,
   `json.lisp`, `http.lisp`, `coverage.lisp`): a program that defines
   `http-request` leaves `http-get` working, and the build still reaches its
   fixpoint.
7. **The libraries we ship** (`cl`, `test`, `datetime`, `pretty`,
   `format-source`): each one's exports, and anything that breaks once its names
   are its own: `cl`'s macros expand into calls of `cl`'s helpers, for example.

## 5. Requirements (subject to the spike)

### 5.1 Declaring a library

- **R-1. A library file starts with `(library name (export name ...))`**
  (decision 1). Its top-level definitions belong to the library: `(define
  (rule ...) ...)` in library `console` defines the cell of `console:rule`. In
  the library's own file, `rule` means it.
- **R-2. A library may export any name it defines,** macros included, and may
  re-export a name it imported. A name it does not export is private: no import
  brings it in.
- **R-3. A library's full names always work** once it is loaded:
  `console:rule` names the cell from any file, with or without an import, as
  `Spectre.Console.Rule` does in C#. That includes private names (decision 6), so
  a non-hygienic macro can expand into a call of a private helper.
- **R-4. The separator is `:`** (decision 5), and a library's name may hold `/`
  for a subfolder (`(library gui/widgets ...)`, so `gui/widgets:button`).

### 5.2 Importing

- **R-5. `require` imports**, as well as loading once:
  - `(require 'console)`: every exported name, unqualified, as today;
  - `(require 'console 'prefix 'con:)`: as `con:rule`, `con:table`;
  - `(require 'console 'only '(render panel))`;
  - `(require 'console 'except '(rule))`;
  - `(require 'console 'rename '((rule hline)))`;
  - options combine, applied in that order.
- **R-6. An import affects only its own file** (decision 4): the program file,
  the library file, or the REPL session that makes it. Two files can import
  `console` with different prefixes, or not at all.
- **R-7. What a name means in a file**, first match wins:
  1. a local binding (`let`, `lambda`, ...);
  2. the file's own library's definitions, when the file is a library;
  3. the file's imports;
  4. the global environment: the built-ins, and the top-level definitions of
     programs, which stay global as today.
- **R-8. Conflicts are errors at the `require` or the `define`**, never
  silent:
  - two imports that bring the same name into one file, from different cells;
  - a file defining a name it imported ("`rule` is imported from `console`:
    choose another name, or import `console` with a prefix").

### 5.3 Protecting what is built in

- **R-9. The built-in libraries are sealed** as the compiler is (decision 7):
  their own calls never reach a program's redefinition, so a program's
  `http-request` cannot break `http-get`.
- **R-10. Redefining a built-in name from a program is a warning** on stderr,
  naming the file, the line and the name: "warning: main.lisp:3: define
  replaces the built-in http-request". It still takes effect for the program,
  as today.
- **R-11. A program can also leave a built-in alone** and define its own under
  the same name for its own file only: decision 8.

### 5.4 Everything that reads names

- **R-12. The REPL** keeps a session table: `(require 'console 'prefix 'con:)`
  at the prompt works there, and `(imports)` lists what the session imported.
- **R-13. The language server** applies a document's imports: hover, completion
  (offering `con:rule` after `con:`), go to definition (into the library's
  file), and diagnostics for R-8's conflicts.
- **R-14. `documentation`** answers for a full name (`(documentation
  'console:rule)`) and for an imported one. The generated reference keeps listing
  the built-ins; each shipped library gets a section of its exports.
- **R-15. Coverage, the formatter and macro expansion** keep working on
  library files (their tests run over them).

### 5.5 Moving to it

- **R-16. Every library cog-lisp ships becomes a library** with an export list:
  `cl`, `test`, `datetime`, `pretty` and `format-source`. `(require 'cl)` still
  brings every name in, so existing programs run unchanged, and
  `lisp-expert`'s suites pass unchanged. But `cl`'s `remove` now replaces the
  built-in `remove` only in files that require `cl` (R-6, R-7).
- **R-17. The self-hosting rule holds:** the compiler's own source, and the
  built-in libraries the seed compiles, use only what the pinned seed supports.
  They are not libraries in the new sense until a seed has this (they stay
  global, and sealed: R-9). The libraries `require`d at run time can be
  libraries at once, since the new compiler compiles them.
- **R-18. A program is not a library:** `load` and running a file work as today,
  and its top-level definitions stay global.
- **R-19. Examples show every scenario** (the owner, on accepting this spec):
  one library imported plainly; two that export the same name, through a
  prefix; `only`, `except` and `rename`; private names, private state and the
  macros that reach them; libraries that use other libraries; and the
  conflicts and their errors. They form a chapter of the manual.

## 6. Acceptance criteria

- **AC-1:** the spike's answers are recorded in §4, and the design is fixed from
  them.
- **AC-2:** `tests/lisp/namespaces*.lisp`:
  - two libraries that each define and export `rule` are used in one file
    through two prefixes, and a third file defines its own `rule`: all three are
    right;
  - `only`, `except`, `rename` and their combination;
  - a private name no import can reach, and its full name that can;
  - an exported `syntax-rules` macro whose template uses a private helper, and a
    `define-macro` that names one in full;
  - R-8's conflicts are errors with their messages;
  - an import in one file is not seen by the file that loaded it.
- **AC-3:** a program that defines `http-request` gets R-10's warning, and
  `http-get` still works (R-9).
- **AC-4:** the REPL's session imports, and the language server's hover,
  completion and definition through a prefix, are checked by their suites.
- **AC-5:** every shipped library has an export list (a suite compares it with
  the library's documented public names); every example and suite passes
  unchanged; `lisp-expert`'s suites pass unchanged.
- **AC-6:** every suite passes on Windows and Linux, and the build reaches its
  fixpoint.

## 7. What it costs at run time

Nothing: names are resolved when code is compiled, and compiled code holds cells
as it does today. A file's table exists only while the file is being compiled.
The REPL's lasts for its session.

## 8. Risks

- **The compiler changes**, and its errors hide its own bugs
  (CLAUDE.md, "The LISP compiler's errors hide its own bugs"). The spike
  exercises the hook on the compiler's own source before the build depends on
  it.
- **Macros are where module systems go wrong.** The spike's items 3 and 4 come
  first for that reason, and R-3 (full names reach private helpers) is the
  escape hatch for non-hygienic macros.
- **Sealing more code** could change the bootstrap. The fixpoint check (AC-6)
  is the guard.

## 9. Decisions for the owner

1. **How a library is declared:** a header at the top of the file,
   `(library console (export rule table ...))`, followed by ordinary
   definitions; or R7RS's `define-library`, with the whole library inside it.
   Leaning: the header, in cog-lisp's style; R7RS's form can come later, for
   portable code, translated to the same thing.
2. **How imports are written:** options to `require` (R-5); or R7RS's
   `(import (prefix (console) con:))` beside it. Leaning: `require`'s options
   now; `import` later, with decision 1's R7RS form.
3. **The default import is unqualified,** as `require` is today, so existing
   programs keep working. Leaning: yes.
4. **Imports are per file,** as C#'s `using` and R7RS's `import` are, not for
   the whole image. Leaning: per file. This is the decision the rest rests on.
5. **The separator is `:`** (`console:rule`), as in Common Lisp; `/` (as in
   Clojure) would collide with names like `call/cc` and
   `hash-table-ref/default`. Leaning: `:`; the spike's item 5 found that
   brackets read it well.
6. **A full name reaches private names too** (R-3), so non-hygienic macros can
   use private helpers, as Common Lisp's `pkg::name` does; or only exported
   names, with a separate reflective procedure for the rest. Leaning: full
   names reach every name; privacy is about what imports bring in.
7. **Seal the built-in libraries** (R-9). Leaning: yes; it closes the
   `http-request` hole for good.
8. **A program's `define` of a built-in name:** global, with a warning (R-10),
   as today; or local to the program's file, leaving the built-in for everyone
   else. Leaning: global with a warning now. File-local definitions for programs
   would mean programs are libraries too, a larger change for later.

All eight were accepted as leaned (2026-11-09).

## 10. As built (2026-11-09)

**The pieces:**

- **A unit per file.** `LispUnit` (`src/coglisp-compiler.st`) holds a file's
  path, its library (name, exports, owned names), its imports, and where in
  the file the compiler is. `LispCurrentUnit`, a dynamic variable, holds the one
  being compiled. `evalFile:` binds a new unit; the REPL has one for its session.
- **The hook.** `lc-resolve-global` (`lib/compiler/compiler.lisp`), called by
  `lc-binding` for every symbol that is not local, answers the global symbol a
  name means. `lc-define-target` does the same for a top-level `define`.
- **A library's definitions are ordinary global cells under their full names**
  (`alpha:rule`). That is why a full name works from anywhere, and private names
  too (R-3).
- **Hygiene across files.** `define-syntax` stamps its compile-time scope with
  its unit, so a `syntax-rules` expansion resolves its template's names in the
  macro's library (spike item 3). A `define-macro` expansion is compiled in the
  user's file, so it names its library's helpers in full (item 4; `cl`'s macros
  do: `cl:setq`, `cl:progn`).
- **`library`** is a `syntax-rules` macro in `lib/core.lisp` over `%library`,
  which reads the rest of the file for the names the library defines
  (`define`, `define-macro`, `define-syntax`, also inside `begin`) before any of
  them is compiled.
- **`require`** takes a symbol (found on the library path) or a path string, and
  `only`, `except`, `rename` and `prefix`. `(imports)` answers the current
  unit's imports as an alist sorted by name.
- **Sealing (R-9).** The built-in libraries' code reads private copies of the
  cells holding procedures and macros (`sealLibraries:frozen:`); cells holding
  data stay shared, so state such as `*env*` is not frozen.
- **The built-ins** are recorded at the end of the build (`LispUnit
  recordBuiltins`), and R-10's warning compares against them.
- **The language server** keeps a unit per document (`lsp-document-units`), and
  resolves hover, completion and definition through it. A unit's warnings are
  collected there instead of being written to stderr, and shown as warning
  diagnostics (severity 2), except in cog-lisp's own `lib/` sources.

**Where it differs from §5:**

- **Imports come before a library's own names** (R-7's steps 2 and 3 swapped).
  Either order makes the conflict an error: a library cannot define a name it
  imported, nor import one it defines. Checking imports first keeps a prefixed
  import (`b:rule`) from being taken for a full name.
- **A program file loaded by another starts with its loader's imports;** a
  library starts with none (R-6 holds for libraries: what a library imports
  stays in its file). A program split across files reads as one program.
- **An import serves the forms compiled after its `require`.** A `require`
  inside a procedure's body is too late for that body, which was compiled
  first; reach those names through `eval`, or require at the top of the file.
- **Imports are all or nothing:** a `require` refused for a conflict imports
  none of its names.
- **`library` is accepted only as the first form of a file being loaded;**
  anywhere else it is an error, so a stray one cannot turn a program into a
  library halfway through.
- **R-17:** the libraries the seed compiles (`core`, `format`, `json`, `http`,
  `coverage`, the compiler) stay global and sealed, as planned.

**Examples (R-19):** `examples/namespaces/`, `namespaces-prefix/`,
`namespaces-choose/`, `namespaces-private/`, `namespaces-files/` and
`namespaces-conflicts/`, the manual's chapter 7, "Libraries and namespaces".

**Tests:** `tests/lisp/namespaces.lisp` (AC-2, AC-3, with fixtures in
`tests/lisp/namespaces/`), `tests/runner/repl-imports.*` and
`vscode/test/lsp.test.js` (AC-4).
