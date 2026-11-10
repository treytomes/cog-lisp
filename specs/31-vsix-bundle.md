# The extension as one bundled file

| | |
|---|---|
| **Status** | Done (2026-11-10; §7), AC-6 for the owner. Accepted (owner, 2026-11-10) with the leanings of §8: not minified, the client a development dependency, the license texts in one generated file |
| **Asked for by** | The owner (2026-11-10), after the v0.5.0 release warned that the extension "consists of 330 files, out of which 170 are JavaScript files. For performance reasons, you should bundle your extension". Asked whether the website was being packaged into it (it is not, §1), the owner asked: "Let's write a spec for `cog-lisp` that will implement this." |
| **Relates to** | `specs/16-phase-10-documentation-and-editor.md` step 10.5 (the language client, and the notices for the npm packages it brought); `specs/28-versioning.md` (`build-ext`, the version stamped into the `.vsix`); `specs/25-vscode-spelling.md` (the package check) |

## 1. Where we start (measured 2026-11-10)

- **The warning.** `vsce package` printed it in the v0.5.0 release
  (`tests / VS Code extension`). It is advice, not an error: the extension
  installs and runs.
- **What is in the v0.5.0 `.vsix`:** 330 files, 507 KB. Nothing from `docs/` or
  the site. The extension's own files are 14:
  - its code, `src/` (4 files);
  - the grammar, `language-configuration.json`, `builtins.json`, the cSpell
    files, the manifest, the README and the notices.

  The other 316 are the language client of step 10.5, packaged as raw
  `node_modules/`:

  | Files | Package |
  |---:|---|
  | 137 | `vscode-languageclient` (with `minimatch`, `brace-expansion` and `balanced-match` nested inside it) |
  | 68 | `vscode-languageserver-protocol` |
  | 54 | `semver` |
  | 48 | `vscode-jsonrpc` |
  | 9 | `vscode-languageserver-types` |

- **Why so many:** `vscode-languageclient` is the extension's one runtime
  `dependency` (`vscode/package.json`), and vsce packages a dependency as its
  installed files. The extension loads one module of it,
  `vscode-languageclient/node`, and VS Code then loads each file it requires,
  one by one, when the extension activates.
- **The code finds its data files through VS Code**, not its own folder:
  `builtins.json` by `context.extensionPath`, the cSpell configuration by
  `context.asAbsolutePath`. So moving the code into one file does not move what
  it reads.
- **The tests:**
  - the unit tests (`npm test`) `require` the modules in `src/` directly;
  - the VS Code tests (`npm run test:vscode`) run the extension from `vscode/`
    as it stands (`extensionDevelopmentPath`), through `package.json`'s `main`.
    CI's VS Code job has no image, so there it runs only the offline pass;
  - `test/package.test.js` checks the files `vsce ls` would package, and that
    `THIRD-PARTY-NOTICES.md` lists each packaged npm package at its version.
- **Packaging** goes through vsce in two places: `npm run package` (which
  `build-ext.sh` and `.bat` run) and `npx vsce package` in `release.yml`.
  vsce runs a `vscode:prepublish` script, if `package.json` has one, before
  either.

**A spike (2026-11-10)**, on a copy of `vscode/` outside the repository:
esbuild 0.28.2,
`esbuild src/extension.js --bundle --platform=node --format=cjs --external:vscode`.
- **It builds with no warning, into one file:**

  | | Size | Gzipped |
  |---|---:|---:|
  | not minified | 815 KB | 119 KB |
  | minified | 369 KB | 88 KB |

- **Its metafile names exactly the 8 packages** `THIRD-PARTY-NOTICES.md` lists,
  and `src/` (25 KB of it).
- **The bundle loads in Node** with a stand-in for `vscode`, and exports what
  the extension does: `activate`, `deactivate` and `_test`.
- **Every bundled package has a license file** (`License.txt`, `LICENSE` or
  `LICENSE.md`). Today the `.vsix` carries each one beside its package. Once
  the packages are bundled, no folder of theirs ships, so the license texts
  must be carried some other way. MIT and ISC both require the notice to go
  with the code.

## 2. The approach

