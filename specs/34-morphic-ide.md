# Developing in the image: a LISP editor, REPL, browser and inspector in Morphic

| | |
|---|---|
| **Status** | Accepted (owner, 2026-11-10) with the leanings of §12, decision 3 amended (a stale image updates itself, R-3) and decision 4 to be reassessed later. A spike first (§4) |
| **Asked for by** | The owner (2026-11-10): "I need you to begin thinking through how we can start migrating app development back into the Pharo UI shell. We need the code file editor, REPL, along with some kind of browse / inspect functionality living inside of Morphic. We need a spec for this." |
| **Relates to** | `specs/16-phase-10-documentation-and-editor.md` (the language server, `lib/lsp.lisp`, whose analysis the editor shares, §5.9); `specs/27-namespaces.md` (`LispUnit`: a file's library, its imports, what a form is evaluated in); `specs/29-console.md` (its output in the REPL pane, §5.4); `specs/32-tui.md` (a later front end on the same model, §3); `specs/33-phase-11-pure-image.md` (11.2's audit, which this changes, §6; 11.5's `inspect`, `apropos`, `who-calls` and `backtrace`, which share this model; 11.7's graphics) |

## 1. Where development happens now

A cog-lisp program is written in VS Code and run from a terminal:

- **The editor is VS Code**, with the extension's language server
  (`lib/lsp.lisp`, Phase 10.3): diagnostics, hover, completion, go to definition
  and formatting. The server runs on its own copy of the image, in the
  temporary folder.
- **The REPL is a terminal** (`cog-lisp.bat`/`.sh`, `LispRepl`), in its own VM.
- **Nothing connects them.** The image the editor analyses, the image the REPL
  runs and the program's own run are three VMs. A definition evaluated at the
  REPL is unknown to the editor; a value at the REPL cannot be looked into
  except by printing it; an error shows its report and its restarts, and no
  more.
- **Pharo's own tools are a Smalltalk programmer's.** Its inspector opens on a
  cons cell, showing two slots; its browser shows the runtime's Smalltalk
  classes; its playground evaluates Smalltalk.

What the owner asks for is the Smalltalk way of working, for LISP: one live
image holding the program, its editor, its REPL and the tools to look into it.

## 2. What the image already has (measured 2026-11-10)

The built `cog-lisp.image` is a full Pharo 14 (build 788) image: 779 packages,
among them 21 Morphic packages, 33 of Spec2, 77 of NewTools (the inspector,
playground, debugger, Spotter), 54 of Calypso (the system browser), 4 of
Rubric (the text editor) and 2 of Shout (styling), with SDL2 windows
(`OSWorldRenderer`, `OSSDL2Driver`) and Athens. The build turns off only
Epicea, Pharo's change log. Checked live, headless:

- **A Spec2 window opens and works without a display.** An `SpCodePresenter`
  opens in a `SpWindowPresenter` (its widget an `SpRubScrolledTextMorph`), its
  text and selection round-trip, and it closes; an `SpTreePresenter` opens as an
  `SpFTTableMorph`; `StInspectorPresenter` opens on a `LispCons`. The UI manager
  is `NonInteractiveUIManager`. So every tool here can be tested by a headless
  suite, as everything else is.
