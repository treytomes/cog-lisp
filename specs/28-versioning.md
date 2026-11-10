# One version for the image and the extension

| | |
|---|---|
| **Status** | Accepted (owner, 2026-11-10) with the leanings of §8 |
| **Asked for by** | The owner (2026-11-10), after a reinstall of the VS Code extension failed: "We need to be bumping the extension version every time we bump the image version. Is there a good way to make both the image and extension reference the same version number?" Then: "Using the build timestamp as part of the version will help when debugging before a release." |
| **Relates to** | `specs/14-phase-8.9-ci-cd.md` (releases), `specs/18-library-path.md` (`*env*`'s `version`), `specs/16-phase-10-documentation-and-editor.md` (the extension and the language server) |

## 1. What went wrong (2026-11-10)

The owner rebuilt the extension (`build-ext.bat`) and installed it
(`load-ext.bat`, which runs `code --install-extension vscode\cog-lisp.vsix
--force`). The install took minutes, then failed:

```text
[node.js fs] rename failed after 1101 retries with error: Error: EPERM:
operation not permitted, rename '...\extensions\cog-lisp.cog-lisp-0.1.0' ->
'...\extensions\cog-lisp.cog-lisp-0.1.0.ffc71ea.vsctmp'
Error: Please restart VS Code before reinstalling cog-lisp.
```

Restarting VS Code and installing again failed the same way.

## 2. The lessons

- **VS Code installs an extension into a folder named for its version**
  (`cog-lisp.cog-lisp-0.1.0`). Installing the *same* version again, with
  `--force`, renames the installed folder out of the way first. While VS Code
  runs the extension, Windows refuses that rename (`EPERM`), and the CLI retries
  about 1,100 times before it gives up. That is the long wait.
- **Restarting VS Code does not free the folder:** the restarted window activates
  the extension again (here within four seconds, and it started the language
  server), before the install runs. Only a version VS Code has not installed
  goes into a folder of its own, and needs no rename.
- **The extension's version never moved.** `vscode/package.json` has said 0.1.0
  since the extension was written. Only a release stamps a real one
  (`release.yml` runs `npm version` from the tag), so every local build was
  0.1.0, and every local reinstall had to replace a folder in use.
- **The image knows its version only in a release.** The build stamps `*env*`'s
  `version` from `COGLISP_VERSION`, which only `release.yml` sets; a local image
  says `dev`. So a local image and a local extension cannot be matched, nor
  either one to the commit it came from.
- **`npm version` rewrites `package-lock.json` as well as `package.json`.**
  Stamping a version for packaging leaves both modified, unless both are put
  back.
- **`vsce` packages a pre-release version** (`0.4.1-dev.4`): checked
  2026-11-10, in `vscode/`. (A copy of `vscode/` in the temporary folder would
  not package at all, at any version, with "Extension entrypoint(s) missing"
  although the file was there; not explained, so package in place.)

## 3. The version

- **R-1. A git tag is the one source of a version.** A release's tag
  `vX.Y.Z[-suffix]` gives `X.Y.Z[-suffix]`, as today. Nothing else in the
  repository holds a version that has to be kept in step by hand.
- **R-2. A build at a release's tag, with nothing uncommitted, is that
  release's version**: `0.4.0`.
- **R-3. Any other build is a development version of the next patch**, with the
  commits since the last tag and the build's time (UTC):
  `0.4.1-dev.4.20261110153000` (four commits after `v0.4.0`, built at
  15:30:00 on 2026-11-10). It sorts after `0.4.0` and before `0.4.1`, as semver
  and VS Code order pre-releases.
- **R-4. Uncommitted changes add `dirty`**:
  `0.4.1-dev.4.20261110153000.dirty`, so a build that no commit can reproduce
  says so.
- **R-5. Without git or without tags** (a source archive, a shallow clone),
  the version is `0.0.0-dev.0.<time>`; the build says so on stderr and goes
  on.
- **R-6. `COGLISP_VERSION`, when set, wins**, so `release.yml` keeps stamping
  the tag's version, and anyone can force one.

## 4. Computing it

- **R-7. `scripts/version.sh` and `scripts/version.bat` print the version**
  (R-2 to R-6), and nothing else on stdout. They are a pair, kept in step like
  the other scripts. The `.bat` needs only git and Windows' own tools (the time
  from PowerShell's `Get-Date`, in UTC).
- **R-8. Each build computes its own version.** The image and the extension
  share everything but the time when they come from the same commit, and are
  identical at a release. Each build's own time is what makes a rebuild
  installable, and it says when that build was made.

## 5. Where the version goes

- **R-9. The image:** `build-image` sets `COGLISP_VERSION` from
  `scripts/version` when it is not set. `*env*`'s `version` and
  `(image-build-info)` (new entries `version`, `commit`, `built`) report it.
- **R-10. The extension:** `build-ext` stamps the version into `package.json`
  only while packaging, then puts `package.json` and `package-lock.json` back
  byte for byte, even when packaging fails. The committed `package.json` keeps
  a placeholder version, `0.0.0`, which no build ships.
- **R-11. The language server reports the image's version** in its
  `initialize` answer (`serverInfo.version`). The extension shows both versions
  in its output channel at start, and warns when they differ in anything but
  the build time (decision 3).
- **R-12. The agent skill** keeps being stamped by `release/package.sh`; a local
  `SKILL.md` stays unstamped, since it is committed and generated.
- **R-13. `load-ext`** prints the version it installs. If that version is
  already installed, it says so and stops, instead of waiting through VS Code's
  retries: rebuild, or uninstall and reload first.

## 6. Acceptance criteria

- **AC-1:** `scripts/version.sh` and `.bat` give the same answers, checked by a
  suite in a temporary git repository: at a tag (`0.4.0`), after it
  (`0.4.1-dev.2.<time>`), with uncommitted changes (`.dirty`), with no tags
  (`0.0.0-dev.0.<time>`), and with `COGLISP_VERSION` set. The time is 14 digits.
- **AC-2:** a local `build-image` gives an image whose `*env*` version and
  `(image-build-info)` carry the version and the commit.
- **AC-3:** a local `build-ext` gives a `.vsix` whose `package.json` holds the
  version, and leaves `vscode/package.json` and `package-lock.json` unchanged
  (`git diff --quiet`), including after a failed packaging.
- **AC-4:** two `build-ext` runs in a row give two versions, and `load-ext`
  installs the second with VS Code running the first (checked by hand, once,
  by the owner).
- **AC-5:** the language server's `initialize` answer carries the image's
  version (`vscode/test/lsp.test.js`).
- **AC-6:** a release still stamps the tag's version into the image, the
  `.vsix`, the bundles and the skill (`release/smoke-test.sh`, and a dry run of
  `release.yml`).
- **AC-7:** every suite passes on Windows and Linux.

## 7. Risks

- **CI clones shallowly**, without tags (`actions/checkout`'s default), so a CI
  build gets R-5's version. That is acceptable for CI's checks, and `release.yml`
  sets `COGLISP_VERSION`. Fetching tags in CI would give real development
  versions (decision 2).
- **A version with 14 more digits is long** in VS Code's extension list and in
  file names. Semver allows it, and it is short of node-semver's limit on a
  number (16 digits).

## 8. Decisions for the owner

1. **The time in every development build**, clean or not (R-3), so every build
   is distinct and dated; or only in builds with uncommitted changes. Leaning:
   every development build, as the owner asked.
2. **CI fetches tags** (`fetch-depth: 0`, or a fetch of tags only) so its builds
   carry real development versions; or CI keeps R-5's version. Leaning: fetch
   tags, which costs seconds.
3. **When the extension and the image differ** (other than by time), the
   extension warns once in its output channel (leaning), or shows a
   notification, or says nothing.
4. **`load-ext` and an installed same version** (R-13): stop with a message
   (leaning), or uninstall it and ask for a reload.