**esbuild bundles `src/extension.js` and everything it requires**, but
`vscode`, into `vscode/dist/extension.js`. VS Code's own guide recommends this
("Bundling Extensions"), and esbuild is one of the two bundlers it names.
- `package.json`'s `main` points at the bundle.
- The `.vsix` carries the bundle and the extension's data files, and no
  `node_modules/` and no `src/`.
- `src/` stays the source: the unit tests still `require` it, and the bundle is
  built from it.

**Not chosen:**
- **webpack**, the guide's other bundler. It needs a configuration file and
  more dependencies; esbuild needs one command and one package.
- **Leaving out the client** (`--no-dependencies` alone). The extension would
  then fail to load: it requires `vscode-languageclient/node` when it starts.

## 3. Requirements

- **R-1. A bundle step**, `vscode/scripts/bundle.js` (Node), run as
  `npm run bundle`. It uses esbuild's API, with:
  - `bundle`, `platform: 'node'`, `format: 'cjs'`, `target: 'node20'` (the
    Node of VS Code 1.90, the oldest the extension supports), and `external`
    `vscode`;
  - output to `dist/extension.js`, not minified (decision 1), with no source
    map;
  - a metafile, from which it learns which npm packages went into the bundle
    and at which versions.

  Then it:
  - writes `dist/THIRD-PARTY-LICENSES.txt`: for each bundled package, its name,
    version and license text, read from the package's own license file
    (R-4);
  - **fails** if a bundled package has no row at its version in
    `THIRD-PARTY-NOTICES.md`, or has no license file. The check that today
    runs only after packaging (`package.test.js`) then runs at every build.
- **R-2. esbuild is a development dependency**, pinned exactly (`"esbuild":
  "0.28.2"`, or the release current when this is built) in `package.json` and
  `package-lock.json`. The lockfile carries its platform packages, so `npm ci`
  installs the right one on Windows and Linux alike. It is a build tool, not
  shipped, so it needs no notice.