- **The code pane is pluggable**: `SpCodePresenter` takes an interaction model
  (`interactionModel:`; `SpCodeInteractionModel` has nine subclasses, the
  playground's and the debugger's among them), styles through a Shout styler
  (the Morphic adapter's `SpMorphicCodeTextStyler` is an `SHTextStyler`), and
  has `addTextSegmentDecoration:`, `withLineNumbers`, `contextMenu:` and
  `addShortcutWith:`. Completion is `CompletionEngine`
  (`SpMorphicCodeCompletionEngine`, `CoCompletionEngine`).
- **The inspector is extended by a method on the inspected class**, tagged
  `<inspectorPresentationOrder: n title: 'Name'>`, taking a builder and
  answering a presenter (122 such methods; `Object>>inspectionMeta:` is one).
- **The rest is extensible too**: the world menu (`<worldMenu>`, 65 uses), the
  tool registry (`Smalltalk tools register:as:`; the workspace role is
  `StPlaygroundPresenter`), the debugger (`TStDebuggerExtension`) and Spotter
  (9 `StSpotterProcessor` subclasses).

What cog-lisp's objects know about themselves:

- **A `LispProcedure`** holds its block, arity, name, source, documentation and
  category: its text (`retain-source`), but **not where that text is**, neither
  file nor position.
- **A `LispUnit`** (a loaded file, or a session) holds its path, its library,
  exports, imports, source, offset and forms. `LispUnit libraries` lists the
  loaded libraries.
- **`LispRepl`** is a read-eval-print loop over any input, output and error
  streams; at a console its break loop is a nested REPL on the failing
  computation's stack, where restarts are invoked.

## 3. Principles

- **Files are the truth; the image is live state.** Programs live in files,
  under git, as now, and VS Code stays a way to edit them. The image holds what
  has been evaluated, and the tools that show it. An edit is saved to its file;
  an evaluation changes the image.
- **One model, many front ends.** What the tools know (a file's definitions, a
  form's unit, a value's parts, who calls what) is a model written in LISP that
  names no Spec2 or Morphic class. The Morphic front end is the first to use it;
  the language server already does in part (§5.9); a REPL-driven inspector
  (11.5) and a full-screen terminal front end (`specs/32-tui.md`) can follow.
- **Lean on Pharo** (the project's tenet): Spec2's presenters, Rubric's text,
  Shout's styling, the inspector and the debugger, each extended where Pharo
  provides for it, rather than new widgets.
- **LISP first, Smalltalk a deliberate door.** A LISP value shows as LISP
  (written as `write` writes it), an error as a LISP report with LISP frames.
  Pharo's own views (the raw slots, a Smalltalk stack, the class browser) stay
  one click away.
- **The UI never waits on an evaluation.** Every evaluation runs in a process
  of its own, so a long or endless computation leaves the windows working and
  can be interrupted.

## 4. The spike, before the design is fixed

Each question gets a recorded answer (§4.1), as `specs/29-console.md` §3 did.
Item 6 is answered already.

1. **The GUI starts on a copy of `cog-lisp.image`** with `Pharo.exe` on
   Windows and `pharo/pharo` without `--headless` on Linux: the world opens,
   Pharo's own tools work, nothing is written to the current folder, and the
   `lisp` command does not run.
2. **A Shout styler for LISP**: an `SHTextStyler` subclass that styles from the
   LISP reader's tokens. It must restyle `lib/console.lisp` (1,477 lines) after
   a keystroke fast enough not to be felt; the spike measures it, and whether
   styling only the top-level form being edited is needed.
3. **A LISP interaction model** on `SpCodePresenter`: Do it, Print it and
   Inspect it evaluate LISP, inside a given `LispUnit`.
4. **The REPL in a process of its own**: `LispRepl`, unchanged, reading from a
   stream the pane feeds (a `SharedQueue`, which waits without blocking the UI)
   and writing to one that appends to the pane, deferred to the UI process. The
   break loop works; a runaway `(let loop () (loop))` is interrupted.
5. **An inspector tab on `LispCons` and `LispProcedure`** through the pragma.
6. **Headless testing** (answered 2026-11-10, §2): windows open, text and
   selection round-trip, and close, without a display.
7. **The console library in the pane**: its escape codes turned into text
   styles (color, bold), the cursor movements dropped, its prompts reading
   lines from the pane (29's R-11).
8. **The cost**: the image's size and start-up time with the IDE's code in it,
   and memory with the tools open.
9. **The update in place** (R-3): the build's own steps (`build/build.st`'s
   chunks 2 to 4: file in `src/`, remove what `src/` no longer defines, the
   compiler building its successor to a fixpoint) run in a live image that holds
   a program's definitions and open windows, and leave them working. The spike
   finds which changes it cannot carry (a class shape change with live
   instances, say), so R-3 can tell them apart.

### 4.1 The answers

To be recorded.

## 5. The design (subject to the spike)

### 5.1 Layers

1. **The glue**, Smalltalk, in a new package `src/coglisp-ide.st`, built into
   the image: the few subclasses Pharo's extension points need (the styler, the
   interaction model, the pane streams, the debugger extension), the inspector
   tab methods on the `Lisp*` classes, the world menu. Each is thin and calls
   LISP. They move onto `define-class` when Phase 11.1 brings it.
2. **The model**, LISP: `lib/editor-services.lisp` (§5.9, shared with the
   language server) and `lib/ide.lisp` (sessions, the browser's queries, the
   inspection views, the projects). No Spec2 or Morphic name appears in it.
3. **The front end**, Spec2 presenters on the Morphic backend: the editor, the
   REPL, the browser (§12 decision 2: in Smalltalk now, beside the glue).

### 5.2 The development image

- **R-1. `ide.bat` and `ide.sh`** (a pair, kept in step) start the GUI on a
  development image, `pharo/ide/cog-lisp-ide.image`, made from
  `pharo/cog-lisp.image` the first time, and on a project folder given as an
  argument (the checkout, or `lisp-expert`).
- **R-2. It is the owner's image to save.** Saving keeps the live state, the
  open windows and the REPL histories (§12 decision 3). `build-image` and the
  suites never touch it, so a build never collides with it (`specs/17`), and
  the suites never depend on it.
- **R-3. A stale image updates itself** (owner, 2026-11-10). At start-up, and
  from the `cog-lisp` menu, it compares the commit it was built from
  (`image-build-info`) with the checkout's. When `src/`, `lib/compiler/` or the
  built-in libraries have changed since, it says what changed and offers to
  update in place, keeping its state:
  - it files in the `src/` packages that changed and removes the methods `src/`
    no longer defines, as the build does (`LispCompiler removeStaleFrom:`);
  - it compiles the changed built-in libraries (`core`, `format`, `json`,
    `http`, `coverage`) into the live environment, so the existing cells take
    the new definitions and the program's code calls them;
  - when `lib/compiler/` changed, the compiler builds and seals its successor,
    to a fixpoint, as the build's bootstrap does;
  - it loads again the project files it had loaded, and records the new commit
    in `image-build-info`.

  Before it starts it saves a copy of the image beside it
  (`cog-lisp-ide.before-update.image`), so a failed update can be undone. A
  change it cannot carry in place (spike 9) it names, and offers the fresh image
  instead: one made from a newly built `cog-lisp.image`, with the project's files
  loaded again. `(ide-update)` does the same from the REPL.
- **R-4. It opens ready to work** (§12 decision 10): a REPL and the project's
  files, and a `cog-lisp` menu in the world menu (new REPL, open a file or a
  project, the browser).

### 5.3 The editor

- **R-5. Files and tabs**: a tree of the project folder's `.lisp` files, and
  each open file in a tab of the editor window.
- **R-6. Styling** by the LISP styler (spike 2): comments, strings,
  characters, numbers, quoted data, special forms and macros (known by name from
  the image), parentheses by depth, the one matching the cursor's highlighted.
- **R-7. Editing**: indentation on Enter, as `format-source` indents; Format
  (the whole file or the selection) by `format-source`, the formatter VS Code
  uses; Undo.
- **R-8. Saving** (Ctrl+S) writes the file as UTF-8, keeping its line endings
  (CRLF or LF: both are in use, in cog-lisp and in lisp-expert). A file changed
  on disk (by VS Code, by git) is reloaded when it has no unsaved edits, and
  otherwise reported, with both versions kept until the owner chooses.
  Saving does not evaluate (§12 decision 4).
- **R-9. Evaluating in the file's unit.** Do it (Ctrl+D), Print it (Ctrl+P,
  the value written after the form as `;; => value`) and Inspect it (Ctrl+I)
  evaluate the selection, or the top-level form at the cursor, **as part of the
  file**: in its `LispUnit`, with its library's names and imports, so a `define`
  in `lib/cl.lisp` defines `cl:remove`. A file not loaded yet is loaded first.
  Load file (Ctrl+L) evaluates the whole file, as `require` or `load` would.
