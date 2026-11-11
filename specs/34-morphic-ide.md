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
  in `lib/cl.lisp` defines `cl:remove`. A library's file not loaded yet is
  loaded first; a program's is not, since loading it runs it (it may wait for
  input). Interrupt stops an evaluation.
  Load file (Ctrl+L) evaluates the whole file, as `require` or `load` would.
- **R-10. What the language server knows**, through the shared services
  (§5.9): diagnostics as underlines and a list of problems, updated as the text
  changes; the documentation of the name at the cursor in a status line;
  completion; go to definition (Ctrl+B), to the file and the place, or to the
  browser for a built-in.
- **R-11. Keys are Pharo's** (§12 decision 6): Ctrl+D, Ctrl+P, Ctrl+I, Ctrl+S,
  Ctrl+B, as the playground and the browser use them.
- **R-42. A toolbar** above the tabs: *Run*, *Load*, *Save*, *Format* and
  *Interrupt*, acting on the file in the tab chosen, so the editor's actions are
  found without the menu or the keys. A status line below the tabs says what
  the last action did (saved, refused while busy, nothing to interrupt).
- **R-43. Run** (Ctrl+R) runs the file as a program, from a clean start, as
  `cog-lisp.bat` would: in a new REPL window, which loads the file as it is on
  disk. So a program that reads its input (`read-line`) or draws with the
  console library runs as in a terminal, its input typed in that window, and
  Interrupt there stops it. Saving and evaluating stay separate (§12 decision
  4): a file with unsaved edits is run as saved, and the status line says so.