- **R-3. The `.vsix` is the bundle:**
  - `main` becomes `./dist/extension.js`;
  - a `vscode:prepublish` script runs `npm run bundle`, so every packaging
    (`npm run package`, `build-ext`, and `release.yml`'s `npx vsce package`)
    bundles first. `release.yml` and the `build-ext` twins need no change;
  - `.vscodeignore` leaves out `node_modules/**`, `src/**`, `scripts/**` and
    `dist/meta.json`;
  - `vscode-languageclient` moves from `dependencies` to `devDependencies`
    (decision 2). vsce then has no dependency to package, so nothing from
    `node_modules/` can creep back in if `.vscodeignore` changes.
- **R-4. The notices, for bundled code.** `THIRD-PARTY-NOTICES.md` says that
  the packages are bundled, unchanged, into `dist/extension.js`, and that their
  license texts are in `dist/THIRD-PARTY-LICENSES.txt` (decision 3). Its table
  stays as it is: one row per package, with version, license and source.
- **R-5. `vscode/dist/` is built, never committed** (`.gitignore`).
- **R-6. The tests run what ships.**
  - `npm run test:vscode` runs `npm run bundle` first, so a real VS Code loads
    the bundle, not `src/`. The server pass then drives the bundled client.
  - The unit tests are unchanged; they test `src/`.
- **R-7. The docs say so.** `CLAUDE.md`'s paragraph on the extension says:
  - the `.vsix` is the bundle;
  - `npm run bundle` builds it, and packaging does that by itself;
  - a new npm package in the bundle needs a row in `THIRD-PARTY-NOTICES.md`,
    or the bundle step fails.

## 4. Acceptance criteria

`test/package.test.js` (run in CI after `build-ext`) gains or changes these:

- **AC-1:** the package holds `dist/extension.js` and
  `dist/THIRD-PARTY-LICENSES.txt`, and no file under `node_modules/`, `src/`,
  `scripts/` or `test/`.
- **AC-2:** the only JavaScript file in the package is `dist/extension.js`, and
  the package holds at most 20 files (it holds 330 today).
- **AC-3:** every npm package the bundle holds (by `dist/meta.json`) has a row
  at its version in `THIRD-PARTY-NOTICES.md` and its license text in
  `dist/THIRD-PARTY-LICENSES.txt`. Planting a package the notices do not list
  makes the bundle step fail (checked once by hand, recorded in §7).
- **AC-4:** `build-ext` (both twins) and `release.yml`'s command each produce a
  `.vsix` that vsce packages with no warning about bundling.
- **AC-5:** `npm test` passes, and `npm run test:vscode` passes both passes
  locally, the server pass with a built image (CI runs the offline pass).
- **AC-6 (by hand, recorded in §7):** the `.vsix` that `build-ext` produces,
  installed with `load-ext` in VS Code, gives hover help, Run File, the REPL,
  and, with the language server, go to definition and diagnostics.

## 5. Steps

One step: R-1 to R-7, the checks, and this spec's "as built". Release it with
the next tag, whose release log should no longer show the warning.

## 6. Risks

- **A bundled client behaves differently.** It should not: esbuild changes no
  code, only how it is loaded. The VS Code tests' server pass covers it, and the
  bundle is not minified, so a stack trace still names the client's own
  functions.
- **esbuild's platform package on a runner.** `npm ci` installs the platform
  package that matches the machine, from the lockfile. The lockfile must be
  written by a recent npm, which lists every platform's package. CI's Linux and
  Windows jobs both run `npm ci`, so a lockfile missing one fails there first.
- **A dependency that reads files beside itself at run time** would break once
  bundled. None of the 8 does, and the spike's bundle loads; the VS Code tests
  would catch a new one.

## 7. As built (2026-11-10)

- **The package:** 12 files, 142 KB, against 330 files and 507 KB in v0.5.0.
  `dist/extension.js` is 796 KB, with 8 npm packages (the 8 of the notices);
  `dist/THIRD-PARTY-LICENSES.txt` is 9.5 KB.
- **vsce no longer warns about bundling.** It prints one line instead, as part of
  its list of files: "The file extension/dist/extension.js is large (795.96 KB)".
  That is the cost of decision 1; a minified bundle (369 KB) would not draw it.
- **esbuild 0.28.2**, with npm 11.12.1. The lockfile lists esbuild's 26 platform
  packages, and `npm ci` from it installs cleanly.
- **One change the spec did not foresee:** the VS Code tests' server pass reached
  the extension's state by requiring `src/extension.js`. With `main` the bundle,
  that loaded a second copy of the code, which had started no server, and two
  checks failed (the private copy of the image, and the restart on a rebuilt
  image). `test/integration/suite.js` now requires the file `main` names, the
  module VS Code loaded.
- **And one it did not mention:** a `cog-lisp.vsix.version` left in `vscode/` was
  packaged when vsce ran without `build-ext` (which deletes it first).
  `.vscodeignore` now leaves out `*.vsix.version`.
- **Checks, on Windows:**
  - `build-ext.sh` and `build-ext.bat` each package the 12 files, and put
    `package.json` back at `0.0.0`. `npx vsce package`, as `release.yml` runs
    it, bundles through `vscode:prepublish` (AC-4).
  - `npm test`: 19/19, 8/8, 15/15, 17/17, the package test 16/16, and the grammar
    (AC-1 to AC-3).
  - `npm run test:vscode`: offline 5/5; with the server, on a built image, 12/12
    (AC-5). `test/lsp.test.js`: 31/31.
  - With `semver`'s row taken out of the notices, `npm run bundle` stopped with
    "semver 7.8.6 has no row in THIRD-PARTY-NOTICES.md", exit 1, and left no
    `dist/` (AC-3).
- **AC-6, for the owner:** build with `build-ext`, install with `load-ext`,
  reload VS Code, and try hover help, Run File, the REPL, go to definition and
  diagnostics.

## 8. Decisions for the owner

1. **Minify the bundle?** Minified, it is 369 KB rather than 815 KB (88 KB
   rather than 119 KB inside the `.vsix`), but a stack trace from it is hard to
   read. Leaning: not minified. The size inside the `.vsix` differs by 31 KB,
   and readable traces matter more for a language server's client.
2. **Move `vscode-languageclient` to `devDependencies`?** It is still needed to
   build. Leaning: yes, so that vsce has nothing to package from
   `node_modules/` even if `.vscodeignore` changes (R-3).
3. **The license texts: one generated file** (`dist/THIRD-PARTY-LICENSES.txt`,
   R-1), or a copy of each package's license file under `dist/licenses/`?
   Leaning: one file. It keeps the package small, and the bundle step writes it
   from the same metafile it checks the notices against.