- **R-10. What the language server knows**, through the shared services
  (§5.9): diagnostics as underlines and a list of problems, updated as the text
  changes; the documentation of the name at the cursor in a status line;
  completion; go to definition (Ctrl+B), to the file and the place, or to the
  browser for a built-in.
- **R-11. Keys are Pharo's** (§12 decision 6): Ctrl+D, Ctrl+P, Ctrl+I, Ctrl+S,
  Ctrl+B, as the playground and the browser use them.

### 5.4 The REPL

- **R-12. A window of its own**, any number of them, each a session unit
  (`specs/27` R-12): a transcript, and an input below it that evaluates when
  Enter ends a complete datum and otherwise takes a new line, as the console
  REPL reads. History with Up and Down, kept with the image.
- **R-13. It runs `LispRepl` in its own process** (spike 4): output appears as
  it is written; a result is written as `write` writes it, and clicking it
  inspects it.
- **R-14. Errors open the break loop in the pane**: the report, and the active
  restarts as links (clicking one invokes it, as typing its name does). The
  failing computation waits, on its own stack, until a restart is chosen or it
  is aborted.
- **R-15. Interrupting**: a button and Alt+. stop the evaluation, offering the
  break loop's restarts.
- **R-16. The console library's output** (spike 7, §12 decision 7): colors and
  bold shown, cursor movement dropped, so a table or a tree renders and a live
  display degrades to plain lines; its prompts read lines from the pane.

