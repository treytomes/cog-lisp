# Developing in the image: a LISP editor, REPL, browser and inspector in Morphic

| | |
|---|---|
| **Status** | Accepted (owner, 2026-11-10) with the leanings of §12, decision 3 amended (a stale image updates itself, R-3) and decision 4 to be reassessed later. A spike first (§4). Amended (owner, 2026-11-10) for the agent the image is a body for: §3's first principle, §5.10 (R-32 to R-36), step 7, AC-7, decisions 11 and 12. Amended again (owner, 2026-11-10): VS Code runs a file, or opens a REPL, in the Pharo GUI (R-37, decision 13) |
| **Asked for by** | The owner (2026-11-10): "I need you to begin thinking through how we can start migrating app development back into the Pharo UI shell. We need the code file editor, REPL, along with some kind of browse / inspect functionality living inside of Morphic. We need a spec for this." |
| **Amended for** | The owner (2026-11-10), on the project's first premise: "One of the original premises of this project was to make the "image" the world that an AI agent lives in, equipped with a well known highly structured, highly reflective language. The Pharo/Lisp image becomes the agent's body." So every tool is a LISP interface before it is a window, and the agent gets a way in (§5.10) |
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

- **The image is a body, and the tools are its senses and hands** (the
  amendment). cog-lisp's world is meant to be where an AI agent lives, in a
  structured, reflective language it can read and rewrite. So every tool is a
  **LISP interface first and a window second**: what the browser lists, what the
  inspector shows, what the editor checks, evaluating in a unit, changing a
  definition, are procedures that answer plain LISP data, documented and tested
  as any library's exports, which a person's windows and an agent's calls use
  alike (§5.10). A window never knows something the interface cannot say.
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

### 4.1 The answers (2026-11-10)

1. **The GUI starts, given `--interactive`.** On Windows, `Pharo.exe
   <image> --interactive --no-default-preferences` opens the world
   (`OSWorldRenderer`, `MorphicUIManager`, 976 by 665), the playground and a code
   pane open, and LISP evaluates. Without `--interactive` the pinned VM (the
   headless build) does not add it, `Smalltalk isInteractive` is false, and the
   image prints Pharo's command-line usage and quits, under `Pharo.exe` and
   `PharoConsole.exe` alike. So `ide.bat` passes it. Nothing is written to the
   current folder; the playground writes its cache to `pharo-local/` beside the
   image, which is the development image's own folder (R-1). Linux is checked by
   hand when step 2 lands: no display reaches WSL or Docker here.
2. **The styler works and is fast enough in the background.** An
   `SHRBTextStyler` subclass (to keep the theme's table of styles) overrides
   `privateStyle:`, fills `charAttr` from LISP tokens and answers the text with
   its runs; the code pane's Shout decorator takes it (`shoutStyler styler:`).
   Comments, strings and keywords take the theme's colors, so a dark theme
   follows. On `lib/console.lisp` (80,854 characters, 1,477 lines): the tokens
   take 70 ms, styling 88 ms, and restyling in the pane about 400 ms, most of
   it Rubric laying out the text. So styling runs in Shout's background process,
   and the form being edited is styled first if typing in long files lags.
   (Skipping `string->number` for words that cannot be numbers halved the tokens'
   time; reading characters with `[text at: i]` instead of `string-ref` gained
   nothing.)
3. **The interaction model is all Do it needs.** `SpCodePresenter` evaluates
   through `interactionModel compiler`, which answers `source:`,
   `environment:`, `failBlock:` and `evaluate`; a LISP model answering a LISP
   evaluator makes Pharo's own Do it, Print it and Inspect it evaluate LISP.
   In a library file's unit, `(define (g) (+ (f) 1))` defined `spike/demo:g`,
   which called the library's private `f`. Print it writes Pharo's
   `printString` ("a LispCons"), so the front end prints with `write` instead.
   The code pane's "selection or else the line" becomes "selection or else the
   top-level form" in the LISP presenter.
4. **The REPL runs unchanged in a process of its own.** `LispRepl` over an
   input that waits on a semaphore (in its own process only) and a
   `WriteStream`: output streamed; an unbound variable opened the break loop
   with `use-value store-value abort`, and `(use-value 5)` continued with 5; a
   runaway loop left the UI process free and was interrupted
   (`signalException:`) into the break loop; `(abort)` returned to the prompt;
   the end of the input ended the REPL. **But the current output and input
   ports are image-global** (`LispPrimitives`' class variables `Output` and
   `Input`), as is the console library's `%console`: two REPLs would write into
   each other's panes. They become per process (a `DynamicVariable`, as
   `LispCurrentUnit` and the restarts already are) in step 2, R-31.
