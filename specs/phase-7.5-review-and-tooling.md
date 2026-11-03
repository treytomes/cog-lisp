# Spec — Phase 7.5: Review & Tooling

| | |
|---|---|
| **Phase** | 7.5 |
| **Status** | Implemented (2026-11-03) — review fixed (all suites 627/627); extension built, installed, and checked in VS Code by the owner (AC-8 to AC-10) |
| **Depends on** | Phases 1–7 |
| **Feeds** | Phase 8 (self-hosting), Smalltalk interop, every later phase |
| **Kind** | Consolidation: no new language features |

## 1. Goal

Before self-hosting raises the cost of changing anything, stop and do two things:

1. **Review Phases 1–7** with what we know now. Find what we would do differently
   and fix it, plan it, or record why we keep it.
2. **Bring cog-lisp into VS Code**, so writing it and working through *ANSI
   Common Lisp* happen in the editor, not in a terminal.

The phase is "half" because it adds no language features. The language in
Phases 1–7 is the language that comes out of it.

## 2. Scope

**In scope**
- A written review of specs, code, tests, build, and the Pharo findings in
  `CLAUDE.md`. It produces a findings document, `specs/review-phases-1-7.md`.
- Fixes for the findings classified *fix now* (§4.3), each with a regression check.
- A VS Code extension in `vscode/`, installed locally from a `.vsix` (§5).
- A plan, in this spec, for an image-backed language server, built in a later
  phase (§5.4).

**Deferred**
- New language features, including anything a finding *plans* rather than fixes.
  Those go into the phase they belong to: interop, numeric tower, conditions,
  hygienic macros, self-hosting.
- Publishing the extension to the Marketplace.
- A debugger (stepping through LISP). Planned with the language server.

## 3. Decisions

- **Review first, then the extension.** The extension's REPL and run commands sit
  on `cog-lisp.bat` and the error output, which the review may change.
- **Every finding gets a verdict.** *Fix now*, *plan* (named target phase), or
  *keep* (with the reason). Nothing is left as just "noted".
- **Fixes keep every existing acceptance check passing**, unless the fix changes
  documented behavior. Then the spec changes first (spec-driven rule 5), and the
  commit says so.
- **The extension is thin.** Highlighting, brackets, comments, and commands that
  call `cog-lisp.bat`. No LISP knowledge in TypeScript beyond the grammar. The
  intelligence comes later from the image (§5.4), in keeping with "the image is
  the world".
- **Lean on VS Code too.** Use declarative contributions (TextMate grammar,
  language configuration, tasks, terminal profile) wherever they suffice. Write
  code only for the commands that need it.

## 4. The review

### 4.1 Areas

Each area is reviewed against its spec and against what later phases learned.

| Area | Look at |
|---|---|
| Reader & printer | Error positions and messages; Unicode; the printer for `#<...>` values |
| Data model | `LispSymbol` interning and uninterned gensyms; `LispUnspecified`; `equal?` on cycles |
| Compiler | Structure of `coglisp-compiler.st` (now large); load-order coupling to the runtime (`Smalltalk at:`, `respondsTo:`); frame-size and temp budgets; source-map reliance on cons identity; special forms a local binding cannot shadow |
| Runtime | Errors that surface as Smalltalk errors (`car` of a non-pair, DNU); arity errors; `LispTailCall` escape paths |
| REPL & runner | Error output format (file, line, form); exit codes; stdin polling cost |
| Optimization | The `globals` gap (65–80× Smalltalk); the 0–4 argument cut-off; option switches nobody turns off |
| Macros | Expansion-time errors and their positions; `macroexpand` at depth; source context of nested expansions |
| Tests & build | The `check`/`checkErr` blocks copied into every suite; build time; one command to run everything |
| Repo hygiene | Line endings: commits warn "LF will be replaced by CRLF" on `.md` and `.st` files that `.gitattributes` does not cover |
| Docs | Specs whose text predates later phases (e.g. "deferred" items now done); `CLAUDE.md` accuracy |

The table lists candidates found so far, not conclusions. Each is checked
against the code before it becomes a finding.

### 4.2 Method

- Read each area fresh, with the spec beside the code, and try to break it with
  the headless harness. A finding is backed by a failing or measured check, not
  by a reading alone.
- Where a fresh read helps, an independent review (a separate reviewer given the
  code, not our conclusions) covers the compiler and the runtime.

### 4.3 The findings document

`specs/review-phases-1-7.md` lists every finding with an id (R-1, R-2, …), the
area, the evidence (a check or measurement), the verdict (*fix now* / *plan →
phase* / *keep*), and, once fixed, the commit. It is reviewed with the owner
before the *fix now* list is implemented.

## 5. VS Code integration

### 5.1 Language support (declarative)

- Language id `cog-lisp`, for `.lisp` files in this workspace. CL's `.lisp`
  convention clashes here; see §7 Q3.
- TextMate grammar: comments, strings, characters, numbers, `#t`/`#f`, quote and
  quasiquote marks, special forms, and the core and CL macro names.
- Language configuration: `;` line comments, bracket pairs and auto-closing for
  `()` and `""`, and word pattern for LISP identifiers (`set!`, `->`, `*limit*`).

### 5.2 Running code

- **Run file:** runs the active file with `cog-lisp.bat`; output to a terminal.
- **REPL:** opens the cog-lisp REPL in the integrated terminal (a terminal
  profile). One per window, reused.
- **Send selection / top-level form to REPL:** sends the selection, or the form
  around the cursor, to that terminal.
- Errors from the runner that name a file and line become problems (a problem
  matcher), so they are clickable. Depends on the review's error-format finding.