### 5.5 The browser

- **R-17. Libraries, definitions, a definition.** Three panes, in the manner of
  Pharo's browser:
  - the **libraries**: the loaded ones (`LispUnit libraries`), the built-ins by
    their documentation categories, the programs' globals, the sessions;
  - their **definitions**, the exports first and the private names dimmed, each
    marked procedure, macro, syntax, variable, special form or primitive;
  - the **definition**: its source (styled), and tabs for its documentation, its
    callers, its callees, and its disassembly (`method-listing`).
- **R-18. Callers and callees** come from the compiled code: a procedure calls
  the global cells its methods and blocks hold as literals, the way Pharo's
  senders are found. So they answer for what is in the image, built-ins
  included.
- **R-19. Search**: names and documentation, as `apropos` will (11.5), from the
  browser, and later from Spotter (Shift+Enter).
- **R-20. Editing from the browser** (§12 decision 5) writes the definition back
  into its file, at its place, saves and evaluates it, when the file still
  holds the same text there; otherwise it opens the file in the editor at that
  place instead.
- **R-21. Where a definition is.** A procedure, a macro and a global variable
  record their unit's path and the start and end of their source text, so the
  browser and go-to-definition reach the file and the place. (`LispProcedure`
  gains a slot: a class-shape change, subject to the seed rule, §10.)

### 5.6 The inspector

- **R-22. Pharo's inspector, with LISP views first**, each a tab through the
  pragma:
  - a **list** (proper or not): its elements, numbered, written as `write`
    writes them, each inspectable; a nested list as a tree;
  - a **procedure**: its source, documentation, disassembly, callers;
  - a **symbol**: its global binding and documentation;
  - a **hash table**: its keys and values;
  - a **unit**: its library, exports, imports and path;
  - a **condition**: its report, message and irritants;
  - a **vector**, a **string**, a **record**, as their parts.
  Pharo's Raw and Meta tabs stay last, the Smalltalk door.
- **R-23. The evaluator under the views evaluates LISP** (§12 decision 8), with
  the inspected value bound to `it`.
- **R-24. `(inspect x)`** opens this inspector when a world is showing; without
  one, 11.5's inspector at the REPL. Both use the model's views.

### 5.7 Errors and the debugger

- **R-25. An error in any evaluation from the tools is a LISP error**: its report,
  its restarts, and a LISP backtrace (procedure names and source places), which
  11.5's `backtrace` also gives at the console. "Debug" opens Pharo's debugger,
  with a LISP pane (`TStDebuggerExtension`) listing the LISP frames, each with
  its source and its locals. This step follows 11.5's backtrace, which it shares
  (§7 step 5).

### 5.8 Testing

- **R-26. The model is tested in LISP** (`tests/lisp/ide-*.lisp`,
  `tests/lisp/editor-services.lisp`), with `lib/test.lisp`.
- **R-27. The front end is tested headless** (§2): each window opened, driven
  through its presenters (text set, a selection made, a command run, a key
  sent), and read back from them, then closed. A suite fails on any window left
  open.
- **R-28. The GUI itself is checked by hand**, as the console's real terminals
  are: a script to start it, and a list of what to try, in `tests/ide/`.

