# Phase 10 — Knowing the language: documentation, the manual, the editor

| | |
|---|---|
| **Status** | Done (2026-11-06). Accepted 2026-11-05, with the owner's decisions (§7); decision 4 accepted with 10.5's detailed spec |
| **Depends on** | Phase 9 (the language it documents) |
| **Feeds** | Phase 11 (the pure image; its LISP-visible tools join the reference) |
| **Review items** | C-18 (compile errors carry no position); R-17 considered and left with the REPL (§7) |

## 1. Goal

Make cog-lisp knowable, by a person reading and by the editor, from one source
of truth kept in the image:

- every built-in documented where it is defined;
- a reference of the built-ins, generated from that documentation;
- hover help in VS Code;
- a user manual built from the examples, whose code and output the suites
  already check;
- a language server served by the image itself, if the spike says it can be.

These were the README's "Later" sections (owner ideas, 2026-11-04). The owner
moved them ahead of the pure image (now Phase 11) on 2026-11-05.

## 2. Where we start (measured 2026-11-05)

- **The image has 643 bound globals:**

  | Kind | All | Public |
  |---|---:|---:|
  | primitives | 253 | 249 |
  | LISP procedures | 321 | about 21 |
  | `syntax-rules` forms | 14 | 14 |
  | `define-macro` macros | 29 | 0 |
  | other values | 26 | 3 |

  - The non-public LISP procedures are the compiler's internals (`lc-`, `rd-`,
    `cg-`, `sr-`, ...).
  - The `define-macro` macros are the code generator's accessors.
  - There are 16 special forms besides.
  - So the public surface is about 300 names. None has documentation: there is
    nowhere to keep it.
- **Procedures keep their source** (`procedure-source`). Primitives have none.
  A primitive knows its arity, but not its parameter names.
- **Examples:** 36, every one with an `.expected` file the runner suite checks,
  and every one opening with a comment that explains it.
- **JSON:** Pharo has `STONJSON` (`toString:`, `fromString:`). NeoJSON is not
  in the image.
- **stdin is read a line at a time** (`LispStdin`). An LSP message is
  `Content-Length: n`, a blank line, then n bytes of JSON with **no newline
  after it**, so a line reader would wait for the next message before it saw
  this one. A server needs to read exact byte counts: on a Windows pipe and a
  Linux pipe alike.
- **The VS Code extension** is plain JavaScript (`vscode/src/`, 302 lines) with
  no runtime dependencies. It has a grammar, run and REPL commands, and a
  problem matcher for `path:line:col: error:`.
- **Compile errors carry no position** (review C-18). A runtime error raised
  while a file loads is located at its top-level form (`LispLocatedError`).

## 3. Principles

- **One source of truth.** Documentation lives with each definition, in the
  image. Everything else is generated from it, with a check that the generated
  copy matches:
  - the reference;
  - the editor's offline data;
  - the manual's code and output.

  A built-in without documentation fails a test.
- **The examples stay the manual's backbone.** A chapter's code is an example,
  and its output is the example's `.expected`, already verified.
- **The editor asks the image** where it can (the language server), and reads
  generated data where it cannot (offline hover). Nothing about the language is
  re-derived in JavaScript.
- **The self-hosting rule holds.** The seed compiles `lib/core.lisp` and
  `lib/compiler/`, so documentation forms there may use only what the pinned
  seed understands (9.1).
- **Every step lands green**, with tests and an example, one commit per step, and
  a status line below.

## 4. Steps

### 10.1 Documentation in the image
Two parts, around a release: the self-hosting rule (9.1) means `lib/core.lisp`
can use a new `define-syntax` argument only once a seed has it. The owner chose
the cleaner form and the release it needs over a stopgap call (2026-11-05).

**10.1a: the machinery, and everything the seed's compiler does not compile.**
- **Where documentation is kept.** A procedure, a macro and a special form each
  carry a documentation string. `(documentation 'name)` answers the
  documentation of what `name` is bound to: a global or a special form.
  `(procedure-documentation f)` answers a procedure's.