5. **An inspector tab is one method.** `LispCons>>inspectionList:` with the
   pragma made the inspector's tabs `List`, `Raw`, `Meta`, in that order; its
   table showed `1 1`, `2 (2 3)`, `3 "x"`, each written as LISP.
6. **Headless testing works** (§2).
7. **The console library in the pane**: the test console already interprets
   the library's escape codes into styled cells (29's R-23), so the pane's
   output stream does the same into text attributes; built in step 2, with
   `%console` per process (answer 4).
8. **The cost**: `cog-lisp.image` is 68.4 MB today; the tools add only the
   IDE's own code, measured in step 2 against this.
9. **The update in place works for `src/` and the libraries.** In a live
   image holding a definition of its own, filing in all of `src/` again took
   3.7 s (478 methods), kept the same `LispEnvironment`, and the definition
   still answered; compiling `lib/core.lisp` into the live environment took
   1.2 s, and afterwards the definition, the built-ins and new code all worked.
   `buildFromSeed:` cannot be used as it is: it makes a fresh environment, which
   would strand the image's own definitions, so the update compiles into the
   existing one. Recompiling the compiler in place is checked when R-3 is built.

## 5. The design (subject to the spike)

### 5.1 Layers

1. **The glue**, Smalltalk, in a new package `src/coglisp-ide.st`, built into
   the image: the few subclasses Pharo's extension points need (the styler, the
   interaction model, the pane streams, the debugger extension), the inspector
   tab methods on the `Lisp*` classes, the world menu. Each is thin and calls
   LISP. They move onto `define-class` when Phase 11.1 brings it.
2. **The model**, LISP: `lib/editor-services.lisp` (§5.9, shared with the
   language server) and `lib/ide.lisp` (sessions, the browser's queries, the
   inspection views, the projects, changing definitions). Both are public
   libraries (§5.10, R-32): their exports documented, tested without a window.
   No Spec2 or Morphic name appears in them.
3. **The front ends.** First, Spec2 presenters on the Morphic backend: the
   editor, the REPL, the browser (§12 decision 2: in Smalltalk now, beside the
   glue). Later, the agent's doorway (R-36), and whatever else is built on the
   model: 11.5's REPL tools, a terminal front end on `specs/32-tui.md`.

### 5.2 The development image

- **R-1. `ide.bat` and `ide.sh`** (a pair, kept in step) start the GUI on a
  development image, `pharo/ide/cog-lisp-ide.image`, made from
  `pharo/cog-lisp.image` the first time, and on a project folder given as an
  argument (the checkout, or `lisp-expert`). They pass `--interactive`, which
  the pinned VM does not add (spike 1).
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