### 5.3 Packaging

- `vscode/` holds the extension. It is built with `npm` and `@vscode/vsce` into
  `cog-lisp-<version>.vsix` and installed with `code --install-extension`. No
  Marketplace, no admin rights (corporate constraints).

### 5.4 Planned: an image-backed language server (later phase)

The north star is a living image, so the editor should talk to the image, not
re-derive the language in TypeScript. The plan, specified when built:

- cog-lisp serves the Language Server Protocol itself: a `cog-lisp lsp` command in
  the image, speaking JSON-RPC over stdio (the stdin/stdout machinery of Phase 5).
- **Hover** shows a global's value and, for a procedure, `procedure-source`.
- **Completion** from the global environment and macro names.
- **Go to definition** for globals defined in workspace files.
- **Diagnostics** from compiling the file: reader and compile errors with
  positions.
- **Macro expansion view:** expand the form at the cursor.
- Later: a debugger (Debug Adapter Protocol) on Pharo's contexts.

It reads requests from a pipe, which `LispStdin` already handles, and needs
JSON, which Pharo has (STON/NeoJSON).

## 6. Acceptance criteria

*Review*
- AC-1 `specs/review-phases-1-7.md` exists and covers every area in §4.1, each
  with at least one finding or a "no findings" note with what was checked.
- AC-2 Every finding has evidence and a verdict; every *plan* names a phase.
- AC-3 Every *fix now* finding is fixed, with a regression check in a suite.
- AC-4 All acceptance suites, the runner suite, and the benchmarks pass after
  the fixes; specs changed by a fix say so.
- AC-5 One command (`tests\run-all.bat`) runs every suite and prints a total.

*VS Code*
- AC-6 `vscode\` builds a `.vsix`; `code --install-extension` installs it.
- AC-7 A `.lisp` file opens as `cog-lisp`; the grammar scopes a fixture file
  correctly (checked with a grammar test: `vscode-tmgrammar-test` snapshots).
- AC-8 Run file runs `examples\hello.lisp` and shows its output.
- AC-9 The REPL command opens a terminal running the REPL; send-form evaluates
  the form at the cursor there.
- AC-10 A runner error that names a file and line appears in Problems.
- AC-11 The language-server plan (§5.4) is reviewed and accepted, ready to be
  numbered as a phase.

AC-8 to AC-10 need the editor; they are checked by hand, with the steps in
`vscode/README.md`. AC-6 and AC-7 run headless.

## 7. Resolved decisions

Settled 2026-11-03 (owner sign-off); the spec is Accepted on these.

1. **Name:** Phase 7.5 — Review & tooling.
2. **Order:** the review first, then the extension.
3. **File extension:** `.lisp`, associated with cog-lisp in this workspace only
   (`.vscode/settings.json`).
4. **Independent review:** separate reviewer agents read the compiler and the
   runtime, given the code and specs but not our candidate list.
5. **Language server:** planned only (§5.4), built in a later phase. The
   extension stays thin in 7.5.

## 8. As implemented

**Review (AC-1 to AC-5).** `specs/review-phases-1-7.md` has 61 findings across
every area of §4.1 (7 from our own pass, 54 from the two independent
reviewers, each re-run before being recorded). Every *fix now* finding was fixed
in four commits; each has regression checks in `tests/phase-7.5-review.st` (114
checks) or a runner fixture (`tests/runner/located.*`). The rest are planned for
named phases or kept, with reasons. `tests\run-all.bat` runs every suite: 624/624.
Specs changed by a fix say so (Phases 1, 4, 5, 6, 7). The root scripts also have
bash equivalents (`bootstrap-pharo.sh`, `build-image.sh`, `cog-lisp.sh`).

**VS Code (AC-6 to AC-10).** `vscode/` is a plain-JavaScript extension (no build
step). `npm test` runs 15 form-scanner checks and the grammar assertions of
`test/syntax.test.lisp`; `npm run package` builds `cog-lisp.vsix`, which
`code --install-extension` installed (AC-6, AC-7). Details settled in building it:

- **The editor runs the repo's own scripts.** Run File is a task, and the REPL a
  terminal, both `cmd.exe /d /c .\cog-lisp.bat …` from the repo root; Rebuild
  Image runs `.\build-image.bat`. The script is named `.\x.bat`: on this machine
  `cmd` does not run a batch file in the current directory by its bare name, and
  a relative path keeps quotes (which `cmd /c` mangles) off the command line.
- **The problem matcher** reads `path:line:col: error: message` (review R-1),
  with absolute paths.
- **Send to REPL** sends the selection, or the top-level form at the cursor,
  found by a small scanner (`src/forms.js`) that knows the reader's rules for
  strings, comments, block comments and character literals.
- **Stale image (review T-3):** on activation, and on saving `src\*.st` or
  `lib\core.lisp`, the extension warns when the image is older than a source and
  offers to rebuild.
- **Grammar test:** `vscode-tmgrammar-test` ends every run on Node 24 for
  Windows with a libuv assertion (exit 127, pass or fail), so
  `test/grammar.test.js` runs it and judges by its output; a planted wrong
  assertion is reported as a failure.
- **Checked in the editor (AC-8 to AC-10)** by the owner, with the steps in
  `vscode/README.md`. That check found one bug: when a program's output did not
  end its line, the error report continued it in the terminal and the matcher
  took the output as part of the path. The runner now starts the report on a new
  line, and the matcher anchors on the path's drive letter
  (`vscode/test/matcher.test.js`, `tests/runner/midline.*`).
- **AC-11:** the language-server plan (§5.4) is accepted, to be numbered and
  specified as a later phase.