- **R-44. The REPL is the editor's output pane.** Each file's tab has a REPL
  below its text, on the file's session (R-9): what Do it, Print it and Load
  file evaluate is shown there as it runs, its output as it is written, then
  its values, an error with its restarts as in a REPL window; a program reading
  its input reads what is typed there; and a form typed at its prompt is
  evaluated as part of the file. Do it and Print it show their form after the
  prompt; Load file shows `; load name.lisp`. The session is made at the first
  evaluation, not when the file opens, so opening a library does not load it.

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
- **R-39. The console library renders fully in a window** (owner, 2026-11-10:
  "`lisp-expert` makes use of the `console` library. I would like the `console`
  library to be able to perform its enhanced rendering inside of the Pharo
  UI"). R-16 shows colors and drops the rest; R-39 goes further, so a program
  such as lisp-expert's weather REPL looks and works in a window as it does in
  a terminal:
  - a **terminal pane**: a Morphic view of a cell grid, in a monospace font,
    drawn from the same escape-code interpreter as the test console (29's
    R-23), so cursor movement, clearing and redrawing in place work (a
    `choose` list's highlight, later live displays);
  - its **size is the window's**: the console's width and height follow the
    pane, and a renderable rendered there fits it;
  - **keys** go to the console library as its events (29's R-19), so `ask`,
    `confirm` and `choose` read keys, not lines, and Escape and Ctrl+C cancel;
  - the console's **capabilities** there: a terminal, interactive, true color,
    Unicode (29's R-1, R-2), so a program needs no change;
  - a **REPL window** whose transcript is such a pane, and a way to run a
    program in one (R-37's *Run File in the Pharo GUI*).
  It is built as step 2c, after the launchers; its checks drive the pane
  headless, as the test console is driven, and read its cells back.
- **R-40. Typing at the REPL's cursor, as in a terminal** (owner, 2026-11-11,
  trying 2c: "It would really be a nicer interface if typing occurred at the
  REPL cursor the way it does in a terminal, rather than in a separate text
  field"; and the Up arrow went to the field's history while Down went to the
  program). This amends R-12: the REPL window has no input field. Its terminal
  pane (R-39) is a view of its own, drawn in the code font, which takes the
  keys:
  - idle, it edits a line at the prompt: the arrows, Home, End, Backspace and
    Delete within it, Up and Down through the history, paste; Enter evaluates
    a whole form and starts a new line in an unfinished one;
  - while a program runs and reads lines, the same editing makes the line it
    reads; while it reads keys (a prompt, `read-event`), every key goes to it;
  - Ctrl+C copies a selection, else interrupts a running evaluation (when the
    program reads keys, it is the program's, as in a terminal);
  - a caret shows where typing goes; the mouse selects; the wheel scrolls, and
    output brings the end into view.
  Colors are a palette meant for a dark background (VS Code's terminal's), and
  the window's own echo and values are in colors that read on it. The Interrupt
  button is drawn as a button.
- **R-41. Finding the tools and the files** (owner, 2026-11-11: "It's not clear
  how to open a new REPL, or locate existing files that have been loaded into
  the image"). One `cog-lisp` menu in the world's menu bar: *New REPL*,
  *Loaded files*, *Update the image from the checkout*. *Loaded files* lists
  every file the image has loaded (its units with a path: programs and
  libraries), shows the one chosen, and runs it in a new REPL; it stands on
  `ide-loaded-files` (R-32), and the editor (step 3) takes over its source pane.
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
- **R-21. Where a definition is.** The browser and go to definition reach a
  definition's file and its place. As built (step 4a), no slot is added, so the
  seed rule (§10) is not met: the place is found. A library's name is looked
  for in its unit's file; any other in the files the image has loaded (its
  units' paths), then in cog-lisp's own built-in sources (`lib/`); in each
  file, among its top-level definitions, by its name; a procedure's retained
  source text, when it has one, picks the definition and its exact place, and a
  definition whose file no longer holds its text is marked stale (§10, the image
  and the files drift).

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
- **R-45. `(browse x)`** (the owner's request, 2026-11-11), built in beside
  `inspect`: opens the original source of a definition, given its name or its
  value: a definition in a file, in the editor at its place; a primitive (`(browse
  car)`), in the browser of Smalltalk, on the method that implements it; anything
  else bound, in the LISP browser. Without a world it writes where the source is.
  It answers the place as data.

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
   and VS Code's commands to reach it (R-37); then, as 2c, the console library's
   full rendering in a window (R-39).
3. **The editor** (R-5 to R-11).
4. **The browser and the inspector** (R-17 to R-24), with the definitions'
   places (R-21): 4a the browser (R-17 to R-21), 4b the inspector (R-22 to
   R-24).
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
- **AC-3c (step 3, R-42 to R-44).** Headless: the toolbar's buttons act on the
  chosen tab; Run opens a REPL window that runs the file as saved, and a
  `read-line` in it answers a line typed there; Do it shows its form and value in
  the tab's REPL; Load file of a program that reads a line, then a line typed in
  the tab's REPL, finishes it; a form typed at that REPL's prompt is evaluated
  in the file's unit.
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
| 2 | The development image and the REPL (2c: R-39) | 2a done (2026-11-10): R-12 to R-16, R-31, R-32 to R-35 for sessions (§14). 2b done (2026-11-11): R-1 to R-4, R-37 (§15). 2c done (2026-11-11): R-39 (§16). 2d done (2026-11-11), the owner's trial of 2c: R-40, R-41 (§17) |
| 3 | The editor | 3a done (2026-11-11): R-5, R-6, R-8's saving, R-9 (but Inspect it), R-11, Format; the owner's trial fixed (§18). 3c done (2026-11-11), the owner's request: R-42 to R-44 (§19). 3b done (2026-11-11): R-7, R-8's files changed on disk, R-10 (§20). |
| 4 | The browser and the inspector | 4a done (2026-11-11): the browser, R-17 to R-21 (§21). The whole body in it, the compiler edited live (§22). 4b done (2026-11-11): the inspector, R-22 to R-24, and R-45, `inspect` and `browse` built in (§23) |
| 5 | Errors and the debugger | Done (2026-11-11): R-25, with 11.5's `backtrace` (§24) |
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

## 15. As built: step 2b, the development image (2026-11-11)

- **`ide.bat` and `ide.sh`** (R-1): `[FOLDER]` opens the development image,
  `pharo/ide/cog-lisp-ide.image` (made from `pharo/cog-lisp.image` the first
  time), on a project folder (`COGLISP_IDE_PROJECT`, else the current folder);
  `--repl` and `--run FILE` ask it for a REPL window, or for a file run in one;
  `--fresh` builds a new image, sets the old development image aside
  (`cog-lisp-ide.before-fresh-<time>.image`) and opens the new one. They start
  `Pharo.exe` (`pharo/pharo` on Linux) with `--interactive`, from `pharo/ide/`:
  the GUI VM writes what a program prints to a file named `stdout` in its
  current folder.
- **Requests** (R-37, decision 13 as leaned): a request is a form in a file in
  `pharo/ide/requests/`: `(project "folder")`, `(repl)`, `(run "file")`,
  `(update)`. A running image takes them every two seconds, oldest name first,
  and touches `pharo/ide/heartbeat`; a launcher that finds the heartbeat less
  than ten seconds old only leaves its request, and otherwise starts the image,
  which takes it at start. `lib/ide.lisp`'s `ide-request` reads one, and
  `LispIde`'s start-up hook (registered with the `SessionManager`, acting only
  at a GUI start of an image with a `requests/` folder beside it) acts on it.
  A run is recorded as a change (kind `run`).
- **Opening ready** (R-4): the first time it takes requests, the image opens a
  REPL window if no request opened one. The world menu has `cog-lisp REPL` and
  `cog-lisp: update the image from the checkout`. Pharo's Welcome window still
  opens; the project's files appear with the editor (step 3).
- **The update in place** (R-3): `ide-stale-files` compares the modification
  times of `src/*.st`, `lib/compiler/` and the built-in libraries (`core`,
  `format`, `json`, `http`, `coverage`) with the image's build time
  (`image-build-info`'s `built`), or its last update: no git is needed, and a
  pull touches the files it changes. This replaces "compares the commit".
  `ide-update` copies the image as last saved beside it
  (`.before-update.image` and `.changes`), files in `src/` again and removes
  what it no longer defines (`LispIde refileSourceFrom:`, the build's chunks 2
  and 3), loads each changed built-in library into the live environment, loads
  again the project's files the image had loaded (those still there), and
  records the update. A change to `lib/compiler/` is answered `fresh`: the
  compiler's rebuilding itself in place (spike 9's last question) is not done,
  and `ide.bat --fresh` is the way. At start the image offers the update when
  files changed (`UIManager confirm:`).
- **Checked by hand on 2026-11-11** (Windows): `ide.bat` on `lisp-expert` made
  and opened the image, its heartbeat ran and it took the request; `ide.sh
  --repl` and `ide.bat --run expert/main.lisp` were taken while it ran, the
  demo's tables and colors in its window; an `(update)` request after a change
  to `src/coglisp-ide.st` updated the running image in place, and a new window
  showed the change. The REPL's transcript is now a code pane, whose monospace
  font has the box-drawing characters (the first piece of R-39).
- **VS Code** (R-37): *Run File in the Pharo GUI* (on the editor's Run menu
  and the palette) and *Open a REPL in the Pharo GUI*, beside the terminal's
  commands, start the `ide` script detached, the workspace folder as the
  project. A release bundle has no `ide` script, and the commands say so.
- **Checks**: `tests/lisp/ide-development-image.lisp` (39: requests, the
  project, taking request files, the headless start doing nothing, staleness,
  `fresh` for the compiler, and an update on a copy of the checkout carrying a
  new built-in and a new `src/` method while a session's own definition still
  answers); VS Code's integration suite checks the commands are there.

## 16. As built: step 2c, the console library in a window (2026-11-11)

- **An emulated terminal, written a piece at a time.** The test console's
  emulator became `make-terminal` (with `terminal-write!`, `terminal-screen`,
  `terminal-take-scrolled!`), exported by the console library: an escape
  sequence split across two writes is held until it is whole, and with the
  `history` option the rows that scroll off the top are kept. The test console
  is one such terminal, written once.
- **Keys from a reader.** A console capability, `reader` (a procedure answering
  the next character typed within a timeout, or #f), makes `read-event`, and
  so `ask`, `confirm`, `choose` and `choose-many`, read keys there as from a
  terminal, through the same decoder; raw mode and the real terminal's restore
  are left alone.
- **The REPL window's transcript is such a terminal**, the size of its pane in
  cells of the code font (measured at each evaluation; a new size makes a new
  terminal, what was shown kept above as history), its rows drawn as text with
  their colors and emphasis (`LispIde textForRow:`). The prompt, the values and
  errors are written into it too, with escape codes. Each evaluation runs in
  `ide-window-console` (`lib/ide.lisp`): a terminal, interactive, true color,
  Unicode, the pane's size, keys from the window (`LispKeyQueue`).
- **Keys.** Once the program reads keys, the transcript takes the focus, and a
  key pressed there goes to it as a terminal sends it (`LispIde
  keysForValue:character:control:alt:`: the arrows, Home, End, Page Up and Down
  and Delete as xterm sequences, Backspace as DEL, Ctrl+letter as its control
  character, Alt after ESC). Enter in the input while a program reads keys
  sends what was typed and a CR; before, a line typed goes to `read-line` as in
  2a. Enter and the arrows are bound as `KeyboardKey`s (a real key) and as
  `Character`s (a scripted one), each action named: Spec refuses two of one
  name (`CmDuplicatedEntryName`).
- **Found by hand in the GUI** (2026-11-11, `lisp-expert`'s weather REPL): the
  greeting panel and the command table draw at the window's width, borders and
  colors as in a terminal. Enter did not submit (it was bound only as
  `Character cr`; a real key arrives as `KeyboardKey enter`), and the transcript
  did not scroll to its end (`scrollToEndOfText` now); both fixed, then checked
  headless. The update in place failed in the development image:
  `removeStaleFrom:` looked for `src/` beside the image's folder, which for
  `pharo/ide/` is no checkout; the update now passes its `src/`
  (`#sourceDirectory`). Keys typed into the GUI after the fix were not checked
  by hand: the owner's checklist below.
- **To check by hand** (AC-5's kind): in a REPL window of the development
  image, `fetch` in the weather REPL, then the arrow keys and Enter in its
  city list; `ask` with Backspace; Escape cancelling. And whether the world
  menu's `cog-lisp REPL` item survives an update in place: after this morning's
  half-failed update it was gone from the GUI's menu bar, while a headless
  re-file keeps it.
- **Checks**: `tests/lisp/console-core.lisp` (19 more: the terminal in pieces,
  its history, keys from a reader, `choose` by keys) and
  `tests/lisp/ide-window-console.lisp` (26: key translation, the console's
  capabilities in a window, a table's borders, `choose`, `ask`, `confirm` and
  Escape by keys, Enter sending keys, output longer than the pane).

## 17. As built: step 2d, the owner's trial of 2c (2026-11-11)

- **The REPL window is a terminal pane typed at its cursor** (R-40):
  `LispTerminalView`, a morph of its own in a `SpMorphPresenter`, draws the
  window's lines in the code font, the caret as a block, a selection, and
  scrolls with the wheel, bringing the end into view on output. It sends every
  key to the window (`pressKey:character:control:alt:`), which edits the line
  at the prompt (drawn after the terminal's cursor, not written into the
  terminal until Enter), or, while the program reads keys, sends every key to
  it. So Up and Down are the program's in a `choose`, and the history's at the
  prompt. Ctrl+C copies a selection, else interrupts; Ctrl+V pastes. The
  prompt is written into the terminal, so the transcript ends with it.
- **Rubric was not used for the pane**: its text area hands every keystroke to
  its editor before any handler, so a terminal's keys could not be taken from
  it.
- **Colors** (R-40): VS Code's terminal palette for the 16 colors; the prompt
  bright green, values bright cyan, errors bright red, on a dark background.
  The Interrupt button has the stop icon and a red tint (`color:`).
- **One `cog-lisp` menu** (R-41): *New REPL*, *Loaded files*, *Update the
  image from the checkout*, all from `LispIde class>>menuCommandOn:`. The REPL
  window's own `<worldMenu>` method is gone: two such methods of one selector
  on two classes is the likeliest reason the item vanished after an update.
- **Loaded files** (R-41): `ide-loaded-files` answers each loaded file's path
  and its library (#f for a program); `LispFilesPresenter` lists them, shows the
  one chosen, and runs it in a new REPL.
- **A headless world is 240 by 120**, so a pane under 40 columns or 8 rows is
  taken for no pane, and the console gets 100 by 30.
- **Checks**: `tests/lisp/ide-window-console.lisp` grew to 54 (typing at the
  cursor, editing keys, the history, the program's keys in a `choose`, Ctrl+C
  and paste, the loaded files, the window listing them, the menu);
  `tests/lisp/ide-repl-window.lisp` (54) checks the transcript ending at the
  prompt.
- **For the owner to check**: the colors, typing at the cursor, Up and Down in
  `fetch`'s city list, the menu, and *Loaded files*, in a fresh development
  image (`ide.bat --fresh`): the window's class changed shape, which an update
  in place carries badly into windows already open.
- **Found by the owner in the fresh image** (2026-11-11), and fixed:
  - typing worked, but the arrows, Backspace, Delete and the Ctrl combinations
    did not: a key that types no character arrives only as a key down, which
    the pane ignored. `LispTerminalView` now takes those, and Ctrl with a
    letter, on key down (by their `KeyboardKey`: `keyValueFor:`, `letterOf:`;
    a letter key is named by its capital, `#C`), and suppresses the key press
    that may follow, so nothing happens twice; typed characters still come as
    key presses. Ctrl+Left and Ctrl+Right move a word.
  - `ide.bat` with no argument failed ("The syntax of the command is
    incorrect"): `%FIRST:~0,1%` of an undefined variable garbles its line; it
    reads `!FIRST:~0,1!` now. With no request, a running image now opens a new
    REPL window, so the launcher's call shows.
  - a closed image's heartbeat looked fresh for ten seconds, so `--fresh` just
    after closing refused: quitting, the image removes its heartbeat
    (`LispIde class>>shutDown:`).

## 18. As built: step 3a, the editor window (2026-11-11)

- **The `ide` procedures first** (R-32): `ide-project-files` (a folder's
  `.lisp` files, `pharo`, `node_modules`, `.git`, `dist`, `coverage` and
  `.vscode-test` left out), `ide-read-file` (`(text . ending)`: the text with line
  feeds, the file's ending `crlf` or `lf`), `ide-save-file` (UTF-8, in the file's
  own ending, or the `ending` option's; recorded as a change of kind `save` with
  the text before, `change-before`), `ide-undo-change` (writes that text back,
  recorded as `undo`), `ide-form-at` (the top-level form holding an offset, or
  the last one before it), `ide-load-file` (a `load` in a session of its own,
  which is closed after) and `ide-file-session` (the session that evaluates as
  part of a file, in its `LispUnit`, the file loaded first if it was not; one per
  file, whichever way its path is written).
- **The window is `LispEditorPresenter`** (the `cog-lisp` menu's *Editor*): a
  tree of the project's folders and `.lisp` files (`ide-project`, else
  `COGLISP_HOME`), a notebook with a page per file opened (a file opens once),
  and an output pane. A page (`LispEditorPage`) is a code pane whose tab title
  marks unsaved edits with `*`.
- **Styling** (R-6) is `LispStyler`, an `SHRBTextStyler` filling its attributes
  from `editor-tokens`: comments, strings, characters, numbers, quoted data,
  special forms and macros as Pharo's styles for comments, strings, characters,
  numbers, symbols and `self`, parentheses by depth as `parenthesis` to
  `parenthesis7`. Rubric styles synchronously ("not safe" in the background).
  The matching parenthesis's highlight is not done.
- **Keys** (R-11): Ctrl+S save, Ctrl+D Do it, Ctrl+P Print it, Ctrl+L Load file,
  Ctrl+Shift+F Format, each bound twice (a real key and a typed one, each named),
  and the same actions, with Cut, Copy and Paste, in the pane's menu, which
  replaces Pharo's (its Do it evaluates Smalltalk). Inspect it (Ctrl+I) comes
  with the inspector, step 4. A shifted key is `KMModifier shift + key` before
  `actionModifier` (a Ctrl-or-Cmd choice, which takes no shift).
- **Evaluating** (R-9): the selection, else the form at the cursor, in the
  file's session, in a process of its own; what it writes and its value go to
  the output pane, Print it writes `;; => value` after the form, an error is
  reported and the session brought back from its break, and a second
  evaluation while one runs is refused (`busy`). Load file evaluates the
  page's text as it is, unsaved edits and all.
- **Format** (R-7) is `format-source` on the whole text; the selection alone is
  not done.
- **Found:**
  - `processPreemptionYields` is true, and headless Pharo still has a Morphic
    UI process cycling the world at the user's priority. So a process changing
    a window can be put behind that process in the middle of a layout. The
    tests failed about one run in six until every change to a window went
    through `LispIde onUi:`, which runs a block in Morphic's UI process
    (`currentWorld defer:`; `UIManager default` has no UI process headless) and
    answers its value. Keys and clicks already run there.
  - A wrapped Rubric pane once recomposed forever, in a loop between its
    scroll pane's width and its paragraph, and ran out of memory: the code and
    output panes are not wrapped (`beNotWrapWord`).
  - `cursorPositionIndex:` moves one end of the selection only, so the old end
    makes a selection; a cursor is an empty `selectionInterval:`.
- **Found by the owner in the GUI** (2026-11-11), and fixed:
  - a right click raised Spec's "You are using contextMenu: and actions: at
    the same time": a presenter with shortcut actions takes its menu from its
    actions. The page's actions are now its menu (*Do it*, *Print it*, *Load
    file*, *Interrupt*, *Save*, *Format*, *Cut*, *Copy*, *Paste*), each with its
    key; the typed-key twins are `beShortcutOnly`. A test builds the menu as a
    right click does (`codePaneMenu:shifted:`).
  - Do it in `examples/echo.lisp` answered only "busy": the file was loaded
    before its first evaluation, which ran the program, and it waited for input
    for ever. Only a library's file is loaded first now, and *Interrupt* stops
    an evaluation (the busy message names it).
  - Pharo's styles were hard to read on LISP: the styler has its own palette,
    VS Code's Dark+ (Light+ on a light theme): keywords blue, strings orange,
    comments green and italic, numbers pale green, quoted data teal,
    parentheses gold, orchid and blue by depth. Checked by drawing the pane to a
    PNG headless (`imageForm`, `PNGReadWriter`).
- **For the owner to check**: in the development image (`ide.bat --fresh`), the
  editor from the `cog-lisp` menu; that Ctrl+D, Ctrl+P and Ctrl+S on a real
  keyboard are the editor's, not Pharo's (headless tests call the actions, not
  the keys); the styling's colors.
- **Checks**: `tests/lisp/ide-editor.lisp` (37: the procedures, a CRLF file
  saved, a save undone, the form at a place, a library's unit, loading) and
  `tests/lisp/ide-editor-window.lisp` (47: the tree, tabs, the unsaved mark,
  saving in CRLF, Do it at the cursor and on a selection in a library's unit,
  an error, Print it, Load file, busy, Format, the styler, the keys and the
  menu); `tests/lisp/ide-window-console.lisp`'s menu check names *Editor*.

## 19. As built: step 3c, running programs from the editor (2026-11-11)

The owner's trial of 3a found no way to run a program that reads its input,
and Ctrl+L hard to find; R-42 to R-44 were added for it.

- **The toolbar** (R-42): *Run*, *Load*, *Save*, *Format*, *Interrupt*, above
  the tabs, each acting on the tab chosen (the editor maps each tab to its page:
  tabs can be closed, so their order is not the pages'). With no file open,
  the status line says to choose one. The status line, below, replaced 3a's
  output pane: saved, refused while busy, nothing to interrupt, running.
- **Run** (R-43, Ctrl+R, the menu's first item): a new REPL window, titled with
  the file's name, that loads the file as saved, as `ide.bat --run` does; it
  reads what is typed there and is interrupted there. A tab with unsaved edits
  runs as saved, and the status line says so.
- **The tab's REPL** (R-44): each page holds a `LispReplPresenter` below its
  text, on the file's session (`sessionSource:`, made at its first evaluation;
  a REPL leaves a session handed to it open when it closes). Do it, Print it
  and Load file go through it (`evaluate:showing:then:`): the form, or
  `; load name.lisp`, after its prompt, then output, values or an error with
  its restart buttons, as in a REPL window. A line typed there answers a
  program's `read-line`; a form typed at its prompt is evaluated as part of
  the file. Print it's insertion comes from the result block, and changes the
  code pane through `LispIde onUi:`: headless, a result is shown in the
  evaluation's process.
- **Checks**: `tests/lisp/ide-editor-window.lisp` (87): the tab's REPL showing
  each evaluation, its break and abort, a program in it reading a typed line, a
  form typed at its prompt seeing a private name, its session made late and
  kept; Run reading a typed line and running the file as saved; the toolbar on
  the tab chosen and with none; the menu and keys with Run.
- **For the owner to check**: `ide.bat --fresh`; in the editor, `echo.lisp` with
  *Run* (type lines in the new window, then Interrupt or close it), and with
  *Load*, typing lines in the tab's REPL; Ctrl+R on a real keyboard.

## 20. As built: step 3b, what the editor knows (2026-11-11)

- **The `ide` procedures** (R-32), over `editor-services`: `ide-check` (a
  text's problems, the text indexed as the file's), `ide-describe` (the
  documentation of the name at a place), `ide-complete` (`(start end
  completions)`), `ide-definitions` (where go to definition goes, the project
  indexed first by `ide-index-project!`, once), `ide-indent-unit`,
  `ide-indent` (R-7) and `ide-format` (format-source, indented as the file
  indents: it formatted with tabs before, whatever the file used).
- **Unbound names** (AC-3's underline): `editor-check` now warns on each use of
  a global nothing defines. A form is compiled a second time (`compile-form`)
  and its method's literals, its blocks' too, searched for unbound
  `LispGlobal` cells; a name is left out when the text defines it (its
  top-level forms macro-expanded, so a defining macro counts, and a name
  defined later in the text is not reported), the image binds it, or another
  file of the index defines it. A warning, not an error: a program may define
  a name at run time. The language server shares it, so VS Code shows it too.
  On eleven of cog-lisp's own files (the compiler among them) it reports
  nothing; the second compile's warnings (a redefined built-in) are dropped,
  or each would be reported twice.
- **Problems** (R-10): a page checks its text 0.4 s after it last changed, in a
  process of its own; a check of a text that changed meanwhile is dropped. The
  problems are underlined by the styler (an error in red too: `TextEmphasis
  underlined`) and listed in a *Problems* tab beside the REPL's, titled with
  their number; choosing one selects it. Styling again keeps the selection.
- **The documentation of the name at the cursor** is in the status line as the
  cursor moves (its first two lines). **Completion** (Ctrl+Space, *Complete*):
  one name is inserted, several are offered in a list below the text (a
  popover). **Go to definition** (Ctrl+B): the file opened in its tab, the
  definition selected, found by its text (the index reads a CRLF file as it is,
  the tab holds it with line feeds); several, a list; none, the documentation
  of a built-in the image has with no file here (the browser comes in step 4).
  Text is inserted through Rubric's editor (`replaceSelectionWith:`), so Undo
  undoes it.
- **Enter** (R-7) starts a new line indented one level deeper than the line
  holding the innermost list still open, in the file's own unit (a tab, or the
  spaces of its first indented line).
- **Files changed on disk** (R-8): while the window is open, every two seconds,
  each tab's file is compared with its text as saved. Without unsaved edits it
  is reloaded; with them it is kept aside, the tab's title says *(changed on
  disk)* and the status line says how to choose: Save keeps these edits,
  *Reload from disk* takes the file's.
- **Found**: a single `!` in a method's string (`ide-index-project!`) ended the
  file-in's chunk, and the build failed with "Unmatched ' in string literal"
  and no place: every `!` in `src/` is doubled, as CLAUDE.md says.
- **Checks**: `tests/lisp/ide-editor.lisp` (64: problems with unbound names, a
  defining macro, a library's private names; documentation; completion; go to
  definition across a project; indenting; formatting in the file's style) and
  `tests/lisp/ide-editor-window.lisp` (128: underlines and the problems tab, a
  check by itself after a pause, the selection kept, documentation at the
  cursor, completion inserted and offered, go to definition in a CRLF file and
  on a built-in, Enter, a file changed on disk with and without unsaved edits);
  the language server's 31 checks and `tests/lisp/editor-services.lisp` (62)
  pass unchanged.
- **For the owner to check**: `ide.bat --fresh`; typing a misspelled name and
  seeing it underlined; Ctrl+Space and Ctrl+B on a real keyboard, and the
  completion list's keys (arrows, Enter); a file changed in VS Code while open
  in the editor.

## 21. As built: step 4a, the browser (2026-11-11)

- **The `ide` procedures** (R-32), each answering data: `ide-groups` (the
  built-in categories that have names, in the reference's order; the loaded
  libraries; programs), `ide-group-definitions` (`#(name kind exported?)`, a
  library's exports first), `ide-definition-kind` (special-form, macro,
  syntax, primitive, procedure, variable), `ide-browse` (`#(name kind
  documentation source path start end stale?)`), `ide-callers`,
  `ide-callees`, `ide-search`, `ide-disassembly` and `ide-write-definition`.
- **Kinds.** A primitive is a procedure whose block is in a method of a class
  (`LispPrimitives`' installers: `map` is one); one cog-lisp compiled is in a
  method of none. A syntax is a macro whose source starts with
  `(define-syntax`. Built-ins the seed compiled keep no source (`filter`), so
  the browser shows their text from the file.
- **Places** (R-21, as amended): found, not recorded, so `LispProcedure`'s shape
  is unchanged and the seed rule is not met. A procedure's retained source picks
  its definition and its exact place; one whose file no longer holds that text
  is stale, and the browser says so.
- **Callers and callees** (R-18): the global cells in a procedure's code and its
  blocks' (a macro's expander's), and the symbols an inlined call to a built-in
  guards with (`*` is inlined, behind a check of its symbol), as Pharo's senders
  count symbol literals; a quoted symbol of that name counts too.
- **Disassembly**: `symbolicBytecodes` of each piece of code, the procedure's,
  then each block's, which prints a nested block without the source lookup
  that `symbolic` fails on.
- **The window is `LispBrowserPresenter`** (the `cog-lisp` menu's *Browser*): a
  search field (Enter searches names, then documentation); the groups; their
  definitions, each with its kind, private names dimmed; the definition, with
  its header (name, kind, file and line, stale), *Save* and *Open in editor*,
  and tabs for its source (styled, editable), documentation, callers, callees
  (each opened by a double click) and disassembly. *Save* (Ctrl+S) is R-20:
  written into its file, saved and evaluated in the file's unit, recorded; a
  stale definition is opened in the editor, not written.
- **The editor's go to definition** on a built-in with no file opens the
  browser on it, as the file means the name (R-10).
- **Checks**: `tests/lisp/ide-browser.lisp` (45: groups, a library's and the
  programs' definitions, kinds, places by text and by name, stale, callers and
  callees, built-ins included, search by name and documentation, disassembly,
  writing back recorded and refused when stale) and
  `tests/lisp/ide-browser-window.lisp` (27); the console suite's menu check
  names *Browser*.
- **For the owner to check**: `ide.bat --fresh`; the browser from the
  `cog-lisp` menu; a definition edited and saved there, then the file in the
  editor; Ctrl+B on `car` in the editor.

## 22. As built: the whole body in the browser, the compiler edited live (2026-11-11)

The owner's trial of 4a found every special form, and many built-ins, shown
"with no source in the image", and asked that the whole compiler be editable
live from the browser.

- **Special forms** are entries in the compiler's table, made by a top-level
  `define-special-form` in `lib/compiler/compiler.lisp`, which no definition
  reader knew. The browser finds that form (its place and text), and the
  translator procedure in the table stands for the form: its callees
  (`lc-translate-if` for `if`), callers and disassembly.
- **Primitives** are Smalltalk: `ide-browse`'s ninth part is `(class selector
  source)`, the method of `LispPrimitives` that installs it and the block that
  implements it (from the block's source node). The browser shows that block in
  the Source tab and opens Pharo's browser on the method (*Browse the
  Smalltalk*): the Smalltalk door.
- **The sealed sources** (`ide-sealed-sources`: the compiler's five files and
  the five built-in libraries) are a group each in the browser, listing every
  definition in the file in its order, the helpers no category holds, and the
  special forms, so the whole compiler can be read there.
- **The compiler edited live.** The sealed compiler reads private copies of the
  cells it uses, so a definition of one of its names, from a program, changes
  only the program's world. A definition evaluated **as part of a sealed
  source** (in its file's session, `ide-file-session`: the editor's Do it and
  Load file, the tab's REPL, the browser's Save) now changes the sealed code
  too: `LispCompiler resealAll:sourceDirectory:` finds each name's private copy
  (walking the sealed code from what the sealed sources define, as sealing
  did), puts the new value in it, seals the new value's own code the same way,
  takes again any entry point defined anew, and voids Cog's machine code. A
  program's definition still never comes there. A special form's
  `define-special-form` replaces its translator in the shared table, which
  needed nothing new. The edit lasts until the next build, which compiles the
  file as saved; a broken edit can break the running compiler, and a fresh image
  (`ide.bat --fresh`) is the way back.
- **One list of categories**: `documentation-categories`, a documented
  built-in in `lib/core.lisp`, which the browser and `tools/docs.lisp` both
  use.
- **A full name of a library not loaded** (`lib:name`) is no longer reported
  unbound by the editor services' check: a program may load the library at run
  time. One of a loaded library that does not have the name still is.
- **Checks**: `tests/lisp/ide-browser.lisp` (63: the category list, a special
  form's place and translator, a primitive's Smalltalk, the sealed sources'
  groups, and the compiler edited live: a program's definition of
  `lc-expansion-too-deep` changes nothing, the same definition evaluated in
  `compiler.lisp`'s session changes the running compiler's message at once,
  and the file's text puts it back); `tests/lisp/ide-browser-window.lisp`
  (35); `tests/lisp/ide-editor.lisp` (65).
- **For the owner to check**: `ide.bat --fresh`; in the browser,
  `compiler/compiler.lisp (source)`, a helper edited and saved, then a form
  compiled that uses it; *Browse the Smalltalk* on `car`.

## 23. As built: step 4b, the inspector, inspect and browse (2026-11-11)

- **The `ide` procedures** (R-32, R-33): `ide-views` (a value's views as data,
  each `#(title rows)`, a row `#(label written value)`, the value itself
  inspectable: a list's elements from 1, an improper one's rest; a vector's and
  a string's from 0; a symbol's name, kind, value and documentation; a
  procedure's name, documentation, source, file and callers; a macro's expander
  and source; a hash table's keys and values; a unit's library, path, exports
  and imports; a condition's report, message and irritants; and a last view,
  Value, for every value), `ide-evaluate-with-it` (R-23), `ide-inspect` (R-24)
  and `ide-open-source` (R-45).
- **A procedure's name** is its local one (`ide-close`, not `ide:ide-close`), so
  its views and `browse` take the name of the cell that holds it.
- **The window is `LispInspectorPresenter`**: each view a tab, its rows a tree
  (a part that is a list or a vector unfolds into its own elements, so a nested
  list is a tree), a double click inspecting a part (Back returns), and a LISP
  evaluator below (Ctrl+D *Evaluate*, Ctrl+I *Inspect* what it answers), with
  `it` bound to the value. *Pharo inspector* opens Pharo's own, the Smalltalk
  door.
- **Pharo's inspector** has a *LISP* tab first (`inspectorPresentationOrder:
  -10`) on LISP's own kinds of value (`LispCons`, `LispSymbol`,
  `LispProcedure`, `LispMacro`, `LispHashTable`, `LispUnit`, `LispError`): that
  same presenter, its own LISP evaluator, Pharo's Smalltalk one turned off for
  it (`withoutEvaluator`). Not on `Object`: Smalltalk's own objects keep
  Pharo's tabs first. Raw and Meta stay last.
- **The ways in**: *Inspect it* (Ctrl+I) in the editor, as Do it then its value
  in an inspector; *Inspect* in a REPL window, on the last value (R-13's
  "clicking a value", as a button: the transcript is a terminal's text, not
  objects); `(inspect x)`; and the browser's callers and callees.
- **`inspect` and `browse` are built in** (category The system), primitives the
  IDE package installs: the runtime's `installInto:` asks `LispIde`, when it is
  filed in, for them (`installToolsInto:`), so they are in every image built from
  this source, at any REPL, with no `require`, and load the `ide` library the
  first time they are called. A world is showing when `Smalltalk
  isInteractive`; headless (a console REPL, the suites) they write.
- **Checks**: `tests/lisp/ide-inspector.lisp` (49: each kind's views, the
  evaluator, `inspect` and `browse` written with no world, their documentation)
  and `tests/lisp/ide-inspector-window.lisp` (31: the tabs, the tree, diving and
  Back, the evaluator and Inspect, Pharo's LISP tab, Inspect it in the editor and
  Inspect in the REPL, the editor and the Smalltalk method `browse` opens);
  `tests/lisp/ide-editor-window.lisp`'s action lists name *Inspect it*.
- **For the owner to check**: `ide.bat --fresh`; `(inspect '(1 (2 3) "x"))`
  and `(browse car)`, `(browse 'filter)`, `(browse 'if)` at a REPL window;
  Ctrl+I in the editor; a LISP value in Pharo's own inspector.

## 24. As built: step 5, errors and the debugger (2026-11-11)

- **A LISP backtrace** (R-25, and 11.5's `backtrace`): `LispIde
  lispFramesFrom:` turns a context into LISP frames, innermost first. A context
  belongs to the procedure whose block it runs, or a block inside it (found
  through the closures' outer contexts), named by the global that holds it; each
  call shows once; a primitive is a frame of its own; the walk stops at the
  top-level form the evaluation began in. A primitive the compiler inlines (`car`,
  a direct send) and a tail call leave no frame, as in any LISP with them.
- **As data** (R-33): a session keeps the error's context at a break (cleared
  back at the top), a result's eighth part is its frames (`result-backtrace`:
  `#(name path line procedure)`, the definition's file and line), and
  `ide-backtrace` answers them for a session at a break.
- **`(backtrace)`**, built in (Conditions and restarts), writes the frames of the
  break it is called at, a line each: at a session's (the windows'), and at the
  console REPL's break loop, which records its error per process
  (`LispErrorContext`, a `ProcessLocalVariable`) and, leaving, puts back the one
  before it. Away from a break, the frames of the current computation.
- **The REPL window** writes the frames under an error's report (`in name
  file:line`, dimmed), and offers *Debug* beside the restarts at a break: Pharo's
  debugger on the session's process, at the error (`OupsDebugRequest`). Closing
  the debugger may end that process; a REPL whose session's process has ended
  makes a new session at its next evaluation, and a file's session is made again.
- **The LISP pane in Pharo's debugger** is `LispDebuggerPane`
  (`TStDebuggerExtension`, always shown): the same frames, and for the one
  chosen, its source (styled) and its arguments and locals, written. The
  compiler keeps no LISP names for its temporaries (`l1`, `l2`), so they are
  shown by place: arguments, then locals (the first locals are the arguments'
  own copies, which `set!` assigns).
- **Not done**: an uncaught error while running a file (`cog-lisp.bat
  file.lisp`) still reports only `path:line:col: error: message`, as the suites
  expect; 11.5's acceptance asks for a backtrace there too, which comes with
  11.5.
- **Checks**: `tests/lisp/ide-backtrace.lisp` (14: frames as data with files and
  lines, a lambda's call as its procedure's frame, `(backtrace)` at a session's
  break and at the console REPL's, away from a break, its documentation) and
  `tests/lisp/ide-debugger-window.lisp` (19: the REPL window's frames and Debug,
  the pane's frames, source and locals, the pane as an extension, a dead session
  replaced). Pharo's debugger is not opened by a suite: closing it is a
  person's act.
- **For the owner to check**: `ide.bat --fresh`; an error in a REPL window (its
  frames under the report), *Debug*, the debugger's *LISP* pane, then closing
  the debugger and evaluating again; `(backtrace)` at a break.
