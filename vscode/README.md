# cog-lisp for VS Code

A thin extension for working on cog-lisp in VS Code
(`specs/phase-7.5-review-and-tooling.md` §5). It adds:

- **Highlighting** for `.lisp` files in this workspace: comments (`;`, nested
  `#| |#`), strings, characters, numbers, booleans, quote marks, special forms,
  the derived forms of `lib/core.lisp` and `lib/cl.lisp`, and the names that
  definitions introduce.
- **Brackets and comments**: matching and auto-closing `()`, `""` and `#| |#`;
  *Toggle Line Comment* uses `;`.
- **cog-lisp: Run File** (the ▷ button in the editor title): runs the file with
  `cog-lisp.bat` in a task. An error (`path:line:col: error: message`) appears in
  *Problems* and is underlined in the file.
- **cog-lisp: Start REPL**: the REPL in an integrated terminal, one per window.
  Also offered as the *cog-lisp REPL* terminal profile.
- **cog-lisp: Send Selection or Form to REPL** (Ctrl+Enter): sends the selection,
  or else the top-level form at the cursor.
- **cog-lisp: Rebuild Image**: runs `build-image.bat`. The extension also warns
  when `src\*.st` or `lib\core.lisp` is newer than `pharo\cog-lisp.image` and
  offers to rebuild (setting `cogLisp.warnStaleImage`).

The language intelligence (hover with procedure source, completion from the
image's globals, diagnostics, macro expansion) is planned for a language server
that the cog-lisp image serves itself (§5.4), not for this extension.

`.lisp` is associated with cog-lisp only in this workspace
(`.vscode/settings.json`), so a Common Lisp extension elsewhere is unaffected.
Running programs needs Windows, as cog-lisp's runner does.

## Build, test, install

```bat
cd vscode
npm install
npm test
npm run package
code --install-extension cog-lisp.vsix
```

`npm test` runs the form-scanner checks and the grammar assertions in
`test/syntax.test.lisp` (scopes checked with `vscode-tmgrammar-test`).
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