- **How it is written:**
  - *A primitive* gets its documentation where it is installed, beside its block
    (`src/coglisp-runtime.st`).
  - *A `define`* (and a `define-macro`) whose body is a string followed by at
    least one more form keeps that string as its documentation, as Common Lisp
    does. The string is still evaluated, so the R7RS meaning is unchanged.
  - *A `define-syntax`* takes an optional string before its transformer:
    `(define-syntax when "(when test body ...)\n..." (syntax-rules ...))`, at
    top level and in a body. `let-syntax` bindings take none.
  - *A special form* is documented where the compiler defines it:
    `(define-special-form 'if "(if test then [else])\n..." translator)`. This is
    a procedure call, which the seed compiles, so `lib/compiler/` can use it at
    once.
- **Its shape.** The first line is the call form, with parameter names:
  `(string-ref string k)`. The rest says what it does, in a sentence or two. A
  primitive's parameter names come from this first line; a LISP procedure's from
  its source.
- **The category** is the section of the reference an entry appears in:
  - for a primitive, the installer that defines it (`installStringsInto:` gives
    Strings);
  - for a special form, Special forms;
  - for a definition in LISP, the file it was loaded from (`lib/core.lisp` gives
    Derived forms, `lib/compiler/` gives The compiler and reader), which the
    compiler records as it does the source text.
- **Public, by rule.** The public names are:
  - the primitives;
  - the special forms;
  - the forms of `lib/core.lisp`;
  - any LISP procedure that has documentation (the compiler's entry points, such
    as `compile-form` and `define-special-form`, get some).

  A test fails if a primitive or a special form has none.
- **Example** `examples/documentation.lisp`: documenting a procedure and a macro,
  and reading a built-in's documentation back.

As built:
- A primitive's documentation is a table at the end of the installer that
  defines it: `self document: anEnv category: 'Strings' with: #(name call
  description ...)`. A name in a table that is not bound is an error, so a table
  cannot drift from what it documents.
- `display`, `write` and `newline` are documented by the ports installer, which
  gives them their final, port-taking definitions.
- An old name (`hash-table-exists?`, `hash-table-size`) is a copy of the
  procedure, so it has documentation of its own.
- Names that start with `%` (`%guard` and the other machinery behind `guard`
  and `restart-case`) are not public.
- The compiler records a definition's category from the file being loaded; the
  bootstrap's stages compile each source file as if loading it, so the
  compiler's own procedures get theirs.
- `(special-form-names)` lists the special forms.

**Then the owner tags a minor release, v0.2.0, and the seed moves to it**, as it
moved to v0.1.3.

**10.1b: the derived forms.**
- `lib/core.lisp`'s forms are documented with `define-syntax`'s string.
- The completeness test covers them too.

### 10.2 The reference of the built-ins
- **`docs/builtins.md`, generated** by a cog-lisp program (`tools/builtins.lisp`)
  from the image's documentation:
  - grouped by category;
  - each entry its call form, its description, and whether it is a procedure, a
    macro or a special form.
- **Checked**: a suite regenerates it and compares the result with the
  committed file, as the bytecode corpus is checked. `COGLISP_REGENERATE=1`
  writes the new one.
- **Linked** from the README, and shipped in the release bundles under `docs/`.

### 10.3 Hover help, offline
- **`vscode/builtins.json`, generated** from the image beside the reference: each
  public name with its call form, description and kind. It is checked against
  the image like the reference.
- **The extension shows it on hover**, and offers the names for completion,
  with no image running. It reads the JSON packaged in the `.vsix`.
- **The editor's tests**: hover over a built-in in a fixture file shows its call
  form.

### 10.4 The user manual
- **`docs/manual/`, generated** by `tools/manual.lisp` from:
  - an ordered list of chapters (`docs/manual/chapters.lisp`): a title, the
    examples it is made of, and an optional prose file;
  - each example: its opening comment becomes prose, its code a listing, and its
    `.expected` the output shown.
- **Checked**: the generated manual matches the committed one. Every example
  belongs to a chapter, or is listed as left out, with a reason.
- **One book**: an index page links the chapters and the reference. Shipped in
  the bundles under `docs/`.
- **What is written by hand** is only what joins the chapters: an introduction,
  installing and running, and a short prose file where a chapter needs one.

As built (10.2 to 10.4):
- `tools/docs.lisp` builds each generated file as a string, and
  `tools/generate-docs.lisp` writes them. The suites load `tools/docs.lisp` and
  compare its strings with the committed files.
