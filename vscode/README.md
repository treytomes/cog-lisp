# cog-lisp for VS Code

A thin extension for working on cog-lisp in VS Code
(`specs/phase-7.5-review-and-tooling.md` §5). It adds:

- **Highlighting** for `.lisp` files in this workspace: comments (`;`, nested
  `#| |#`), strings, characters, numbers, booleans, quote marks, special forms,
  the derived forms of `lib/core.lisp` and `lib/cl.lisp`, and the names that
  definitions introduce.
- **Brackets and comments**: matching and auto-closing `()`, `""` and `#| |#`;
  *Toggle Line Comment* uses `;`.
- **Hover help and completion** for every built-in (special forms, derived forms
  and procedures): hover over a name to see its call form and what it does, and
  completion offers the names as you type. The data is `builtins.json`,
  generated from the documentation kept in the image (Phase 10 step 10.3), so it
  works with no image running and never goes out of date: a suite checks it.
- **cog-lisp: Run File** (the ▷ button in the editor title): runs the file with
  `cog-lisp.bat` (Windows) or `cog-lisp.sh` (Linux) in a task. An error (`path:line:col: error: message`) appears in
  *Problems* and is underlined in the file.
- **cog-lisp: Start REPL**: the REPL in an integrated terminal, one per window.
  Also offered as the *cog-lisp REPL* terminal profile.
- **cog-lisp: Send Selection or Form to REPL** (Ctrl+Enter): sends the selection,
  or else the top-level form at the cursor.
- **cog-lisp: Rebuild Image**: runs `build-image.bat` or `build-image.sh` (in a checkout). The extension also warns
  when `src\*.st`, `lib\compiler\*.lisp` or a library the build compiles (`lib\core.lisp`, `format.lisp`,
  `json.lisp`, `http.lisp`, `coverage.lisp`) is newer than `pharo\cog-lisp.image` and offers to rebuild
  (setting `cogLisp.warnStaleImage`).
- **cog-lisp's names in the spell checker** (`specs/vscode-spelling.md`): when
  Code Spell Checker is installed, the extension gives it a dictionary of the
  built-ins' names and the libraries' (`cspell/`, generated from the image), for
  `.lisp` files and Markdown, so `nthcdr` and `letrec` are not flagged.

- **The language server** (Phase 10 step 10.5): when the folder has a cog-lisp
  launcher (or `cogLisp.root` names one), the extension starts `lib/lsp.lisp`,
  a language server the cog-lisp image serves itself. It adds:
  - hover over the program's own top-level definitions (their documentation
    string and source), in the open file and across the workspace;
  - completion of the names the workspace defines;
  - **Go to Definition** (F12) for those names;
  - diagnostics as you type: read errors, and compile errors underlined at the
    innermost form that failed. The server reads and compiles each form but
    runs only the file's `define-syntax` and `define-macro` forms, so the file's
    own macros expand as they will when it runs;
  - **cog-lisp: Expand Macro**, which opens the expansion of the macro call at
    the cursor (the innermost one) beside the file;
  - **Format Document** (Shift+Alt+F), with `format-source`
    (`specs/formatter.md`): a form with a body over lines, each argument on its
    own line and the closing parenthesis on its own, everything else on one line;
    comments and strings untouched. `cog-lisp` files indent with tabs by default
    (`editor.insertSpaces` false for the language); your own settings win.

  The server runs on its own copy of the image, in the system's temporary
  folder, so *Run File*, the REPL and the terminal keep using the checkout's
  image beside it. A rebuilt image restarts the server on a new copy.

  Without a launcher, or with `cogLisp.languageServer` set to `false`, the
  built-ins' hover help and completion above still work. If the server stops,
  the extension says so once and goes on with them.

The extension claims `.lisp` files, so it works in any folder; disable it in a
workspace where `.lisp` means Common Lisp.
Running programs works on Windows and Linux (Phase 8.9), in a checkout or in an
unpacked release; macOS is not supported yet.

## Build, test, install

```bat
cd vscode
npm install
npm test
npm run package
code --install-extension cog-lisp.vsix
```

`npm test` runs the form-scanner checks, the hover-help checks, the package
checks (the `.vsix` holds `builtins.json`, the language client and a notice for
every npm package it ships, and claims `.lisp` files) and the grammar assertions
in `test/syntax.test.lisp` (scopes checked with `vscode-tmgrammar-test`).
`node test/lsp.test.js` talks to the language server through VS Code's own
message layer, and needs a built image. `npm run test:vscode` runs the extension
inside a real VS Code (1.90, downloaded into `.vscode-test/`): once offline, and
once with the language server, when the image is built.

The extension ships `vscode-languageclient` and its dependencies, all MIT or
ISC: `THIRD-PARTY-NOTICES.md`.

From the repository root, `build-ext.bat` (or `build-ext.sh`) packages it,
installing the npm packages first if they are missing, and `load-ext.bat` (or
`load-ext.sh`) installs it.

**Rebuild the `.vsix` before installing it** (`npm run package`): it is not kept
in git, so an old one stays in this folder until you do. A release builds its
own (`cog-lisp-VERSION.vsix`). After installing, reload the window
(*Developer: Reload Window*).
Uninstall with `code --uninstall-extension cog-lisp.cog-lisp`.

## Checking it by hand (AC-8 to AC-10)

Open the repo folder in VS Code with the extension installed and the image built.

1. **Highlighting (AC-7, visually):** open `examples\macros.lisp`; `define-macro`
   and `cond` are keywords, `while` (the name being defined) is a function name,
   strings and comments are colored.
2. **Run file (AC-8):** open `examples\hello.lisp`, press ▷ (or run *cog-lisp: Run
   File*). The terminal shows `Hello from cog-lisp!` and the task ends with exit
   code 0.
3. **REPL (AC-9):** run *cog-lisp: Start REPL*; a terminal opens at the `>`
   prompt. In `examples\factorial.lisp`, put the cursor inside the `define` of
   `fact` and press Ctrl+Enter, then type `(fact 10)` in the terminal: `3628800`.
4. **Problems (AC-10):** open `tests\runner\located.lisp` and run it. *Problems*
   lists `car: not a pair: 5` at line 4, column 3, and the line is underlined.
5. **Stale image (review T-3):** add a blank line to `lib\core.lisp` and save. A
   warning offers *Rebuild Image*; accept it and the build runs in a terminal.
   (Remove the blank line afterwards and rebuild.)