### 5.9 The editor services, shared with the language server

- **R-29. `lib/editor-services.lisp`** takes the language server's analysis out
  of `lib/lsp.lisp` (611 lines): the index of definitions, the name at an
  offset, diagnostics (`lisp-check`), completion items, definitions by name,
  documentation text and formatting. Offsets are in characters; the server
  converts to and from LSP's UTF-16 positions, its JSON and its framing, and is
  then an adapter over the services.
- **R-30. VS Code sees no difference**: `vscode/test/lsp.test.js` and
  `npm run test:vscode` pass unchanged.

## 6. What it changes elsewhere

- **Phase 11's audit (`specs/33` 11.2).** It expects to remove "the IDE" and to
  decide Morphic and Spec by measurement. With this spec, Morphic, Spec2,
  Rubric, Shout, the inspector and the debugger are used, and the audit should
  expect to keep them. The front end stays replaceable (§3), so 11.7 may yet
  carry the tools onto a LISP-written UI. The change is recorded in 33 when this
  spec is accepted (§12 decision 9).
- **Phase 11.5** (`describe`, `inspect`, `apropos`, `who-calls`, `backtrace`) is
  built on this model, not beside it: one implementation, two front ends.
- **`LispProcedure`'s shape** (R-21).

## 7. Steps

Each step lands green, with its tests and a status line here, one commit each,
through CI.

1. **The spike** (§4), its answers recorded; and **the editor services** taken
   out of the language server (R-29, R-30).
2. **The development image and the REPL** (R-1 to R-4, R-12 to R-16).
3. **The editor** (R-5 to R-11).
4. **The browser and the inspector** (R-17 to R-24), with the definitions'
   places (R-21).
5. **Errors and the debugger** (R-25), with 11.5's backtrace.
6. **Finishing**: Spotter, the theme (dark, as the site is), settings, the
   manual's chapter "Developing in the image".

## 8. Examples

The tools are not programs, so the manual's chapter (step 6) is prose and
screenshots, not a checked example; what each step adds to the model gets an
example as every feature does (`examples/`): `inspect`'s views, `apropos`,
`who-calls`, a definition's place.

## 9. Acceptance criteria

- **AC-1 (step 1).** The spike's answers are recorded in §4.1. The language
  server runs on `lib/editor-services.lisp`, and its tests and the VS Code tests
  pass unchanged; `tests/lisp/editor-services.lisp` checks the services with
  character offsets, wide characters among them.
- **AC-2 (step 2).** Headless: an image built at one commit, with a program's
  definition evaluated in it, updates itself to a later commit that changed a
  built-in library and a `src/` method; the new definitions are in force, the
  program's definition still answers, and the copy from before the update
  exists. Headless: a REPL window evaluates `(+ 1 2)` and shows `3`;
  `(display "hi")` shows `hi` as it is written; an unbound variable shows the
  report and the restarts, and choosing `use-value` with `5` continues the
  computation; `(let loop () (loop))` is interrupted, and the REPL answers the
  next input; a console `table` shows with its borders. By hand: `ide.bat` and
  `ide.sh` open the image on a project; saving and reopening keeps the REPL's
  history; a stale image offers a fresh one.
- **AC-3 (step 3).** Headless: a file opens styled (a string, a comment and a
  special form each with their style); Do it on a `define` in a library file
  defines the library's qualified name; Print it inserts `;; => value`; saving
  keeps CRLF in a CRLF file; a file changed on disk reloads, and one with unsaved
  edits is reported; an unbound name is underlined; completion offers
  `string-append` for `string-ap`; go to definition opens the file at the place.
- **AC-4 (step 4).** Headless: the browser lists `console`'s exports, shows
  `panel`'s source, documentation and callers, and finds `table` by searching
  `"table"`; editing a definition in the browser writes it to its file and
  evaluates it; the inspector on `'(1 (2 3) "x")` shows three elements, written,
  and the nested list as a tree; on a procedure, its source; its evaluator
  answers `(car it)`.
- **AC-5 (step 5).** An error in a procedure called from the REPL shows a LISP
  backtrace naming that procedure and its file and line; "Debug" opens the
  debugger with the LISP pane listing the same frames.
