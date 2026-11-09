# cog-lisp's names in VS Code's spell checker (issue #7)

| | |
|---|---|
| **Status** | Done (2026-11-09); accepted with the leanings of §4. AC-4 is the owner's, in VS Code |
| **Issue** | [#7](https://github.com/treytomes/cog-lisp/issues/7) "Include built-ins in the VS.Code dictionary? There must be a way for these terms to be recognized automatically." |
| **Relates to** | Phase 10 step 10.3 (hover help and completion from `vscode/builtins.json`) |

## 1. What is there

- **Hover help and completion already know every built-in** (step 10.3):
  `vscode/builtins.json`, generated from the image, gives 372 names.
- **The spell checker does not.** Code Spell Checker (cSpell,
  `streetsidesoftware.code-spell-checker`) flags names such as `nthcdr`,
  `zerop` and `letrec`. This repository keeps them by hand in
  `.vscode/settings.json` (`cSpell.words`), as any project using cog-lisp would
  have to.
- **Several of those names are not built-ins** but come from the libraries a
  program `require`s: `nthcdr`, `zerop`, `listp` and `numberp` are `cl`'s.
- **cSpell takes dictionaries from other extensions** (checked 2026-11-09, in
  `streetsidesoftware/vscode-cspell-dict-extensions`). A dictionary extension:
  1. finds cSpell with `vscode.extensions.getExtension('streetsidesoftware.code-spell-checker')`;
  2. activates it, which answers cSpell's API;
  3. calls the API's `registerConfig(path)` with the absolute path of a
     `cspell-ext.json`, which declares the dictionary and where it applies.

  There is no `package.json` contribution point; it is done at activation.

## 2. Requirements

- **R-1. A word list, generated.** `tools/generate-docs.lisp` writes
  `vscode/cspell/cog-lisp-words.txt`, one word a line, sorted:
  - every built-in's name, and every documented name of the libraries shipped
    in `lib/` that a program `require`s (`cl`, `test`, `datetime`, `pretty`);
  - each name split the way cSpell splits it, into its runs of letters, so a
    word that cSpell already knows (`call`, `with`, `values` in
    `call-with-values`) adds nothing. A run of one or two letters is left out.
- **R-2. A cSpell configuration**, `vscode/cspell/cspell-ext.json`, committed
  (not generated). It defines a dictionary `cog-lisp` from the word list, and
  turns it on for documents in the `cog-lisp` language and in Markdown
  (decision 1).
- **R-3. The extension registers it** when it activates, if cSpell is
  installed:
  - it never requires cSpell (no `extensionDependencies`), and a cSpell that
    is missing, inactive or failing changes nothing else the extension does;
  - it registers once per activation, and logs a failure to the extension's
    output channel without showing an error.
- **R-4. The words ship in the `.vsix`**, and the package checks
  (`vscode/test/package.test.js`) see both files there.
- **R-5. A user's own settings still win:** a word the user adds, or a
  dictionary they turn off, is cSpell's business. The extension sets no
  `cSpell.*` setting.

## 3. Acceptance criteria

- **AC-1:** the committed word list is what the image generates; a suite
  fails while it is out of date (as for `builtins.json`), and it holds
  `nthcdr`, `zerop`, `letrec`, `cdar` and `cadddr`.
- **AC-2:** a unit test runs the extension's registration against a stand-in
  for cSpell's API and sees `registerConfig` called with the path of
  `cspell-ext.json`; with no cSpell present, activation succeeds and registers
  nothing.
- **AC-3:** the package check finds both files in the `.vsix`.
- **AC-4 (by hand, recorded here):** with cSpell installed, a `.lisp` file
  using `nthcdr`, `zerop` and `letrec` shows no spelling warning for them,
  and `cSpell.words` entries for built-in names can be removed from this
  repository's settings.

## 4. Decisions for the owner

1. **Where the dictionary applies:** `cog-lisp` files and Markdown (where the
   documentation names them), or `cog-lisp` files only. Leaning: both, since
   this repository's own `cSpell.words` exists mostly for its Markdown.
2. **Which names:** the built-ins and the shipped libraries (R-1), or the
   built-ins only. Leaning: both; the names you listed by hand are `cl`'s.

## 5. As built (2026-11-09)

- **`tools/docs.lisp`** (`spelling-words`, written by `generate-docs.lisp`):
  350 words. The libraries' names are read from their files' top-level
  `define`, `define-macro` and `define-syntax` forms, not by requiring them,
  so `cl`'s `remove` never changes the built-ins' documentation in the same
  run.
- **`vscode/cspell/`**: `cspell-ext.json` (committed) and
  `cog-lisp-words.txt` (generated), both in the `.vsix`.
- **`vscode/src/spelling.js`**: `registerSpelling`, called by `activate`;
  failures go to a "cog-lisp" output channel, made only when one happens.
- **Checks:** `vscode/test/spelling.test.js` (17, in `npm test`; AC-2), the
  package check (AC-3), and a check in `tests/lisp/phase-10.2-reference.lisp`
  that the committed list is current (AC-1).
- **Checked with cSpell's own engine** (its command-line `cspell` 8, which
  reads the same `cspell-ext.json`): a `cog-lisp` file using `nthcdr`,
  `zerop`, `letrec` and `cadddr` gave four unknown words without the
  configuration, and only a real typo (`recieve`) with it.
- **Fixed on the way:** the extension's stale-image check watched only
  `lib/core.lisp` and `lib/format.lisp` of the libraries the build compiles;
  it now watches all five (`BUILT_IN_LIBRARIES`), and the spelling test fails
  if that list and the build's differ.
- **AC-4, for the owner:** install the new `.vsix` (`build-ext`,
  `load-ext`), reload, and open a `.lisp` file: `nthcdr`, `zerop` and `letrec`
  should show no spelling warning. The built-in names in this repository's
  `cSpell.words` can then go (the others, such as `objdump`, stay).