- The reference holds only the built-in categories, so neither the tool's nor a
  program's documented definitions get into it.
- The JSON is written by hand, sorted and one entry per line, so it diffs well.
  `STONJSON` writes a dictionary in hash order.
- The extension activates when a cog-lisp file opens, not only in a folder with
  the launcher, so help works in any workspace.
- **Found by the owner, 2026-11-06: no hover after installing.** There were two
  causes:
  - The `.vsix` in `vscode/` was a Nov 4 build. It is git-ignored, and nothing
    had rebuilt it since hover help landed.
  - The extension's language claimed no file extension, so `.lisp` files became
    `cog-lisp` only through this repository's `.vscode/settings.json`. Anywhere
    else (an unpacked release, say) they opened as plain text, with no help.

  Fixes:
  - The language claims `.lisp`.
  - `test/package.test.js` checks the package holds `builtins.json` and makes
    that claim.
  - `test/integration/` runs the extension in a real VS Code
    (`@vscode/test-electron`, VS Code 1.90). It hovers over `define` and
    `display` in a folder with no cog-lisp settings, in CI under `xvfb`. It
    passes 5/5; without the `.lisp` claim it fails 4 of 5.
- A manual section's title is the example's first comment line, after `--` and
  without its spec reference. A folder example shows each of its files, an
  `.args` or `.input` file is shown with it, and an example without
  `.expected` (`dual.lisp`) is shown as a library.

### 10.5 The language server (spike first)
- **The spike, before the step's detailed spec:**
  - a `lisp lsp` command reads LSP messages from stdin and answers on stdout,
    with exact byte counts, on Windows and Linux;
  - VS Code's language client (`vscode-languageclient`, MIT) talks to it;
  - hover on a built-in shows its documentation.

  If exact reads from a pipe cannot be done reliably, the fallback is a local
  socket. The decision is recorded either way.
- **Then, served by the image** (each measured and specified after the spike):
  - **hover**: documentation, the parameter list, and `procedure-source` for a
    definition in the workspace;
  - **completion**: globals, special forms and macros;
  - **go to definition**: top-level definitions in workspace files, from the
    reader's source ranges;
  - **diagnostics**: read errors and compile errors with positions (closes C-18:
    a compile error carries its form, and the reader's source map gives its
    place);
  - **expand the form at the cursor**.
- **How the server compiles without running the program:** it reads and
  compiles each top-level form. It evaluates only the forms that define syntax
  (`define-syntax`, `define-macro`), so later forms expand as they will when the
  file runs. This is a decision for the owner (§7).
- **If the spike fails**, the step ends with the spike's record, and offline
  hover (10.3) is the editor's help until a later phase.

#### The spike's record (2026-11-05): it works, on both platforms

- **The worry was unfounded.** `LispStdin` already buffers raw bytes. Its
  `nextLine` takes them only up to a line feed, and `atEnd` blocks until bytes
  arrive or input ends. So a header line reads with `nextLine`, and only the
  body needed something new: `nextBytes: n`, which waits for exactly n bytes.
  No socket was needed.
- **The server is LISP**: `lib/lsp.lisp`, run by the ordinary launcher
  (`./cog-lisp.sh lib/lsp.lisp`), so no new shell command is needed.
  - Two documented primitives frame the messages: `(read-framed-message)` and
    `(write-framed-message text)`.
  - JSON is Pharo's `STONJSON`, a message a Smalltalk `Dictionary`, reached
    through interop.
  - It answers `initialize`, keeps the open documents (full sync), answers
    `hover` from `(documentation name)`, answers an unknown request with an
    error, and ends on `shutdown` and `exit`.
- **Checked from two clients.** Messages were written 7 bytes at a time, so a
  body has no line break after it and the next message comes later:
  - a Python probe, 8/8 on Windows (through `cog-lisp.bat`) and on Linux;
  - VS Code's own message layer (`vscode-jsonrpc` 8.2.0, which
    `vscode-languageclient` is built on; `vscode/test/lsp.test.js`), 6/6 on
    both.

  | | Windows | Linux (Docker) |
  |---|---:|---:|
  | start-up, to the `initialize` answer | 673 ms | 450 ms |
  | a hover, median of 20 | 33 ms | 1 ms |