- **AC-6 (every step).** `tests/run-all` passes on both platforms; the image's
  size and start-up time are recorded, and stay within what step 1 measured plus
  what the IDE's own code adds.

## 10. Risks

- **The seed rule.** R-21's new slot changes `LispProcedure`'s shape, and the
  new `src/` must still run the seed's compiler for one build (CLAUDE.md). The
  slot is added so that a seed's procedures, without it, still work, or the
  seed pin moves forward first.
- **Pharo's internal APIs.** Shout's styler and Spec2's code adapter are Pharo's
  internals, not a published API; the pin holds them still, and a Pharo upgrade
  re-runs the spike's checks.
- **Speed.** Styling a long file at every keystroke, and diagnostics that compile
  every form, could make typing slow; the spike measures, and both work on the
  form being edited when they must.
- **The image and the files drift.** A definition removed from a file stays in
  the image after the file is loaded again, as in any LISP image; the browser
  marks a definition whose file no longer holds it, and a fresh image (R-3)
  starts clean.
- **An update in place goes wrong.** Recompiling the compiler inside a live
  image is what the build does, but on an image the owner has worked in. The
  copy made first (R-3) is the way back; spike 9 finds what cannot be carried.
- **No Epicea.** The build turns it off, so a crash loses unsaved edits and what
  was evaluated since the last save of the image. Files are the truth (§3), so
  saving often is the remedy; recovery of unsaved buffers is not in this spec.
- **Blocking calls.** A uFFI call stops every process, the UI's included
  (`specs/29` R-20). The console library's raw key reading must not run in the
  pane (R-16: prompts read lines there); `LispProcess` already polls.
- **The pure image.** Keeping Morphic and Spec2 costs the pure image size (§6);
  step 1 measures what the tools add.

## 11. What it is not

- **Not a replacement for VS Code.** Both edit the same files; the language
  server keeps working (R-30).
- **Not a change to Pharo's own tools.** The system browser, the playground and
  the debugger stay as they are, for Smalltalk.
- **Not version control.** Iceberg is in the image; git stays where it is.
- **Not a GUI library for programs.** Windows for LISP programs are 11.7's,
  and full-screen terminal programs 32's.

## 12. Decisions for the owner

1. **Where the IDE lives.** Leaning: the glue and the front end built into
   `cog-lisp.image` (`src/coglisp-ide.st`), the model in `lib/`, so the tools
   are there whenever a world is; they cost nothing until opened.
2. **The front end's language.** Leaning: Smalltalk now, thin, calling the LISP
   model, because Spec2 is built by subclassing and cog-lisp cannot yet define a
   Smalltalk class from LISP; it moves to `define-class` with 11.1. The other
   choice, building Spec2 presenters from LISP through `send` now, puts more of
   it in LISP sooner, at the cost of fighting a framework made for subclasses.
3. **The development image.** Leaning: the owner's own, saved and kept, with
   R-3's warning when it is stale. The other choice is a fresh image at every
   start, with the project loaded: reproducible, but no state survives, which
   is what makes an image an image. *Accepted, amended: a stale image updates
   itself in place (R-3).*
4. **Saving and evaluating.** Leaning: saving writes the file only;
   evaluating is asked for (Do it, Load file). The other choice is Smalltalk's
   accept: saving also evaluates the forms that changed. *Accepted for now; to
   be reassessed.*
5. **Editing in the browser.** Leaning: allowed, writing back into the file
   (R-20). The other choice is a read-only browser, editing only in the
   editor.
6. **Keys.** Leaning: Pharo's (R-11), since the tools live among Pharo's. The
   other choice is VS Code's (Ctrl+Enter to evaluate, F12 for the definition),
   to match the other editor.
7. **The console library in the REPL pane.** Leaning: styles shown, cursor
   movement dropped (R-16). The other choice is plain text.
8. **The inspector's evaluator.** Leaning: LISP, with `it` (R-23).
9. **Spec 33's audit.** Leaning: record now that Morphic, Spec2, Rubric,
   Shout, the inspector and the debugger are expected keeps, the audit still
   measuring their size.
10. **What the image opens to.** Leaning: a REPL and the project's files
    (R-4). The other choice is Pharo's own world, with the `cog-lisp` menu.