- **R-37. VS Code reaches the GUI** (owner, 2026-11-10: "an update to the
  VS.Code extension to run either the current source file or the REPL from the
  Pharo GUI, in addition to the terminal options"). The extension gains two
  commands beside its terminal ones: *Run File in the Pharo GUI* and *Open a
  REPL in the Pharo GUI*. Each starts the development image if it is not
  running (as `ide.bat`/`ide.sh` do, on the workspace folder), and otherwise
  hands the running image the request (decision 13): the file runs in a new
  REPL window of the image, its output and errors there, or a REPL window opens.
  The image records each as a change made by a person (R-35). The terminal
  commands are unchanged.

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
- **R-31. Each evaluation has its own ports** (spike 4). The current output and
  input ports, and the console library's capabilities, are bound per process
  (as `LispCurrentUnit` and the restarts are), not in variables the whole image
  shares, so two REPLs, or a REPL and the editor's Do it, never write into each
  other's panes. A program run from a terminal sees no difference.

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

### 5.10 The agent's interface (the amendment)

- **R-32. Every tool is an `ide` procedure first.** For each thing a window
  does, `lib/ide.lisp` (`(require 'ide)`) exports a procedure that does it,
  and the window calls that procedure:
  - **evaluating**: a session (`ide-session`), with its own ports (R-31) and
    unit; evaluating text in a session or in a file's unit (R-9), answering the
    values, the output written, and the error and its restarts if one is raised;
    choosing a restart; interrupting;
  - **reading the body**: the libraries, a library's definitions, a definition
    (name, kind, documentation, source, file and place, R-21), callers and
    callees (R-18), searching names and documentation (R-19);
  - **looking into a value**: its views (R-22) as data, each a title and its
    rows, a row's value itself inspectable;
  - **checking and changing source**: the editor services' checks (§5.9);
    writing a definition back into its file and evaluating it (R-20); loading
    a file; the update in place (R-3).
- **R-33. Answers are data, not windows.** Lists, vectors, strings, symbols and
  the values themselves, described by the procedures' documentation; never a
  presenter or a morph. A window renders them; an agent reads them.
- **R-34. The interface is a public library.** Its exports are documented
  (the 10.1 suite) and listed in the reference (`docs/builtins.md`, Libraries),
  and `tests/lisp/ide-*.lisp` checks every one without opening a window. A step
  lands its interface before its window (§7).
- **R-35. Changes to the body are recorded.** Every change made through the
  interface, to a file or to the image (an evaluation that defines, a
  definition written back, a file loaded, an update), is appended to a log: when,
  by whom (the session, and whether a person's window or an agent made it), what
  changed (the file and place, the names defined), and the text before and
  after for a file. `(ide-changes)` answers it; a file's change can be undone.
  The log is kept in the image and, line by line, in a file beside it, so it
  outlives a crash (§10's "No Epicea").
- **R-36. The agent's doorway** (step 7, its own spec first): a server in the
  image that offers R-32's procedures to an agent as tools, over the Model
  Context Protocol (decision 11), on standard input and output or a local
  socket, its JSON and framing the language server's. What an agent may change
  is bounded (decision 12), and every change it makes goes to R-35's log.
- **R-38. Several agents at once** (owner, 2026-11-10: "We're going to need to
  consider ways for multiple agents to be able to work with the image without
  getting in each others way"). Specified with the doorway (step 7). What each
  agent already has of its own: a session, with its process, ports, console
  and unit (R-31). What they share, and the spec must settle:
  - **who**: an identity for each agent, not only "agent", in R-35's record and
    on every change;
  - **the definitions**: one global environment, where two agents defining one
    name replace each other's; perhaps a session's own namespace (a unit of its
    own, `specs/27`) to work in, and a deliberate step to make its definitions
    everyone's;
  - **the files**: two agents editing one file, or one a person has open:
    leases on files or definitions, or a check that the text is still what the
    agent read (as R-20 does for the browser);
  - **dynamic state** shared across processes: `parameterize`'s bindings are one
    per image today, as the ports were until R-31;
  - **saving and updating the image** (R-2, R-3): one at a time, and not under
    an agent mid-evaluation;
  - **the image files on disk**: a build, or a second VM, on an image another
    has open (`specs/17`; on 2026-11-10 another session's run held
    `cog-lisp.image` and the build could not replace it).

## 6. What it changes elsewhere

- **Phase 11's audit (`specs/33` 11.2).** It expects to remove "the IDE" and to
  decide Morphic and Spec by measurement. With this spec, Morphic, Spec2,
  Rubric, Shout, the inspector and the debugger are used, and the audit should
  expect to keep them. The front end stays replaceable (§3), so 11.7 may yet
  carry the tools onto a LISP-written UI. The change is recorded in 33 when this
  spec is accepted (§12 decision 9).
- **Phase 11.5** (`describe`, `inspect`, `apropos`, `who-calls`, `backtrace`) is
  built on this model, not beside it: one implementation, two front ends.
- **Phase 11.6** (networking from LISP) is how an agent gets into the world
  from outside (`specs/33`); R-36's doorway is its first use, local only.
- **`LispProcedure`'s shape** (R-21).

## 7. Steps

Each step lands green, with its tests and a status line here, one commit each,
through CI. Each lands its `ide` procedures (R-32) and their LISP tests before
its windows.

1. **The spike** (§4), its answers recorded; and **the editor services** taken
   out of the language server (R-29, R-30).
2. **The development image and the REPL** (R-1 to R-4, R-12 to R-16, R-31),
   and VS Code's commands to reach it (R-37).
3. **The editor** (R-5 to R-11).
4. **The browser and the inspector** (R-17 to R-24), with the definitions'
   places (R-21).
5. **Errors and the debugger** (R-25), with 11.5's backtrace.
6. **Finishing**: Spotter, the theme (dark, as the site is), settings, the
   manual's chapter "Developing in the image".
7. **The agent's doorway** (R-36), after its own spec, with R-35's log. The log
   itself lands with step 2, the first step that changes the body.

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
- **AC-7 (every step from 2; the amendment).** Everything the step's windows do
  is done by an `ide` procedure, checked by `tests/lisp/ide-*.lisp` with no window
  open, and documented (the 10.1 suite lists `ide`). Every change the step's
  procedures make to a file or the image appears in `(ide-changes)` with its
  session and its maker, and a file's change undoes.

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
- **Not in the release bundles, yet.** A bundle ships only the VM files
  `release/package.sh` keeps, and it drops `Pharo.exe`, SDL2, Cairo and the
  other libraries a window needs (their licenses were never needed). The tools
  run from a checkout's `pharo/` VM. Shipping them is a later decision, with
  those licenses checked as `release/licenses/README.md` says.

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
11. **The doorway's protocol** (the amendment). *Settled (owner, 2026-11-10):
    "The MCP server will eventually be built as well."* The Model Context
    Protocol, which agents speak already, carried on the language server's
    JSON and framing. When, and its details, are its own spec's (step 7).
12. **What an agent may change** (the amendment; settled in its own spec).
    Leaning: by default, a project's files and the definitions it loads; cog-lisp's
    own `lib/`, `src/` and the compiler only with the owner's leave, given for a
    session. Reading the whole body is always allowed.
13. **How VS Code hands a running image a request** (R-37). Leaning: a request
    file the extension writes into the development image's folder
    (`pharo/ide/requests/`), which the image watches and removes once taken:
    no network port (none to open in the firewall), nothing the image cannot
    do already, and replaced by the model's doorway (R-36) when it comes. The
    other choice is a socket on localhost now, which the doorway could later
    share.

## 13. Step status

| Step | What | Status |
|------|------|--------|
| 1 | The spike (§4.1); the editor services (R-29, R-30) | Done (2026-11-10): `lib/editor-services.lisp` and `tests/lisp/editor-services.lisp` (62 checks); the language server on it, its 31 checks and VS Code's 5 offline and 12 with the server passing unchanged |
| 2 | The development image and the REPL | 2a done (2026-11-10): R-12 to R-16, R-31, R-32 to R-35 for sessions (§14). 2b next: R-1 to R-4, R-37 |
| 3 | The editor | |
| 4 | The browser and the inspector | |
| 5 | Errors and the debugger | |
| 6 | Finishing | |
| 7 | The agent's doorway (its own spec first) | |

## 14. As built: step 2a, sessions and the REPL window (2026-11-10)

- **R-31.** `LispPrimitives`' output and input ports are bound in
  `LispOutputBinding` and `LispInputBinding` (`DynamicVariable`s), falling back
  to the image-wide default; the console library binds its capabilities in a
  `DynamicVariable` instance it makes (`%bound-console`). A forked process sees
  the defaults, not its parent's bindings.
- **A session is `LispSession`** (`src/coglisp-ide.st`, the new package
  `CogLisp-IDE`, filed in after the shell): requests in, results out, in a
  process of its own below the UI's priority, with its unit, ports and a
  wrapper run around each evaluation. It evaluates as `LispRepl` does, but
  answers results as data rather than printing them: on an error it answers
  the report and the active restarts, then waits on the failing computation's
  stack for the next request, so `(use-value 5)` continues the computation and
  `(abort)` comes back to the top (answered `aborted`). This replaces R-13's
  "`LispRepl` in its own process": the same break loop, with results a window
  or an agent can read.
- **`lib/ide.lisp`** (`(require 'ide)`, documented and in the reference):
  `ide-session`, `ide-eval` (with a `timeout`), `ide-wait`, `ide-type`,
  `ide-interrupt`, `ide-close`, `ide-sessions`, the result accessors, and the
  record of changes, `ide-changes` and `ide-log-to!`. A change is recorded when
  an evaluation that defines names is answered; its maker is the session's,
  person or agent.
- **The REPL window is `LispReplPresenter`** (and the `cog-lisp REPL` item in
  the world menu): a transcript, an input, an Interrupt button, and a row of
  buttons for the restarts at a break. R-14's restarts are buttons, not links:
  `abort` and `continue` run at once, any other puts `(name )` in the input to be
  finished. It evaluates only through `ide` (R-32); a watcher process streams
  the output and queues updates for the UI process. The console library's
  escape codes become text colors and emphasis (`LispIde textFromTerminal:`),
  the session running inside `with-console` with true color, 100 columns, and
  prompts reading lines.
- **Not yet**: clicking a value to inspect it (R-13) comes with the inspector,
  step 4; Alt+. for Interrupt, with the editor's keys, step 3.
- **Found**: `Semaphore>>waitTimeoutMSecs:` is deprecated in Pharo 14, and its
  rewrite notice goes to stdout: use `waitTimeoutMilliseconds:`. Under the
  headless `NonInteractiveUIManager`, `defer:` runs its block at once in the
  calling process.
- **Checks**: `tests/lisp/ide-sessions.lisp` (60) and
  `tests/lisp/ide-repl-window.lisp` (54).