- **Found on the way**: a Windows client must start the batch file as
  `.\cog-lisp.bat` (as the extension's tasks do), and must stop the VM itself
  if it stops the server: killing `cmd` leaves the VM running.

#### 10.5 in detail (accepted 2026-11-06, with decision 4 as proposed)

**The extension starts the server and falls back.** It uses
`vscode-languageclient` 9.0.1 (MIT; its license added to the extension's
notices), packaged in the `.vsix`.
- It starts `lib/lsp.lisp` with the workspace's launcher (`cogLisp.root`, as Run
  File finds it).
- With no launcher, or with `cogLisp.languageServer` set to `false`, the
  offline hover and completion of 10.3 stay in use.
- If the server stops, the extension says so once and falls back to the offline
  help.

**What the server serves**, each with checks in `vscode/test/lsp.test.js`:
- **Hover**: a built-in's documentation, as in the spike. For a top-level
  definition in an open document or a workspace file, hover also shows its
  documentation string (if any) and its source.
- **Completion**: the global environment's documented names and the special
  forms, as 10.3 does, plus the names that workspace files define.
- **Go to definition**: for a name a workspace file defines at top level.
  - The server reads (never runs) each `.lisp` file of the workspace when
    started, and each document as it changes.
  - The reader's source ranges give each definition's place.
- **Diagnostics**, as a document opens and changes:
  - read errors, at the reader's position;
  - compile errors, at the top-level form that failed. A compile error now
    carries its form and the reader's range of it, which closes C-18; the
    innermost form's place when the reader recorded it.
  - Unbound names are not reported, since a program may define them at run time.
- **Expand the form at the cursor**: a command, *cog-lisp: Expand Macro*, served
  by a cog-lisp request (`cog-lisp/expand`). It shows `macroexpand`'s answer in a
  new editor.
- **Positions**: the protocol counts UTF-16 units, and cog-lisp strings count
  characters. The server converts both ways, so a line with characters outside
  the Basic Multilingual Plane is placed correctly; a check covers it.

**Decision 4, the owner's: does the server run a document's syntax definitions?**
- *Proposed: yes*, for `define-syntax` and `define-macro` at top level, so that
  diagnostics see the program's own macros. This accepts that a document's
  macro definitions (and, for `define-macro`, its expander's code) run inside
  the server's image.
- *Without it*, a use of the program's own macro compiles as a procedure call.
  That gives no false errors, but misses the errors inside the use.

**Checked in CI**:
- the Linux and Windows jobs, which build the image, also run
  `vscode/test/lsp.test.js`;
- the VS Code job packages the `.vsix` with the client inside it.

**Measured and recorded**: start-up, and the median hover, completion and
diagnostics times on a file the size of `lib/compiler/compiler.lisp`.

#### 10.5 as built (2026-11-06)

- **The server**, `lib/lsp.lisp`, does all of the above.
  - Open documents are fully synced. The workspace index holds the top-level
    `define`, `define-macro` and `define-syntax` forms of every `.lisp` file. It
    skips `pharo`, `node_modules`, `.vscode-test`, `.git` and `dist`.
  - Paths are compared lowercased on Windows.
- **C-18 is closed.** A `LispCompileError` carries the forms being translated,
  outermost to innermost (`forms`). The server underlines the innermost one the
  reader has a range for.
- **The extension** starts the server through `vscode-languageclient` 9.0.1,
  spawning the launcher itself:
  - Windows: `cmd /d /c .\cog-lisp.bat lib\lsp.lisp`;
  - Linux: `./cog-lisp.sh lib/lsp.lisp`.

  While the server runs, the offline hover and completion answer nothing, so
  nothing shows twice. If the server stops, the extension warns once, does not
  restart it, and the offline help answers again.
- **The `.vsix` ships 8 npm packages, all MIT or ISC.** They are listed in
  `vscode/THIRD-PARTY-NOTICES.md`, and the package test fails on an unlisted one.
- **Checks:**
  - `vscode/test/lsp.test.js`: 18/18 on Windows and on Linux (Docker).
  - `npm run test:vscode`, inside VS Code 1.90:
    - offline 5/5;
    - with the server 7/7, covering one hover per name, go to definition,
      diagnostics, completion and Expand Macro.
  - CI runs `lsp.test.js` in its Linux and Windows jobs. Its VS Code job has no
    image, so it runs only the offline pass.

  | | Windows | Linux (Docker) |
  |---|---:|---:|
  | start-up, to the `initialize` answer | 352 ms | 277 ms |
  | diagnostics, a small file | 53 ms | 10 ms |
  | diagnostics, `compiler.lisp` (1295 lines) | 374 ms | 350 ms |
  | hover, median of 15 | 51 ms | 1 ms |
  | completion, median of 15 | 42 ms | 5 ms |

  Windows' extra time per request is probably `LispStdin` polling an empty pipe
  every 20 ms, where Linux blocks in `read`. This is not measured. It is well
  under the 300 ms budget.

## 5. Acceptance criteria

- AC-1 (10.1) Every primitive, special form and `lib/core.lisp` form has
  documentation, and a test fails when one does not. `(documentation 'name)`
  answers it, and a documented `define`, `define-macro` and `define-syntax` keep
  their strings. `lib/core.lisp` uses `define-syntax`'s string, compiled by the
  v0.2.0 seed. The example runs.
- AC-2 (10.2) `docs/builtins.md` is generated from the image, matches it in a
  suite, and ships in the bundles.
- AC-3 (10.3) The extension shows hover help and completion for every public
  name, from generated data checked against the image, with no image running.
- AC-4 (10.4) `docs/manual/` is generated from the examples and the chapter
  list, matches them in a suite, accounts for every example, and ships in the
  bundles.
- AC-5 (10.5) Either the image serves hover, completion, go to definition,
  diagnostics with positions and macro expansion to VS Code on Windows and
  Linux, with tests on both; or the spike's record says why not and what was
  tried.

## 6. Examples

| Example | Proves |
|---|---|
| `examples/documentation.lisp` | a documented procedure, and a built-in's documentation read back |
| (the manual) | every example, as a chapter's worked and checked code |

## 7. Decisions (owner, 2026-11-05)

1. **Macros are documented by a string in `define-syntax`**, not a separate
   call. A minor release (v0.2.0) gives the seed that compiles it (10.1). Special
   forms use a string in `define-special-form`, which needs no release.
2. **Every generated file is committed** and checked against the image by a
   suite: the reference, the editor's data, the manual.
3. **The manual is Markdown.**
4. **The language server evaluates a document's top-level syntax definitions**
   (`define-syntax`, `define-macro`), so later forms expand as they will when
   the file runs. This accepts that a document's macros run inside the server's
   image. (Proposed with 10.5's detailed spec; accepted 2026-11-06.)
5. **R-17 stays with the REPL**: the server reads whole documents. It is fixed
   when a large form sent to the REPL makes it matter.

## 8. Risks

- **About 300 descriptions to write** at once. They are mechanical and each is
  short. The test that fails on a missing one keeps it from drifting, and
  `docs/builtins.md` shows the whole set for review.
- **Exact byte reads from stdin** (10.5): the stdio machinery was built for lines,
  and the Windows pipe and console paths differ. Hence the spike, and the socket
  fallback.
- **A new runtime dependency for the extension** (the language client): packaged
  into the `.vsix`, and its license added to the notices.
- **The runtime moves to LISP in Phase 11.1**: primitive documentation written in
  Smalltalk now must move with it. Keeping it beside each definition makes that
  a move, not a rewrite.

## 9. Step status

| Step | Status |
|---|---|
| 10.1 Documentation in the image | done: the machinery; 249 primitives, 16 special forms and the compiler's entry points documented (10.1a, 2026-11-05); the 14 derived forms, by define-syntax's string, compiled by the v0.2.0 seed (10.1b, 2026-11-06) |
| 10.2 The reference of the built-ins | done (2026-11-05): docs/builtins.md, 283 entries in 17 sections, checked against the image |
| 10.3 Hover help, offline | done (2026-11-05): hover and completion from vscode/builtins.json, checked against the image |
| 10.4 The user manual | done (2026-11-05): docs/manual/, 14 chapters from all 36 examples |
| 10.5 The language server | done (2026-11-06): hover, completion, go to definition, diagnostics (C-18 closed) and Expand Macro, served by the image to VS Code on Windows and Linux |
